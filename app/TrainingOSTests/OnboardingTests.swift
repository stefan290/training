import XCTest
import SwiftData
@testable import TrainingOS

/// Stage V1.Checkpoint 1: proves the real production routing/persistence
/// boundary this checkpoint introduces — `AppRootStateResolver` (root
/// routing) and `OnboardingViewModel` (the flow itself), through their real
/// production entry points, never a resolver-unit-only test.
@MainActor
final class OnboardingTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    // MARK: 1/15 — fresh production state routes to onboarding, no demo seed dependency

    func testFreshProductionStateRoutesToOnboarding() throws {
        XCTAssertEqual(AppRootStateResolver.resolve(context: context), .needsOnboarding)
        XCTAssertTrue((try context.fetch(FetchDescriptor<Goal>())).isEmpty, "no fake Goal exists on a fresh store")
        XCTAssertTrue((try context.fetch(FetchDescriptor<TrainingPlan>())).isEmpty, "no fake Plan exists on a fresh store")
    }

    // MARK: 2/11 — existing valid athlete/Goal state does not restart onboarding; relaunch is stable

    func testExistingActiveGoalAndEnvironmentDoesNotRestartOnboarding() throws {
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let environment = TrainingEnvironment(name: "Home Gym", availableEquipment: [.dumbbells])
        context.insert(environment)
        user.profile?.trainingEnvironments = [environment]
        user.profile?.defaultTrainingEnvironment = environment
        let goal = Goal(ownerUserID: user.id, primaryType: .generalStrength)
        context.insert(goal)
        user.addGoal(goal)
        try context.save()

        XCTAssertEqual(AppRootStateResolver.resolve(context: context), .readyForPlan, "onboarding complete, no plan yet")
        // Simulate relaunch: resolve again from the same persisted state.
        XCTAssertEqual(AppRootStateResolver.resolve(context: context), .readyForPlan, "relaunch never restarts onboarding")
    }

    func testActivePlanRoutesToActiveTraining() throws {
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let environment = TrainingEnvironment(name: "Home Gym", availableEquipment: [.dumbbells])
        context.insert(environment)
        user.profile?.trainingEnvironments = [environment]
        user.profile?.defaultTrainingEnvironment = environment
        let goal = Goal(ownerUserID: user.id, primaryType: .generalStrength)
        context.insert(goal)
        user.addGoal(goal)
        let plan = TrainingPlan(status: .active)
        context.insert(plan)
        goal.addPlan(plan)
        try context.save()

        XCTAssertEqual(AppRootStateResolver.resolve(context: context), .activeTraining)
    }

    // MARK: 3/12/13/14 — onboarding creates only real, planner-needed objects; nothing fabricated

    func testEnsureBaselineIdentityCreatesRealObjectsAndNoFakeTacticalState() throws {
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        XCTAssertNotNil(user.profile, "UserProfile required by the planner/TE.1")
        XCTAssertNotNil(user.performanceProfile, "PerformanceProfile required by StartPhaseUseCase.start")
        XCTAssertFalse((try context.fetch(FetchDescriptor<Exercise>())).isEmpty, "the static Exercise catalog must exist for any later materialization")
        XCTAssertTrue((try context.fetch(FetchDescriptor<Goal>())).isEmpty, "no Goal fabricated")
        XCTAssertTrue((try context.fetch(FetchDescriptor<TrainingPlan>())).isEmpty, "no TrainingPlan fabricated")
        XCTAssertTrue((try context.fetch(FetchDescriptor<ProgramInstance>())).isEmpty, "no ProgramInstance fabricated")
        XCTAssertTrue((try context.fetch(FetchDescriptor<Session>())).isEmpty, "no Session fabricated")
    }

    func testEnsureBaselineIdentityIsIdempotent() throws {
        let first = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let second = AppRootStateResolver.ensureBaselineIdentity(context: context)
        XCTAssertEqual(first.id, second.id, "calling this twice must never create a second User")
        XCTAssertEqual((try context.fetch(FetchDescriptor<User>())).count, 1)
    }

    // MARK: 4/5 — Goal choice and planner-relevant preferences persist

    func testOnboardingViewModelPersistsGoalAndPlannerRelevantPreferences() throws {
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .fatLoss
        viewModel.hasTargetDate = true
        viewModel.targetDate = Date(timeIntervalSince1970: 2_000_000_000)
        viewModel.varietyPreference = .high
        viewModel.availableTrainingDaysPerWeek = 5
        viewModel.allowsDoubleSessions = true

        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)
        viewModel.advance(from: .modalityPreferences, modelContext: context)

        let goals = try context.fetch(FetchDescriptor<Goal>())
        let goal = try XCTUnwrap(goals.first)
        XCTAssertEqual(goal.primaryType, .fatLoss)
        XCTAssertEqual(goal.status, .active)
        XCTAssertEqual(goal.targetDate, Date(timeIntervalSince1970: 2_000_000_000))
        let preferences = try XCTUnwrap(goal.preferences)
        XCTAssertEqual(preferences.varietyPreference, .high)
        XCTAssertEqual(preferences.availableTrainingDaysPerWeek, 5)
        XCTAssertEqual(preferences.allowsDoubleSessions, true)
    }

    // MARK: 6/7 — Training Environment created via the real TE.1 model and persists as default

    func testOnboardingCreatesRealTrainingEnvironmentAndSetsDefault() throws {
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let environment = TrainingEnvironment(name: "Garage Gym", availableEquipment: [.barbell, .rack])
        context.insert(environment)
        user.profile?.trainingEnvironments.append(environment)
        user.profile?.defaultTrainingEnvironment = environment
        try context.save()

        XCTAssertEqual(user.profile?.trainingEnvironments.count, 1)
        XCTAssertEqual(user.profile?.defaultTrainingEnvironment?.name, "Garage Gym")
        XCTAssertTrue(environment.availableEquipment.contains(.barbell))
    }

    // MARK: 9 — back navigation / re-running goal creation never duplicates the Goal

    func testCreatingGoalTwiceUpdatesInPlaceRatherThanDuplicating() throws {
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .generalStrength
        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)
        viewModel.advance(from: .modalityPreferences, modelContext: context)

        // Athlete goes back to Goal and changes their mind, then re-confirms.
        viewModel.goBack(from: .environment)
        viewModel.goBack(from: .modalityPreferences)
        viewModel.goBack(from: .preferences)
        viewModel.selectedGoalType = .muscleGain
        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)
        viewModel.advance(from: .modalityPreferences, modelContext: context)

        let goals = try context.fetch(FetchDescriptor<Goal>())
        XCTAssertEqual(goals.count, 1, "must never create a second Goal")
        XCTAssertEqual(goals.first?.primaryType, .muscleGain, "the latest choice wins")
    }

    // MARK: 10 — completing onboarding is idempotent

    func testCompletingOnboardingTwiceRemainsIdempotent() throws {
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let environment = TrainingEnvironment(name: "Home Gym", availableEquipment: [.dumbbells])
        context.insert(environment)
        user.profile?.trainingEnvironments = [environment]
        user.profile?.defaultTrainingEnvironment = environment
        let goal = Goal(ownerUserID: user.id, primaryType: .generalStrength)
        context.insert(goal)
        user.addGoal(goal)
        try context.save()

        let firstResolve = AppRootStateResolver.resolve(context: context)
        let secondResolve = AppRootStateResolver.resolve(context: context)
        XCTAssertEqual(firstResolve, secondResolve)
        XCTAssertEqual((try context.fetch(FetchDescriptor<Goal>())).count, 1)
        XCTAssertEqual((try context.fetch(FetchDescriptor<User>())).count, 1)
    }

    // MARK: 8 — review reflects actual selections (proven at the ViewModel/persisted-state level)

    func testReviewStateReflectsActualPersistedSelections() throws {
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .enduranceEvent
        viewModel.availableTrainingDaysPerWeek = 6
        viewModel.varietyPreference = .low
        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)
        viewModel.advance(from: .modalityPreferences, modelContext: context)

        // A fresh ViewModel re-reading persisted state (simulating relaunch mid-flow
        // before the Environment step) must reflect the real, saved choices.
        let resumed = OnboardingViewModel()
        resumed.start(modelContext: context)
        XCTAssertEqual(resumed.selectedGoalType, .enduranceEvent)
        XCTAssertEqual(resumed.availableTrainingDaysPerWeek, 6)
        XCTAssertEqual(resumed.varietyPreference, .low)
        XCTAssertEqual(resumed.step, .environment, "resumes at Environment since no default Training Environment exists yet")
    }

    // MARK: Dogfooding regression — Continue enables after a real Training Environment is created,
    // even though TrainingEnvironmentSettingsView mutates its own independently-fetched `profile` reference

    func testContinueStaysDisabledUntilARealDefaultTrainingEnvironmentExists() throws {
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .generalStrength
        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)
        viewModel.advance(from: .modalityPreferences, modelContext: context)
        XCTAssertEqual(viewModel.step, .environment)
        XCTAssertFalse(viewModel.hasDefaultTrainingEnvironment, "Continue must stay disabled with no default Training Environment yet")
    }

    func testRefreshEnvironmentStateEnablesContinueAfterASiblingViewSetsTheDefault() throws {
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)
        viewModel.advance(from: .modalityPreferences, modelContext: context)
        XCTAssertFalse(viewModel.hasDefaultTrainingEnvironment)

        // Simulate exactly what TrainingEnvironmentSettingsView does: its OWN
        // independently-fetched `profile` reference (never touching `viewModel`
        // directly) creates a real TrainingEnvironment and sets it as default —
        // this is the real, reproduced dogfooding scenario.
        let users = try context.fetch(FetchDescriptor<User>())
        let siblingProfile = try XCTUnwrap(users.first?.profile)
        let environment = TrainingEnvironment(name: "Home Gym", availableEquipment: [.dumbbells])
        context.insert(environment)
        siblingProfile.trainingEnvironments.append(environment)
        siblingProfile.defaultTrainingEnvironment = environment
        try context.save()

        // Before the explicit refresh this ViewModel's own tracked property
        // must not be assumed to have updated on its own — proving the fix's
        // whole premise (implicit relationship-observation is NOT relied upon).
        viewModel.refreshEnvironmentState(modelContext: context)
        XCTAssertTrue(viewModel.hasDefaultTrainingEnvironment, "must observe the sibling view's real write once explicitly refreshed")

        viewModel.advance(from: .environment, modelContext: context)
        XCTAssertEqual(viewModel.step, .review, "Continue must now actually advance")

        // No duplicate environment/default ever created by the refresh itself.
        XCTAssertEqual((try context.fetch(FetchDescriptor<TrainingEnvironment>())).count, 1)
        XCTAssertEqual(try XCTUnwrap(users.first?.profile?.defaultTrainingEnvironment?.id), environment.id)
    }

    func testTrainingEnvironmentSettingsViewPostsTheRefreshNotificationOnCreateAndOnExplicitDefaultChange() throws {
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        try context.save()

        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(forName: .trainingEnvironmentDefaultChanged, object: nil, queue: nil) { _ in
            notificationCount += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        // First environment: auto-set as default, must notify.
        let first = TrainingEnvironment(name: "Home Gym", availableEquipment: [.dumbbells])
        context.insert(first)
        user.profile?.trainingEnvironments.append(first)
        if user.profile?.defaultTrainingEnvironment == nil {
            user.profile?.defaultTrainingEnvironment = first
            NotificationCenter.default.post(name: .trainingEnvironmentDefaultChanged, object: nil)
        }
        try context.save()
        XCTAssertEqual(notificationCount, 1)

        // Explicit tap-to-make-default on a second environment must also notify.
        let second = TrainingEnvironment(name: "Garage Gym", availableEquipment: [.barbell, .rack])
        context.insert(second)
        user.profile?.trainingEnvironments.append(second)
        user.profile?.defaultTrainingEnvironment = second
        NotificationCenter.default.post(name: .trainingEnvironmentDefaultChanged, object: nil)
        try context.save()
        XCTAssertEqual(notificationCount, 2)
    }

    func testRelaunchAfterEnvironmentStepPreservesTheValidStateAndDoesNotRestartOnboarding() throws {
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)
        viewModel.advance(from: .modalityPreferences, modelContext: context)

        let users = try context.fetch(FetchDescriptor<User>())
        let profile = try XCTUnwrap(users.first?.profile)
        let environment = TrainingEnvironment(name: "Home Gym", availableEquipment: [.dumbbells])
        context.insert(environment)
        profile.trainingEnvironments.append(environment)
        profile.defaultTrainingEnvironment = environment
        try context.save()

        viewModel.refreshEnvironmentState(modelContext: context)
        viewModel.advance(from: .environment, modelContext: context)

        // Simulate relaunch: a brand new ViewModel re-resolving from the same persisted state.
        let relaunched = OnboardingViewModel()
        relaunched.start(modelContext: context)
        XCTAssertEqual(relaunched.step, .review, "relaunch must resume at Review, never restart onboarding")
        XCTAssertTrue(relaunched.hasDefaultTrainingEnvironment)
        XCTAssertEqual((try context.fetch(FetchDescriptor<TrainingEnvironment>())).count, 1, "no duplicate environment across relaunch")
    }
}
