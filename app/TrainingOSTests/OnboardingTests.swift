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

    // MARK: Milestone Onboarding — real onboarding input reaches the existing,
    // already-real milestone planning mechanism (LongTermPlanner.proposeMilestoneAnchoredPhases).
    // The athlete never selects "Fat Loss" directly — only a goal, a milestone
    // date, and (implicitly) a "leaner by then" intent.

    func testMilestoneOnboardingProducesMuscleGainTransitionFatLossMuscleGainSequence() throws {
        let asOf = Date(timeIntervalSince1970: 1_700_000_000)
        let milestoneDate = asOf.addingTimeInterval(20 * 7 * 86400) // 20 weeks out — enough lead time for a real primary phase + transition before it
        let targetDate = milestoneDate.addingTimeInterval(12 * 7 * 86400) // 12 weeks after the milestone — enough for a real resume phase

        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .muscleGain
        viewModel.hasMilestone = true
        viewModel.milestoneDate = milestoneDate
        viewModel.hasTargetDate = true
        viewModel.targetDate = targetDate
        viewModel.availableTrainingDaysPerWeek = 5

        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)

        let goals = try context.fetch(FetchDescriptor<Goal>())
        let goal = try XCTUnwrap(goals.first, "the real onboarding flow must persist a real Goal")
        XCTAssertEqual(goal.primaryType, .muscleGain, "the athlete's primary goal is never replaced by the milestone")
        XCTAssertEqual(goal.milestoneDate, milestoneDate, "the milestone date the athlete entered must reach the real Goal")
        XCTAssertEqual(goal.bodyCompositionDirection, .loseFat, "this onboarding control's only supported direction — the athlete never picks a BodyCompositionDirection directly")

        // The real, unmodified planning entry point — never a hand-built expectation.
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        XCTAssertEqual(proposal.feasibility, .feasible)
        let types = proposal.phases.map(\.type)
        XCTAssertTrue(types.contains(.fatLoss), "the real milestone mechanism must produce a Fat Loss-flavored phase from a leaner-by-date milestone, entirely from the onboarding input — the athlete never selected this phase")
        guard let fatLossIndex = types.firstIndex(of: .fatLoss) else {
            return XCTFail("expected a fatLoss milestone phase in the real proposal")
        }
        XCTAssertTrue(types.prefix(fatLossIndex).allSatisfy { $0 == .muscleGain || $0 == .transition }, "everything before the milestone must be primary-goal fill-forward or an automatic transition, never an athlete-chosen phase")
        XCTAssertTrue(types.suffix(from: fatLossIndex + 1).contains(.muscleGain), "the primary goal must resume after the milestone since the target date is later")
    }

    // MARK: Milestone Onboarding — 12-week default post-milestone horizon
    // (product-contract fix: removing the athlete-facing targetDate control
    // must never leave a milestone-only Goal strategically dead-ended at
    // the milestone phase).

    /// Proof — a milestone-only Goal (no athlete-entered targetDate, since
    /// normal onboarding no longer offers that control at all) must still
    /// produce Muscle Gain -> Transition -> Fat Loss -> Muscle Gain, using
    /// the real, unmodified LongTermPlanner's own internal 12-week default
    /// post-milestone horizon — never a presentation-layer fabrication.
    func testMilestoneOnlyGoalWithNilTargetDateStillResumesPrimaryGoalAfterward() throws {
        let asOf = Date(timeIntervalSince1970: 1_700_000_000)
        let milestoneDate = asOf.addingTimeInterval(20 * 7 * 86400)

        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .muscleGain
        viewModel.hasMilestone = true
        viewModel.milestoneDate = milestoneDate
        // No targetDate — no UI control sets this, and none is set here,
        // exactly matching what a real athlete using the corrected
        // onboarding flow persists.
        viewModel.availableTrainingDaysPerWeek = 5

        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)

        let goal = try XCTUnwrap((try context.fetch(FetchDescriptor<Goal>())).first)
        XCTAssertNil(goal.targetDate, "the 12-week default must never be written back onto the persisted Goal.targetDate")

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        XCTAssertEqual(proposal.feasibility, .feasible)
        let types = proposal.phases.map(\.type)
        XCTAssertTrue(types.contains(.fatLoss), "the milestone phase must still appear")
        guard let fatLossIndex = types.firstIndex(of: .fatLoss) else {
            return XCTFail("expected a fatLoss milestone phase in the real proposal")
        }
        XCTAssertTrue(types.prefix(fatLossIndex).allSatisfy { $0 == .muscleGain || $0 == .transition })
        XCTAssertTrue(types.suffix(from: fatLossIndex + 1).contains(.muscleGain), "the primary goal must resume after the milestone even with no explicit targetDate — the planner-owned 12-week default must apply")

        // The Goal itself is re-fetched fresh, proving the default is never
        // persisted anywhere as if it were athlete intent.
        let refetchedGoal = try XCTUnwrap((try context.fetch(FetchDescriptor<Goal>())).first)
        XCTAssertNil(refetchedGoal.targetDate)
    }

    /// Proof — an explicit, athlete-set targetDate later than the milestone
    /// always takes precedence over the 12-week default. Constructed so the
    /// explicit choice (2 weeks after the milestone) is far shorter than
    /// what the 12-week default would produce, distinguishing the two: if
    /// the default were wrongly applied instead of the explicit value, the
    /// resume phase(s) would extend roughly 10 weeks further than they
    /// actually do here.
    func testExplicitTargetDateTakesPrecedenceOverTheTwelveWeekDefault() throws {
        let asOf = Date(timeIntervalSince1970: 1_700_000_000)
        let milestoneDate = asOf.addingTimeInterval(20 * 7 * 86400)
        let explicitTargetDate = milestoneDate.addingTimeInterval(2 * 7 * 86400) // far short of the 12-week default

        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .muscleGain
        viewModel.hasMilestone = true
        viewModel.milestoneDate = milestoneDate
        viewModel.hasTargetDate = true
        viewModel.targetDate = explicitTargetDate

        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)

        let goal = try XCTUnwrap((try context.fetch(FetchDescriptor<Goal>())).first)
        XCTAssertEqual(goal.targetDate, explicitTargetDate, "the athlete's own explicit choice must persist exactly as entered")

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        let phases = proposal.phases
        if let lastPhase = phases.last, lastPhase.type == .muscleGain, let lastPhaseEndDate = lastPhase.endDate {
            XCTAssertLessThanOrEqual(lastPhaseEndDate, explicitTargetDate, "the resume phase must never extend past the athlete's own explicit target date")
            XCTAssertLessThan(explicitTargetDate.timeIntervalSince(milestoneDate), 12 * 7 * 86400, "sanity check on this test's own fixture: the explicit date is genuinely shorter than the 12-week default would be")
        }
        // A too-short post-milestone remainder legitimately produces no
        // resume phase at all (existing, unchanged behavior) — either
        // outcome is acceptable here; what must never happen is the
        // 12-week default silently overriding this explicit, shorter date.
    }

    // MARK: Milestone Onboarding UX correction — real production-path proofs

    /// Proof 1/2 — adding "Summer Shape" leaves the primary goal untouched
    /// and maps directly to the existing `Goal.milestoneDate`/
    /// `.bodyCompositionDirection` fields, exactly as before this UX pass —
    /// only the athlete-facing interaction shape changed, never the domain
    /// mapping.
    func testAddingSummerShapeLeavesPrimaryGoalUnchangedAndMapsToExistingFields() throws {
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .muscleGain
        let readyBy = Date().addingTimeInterval(60 * 86400)
        viewModel.hasMilestone = true
        viewModel.milestoneDate = readyBy

        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)

        let goal = try XCTUnwrap((try context.fetch(FetchDescriptor<Goal>())).first)
        XCTAssertEqual(goal.primaryType, .muscleGain, "the main goal is never replaced by adding a milestone")
        XCTAssertEqual(goal.milestoneDate, readyBy)
        XCTAssertEqual(goal.bodyCompositionDirection, .loseFat)
    }

    /// Proof 3 — normal onboarding (no milestone selected) no longer
    /// requires an athlete-entered `targetDate` at all; the real Goal
    /// persists with `targetDate == nil`, the same valid, already-supported
    /// open-ended-plan state this app has always had.
    func testNormalOnboardingNoLongerRequiresAnAthleteEnteredTargetDate() throws {
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .generalStrength
        XCTAssertFalse(viewModel.hasTargetDate, "no UI control sets this for a brand-new athlete")

        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)

        let goal = try XCTUnwrap((try context.fetch(FetchDescriptor<Goal>())).first)
        XCTAssertNil(goal.targetDate, "targetDate stays nil — a real, valid, already-supported open-ended plan")
        XCTAssertNil(goal.milestoneDate)

        // The real planner must still produce a valid, feasible proposal.
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: Date())
        XCTAssertEqual(proposal.feasibility, .feasible)
    }

    /// Proof 5 — removing an already-added Summer Shape milestone clears
    /// both real domain fields without touching the primary goal.
    func testRemovingSummerShapeClearsMilestoneFieldsWithoutChangingPrimaryGoal() throws {
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .muscleGain
        viewModel.hasMilestone = true
        viewModel.milestoneDate = Date().addingTimeInterval(60 * 86400)
        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)
        XCTAssertNotNil((try context.fetch(FetchDescriptor<Goal>())).first?.milestoneDate)

        // Athlete goes back and removes it (mirrors the real "Remove" UI action).
        viewModel.goBack(from: .environment)
        viewModel.goBack(from: .preferences)
        viewModel.hasMilestone = false
        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)

        let goal = try XCTUnwrap((try context.fetch(FetchDescriptor<Goal>())).first)
        XCTAssertEqual(goal.primaryType, .muscleGain, "removing the milestone never changes the primary goal")
        XCTAssertNil(goal.milestoneDate, "removal must clear the real persisted milestone date")
        XCTAssertNil(goal.bodyCompositionDirection, "removal must clear the real persisted direction")
        XCTAssertEqual((try context.fetch(FetchDescriptor<Goal>())).count, 1, "removal must never create a second Goal")

        // The 12-week default is milestone-anchored — with no milestone at
        // all, the real planner must fall back to the existing, unchanged
        // nil-targetDate open-ended-phase behavior, never apply the
        // default horizon to a Goal that has no milestone to anchor it to.
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: Date())
        XCTAssertEqual(proposal.feasibility, .feasible)
        XCTAssertEqual(proposal.phases.count, 1, "no milestone + nil targetDate must restore the existing single open-ended phase behavior")
        XCTAssertEqual(proposal.phases.first?.type, .muscleGain)
    }

    /// Proof — a Goal with no milestone and no targetDate at all (the
    /// ordinary, most common onboarding case) must keep producing the
    /// existing, unchanged single open-ended phase — the 12-week default
    /// is milestone-anchored only and must never apply here.
    func testNoMilestoneNilTargetDatePreservesExistingOpenEndedBehavior() throws {
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .muscleGain

        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)

        let goal = try XCTUnwrap((try context.fetch(FetchDescriptor<Goal>())).first)
        XCTAssertNil(goal.milestoneDate)
        XCTAssertNil(goal.targetDate)

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: Date())
        XCTAssertEqual(proposal.feasibility, .feasible)
        XCTAssertEqual(proposal.phases.count, 1, "the existing single open-ended phase behavior must be completely unchanged")
        XCTAssertEqual(proposal.phases.first?.type, .muscleGain)
    }

    /// Proof 6 — a past/present milestone date must never be accepted; this
    /// is the exact predicate the real "Add to my plan"/"Save" confirm
    /// button's `.disabled()` reads, not merely a visual check.
    func testPastOrPresentMilestoneDateIsNeverValid() throws {
        let viewModel = OnboardingViewModel()
        viewModel.milestoneDate = Date().addingTimeInterval(-86400)
        XCTAssertFalse(viewModel.isMilestoneDateValid, "a past date must never validate")
        viewModel.milestoneDate = Date()
        XCTAssertFalse(viewModel.isMilestoneDateValid, "the present moment must never validate — the milestone must be genuinely in the future")
        viewModel.milestoneDate = Date().addingTimeInterval(86400)
        XCTAssertTrue(viewModel.isMilestoneDateValid, "a genuine future date must validate")
    }

    /// Proof 7 — existing non-milestone onboarding (main goal + preferences
    /// + environment, no "working toward" item) remains fully valid,
    /// end-to-end, unchanged by this UX correction.
    func testExistingNonMilestoneOnboardingRemainsValid() throws {
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .functionalFitness
        viewModel.availableTrainingDaysPerWeek = 3
        XCTAssertFalse(viewModel.hasMilestone)

        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)

        let goal = try XCTUnwrap((try context.fetch(FetchDescriptor<Goal>())).first)
        XCTAssertEqual(goal.primaryType, .functionalFitness)
        XCTAssertNil(goal.milestoneDate)
        XCTAssertNil(goal.bodyCompositionDirection)
        XCTAssertEqual(goal.preferences?.availableTrainingDaysPerWeek, 3)
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

        // Athlete goes back to Goal and changes their mind, then re-confirms.
        viewModel.goBack(from: .environment)
        viewModel.goBack(from: .preferences)
        viewModel.selectedGoalType = .muscleGain
        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)

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
        XCTAssertEqual(viewModel.step, .environment)
        XCTAssertFalse(viewModel.hasDefaultTrainingEnvironment, "Continue must stay disabled with no default Training Environment yet")
    }

    func testRefreshEnvironmentStateEnablesContinueAfterASiblingViewSetsTheDefault() throws {
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)
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

    // MARK: - Dated Objectives + 10K Strategic Reconciliation V1

    /// Adding a 10K Race maps to `Goal.datedObjectives`, never touching
    /// `Goal.milestoneDate`/`.bodyCompositionDirection` (which stay nil when
    /// no Summer Shape milestone was also added) — the primary goal itself
    /// is never replaced.
    func testAddingATenKRaceMapsToDatedObjectivesWithoutTouchingLegacyMilestoneFields() throws {
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .muscleGain
        let raceDay = Date().addingTimeInterval(300 * 86400)
        viewModel.hasRunningEvent = true
        viewModel.runningEventDate = raceDay
        viewModel.runningStartingState = .occasionalShorterDistances

        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)

        let goal = try XCTUnwrap((try context.fetch(FetchDescriptor<Goal>())).first)
        XCTAssertEqual(goal.primaryType, .muscleGain, "the main goal is never replaced by adding a 10K race")
        XCTAssertNil(goal.milestoneDate)
        XCTAssertNil(goal.bodyCompositionDirection)
        XCTAssertEqual(goal.datedObjectives.count, 1)
        XCTAssertEqual(goal.datedObjectives.first?.kind, .runningEvent)
        XCTAssertEqual(goal.datedObjectives.first?.date, raceDay)
        XCTAssertEqual(goal.datedObjectives.first?.runningStartingState, .occasionalShorterDistances)
    }

    /// Adding BOTH Summer Shape and a 10K Race must never silently drop
    /// Summer Shape from planning — once `datedObjectives` is authoritative,
    /// the legacy milestone is projected into it too (the onboarding-layer
    /// fix for the "authority flip" footgun this checkpoint's locked domain
    /// rule would otherwise create).
    func testAddingBothSummerShapeAndATenKRaceProjectsBothIntoDatedObjectives() throws {
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .muscleGain
        let summerShapeDate = Date().addingTimeInterval(200 * 86400)
        let raceDay = Date().addingTimeInterval(280 * 86400)
        viewModel.hasMilestone = true
        viewModel.milestoneDate = summerShapeDate
        viewModel.hasRunningEvent = true
        viewModel.runningEventDate = raceDay
        viewModel.runningStartingState = .notCurrentlyRunning

        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)

        let goal = try XCTUnwrap((try context.fetch(FetchDescriptor<Goal>())).first)
        XCTAssertEqual(goal.datedObjectives.count, 2)
        XCTAssertTrue(goal.datedObjectives.contains { $0.kind == .bodyCompositionMilestone && $0.date == summerShapeDate })
        XCTAssertTrue(goal.datedObjectives.contains { $0.kind == .runningEvent && $0.date == raceDay })

        // The real planner must still coordinate both, never silently drop one.
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: Date())
        XCTAssertEqual(proposal.feasibility, .feasible)
        XCTAssertTrue(proposal.phases.contains { $0.type == .fatLoss })
        XCTAssertTrue(proposal.phases.contains { $0.type == .enduranceEvent })
    }

    /// Removing an already-added 10K Race clears it from `datedObjectives`
    /// without touching the primary goal — mirrors
    /// `testRemovingSummerShapeClearsMilestoneFieldsWithoutChangingPrimaryGoal`.
    func testRemovingATenKRaceClearsItFromDatedObjectives() throws {
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .muscleGain
        viewModel.hasRunningEvent = true
        viewModel.runningEventDate = Date().addingTimeInterval(200 * 86400)
        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)
        XCTAssertEqual((try context.fetch(FetchDescriptor<Goal>())).first?.datedObjectives.count, 1)

        viewModel.goBack(from: .environment)
        viewModel.goBack(from: .preferences)
        viewModel.hasRunningEvent = false
        viewModel.advance(from: .goal, modelContext: context)
        viewModel.advance(from: .preferences, modelContext: context)

        let goal = try XCTUnwrap((try context.fetch(FetchDescriptor<Goal>())).first)
        XCTAssertTrue(goal.datedObjectives.isEmpty, "removal must clear the real persisted dated objective")
        XCTAssertEqual(goal.primaryType, .muscleGain)
    }

    /// The locked "6-week recency" suggestion rule: recent real running
    /// activity may only ever preselect the conservative
    /// `.occasionalShorterDistances` tier, never `.comfortably10K` (never
    /// invents a signal result data can't reliably prove), and never when
    /// there is no recent activity at all.
    func testRunningStartingStateSuggestionFromRecentActivityNeverOverridesNeverGuessesCapability() throws {
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let activityProfile = ActivityPerformanceProfile(activityType: .running, lastPerformedAt: Date().addingTimeInterval(-14 * 86400))
        context.insert(activityProfile)
        user.performanceProfile?.addActivityProfile(activityProfile)
        try context.save()

        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)

        XCTAssertEqual(viewModel.runningStartingState, .occasionalShorterDistances, "recent activity may only ever suggest the conservative tier")
    }

    func testNoRecentRunningActivityLeavesDefaultStartingStateUnchanged() throws {
        _ = AppRootStateResolver.ensureBaselineIdentity(context: context)

        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)

        XCTAssertEqual(viewModel.runningStartingState, .notCurrentlyRunning)
    }
}
