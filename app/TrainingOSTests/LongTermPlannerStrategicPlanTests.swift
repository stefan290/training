import XCTest
import SwiftData
@testable import TrainingOS

/// `STRATEGIC_PLAN_MODEL.md` §4 — forward-fill and backward milestone
/// anchoring, plus `AcceptStrategicPlanUseCase`'s history-preserving
/// acceptance (`PLAN_REVISION_MODEL.md` §1/§4a).
@MainActor
final class LongTermPlannerStrategicPlanTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar.current.date(from: components)!
    }

    // MARK: - Forward-only planning (no milestone)

    func testForwardOnlyPlanFillsPrimaryTypePhasesToTargetDate() {
        let goal = Goal(ownerUserID: UUID(), primaryType: .muscleGain, targetDate: date(2027, 8, 14), createdAt: date(2026, 8, 14))

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: date(2026, 8, 14))

        XCTAssertEqual(proposal.feasibility, .feasible)
        XCTAssertFalse(proposal.phases.isEmpty)
        XCTAssertTrue(proposal.phases.allSatisfy { $0.type == .muscleGain || $0.type == .maintenance })
        XCTAssertEqual(proposal.phases.first?.type, .muscleGain)
        // Chronologically contiguous, never overlapping or gapped.
        for (a, b) in zip(proposal.phases, proposal.phases.dropFirst()) {
            XCTAssertEqual(a.endDate, b.startDate)
        }
    }

    func testNoTargetDateProducesASingleOpenEndedPhase() {
        let goal = Goal(ownerUserID: UUID(), primaryType: .functionalFitness, createdAt: date(2026, 8, 14))

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: date(2026, 8, 14))

        XCTAssertEqual(proposal.feasibility, .feasible)
        XCTAssertEqual(proposal.phases.count, 1)
        XCTAssertEqual(proposal.phases.first?.type, .functionalFitness)
        XCTAssertNil(proposal.phases.first?.endDate)
    }

    /// §44's required annual proof case: an August start, 12-month
    /// horizon, Muscle Gain primary objective, a summer milestone implying
    /// a Fat Loss phase. Deliberately does not assert exact universal
    /// month boundaries — only structure.
    func testAnnualMuscleGainWithSummerMilestoneAnchorsAFatLossPhaseBackward() throws {
        let goal = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain,
            targetDate: date(2027, 8, 14), milestoneDate: date(2027, 6, 15),
            bodyCompositionDirection: .loseFat,
            preferences: GoalPreferences(varietyPreference: .high, availableTrainingDaysPerWeek: 6),
            createdAt: date(2026, 8, 14)
        )

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: date(2026, 8, 14))

        XCTAssertEqual(proposal.feasibility, .feasible)
        XCTAssertTrue(proposal.phases.contains { $0.type == .fatLoss })
        XCTAssertTrue(proposal.phases.contains { $0.type == .muscleGain })
        let fatLossPhase = try XCTUnwrap(proposal.phases.first { $0.type == .fatLoss })
        XCTAssertEqual(fatLossPhase.endDate, date(2027, 6, 15))
        XCTAssertTrue(fatLossPhase.reasonCodes.contains(.fatLossTimedToMilestone))
        // Muscle Gain resumes after the milestone since targetDate extends beyond it.
        let lastPhase = proposal.phases.last
        XCTAssertEqual(lastPhase?.type, .muscleGain)
        XCTAssertTrue((lastPhase?.startDate ?? .distantPast) >= date(2027, 6, 15))
    }

    func testTransitionPhaseInsertedWhenMilestoneTypeDiffersFromPrimaryType() {
        let goal = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain,
            milestoneDate: date(2027, 3, 1), bodyCompositionDirection: .loseFat,
            createdAt: date(2026, 8, 14)
        )

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: date(2026, 8, 14))

        XCTAssertTrue(proposal.phases.contains { $0.type == .transition })
        let transitionIndex = proposal.phases.firstIndex { $0.type == .transition }
        let fatLossIndex = proposal.phases.firstIndex { $0.type == .fatLoss }
        XCTAssertNotNil(transitionIndex)
        XCTAssertNotNil(fatLossIndex)
        if let t = transitionIndex, let f = fatLossIndex {
            XCTAssertEqual(t + 1, f, "transition must sit immediately before the milestone phase")
        }
    }

    func testNoTransitionInsertedWhenMilestoneTypeMatchesPrimaryType() {
        let goal = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain,
            milestoneDate: date(2027, 3, 1), bodyCompositionDirection: .gainMuscle,
            createdAt: date(2026, 8, 14)
        )

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: date(2026, 8, 14))

        XCTAssertFalse(proposal.phases.contains { $0.type == .transition })
    }

    func testMaintenanceCadenceInsertsAfterTwoConsecutivePrimaryPhases() {
        // A long enough horizon (well beyond 2 muscle-gain phases at their
        // typical 12 weeks each) that the maintenance-insertion cadence
        // must fire at least once.
        let goal = Goal(ownerUserID: UUID(), primaryType: .muscleGain, targetDate: date(2028, 8, 14), createdAt: date(2026, 8, 14))

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: date(2026, 8, 14))

        XCTAssertTrue(proposal.phases.contains { $0.type == .maintenance })
        // Never 3 consecutive muscleGain phases in a row.
        var consecutive = 0
        for phase in proposal.phases {
            if phase.type == .muscleGain {
                consecutive += 1
                XCTAssertLessThanOrEqual(consecutive, 2)
            } else {
                consecutive = 0
            }
        }
    }

    func testTimeframeTooShortForMinimumPhaseDurationIsInfeasibleNeverSilentlyCompressed() {
        // Muscle Gain's minimum is 6 weeks (`PhaseDurationDefaults`) — 2
        // weeks cannot fit even one, and must never be silently squeezed.
        let goal = Goal(ownerUserID: UUID(), primaryType: .muscleGain, targetDate: date(2026, 8, 28), createdAt: date(2026, 8, 14))

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: date(2026, 8, 14))

        XCTAssertEqual(proposal.feasibility, .infeasible)
        XCTAssertTrue(proposal.phases.isEmpty)
    }

    func testNotEnoughLeadTimeBeforeMilestoneIsInfeasible() {
        let goal = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain,
            milestoneDate: date(2026, 8, 20), bodyCompositionDirection: .loseFat,
            createdAt: date(2026, 8, 14)
        )

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: date(2026, 8, 14))

        XCTAssertEqual(proposal.feasibility, .infeasible)
    }

    // MARK: - Determinism (§37)

    func testProposalIsDeterministicAcrossRepeatedCalls() {
        let goal = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain,
            targetDate: date(2027, 8, 14), milestoneDate: date(2027, 6, 15),
            bodyCompositionDirection: .loseFat, createdAt: date(2026, 8, 14)
        )

        let first = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: date(2026, 8, 14))
        let second = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: date(2026, 8, 14))

        XCTAssertEqual(first.phases.map(\.type), second.phases.map(\.type))
        XCTAssertEqual(first.phases.map(\.startDate), second.phases.map(\.startDate))
        XCTAssertEqual(first.phases.map(\.endDate), second.phases.map(\.endDate))
    }

    // MARK: - AcceptStrategicPlanUseCase

    func testAcceptingAnInfeasibleProposalThrows() {
        let goal = Goal(ownerUserID: UUID(), primaryType: .muscleGain, createdAt: date(2026, 8, 14))
        context.insert(goal)
        let proposal = StrategicPlanProposal(goal: goal, phases: [], feasibility: .infeasible, explanation: "too short")

        XCTAssertThrowsError(try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: date(2026, 8, 14))) { error in
            XCTAssertEqual(error as? StrategicPlanAcceptanceError, .infeasible)
        }
    }

    func testAcceptingAFeasibleProposalPersistsPlanPhasesAndOneDecision() throws {
        let goal = Goal(ownerUserID: UUID(), primaryType: .muscleGain, targetDate: date(2027, 8, 14), createdAt: date(2026, 8, 14))
        context.insert(goal)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: date(2026, 8, 14))

        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: date(2026, 8, 14))
        try context.save()

        XCTAssertEqual(plan.status, .active)
        XCTAssertEqual(plan.orderedPhases.count, proposal.phases.count)
        XCTAssertTrue(plan.orderedPhases.allSatisfy { $0.status == .planned })

        let decisions = try context.fetch(FetchDescriptor<PlannerDecision>())
        XCTAssertEqual(decisions.count, 1)
        XCTAssertEqual(decisions.first?.planRevision?.id, plan.id)
    }

    /// `PLAN_REVISION_MODEL.md` §4a's central invariant: a completed
    /// phase must never be mutated by a later acceptance, and a
    /// superseded plan's own still-`.planned` phases become `.abandoned`,
    /// never deleted.
    func testSupersedingAPlanNeverMutatesCompletedHistoryAndAbandonsPlannedPhases() throws {
        let goal = Goal(ownerUserID: UUID(), primaryType: .muscleGain, createdAt: date(2026, 1, 1))
        context.insert(goal)

        let oldPlan = TrainingPlan(status: .active, createdAt: date(2026, 1, 1))
        context.insert(oldPlan)
        goal.addPlan(oldPlan)

        let completedPhase = TrainingPhase(type: .muscleGain, startDate: date(2026, 1, 1), endDate: date(2026, 4, 1), priorityRule: .strength, status: .completed)
        context.insert(completedPhase)
        oldPlan.addPhase(completedPhase)

        let plannedPhase = TrainingPhase(type: .fatLoss, startDate: date(2026, 4, 1), endDate: date(2026, 6, 1), priorityRule: .strength, status: .planned)
        context.insert(plannedPhase)
        oldPlan.addPhase(plannedPhase)

        let newProposal = StrategicPlanProposal(
            goal: goal,
            phases: [ProposedPhase(
                type: .muscleGain, priorityRule: .strength, startDate: date(2026, 8, 14), endDate: date(2027, 2, 14),
                durationKind: .range(typical: 12, minimum: 6, maximum: 20), reasonCodes: [.phaseSelectedForGoal]
            )],
            feasibility: .feasible, explanation: "revised"
        )

        _ = try AcceptStrategicPlanUseCase.accept(
            newProposal, context: context, decidedAt: date(2026, 8, 14),
            supersedes: oldPlan, lineageID: oldPlan.lineageID
        )
        try context.save()

        XCTAssertEqual(completedPhase.status, .completed, "completed history must never be mutated")
        XCTAssertEqual(completedPhase.startDate, date(2026, 1, 1))
        XCTAssertEqual(completedPhase.endDate, date(2026, 4, 1))
        XCTAssertEqual(plannedPhase.status, .abandoned, "a superseded plan's own planned phases become abandoned, never deleted")
        XCTAssertEqual(oldPlan.status, .superseded)
    }

    func testRevisionAcceptanceSharesLineageIDWithSupersededPlan() throws {
        let goal = Goal(ownerUserID: UUID(), primaryType: .muscleGain, createdAt: date(2026, 1, 1))
        context.insert(goal)
        let oldPlan = TrainingPlan(status: .active, createdAt: date(2026, 1, 1))
        context.insert(oldPlan)
        goal.addPlan(oldPlan)

        let proposal = StrategicPlanProposal(
            goal: goal,
            phases: [ProposedPhase(
                type: .muscleGain, priorityRule: .strength, startDate: date(2026, 8, 14), endDate: date(2027, 2, 14),
                durationKind: .range(typical: 12, minimum: 6, maximum: 20), reasonCodes: [.phaseSelectedForGoal]
            )],
            feasibility: .feasible, explanation: "revised"
        )

        let newPlan = try AcceptStrategicPlanUseCase.accept(
            proposal, context: context, decidedAt: date(2026, 8, 14), supersedes: oldPlan, lineageID: oldPlan.lineageID
        )

        XCTAssertEqual(newPlan.lineageID, oldPlan.lineageID)
        XCTAssertEqual(newPlan.supersedes?.id, oldPlan.id)
    }
}
