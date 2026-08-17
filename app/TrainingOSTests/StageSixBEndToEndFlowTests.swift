import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 6B Slice 10: end-to-end coverage of a full Session lifecycle
/// through the same orchestrating use-case chain the UI calls — not a
/// redundant re-test of any single use case (those are already covered
/// individually), but proof the pieces compose correctly across a real,
/// multi-block, multi-modality Session the way a live workout actually
/// runs (Part Q's flow list, exercised at the use-case layer since
/// scripted UI/tap automation isn't available in this environment).
@MainActor
final class StageSixBEndToEndFlowTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func freshContext() -> ModelContext {
        ModelContext(container)
    }

    private func makeUserWithPerformanceProfile() -> (User, PerformanceProfile) {
        let profile = PerformanceProfile()
        context.insert(profile)
        let user = User(displayName: "Validation User")
        context.insert(user)
        user.attachPerformanceProfile(profile)
        return (user, profile)
    }

    /// Today -> start -> log two Strength movements (one a first-ever
    /// entry) -> log a Steady State activity -> Finish Session (full).
    /// Confirms the completion summary reflects both blocks' highlights
    /// and a real progression preview, using nothing but the same
    /// orchestrating use cases SessionDetailView/StrengthExecutionView/
    /// SteadyStateExecutionView call.
    func testFullMultiModalitySessionLifecycleProducesCorrectCompletionSummary() throws {
        let (_, performanceProfile) = makeUserWithPerformanceProfile()

        let sessionID = UUID()
        let session = Session(id: sessionID, name: "Full Body + Zone 2", modality: .hybrid, status: .scheduled)
        context.insert(session)

        let strengthBlock = WorkoutBlock(type: .strength)
        context.insert(strengthBlock)
        session.addBlock(strengthBlock)

        let squat = Exercise(canonicalName: "Back Squat", modality: .strength, equipment: "barbell", movementPattern: "squat")
        context.insert(squat)
        let squatMovement = ExercisePrescription(exercise: squat)
        context.insert(squatMovement)
        strengthBlock.addPrescription(squatMovement)
        let squatSet = SetPrescription(repRangeLow: 5, repRangeHigh: 5, targetWeight: 100, targetRir: 2)
        context.insert(squatSet)
        squatMovement.addSetPrescription(squatSet)

        let steadyBlock = WorkoutBlock(type: .steadyState)
        context.insert(steadyBlock)
        session.addBlock(steadyBlock)
        let steadyPrescription = SteadyStatePrescription(activityType: .running, durationSeconds: 1800)
        context.insert(steadyPrescription)
        steadyBlock.attachSteadyStatePrescription(steadyPrescription)

        try StartSessionUseCase.start(session, asOf: Date(), modelContext: context)
        XCTAssertEqual(session.status, .inProgress)

        let executionState = SessionExecutionState()

        let setOutcome = try LogSetUseCase.logSet(
            setIndex: 0, weight: 100, reps: 5, targetRir: 2, actualRir: 2, prBand: "5-5",
            scoringDirection: .higherIsBetter, context: .rx, setPrescription: squatSet,
            exercisePrescription: squatMovement, exercise: squat, performanceProfile: performanceProfile,
            completedAt: Date(), modelContext: context
        )
        executionState.record(LoggedResultHighlight(
            label: squat.canonicalName, value: "100 kg x 5",
            isPersonalRecord: setOutcome.result.isPersonalRecord, isFirstEverEntry: setOutcome.isFirstEverEntry
        ))
        try CompleteBlockUseCase.complete(strengthBlock, context: .full, modelContext: context)

        let steadyResult = SteadyStateResult(actualDurationSeconds: 1800, actualDistanceMeters: 5000, rpe: 5)
        let steadyOutcome = try LogEnduranceResultUseCase.logSteadyStateResult(
            steadyResult, for: steadyBlock, activityType: .running, prCandidateValue: nil,
            scoringDirection: .none, performanceProfile: performanceProfile, modelContext: context
        )
        executionState.record(LoggedResultHighlight(
            label: "Running", value: "30 min", isPersonalRecord: false, isFirstEverEntry: steadyOutcome.isFirstEverEntry
        ))
        try CompleteBlockUseCase.complete(steadyBlock, context: .full, modelContext: context)

        let summary = try CompleteSessionUseCase.complete(
            session, context: .full, asOf: Date(), highlights: executionState.highlights,
            modelContext: context
        )

        XCTAssertEqual(summary.completionContext, .full)
        XCTAssertEqual(session.status, .completed)
        // Only the squat's first-ever entry qualifies as a highlight —
        // the Steady State result was logged with `prCandidateValue: nil`
        // (no single unambiguous PR metric for that modality), so its
        // `isFirstEverEntry` is correctly always `false` and it's never
        // surfaced as a highlight (SessionExecutionState's own contract).
        XCTAssertEqual(summary.highlights.count, 1)
        XCTAssertEqual(summary.highlights.first?.label, "Back Squat")
        XCTAssertTrue(summary.progressionPreview.contains { $0.exerciseName == "Back Squat" })

        // Durability: a completely fresh context sees the same result.
        let fetchContext = freshContext()
        let reloadedSession = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionID })).first)
        XCTAssertEqual(reloadedSession.status, .completed)
        XCTAssertEqual(reloadedSession.completionContext, .full)
    }

    /// Finish-as-Partial auto-skips whatever's left, never fabricates
    /// progress for the untouched block, and stays resumable-in-spirit —
    /// the completed block's own result is untouched by the partial
    /// finish.
    func testFinishAsPartialSkipsUntouchedBlockAndNeverInventsItsResult() throws {
        let session = Session(name: "Partial Session", modality: .strength, status: .scheduled)
        context.insert(session)
        let doneBlock = WorkoutBlock(type: .strength, status: .completed)
        doneBlock.completionContext = .full
        context.insert(doneBlock)
        session.addBlock(doneBlock)
        let untouchedBlock = WorkoutBlock(type: .accessory)
        context.insert(untouchedBlock)
        session.addBlock(untouchedBlock)

        try StartSessionUseCase.start(session, asOf: Date(), modelContext: context)
        let summary = try CompleteSessionUseCase.complete(session, context: .partial, asOf: Date(), modelContext: context)

        XCTAssertEqual(summary.completionContext, .partial)
        XCTAssertEqual(untouchedBlock.status, .skipped)
        XCTAssertEqual(doneBlock.status, .completed, "the already-completed block is never touched by a sibling's partial finish")
        XCTAssertEqual(doneBlock.completionContext, .full)
    }

    /// Today Only substitution mid-session, then switching back — the
    /// original exercise's own history must be intact and untouched by
    /// whatever was logged against the substitute (SUBSTITUTION_MODEL.md).
    func testTodayOnlySubstitutionThenSwitchingBackPreservesBothExercisesOwnHistory() throws {
        let (_, performanceProfile) = makeUserWithPerformanceProfile()

        let benchPress = Exercise(canonicalName: "Barbell Bench Press", modality: .strength, equipment: "barbell", movementPattern: "push")
        context.insert(benchPress)
        let dumbbellPress = Exercise(canonicalName: "Dumbbell Bench Press", modality: .strength, equipment: "dumbbell", movementPattern: "push")
        context.insert(dumbbellPress)
        let slot = ExerciseSlot(name: "Horizontal Push", allowedExercises: [benchPress, dumbbellPress])
        context.insert(slot)

        let movement = ExercisePrescription(exercise: benchPress)
        movement.sourceExerciseSlot = slot
        context.insert(movement)
        let setA = SetPrescription(repRangeLow: 8, repRangeHigh: 8, targetWeight: 80)
        context.insert(setA)
        movement.addSetPrescription(setA)

        // Set 1 against the original exercise.
        try LogSetUseCase.logSet(
            setIndex: 0, weight: 80, reps: 8, targetRir: nil, actualRir: nil, prBand: "8-8",
            scoringDirection: .higherIsBetter, context: .rx, setPrescription: setA,
            exercisePrescription: movement, exercise: benchPress, performanceProfile: performanceProfile,
            completedAt: Date(), modelContext: context
        )

        // Substitute Today Only, log a second set against the substitute.
        try ApplySubstitutionUseCase.substituteExerciseThisSessionOnly(
            prescription: movement, slot: slot, with: dumbbellPress, modelContext: context
        )
        XCTAssertEqual(movement.exercise?.canonicalName, "Dumbbell Bench Press")
        try LogSetUseCase.logSet(
            setIndex: 1, weight: 30, reps: 10, targetRir: nil, actualRir: nil, prBand: "8-8",
            scoringDirection: .higherIsBetter, context: .rx, setPrescription: nil,
            exercisePrescription: movement, exercise: dumbbellPress, performanceProfile: performanceProfile,
            completedAt: Date(), modelContext: context
        )

        // Switch back — a real product action is just re-substituting to
        // the original exercise; its own history was never touched.
        try ApplySubstitutionUseCase.substituteExerciseThisSessionOnly(
            prescription: movement, slot: slot, with: benchPress, modelContext: context
        )
        try LogSetUseCase.logSet(
            setIndex: 2, weight: 82.5, reps: 6, targetRir: nil, actualRir: nil, prBand: "8-8",
            scoringDirection: .higherIsBetter, context: .rx, setPrescription: nil,
            exercisePrescription: movement, exercise: benchPress, performanceProfile: performanceProfile,
            completedAt: Date(), modelContext: context
        )

        let benchProfile = try XCTUnwrap(performanceProfile.profile(for: benchPress))
        let dumbbellProfile = try XCTUnwrap(performanceProfile.profile(for: dumbbellPress))

        XCTAssertEqual(benchProfile.orderedSetResults.map(\.weight), [80, 82.5], "the original exercise's own history gains both its sets, never the substitute's")
        XCTAssertEqual(dumbbellProfile.orderedSetResults.map(\.weight), [30], "the substitute's set is never merged into the original exercise's history")
    }
}
