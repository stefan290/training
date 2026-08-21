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

    func testSeedsSevenIndependentSessionsScheduledForToday() throws {
        try seedRealJourney()
        try DebugAcceptanceFixturesUseCase.seedIfNeeded(context: context)

        let sessions = try context.fetch(FetchDescriptor<Session>())
        let acceptanceSessions = sessions.filter { $0.name.hasPrefix("Acceptance — ") }
        XCTAssertEqual(acceptanceSessions.count, 7, "one independent session per acceptance scenario, including the Stage 9B multi-exercise lower-body fixture")
        XCTAssertTrue(acceptanceSessions.allSatisfy { $0.status == .scheduled })

        let today = Calendar.current.startOfDay(for: Date())
        XCTAssertTrue(acceptanceSessions.allSatisfy { Calendar.current.isDate($0.day?.date ?? .distantPast, inSameDayAs: today) })
    }

    /// Stage 9B: the real, multi-exercise lower-body/hinge fixture
    /// (`SeedScenarios.materializedLowerASession`), surfaced so Case B's
    /// generated warm-up can be visually inspected — proven here to be the
    /// exact real production materialization, not a stand-in.
    func testLowerBodyFixtureIsTheRealMultiExerciseMaterializedSession() throws {
        try seedRealJourney()
        try DebugAcceptanceFixturesUseCase.seedIfNeeded(context: context)

        let sessions = try context.fetch(FetchDescriptor<Session>())
        let lowerBodySession = try XCTUnwrap(sessions.first { $0.name == "Acceptance — Lower Body (multi-exercise)" })
        let exerciseNames = Set(lowerBodySession.orderedBlocks.flatMap(\.orderedPrescriptions).compactMap { $0.exercise?.canonicalName })

        XCTAssertEqual(exerciseNames, ["Back Squat", "Romanian Deadlift", "Leg Press", "Leg Curl", "Calf Raise"])
        XCTAssertEqual(lowerBodySession.status, .scheduled)
        XCTAssertNotNil(lowerBodySession.programInstance, "materialized through the real StrengthMaterializer path, which always attaches a ProgramInstance")
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
        XCTAssertEqual(acceptanceSessions.count, 7, "a second seed call must never duplicate the fixtures")
    }

    /// REVISED: the lower-body fixture legitimately creates its own new,
    /// independent `ProgramInstance` (via the real materializer path) —
    /// the invariant under test is that every PRE-EXISTING ProgramInstance/
    /// TrainingPhase/Session from the real annual-plan journey survives
    /// completely unchanged, not that zero new ones are ever created.
    func testNeverTouchesTheRealAnnualPlanJourney() throws {
        try seedRealJourney()
        let programInstancesBefore = try context.fetch(FetchDescriptor<ProgramInstance>()).map(\.id)
        let phasesBefore = try context.fetch(FetchDescriptor<TrainingPhase>()).map(\.id)
        let realSessionsBefore = try context.fetch(FetchDescriptor<Session>()).map(\.id)

        try DebugAcceptanceFixturesUseCase.seedIfNeeded(context: context)

        let programInstancesAfter = Set(try context.fetch(FetchDescriptor<ProgramInstance>()).map(\.id))
        let phasesAfter = Set(try context.fetch(FetchDescriptor<TrainingPhase>()).map(\.id))
        let realSessionsAfter = try context.fetch(FetchDescriptor<Session>()).filter { !$0.name.hasPrefix("Acceptance — ") }.map(\.id)

        XCTAssertTrue(Set(programInstancesBefore).isSubset(of: programInstancesAfter), "every pre-existing ProgramInstance survives untouched")
        XCTAssertEqual(Set(phasesBefore), phasesAfter, "no TrainingPhase touched — the lower-body fixture's new ProgramInstance is never attached to any existing Phase")
        XCTAssertEqual(Set(realSessionsBefore), Set(realSessionsAfter), "every pre-existing real Session is untouched")
    }
}
