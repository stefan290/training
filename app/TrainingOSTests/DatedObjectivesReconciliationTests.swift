import XCTest
import SwiftData
@testable import TrainingOS

/// Dated Objectives + 10K Strategic Reconciliation V1 — the locked
/// "OVERLAP != CONFLICT" reconciliation algorithm
/// (`LongTermPlanner.proposeReconciledPhases`), the 16/12/8-week lead-time
/// policy (`RunningStartingState.leadTimeWeeks`), forced Running activity
/// semantics for a 10K-driven `.enduranceEvent` phase, and the legacy
/// `Goal.milestoneDate` projection rule.
@MainActor
final class DatedObjectivesReconciliationTests: XCTestCase {
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

    // MARK: - 1. Existing behavior preserved (legacy milestone, no dated objectives)

    func testExistingBehaviorPreservedForSummerShapeOnlyGoal() {
        // A legacy Goal exactly like `LongTermPlannerStrategicPlanTests
        // .testAnnualMuscleGainWithSummerMilestoneAnchorsAFatLossPhaseBackward`
        // — `datedObjectives` empty, `milestoneDate` set — must still route
        // through the untouched `proposeMilestoneAnchoredPhases` path.
        let goal = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain,
            targetDate: date(2027, 8, 14), milestoneDate: date(2027, 6, 15),
            bodyCompositionDirection: .loseFat, createdAt: date(2026, 8, 14)
        )
        XCTAssertTrue(goal.datedObjectives.isEmpty, "sanity check: legacy fixture carries no dated objectives")

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: date(2026, 8, 14))

        XCTAssertEqual(proposal.feasibility, .feasible)
        let fatLossPhase = proposal.phases.first { $0.type == .fatLoss }
        XCTAssertEqual(fatLossPhase?.endDate, date(2027, 6, 15))
        XCTAssertEqual(proposal.phases.last?.type, .muscleGain, "muscle gain resumes after the milestone")
    }

    // MARK: - 2. Existing behavior preserved (10K-only, no legacy milestone)

    func testExistingBehaviorPreservedForTenKOnlyGoal() {
        let raceDate = date(2027, 9, 20)
        let goal = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain,
            datedObjectives: [DatedObjective(kind: .runningEvent, date: raceDate, runningStartingState: .notCurrentlyRunning)],
            createdAt: date(2026, 8, 14)
        )

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: date(2026, 8, 14))

        XCTAssertEqual(proposal.feasibility, .feasible)
        let racePhase = proposal.phases.first { $0.type == .enduranceEvent }
        XCTAssertEqual(racePhase?.endDate, raceDate)
        // 16-week tier, uncompressed (plenty of lead time from Aug 2026).
        XCTAssertFalse(racePhase?.reasonCodes.contains(.objectivePrepCompressed) ?? true)
        XCTAssertEqual(proposal.phases.first?.type, .muscleGain, "primary goal fills the lead time")
    }

    // MARK: - 3. Canonical production case

    func testCanonicalMuscleGainSummerShapeThenTenKCoordinatesOneCoherentPlan() throws {
        let asOf = date(2026, 9, 3)
        let summerShape = date(2027, 6, 15)
        let tenK = date(2027, 9, 20)
        let goal = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain,
            datedObjectives: [
                DatedObjective(kind: .bodyCompositionMilestone, date: summerShape, bodyCompositionDirection: .loseFat),
                DatedObjective(kind: .runningEvent, date: tenK, runningStartingState: .notCurrentlyRunning),
            ],
            createdAt: asOf
        )

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)

        XCTAssertEqual(proposal.feasibility, .feasible)
        // Muscle Gain dominates initially.
        XCTAssertEqual(proposal.phases.first?.type, .muscleGain)
        // Summer Shape's own Fat Loss phase still ends exactly on its date.
        let fatLossPhase = try XCTUnwrap(proposal.phases.first { $0.type == .fatLoss })
        XCTAssertEqual(fatLossPhase.endDate, summerShape)
        XCTAssertTrue(fatLossPhase.reasonCodes.contains(.fatLossTimedToMilestone))
        // The 10K's own Endurance Event phase ends exactly on race day.
        let racePhase = try XCTUnwrap(proposal.phases.first { $0.type == .enduranceEvent })
        XCTAssertEqual(racePhase.endDate, tenK)
        // Overlap reconciled via sequencing, not fabrication: the race
        // phase never starts before the Fat Loss phase's own end.
        XCTAssertGreaterThanOrEqual(racePhase.startDate, fatLossPhase.endDate ?? .distantFuture)
        // Genuinely compressed below the 16-week ideal because Summer
        // Shape's own phase ran right up against it.
        XCTAssertTrue(racePhase.reasonCodes.contains(.objectivePrepCompressed))
        // Endurance specificity increases toward September, but Muscle Gain
        // resumes afterward — never abandoned.
        XCTAssertEqual(proposal.phases.last?.type, .muscleGain)
        XCTAssertGreaterThanOrEqual(proposal.phases.last?.startDate ?? .distantPast, tenK)
        // Primary goal itself is never mutated by any of this.
        XCTAssertEqual(goal.primaryType, .muscleGain)
        // Phases remain strictly sequential — no fabricated blended phase.
        for (a, b) in zip(proposal.phases, proposal.phases.dropFirst()) {
            XCTAssertEqual(a.endDate, b.startDate)
        }
    }

    // MARK: - 4. Overlap reconciliation: overlap != conflict

    func testCloseOverlapReconcilesWithoutConflict() throws {
        let asOf = date(2026, 9, 3)
        let summerShape = date(2027, 6, 15)
        let tenK = date(2027, 6, 28) // 13 days after Summer Shape
        let goal = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain,
            datedObjectives: [
                DatedObjective(kind: .bodyCompositionMilestone, date: summerShape, bodyCompositionDirection: .loseFat),
                DatedObjective(kind: .runningEvent, date: tenK, runningStartingState: .notCurrentlyRunning),
            ],
            createdAt: asOf
        )

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)

        XCTAssertEqual(proposal.feasibility, .feasible, "overlap alone must never produce a conflict")
        let racePhase = try XCTUnwrap(proposal.phases.first { $0.type == .enduranceEvent })
        XCTAssertEqual(racePhase.startDate, summerShape, "compressed all the way back to the moment Summer Shape's own phase ends")
        XCTAssertEqual(racePhase.endDate, tenK)
        XCTAssertTrue(racePhase.reasonCodes.contains(.objectivePrepCompressed))
        XCTAssertEqual(goal.primaryType, .muscleGain)
        // Only real, already-supported mixes are ever selected for either phase.
        let fatLossCandidates = LongTermPlanner.proposeTrainingMix(
            phase: TrainingPhase(type: .fatLoss, startDate: asOf, endDate: summerShape, priorityRule: .strength), goal: goal
        )
        XCTAssertTrue(fatLossCandidates.allSatisfy { ["Conditioning-Focused Fat Loss", "Functional Fat Loss"].contains($0.mix.name) })
    }

    // MARK: - 5. Unrepresentable overlap: genuine conflict

    func testSameDateDifferentPhaseTypesProducesExplicitConflict() {
        let sameDay = date(2027, 6, 15)
        let goal = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain,
            datedObjectives: [
                DatedObjective(kind: .bodyCompositionMilestone, date: sameDay, bodyCompositionDirection: .loseFat),
                DatedObjective(kind: .runningEvent, date: sameDay, runningStartingState: .notCurrentlyRunning),
            ],
            createdAt: date(2026, 9, 3)
        )

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: date(2026, 9, 3))

        XCTAssertEqual(proposal.feasibility, .objectivesConflict)
        XCTAssertTrue(proposal.phases.isEmpty)
        XCTAssertFalse(proposal.explanation.isEmpty)
    }

    func testAcceptingAnObjectivesConflictProposalThrowsAndPersistsNothing() throws {
        let goal = Goal(ownerUserID: UUID(), primaryType: .muscleGain, createdAt: date(2026, 9, 3))
        context.insert(goal)
        let proposal = StrategicPlanProposal(goal: goal, phases: [], feasibility: .objectivesConflict, explanation: "conflict")

        XCTAssertThrowsError(try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: date(2026, 9, 3))) { error in
            XCTAssertEqual(error as? StrategicPlanAcceptanceError, .objectivesConflict)
        }
        XCTAssertTrue(goal.plans.isEmpty)
    }

    // MARK: - 6. Too-soon 10K: best-effort, never blocked

    func testVeryCloseTenKStillProducesABestEffortFeasiblePlan() throws {
        let asOf = date(2027, 1, 1)
        let raceDate = date(2027, 1, 22) // 3 weeks out — far short of any tier
        let goal = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain,
            datedObjectives: [DatedObjective(kind: .runningEvent, date: raceDate, runningStartingState: .notCurrentlyRunning)],
            createdAt: asOf
        )

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)

        XCTAssertEqual(proposal.feasibility, .feasible, "an event being soon must never block plan creation")
        let racePhase = try XCTUnwrap(proposal.phases.first { $0.type == .enduranceEvent })
        XCTAssertEqual(racePhase.startDate, asOf)
        XCTAssertEqual(racePhase.endDate, raceDate)
        XCTAssertTrue(racePhase.reasonCodes.contains(.objectivePrepCompressed), "the truthful caveat signal must be present")
    }

    // MARK: - 7. Post-event return to primary goal

    func testPostEventReturnUsesTwelveWeekDefaultAndNeverMutatesTargetDate() {
        let asOf = date(2026, 9, 3)
        let raceDate = date(2027, 1, 1)
        let goal = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain,
            datedObjectives: [DatedObjective(kind: .runningEvent, date: raceDate, runningStartingState: .notCurrentlyRunning)],
            createdAt: asOf
        )
        XCTAssertNil(goal.targetDate)

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)

        XCTAssertEqual(proposal.phases.last?.type, .muscleGain)
        let lastEnd = proposal.phases.last?.endDate
        XCTAssertNotNil(lastEnd)
        let expectedDefault = Calendar.current.date(byAdding: .weekOfYear, value: 12, to: raceDate)!
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: lastEnd!, to: expectedDefault).day, 0)
        XCTAssertNil(goal.targetDate, "the planner-owned default must never be written back onto the real Goal")
    }

    // MARK: - 8. Edit/cancel-objective revision preserves history

    func testCancellingADatedObjectiveRevisesFutureWithoutRewritingCompletedHistory() throws {
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

        let objectiveID = UUID()
        goal.datedObjectives = [DatedObjective(id: objectiveID, kind: .runningEvent, date: date(2027, 9, 20), runningStartingState: .notCurrentlyRunning)]

        // The athlete cancels the objective — a new forward roadmap only.
        goal.datedObjectives[0].status = .cancelled
        let revision = LongTermPlanner.reviseStrategicPlan(current: oldPlan, revision: .changeLongTermGoal(goal), asOf: date(2026, 4, 1))

        XCTAssertEqual(revision.feasibility, .feasible)
        XCTAssertFalse(revision.phases.contains { $0.type == .enduranceEvent }, "a cancelled objective must not appear in the new roadmap")
        XCTAssertEqual(completedPhase.status, .completed, "completed history must never be rewritten")
        XCTAssertEqual(completedPhase.startDate, date(2026, 1, 1))
        XCTAssertEqual(completedPhase.endDate, date(2026, 4, 1))
    }

    // MARK: - 9. Stable multi-objective ordering

    func testObjectivesAreProcessedInDateOrderRegardlessOfArrayOrder() {
        let asOf = date(2026, 9, 3)
        let earlier = date(2027, 6, 15)
        let later = date(2027, 9, 20)
        let goalOutOfOrder = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain,
            datedObjectives: [
                DatedObjective(kind: .runningEvent, date: later, runningStartingState: .notCurrentlyRunning),
                DatedObjective(kind: .bodyCompositionMilestone, date: earlier, bodyCompositionDirection: .loseFat),
            ],
            createdAt: asOf
        )
        let goalInOrder = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain,
            datedObjectives: [
                DatedObjective(kind: .bodyCompositionMilestone, date: earlier, bodyCompositionDirection: .loseFat),
                DatedObjective(kind: .runningEvent, date: later, runningStartingState: .notCurrentlyRunning),
            ],
            createdAt: asOf
        )

        let a = LongTermPlanner.proposeStrategicPlan(goal: goalOutOfOrder, asOf: asOf)
        let b = LongTermPlanner.proposeStrategicPlan(goal: goalInOrder, asOf: asOf)

        XCTAssertEqual(a.phases.map { $0.type }, b.phases.map { $0.type })
        XCTAssertEqual(a.phases.map { $0.startDate }, b.phases.map { $0.startDate })
        XCTAssertEqual(a.phases.map { $0.endDate }, b.phases.map { $0.endDate })
    }

    // MARK: - 10. No-objectives regression

    func testEmptyDatedObjectivesAndNoMilestoneBehavesExactlyLikeForwardOnly() {
        let goal = Goal(ownerUserID: UUID(), primaryType: .muscleGain, targetDate: date(2027, 8, 14), createdAt: date(2026, 8, 14))
        XCTAssertTrue(goal.datedObjectives.isEmpty)

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: date(2026, 8, 14))

        XCTAssertEqual(proposal.feasibility, .feasible)
        XCTAssertTrue(proposal.phases.allSatisfy { $0.type == .muscleGain || $0.type == .maintenance })
    }

    // MARK: - 11. 16/12/8-week lead-time tiers

    func testRunningStartingStateLeadTimeWeeksAreLocked() {
        XCTAssertEqual(RunningStartingState.notCurrentlyRunning.leadTimeWeeks, 16)
        XCTAssertEqual(RunningStartingState.occasionalShorterDistances.leadTimeWeeks, 12)
        XCTAssertEqual(RunningStartingState.comfortably10K.leadTimeWeeks, 8)
    }

    func testEachRunningStartingStateTierProducesItsOwnUncompressedLeadTime() {
        let tiers: [(RunningStartingState, Int)] = [
            (.notCurrentlyRunning, 16),
            (.occasionalShorterDistances, 12),
            (.comfortably10K, 8),
        ]
        for (state, expectedWeeks) in tiers {
            let raceDate = date(2028, 1, 1)
            let asOf = date(2026, 1, 1) // ample lead time — never compressed
            let goal = Goal(
                ownerUserID: UUID(), primaryType: .muscleGain,
                datedObjectives: [DatedObjective(kind: .runningEvent, date: raceDate, runningStartingState: state)],
                createdAt: asOf
            )
            let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
            let racePhase = proposal.phases.first { $0.type == .enduranceEvent }
            XCTAssertNotNil(racePhase, "tier \(state)")
            XCTAssertFalse(racePhase?.reasonCodes.contains(.objectivePrepCompressed) ?? true, "tier \(state) must be uncompressed given ample lead time")
            let actualWeeks = Calendar.current.dateComponents([.day], from: racePhase!.startDate, to: raceDate).day! / 7
            XCTAssertEqual(actualWeeks, expectedWeeks, "tier \(state)")
        }
    }

    // MARK: - 12. Goal.targetDate semantics unchanged

    func testExplicitTargetDateStillTakesPrecedenceInTheMultiObjectivePath() {
        let asOf = date(2026, 9, 3)
        let raceDate = date(2027, 1, 1)
        let explicitTargetDate = date(2027, 1, 15) // far short of the 12-week default
        let goal = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain, targetDate: explicitTargetDate,
            datedObjectives: [DatedObjective(kind: .runningEvent, date: raceDate, runningStartingState: .notCurrentlyRunning)],
            createdAt: asOf
        )

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)

        if let lastEnd = proposal.phases.last?.endDate {
            XCTAssertLessThanOrEqual(lastEnd, explicitTargetDate)
        }
        XCTAssertEqual(goal.targetDate, explicitTargetDate, "never mutated by planning")
    }

    // MARK: - 13. No-double / capacity contract preserved

    func testCapacityApportionmentStillAppliesToATenKDrivenEndurancePhase() {
        let goal = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain,
            preferences: GoalPreferences(availableTrainingDaysPerWeek: 3),
            datedObjectives: [DatedObjective(kind: .runningEvent, date: date(2027, 9, 20), runningStartingState: .notCurrentlyRunning)],
            createdAt: date(2026, 9, 3)
        )
        let phase = TrainingPhase(type: .enduranceEvent, startDate: date(2027, 6, 1), endDate: date(2027, 9, 20), priorityRule: .endurance)

        let candidates = LongTermPlanner.proposeTrainingMix(phase: phase, goal: goal)

        XCTAssertFalse(candidates.isEmpty)
        for candidate in candidates {
            let totalSessions = candidate.mix.orderedComponents.reduce(0) { $0 + $1.frequency.target }
            XCTAssertLessThanOrEqual(totalSessions, 3, "capacity apportionment must still cap total weekly sessions at the stated availability")
        }
    }

    // MARK: - 15/16. Forced Running activity label for a 10K, existing endurance-primary preference preserved

    func testTenKDrivenEnduranceEventPhaseForcesRunningRegardlessOfStatedPreference() {
        let goal = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain,
            preferences: GoalPreferences(preferredModalities: [ModalityPreference(system: .steadyState, activityType: .cycling)]),
            datedObjectives: [DatedObjective(kind: .runningEvent, date: date(2027, 9, 20), runningStartingState: .notCurrentlyRunning)],
            createdAt: date(2026, 9, 3)
        )
        let phase = TrainingPhase(type: .enduranceEvent, startDate: date(2027, 6, 1), endDate: date(2027, 9, 20), priorityRule: .endurance)

        let candidates = LongTermPlanner.proposeTrainingMix(phase: phase, goal: goal)

        XCTAssertTrue(candidates.allSatisfy { $0.mix.name.contains("Running") })
        XCTAssertFalse(candidates.contains { $0.mix.name.contains("Cycling") })
    }

    func testPrimaryEnduranceGoalStillHonorsStatedActivityPreference() {
        // Regression guard: when `.enduranceEvent` IS the primary goal's own
        // phase type (no 10K dated objective involved at all), the existing
        // preference-driven activity label must be completely unaffected.
        let goal = Goal(
            ownerUserID: UUID(), primaryType: .enduranceEvent,
            preferences: GoalPreferences(preferredModalities: [ModalityPreference(system: .steadyState, activityType: .cycling)]),
            createdAt: date(2026, 9, 3)
        )
        let phase = TrainingPhase(type: .enduranceEvent, startDate: date(2026, 9, 3), endDate: date(2027, 1, 1), priorityRule: .endurance)

        let candidates = LongTermPlanner.proposeTrainingMix(phase: phase, goal: goal)

        XCTAssertTrue(candidates.allSatisfy { $0.mix.name.contains("Cycling") })
    }

    // MARK: - 17. Real mixes only, zero fabrication

    func testReconciledPathOnlySelectsAlreadyRealMixNames() {
        let knownRealNames: Set<String> = [
            "Focused Hypertrophy", "Strength Plus Variety", // muscleGain
            "Conditioning-Focused Fat Loss", "Functional Fat Loss", // fatLoss
            "Running Performance", "Running Plus Interval Variety", // enduranceEvent (forced label)
        ]
        let asOf = date(2026, 9, 3)
        let goal = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain,
            datedObjectives: [
                DatedObjective(kind: .bodyCompositionMilestone, date: date(2027, 6, 15), bodyCompositionDirection: .loseFat),
                DatedObjective(kind: .runningEvent, date: date(2027, 9, 20), runningStartingState: .notCurrentlyRunning),
            ],
            createdAt: asOf
        )
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)

        for proposedPhase in proposal.phases where proposedPhase.type != .maintenance && proposedPhase.type != .transition {
            let phase = TrainingPhase(type: proposedPhase.type, startDate: proposedPhase.startDate, endDate: proposedPhase.endDate, priorityRule: proposedPhase.priorityRule)
            let candidates = LongTermPlanner.proposeTrainingMix(phase: phase, goal: goal)
            for candidate in candidates {
                XCTAssertTrue(knownRealNames.contains(candidate.mix.name), "unexpected/fabricated mix name: \(candidate.mix.name)")
            }
        }
    }

    // MARK: - Determinism carries over to the reconciled path too

    func testReconciledProposalIsDeterministicAcrossRepeatedCalls() {
        let asOf = date(2026, 9, 3)
        let goal = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain,
            datedObjectives: [
                DatedObjective(kind: .bodyCompositionMilestone, date: date(2027, 6, 15), bodyCompositionDirection: .loseFat),
                DatedObjective(kind: .runningEvent, date: date(2027, 9, 20), runningStartingState: .notCurrentlyRunning),
            ],
            createdAt: asOf
        )

        let first = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        let second = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)

        XCTAssertEqual(first.phases.map { $0.type }, second.phases.map { $0.type })
        XCTAssertEqual(first.phases.map { $0.startDate }, second.phases.map { $0.startDate })
        XCTAssertEqual(first.phases.map { $0.endDate }, second.phases.map { $0.endDate })
    }

    // MARK: - Completed/cancelled objectives never resurrected

    func testOnlyPlannedObjectivesAreConsideredForPlanning() {
        let asOf = date(2026, 9, 3)
        let goal = Goal(
            ownerUserID: UUID(), primaryType: .muscleGain,
            datedObjectives: [
                DatedObjective(kind: .runningEvent, date: date(2026, 10, 1), status: .completed, runningStartingState: .notCurrentlyRunning),
                DatedObjective(kind: .bodyCompositionMilestone, date: date(2027, 6, 15), status: .cancelled, bodyCompositionDirection: .loseFat),
            ],
            createdAt: asOf
        )

        // Every real objective is non-planned — must degrade to an ordinary
        // forward-only plan, never resurrect the legacy milestoneDate pair
        // (which is nil here anyway) and never plan around a
        // completed/cancelled objective's own date.
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)

        XCTAssertEqual(proposal.feasibility, .feasible)
        XCTAssertTrue(proposal.phases.allSatisfy { $0.type == .muscleGain || $0.type == .maintenance })
    }
}
