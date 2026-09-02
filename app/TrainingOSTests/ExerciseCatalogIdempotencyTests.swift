import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 10R.7A-TX permanent regression coverage
/// (`STAGE10R7A_TX_ROOT_CAUSE_REPORT.md`): `ExerciseCatalog.resolveOrInsert`
/// (formerly `makeAndInsert`) used to construct a brand-new `Exercise` row
/// with a fixed `canonicalName` on every call — calling it twice against
/// the same store created colliding `canonicalName` rows that, once
/// referenced by a real `ExerciseSlot.resolvedExercise` relationship,
/// corrupted an unrelated `Exercise` row at save time (SwiftData's
/// `@Attribute(.unique)` conflict-merge had no inverse to correctly repair
/// the relationship through). These tests prove the fixed, idempotent
/// resolve-by-`canonicalName` behavior directly — they are the permanent
/// successors to the investigation's throwaway `ZZZScratchInvestigationTests`
/// probes, not exploratory diagnostics.
@MainActor
final class ExerciseCatalogIdempotencyTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    // MARK: 1 — first resolution inserts exactly one canonical row per exercise

    func testFirstResolutionInsertsExactlyOneRowPerCanonicalName() throws {
        _ = ExerciseCatalog.resolveOrInsert(context: context)
        try context.save()

        let all = try context.fetch(FetchDescriptor<Exercise>())
        let namesSeen = Set(all.map(\.canonicalName))
        XCTAssertEqual(all.count, namesSeen.count, "every canonicalName must back exactly one Exercise row after a single resolution")
        XCTAssertGreaterThan(all.count, 30, "sanity check: the real catalog has dozens of distinct exercises")
    }

    // MARK: 2/3 — second resolution against the same store never creates duplicates or triggers the uniqueness conflict

    func testSecondResolutionAgainstTheSameStoreCreatesNoDuplicateCanonicalExercises() throws {
        _ = ExerciseCatalog.resolveOrInsert(context: context)
        try context.save()
        let countAfterFirst = try context.fetchCount(FetchDescriptor<Exercise>())

        _ = ExerciseCatalog.resolveOrInsert(context: context)
        try context.save()
        let countAfterSecond = try context.fetchCount(FetchDescriptor<Exercise>())

        XCTAssertEqual(countAfterFirst, countAfterSecond, "a second resolution against the same store must never insert a duplicate canonical Exercise")

        let all = try context.fetch(FetchDescriptor<Exercise>())
        let broken = all.filter { $0.canonicalName.isEmpty }
        XCTAssertTrue(broken.isEmpty, "normal repeated resolution must never leave a corrupted (nil-required-field) Exercise row behind")
    }

    // MARK: 4 — repeated resolution returns the SAME persistent identity

    func testRepeatedResolutionReturnsTheSamePersistentIdentityForACanonicalExercise() throws {
        let first = ExerciseCatalog.resolveOrInsert(context: context)
        try context.save()
        let firstBackSquatID = first.backSquat.persistentModelID

        let second = ExerciseCatalog.resolveOrInsert(context: context)
        try context.save()
        let secondBackSquatID = second.backSquat.persistentModelID

        XCTAssertEqual(firstBackSquatID, secondBackSquatID, "resolving the catalog twice must return the identical persisted Exercise for the same canonicalName, not a second row")
    }

    // MARK: 9/10 — the decisive real production-shaped reproduction now passes

    /// Formerly `ZZZScratchInvestigationTests.testRung0e_...` — the exact
    /// real production call sequence (`ExerciseCatalog.resolveOrInsert` ->
    /// `AcceptStrategicPlanUseCase.accept` -> `StartPhaseUseCase.start`),
    /// run twice against one store, `TransitionPhaseUseCase` never
    /// invoked. This was the decisive proof the root-cause investigation
    /// used to rule out the scratch-context architecture entirely; now
    /// that the catalog is idempotent and `resolvedExercise` has a real
    /// inverse, it must pass cleanly.
    func testTwoSequentialStartPhaseRunsAgainstIndependentPlanGraphsInOneStoreNeverCorruptExerciseRelationships() throws {
        func runOneStartPhaseOnly(userLabel: String) throws {
            let user = User(displayName: userLabel)
            context.insert(user)
            let profile = PerformanceProfile()
            context.insert(profile)
            user.attachPerformanceProfile(profile)
            let catalog = ExerciseCatalog.resolveOrInsert(context: context)

            let goal = Goal(ownerUserID: user.id, primaryType: .muscleGain, targetDate: nil, createdAt: Date(timeIntervalSince1970: 0))
            context.insert(goal)
            user.addGoal(goal)
            let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: Date(timeIntervalSince1970: 0))
            let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: Date(timeIntervalSince1970: 0))
            let phase1 = plan.orderedPhases[0]

            let availability = UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1)
            let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)
            let strengthCandidates = [catalog.backSquat, catalog.benchPress, catalog.romanianDeadlift, catalog.legPress]
            let materializationContext = TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: strengthCandidates, functionalFitnessCandidateExercises: [], trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context))
            let phase1Candidates = LongTermPlanner.proposeTrainingMix(phase: phase1, goal: goal)
            guard let mix1 = phase1Candidates.first else { throw SeedAnnualPlanJourneyError.noMixCandidates }
            try StartPhaseUseCase.start(
                phase: phase1, mix: mix1.mix, asOf: Date(timeIntervalSince1970: 0), ownerUserID: user.id,
                performanceProfile: profile, availability: availability,
                materializationContext: materializationContext, context: context
            )
            try context.save()
        }

        try runOneStartPhaseOnly(userLabel: "First independent plan graph")
        try runOneStartPhaseOnly(userLabel: "Second independent plan graph")

        let all = try context.fetch(FetchDescriptor<Exercise>())
        let broken = all.filter { $0.canonicalName.isEmpty }
        XCTAssertTrue(broken.isEmpty, "two sequential StartPhaseUseCase runs against independent plan graphs in one store must never corrupt an Exercise row")

        let backSquatRows = all.filter { $0.canonicalName == "Back Squat" }
        XCTAssertEqual(backSquatRows.count, 1, "both independent runs must resolve to the SAME canonical Back Squat row, never a duplicate")
    }
}
