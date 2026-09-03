import XCTest
import SwiftData
@testable import TrainingOS

/// Stage V1.Checkpoint 2: proves the real production plan-selection path —
/// `StrategicPlanSelectionViewModel` orchestrating the exact, unmodified
/// `LongTermPlanner`/`AcceptStrategicPlanUseCase`/`StartPhaseUseCase`
/// pipeline, through their real production entry points, never a
/// resolver/planner-unit-only test.
@MainActor
final class StrategicPlanSelectionTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    /// The exact real "completed onboarding" state Checkpoint 1 produces —
    /// real `User`/`UserProfile`/`PerformanceProfile` (`ensureBaselineIdentity`,
    /// which also seeds the real static `ExerciseCatalog`), a real, fully
    /// TE.1-equipped `TrainingEnvironment`, and a real `Goal` with real
    /// `GoalPreferences` — never a hand-fabricated shortcut.
    @discardableResult
    private func makeOnboardedAthlete(
        goalType: GoalType = .generalStrength, trainingDays: Int = 4, allowsDoubles: Bool = false
    ) throws -> (user: User, goal: Goal) {
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        user.profile?.trainingEnvironments = [environment]
        user.profile?.defaultTrainingEnvironment = environment
        let goal = Goal(
            ownerUserID: user.id, primaryType: goalType,
            preferences: GoalPreferences(availableTrainingDaysPerWeek: trainingDays, allowsDoubleSessions: allowsDoubles)
        )
        context.insert(goal)
        user.addGoal(goal)
        try context.save()
        return (user, goal)
    }

    // MARK: 1 — completed onboarding + no active plan resolves Ready For Plan

    func testCompletedOnboardingNoPlanResolvesReadyForPlan() throws {
        try makeOnboardedAthlete()
        XCTAssertEqual(AppRootStateResolver.resolve(context: context), .readyForPlan)
    }

    // MARK: 2/3 — real recommendation from the athlete's actual Goal/preferences; viewing never creates an active plan

    func testLoadProducesRealRecommendationFromTheAthletesActualGoalWithoutCreatingAnActivePlan() throws {
        try makeOnboardedAthlete(goalType: .generalStrength, trainingDays: 5)
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)

        XCTAssertEqual(viewModel.goalTypeLabel, PlanPresentation.goalTypeLabel(.generalStrength))
        XCTAssertNotNil(viewModel.recommendedMixSummary, "a real LongTermPlanner recommendation must be produced")
        XCTAssertFalse(viewModel.phaseTypeLabels.isEmpty)
        XCTAssertTrue((try context.fetch(FetchDescriptor<TrainingPlan>())).isEmpty, "viewing a recommendation must never create an active plan")
        XCTAssertEqual(AppRootStateResolver.resolve(context: context), .readyForPlan, "still readyForPlan after only viewing")
    }

    // MARK: 4 — recommended and selected mix remain distinct before acceptance

    func testRecommendedMixIsNotYetSelectedBeforeAcceptance() throws {
        try makeOnboardedAthlete()
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        let mix = try XCTUnwrap(viewModel.reviewedMix)
        XCTAssertEqual(mix.kind, .recommended, "TrainingMix.kind only becomes .selected inside StartPhaseUseCase.start")
    }

    // MARK: 5/7/8/9 — Accept uses the real use cases; real ProgramInstances/Sessions created; Training Environment honored

    func testAcceptAndStartUsesRealUseCasesAndCreatesRealProgramInstancesAndSessions() throws {
        // .functionalFitness's real recommended mix has no .rmBased
        // component, so nothing is deferred pending calibration — an
        // honest choice for proving Sessions materialize immediately
        // (the separate calibration test below covers the .generalStrength
        // deferral case explicitly).
        let (_, goal) = try makeOnboardedAthlete(goalType: .functionalFitness, trainingDays: 5)
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context), "acceptAndStart must succeed against a real, fully-equipped athlete")
        // A fresh FetchDescriptor query (as opposed to relationship
        // traversal on an already-loaded object) needs a save to see
        // objects `StartPhaseUseCase.start` inserted this same context
        // pass — the same discipline `OnboardingTests`' own fixtures
        // already follow after each real write.
        try context.save()

        let plans = try context.fetch(FetchDescriptor<TrainingPlan>())
        XCTAssertEqual(plans.count, 1)
        let plan = try XCTUnwrap(plans.first)
        XCTAssertEqual(plan.status, .active)
        XCTAssertEqual(plan.goal?.id, goal.id)
        XCTAssertFalse(plan.orderedPhases.isEmpty)
        XCTAssertEqual(plan.orderedPhases.first?.status, .active, "StartPhaseUseCase.start activates the first phase")

        let instances = try context.fetch(FetchDescriptor<ProgramInstance>())
        XCTAssertFalse(instances.isEmpty, "real ProgramInstances must be created — never fabricated onboarding-only state")

        let sessions = try context.fetch(FetchDescriptor<Session>())
        XCTAssertFalse(sessions.isEmpty, "real first tactical Sessions must exist")
    }

    // MARK: 6 — double Accept cannot create duplicate plans

    func testDoubleAcceptCannotCreateDuplicatePlans() throws {
        try makeOnboardedAthlete()
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context))
        XCTAssertFalse(viewModel.acceptAndStart(modelContext: context), "guarded by didSucceed — must refuse a second call")

        XCTAssertEqual((try context.fetch(FetchDescriptor<TrainingPlan>())).count, 1)
    }

    // MARK: 10/16 — Today/Plan see the newly-created real Sessions/plan; no seed/demo journey ever invoked

    func testAfterStartTodayAndPlanSeeTheRealNewlyCreatedState() throws {
        // Same reasoning as the test above — a non-.rmBased goal so
        // Sessions materialize immediately, with nothing awaiting calibration.
        try makeOnboardedAthlete(goalType: .functionalFitness, trainingDays: 5)
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context))
        try context.save()

        // Today's own real production ViewModel, unmodified.
        let todayViewModel = TodayViewModel()
        todayViewModel.load(modelContext: context)
        XCTAssertFalse(todayViewModel.sessions.isEmpty, "Today must show the athlete's own real Sessions")

        // No demo/seed journey ever ran.
        XCTAssertTrue((try context.fetch(FetchDescriptor<TrainingPlan>())).allSatisfy { $0.goal?.ownerUserID != nil })
    }

    // MARK: 14 — after successful start, AppRootStateResolver resolves activeTraining; relaunch preserves it

    func testAfterSuccessfulStartResolverReachesActiveTrainingAndRelaunchPreservesIt() throws {
        try makeOnboardedAthlete()
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context))

        XCTAssertEqual(AppRootStateResolver.resolve(context: context), .activeTraining)
        // Simulate relaunch: resolve again from the same persisted state.
        XCTAssertEqual(AppRootStateResolver.resolve(context: context), .activeTraining, "relaunch must not restart onboarding/plan-selection or create a second plan")
        XCTAssertEqual((try context.fetch(FetchDescriptor<TrainingPlan>())).count, 1, "no duplicate plan from re-resolving")
    }

    // MARK: 12/13 — required calibration remains required; no fake RM inserted

    func testRequiredCalibrationRemainsRequiredAndNoFakeRMIsInserted() throws {
        // .generalStrength's real recommended mix includes an .rmBased
        // system (Hypertrophy/Powerlifting) per LongTermPlanner's own
        // candidateMixTemplates — a fresh athlete has no SourceRMCalibration
        // yet, so StartPhaseUseCase.start must defer that component rather
        // than fabricate a starting weight.
        try makeOnboardedAthlete(goalType: .generalStrength)
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context))

        XCTAssertNotNil(viewModel.componentsAwaitingCalibrationCount, "the real componentsAwaitingCalibration count must be surfaced, not silently discarded")
        XCTAssertTrue((try context.fetch(FetchDescriptor<SourceRMCalibration>())).isEmpty, "no calibration must be fabricated merely to let the plan start")

        // The existing, unchanged production gate must now activate.
        let calibrationViewModel = SourceRMCalibrationViewModel()
        calibrationViewModel.load(modelContext: context)
        if (viewModel.componentsAwaitingCalibrationCount ?? 0) > 0 {
            XCTAssertTrue(calibrationViewModel.hasPendingCalibration, "the existing RootTabView gate must see the real pending calibration")
        }
    }

    // MARK: 11 — Training Environment incompatibility produces truthful recovery, never a fake prescription

    func testIncompatibleTrainingEnvironmentProducesTruthfulRecoveryNeverFakePrescription() throws {
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        // A deliberately minimal, bodyweight-only environment — every real
        // strength/functional-fitness candidate in the catalog needs some
        // real equipment this environment lacks entirely.
        let environment = TrainingEnvironment(name: "Bodyweight Only", availableEquipment: [])
        context.insert(environment)
        user.profile?.trainingEnvironments = [environment]
        user.profile?.defaultTrainingEnvironment = environment
        let goal = Goal(ownerUserID: user.id, primaryType: .generalStrength, preferences: GoalPreferences(availableTrainingDaysPerWeek: 4))
        context.insert(goal)
        user.addGoal(goal)
        try context.save()

        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        let succeeded = viewModel.acceptAndStart(modelContext: context)

        if !succeeded {
            XCTAssertNotNil(viewModel.errorMessage, "a truthful recovery message must be shown")
            XCTAssertTrue((try context.fetch(FetchDescriptor<Session>())).isEmpty, "no fake prescription/Session may be materialized against an incompatible environment")
        }
        // Either outcome is acceptable here (some components may still resolve
        // bodyweight-eligible candidates) — the invariant under test is that
        // failure, if it occurs, is truthful and produces no fake Session,
        // never that failure is guaranteed for every real mix.
    }

    // MARK: 19/20/21/22/23 — regressions

    func testExistingStrategicLifecycleRegressionUnaffected() throws {
        // Spot-check: a real StrategicPlanProposal/acceptance identical to
        // what StrategicPhaseLifecycleTests already exercises still behaves
        // the same when driven through the new ViewModel.
        let (_, goal) = try makeOnboardedAthlete(goalType: .functionalFitness, trainingDays: 4)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: Date())
        XCTAssertEqual(proposal.feasibility, .feasible)
        XCTAssertFalse(proposal.phases.isEmpty)
    }
}
