import XCTest
import SwiftData
@testable import TrainingOS

/// Verifies the single-side ownership convention actually works the way
/// CLAUDE.md and DELETE_RULE_MATRIX.md say it does: every `addX`/`attachX`
/// method mutates exactly one side of a relationship, and SwiftData is
/// trusted to maintain the inverse — never assumed to, always checked.
@MainActor
final class RelationshipOwnershipTests: XCTestCase {
    func testAddingOneBlockProducesExactlyOneRelationshipEntryBothWays() {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext

        let session = Session(name: "Test Session", modality: .strength)
        context.insert(session)

        let block = WorkoutBlock(type: .strength)
        context.insert(block)

        // addBlock touches only `session.blocks`. It never sets
        // `block.session` — that must come from SwiftData's inverse sync.
        session.addBlock(block)

        XCTAssertEqual(session.blocks.count, 1)
        XCTAssertEqual(session.orderedBlocks.count, 1)
        XCTAssertTrue(session.blocks.first === block)
        XCTAssertTrue(block.session === session, "SwiftData did not maintain the inverse from a single-sided append.")
    }

    func testAddingSeveralBlocksNeverDuplicatesEntries() {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext
        let session = Session(name: "Test", modality: .strength)
        context.insert(session)

        for _ in 0..<5 {
            let block = WorkoutBlock(type: .strength)
            context.insert(block)
            session.addBlock(block)
        }

        XCTAssertEqual(session.blocks.count, 5)
        XCTAssertEqual(Set(session.blocks.map(\.id)).count, 5, "Every block should be a distinct entry — no duplicates from inverse-sync plus manual append.")
    }

    func testOrderedBlocksSurviveSaveAndRefetchInDeterministicOrder() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext

        let sessionID = UUID()
        let session = Session(id: sessionID, name: "Ordered", modality: .strength)
        context.insert(session)

        let types: [WorkoutBlockType] = [.warmup, .strength, .accessory, .cooldown]
        for type in types {
            let block = WorkoutBlock(type: type)
            context.insert(block)
            session.addBlock(block)
        }

        try context.save()

        // A fresh ModelContext on the same container reads through the
        // persistent store rather than the in-memory objects above — the
        // closest in-process approximation of "quit and relaunch the app."
        let reloadContext = ModelContext(container)
        let reloaded = try XCTUnwrap(
            reloadContext.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionID })).first
        )

        XCTAssertEqual(reloaded.orderedBlocks.map(\.type), types, "Block order must come from sortIndex, not collection order.")
        XCTAssertEqual(reloaded.orderedBlocks.map(\.sortIndex), [0, 1, 2, 3])
    }

    func testDayOrderedSessionsSurviveSaveAndRefetch() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext

        let dayID = UUID()
        let day = Day(id: dayID, ownerUserID: UUID(), date: Date())
        context.insert(day)

        let names = ["Morning", "Midday", "Evening"]
        for name in names {
            let session = Session(name: name, modality: .strength)
            context.insert(session)
            day.addSession(session)
        }

        try context.save()

        let reloadContext = ModelContext(container)
        let reloaded = try XCTUnwrap(
            reloadContext.fetch(FetchDescriptor<Day>(predicate: #Predicate { $0.id == dayID })).first
        )

        XCTAssertEqual(reloaded.orderedSessions.map(\.name), names)
        XCTAssertEqual(reloaded.orderedSessions.map(\.sortIndex), [0, 1, 2])
    }

    func testExercisePrescriptionOrderingSurvivesSaveAndRefetch() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext

        let blockID = UUID()
        let block = WorkoutBlock(id: blockID, type: .amrap)
        context.insert(block)

        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        for exercise in [catalog.wallBall, catalog.pullUp, catalog.burpee] {
            let movement = ExercisePrescription(exercise: exercise)
            context.insert(movement)
            block.addPrescription(movement)
        }

        try context.save()

        let reloadContext = ModelContext(container)
        let reloaded = try XCTUnwrap(
            reloadContext.fetch(FetchDescriptor<WorkoutBlock>(predicate: #Predicate { $0.id == blockID })).first
        )

        XCTAssertEqual(
            reloaded.orderedPrescriptions.compactMap { $0.exercise?.canonicalName },
            ["Wall Ball", "Pull-up", "Burpee"]
        )
    }

    func testSetPrescriptionOrderingSurvivesSaveAndRefetch() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext

        let movementID = UUID()
        let movement = ExercisePrescription(id: movementID)
        context.insert(movement)

        for weight in [40.0, 50.0, 60.0] {
            let prescription = SetPrescription(repRangeLow: 5, repRangeHigh: 8, targetWeight: weight)
            context.insert(prescription)
            movement.addSetPrescription(prescription)
        }

        try context.save()

        let reloadContext = ModelContext(container)
        let reloaded = try XCTUnwrap(
            reloadContext.fetch(FetchDescriptor<ExercisePrescription>(predicate: #Predicate { $0.id == movementID })).first
        )

        XCTAssertEqual(reloaded.orderedSetPrescriptions.map(\.targetWeight), [40.0, 50.0, 60.0])
        XCTAssertEqual(reloaded.orderedSetPrescriptions.map(\.sortIndex), [0, 1, 2])
    }

    func testAttachingWorkoutResultEstablishesInverseWithoutManualAssignment() {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext

        let block = WorkoutBlock(type: .forTime, timeCapSeconds: 600)
        context.insert(block)
        let result = WorkoutResult(type: .forTime, scoringDirection: .lowerIsBetter, elapsedSeconds: 200)
        context.insert(result)

        // attachResult touches only `block.result`, never `result.workoutBlock`.
        block.attachResult(result)

        XCTAssertTrue(block.result === result)
        XCTAssertTrue(result.workoutBlock === block, "SwiftData did not maintain the to-one inverse from a single-sided assignment.")
    }

    func testProgramInstanceAddSessionEstablishesInverseWithoutManualAssignment() {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext

        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        let session = Session(name: "Instance-owned", modality: .strength)
        context.insert(session)

        instance.addSession(session)

        XCTAssertEqual(instance.sessions.count, 1)
        XCTAssertTrue(session.programInstance === instance)
    }

    // MARK: Stage 10R.7A-TX — `ExerciseSlot.resolvedExercise` <-> `Exercise.resolvedSlots`

    /// Assigning `slot.resolvedExercise` (the documented, single-sided
    /// convention every other relationship in this file follows) must
    /// maintain `Exercise.resolvedSlots` from the declared inverse —
    /// exactly like `block.session`/`result.workoutBlock` above. Before
    /// Stage 10R.7A-TX, `resolvedExercise` had no inverse at all, which is
    /// what let SwiftData's `canonicalName` uniqueness-conflict merge
    /// corrupt an unrelated row instead of cleanly repairing the
    /// relationship (`STAGE10R7A_TX_ROOT_CAUSE_REPORT.md`).
    func testAssigningResolvedExerciseEstablishesInverseWithoutManualAssignment() {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext

        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let slot = ExerciseSlot(name: "Squat Slot")
        context.insert(slot)

        slot.resolvedExercise = catalog.backSquat

        XCTAssertTrue(catalog.backSquat.resolvedSlots.contains { $0 === slot }, "SwiftData did not maintain Exercise.resolvedSlots from a single-sided resolvedExercise assignment.")
    }

    /// Item 6 — many `ExerciseSlot`s legitimately share one canonical
    /// `Exercise`; that's the entire point of a canonical catalog, and
    /// must never be treated as a conflict.
    func testMultipleExerciseSlotsCanReferenceTheSameCanonicalExercise() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext

        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let slots = (0..<3).map { ExerciseSlot(name: "Squat Slot \($0)") }
        for slot in slots {
            context.insert(slot)
            slot.resolvedExercise = catalog.backSquat
        }
        try context.save()

        XCTAssertEqual(catalog.backSquat.resolvedSlots.count, 3, "all three slots must be reflected on the shared Exercise's inverse collection")

        let all = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(all.filter { $0.canonicalName == "Back Squat" }.count, 1, "sharing one Exercise across slots must never duplicate the canonical row")
    }

    /// Item 7 — deleting a slot must never cascade into deleting the
    /// shared canonical Exercise it resolved to (`.nullify`, never
    /// `.cascade` — canonical Exercise data is shared catalog data, not
    /// owned by any one slot; see `DELETE_RULE_MATRIX.md`).
    func testDeletingASlotDoesNotDeleteTheSharedCanonicalExercise() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext

        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let keepSlot = ExerciseSlot(name: "Kept Slot")
        context.insert(keepSlot)
        keepSlot.resolvedExercise = catalog.backSquat
        let deleteSlot = ExerciseSlot(name: "Deleted Slot")
        context.insert(deleteSlot)
        deleteSlot.resolvedExercise = catalog.backSquat
        try context.save()

        context.delete(deleteSlot)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertTrue(all.contains { $0.canonicalName == "Back Squat" }, "deleting an ExerciseSlot must never delete the shared canonical Exercise it resolved to")
        XCTAssertTrue(keepSlot.resolvedExercise === catalog.backSquat, "the surviving slot's own resolvedExercise must be unaffected by a sibling slot's deletion")
    }

    /// Item 8 — a historical `ExerciseSlot.resolvedExercise` reference
    /// must survive a save + fresh-context refetch (the closest in-process
    /// approximation of "quit and relaunch the app," same convention as
    /// every other survives-refetch test in this file).
    func testHistoricalResolvedExerciseReferenceSurvivesSaveAndRefetch() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext

        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let slotID = UUID()
        let slot = ExerciseSlot(id: slotID, name: "Historical Slot")
        context.insert(slot)
        slot.resolvedExercise = catalog.backSquat
        try context.save()

        let reloadContext = ModelContext(container)
        let reloaded = try XCTUnwrap(
            reloadContext.fetch(FetchDescriptor<ExerciseSlot>(predicate: #Predicate { $0.id == slotID })).first
        )

        XCTAssertEqual(reloaded.resolvedExercise?.canonicalName, "Back Squat", "a historical slot's resolvedExercise must remain valid after save + relaunch-equivalent refetch")
    }
}
