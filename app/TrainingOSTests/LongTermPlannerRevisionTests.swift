import XCTest
import SwiftData
@testable import TrainingOS

/// `PLAN_REVISION_MODEL.md` §4b/§4c — `reviseStrategicPlan` +
/// `AcceptStrategicPlanUseCase`'s revision-lineage behavior end-to-end.
@MainActor
final class LongTermPlannerRevisionTests: XCTestCase {
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

    /// Builds a real, accepted `TrainingPlan` with one `.completed` phase
    /// and two `.planned` future phases — the fixture every revision test
    /// in this file resizes/replans against.
    private func makeAcceptedPlan(goal: Goal) throws -> TrainingPlan {
        context.insert(goal)
        let plan = TrainingPlan(status: .active, createdAt: date(2026, 1, 1))
        context.insert(plan)
        goal.addPlan(plan)

        let completed = TrainingPhase(type: .muscleGain, startDate: date(2026, 1, 1), endDate: date(2026, 4, 1), priorityRule: .strength, status: .completed)
        context.insert(completed)
        plan.addPhase(completed)

        let plannedA = TrainingPhase(type: .muscleGain, startDate: date(2026, 4, 1), endDate: date(2026, 7, 1), priorityRule: .strength, status: .planned)
        context.insert(plannedA)
        plan.addPhase(plannedA)

        let plannedB = TrainingPhase(type: .maintenance, startDate: date(2026, 7, 1), endDate: date(2026, 8, 1), priorityRule: .mixedModal, status: .planned)
        context.insert(plannedB)
        plan.addPhase(plannedB)

        try context.save()
        return plan
    }

    // MARK: - Extend / shorten

    func testExtendPhaseShiftsTheNextPlannedPhaseAndEverythingAfterIt() throws {
        let goal = Goal(ownerUserID: UUID(), primaryType: .muscleGain, createdAt: date(2026, 1, 1))
        let plan = try makeAcceptedPlan(goal: goal)

        let proposal = LongTermPlanner.reviseStrategicPlan(current: plan, revision: .extendPhase(weeks: 2), asOf: date(2026, 6, 1))

        XCTAssertEqual(proposal.feasibility, .feasible)
        XCTAssertEqual(proposal.phases.count, 2)
        XCTAssertEqual(proposal.phases[0].endDate, date(2026, 7, 15))
        XCTAssertTrue(proposal.phases[0].reasonCodes.contains(.phaseExtended))
        XCTAssertEqual(proposal.phases[1].startDate, date(2026, 7, 15))
        XCTAssertEqual(proposal.phases[1].endDate, date(2026, 8, 15))
    }

    func testShortenPhasePullsTheNextPlannedPhaseAndEverythingAfterItIn() throws {
        let goal = Goal(ownerUserID: UUID(), primaryType: .muscleGain, createdAt: date(2026, 1, 1))
        let plan = try makeAcceptedPlan(goal: goal)

        let proposal = LongTermPlanner.reviseStrategicPlan(current: plan, revision: .shortenPhase(weeks: 2), asOf: date(2026, 6, 1))

        XCTAssertEqual(proposal.feasibility, .feasible)
        XCTAssertEqual(proposal.phases[0].endDate, date(2026, 6, 17))
        XCTAssertTrue(proposal.phases[0].reasonCodes.contains(.phaseShortened))
    }

    func testExtendingPastAnExistingMilestoneIsInfeasible() throws {
        let goal = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain,
            milestoneDate: date(2026, 7, 10), bodyCompositionDirection: .gainMuscle,
            createdAt: date(2026, 1, 1)
        )
        let plan = try makeAcceptedPlan(goal: goal)

        let proposal = LongTermPlanner.reviseStrategicPlan(current: plan, revision: .extendPhase(weeks: 2), asOf: date(2026, 6, 1))

        XCTAssertEqual(proposal.feasibility, .infeasible)
    }

    func testShorteningToZeroOrNegativeDurationIsInfeasible() throws {
        let goal = Goal(ownerUserID: UUID(), primaryType: .muscleGain, createdAt: date(2026, 1, 1))
        let plan = try makeAcceptedPlan(goal: goal)

        // plannedA spans exactly 13 weeks (Apr 1 -> Jul 1) — shortening by 20 weeks must fail cleanly, never invert the phase.
        let proposal = LongTermPlanner.reviseStrategicPlan(current: plan, revision: .shortenPhase(weeks: 20), asOf: date(2026, 6, 1))

        XCTAssertEqual(proposal.feasibility, .infeasible)
    }

    // MARK: - Milestone date change

    func testChangingMilestoneDateReplansOnlyTheRemainingFuture() throws {
        let goal = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain,
            milestoneDate: date(2026, 12, 1), bodyCompositionDirection: .loseFat,
            createdAt: date(2026, 1, 1)
        )
        let plan = try makeAcceptedPlan(goal: goal)

        let proposal = LongTermPlanner.reviseStrategicPlan(
            current: plan, revision: .changeMilestoneDate(date(2027, 3, 1)), asOf: date(2026, 6, 1)
        )

        XCTAssertEqual(proposal.feasibility, .feasible)
        XCTAssertTrue(proposal.phases.contains { $0.type == .fatLoss })
        let fatLossPhase = try XCTUnwrap(proposal.phases.first { $0.type == .fatLoss })
        XCTAssertEqual(fatLossPhase.endDate, date(2027, 3, 1))
        // Never includes the already-.completed phase from the old revision.
        XCTAssertFalse(proposal.phases.contains { $0.startDate == date(2026, 1, 1) })
    }

    // MARK: - Major revision: long-term goal change

    func testChangingLongTermGoalProducesANewLineageOnAcceptance() throws {
        let oldGoal = Goal(ownerUserID: UUID(), primaryType: .muscleGain, createdAt: date(2026, 1, 1))
        let plan = try makeAcceptedPlan(goal: oldGoal)
        let oldLineageID = plan.lineageID

        let newGoal = Goal(ownerUserID: UUID(), primaryType: .enduranceEvent, targetDate: date(2027, 1, 1), createdAt: date(2026, 6, 1))
        context.insert(newGoal)

        let proposal = LongTermPlanner.reviseStrategicPlan(current: plan, revision: .changeLongTermGoal(newGoal), asOf: date(2026, 6, 1))
        XCTAssertEqual(proposal.feasibility, .feasible)
        XCTAssertTrue(proposal.phases.allSatisfy { $0.type == .enduranceEvent || $0.type == .maintenance })
        XCTAssertEqual(proposal.phases.first?.type, .enduranceEvent)

        let newPlan = try AcceptStrategicPlanUseCase.accept(
            proposal, context: context, decidedAt: date(2026, 6, 1),
            supersedes: plan, lineageID: nil,
            decisionType: .roadmapRevised, decisionReasonCode: .longTermGoalChanged, decisionSource: .userOverride
        )
        try context.save()

        XCTAssertNotEqual(newPlan.lineageID, oldLineageID, "a long-term goal change is a new strategic intent, never a refinement of the old lineage")
        XCTAssertEqual(newPlan.supersedes?.id, plan.id, "still traceable back to what it replaced")
    }

    // MARK: - History preservation across a full revise-and-accept cycle

    func testFullRevisionCycleNeverMutatesTheCompletedPhaseOrPerformanceHistory() throws {
        let goal = Goal(ownerUserID: UUID(), primaryType: .muscleGain, createdAt: date(2026, 1, 1))
        let plan = try makeAcceptedPlan(goal: goal)
        let completedPhase = try XCTUnwrap(plan.orderedPhases.first { $0.status == .completed })
        let originalStart = completedPhase.startDate
        let originalEnd = completedPhase.endDate

        let profile = PerformanceProfile()
        context.insert(profile)
        let exercise = Exercise(canonicalName: "Barbell Back Squat", modality: .hypertrophy, equipment: "barbell", movementPattern: "squat")
        context.insert(exercise)
        let exerciseProfile = ExercisePerformanceProfile(estimatedOneRepMax: 120, confidence: 0.8)
        exerciseProfile.exercise = exercise
        context.insert(exerciseProfile)
        profile.addExerciseProfile(exerciseProfile)
        try context.save()

        let proposal = LongTermPlanner.reviseStrategicPlan(current: plan, revision: .extendPhase(weeks: 2), asOf: date(2026, 6, 1))
        _ = try AcceptStrategicPlanUseCase.accept(
            proposal, context: context, decidedAt: date(2026, 6, 1),
            supersedes: plan, lineageID: plan.lineageID,
            decisionType: .phaseExtendedOrShortened, decisionReasonCode: .phaseExtended
        )
        try context.save()

        XCTAssertEqual(completedPhase.status, .completed)
        XCTAssertEqual(completedPhase.startDate, originalStart)
        XCTAssertEqual(completedPhase.endDate, originalEnd)
        XCTAssertEqual(profile.exerciseProfiles.count, 1)
        XCTAssertEqual(profile.exerciseProfiles.first?.confidence, 0.8)
    }

    // MARK: - Determinism (§37)

    func testRevisionProposalIsDeterministicAcrossRepeatedCalls() throws {
        let goal = Goal(ownerUserID: UUID(), primaryType: .muscleGain, createdAt: date(2026, 1, 1))
        let plan = try makeAcceptedPlan(goal: goal)

        let first = LongTermPlanner.reviseStrategicPlan(current: plan, revision: .extendPhase(weeks: 3), asOf: date(2026, 6, 1))
        let second = LongTermPlanner.reviseStrategicPlan(current: plan, revision: .extendPhase(weeks: 3), asOf: date(2026, 6, 1))

        XCTAssertEqual(first.phases.map(\.startDate), second.phases.map(\.startDate))
        XCTAssertEqual(first.phases.map(\.endDate), second.phases.map(\.endDate))
    }
}
