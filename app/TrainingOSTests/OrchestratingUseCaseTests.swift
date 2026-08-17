import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 6B: the save-owning orchestrating use-case layer —
/// `WORKOUT_COMPLETION_PIPELINE.md` §1, `STAGE6A_DECISION_MEMO.md` §1d.
/// Each test confirms the action is durable immediately (a fresh
/// `ModelContext` sees it) and, where applicable, idempotent.
@MainActor
final class OrchestratingUseCaseTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func freshContext() -> ModelContext {
        ModelContext(container)
    }

    // MARK: - StartSessionUseCase

    func testStartSessionStampsStatusAndStartedAtImmediately() throws {
        let sessionID = UUID()
        let session = Session(id: sessionID, name: "Lower A", modality: .strength)
        context.insert(session)
        try context.save()

        let startedAt = Date(timeIntervalSince1970: 1_000)
        try StartSessionUseCase.start(session, asOf: startedAt, modelContext: context)

        let fetchContext = freshContext()
        let reloaded = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionID })).first)
        XCTAssertEqual(reloaded.status, .inProgress)
        XCTAssertEqual(reloaded.startedAt, startedAt)
    }

    func testStartSessionIsIdempotent() throws {
        let session = Session(name: "Lower A", modality: .strength)
        context.insert(session)
        try StartSessionUseCase.start(session, asOf: Date(timeIntervalSince1970: 1_000), modelContext: context)
        try StartSessionUseCase.start(session, asOf: Date(timeIntervalSince1970: 5_000), modelContext: context)

        XCTAssertEqual(session.startedAt, Date(timeIntervalSince1970: 1_000), "a second Start call never re-stamps an already-in-progress Session")
    }

    // MARK: - LogSetUseCase — durability

    func testLogSetPersistsImmediatelyEvenBeforeSessionCompletes() throws {
        let profile = PerformanceProfile()
        context.insert(profile)
        let exercise = Exercise(canonicalName: "Barbell Back Squat", modality: .hypertrophy, equipment: "barbell", movementPattern: "squat")
        context.insert(exercise)
        let prescriptionID = UUID()
        let prescription = ExercisePrescription(id: prescriptionID, exercise: exercise)
        context.insert(prescription)

        try LogSetUseCase.logSet(
            setIndex: 0, weight: 100, reps: 8, targetRir: 2, actualRir: 2, prBand: "8-12",
            scoringDirection: .higherIsBetter, context: .rx, setPrescription: nil,
            exercisePrescription: prescription, exercise: exercise, performanceProfile: profile,
            completedAt: Date(timeIntervalSince1970: 1_000), modelContext: context
        )

        // A fresh context proves this is genuinely durable, not merely
        // present in the in-memory object graph.
        let fetchContext = freshContext()
        let reloaded = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<ExercisePrescription>(predicate: #Predicate { $0.id == prescriptionID })).first)
        XCTAssertEqual(reloaded.loggedSetResults.count, 1)
    }

    // MARK: - LogEnduranceResultUseCase — durability

    func testLogSteadyStateResultPersistsImmediately() throws {
        let profile = PerformanceProfile()
        context.insert(profile)
        let blockID = UUID()
        let block = WorkoutBlock(id: blockID, type: .steadyState, status: .active)
        context.insert(block)

        let result = SteadyStateResult(actualDurationSeconds: 2_700)
        try LogEnduranceResultUseCase.logSteadyStateResult(
            result, for: block, activityType: .cycling, prCandidateValue: nil,
            scoringDirection: .higherIsBetter, performanceProfile: profile, modelContext: context
        )

        let fetchContext = freshContext()
        let reloaded = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<WorkoutBlock>(predicate: #Predicate { $0.id == blockID })).first)
        XCTAssertNotNil(reloaded.steadyStateResult)
    }

    // MARK: - LogFunctionalFitnessResultUseCase — durability

    func testLogFunctionalFitnessResultPersistsImmediately() throws {
        let blockID = UUID()
        let block = WorkoutBlock(id: blockID, type: .functionalFitness, status: .active)
        context.insert(block)

        let result = FunctionalFitnessResult(scoreType: .roundsAndReps, scoreValue: .roundsAndReps(rounds: 7, partialReps: 14), scoreDirection: .higherIsBetter)
        try LogFunctionalFitnessResultUseCase.logResult(result, for: block, benchmark: nil, performanceProfile: nil, modelContext: context)

        let fetchContext = freshContext()
        let reloaded = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<WorkoutBlock>(predicate: #Predicate { $0.id == blockID })).first)
        XCTAssertNotNil(reloaded.functionalFitnessResult)
    }

    // MARK: - ApplySubstitutionUseCase

    func testSubstituteExerciseThisSessionOnlySavesOnSuccess() throws {
        let barbellSquat = Exercise(canonicalName: "Barbell Back Squat", modality: .hypertrophy, equipment: "barbell", movementPattern: "squat")
        let legPress = Exercise(canonicalName: "Leg Press", modality: .hypertrophy, equipment: "machine", movementPattern: "squat")
        context.insert(barbellSquat)
        context.insert(legPress)
        let slot = ExerciseSlot(name: "Squat slot", allowedExercises: [barbellSquat, legPress])
        context.insert(slot)
        let prescriptionID = UUID()
        let prescription = ExercisePrescription(id: prescriptionID, exercise: barbellSquat)
        context.insert(prescription)
        try context.save()

        try ApplySubstitutionUseCase.substituteExerciseThisSessionOnly(
            prescription: prescription, slot: slot, with: legPress, modelContext: context
        )

        let fetchContext = freshContext()
        let reloaded = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<ExercisePrescription>(predicate: #Predicate { $0.id == prescriptionID })).first)
        XCTAssertEqual(reloaded.exercise?.canonicalName, "Leg Press")
        XCTAssertTrue(reloaded.substitutionUsed)
    }

    func testSubstituteExerciseThisSessionOnlyThrowsAndNeverMutatesOnInvalidCandidate() throws {
        let barbellSquat = Exercise(canonicalName: "Barbell Back Squat", modality: .hypertrophy, equipment: "barbell", movementPattern: "squat")
        let unrelated = Exercise(canonicalName: "Bicep Curl", modality: .hypertrophy, equipment: "dumbbell", movementPattern: "curl")
        context.insert(barbellSquat)
        context.insert(unrelated)
        let slot = ExerciseSlot(name: "Squat slot", allowedExercises: [barbellSquat])
        context.insert(slot)
        let prescription = ExercisePrescription(exercise: barbellSquat)
        context.insert(prescription)

        XCTAssertThrowsError(
            try ApplySubstitutionUseCase.substituteExerciseThisSessionOnly(
                prescription: prescription, slot: slot, with: unrelated, modelContext: context
            )
        ) { error in
            XCTAssertEqual(error as? SubstitutionError, .invalidForSlot)
        }
        XCTAssertEqual(prescription.exercise?.canonicalName, "Barbell Back Squat", "an invalid substitution never mutates the prescription")
        XCTAssertFalse(prescription.substitutionUsed)
    }

    // MARK: - CompleteBlockUseCase

    func testCompleteBlockSetsStatusAndCompletionContext() throws {
        let block = WorkoutBlock(type: .strength, status: .active)
        context.insert(block)

        try CompleteBlockUseCase.complete(block, context: .partial, modelContext: context)

        XCTAssertEqual(block.status, .completed)
        XCTAssertEqual(block.completionContext, .partial)
    }

    func testCompleteBlockIsIdempotent() throws {
        let block = WorkoutBlock(type: .strength, status: .active)
        context.insert(block)

        try CompleteBlockUseCase.complete(block, context: .full, modelContext: context)
        try CompleteBlockUseCase.complete(block, context: .partial, modelContext: context)

        XCTAssertEqual(block.completionContext, .full, "a second complete() call never overwrites an already-completed block's context")
    }

    func testSkipBlockNeverGoesThroughCompletedStatus() throws {
        let block = WorkoutBlock(type: .strength, status: .pending)
        context.insert(block)

        try CompleteBlockUseCase.skip(block, modelContext: context)

        XCTAssertEqual(block.status, .skipped)
        XCTAssertNil(block.completionContext, "a skipped block was never attempted — completionContext stays nil, distinct from a partial attempt")
    }

    // MARK: - ChangeSessionStatusUseCase

    func testSkipSessionOnlyValidFromScheduled() throws {
        let session = Session(name: "Lower A", modality: .strength, status: .scheduled)
        context.insert(session)

        try ChangeSessionStatusUseCase.skip(session, modelContext: context)
        XCTAssertEqual(session.status, .skipped)
    }

    func testSkipSessionIsANoOpOnceAlreadyInProgress() throws {
        let session = Session(name: "Lower A", modality: .strength, status: .inProgress)
        context.insert(session)

        try ChangeSessionStatusUseCase.skip(session, modelContext: context)

        XCTAssertEqual(session.status, .inProgress, "an in-progress Session can never be retroactively marked skipped through this path")
    }

    func testMarkMissedOnlyValidFromScheduled() throws {
        let session = Session(name: "Lower A", modality: .strength, status: .scheduled)
        context.insert(session)

        try ChangeSessionStatusUseCase.markMissed(session, modelContext: context)
        XCTAssertEqual(session.status, .missed)
    }

    /// The exact distinction the resolved decision sharpens: an explicit
    /// skip and a passively-missed Session must never be conflatable —
    /// each use case only ever writes its own status.
    func testUserSkippedAndMissedAreNeverConflated() throws {
        let skipped = Session(name: "A", modality: .strength, status: .scheduled)
        let missed = Session(name: "B", modality: .strength, status: .scheduled)
        context.insert(skipped)
        context.insert(missed)

        try ChangeSessionStatusUseCase.skip(skipped, modelContext: context)
        try ChangeSessionStatusUseCase.markMissed(missed, modelContext: context)

        XCTAssertEqual(skipped.status, .skipped)
        XCTAssertEqual(missed.status, .missed)
    }

    // MARK: - CompleteSessionUseCase

    func testCompleteSessionFullMarksSessionCompletedWithFullContext() throws {
        let session = Session(name: "Lower A", modality: .strength, status: .inProgress)
        context.insert(session)
        let block = WorkoutBlock(type: .strength, status: .completed)
        block.completionContext = .full
        context.insert(block)
        session.addBlock(block)

        let summary = try CompleteSessionUseCase.complete(session, context: .full, asOf: Date(timeIntervalSince1970: 5_000), modelContext: context)

        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.completionContext, .full)
        XCTAssertEqual(session.completedAt, Date(timeIntervalSince1970: 5_000))
        XCTAssertEqual(summary.completionContext, .full)
    }

    func testCompleteSessionAsPartialMarksRemainingBlocksSkipped() throws {
        let session = Session(name: "Lower A", modality: .strength, status: .inProgress)
        context.insert(session)
        let doneBlock = WorkoutBlock(type: .strength, status: .completed)
        doneBlock.completionContext = .full
        context.insert(doneBlock)
        session.addBlock(doneBlock)
        let pendingBlock = WorkoutBlock(type: .functionalFitness, status: .pending)
        context.insert(pendingBlock)
        session.addBlock(pendingBlock)
        let activeBlock = WorkoutBlock(type: .cooldown, status: .active)
        context.insert(activeBlock)
        session.addBlock(activeBlock)

        try CompleteSessionUseCase.complete(session, context: .partial, asOf: Date(timeIntervalSince1970: 5_000), modelContext: context)

        XCTAssertEqual(session.completionContext, .partial)
        XCTAssertEqual(doneBlock.status, .completed, "an already-finished block is untouched")
        XCTAssertEqual(pendingBlock.status, .skipped)
        XCTAssertEqual(activeBlock.status, .skipped)
    }

    /// §52: completion must be idempotent — a double-tapped Finish must
    /// never re-mutate state or duplicate anything.
    func testCompleteSessionCalledTwiceNeverReMutatesOrDuplicates() throws {
        let session = Session(name: "Lower A", modality: .strength, status: .inProgress)
        context.insert(session)
        let block = WorkoutBlock(type: .strength, status: .active)
        context.insert(block)
        session.addBlock(block)

        try CompleteSessionUseCase.complete(session, context: .partial, asOf: Date(timeIntervalSince1970: 1_000), modelContext: context)
        XCTAssertEqual(block.status, .skipped)

        // Second call: different (wrong) context/timestamp intentionally,
        // to prove the first completion's facts are never overwritten.
        try CompleteSessionUseCase.complete(session, context: .full, asOf: Date(timeIntervalSince1970: 9_999), modelContext: context)

        XCTAssertEqual(session.completionContext, .partial, "the second call must not silently reclassify an already-completed Session")
        XCTAssertEqual(session.completedAt, Date(timeIntervalSince1970: 1_000))
    }

    func testCompleteSessionProducesAProgressionPreviewForLoggedExercises() throws {
        let profile = PerformanceProfile()
        context.insert(profile)
        let exercise = Exercise(canonicalName: "Barbell Back Squat", modality: .hypertrophy, equipment: "barbell", movementPattern: "squat")
        context.insert(exercise)
        let session = Session(name: "Lower A", modality: .strength, status: .inProgress)
        context.insert(session)
        let block = WorkoutBlock(type: .strength, status: .active)
        context.insert(block)
        session.addBlock(block)
        let prescription = ExercisePrescription(exercise: exercise)
        context.insert(prescription)
        block.addPrescription(prescription)
        let setPrescription = SetPrescription(repRangeLow: 8, repRangeHigh: 12, targetWeight: 100, targetRir: 2)
        context.insert(setPrescription)
        prescription.addSetPrescription(setPrescription)

        try LogSetUseCase.logSet(
            setIndex: 0, weight: 100, reps: 12, targetRir: 2, actualRir: 2, prBand: "8-12",
            scoringDirection: .higherIsBetter, context: .rx, setPrescription: setPrescription,
            exercisePrescription: prescription, exercise: exercise, performanceProfile: profile,
            completedAt: Date(timeIntervalSince1970: 1_000), modelContext: context
        )

        let summary = try CompleteSessionUseCase.complete(session, context: .full, asOf: Date(timeIntervalSince1970: 2_000), modelContext: context)

        XCTAssertEqual(summary.progressionPreview.count, 1)
        XCTAssertEqual(summary.progressionPreview.first?.exerciseName, "Barbell Back Squat")
        XCTAssertEqual(summary.progressionPreview.first?.reasonCode, .loadIncrease, "every set hit the top of range at target RIR")
    }

    func testCompleteSessionSkipsPreviewForBlocksWithNoLoggedResults() throws {
        let exercise = Exercise(canonicalName: "Overhead Press", modality: .hypertrophy, equipment: "barbell", movementPattern: "press")
        context.insert(exercise)
        let session = Session(name: "Upper A", modality: .strength, status: .inProgress)
        context.insert(session)
        let block = WorkoutBlock(type: .strength, status: .pending)
        context.insert(block)
        session.addBlock(block)
        let prescription = ExercisePrescription(exercise: exercise)
        context.insert(prescription)
        block.addPrescription(prescription)

        let summary = try CompleteSessionUseCase.complete(session, context: .partial, asOf: Date(timeIntervalSince1970: 2_000), modelContext: context)

        XCTAssertTrue(summary.progressionPreview.isEmpty, "no logged results — never a fabricated preview row")
    }
}
