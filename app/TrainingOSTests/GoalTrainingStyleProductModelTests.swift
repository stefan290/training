import XCTest
import SwiftData
@testable import TrainingOS

/// V1 "Goal ≠ Training Method" product model correction: proves (1) the
/// Main Goal (OUTCOME) / Training Style (HOW) / Dated Objective (WHAT/WHEN)
/// vocabularies are kept distinct, (2) the real root-cause fix for the
/// dogfooding bug ("General Strength + especially want Hypertrophy/
/// Functional Fitness" recommending 4x Powerlifting regardless) — a real
/// candidate-library gap for `.strength` phases, not a ranking defect —
/// through the real production path (`OnboardingViewModel` ->
/// `Goal`/`GoalPreferences` -> `LongTermPlanner.proposeTrainingMix`/
/// `rankCandidateMixes` -> `StrategicPlanSelectionViewModel`), never a
/// resolver/planner-unit-only test. Every candidate asserted against is a
/// REAL, pre-existing `LongTermPlanner` template — nothing here fabricates
/// a mix.
@MainActor
final class GoalTrainingStyleProductModelTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    /// Mirrors `StrategicPlanSelectionTests.makeOnboardedAthlete` exactly —
    /// the real, fully TE.1-equipped "completed onboarding" state.
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

    // MARK: 1 — Main Goal vocabulary is outcomes only

    func testMainGoalOptionsExcludeFunctionalFitnessAndUseOutcomePhrasing() {
        XCTAssertFalse(PlanPresentation.mainGoalOptions.contains(.functionalFitness), "Functional Fitness is a Training Style, never a Main Goal option")
        XCTAssertEqual(Set(PlanPresentation.mainGoalOptions), [.muscleGain, .generalStrength, .fatLoss, .enduranceEvent, .maintenance])
        XCTAssertEqual(PlanPresentation.mainGoalLabel(.enduranceEvent), "Improve Fitness & Endurance", "never the raw internal 'Endurance Event' phrase on the Main Goal screen")
        XCTAssertEqual(PlanPresentation.mainGoalLabel(.generalStrength), "Get Stronger")
        XCTAssertEqual(PlanPresentation.mainGoalLabel(.muscleGain), "Build Muscle")
        XCTAssertEqual(PlanPresentation.mainGoalLabel(.fatLoss), "Lose Fat")
        XCTAssertEqual(PlanPresentation.mainGoalLabel(.maintenance), "Maintain My Fitness")
    }

    // MARK: 2 — Training Style maps deterministically to real domain preferences

    func testTrainingStyleMapsDeterministicallyToRealDomainPreferences() {
        XCTAssertEqual(TrainingStyle.hypertrophy.modalityPreferences, [ModalityPreference(system: .hypertrophy)])
        XCTAssertEqual(TrainingStyle.strengthTraining.modalityPreferences, [ModalityPreference(system: .powerlifting)], "Strength Training maps to Powerlifting, distinct from the separate Hypertrophy style")
        XCTAssertEqual(TrainingStyle.functionalFitness.modalityPreferences, [ModalityPreference(system: .functionalFitness)])
        XCTAssertEqual(TrainingStyle.running.modalityPreferences, [
            ModalityPreference(system: .steadyState, activityType: .running),
            ModalityPreference(system: .interval, activityType: .running),
        ])
        XCTAssertEqual(TrainingStyle.cycling.modalityPreferences, [
            ModalityPreference(system: .steadyState, activityType: .cycling),
            ModalityPreference(system: .interval, activityType: .cycling),
        ])
        // Determinism — calling it twice must produce identical results.
        for style in TrainingStyle.allCases {
            XCTAssertEqual(style.modalityPreferences, style.modalityPreferences)
        }
    }

    // MARK: 3 — Running is selectable as a style independent of any dated objective

    func testRunningSelectableAsTrainingStyleIndependentOfAnyDatedObjective() throws {
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .muscleGain
        viewModel.preferredTrainingStyles = [.running]
        // Explicitly no dated objective of any kind.
        XCTAssertFalse(viewModel.hasMilestone)
        XCTAssertFalse(viewModel.hasRunningEvent)

        viewModel.advance(from: .goal, modelContext: context)
        // V1 "Explicit Weekly Composition" checkpoint: `.modalityPreferences`
        // was removed from the primary flow — `createOrUpdateGoal` now
        // fires on the `.preferences` step's own advance. The underlying
        // `preferredTrainingStyles` -> `GoalPreferences.preferredModalities`
        // write path this test proves is otherwise unchanged.
        viewModel.advance(from: .preferences, modelContext: context)

        let goal = try XCTUnwrap((try context.fetch(FetchDescriptor<Goal>())).first)
        XCTAssertTrue(goal.datedObjectives.isEmpty, "Running as a style must never create a dated objective")
        let preferred = goal.preferences?.preferredModalities ?? []
        XCTAssertEqual(preferred.count, TrainingStyle.running.modalityPreferences.count)
        for expected in TrainingStyle.running.modalityPreferences {
            XCTAssertTrue(preferred.contains(expected), "missing expected preference \(expected)")
        }
    }

    // MARK: 4 — Steady State / Intervals / raw ProgrammingSystemKind never appear as athlete-facing style labels

    func testSteadyStateAndIntervalNeverAppearAsTrainingStyleLabels() {
        let labels = Set(TrainingStyle.allCases.map(PlanPresentation.trainingStyleLabel))
        for forbidden in ["Steady State", "Intervals", "Interval", "ProgrammingSystemKind"] {
            XCTAssertFalse(labels.contains(forbidden), "'\(forbidden)' must never be an athlete-facing Training Style label")
        }
        XCTAssertEqual(labels, ["Hypertrophy", "Strength Training", "Functional Fitness", "Running", "Cycling"])
    }

    // MARK: 5 — THE CORE BUG FIX: General Strength + especially-want Hypertrophy/Functional Fitness

    /// Reproduces the exact reported dogfooding bug: Main Goal = General
    /// Strength (`.generalStrength` -> `PhaseType.strength`), 4 training
    /// days, "especially want" Hypertrophy + Functional Fitness, no
    /// exclusions. Before this checkpoint's fix, `.strength` had exactly
    /// ONE candidate template (`strengthFocusedMix()`, 4x Powerlifting) —
    /// no stated preference could ever change the outcome. This proves the
    /// real recommendation now reflects the stated preference using ONLY
    /// real, pre-existing `LongTermPlanner` templates, and that the
    /// highest-goal-alignment candidate is still shown, never hidden
    /// (CLAUDE.md rule 17).
    func testGeneralStrengthWithHypertrophyAndFunctionalFitnessPreferenceReachesRealRecommendation() throws {
        try makeOnboardedAthlete(
            goalType: .generalStrength, trainingDays: 4, allowsDoubles: false,
            preferredModalities: TrainingStyle.hypertrophy.modalityPreferences + TrainingStyle.functionalFitness.modalityPreferences
        )
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)

        let allCandidateNames = Set(viewModel.candidates.map(\.mix.name))
        XCTAssertEqual(allCandidateNames, ["Focused Powerlifting", "Strength Plus Variety"], "no fabricated mix — only real, pre-existing LongTermPlanner templates")

        let recommended = try XCTUnwrap(viewModel.reviewedMix, "a real recommendation must be produced")
        let recommendedSystems = Set(recommended.orderedComponents.compactMap(\.programmingSystem))
        XCTAssertFalse(
            recommendedSystems.isDisjoint(with: [.hypertrophy, .functionalFitness]),
            "the recommendation must reflect the athlete's stated Hypertrophy/Functional Fitness preference — it must not default to Powerlifting-only regardless of stated preference"
        )

        XCTAssertTrue(
            viewModel.candidates.contains { $0.mix.name == "Focused Powerlifting" },
            "the highest-goal-alignment candidate must still be shown, never hidden, when a preference promotes an alternative (CLAUDE.md rule 17)"
        )
    }

    /// Backward-compatibility regression: with NO stated preference, a
    /// General Strength goal must still recommend the real Powerlifting
    /// path exactly as before this checkpoint (matches
    /// `ProgramInstanceExerciseSlotResolutionTests`'s own documented
    /// assumption) — adding a second `.strength` candidate must never
    /// change the no-preference outcome.
    func testGeneralStrengthWithNoPreferenceStillRecommendsFocusedPowerliftingRegression() throws {
        try makeOnboardedAthlete(goalType: .generalStrength, trainingDays: 4)
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        let recommended = try XCTUnwrap(viewModel.reviewedMix)
        XCTAssertEqual(recommended.name, "Focused Powerlifting")
        XCTAssertEqual(recommended.orderedComponents.first?.programmingSystem, .powerlifting)
    }

    // MARK: 6 — Running preference for a Build Muscle goal (no event)

    /// Build Muscle + especially-want Hypertrophy + Running, no dated
    /// objective. Both real Muscle Gain templates already contain a
    /// Hypertrophy component; proves the Running preference (Steady
    /// State/Interval + `.running`) genuinely reaches the real ranking
    /// architecture and is presentable, without fabricating anything.
    func testBuildMuscleWithHypertrophyAndRunningPreferenceReachesRealRecommendation() throws {
        try makeOnboardedAthlete(
            goalType: .muscleGain, trainingDays: 5, allowsDoubles: false,
            preferredModalities: TrainingStyle.hypertrophy.modalityPreferences + TrainingStyle.running.modalityPreferences
        )
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)

        let allCandidateNames = Set(viewModel.candidates.map(\.mix.name))
        XCTAssertEqual(allCandidateNames, ["Focused Hypertrophy", "Strength Plus Variety"], "no fabricated mix")

        let selectable = [viewModel.reviewedMix].compactMap { $0 } + viewModel.alternatives.map(\.mix)
        XCTAssertTrue(
            selectable.contains { $0.orderedComponents.contains { $0.programmingSystem == .steadyState } },
            "a Running-compatible (steady-state) real candidate must be reachable as the recommendation or a real alternative"
        )
    }

    // MARK: 7 — Hard exclusions still work through the same style mapping

    /// Disliking Functional Fitness (system-wide, via the Training Style
    /// mapping) must never let it be PROMOTED into the recommendation —
    /// the real, pre-existing `isPreferenceAligned` system-wide veto,
    /// reused unchanged, verified through the new Training Style vocabulary
    /// rather than a raw `ProgrammingSystemKind` value.
    func testDislikedFunctionalFitnessIsNeverPromotedForStrengthGoal() throws {
        try makeOnboardedAthlete(
            goalType: .generalStrength, trainingDays: 4, allowsDoubles: false,
            preferredModalities: TrainingStyle.hypertrophy.modalityPreferences,
            dislikedModalities: TrainingStyle.functionalFitness.modalityPreferences
        )
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        let recommended = try XCTUnwrap(viewModel.reviewedMix)
        XCTAssertFalse(
            recommended.orderedComponents.contains { $0.programmingSystem == .functionalFitness },
            "a disliked style must never be promoted into the recommendation"
        )
    }

    // MARK: 8/9 — Other Compatible Options are real candidates; selecting one starts exactly that mix

    func testOtherCompatibleOptionsAreRealCandidatesForTheStrengthScenario() throws {
        try makeOnboardedAthlete(
            goalType: .generalStrength, trainingDays: 4, allowsDoubles: false,
            preferredModalities: TrainingStyle.hypertrophy.modalityPreferences + TrainingStyle.functionalFitness.modalityPreferences
        )
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        for alternative in viewModel.alternatives {
            XCTAssertTrue(viewModel.candidates.contains { $0.mix.id == alternative.mix.id }, "every alternative must be a real, planner-returned candidate")
        }
    }

    func testSelectingAlternativeStartsExactlyThatMixForTheStrengthScenario() throws {
        try makeOnboardedAthlete(
            goalType: .generalStrength, trainingDays: 4, allowsDoubles: false,
            preferredModalities: TrainingStyle.hypertrophy.modalityPreferences + TrainingStyle.functionalFitness.modalityPreferences
        )
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        guard let alternative = viewModel.alternatives.first else {
            return XCTFail("this scenario must produce at least one real alternative")
        }
        viewModel.selectAlternative(alternative)
        XCTAssertEqual(viewModel.reviewedMix?.id, alternative.mix.id)
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context))
        let plans = try context.fetch(FetchDescriptor<TrainingPlan>())
        let startedMixName = try XCTUnwrap(plans.first?.orderedPhases.first?.selectedTrainingMix?.name)
        XCTAssertEqual(startedMixName, alternative.mix.name, "accepting after selecting an alternative must start exactly that alternative, never the original recommendation")
    }

    // MARK: 10 — the ViewModel's own state keeps Main Goal / Training Styles / Working Toward distinct

    func testOnboardingViewModelKeepsMainGoalTrainingStylesAndWorkingTowardAsDistinctState() {
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .generalStrength
        viewModel.preferredTrainingStyles = [.hypertrophy, .functionalFitness]
        viewModel.hasMilestone = true
        viewModel.milestoneDate = Date().addingTimeInterval(120 * 86400)

        // Three independent axes — changing one must never change another.
        XCTAssertEqual(viewModel.selectedGoalType, .generalStrength)
        XCTAssertEqual(viewModel.preferredTrainingStyles, [.hypertrophy, .functionalFitness])
        XCTAssertTrue(viewModel.hasMilestone)
        XCTAssertFalse(viewModel.hasRunningEvent)
    }

    // MARK: 11 — recommendation explanation is athlete-language, derived from real data only

    func testRecommendationExplanationNamesRealGoalAndMatchedPreferredStyles() throws {
        try makeOnboardedAthlete(
            goalType: .generalStrength, trainingDays: 4, allowsDoubles: false,
            preferredModalities: TrainingStyle.hypertrophy.modalityPreferences + TrainingStyle.functionalFitness.modalityPreferences
        )
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context)
        let explanation = try XCTUnwrap(viewModel.recommendationExplanation)
        XCTAssertTrue(explanation.contains("to get stronger"), "must name the real Main Goal in athlete language, never an internal enum name")
        XCTAssertFalse(explanation.contains("ProgrammingSystemKind"))
        XCTAssertFalse(explanation.contains("Steady State"))
    }
}
