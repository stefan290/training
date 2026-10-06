import XCTest
import SwiftData
@testable import TrainingOS

/// Dogfood Round 2 Continuation (Finding I): real simulator dogfooding
/// found a brand-new athlete is never actually asked about Training
/// Environment — `AppRootStateResolver.ensureBaselineIdentity` auto-seeds
/// Full Gym as the default the moment baseline identity exists, and
/// `OnboardingViewModel` used to treat that existing default alone as
/// license to skip the Environment step entirely. These tests cover the
/// fix: `UserProfile.hasConfirmedTrainingEnvironment` is now a real,
/// separate signal from "a default exists," and the Environment step is
/// shown at least once until the athlete actually advances past it.
@MainActor
final class DogfoodRound2ContinuationFindingITests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    /// The core Finding I regression guard: a genuinely fresh athlete must
    /// see the Environment step before Review, even though Full Gym
    /// already exists as a real default the instant baseline identity is
    /// created — never silently skipped just because a default exists.
    func testFreshAthleteMustExplicitlyAcceptEnvironmentBeforeReview() throws {
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .muscleGain
        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)

        XCTAssertEqual(viewModel.step, .environment, "a default existing alone must never skip this step")
        XCTAssertTrue(viewModel.hasDefaultTrainingEnvironment)
        XCTAssertFalse(viewModel.hasConfirmedTrainingEnvironment, "existing but not yet explicitly accepted")

        viewModel.advance(from: .environment, modelContext: context)
        XCTAssertEqual(viewModel.step, .review)
        XCTAssertTrue(viewModel.hasConfirmedTrainingEnvironment)
    }

    /// An athlete who changes their environment away from Full Gym during
    /// this step must have THAT real, chosen environment — not the
    /// silently auto-seeded one — reach the first real materialization at
    /// plan acceptance.
    func testChangedEnvironmentDuringOnboardingReachesFirstMaterialization() throws {
        let monday = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 0))!
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .generalStrength
        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)
        XCTAssertEqual(viewModel.step, .environment)

        // Simulate the athlete creating and selecting a real custom
        // environment during this step — exactly what
        // `TrainingEnvironmentSettingsView`'s own real "Add"/"Make
        // Default" actions do (a sibling view with its own independently-
        // fetched `profile` reference, per this file's own established
        // notification-refresh pattern).
        let users = try context.fetch(FetchDescriptor<User>())
        let profile = try XCTUnwrap(users.first?.profile)
        let homeGym = TrainingEnvironment(name: "Home Gym", availableEquipment: [.dumbbells, .bodyweight])
        context.insert(homeGym)
        profile.trainingEnvironments.append(homeGym)
        profile.defaultTrainingEnvironment = homeGym
        try context.save()
        viewModel.refreshEnvironmentState(modelContext: context)

        viewModel.advance(from: .environment, modelContext: context)
        XCTAssertEqual(viewModel.step, .review)
        XCTAssertTrue(try XCTUnwrap(users.first?.profile).hasConfirmedTrainingEnvironment)

        let planViewModel = StrategicPlanSelectionViewModel()
        planViewModel.load(modelContext: context, referenceDate: monday)
        XCTAssertTrue(planViewModel.acceptAndStart(modelContext: context, referenceDate: monday), "the real production acceptance path (which reads `profile.defaultTrainingEnvironment` fresh at this moment — StrategicPlanSelectionViewModel.swift) must run successfully against the athlete's actually-chosen environment")

        // The athlete's real choice remains exactly what acceptance read —
        // never silently reverted to Full Gym by anything in between.
        XCTAssertEqual(try XCTUnwrap(users.first?.profile).defaultTrainingEnvironment?.id, homeGym.id)
        XCTAssertEqual((try context.fetch(FetchDescriptor<TrainingEnvironment>())).count, 2, "Full Gym (auto-seeded) plus the one real Home Gym — never a duplicate")
    }

    /// An athlete who explicitly keeps Full Gym (never touches anything on
    /// this step, just taps Continue) still has it correctly recorded as
    /// confirmed and used — no regression to the existing zero-config
    /// default behavior.
    func testExplicitlyKeepingFullGymStillConfirmsAndIsUsed() throws {
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .muscleGain
        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)
        XCTAssertEqual(viewModel.step, .environment)

        viewModel.advance(from: .environment, modelContext: context)
        XCTAssertEqual(viewModel.step, .review)

        let users = try context.fetch(FetchDescriptor<User>())
        let profile = try XCTUnwrap(users.first?.profile)
        XCTAssertTrue(profile.hasConfirmedTrainingEnvironment)
        XCTAssertEqual(profile.defaultTrainingEnvironment?.name, "Full Gym")

        // Resuming later must never re-ask, having already confirmed once.
        let resumed = OnboardingViewModel()
        resumed.start(modelContext: context)
        XCTAssertEqual(resumed.step, .review)
    }

    /// A pre-existing athlete whose profile already has a default
    /// environment but has never gone through the corrected Environment
    /// step (i.e. `hasConfirmedTrainingEnvironment` defaults to `false`,
    /// as it does for any profile predating this fix) is routed through it
    /// once — never silently treated as already having accepted it.
    func testPreExistingUnconfirmedProfileIsRoutedThroughEnvironmentOnce() throws {
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let goal = Goal(ownerUserID: user.id, primaryType: .muscleGain, preferences: GoalPreferences(availableTrainingDaysPerWeek: 5))
        context.insert(goal)
        user.addGoal(goal)
        // Simulate legacy data: a real default exists (as it always has),
        // but the athlete never explicitly confirmed it — the exact state
        // every pre-fix athlete is actually in.
        XCTAssertFalse(user.profile!.hasConfirmedTrainingEnvironment)
        try context.save()

        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        XCTAssertEqual(viewModel.step, .environment, "an existing but never-confirmed default must still route through this step once")
    }
}
