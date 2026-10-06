import XCTest
import SwiftData
@testable import TrainingOS

/// Dogfood Round 2 Continuation 3 — Findings N and O:
///
/// N. "Confirm & Continue" on the in-session calibration prompt left the
///    athlete on the same exercise, requiring a manual "Next Exercise" tap.
/// O. After entering all required calibrations, the session overview showed
///    BOTH Functional Bodybuilding and Conditioning as "In Progress" with no
///    clear athlete action — calibration (preparation) was being conflated
///    with genuinely performing a block's work.
///
/// Both findings are exercised against the real Muscle Gain Functional
/// Bodybuilding production path (`StrategicPlanSelectionViewModel
/// .buildCustomMix` -> `acceptAndStart` -> `StartPhaseUseCase.start` -> real
/// materializers), deliberately WITHOUT pre-resolving calibration (unlike
/// `DogfoodRound2CompletionTests`'s own `completeAnyCalibration` helper) so
/// the real, still-`.calibrationRequired` state these findings are about is
/// actually reachable.
@MainActor
final class DogfoodRound2ContinuationFindingsNOTests: XCTestCase {
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

    /// Mirrors `DogfoodRound2CompletionTests`'s own real-path fixture,
    /// deliberately stopping before any calibration is resolved.
    private func makeUncalibratedMuscleGainFBBSession() throws -> Session {
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        user.profile?.trainingEnvironments = [environment]
        user.profile?.defaultTrainingEnvironment = environment
        let goal = Goal(
            ownerUserID: user.id, primaryType: .muscleGain,
            preferences: GoalPreferences(availableTrainingDaysPerWeek: 5, allowsDoubleSessions: false)
        )
        context.insert(goal)
        user.addGoal(goal)
        try context.save()

        let monday = date(2026, 1, 5)
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context, referenceDate: monday)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.hypertrophy, 4), (.functionalFitness, 1)]))
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))

        guard let phase = goal.plans.first?.orderedPhases.first,
              let ffComponent = (phase.selectedTrainingMix ?? phase.recommendedTrainingMix)?.orderedComponents.first(where: { $0.programmingSystem == .functionalFitness }),
              let ffSession = ffComponent.programInstance?.sessions.first
        else { throw XCTSkip("expected a real, materialized FF session") }
        return ffSession
    }

    // MARK: - Finding N: "Confirm & Continue" must actually continue

    func testFindingN_IntermediateCalibrationAdvancesToNextUnresolvedMovement() throws {
        let session = try makeUncalibratedMuscleGainFBBSession()
        let strengthBlock = try XCTUnwrap(session.orderedBlocks.first { ($0.type == .strength || $0.type == .hypertrophy) })
        let requiringCalibration = strengthBlock.orderedPrescriptions.filter { $0.appliedLoadReasonCode == .calibrationRequired }
        try XCTSkipUnless(requiringCalibration.count >= 2, "needs at least 2 distinct loaded-pattern roles to prove intermediate advancement")

        let viewModel = StrengthExecutionViewModel(block: strengthBlock)
        let firstIndex = viewModel.movementIndex
        XCTAssertTrue(viewModel.currentMovementNeedsCalibration, "the first not-yet-complete movement must be the one awaiting calibration")

        XCTAssertTrue(viewModel.submitCalibration(kilograms: 100, modelContext: context))

        XCTAssertNotEqual(viewModel.movementIndex, firstIndex, "Confirm & Continue must automatically move to the next unresolved-calibration exercise, never leave the athlete on the same one")
        XCTAssertTrue(viewModel.currentMovementNeedsCalibration, "the exercise it advanced to must itself still genuinely need calibration")
    }

    func testFindingN_FinalCalibrationLeavesAthleteOffCalibrationStateAutomatically() throws {
        let session = try makeUncalibratedMuscleGainFBBSession()
        let strengthBlock = try XCTUnwrap(session.orderedBlocks.first { ($0.type == .strength || $0.type == .hypertrophy) })
        let requiringCalibration = strengthBlock.orderedPrescriptions.filter { $0.appliedLoadReasonCode == .calibrationRequired }
        try XCTSkipUnless(!requiringCalibration.isEmpty, "needs at least one calibration-required role")

        let viewModel = StrengthExecutionViewModel(block: strengthBlock)
        // Resolve every real calibration requirement this block has, one
        // real exercise at a time, exactly as the athlete would.
        var resolvedExerciseIDs: Set<UUID> = []
        while viewModel.currentMovementNeedsCalibration {
            guard let requirement = viewModel.currentMovementCalibrationRequirement else { break }
            XCTAssertFalse(resolvedExerciseIDs.contains(requirement.exercise.id), "must never re-resolve the same exercise's calibration twice")
            resolvedExerciseIDs.insert(requirement.exercise.id)
            XCTAssertTrue(viewModel.submitCalibration(kilograms: 100, modelContext: context))
        }

        XCTAssertFalse(viewModel.currentMovementNeedsCalibration, "after the final real calibration, the current movement must already be resolved — no further calibration prompt")
        XCTAssertTrue(strengthBlock.orderedPrescriptions.allSatisfy { $0.appliedLoadReasonCode != .calibrationRequired }, "every rmBased role in this block must be resolved once every distinct exercise it depends on has been calibrated")
    }

    // MARK: - Finding O: calibration is preparation, never performance

    func testFindingO_CalibrationSubmissionAloneNeverMarksTheBlockActive() throws {
        let session = try makeUncalibratedMuscleGainFBBSession()
        let strengthBlock = try XCTUnwrap(session.orderedBlocks.first { ($0.type == .strength || $0.type == .hypertrophy) })
        XCTAssertEqual(strengthBlock.status, .pending, "sanity: a freshly materialized block is untouched")

        let viewModel = StrengthExecutionViewModel(block: strengthBlock)
        while viewModel.currentMovementNeedsCalibration {
            XCTAssertTrue(viewModel.submitCalibration(kilograms: 100, modelContext: context))
        }

        XCTAssertEqual(strengthBlock.status, .pending, "resolving every required calibration must never, by itself, mark the block as actively performed — that would conflate preparation with performance")
    }

    func testFindingO_BlockBecomesActiveOnlyOnceARealSetIsLogged() throws {
        let session = try makeUncalibratedMuscleGainFBBSession()
        let strengthBlock = try XCTUnwrap(session.orderedBlocks.first { ($0.type == .strength || $0.type == .hypertrophy) })

        let viewModel = StrengthExecutionViewModel(block: strengthBlock)
        while viewModel.currentMovementNeedsCalibration {
            XCTAssertTrue(viewModel.submitCalibration(kilograms: 100, modelContext: context))
        }
        XCTAssertEqual(strengthBlock.status, .pending, "still untouched after calibration alone")

        XCTAssertNotNil(viewModel.logCurrentSet(weight: 100, reps: 8, actualRir: 2, modelContext: context))

        XCTAssertNotEqual(strengthBlock.status, .pending, "logging a real set must transition the block away from .pending — this IS the athlete genuinely performing the work")
    }

    // MARK: - Finding O: session overview auto-advance across multiple blocks

    func testFindingO_AutoAdvanceDoesNotFireWhileBothBlocksStillHaveWork() throws {
        let session = try makeUncalibratedMuscleGainFBBSession()
        try StartSessionUseCase.start(session, asOf: date(2026, 1, 5), modelContext: context)
        XCTAssertEqual(session.orderedBlocks.count, 2, "sanity: Functional Bodybuilding + Conditioning")
        XCTAssertTrue(session.orderedBlocks.allSatisfy { $0.status == .pending })

        XCTAssertNil(SessionAutoAdvance.blockToAutoOpen(session: session), "a real choice still exists while more than one block has work left — must not force a destination")
    }

    func testFindingO_AutoAdvanceOpensConditioningOnceFunctionalBodybuildingCompletes() throws {
        let session = try makeUncalibratedMuscleGainFBBSession()
        try StartSessionUseCase.start(session, asOf: date(2026, 1, 5), modelContext: context)
        let strengthBlock = try XCTUnwrap(session.orderedBlocks.first { ($0.type == .strength || $0.type == .hypertrophy) })
        let conditioningBlock = try XCTUnwrap(session.orderedBlocks.first { $0.type == .functionalFitness })

        try CompleteBlockUseCase.complete(strengthBlock, context: .full, modelContext: context)

        let candidate = SessionAutoAdvance.blockToAutoOpen(session: session)
        XCTAssertEqual(candidate?.id, conditioningBlock.id, "Functional Bodybuilding genuinely finished — Conditioning is now the sole remaining thing to do, so it must auto-advance, closing the reported dead end")
    }

    func testFindingO_AutoAdvanceNeverFiresOnceEveryBlockIsFinished() throws {
        let session = try makeUncalibratedMuscleGainFBBSession()
        try StartSessionUseCase.start(session, asOf: date(2026, 1, 5), modelContext: context)
        for block in session.orderedBlocks {
            try CompleteBlockUseCase.complete(block, context: .full, modelContext: context)
        }
        XCTAssertNil(SessionAutoAdvance.blockToAutoOpen(session: session), "nothing left to do — must never fire once the whole Session is genuinely finished")
    }

    func testFindingO_UnopenedConditioningNeverShowsInProgressMerelyBecauseSessionStarted() throws {
        let session = try makeUncalibratedMuscleGainFBBSession()
        try StartSessionUseCase.start(session, asOf: date(2026, 1, 5), modelContext: context)
        let conditioningBlock = try XCTUnwrap(session.orderedBlocks.first { $0.type == .functionalFitness })
        XCTAssertEqual(session.status, .inProgress, "sanity: the Session itself is started")
        XCTAssertEqual(conditioningBlock.status, .pending, "an untouched block must stay Pending even once its parent Session is In Progress — block-level status is independent")
        XCTAssertEqual(BlockPresentation.statusLabel(conditioningBlock), "Pending")
    }
}
