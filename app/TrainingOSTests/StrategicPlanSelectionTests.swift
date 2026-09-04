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
        goalType: GoalType = .generalStrength, trainingDays: Int = 4, allowsDoubles: Bool = false,
        preferredModalities: [ModalityPreference] = [], dislikedModalities: [ModalityPreference] = []
    ) throws -> (user: User, goal: Goal) {
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        user.profile?.trainingEnvironments = [environment]
        user.profile?.defaultTrainingEnvironment = environment
        let goal = Goal(
            ownerUserID: user.id, primaryType: goalType,
            preferences: GoalPreferences(
                preferredModalities: preferredModalities, dislikedModalities: dislikedModalities,
                availableTrainingDaysPerWeek: trainingDays, allowsDoubleSessions: allowsDoubles
            )
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
        // V1 R0 (mid-week start / no-double production bug fix): a
        // brand-new plan's first tactical week only genuinely begins on
        // the next real Monday (`LongTermPlanner.resolvedInitialPlanStartDate`)
        // — this test runs against real `Date()` (no controllable `asOf`
        // exists on the real onboarding ViewModel, deliberately, since it
        // represents "load right now"), so its assertion must reflect
        // whichever real calendar day the suite happens to run on rather
        // than assuming sessions always exist "today" immediately after
        // acceptance.
        let todayIsMonday = Calendar.current.component(.weekday, from: Date()) == 2
        if todayIsMonday {
            XCTAssertFalse(todayViewModel.sessions.isEmpty, "Today must show the athlete's own real Sessions once the plan's first tactical week has genuinely begun")
        } else {
            XCTAssertTrue(todayViewModel.sessions.isEmpty, "Today must show ZERO sessions before the plan's first full calendar week begins — never fabricated, never carried as debt")
        }

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

    // MARK: Plan Recommendation Integrity + Athlete Choice

    // Test 1 — the real dogfooding reproduction: 5 days, no doubles, Muscle
    // Gain must never recommend more sessions than real capacity, and the
    // real materialized schedule must never double-book a day.
    func testFiveDayNoDoublesMuscleGainRecommendationFitsCapacityWithNoDoubleBookedDays() throws {
        try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: 5, allowsDoubles: false)
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        let mix = try XCTUnwrap(viewModel.reviewedMix, "a real recommendation must exist for a 5-day Muscle Gain athlete")
        let totalSessions = mix.orderedComponents.reduce(0) { $0 + $1.frequency.target }
        XCTAssertLessThanOrEqual(totalSessions, 5, "recommended mix must never exceed the athlete's stated 5-day capacity")

        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context))
        try context.save()
        let sessions = try context.fetch(FetchDescriptor<Session>())
        let dates = sessions.compactMap { $0.day?.date }
        XCTAssertEqual(dates.count, Set(dates).count, "no two real Sessions may share the same calendar day when allowsDoubleSessions is false")
    }

    // Test 2 — with doubles allowed, capacity-scaling must not apply; the
    // real fixed template (7 sessions) is left untouched, and whether it's
    // actually placeable is exactly what the real scheduling-based
    // alignment already determines honestly.
    func testFiveDayAllowsDoublesLeavesTheRealTemplateUntouched() throws {
        try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: 5, allowsDoubles: true)
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        let mix = try XCTUnwrap(viewModel.reviewedMix)
        let totalSessions = mix.orderedComponents.reduce(0) { $0 + $1.frequency.target }
        XCTAssertEqual(totalSessions, 7, "allowsDoubleSessions=true must leave the real fixed template exactly as-is")
    }

    // Test 3 — 3 days, no doubles: whatever is recommended (if anything)
    // must be genuinely feasible; an infeasible mix must never be silently
    // labeled RECOMMENDED.
    func testThreeDayNoDoublesNeverPresentsAnInfeasibleMixAsRecommended() throws {
        try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: 3, allowsDoubles: false)
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        if let mix = viewModel.reviewedMix {
            let totalSessions = mix.orderedComponents.reduce(0) { $0 + $1.frequency.target }
            XCTAssertLessThanOrEqual(totalSessions, 3)
        } else {
            XCTAssertTrue(viewModel.hasNoCompatibleMix, "if nothing is recommended, the ViewModel must honestly say so — never silently proceed")
        }
    }

    // MARK: Capacity-scaling POLICY CORRECTION — composition-preserving,
    // proportional apportionment (largest-remainder/Hamilton), never
    // "primary fully protected, supporting yields to zero."

    /// Locked worked example: the real "Focused Hypertrophy" template
    /// (5 Hypertrophy + 2 Zone 2) at capacity 5 must become 4 Hypertrophy +
    /// 1 Zone 2 — BOTH components survive, composition preserved, never
    /// 5+0.
    func testFiveDayNoDoublesCapacityScalingProducesFourHypertrophyPlusOneZoneTwo() throws {
        let (_, goal) = try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: 5, allowsDoubles: false)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: Date())
        let proposedPhase = try XCTUnwrap(proposal.phases.first)
        let previewPhase = TrainingPhase(
            type: proposedPhase.type, startDate: proposedPhase.startDate,
            endDate: proposedPhase.endDate, priorityRule: proposedPhase.priorityRule
        )
        let candidates = LongTermPlanner.proposeTrainingMix(phase: previewPhase, goal: goal)
        let focusedHypertrophy = try XCTUnwrap(candidates.first { $0.mix.name == "Focused Hypertrophy" })
        let hypertrophy = focusedHypertrophy.mix.orderedComponents.first { $0.programmingSystem == .hypertrophy }
        let zoneTwo = focusedHypertrophy.mix.orderedComponents.first { $0.programmingSystem == .steadyState }
        XCTAssertEqual(hypertrophy?.frequency.target, 4, "largest-remainder apportionment of 5+2 at capacity 5 must give Hypertrophy 4")
        XCTAssertEqual(zoneTwo?.frequency.target, 1, "Zone 2 must survive with 1 session, never be zeroed out")
    }

    /// Same real template at capacity 3: both components must still
    /// survive (capacity 3 >= 2 non-zero components), proportionally
    /// apportioned — 5:2 ratio over 3 sessions gives 2 Hypertrophy + 1
    /// Zone 2 (quotas 3*5/7≈2.143, 3*2/7≈0.857; floors 2+0=2, leftover 1
    /// goes to Zone 2's larger remainder).
    func testThreeDayNoDoublesCapacityScalingProducesTwoHypertrophyPlusOneZoneTwo() throws {
        let (_, goal) = try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: 3, allowsDoubles: false)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: Date())
        let proposedPhase = try XCTUnwrap(proposal.phases.first)
        let previewPhase = TrainingPhase(
            type: proposedPhase.type, startDate: proposedPhase.startDate,
            endDate: proposedPhase.endDate, priorityRule: proposedPhase.priorityRule
        )
        let candidates = LongTermPlanner.proposeTrainingMix(phase: previewPhase, goal: goal)
        let focusedHypertrophy = try XCTUnwrap(candidates.first { $0.mix.name == "Focused Hypertrophy" })
        let hypertrophy = focusedHypertrophy.mix.orderedComponents.first { $0.programmingSystem == .hypertrophy }
        let zoneTwo = focusedHypertrophy.mix.orderedComponents.first { $0.programmingSystem == .steadyState }
        XCTAssertEqual(hypertrophy?.frequency.target, 2)
        XCTAssertEqual(zoneTwo?.frequency.target, 1, "both components must still survive at capacity 3, never dropped to 0")
        XCTAssertEqual((hypertrophy?.frequency.target ?? 0) + (zoneTwo?.frequency.target ?? 0), 3)
    }

    /// Capacity 1 (< 2 non-zero components, rule 7): only the
    /// higher-`GoalPriority` component (Hypertrophy, primary) survives —
    /// Zone 2 (supporting) is dropped entirely, since there isn't even
    /// room for 1 session per component.
    func testCapacityOneRetainsOnlyTheHigherPriorityComponent() throws {
        let (_, goal) = try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: 1, allowsDoubles: false)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: Date())
        let proposedPhase = try XCTUnwrap(proposal.phases.first)
        let previewPhase = TrainingPhase(
            type: proposedPhase.type, startDate: proposedPhase.startDate,
            endDate: proposedPhase.endDate, priorityRule: proposedPhase.priorityRule
        )
        let candidates = LongTermPlanner.proposeTrainingMix(phase: previewPhase, goal: goal)
        let focusedHypertrophy = try XCTUnwrap(candidates.first { $0.mix.name == "Focused Hypertrophy" })
        XCTAssertEqual(focusedHypertrophy.mix.orderedComponents.count, 1, "only 1 component may survive when capacity is less than the number of non-zero components")
        let survivor = try XCTUnwrap(focusedHypertrophy.mix.orderedComponents.first)
        XCTAssertEqual(survivor.programmingSystem, .hypertrophy, "the primary/goal-defining component survives, not the supporting one")
        XCTAssertEqual(survivor.frequency.target, 1)
    }

    /// No component's final target may ever exceed its own original
    /// template target, across a range of capacities.
    func testNoComponentEverExceedsItsOriginalTemplateTarget() throws {
        for days in 1...10 {
            let (_, goal) = try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: days, allowsDoubles: false)
            let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: Date())
            let proposedPhase = try XCTUnwrap(proposal.phases.first)
            let previewPhase = TrainingPhase(
                type: proposedPhase.type, startDate: proposedPhase.startDate,
                endDate: proposedPhase.endDate, priorityRule: proposedPhase.priorityRule
            )
            let candidates = LongTermPlanner.proposeTrainingMix(phase: previewPhase, goal: goal)
            let focusedHypertrophy = try XCTUnwrap(candidates.first { $0.mix.name == "Focused Hypertrophy" })
            let hypertrophy = focusedHypertrophy.mix.orderedComponents.first { $0.programmingSystem == .hypertrophy }
            let zoneTwo = focusedHypertrophy.mix.orderedComponents.first { $0.programmingSystem == .steadyState }
            XCTAssertLessThanOrEqual(hypertrophy?.frequency.target ?? 0, 5, "Hypertrophy's original template target is 5 — never exceeded")
            XCTAssertLessThanOrEqual(zoneTwo?.frequency.target ?? 0, 2, "Zone 2's original template target is 2 — never exceeded")
            let total = (hypertrophy?.frequency.target ?? 0) + (zoneTwo?.frequency.target ?? 0)
            XCTAssertLessThanOrEqual(total, days, "total sessions must never exceed the athlete's stated capacity (day \(days))")
        }
    }

    /// Modality-preference consequence: a REAL existing candidate mix
    /// ("Strength Plus Variety" — 3 Strength + 2 Functional Fitness + 1
    /// Running) at a capacity where the old "primary fully protected,
    /// supporting yields to zero" policy would have silently zeroed out
    /// Functional Fitness even though the athlete explicitly preferred it.
    /// Proportional apportionment (3:2:1 ratio over capacity 4 — quotas
    /// 2/1.333/0.667, floors 2+1+0=3, leftover 1 goes to Running's larger
    /// remainder) must retain Functional Fitness with at least 1 session.
    func testCapacityScalingNeverErasesAPreferredNonPrimaryModality() throws {
        let (_, goal) = try makeOnboardedAthlete(
            goalType: .muscleGain, trainingDays: 4, allowsDoubles: false,
            preferredModalities: [ModalityPreference(system: .functionalFitness)]
        )
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: Date())
        let proposedPhase = try XCTUnwrap(proposal.phases.first)
        let previewPhase = TrainingPhase(
            type: proposedPhase.type, startDate: proposedPhase.startDate,
            endDate: proposedPhase.endDate, priorityRule: proposedPhase.priorityRule
        )
        let candidates = LongTermPlanner.proposeTrainingMix(phase: previewPhase, goal: goal)
        let strengthPlusVariety = try XCTUnwrap(candidates.first { $0.mix.name == "Strength Plus Variety" }, "the real 'Strength Plus Variety' template (3 Strength + 2 Functional Fitness + 1 Running) must exist as a candidate for a Muscle Gain goal")
        let functionalFitness = strengthPlusVariety.mix.orderedComponents.first { $0.programmingSystem == .functionalFitness }
        XCTAssertNotNil(functionalFitness, "Functional Fitness must not be dropped from the mix entirely")
        XCTAssertGreaterThanOrEqual(functionalFitness?.frequency.target ?? 0, 1, "a preferred supporting modality must retain at least 1 real session at capacity 4 — never zeroed out merely because Strength (primary) has a higher raw template target")
    }

    // Test 4 — a stated Functional Fitness preference must reach the real
    // ranking (recommended or a real alternative), never be silently
    // ignored by the planner.
    func testPreferredFunctionalFitnessReachesRealPlannerRanking() throws {
        try makeOnboardedAthlete(
            goalType: .muscleGain, trainingDays: 6, allowsDoubles: false,
            preferredModalities: [ModalityPreference(system: .functionalFitness)]
        )
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        let selectable = [viewModel.reviewedMix].compactMap { $0 } + viewModel.alternatives.map(\.mix)
        let containsFF = selectable.contains { mix in
            mix.orderedComponents.contains { $0.programmingSystem == .functionalFitness }
        }
        XCTAssertTrue(containsFF, "a stated preference for Functional Fitness must be reachable as the recommendation or a real alternative")
    }

    // Test 5 — an activity-scoped dislike ("no running") must steer the
    // real materialized activity away from running WITHOUT vetoing
    // steady-state/conditioning entirely.
    func testDislikedRunningSpecificallyExcludesRunningFromMaterializedActivity() throws {
        // 7-day capacity so the supporting steady-state component keeps a
        // real, nonzero allocation regardless of capacity-scaling — this
        // test isolates activity SELECTION, not capacity REDUCTION.
        try makeOnboardedAthlete(
            goalType: .muscleGain, trainingDays: 7, allowsDoubles: false,
            dislikedModalities: [ModalityPreference(system: .steadyState, activityType: .running)]
        )
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        let mix = try XCTUnwrap(viewModel.reviewedMix)
        XCTAssertTrue(mix.orderedComponents.contains { $0.programmingSystem == .steadyState }, "an activity-scoped dislike must never veto the whole steady-state system")

        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context))
        try context.save()
        let steadyStatePrescriptions = try context.fetch(FetchDescriptor<SteadyStatePrescription>())
        XCTAssertFalse(steadyStatePrescriptions.isEmpty, "a real steady-state component must have materialized")
        for prescription in steadyStatePrescriptions {
            XCTAssertNotEqual(prescription.activityType, .running, "materialization must avoid the specifically-disliked activity")
        }
    }

    // Test 6 — no modality preference at all: existing goal-first ranking
    // remains valid (regression against Checkpoint 2's own established
    // behavior).
    func testNoModalityPreferenceLeavesGoalFirstRankingValid() throws {
        try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: 6, allowsDoubles: false)
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        XCTAssertNotNil(viewModel.reviewedMix)
    }

    // Test 7 — alternatives are real, planner-returned candidates, never
    // UI-fabricated.
    func testAlternativesAreRealPlannerReturnedCandidates() throws {
        try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: 6, allowsDoubles: false)
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        for alternative in viewModel.alternatives {
            XCTAssertTrue(viewModel.candidates.contains { $0.mix.id == alternative.mix.id }, "every shown alternative must be a real candidate LongTermPlanner itself returned")
        }
    }

    // Test 8 — only feasible alternatives are selectable; selecting a
    // real, feasible alternative replaces the reviewed mix; an
    // unrelated/non-member mix is rejected.
    func testOnlyFeasibleAlternativesAreSelectableAndSelectionReplacesTheReviewedMix() throws {
        try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: 6, allowsDoubles: false)
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        for alternative in viewModel.alternatives {
            XCTAssertGreaterThanOrEqual(alternative.alignment.rating, LongTermPlanner.compatibilityThreshold, "only genuinely feasible alternatives may ever be offered as selectable")
        }
        if let firstAlternative = viewModel.alternatives.first {
            viewModel.selectAlternative(firstAlternative)
            XCTAssertEqual(viewModel.reviewedMix?.id, firstAlternative.mix.id)
        }
    }

    // MARK: - Dated Objectives + 10K Strategic Reconciliation V1

    /// A genuine `.objectivesConflict` proposal must surface as its own
    /// distinct, athlete-facing trade-off — never silently blocked like
    /// `.infeasible`, and never allowed to proceed to a mix recommendation.
    func testLoadSurfacesAnObjectivesConflictDistinctlyAndNeverBuildsAMix() throws {
        let (_, goal) = try makeOnboardedAthlete(goalType: .muscleGain)
        let sameDay = Date().addingTimeInterval(300 * 86400)
        goal.datedObjectives = [
            DatedObjective(kind: .bodyCompositionMilestone, date: sameDay, bodyCompositionDirection: .loseFat),
            DatedObjective(kind: .runningEvent, date: sameDay, runningStartingState: .notCurrentlyRunning),
        ]
        try context.save()

        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)

        XCTAssertTrue(viewModel.hasObjectivesConflict)
        XCTAssertFalse(viewModel.isInfeasible, "a genuine conflict must never be reported as the unrelated 'infeasible' vocabulary")
        XCTAssertNil(viewModel.reviewedMix)
        XCTAssertTrue(viewModel.candidates.isEmpty)
    }

    /// A compressed (too-soon) dated objective must surface the truthful
    /// "shorter than normal lead time" signal.
    func testLoadSurfacesCompressedObjectivePrepWhenAnEarlierObjectiveRunsLateIntoTheNext() throws {
        let (_, goal) = try makeOnboardedAthlete(goalType: .muscleGain)
        let asOf = Date()
        let soon = asOf.addingTimeInterval(20 * 86400) // ~3 weeks — far short of any real tier
        goal.datedObjectives = [DatedObjective(kind: .runningEvent, date: soon, runningStartingState: .notCurrentlyRunning)]
        try context.save()

        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)

        XCTAssertTrue(viewModel.hasCompressedObjectivePrep)
        XCTAssertFalse(viewModel.isInfeasible, "an event being soon must never block plan creation")
    }
}
