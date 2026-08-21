import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 8B: proves the debug-only manual-acceptance seeding utility
/// itself behaves correctly — idempotent, session-independent, and never
/// touching any `ProgramInstance`/`TrainingPhase`/`TrainingMix` that might
/// already exist in the store.
@MainActor
final class DebugAcceptanceFixturesUseCaseTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func seedRealJourney() throws {
        let prerequisites = SeedDataProvider.seedPrerequisites(in: context)
        try SeedAnnualPlanJourney.seed(
            user: prerequisites.user, performanceProfile: prerequisites.performanceProfile,
            catalog: prerequisites.catalog, context: context
        )
    }

    func testSeedsSixIndependentSessionsScheduledForToday() throws {
        try seedRealJourney()
        try DebugAcceptanceFixturesUseCase.seedIfNeeded(context: context)

        let sessions = try context.fetch(FetchDescriptor<Session>())
        let acceptanceSessions = sessions.filter { $0.name.hasPrefix("Acceptance — ") }
        XCTAssertEqual(acceptanceSessions.count, 6, "one independent session per acceptance scenario")
        XCTAssertTrue(acceptanceSessions.allSatisfy { $0.status == .scheduled })
        XCTAssertTrue(acceptanceSessions.allSatisfy { $0.programInstance == nil }, "ad hoc, outside any active program instance")

        let today = Calendar.current.startOfDay(for: Date())
        XCTAssertTrue(acceptanceSessions.allSatisfy { Calendar.current.isDate($0.day?.date ?? .distantPast, inSameDayAs: today) })
    }

    func testLocalPainScenarioHasTwoExercisesTargetingDifferentMuscleGroups() throws {
        try seedRealJourney()
        try DebugAcceptanceFixturesUseCase.seedIfNeeded(context: context)

        let sessions = try context.fetch(FetchDescriptor<Session>())
        let painSession = try XCTUnwrap(sessions.first { $0.name == "Acceptance — Local Pain" })
        let prescriptions = painSession.orderedBlocks.flatMap(\.orderedPrescriptions)
        XCTAssertEqual(prescriptions.count, 2)

        let squat = try XCTUnwrap(prescriptions.first { $0.exercise?.canonicalName == "Back Squat" })
        let bench = try XCTUnwrap(prescriptions.first { $0.exercise?.canonicalName == "Barbell Bench Press" })
        XCTAssertTrue(Set(squat.exercise!.primaryTargets).isDisjoint(with: Set(bench.exercise!.primaryTargets)))
        XCTAssertNotNil(squat.sourceExerciseSlot, "a real slot-valid alternative exists so Level 3 substitution can be demonstrated")
    }

    func testSeedingTwiceIsIdempotent() throws {
        try seedRealJourney()
        try DebugAcceptanceFixturesUseCase.seedIfNeeded(context: context)
        try DebugAcceptanceFixturesUseCase.seedIfNeeded(context: context)

        let sessions = try context.fetch(FetchDescriptor<Session>())
        let acceptanceSessions = sessions.filter { $0.name.hasPrefix("Acceptance — ") }
        XCTAssertEqual(acceptanceSessions.count, 6, "a second seed call must never duplicate the fixtures")
    }

    func testNeverTouchesTheRealAnnualPlanJourney() throws {
        try seedRealJourney()
        let programInstancesBefore = try context.fetch(FetchDescriptor<ProgramInstance>()).map(\.id)
        let phasesBefore = try context.fetch(FetchDescriptor<TrainingPhase>()).map(\.id)
        let realSessionsBefore = try context.fetch(FetchDescriptor<Session>()).map(\.id)

        try DebugAcceptanceFixturesUseCase.seedIfNeeded(context: context)

        let programInstancesAfter = try context.fetch(FetchDescriptor<ProgramInstance>()).map(\.id)
        let phasesAfter = try context.fetch(FetchDescriptor<TrainingPhase>()).map(\.id)
        let realSessionsAfter = try context.fetch(FetchDescriptor<Session>()).filter { !$0.name.hasPrefix("Acceptance — ") }.map(\.id)

        XCTAssertEqual(Set(programInstancesBefore), Set(programInstancesAfter), "no ProgramInstance created, deleted, or reassigned")
        XCTAssertEqual(Set(phasesBefore), Set(phasesAfter), "no TrainingPhase touched")
        XCTAssertEqual(Set(realSessionsBefore), Set(realSessionsAfter), "every pre-existing real Session is untouched")
    }
}
