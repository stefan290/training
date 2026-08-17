import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 6B: real SwiftData round-trip coverage for every new persisted
/// field this stage introduces — written before trusting any of them,
/// per this project's own "verify persistence assumptions before
/// trusting them" discipline (Stage 4A's Bug 2/3, re-confirmed every
/// stage since).
@MainActor
final class ExecutionStatePersistenceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func freshContext() -> ModelContext {
        ModelContext(container)
    }

    func testSessionCompletionContextSurvivesRoundTrip() throws {
        let sessionID = UUID()
        let session = Session(id: sessionID, name: "Lower A", modality: .strength, status: .completed)
        session.completionContext = .partial
        context.insert(session)
        try context.save()

        let fetchContext = freshContext()
        let reloaded = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionID })).first)

        XCTAssertEqual(reloaded.status, .completed)
        XCTAssertEqual(reloaded.completionContext, .partial)
    }

    func testSessionCompletionContextDefaultsToNil() throws {
        let session = Session(name: "Upper Push A", modality: .strength)
        context.insert(session)
        try context.save()

        XCTAssertNil(session.completionContext)
    }

    /// The Stage 4A Bug 2/3 diagnostic, repeated for this stage's own new
    /// fields: two sibling rows with different values for the same new
    /// field must both survive independently, never silently nil-ing a
    /// sibling.
    func testTwoSiblingSessionsWithDifferentCompletionContextsBothSurviveRoundTrip() throws {
        let fullID = UUID()
        let full = Session(id: fullID, name: "Full", modality: .strength, status: .completed)
        full.completionContext = .full
        context.insert(full)

        let partialID = UUID()
        let partial = Session(id: partialID, name: "Partial", modality: .strength, status: .completed)
        partial.completionContext = .partial
        context.insert(partial)

        try context.save()

        let fetchContext = freshContext()
        let reloadedFull = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == fullID })).first)
        let reloadedPartial = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == partialID })).first)

        XCTAssertEqual(reloadedFull.completionContext, .full)
        XCTAssertEqual(reloadedPartial.completionContext, .partial)
    }

    func testWorkoutBlockCompletionContextSurvivesRoundTrip() throws {
        let blockID = UUID()
        let block = WorkoutBlock(id: blockID, type: .strength, status: .completed)
        block.completionContext = .partial
        context.insert(block)
        try context.save()

        let fetchContext = freshContext()
        let reloaded = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<WorkoutBlock>(predicate: #Predicate { $0.id == blockID })).first)

        XCTAssertEqual(reloaded.status, .completed)
        XCTAssertEqual(reloaded.completionContext, .partial)
    }

    func testWorkoutBlockTimerStateSurvivesRoundTripWithAllFieldsPopulated() throws {
        let blockID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let pausedAt = Date(timeIntervalSince1970: 1_800_000_060)
        let block = WorkoutBlock(id: blockID, type: .functionalFitness, status: .active)
        block.timerState = TimerState(
            startedAt: startedAt,
            pausedAt: pausedAt,
            accumulatedPauseSeconds: 45,
            targetDurationSeconds: 720,
            currentUnitIndex: 3
        )
        context.insert(block)
        try context.save()

        let fetchContext = freshContext()
        let reloaded = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<WorkoutBlock>(predicate: #Predicate { $0.id == blockID })).first)

        let timerState = try XCTUnwrap(reloaded.timerState)
        XCTAssertEqual(timerState.startedAt, startedAt)
        XCTAssertEqual(timerState.pausedAt, pausedAt)
        XCTAssertEqual(timerState.accumulatedPauseSeconds, 45)
        XCTAssertEqual(timerState.targetDurationSeconds, 720)
        XCTAssertEqual(timerState.currentUnitIndex, 3)
    }

    func testWorkoutBlockTimerStateSurvivesRoundTripWhileRunning() throws {
        let blockID = UUID()
        let block = WorkoutBlock(id: blockID, type: .strength, status: .active)
        block.timerState = TimerState(startedAt: Date(timeIntervalSince1970: 1_800_000_000), targetDurationSeconds: 180)
        context.insert(block)
        try context.save()

        let fetchContext = freshContext()
        let reloaded = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<WorkoutBlock>(predicate: #Predicate { $0.id == blockID })).first)

        let timerState = try XCTUnwrap(reloaded.timerState)
        XCTAssertNil(timerState.pausedAt)
        XCTAssertEqual(timerState.accumulatedPauseSeconds, 0)
        XCTAssertNil(timerState.currentUnitIndex)
    }

    /// Two sibling blocks with different `TimerState`s — the same
    /// sibling-row diagnostic as the Session test above, one layer down.
    func testTwoSiblingBlocksWithDifferentTimerStatesBothSurviveRoundTrip() throws {
        let restID = UUID()
        let restBlock = WorkoutBlock(id: restID, type: .strength, status: .active)
        restBlock.timerState = TimerState(startedAt: Date(timeIntervalSince1970: 1_000), targetDurationSeconds: 180)
        context.insert(restBlock)

        let emomID = UUID()
        let emomBlock = WorkoutBlock(id: emomID, type: .functionalFitness, status: .active)
        emomBlock.timerState = TimerState(startedAt: Date(timeIntervalSince1970: 2_000), targetDurationSeconds: 60, currentUnitIndex: 4)
        context.insert(emomBlock)

        try context.save()

        let fetchContext = freshContext()
        let reloadedRest = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<WorkoutBlock>(predicate: #Predicate { $0.id == restID })).first)
        let reloadedEmom = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<WorkoutBlock>(predicate: #Predicate { $0.id == emomID })).first)

        XCTAssertEqual(reloadedRest.timerState?.currentUnitIndex, nil)
        XCTAssertEqual(reloadedEmom.timerState?.currentUnitIndex, 4)
        XCTAssertEqual(reloadedRest.timerState?.targetDurationSeconds, 180)
        XCTAssertEqual(reloadedEmom.timerState?.targetDurationSeconds, 60)
    }

    func testWorkoutBlockWithNoTimerStateDegradesGracefully() throws {
        let block = WorkoutBlock(type: .warmup, status: .pending)
        context.insert(block)
        try context.save()

        XCTAssertNil(block.timerState)
        XCTAssertNil(block.completionContext)
    }

    /// Slice 6: `ExercisePrescription.sourceExerciseSlot` survives a
    /// round trip, and deleting the slot's `ExerciseSlot` (simulating the
    /// slot's `ProgramDefinition` going away) nullifies the pointer
    /// rather than cascading away the movement it was materialized into —
    /// CLAUDE.md rule 1, mirroring `DeleteRuleMatrixTests`' own coverage
    /// for every other un-inversed-until-now reference in this graph.
    func testExercisePrescriptionSourceExerciseSlotSurvivesRoundTrip() throws {
        let slot = ExerciseSlot(name: "Horizontal Push")
        context.insert(slot)

        let prescriptionID = UUID()
        let prescription = ExercisePrescription(id: prescriptionID)
        prescription.sourceExerciseSlot = slot
        context.insert(prescription)
        try context.save()

        let fetchContext = freshContext()
        let reloaded = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<ExercisePrescription>(predicate: #Predicate { $0.id == prescriptionID })).first)

        XCTAssertEqual(reloaded.sourceExerciseSlot?.name, "Horizontal Push")
    }

    func testDeletingExerciseSlotNullifiesSourceExerciseSlotWithoutDeletingThePrescription() throws {
        let slot = ExerciseSlot(name: "Horizontal Push")
        context.insert(slot)

        let prescriptionID = UUID()
        let prescription = ExercisePrescription(id: prescriptionID)
        prescription.sourceExerciseSlot = slot
        context.insert(prescription)
        try context.save()

        context.delete(slot)
        try context.save()

        let fetchContext = freshContext()
        let reloaded = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<ExercisePrescription>(predicate: #Predicate { $0.id == prescriptionID })).first)

        XCTAssertNil(reloaded.sourceExerciseSlot)
    }

    /// Slice 7: the endurance siblings of `sourceExerciseSlot` — both
    /// `SteadyStatePrescription.sourceWorkoutBlockTemplate` and
    /// `IntervalPrescription.sourceWorkoutBlockTemplate` survive a round
    /// trip and nullify (never cascade away the materialized prescription)
    /// when their `WorkoutBlockTemplate` is deleted.
    func testSteadyStatePrescriptionSourceWorkoutBlockTemplateSurvivesRoundTrip() throws {
        let template = WorkoutBlockTemplate(type: .steadyState)
        context.insert(template)

        let prescriptionID = UUID()
        let prescription = SteadyStatePrescription(id: prescriptionID, activityType: .running)
        prescription.sourceWorkoutBlockTemplate = template
        context.insert(prescription)
        try context.save()

        let fetchContext = freshContext()
        let reloaded = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<SteadyStatePrescription>(predicate: #Predicate { $0.id == prescriptionID })).first)

        XCTAssertNotNil(reloaded.sourceWorkoutBlockTemplate)
    }

    func testDeletingWorkoutBlockTemplateNullifiesSteadyStateAndIntervalSourceTemplateWithoutDeletingThePrescriptions() throws {
        let steadyTemplate = WorkoutBlockTemplate(type: .steadyState)
        context.insert(steadyTemplate)
        let intervalTemplate = WorkoutBlockTemplate(type: .intervals)
        context.insert(intervalTemplate)

        let steadyID = UUID()
        let steadyPrescription = SteadyStatePrescription(id: steadyID, activityType: .running)
        steadyPrescription.sourceWorkoutBlockTemplate = steadyTemplate
        context.insert(steadyPrescription)

        let intervalID = UUID()
        let intervalPrescription = IntervalPrescription(id: intervalID, activityType: .running, intervalCount: 6)
        intervalPrescription.sourceWorkoutBlockTemplate = intervalTemplate
        context.insert(intervalPrescription)
        try context.save()

        context.delete(steadyTemplate)
        context.delete(intervalTemplate)
        try context.save()

        let fetchContext = freshContext()
        let reloadedSteady = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<SteadyStatePrescription>(predicate: #Predicate { $0.id == steadyID })).first)
        let reloadedInterval = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<IntervalPrescription>(predicate: #Predicate { $0.id == intervalID })).first)

        XCTAssertNil(reloadedSteady.sourceWorkoutBlockTemplate)
        XCTAssertNil(reloadedInterval.sourceWorkoutBlockTemplate)
    }
}
