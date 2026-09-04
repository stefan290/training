import Foundation
import SwiftData
import Observation

/// Stage V1.Checkpoint 2: the athlete's real first strategic-plan
/// selection — `Goal` -> `LongTermPlanner.proposeStrategicPlan`/
/// `.proposeTrainingMix` -> athlete review -> `AcceptStrategicPlanUseCase`
/// -> `StartPhaseUseCase.start`. Never a second planner: every candidate
/// shown here is the exact, unmodified engine output.
///
/// **`proposeTrainingMix` is called exactly ONCE per `load`** — the same
/// discipline `StrategicTransitionViewModel` already establishes and
/// documents (ranking reads `goal.preferences`, real mutable state, so a
/// second independent call is not provably guaranteed to return the same
/// candidate). `reviewedMix` is the one resolved candidate this type ever
/// holds; `acceptAndStart` uses it directly, never re-proposes.
///
/// **The first real `TrainingPhase` does not exist yet at `load` time** —
/// unlike `StrategicTransitionViewModel` (which previews an already-real,
/// already-`.planned` next phase), Checkpoint 2 has no persisted
/// `TrainingPlan` at all before acceptance. `proposeTrainingMix` needs a
/// real `TrainingPhase` (it reads `.startDate`/`.type`), so `load` builds
/// an uninserted, in-memory preview phase from the proposal's own first
/// `ProposedPhase` — never persisted, discarded once acceptance creates
/// the real row from the exact same values. This mirrors the codebase's
/// own existing "uninserted, in-memory candidate held until an explicit
/// acceptance step" pattern for `TrainingMix` itself (`CandidateTrainingMix`'s
/// own doc comment).
@MainActor
@Observable
final class StrategicPlanSelectionViewModel {
    private(set) var goal: Goal?
    private(set) var proposal: StrategicPlanProposal?
    /// The ONE `TrainingMix` candidate resolved during `load` — an
    /// uninserted, in-memory value until `acceptAndStart` commits it via
    /// `StartPhaseUseCase.start` (which is what actually sets `.kind`
    /// to `.selected` — mirrors `StrategicTransitionViewModel.reviewedMix`
    /// exactly, including why a second `proposeTrainingMix` call is unsafe).
    private(set) var reviewedMix: TrainingMix?
    private(set) var isAccepting = false
    private(set) var didSucceed = false
    private(set) var errorMessage: String?
    /// `true` when acceptance/start failed for a reason recoverable
    /// through Training Environment configuration — detected structurally
    /// via `TrainingEnvironmentRecoverableError`, never by matching
    /// `errorMessage` (same discipline as `StrategicTransitionViewModel`).
    private(set) var needsTrainingEnvironment = false
    private(set) var componentsAwaitingCalibrationCount: Int?
    /// Stage V1 dogfooding fix (Plan Recommendation Integrity): every real
    /// candidate `LongTermPlanner.proposeTrainingMix` returned this load —
    /// never discarded. `alternatives` (below) is derived from this array,
    /// never a second, independent planner call (same "propose once" rule
    /// `reviewedMix` itself already follows).
    private(set) var candidates: [CandidateTrainingMix] = []
    /// V1 "Explicit Weekly Composition" checkpoint (Checkpoint 1): the
    /// uninserted, in-memory phase `load()` already builds — kept so
    /// `buildCustomMix` can evaluate a custom composition against the
    /// exact same phase window `proposeTrainingMix` used, without a
    /// second, independently-computed phase.
    private var previewPhase: TrainingPhase?
    /// The engine's own top pick this load, kept SEPARATELY from
    /// `reviewedMix` once the athlete builds/selects a custom composition
    /// — so "TrainingOS recommends X" can always still be shown even when
    /// "your selected mix" is something else entirely (PLAN SCREEN
    /// requirement: never let the athlete lose sight of what will
    /// actually start vs. what the system would have suggested).
    private(set) var recommendedMix: TrainingMix?
    /// `true` once the athlete has built/accepted a "Build My Own Mix"
    /// composition — `reviewedMix` is then that custom `TrainingMix`, not
    /// one of `candidates`. Reset to `false` by `selectAlternative`/
    /// `selectRecommended`.
    private(set) var isCustomMixSelected = false
    /// The raw (style, frequency) input behind the current custom
    /// `reviewedMix`, if any — kept only so `acceptAndStart` can merge the
    /// real `ModalityPreference`s a Running/Cycling component needs
    /// (`LongTermPlanner.requiredModalityPreferences`) into `Goal
    /// .preferences` at the one moment a selection becomes authoritative,
    /// never earlier.
    private var customMixSelections: [(style: TrainingStyle, frequency: Int)] = []
    private(set) var customMixValidationError: LongTermPlanner.CustomMixValidationError?
    /// The real, unmodified `GoalAlignmentEvaluator` result for the
    /// current custom `reviewedMix` — `nil` whenever `reviewedMix` came
    /// from `candidates` instead (a `CandidateTrainingMix` already carries
    /// its own `.alignment`, this is only needed for the custom path).
    /// CLAUDE.md rule 18: a poor rating here is disclosed, never blocked.
    private(set) var customMixAlignment: GoalAlignment?

    var goalTypeLabel: String? { goal.map { PlanPresentation.goalTypeLabel($0.primaryType) } }
    /// The athlete's real weekly training-day capacity — the one number
    /// the "Build My Own Mix" editor must never let a composition exceed.
    var weeklyCapacity: Int { goal?.preferences?.availableTrainingDaysPerWeek ?? 4 }
    /// TE.1's own existing equipment-compatibility rule, unmodified —
    /// Cycling stays gated on a real bike being available, exactly like
    /// every other TE.1-gated activity in this app.
    var cyclingSupported: Bool {
        let environment = goal?.user?.profile?.defaultTrainingEnvironment
        return TrainingEnvironmentCompatibilityRule.evaluate(required: ActivityType.cycling.requiredEquipment, environment: environment) == .compatible
    }
    /// This is a planner RECOMMENDATION, not yet a selected/accepted
    /// configuration — `TrainingMix.kind` only actually becomes `.selected`
    /// inside `StartPhaseUseCase.start`, the moment `acceptAndStart`
    /// commits it. Computed directly from `reviewedMix`, never a second
    /// independent read (same reasoning as `StrategicTransitionViewModel
    /// .previewMixSummary`).
    var recommendedMixSummary: String? { reviewedMix.map(PlanPresentation.mixSummary) }
    /// Always the engine's own top pick, regardless of what the athlete
    /// is currently reviewing — distinct from `recommendedMixSummary`
    /// above (which reflects whatever `reviewedMix` currently is). The
    /// PLAN SCREEN requirement: "TrainingOS recommends" must stay visible
    /// even once "your selected mix" is a custom composition.
    var systemRecommendationSummary: String? { recommendedMix.map(PlanPresentation.mixSummary) }
    /// V1 "Goal ≠ Training Method" checkpoint: athlete-language "why this
    /// fits" — e.g. "Recommended because your goal is to get stronger and
    /// you said you enjoy hypertrophy and functional fitness." Derived
    /// ONLY from real data already on hand this load (the goal's own Main
    /// Goal label, plus whichever `TrainingStyle`s the athlete's real
    /// stated `preferredModalities` and the real recommended mix's own
    /// components both actually contain) — never fabricated copy, and
    /// never a second planner call. The preference clause only appears
    /// when the planner's own `.adherencePreferencePromotedAlternative`
    /// reason code is present, i.e. a stated preference genuinely changed
    /// which candidate was recommended (CLAUDE.md rule 16's discipline:
    /// read the typed reason code, never re-derive/guess at intent).
    var recommendationExplanation: String? {
        guard let goal, let mix = recommendedMix else { return nil }
        var text = "Recommended because your goal is to \(PlanPresentation.mainGoalLabel(goal.primaryType).lowercased())"

        let wasPreferencePromoted = candidates.first { $0.mix.id == mix.id }?
            .reasonCodes.contains(.adherencePreferencePromotedAlternative) ?? false
        if wasPreferencePromoted {
            let preferredSystems = Set(goal.preferences?.preferredModalities.map(\.system) ?? [])
            let mixSystems = Set(mix.orderedComponents.compactMap(\.programmingSystem))
            let matchedStyles = TrainingStyle.allCases.filter { style in
                !Set(style.modalityPreferences.map(\.system)).isDisjoint(with: preferredSystems.intersection(mixSystems))
            }
            if !matchedStyles.isEmpty {
                let names = matchedStyles.map(PlanPresentation.trainingStyleLabel).sorted().joined(separator: " and ")
                text += ", and you said you enjoy \(names)"
            }
        }
        text += "."
        return text
    }
    var phaseTypeLabels: [String] { proposal?.phases.map { PlanPresentation.phaseTypeLabel($0.type) } ?? [] }
    /// Dated Objectives + 10K Strategic Reconciliation V1: true when any
    /// proposed phase's own prep window was compressed below its ideal
    /// lead time because an earlier dated objective's own phase ran late
    /// into it — the real, structural signal for the locked "truthfully
    /// disclose when available time is shorter than normal" requirement,
    /// never a guessed heuristic.
    var hasCompressedObjectivePrep: Bool {
        proposal?.phases.contains { $0.reasonCodes.contains(.objectivePrepCompressed) } ?? false
    }
    var isInfeasible: Bool { proposal?.feasibility == .infeasible }
    /// Dated Objectives + 10K Strategic Reconciliation V1: distinct from
    /// `isInfeasible` — a genuine, athlete-facing trade-off ("two dated
    /// goals can't both be true"), never a "not enough calendar time"
    /// message (CLAUDE.md rule 18/19's discipline extended to this new
    /// vocabulary).
    var hasObjectivesConflict: Bool { proposal?.feasibility == .objectivesConflict }
    /// A feasible plan (calendar-wise) with zero executable `TrainingMix`
    /// candidate — a real, distinct failure mode from infeasibility
    /// (CLAUDE.md rule 18: never conflate the two vocabularies).
    var hasNoCompatibleMix: Bool { proposal != nil && proposal?.feasibility == .feasible && reviewedMix == nil }
    /// Stage V1 dogfooding fix: every OTHER real, genuinely feasible
    /// candidate this load produced — `alignment.rating` at or above
    /// `LongTermPlanner`'s own real compatibility gate, exactly the same
    /// bar the engine itself already uses to decide `.recommended`
    /// eligibility. An infeasible/poor candidate is never offered as a
    /// selectable alternative, never merely hidden by omission after the
    /// fact.
    var alternatives: [CandidateTrainingMix] {
        candidates.filter {
            $0.mix.id != reviewedMix?.id && $0.mix.id != recommendedMix?.id
                && $0.alignment.rating >= LongTermPlanner.compatibilityThreshold
        }
    }

    func load(modelContext: ModelContext) {
        errorMessage = nil
        didSucceed = false
        needsTrainingEnvironment = false
        componentsAwaitingCalibrationCount = nil
        isCustomMixSelected = false
        customMixSelections = []
        customMixValidationError = nil
        customMixAlignment = nil

        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        guard let activeGoal = users.first?.goals.first(where: { $0.status == .active }) else {
            goal = nil
            proposal = nil
            reviewedMix = nil
            recommendedMix = nil
            candidates = []
            previewPhase = nil
            return
        }
        goal = activeGoal

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: activeGoal, asOf: Date())
        self.proposal = proposal

        guard proposal.feasibility == .feasible, let firstProposedPhase = proposal.phases.first else {
            reviewedMix = nil
            recommendedMix = nil
            candidates = []
            previewPhase = nil
            return
        }
        let previewPhase = TrainingPhase(
            type: firstProposedPhase.type, startDate: firstProposedPhase.startDate,
            endDate: firstProposedPhase.endDate, priorityRule: firstProposedPhase.priorityRule
        )
        self.previewPhase = previewPhase
        let proposedCandidates = LongTermPlanner.proposeTrainingMix(phase: previewPhase, goal: activeGoal)
        candidates = proposedCandidates
        // Stage V1 dogfooding fix: ONLY a candidate the real ranking engine
        // itself assigned `.recommended` may ever be labeled "RECOMMENDED"
        // to the athlete — the previous `?? candidates.first` fallback
        // could silently substitute an arbitrary, non-recommended (even
        // infeasible) candidate and the View would still call it
        // "RECOMMENDED TRAINING." `rankCandidateMixes` never assigns
        // `.recommended` to a candidate that didn't clear its own real
        // compatibility gate (`LongTermPlanner.swift`'s §5a) — so `nil`
        // here means "no compatible mix," never a mislabeled fallback.
        let recommended = proposedCandidates.first { $0.roles.contains(.recommended) }?.mix
        reviewedMix = recommended
        recommendedMix = recommended
    }

    /// Stage V1 dogfooding fix (Part 4 — real alternatives): the athlete
    /// picks among real, already-ranked planner candidates only — never a
    /// custom-built mix. Only ever called with a member of `alternatives`
    /// (already feasibility-filtered); re-asserts membership defensively
    /// rather than trusting the caller.
    func selectAlternative(_ candidate: CandidateTrainingMix) {
        guard alternatives.contains(where: { $0.mix.id == candidate.mix.id }) else { return }
        reviewedMix = candidate.mix
        isCustomMixSelected = false
        customMixSelections = []
        customMixAlignment = nil
    }

    /// Returns to the engine's own top pick after having reviewed a
    /// custom composition or alternative.
    func selectRecommended() {
        guard let recommendedMix else { return }
        reviewedMix = recommendedMix
        isCustomMixSelected = false
        customMixSelections = []
        customMixAlignment = nil
    }

    /// V1 "Explicit Weekly Composition" checkpoint (Checkpoint 1): "BUILD
    /// MY OWN MIX" — constructs and reviews a real `TrainingMix` directly
    /// from the athlete's explicit (style, frequency) choices, bypassing
    /// `candidateMixTemplates`'s fixed preset list entirely (the core
    /// "no planner prison" proof). Returns `false` and sets
    /// `customMixValidationError` on any rejection (unsupported
    /// frequency, over capacity, empty, conflicting endurance styles) —
    /// `reviewedMix`/`isCustomMixSelected` are left untouched on failure,
    /// never partially applied.
    @discardableResult
    func buildCustomMix(selections: [(style: TrainingStyle, frequency: Int)]) -> Bool {
        guard let goal, let previewPhase else { return false }
        customMixValidationError = nil
        switch LongTermPlanner.buildCustomMix(selections: selections, capacity: weeklyCapacity) {
        case .failure(let error):
            customMixValidationError = error
            return false
        case .success(let mix):
            customMixAlignment = LongTermPlanner.evaluateCustomMix(mix, phase: previewPhase, goal: goal)
            reviewedMix = mix
            isCustomMixSelected = true
            customMixSelections = selections
            return true
        }
    }

    /// The one deliberate write this ViewModel performs. Guarded against
    /// re-entry two ways: `isAccepting` (blocks a genuine concurrent
    /// double-tap) and `didSucceed` (blocks a second tap after success,
    /// since a second `AcceptStrategicPlanUseCase.accept` call against the
    /// same `Goal` would create a second, duplicate `TrainingPlan` — the
    /// use case itself has no "already accepted this exact proposal"
    /// guard, so the ViewModel owns that discipline, same shape as
    /// `StrategicTransitionViewModel.startTransition`).
    @discardableResult
    func acceptAndStart(modelContext: ModelContext) -> Bool {
        guard !isAccepting, !didSucceed else { return false }
        guard let goal, let proposal, let mix = reviewedMix else {
            errorMessage = "No plan recommendation is available yet."
            return false
        }
        isAccepting = true
        defer { isAccepting = false }
        errorMessage = nil
        needsTrainingEnvironment = false

        // V1 "Explicit Weekly Composition" checkpoint: a custom mix's
        // Running/Cycling component has no per-component `ActivityType`
        // of its own — `proposeProgram`'s `preferredActivityType` resolves
        // it from `Goal.preferences.preferredModalities` (the same
        // existing mechanism `TrainingStyle`'s own soft-preference path
        // already uses). Merged here — the one moment this composition
        // becomes authoritative — additively (never removing an existing
        // stated preference), never at mere construction/review time.
        if isCustomMixSelected {
            var preferences = goal.preferences ?? GoalPreferences()
            let required = LongTermPlanner.requiredModalityPreferences(for: customMixSelections)
            for preference in required where !preferences.preferredModalities.contains(preference) {
                preferences.preferredModalities.append(preference)
            }
            goal.preferences = preferences
        }

        do {
            let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: modelContext, decidedAt: Date())
            guard let firstPhase = plan.orderedPhases.first else {
                errorMessage = "Your plan could not be started. Nothing was changed."
                return false
            }

            // Same established candidate-pool pattern every other real
            // caller (SeedAnnualPlanJourney, PhaseDetailViewModel,
            // StrategicTransitionViewModel) already uses — including the
            // same KNOWN DOMAIN GAP (no persisted equipment-inventory
            // model yet, tracked as a pre-existing FOLLOW-UP, not
            // introduced here).
            let exercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
            let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
            let user = users.first
            let environment = user?.profile?.defaultTrainingEnvironment
            let preferences = goal.preferences
            let trainingDays = preferences?.availableTrainingDaysPerWeek ?? 4
            let allowsDoubles = preferences?.allowsDoubleSessions ?? false
            let materializationContext = TacticalMaterializationContext(
                equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
                strengthCandidateExercises: exercises,
                functionalFitnessCandidateExercises: exercises,
                trainingEnvironment: environment
            )

            let result = try StartPhaseUseCase.start(
                phase: firstPhase, mix: mix, asOf: Date(), ownerUserID: goal.ownerUserID,
                performanceProfile: user?.performanceProfile,
                availability: UserAvailability(
                    trainingDaysPerWeek: trainingDays, allowsDoubleSessions: allowsDoubles,
                    maxSessionsPerDay: allowsDoubles ? 2 : 1
                ),
                materializationContext: materializationContext, context: modelContext
            )
            componentsAwaitingCalibrationCount = result.componentsAwaitingCalibration.count
            // Explicit save — this single write unlocks the entire rest of
            // the app (Today/Plan/execution all query fresh from this
            // context right after `onComplete()` switches the root view).
            // Relationship traversal on an already-loaded object reflects
            // this same context's pending inserts immediately, but a
            // caller one screen away starting a brand-new query should
            // never depend on SwiftUI's own autosave timing for something
            // this durability-critical (mirrors CLAUDE.md rule 20's "durable
            // at each meaningful action" discipline).
            try? modelContext.save()
            didSucceed = true
            return true
        } catch {
            if let recoveryMessage = trainingEnvironmentRecoveryMessage(for: error) {
                needsTrainingEnvironment = true
                errorMessage = recoveryMessage
            } else if error is StrategicPlanAcceptanceError {
                errorMessage = "This plan could not be created from your current goal. Please review your goal and try again."
            } else {
                errorMessage = "Your plan could not be started. Nothing was changed."
            }
            return false
        }
    }
}
