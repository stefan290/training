import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 6C acceptance tests (Part AA): a realistic 5-exercise Strength
/// WorkoutBlock can be viewed, started, executed exercise-to-exercise,
/// interrupted, resumed, and completed — proving the exact end-to-end
/// gap manual Simulator testing found was not exercised by Stage 6B's own
/// suite. Every fixture here goes through the real production
/// materialization path (`SeedScenarios.materializedLowerASession`), not
/// a hand-assembled single-exercise stand-in.
@MainActor
final class MultiExerciseExecutionTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var performanceProfile: PerformanceProfile!
    let ownerUserID = UUID()

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
        performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        // StrengthExecutionViewModel.logCurrentSet resolves its own
        // PerformanceProfile via the first User in the store (matching
        // every other execution ViewModel) — without this, the view-
        // model-driven logging path silently no-ops forever, an infinite
        // loop for any test that logs through it directly.
        let user = User(displayName: "Test User")
        context.insert(user)
        user.attachPerformanceProfile(performanceProfile)
    }

    private func freshContext() -> ModelContext {
        ModelContext(container)
    }

    @discardableResult
    private func makeLowerA() -> (session: Session, programInstance: ProgramInstance, multiAlternativeSlot: ExerciseSlot, catalog: ExerciseCatalog) {
        let catalog = ExerciseCatalog.makeAndInsert(context: context)
        let day = Day(ownerUserID: ownerUserID, date: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(day)
        let fixture = SeedScenarios.materializedLowerASession(
            day: day, catalog: catalog, ownerUserID: ownerUserID, modelContext: context
        )
        return (fixture.session, fixture.programInstance, fixture.multiAlternativeSlot, catalog)
    }

    private func logAllSets(for movement: ExercisePrescription, modelContext: ModelContext) throws {
        for setPrescription in movement.orderedSetPrescriptions {
            try LogSetUseCase.logSet(
                setIndex: movement.loggedSetResults.count,
                weight: setPrescription.targetWeight ?? 20,
                reps: setPrescription.repRangeHigh,
                targetRir: setPrescription.targetRir,
                actualRir: setPrescription.targetRir,
                prBand: "\(setPrescription.repRangeLow)-\(setPrescription.repRangeHigh)",
                scoringDirection: .higherIsBetter,
                context: .rx,
                setPrescription: setPrescription,
                exercisePrescription: movement,
                exercise: movement.exercise!,
                performanceProfile: performanceProfile,
                completedAt: Date(),
                modelContext: modelContext
            )
        }
    }

    // MARK: A — canonical order

    func testFiveExercisePrescriptionsPreserveCanonicalOrder() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        XCTAssertEqual(block.orderedPrescriptions.count, 5)
        XCTAssertEqual(
            block.orderedPrescriptions.compactMap { $0.exercise?.canonicalName },
            ["Back Squat", "Romanian Deadlift", "Leg Press", "Leg Curl", "Calf Raise"]
        )
    }

    /// Stage 6D Part 2: the materialized prescription's `targetRir` is the
    /// engine's own honest translation of `RepGoal.toFailure` (0, the only
    /// intensity-target concept the approved family specs define) — never
    /// hardcoded in the UI, and never present where the source data has
    /// no such concept (an accessory's `toFailure == false`).
    func testMaterializedRIRComesFromTheRealPrescriptionNeverHardcoded() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        let squat = try XCTUnwrap(block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Back Squat" })
        let legCurl = try XCTUnwrap(block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Leg Curl" })

        XCTAssertEqual(squat.orderedSetPrescriptions.first?.targetRir, 0, "a to-failure primary movement materializes with a real RIR target")
        XCTAssertNil(legCurl.orderedSetPrescriptions.first?.targetRir, "an accessory with no toFailure target has no invented RIR value")
    }

    // MARK: B/C — exercise completion + next exercise

    func testCompletingAllSetsOfExerciseOneMakesItLogicallyComplete() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        let viewModel = StrengthExecutionViewModel(block: block)
        let firstMovement = try XCTUnwrap(viewModel.movements.first)

        try logAllSets(for: firstMovement, modelContext: context)

        XCTAssertTrue(StrengthExecutionViewModel.isComplete(firstMovement))
    }

    func testExerciseTwoBecomesTheLogicalNextExercise() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        let firstMovement = try XCTUnwrap(block.orderedPrescriptions.first)
        try logAllSets(for: firstMovement, modelContext: context)

        // A fresh ViewModel (as a relaunch would create) resumes at the
        // first not-yet-complete movement — index 1, Romanian Deadlift.
        let resumed = StrengthExecutionViewModel(block: block)
        XCTAssertEqual(resumed.movementIndex, 1)
        XCTAssertEqual(resumed.currentMovement?.exercise?.canonicalName, "Romanian Deadlift")
    }

    // MARK: D/E — WorkoutBlock completion

    func testCompletingExerciseOneNeverCompletesTheBlockWithFourExercisesRemaining() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        let viewModel = StrengthExecutionViewModel(block: block)
        try logAllSets(for: viewModel.movements[0], modelContext: context)

        XCTAssertFalse(viewModel.isBlockComplete)
        XCTAssertNotEqual(block.status, .completed)
    }

    func testCompletingAllFiveExercisesCompletesTheWorkoutBlock() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        let viewModel = StrengthExecutionViewModel(block: block)

        for movement in viewModel.movements {
            try logAllSets(for: movement, modelContext: context)
        }
        // The view model itself triggers the auto-transition on its own
        // `logCurrentSet` path; since this test logs directly through
        // `LogSetUseCase` to control fixture values precisely, drive the
        // same completion check the view model would have performed.
        if viewModel.isBlockComplete {
            try CompleteBlockUseCase.complete(block, context: .full, modelContext: context)
        }

        XCTAssertTrue(viewModel.isBlockComplete)
        XCTAssertEqual(block.status, .completed)
        XCTAssertEqual(block.completionContext, .full)
    }

    /// The real, view-driven path: logging through
    /// `StrengthExecutionViewModel.logCurrentSet` itself (not the lower-
    /// level `LogSetUseCase` directly) must auto-complete the block with
    /// no separate confirmation step — this is the exact fix for the
    /// manually-observed "all required work complete, block remains In
    /// Progress indefinitely" bug (Part J).
    func testLoggingThroughTheViewModelAutoCompletesTheBlockOnTheFinalSet() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        let viewModel = StrengthExecutionViewModel(block: block)

        var iterations = 0
        while !viewModel.isBlockComplete {
            iterations += 1
            guard iterations < 100 else {
                XCTFail("safety bound — logging should never take this many iterations for 5 exercises")
                break
            }
            guard let setPrescription = viewModel.currentSetPrescription else { break }
            viewModel.logCurrentSet(weight: setPrescription.targetWeight ?? 20, reps: setPrescription.repRangeHigh, actualRir: setPrescription.targetRir, modelContext: context)
            if viewModel.isMovementComplete, viewModel.hasNextMovement {
                viewModel.goToNextMovement(modelContext: context)
            }
        }

        XCTAssertEqual(block.status, .completed)
    }

    // MARK: F/G — Session completion normal vs. partial

    func testOneBlockSessionFullyCompletedFinishesNormally() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        for movement in block.orderedPrescriptions {
            try logAllSets(for: movement, modelContext: context)
        }
        try CompleteBlockUseCase.complete(block, context: .full, modelContext: context)
        try StartSessionUseCase.start(fixture.session, asOf: Date(), modelContext: context)

        let allCompleted = fixture.session.orderedBlocks.allSatisfy { $0.status == .completed }
        XCTAssertTrue(allCompleted, "a fully completed Session must be offered normal Finish, never forced through Finish as Partial")

        let summary = try CompleteSessionUseCase.complete(fixture.session, context: .full, asOf: Date(), modelContext: context)
        XCTAssertEqual(summary.completionContext, .full)
        XCTAssertEqual(fixture.session.status, .completed)
    }

    func testFullyCompletedSessionIsNotForcedThroughFinishAsPartial() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        for movement in block.orderedPrescriptions {
            try logAllSets(for: movement, modelContext: context)
        }
        try CompleteBlockUseCase.complete(block, context: .full, modelContext: context)

        // The exact condition SessionDetailView uses to choose between
        // "Finish Session" and "Finish as Partial."
        let allCompleted = !fixture.session.orderedBlocks.isEmpty
            && fixture.session.orderedBlocks.allSatisfy { $0.status == .completed }
        XCTAssertTrue(allCompleted)
    }

    func testGenuinelyIncompleteSessionCanStillFinishAsPartial() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        try logAllSets(for: block.orderedPrescriptions[0], modelContext: context)
        try StartSessionUseCase.start(fixture.session, asOf: Date(), modelContext: context)

        let summary = try CompleteSessionUseCase.complete(fixture.session, context: .partial, asOf: Date(), modelContext: context)
        XCTAssertEqual(summary.completionContext, .partial)
        XCTAssertEqual(fixture.session.status, .completed)
        XCTAssertEqual(block.status, .skipped, "the never-finished block is auto-skipped by a partial finish")
    }

    // MARK: I — multi-block Session moves to the next block instead of finishing early

    func testStrengthPlusFunctionalFitnessSessionDoesNotFinishEarlyAfterStrengthCompletes() throws {
        let fixture = makeLowerA()
        let strengthBlock = try XCTUnwrap(fixture.session.orderedBlocks.first)
        for movement in strengthBlock.orderedPrescriptions {
            try logAllSets(for: movement, modelContext: context)
        }
        try CompleteBlockUseCase.complete(strengthBlock, context: .full, modelContext: context)

        let ffBlock = WorkoutBlock(type: .functionalFitness, status: .pending)
        context.insert(ffBlock)
        fixture.session.addBlock(ffBlock)

        XCTAssertEqual(strengthBlock.status, .completed, "completing block 1 never mutates block 2")
        XCTAssertEqual(ffBlock.status, .pending, "the sibling block is untouched by the first block's own completion")
        XCTAssertFalse(fixture.session.orderedBlocks.allSatisfy { $0.status == .completed }, "the Session is not yet eligible for normal Finish while the FF block remains")
    }

    // MARK: J/K/L — crash/relaunch resume

    func testRelaunchingResumesAtTheCorrectIncompleteExercise() throws {
        let fixture = makeLowerA()
        let sessionID = fixture.session.id
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        try logAllSets(for: block.orderedPrescriptions[0], modelContext: context)
        try LogSetUseCase.logSet(
            setIndex: 0, weight: 60, reps: 9, targetRir: nil, actualRir: nil, prBand: nil,
            scoringDirection: .higherIsBetter, context: .rx,
            setPrescription: block.orderedPrescriptions[1].orderedSetPrescriptions.first,
            exercisePrescription: block.orderedPrescriptions[1], exercise: block.orderedPrescriptions[1].exercise!,
            performanceProfile: performanceProfile, completedAt: Date(), modelContext: context
        )
        try context.save()

        // Simulate relaunch: a completely fresh ModelContext/fetch.
        let fetchContext = freshContext()
        let reloadedSession = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionID })).first)
        let reloadedBlock = try XCTUnwrap(reloadedSession.orderedBlocks.first)
        let resumedViewModel = StrengthExecutionViewModel(block: reloadedBlock)

        XCTAssertEqual(resumedViewModel.currentMovement?.exercise?.canonicalName, "Romanian Deadlift")
        XCTAssertEqual(resumedViewModel.currentSetIndex, 1, "one Romanian Deadlift set was already logged before relaunch")
    }

    func testLoggedResultsSurviveRelaunch() throws {
        let fixture = makeLowerA()
        let sessionID = fixture.session.id
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        try logAllSets(for: block.orderedPrescriptions[0], modelContext: context)
        try context.save()

        let fetchContext = freshContext()
        let reloadedSession = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionID })).first)
        let reloadedBlock = try XCTUnwrap(reloadedSession.orderedBlocks.first)
        XCTAssertEqual(reloadedBlock.orderedPrescriptions[0].loggedSetResults.count, 3)
    }

    func testAlreadyCompletedSetsAreNotDuplicatedAfterResume() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        try logAllSets(for: block.orderedPrescriptions[0], modelContext: context)

        // "Resuming" is just constructing a new view model against the
        // same, already-persisted block — it must never re-log anything.
        _ = StrengthExecutionViewModel(block: block)
        XCTAssertEqual(block.orderedPrescriptions[0].loggedSetResults.count, 3)
    }

    // MARK: M/N/O/P — Change Exercise / substitution

    func testChangeExerciseAvailabilityReflectsWhetherASourceSlotExists() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        XCTAssertNotNil(block.orderedPrescriptions[0].sourceExerciseSlot, "materialized through the real slot pipeline")

        let adHoc = ExercisePrescription(exercise: fixture.catalog.backSquat)
        XCTAssertNil(adHoc.sourceExerciseSlot, "an ad hoc/seed-authored movement has nothing to validate an alternative against")
    }

    func testSlotMaterializedExerciseExposesValidSubstitutionAlternatives() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        let legPressMovement = try XCTUnwrap(block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Leg Press" })
        let slot = try XCTUnwrap(legPressMovement.sourceExerciseSlot)

        let candidates = SubstitutionCandidateRanking.rank(
            slot: slot, excluding: fixture.catalog.legPress,
            allExercises: [fixture.catalog.legPress, fixture.catalog.bulgarianSplitSquat],
            curatedRelationships: [], profileLookup: { _ in nil }
        )
        XCTAssertTrue(candidates.contains { $0.exercise.canonicalName == "Bulgarian Split Squat" })
    }

    func testTodayOnlySubstitutionAffectsOnlyTheIntendedMaterializedPrescription() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        let legPressMovement = try XCTUnwrap(block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Leg Press" })
        let squatMovement = try XCTUnwrap(block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Back Squat" })
        let slot = try XCTUnwrap(legPressMovement.sourceExerciseSlot)

        try ApplySubstitutionUseCase.substituteExerciseThisSessionOnly(
            prescription: legPressMovement, slot: slot, with: fixture.catalog.bulgarianSplitSquat, modelContext: context
        )

        XCTAssertEqual(legPressMovement.exercise?.canonicalName, "Bulgarian Split Squat")
        XCTAssertEqual(squatMovement.exercise?.canonicalName, "Back Squat", "an unrelated movement in the same block is untouched")
        XCTAssertEqual(slot.resolvedExercise?.canonicalName, "Leg Press", "the template's own default is never mutated by a THIS SESSION ONLY edit")
    }

    func testGoingForwardSubstitutionUsesTheExistingOverrideArchitecture() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        let legPressMovement = try XCTUnwrap(block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Leg Press" })
        let slot = try XCTUnwrap(legPressMovement.sourceExerciseSlot)

        try ApplySubstitutionUseCase.substituteExerciseGoingForward(
            instance: fixture.programInstance, slot: slot, with: fixture.catalog.bulgarianSplitSquat, modelContext: context
        )

        XCTAssertNotNil(fixture.programInstance.slotSelectionOverride(for: slot))
        XCTAssertEqual(
            SubstituteExerciseUseCase.resolvedExercise(for: slot, in: fixture.programInstance)?.canonicalName,
            "Bulgarian Split Squat"
        )
        XCTAssertEqual(slot.resolvedExercise?.canonicalName, "Leg Press", "the template default itself is never rewritten by an instance-level override")
        // The already-materialized prescription itself is untouched by a
        // GOING FORWARD override — it only governs *future* materialization.
        XCTAssertEqual(legPressMovement.exercise?.canonicalName, "Leg Press")
    }

    /// Stage 6D Part 3: lacking history must never block a valid slot
    /// substitution — CALIBRATION_REQUIRED means "we can't confidently
    /// suggest a starting load," never "you can't perform this exercise."
    /// A calibration-required candidate must be exactly as selectable and
    /// applicable as any other tier.
    func testValidSubstitutionWithNoHistoryIsAllowedAndRequiresCalibrationRatherThanBlocking() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        let legPressMovement = try XCTUnwrap(block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Leg Press" })
        let slot = try XCTUnwrap(legPressMovement.sourceExerciseSlot)

        let candidates = SubstitutionCandidateRanking.rank(
            slot: slot, excluding: fixture.catalog.legPress,
            allExercises: [fixture.catalog.legPress, fixture.catalog.bulgarianSplitSquat],
            curatedRelationships: [], profileLookup: { _ in nil }
        )
        let noHistoryCandidate = try XCTUnwrap(candidates.first { $0.exercise.canonicalName == "Bulgarian Split Squat" })
        XCTAssertEqual(noHistoryCandidate.tier, .calibrationRequired, "no history for this candidate or any related exercise")

        // The substitution itself must succeed exactly like any other tier.
        try ApplySubstitutionUseCase.substituteExerciseThisSessionOnly(
            prescription: legPressMovement, slot: slot, with: noHistoryCandidate.exercise, modelContext: context
        )
        XCTAssertEqual(legPressMovement.exercise?.canonicalName, "Bulgarian Split Squat")

        // The prescribed sets/reps remain applicable — substitution never
        // clears or blocks the existing sets/reps prescription.
        XCTAssertFalse(legPressMovement.orderedSetPrescriptions.isEmpty)
    }
}
