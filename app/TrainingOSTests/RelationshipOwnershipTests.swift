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

        let catalog = ExerciseCatalog.makeAndInsert(context: context)
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
}
