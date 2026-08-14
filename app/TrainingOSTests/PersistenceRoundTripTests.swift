import XCTest
import SwiftData
@testable import TrainingOS

/// End-to-end: seed the full dataset, save, open a brand new ModelContext
/// on the same container (the closest in-process approximation of quitting
/// and relaunching the app), and walk the graph back from just a User ID —
/// the way the real app would after a cold start. Complements
/// RelationshipOwnershipTests (which isolates one relationship at a time)
/// with a single realistic, whole-graph check.
@MainActor
final class PersistenceRoundTripTests: XCTestCase {
    func testFullSeededGraphSurvivesSaveAndRefetch() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext
        let seed = SeedDataProvider.seedAll(in: context)
        let userID = seed.user.id

        try context.save()

        let reloadContext = ModelContext(container)
        let reloadedUser = try XCTUnwrap(
            reloadContext.fetch(FetchDescriptor<User>(predicate: #Predicate { $0.id == userID })).first
        )

        // User -> Profile / PerformanceProfile (to-one/to-one) survive.
        XCTAssertNotNil(reloadedUser.profile)
        let performanceProfile = try XCTUnwrap(reloadedUser.performanceProfile)

        // User -> Goals -> Plans -> ordered Phases.
        let goal = try XCTUnwrap(reloadedUser.goals.first)
        let plan = try XCTUnwrap(goal.plans.first)
        XCTAssertEqual(plan.orderedPhases.count, 2)
        XCTAssertEqual(plan.orderedPhases.map(\.sortIndex), [0, 1])
        XCTAssertEqual(plan.orderedPhases.first?.status, .completed)
        XCTAssertEqual(plan.orderedPhases.last?.status, .active)

        // Phase -> ProgramInstance -> ProgramDefinition -> ordered Weeks.
        let phaseA = plan.orderedPhases[0]
        let instanceA = try XCTUnwrap(phaseA.programInstances.first)
        let definitionA = try XCTUnwrap(instanceA.programDefinition)
        XCTAssertEqual(definitionA.orderedWeeks.count, 8)
        XCTAssertEqual(definitionA.orderedWeeks.map(\.sortIndex), Array(0..<8))
        XCTAssertEqual(definitionA.orderedWeeks.filter(\.isDeload).count, 1)

        // Permanent history: Bench Press spans both instances, ordered
        // chronologically, independent of any program.
        let benchProfile = try XCTUnwrap(performanceProfile.profile(for: seed.catalog.benchPress))
        XCTAssertEqual(benchProfile.setResults.count, 6)
        let chronological = benchProfile.orderedSetResults
        XCTAssertEqual(chronological.first?.completedAt, chronological.map(\.completedAt).min())
        XCTAssertEqual(chronological.last?.completedAt, chronological.map(\.completedAt).max())

        // Today: exactly the two scheduled sessions, in the order they
        // were added, each with its ordered block/prescription chain intact.
        let days = try reloadContext.fetch(FetchDescriptor<Day>())
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let today = try XCTUnwrap(days.first { Calendar.current.isDate($0.date, inSameDayAs: startOfToday) })
        XCTAssertEqual(today.orderedSessions.map(\.name), ["Lower A", "Evening Zone 2"])

        let lowerA = today.orderedSessions[0]
        let strengthBlock = try XCTUnwrap(lowerA.orderedBlocks.first)
        let squatMovement = try XCTUnwrap(strengthBlock.orderedPrescriptions.first)
        XCTAssertEqual(squatMovement.exercise?.canonicalName, "Back Squat")
        XCTAssertEqual(squatMovement.orderedSetPrescriptions.map(\.sortIndex), [0, 1, 2])

        // The hybrid session's two differently-typed blocks kept their
        // relative order through the round trip.
        let sessions = try reloadContext.fetch(FetchDescriptor<Session>())
        let hybrid = try XCTUnwrap(sessions.first { $0.name == "Strength + Metcon" })
        XCTAssertEqual(hybrid.orderedBlocks.map(\.type), [.strength, .amrap])
    }
}
