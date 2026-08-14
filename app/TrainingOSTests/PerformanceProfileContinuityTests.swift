import XCTest
import SwiftData
@testable import TrainingOS

/// The core invariant this pass exists to prove: performance history is
/// permanent and belongs to the ExercisePerformanceProfile, never to a
/// ProgramDefinition or ProgramInstance. Ending a program, starting a new
/// one, or even deleting the old program outright must never touch it.
final class PerformanceProfileContinuityTests: XCTestCase {
    func testBenchPressHistorySurvivesProgramTransition() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext
        let seed = SeedDataProvider.seedAll(in: context)

        let benchProfile = try XCTUnwrap(seed.performanceProfile.profile(for: seed.catalog.benchPress))

        // "Push Day" (3 sets) ran under Program A; "Full Body A" (3 sets)
        // ran under Program B, after Program A had already completed.
        XCTAssertEqual(benchProfile.setResults.count, 6)

        let instanceIDsBehindTheseResults = Set(
            benchProfile.setResults.compactMap { $0.exercisePrescription?.workoutBlock?.session?.programInstance?.id }
        )
        XCTAssertEqual(instanceIDsBehindTheseResults, [seed.programInstanceA.id, seed.programInstanceB.id])

        XCTAssertEqual(seed.programInstanceA.status, .completed)
        XCTAssertEqual(seed.programInstanceB.status, .active)
    }

    /// A structural guard, not a behavioural one: fails loudly if
    /// ProgramDefinition ever grows a field that looks like performance
    /// data, since that would silently violate the invariant above.
    func testProgramDefinitionExposesNoPerformanceLookingFields() {
        let definition = ProgramDefinition(name: "Structural check", lengthWeeks: 1)
        let suspiciousFields = Mirror(reflecting: definition).children
            .compactMap { $0.label }
            .filter { $0.lowercased().contains("result") || $0.lowercased().contains("record") || $0.lowercased().contains("performance") }

        XCTAssertTrue(
            suspiciousFields.isEmpty,
            "ProgramDefinition gained fields that look like performance data: \(suspiciousFields)"
        )
    }

    func testDeletingProgramDefinitionAndInstanceNeverDeletesLoggedHistory() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext
        let seed = SeedDataProvider.seedAll(in: context)

        let benchProfile = try XCTUnwrap(seed.performanceProfile.profile(for: seed.catalog.benchPress))
        let benchProfileID = benchProfile.id
        let setCountBeforeDeletion = benchProfile.setResults.count

        context.delete(seed.programDefinitionA)
        context.delete(seed.programInstanceA)
        try context.save()

        let profiles = try context.fetch(FetchDescriptor<ExercisePerformanceProfile>())
        let survivingProfile = try XCTUnwrap(profiles.first { $0.id == benchProfileID })
        XCTAssertEqual(
            survivingProfile.setResults.count,
            setCountBeforeDeletion,
            "Deleting a ProgramDefinition/ProgramInstance must never delete logged history."
        )

        let sessions = try context.fetch(FetchDescriptor<Session>())
        XCTAssertTrue(
            sessions.contains { $0.name == "Push Day" },
            "The Session that logged the history must also survive the ProgramInstance's deletion."
        )
        XCTAssertNil(
            sessions.first { $0.name == "Push Day" }?.programInstance,
            "The nullify relationship should clear the dangling reference, not cascade the delete."
        )
    }
}
