import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 10R.1C crash investigation: reproduces the real production
/// persistence path (on-disk `ModelConfiguration`, exactly like
/// `PersistenceController.makeAppContainer()`) rather than the in-memory
/// configuration every other test uses — the manual Simulator crash was
/// reported only against a fresh on-disk install, never observed in the
/// in-memory test suite, so this isolates whether the two configurations
/// actually behave differently for the new `SourceRMCalibration` type.
@MainActor
final class SourceRMCalibrationOnDiskReproTests: XCTestCase {
    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("repro-\(UUID().uuidString).store")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeURL)
    }

    private func makeOnDiskContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: PersistenceController.schema, url: storeURL)
        return try ModelContainer(for: PersistenceController.schema, configurations: [configuration])
    }

    func testInsertingASourceRMCalibrationIntoARealOnDiskContainerSucceeds() throws {
        let container = try makeOnDiskContainer()
        let context = container.mainContext

        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 3, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "on-disk repro"), context: context
        )
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition
        _ = catalog

        let exercise = try XCTUnwrap(definition.orderedTemplateSessions.first?.orderedBlockTemplates.first?.orderedPrescriptionTemplates.first?.exerciseSlot?.resolvedExercise)

        RecordSourceRMCalibrationUseCase.record(exercise: exercise, rmType: .rm10, kilograms: 80, for: instance, modelContext: context)
        try context.save()

        // Re-open a FRESH container against the SAME store file — exactly
        // what a relaunch does — and confirm the calibration survives.
        let reopened = try ModelContainer(for: PersistenceController.schema, configurations: [ModelConfiguration(schema: PersistenceController.schema, url: storeURL)])
        let reopenedCalibrations = try reopened.mainContext.fetch(FetchDescriptor<SourceRMCalibration>())
        XCTAssertEqual(reopenedCalibrations.count, 1, "the calibration must survive a real on-disk save + container reopen")
        XCTAssertEqual(reopenedCalibrations.first?.kilograms, 80)
    }

    /// Faithfully reproduces the real reported flow: fresh on-disk store
    /// (exactly `TrainingOSApp.init()`'s first-launch path) -> real
    /// `SeedAnnualPlanJourney` (creates the awaiting-calibration Hypertrophy
    /// component exactly as the real app does) -> the exact ViewModel
    /// sequence a user tapping through "Set your starting weights" and
    /// "Start Program" triggers -> a fresh reopen simulating relaunch.
    func testRealSeedJourneyThenCalibrationCompletionOnDiskMatchesTheReportedFlow() throws {
        let container = try makeOnDiskContainer()
        let context = container.mainContext

        let user = User(displayName: "Test User")
        context.insert(user)
        let profile = PerformanceProfile()
        context.insert(profile)
        user.attachPerformanceProfile(profile)
        let userProfile = UserProfile()
        context.insert(userProfile)
        user.attachProfile(userProfile)
        let fullGym = TrainingEnvironment(name: "Test Full Gym", availableEquipment: EquipmentRequirement.allCases)
        context.insert(fullGym)
        userProfile.trainingEnvironments = [fullGym]
        userProfile.defaultTrainingEnvironment = fullGym
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        try context.save()

        let journey = try SeedAnnualPlanJourney.seed(user: user, performanceProfile: profile, catalog: catalog, context: context)
        try context.save()

        let viewModel = SourceRMCalibrationViewModel()
        viewModel.load(modelContext: context)
        XCTAssertTrue(viewModel.hasPendingCalibration, "sanity: the real seed journey must leave the Hypertrophy component awaiting calibration")
        let requiredCount = viewModel.rows.count
        XCTAssertGreaterThan(requiredCount, 0)

        for index in viewModel.rows.indices {
            viewModel.rows[index].enteredText = "100"
        }
        XCTAssertTrue(viewModel.allSatisfied)

        viewModel.completeCalibrationAndStart(modelContext: context)
        try context.save()

        XCTAssertFalse(viewModel.hasPendingCalibration, "materialization must have consumed the requirement")
        let instance = try XCTUnwrap(journey.activePhase.primaryInstance)
        XCTAssertFalse(instance.sessions.isEmpty, "Week 1 must be materialized after calibration completes")
        let instanceID = instance.id

        // Simulate relaunch: a brand-new container/context against the SAME file.
        let reopened = try ModelContainer(for: PersistenceController.schema, configurations: [ModelConfiguration(schema: PersistenceController.schema, url: storeURL)])
        let reopenedCalibrations = try reopened.mainContext.fetch(FetchDescriptor<SourceRMCalibration>())
        XCTAssertEqual(reopenedCalibrations.count, requiredCount, "every entered calibration must survive relaunch")
        // Matched by the exact instance this test operated on, not just
        // "the first Hypertrophy instance" — the real seed journey's
        // completed Phase 1 is ALSO a Hypertrophy instance, so an
        // unordered "first" match is genuinely ambiguous between the two.
        let reopenedInstances = try reopened.mainContext.fetch(FetchDescriptor<ProgramInstance>())
        let reopenedHypertrophyInstance = try XCTUnwrap(reopenedInstances.first { $0.id == instanceID })
        XCTAssertFalse(reopenedHypertrophyInstance.sessions.isEmpty, "materialized sessions must survive relaunch too")
    }
}
