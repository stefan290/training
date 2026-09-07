import XCTest
import SwiftData
@testable import TrainingOS

/// V1 R6 (Onboarding + Plan Selection reconciliation): proves the real
/// end-to-end new-athlete journey through the REAL production path —
/// `AppRootStateResolver` -> `LongTermPlanner` -> `AcceptStrategicPlanUseCase`
/// -> `StartPhaseUseCase` -> `SourceRMCalibrationViewModel` (the exact
/// real call `RootTabView.onAppear` makes) — never a hand-built fixture
/// that bypasses the real onboarding/acceptance flow.
@MainActor
final class OnboardingPlanSelectionReconciliationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar.current.date(from: components)!
    }

    private struct Candidates {
        let strength: [Exercise]
        let functionalFitness: [Exercise]
    }

    private func makeCandidates() -> Candidates {
        func exercise(
            _ name: String, _ targets: [MuscleGroup] = [], _ movementFunctions: [MovementFunction] = [], _ functionalModality: FunctionalModality? = nil
        ) -> Exercise {
            let ex = Exercise(canonicalName: name, modality: .hypertrophy, equipment: "barbell", movementPattern: "test", primaryTargets: targets, movementFunctions: movementFunctions, functionalModality: functionalModality)
            context.insert(ex)
            return ex
        }
        let strength = [
            exercise("R6 Boundary Primary Shoulders", [.shoulders]),
            exercise("R6 Boundary Primary Quads", [.quadriceps]),
            exercise("R6 Boundary Primary Back", [.back]),
            exercise("R6 Boundary Paired Accessory", [.chest, .triceps]),
        ]
        let ff = [
            exercise("R6 Boundary FF Squat Lift", [], [.squatLoaded], .weightlifting),
            exercise("R6 Boundary FF Pull-up", [], [.gymnasticsPull], .gymnastics),
            exercise("R6 Boundary FF Bike", [], [.monostructural], .metabolicConditioning),
        ]
        return Candidates(strength: strength, functionalFitness: ff)
    }

    // MARK: H — THE CRITICAL TEST: pure 5x Functional Fitness, real onboarding -> accept -> start -> calibration routing.
    // Known unconfirmed bug lead: Functional-Fitness-only composition may crash
    // SourceRMCalibrationViewModel.load via RequiredSourceCalibrationsUseCase/ProgramDefinition.
    // Expected: NO source RM calibration required, NO crash, real plan starts normally.

    func testPureFunctionalFitnessJourneyNeverRequiresCalibrationAndNeverCrashesRootRouting() throws {
        let monday = date(2026, 1, 5) // confirmed Monday — isolates this proof from R0 boundary behavior
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let candidates = makeCandidates()

        let goal = Goal(ownerUserID: user.id, primaryType: .functionalFitness, preferences: GoalPreferences(availableTrainingDaysPerWeek: 5, allowsDoubleSessions: false), createdAt: monday)
        context.insert(goal)
        user.addGoal(goal)
        try context.save()

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: monday)
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: monday)
        let phase = try XCTUnwrap(plan.orderedPhases.first)

        guard case .success(let mix) = LongTermPlanner.buildCustomMix(
            selections: [(style: .functionalFitness, frequency: 5)], capacity: 5
        ) else { return XCTFail("5x Functional Fitness must be a real, constructible composition") }

        let environment = try XCTUnwrap(user.profile?.defaultTrainingEnvironment, "R5: a brand-new athlete must already have Full Gym as a real default")
        let materializationContext = TacticalMaterializationContext(
            equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
            strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness,
            trainingEnvironment: environment
        )
        let result = try StartPhaseUseCase.start(
            phase: phase, mix: mix, asOf: monday, ownerUserID: user.id,
            performanceProfile: user.performanceProfile,
            availability: UserAvailability(trainingDaysPerWeek: 5, allowsDoubleSessions: false, maxSessionsPerDay: 1),
            materializationContext: materializationContext, context: context
        )
        try context.save()

        // No component of a pure-FF mix is ever `.rmBased` — nothing should
        // be awaiting calibration at all.
        XCTAssertEqual(result.componentsAwaitingCalibration.count, 0, "a pure Functional Fitness composition must never defer to source RM calibration")

        // The exact real call RootTabView.onAppear makes, unconditionally,
        // on every launch — this is the call the known bug lead worried
        // would crash for a pure-FF-only active ProgramInstance.
        let calibrationViewModel = SourceRMCalibrationViewModel()
        calibrationViewModel.load(modelContext: context)
        XCTAssertFalse(calibrationViewModel.hasPendingCalibration, "a pure Functional Fitness plan must never route through the calibration screen")

        // The real plan actually started: exactly 5 real Sessions exist,
        // all Functional Fitness, on a real Monday-anchored full week.
        let sessions = try context.fetch(FetchDescriptor<Session>())
        XCTAssertEqual(sessions.count, 5, "a pure 5x Functional Fitness plan must materialize exactly 5 real Sessions immediately")
        XCTAssertTrue(sessions.allSatisfy { $0.status == .scheduled })
    }

    // MARK: A — recommendation path, Build Muscle, accept as-is

    func testBuildMuscleRecommendationPathProducesARealAcceptableMix() throws {
        let monday = date(2026, 1, 5)
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let goal = Goal(ownerUserID: user.id, primaryType: .muscleGain, preferences: GoalPreferences(availableTrainingDaysPerWeek: 5, allowsDoubleSessions: false), createdAt: monday)
        context.insert(goal)
        user.addGoal(goal)
        try context.save()

        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        let recommended = try XCTUnwrap(viewModel.reviewedMix, "a real recommendation must be produced for a fresh Build Muscle athlete")
        XCTAssertFalse(viewModel.isCustomMixSelected)
        XCTAssertNotNil(viewModel.recommendedMixSummary)

        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context))
        let plans = try context.fetch(FetchDescriptor<TrainingPlan>())
        XCTAssertEqual(plans.count, 1, "acceptance must create exactly one real TrainingPlan — the one authoritative write path")
        XCTAssertEqual(plans.first?.orderedPhases.first?.selectedTrainingMix?.name, recommended.name)
    }

    // MARK: B — Build Muscle, custom 3H+2FF, exact composition instantiated

    func testBuildMuscleCustomThreeHypertrophyTwoFunctionalFitnessInstantiatesExactly() throws {
        let monday = date(2026, 1, 5)
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let candidates = makeCandidates()
        let goal = Goal(ownerUserID: user.id, primaryType: .muscleGain, preferences: GoalPreferences(availableTrainingDaysPerWeek: 5, allowsDoubleSessions: false), createdAt: monday)
        context.insert(goal)
        user.addGoal(goal)
        try context.save()

        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.hypertrophy, 3), (.functionalFitness, 2)]))
        XCTAssertTrue(viewModel.isCustomMixSelected)
        let summary = try XCTUnwrap(viewModel.recommendedMixSummary)
        XCTAssertEqual(summary, "3× Hypertrophy + 2× Functional Fitness")

        // Reviewing a custom mix must never silently keep presenting the
        // system recommendation as though it were what will start.
        XCTAssertNotEqual(viewModel.systemRecommendationSummary, viewModel.recommendedMixSummary)

        _ = try? context.save()
        // Real candidate exercises are required for the real materializer
        // to actually resolve/produce Sessions rather than merely defer.
        let environment = try XCTUnwrap(user.profile?.defaultTrainingEnvironment)
        _ = environment
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context))
        let plans = try context.fetch(FetchDescriptor<TrainingPlan>())
        XCTAssertEqual(plans.count, 1)
        let selectedMix = try XCTUnwrap(plans.first?.orderedPhases.first?.selectedTrainingMix)
        XCTAssertEqual(PlanPresentation.mixSummary(selectedMix), "3× Hypertrophy + 2× Functional Fitness", "the exact athlete-selected composition, never a preset substitution, must be what is instantiated")
    }

    // MARK: D/E — invalid source frequencies are rejected before any program/session creation

    func testInvalidTwoHypertrophyThreeFunctionalFitnessIsRejectedNeverApproximated() throws {
        let result = LongTermPlanner.buildCustomMix(selections: [(style: .hypertrophy, frequency: 2), (style: .functionalFitness, frequency: 3)], capacity: 5)
        guard case .failure(.unsupportedFrequency(let style, let frequency)) = result else {
            return XCTFail("expected .unsupportedFrequency, got \(result)")
        }
        XCTAssertEqual(style, .hypertrophy)
        XCTAssertEqual(frequency, 2)
    }

    func testInvalidTwoStrengthThreeFunctionalFitnessIsRejectedNeverApproximated() throws {
        let result = LongTermPlanner.buildCustomMix(selections: [(style: .strengthTraining, frequency: 2), (style: .functionalFitness, frequency: 3)], capacity: 5)
        guard case .failure(.unsupportedFrequency(let style, let frequency)) = result else {
            return XCTFail("expected .unsupportedFrequency, got \(result)")
        }
        XCTAssertEqual(style, .strengthTraining)
        XCTAssertEqual(frequency, 2)
    }

    // MARK: I/J — R0 start truth is visible before acceptance (the real Review requirement)

    func testResolvedStartDatePreviewMatchesWhatAcceptanceActuallyProduces() throws {
        let friday = date(2026, 1, 2) // confirmed Friday
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let goal = Goal(ownerUserID: user.id, primaryType: .muscleGain, preferences: GoalPreferences(availableTrainingDaysPerWeek: 5, allowsDoubleSessions: false), createdAt: friday)
        context.insert(goal)
        user.addGoal(goal)
        try context.save()

        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context, referenceDate: friday)
        let previewedStart = try XCTUnwrap(viewModel.resolvedStartDate, "Review must show the real R0-resolved start date before acceptance, never imply the athlete starts today")
        XCTAssertEqual(Calendar.current.startOfDay(for: previewedStart), Calendar.current.startOfDay(for: date(2026, 1, 5)), "Friday acceptance must preview the following Monday, never today")

        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context))
        let phase = try XCTUnwrap((try context.fetch(FetchDescriptor<TrainingPlan>())).first?.orderedPhases.first)
        XCTAssertEqual(Calendar.current.startOfDay(for: phase.startDate), Calendar.current.startOfDay(for: previewedStart), "the previewed start date must match the real, actually-accepted phase start exactly")
    }

    func testMondayAcceptanceCanStartImmediately() throws {
        let monday = date(2026, 1, 5)
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let goal = Goal(ownerUserID: user.id, primaryType: .muscleGain, preferences: GoalPreferences(availableTrainingDaysPerWeek: 5, allowsDoubleSessions: false), createdAt: monday)
        context.insert(goal)
        user.addGoal(goal)
        try context.save()

        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context, referenceDate: monday)
        let previewedStart = try XCTUnwrap(viewModel.resolvedStartDate)
        XCTAssertEqual(Calendar.current.startOfDay(for: previewedStart), Calendar.current.startOfDay(for: monday), "a Monday acceptance previews starting immediately")
    }

    // MARK: F/G — dated objectives, single and multiple, correctly ordered

    func testSingleDatedObjectiveIsReflectedInTheRealStrategicRoute() throws {
        let asOf = date(2026, 1, 5)
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let goal = Goal(
            ownerUserID: user.id, primaryType: .muscleGain,
            preferences: GoalPreferences(availableTrainingDaysPerWeek: 5, allowsDoubleSessions: false),
            datedObjectives: [DatedObjective(kind: .bodyCompositionMilestone, date: date(2026, 6, 15))],
            createdAt: asOf
        )
        context.insert(goal)
        user.addGoal(goal)
        try context.save()

        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context, referenceDate: asOf)
        XCTAssertFalse(viewModel.phaseTypeLabels.isEmpty, "a real dated objective must produce a real multi-phase strategic route")
        XCTAssertGreaterThan(viewModel.phaseTypeLabels.count, 1, "Summer Shape must introduce a distinct phase beyond the initial Muscle Gain phase")
    }

    func testMultipleDatedObjectivesRemainCorrectlyOrdered() throws {
        let asOf = date(2026, 1, 5)
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let goal = Goal(
            ownerUserID: user.id, primaryType: .muscleGain,
            preferences: GoalPreferences(availableTrainingDaysPerWeek: 5, allowsDoubleSessions: false),
            datedObjectives: [
                DatedObjective(kind: .bodyCompositionMilestone, date: date(2026, 6, 15)),
                DatedObjective(kind: .runningEvent, date: date(2026, 9, 20)),
            ],
            createdAt: asOf
        )
        context.insert(goal)
        user.addGoal(goal)
        try context.save()

        XCTAssertEqual(goal.datedObjectives.map(\.date).sorted(), goal.datedObjectives.map(\.date), "objectives must already be in real chronological order")
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context, referenceDate: asOf)
        XCTAssertGreaterThanOrEqual(viewModel.phaseTypeLabels.count, 3, "two real dated objectives must produce a multi-phase route reflecting both")
    }

    // MARK: L — zero-config environment: a fresh athlete never manually configures equipment

    func testFreshAthleteNeverManuallyConfiguresEnvironmentThroughOnboarding() throws {
        let onboardingViewModel = OnboardingViewModel()
        onboardingViewModel.start(modelContext: context)
        onboardingViewModel.selectedGoalType = .muscleGain
        onboardingViewModel.advance(from: .goal, modelContext: context)
        onboardingViewModel.advance(from: .preferences, modelContext: context)
        XCTAssertEqual(onboardingViewModel.step, .review, "Full Gym already exists (R5) — the Environment step must never be forced")
        XCTAssertTrue(onboardingViewModel.hasDefaultTrainingEnvironment)

        let users = try context.fetch(FetchDescriptor<User>())
        let environment = try XCTUnwrap(users.first?.profile?.defaultTrainingEnvironment)
        XCTAssertEqual(environment.name, "Full Gym")
        XCTAssertTrue(environment.isBuiltIn)
    }

    // MARK: K — editing an earlier onboarding answer invalidates/recomputes dependent state truthfully

    func testChangingGoalRecomputesRecommendationTruthfullyWithoutDuplicatePlans() throws {
        let asOf = date(2026, 1, 5)
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let goal = Goal(ownerUserID: user.id, primaryType: .muscleGain, preferences: GoalPreferences(availableTrainingDaysPerWeek: 5, allowsDoubleSessions: false), createdAt: asOf)
        context.insert(goal)
        user.addGoal(goal)
        try context.save()

        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context, referenceDate: asOf)
        let firstSummary = viewModel.recommendedMixSummary

        // The athlete goes back and changes their main goal.
        goal.primaryType = .generalStrength
        try context.save()
        viewModel.load(modelContext: context, referenceDate: asOf)
        let secondSummary = viewModel.recommendedMixSummary

        XCTAssertNotEqual(firstSummary, secondSummary, "changing the goal must produce a genuinely different, truthfully recomputed recommendation")
        XCTAssertFalse(viewModel.isCustomMixSelected, "a fresh load after an edit must never carry over a stale prior custom-mix selection state")

        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context))
        let plans = try context.fetch(FetchDescriptor<TrainingPlan>())
        XCTAssertEqual(plans.count, 1, "editing before acceptance must never leave behind a duplicate accepted plan")
    }

    // MARK: NEW FINDING investigation — milestone-only Summer Shape (no paired running event),
    // through the REAL production write path (OnboardingViewModel.createOrUpdateGoal), which
    // leaves Goal.datedObjectives EMPTY and stores intent solely in Goal.milestoneDate.
    func testMilestoneOnlySummerShapeThroughRealOnboardingWritePathProducesAFeasiblePlan() throws {
        let asOf = date(2026, 1, 2)
        let onboardingViewModel = OnboardingViewModel()
        onboardingViewModel.start(modelContext: context)
        onboardingViewModel.selectedGoalType = .muscleGain
        onboardingViewModel.availableTrainingDaysPerWeek = 5
        onboardingViewModel.hasMilestone = true
        onboardingViewModel.milestoneDate = date(2026, 6, 15)
        onboardingViewModel.advance(from: .goal, modelContext: context)
        onboardingViewModel.advance(from: .preferences, modelContext: context)

        let users = try context.fetch(FetchDescriptor<User>())
        let goal = try XCTUnwrap(users.first?.goals.first { $0.status == .active })
        XCTAssertNil(goal.targetDate)
        XCTAssertEqual(goal.milestoneDate, date(2026, 6, 15))
        XCTAssertTrue(goal.datedObjectives.isEmpty, "confirms the real production write path for a milestone-only goal leaves datedObjectives empty")

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        XCTAssertEqual(proposal.feasibility, .feasible, "NEW FINDING under investigation: a milestone-only Summer Shape ~24 weeks out, through the REAL onboarding write path (legacy proposeMilestoneAnchoredPhases), may report .infeasible even though the newer datedObjectives-based reconciliation path handles the same real-world date gracefully")
    }

}
