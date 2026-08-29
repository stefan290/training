import Foundation
import SwiftData
import Observation

/// Loads everything one `TrainingPhase` needs for its detail screen —
/// mirrors `PlanViewModel`'s exact shape (`@Observable`, plain
/// `load(...)`, broad fetch + Swift-side filtering). One ViewModel,
/// branching on `phase.status` at the View layer, never a parallel
/// phase-detail mechanism per system/status.
///
/// **`load` never writes anything.** Every property `load` populates is
/// derived from already-persisted state — it never creates, materializes,
/// or mutates a `Session`/`ProgramInstance`/`TrainingMix`. Stage 10R.2B
/// adds the one deliberate exception: `startNextHypertrophyPhase`, a
/// single, explicit, user-initiated write (never called by `load` or any
/// other read path) that starts the real Mesocycle-to-Mesocycle
/// transition (`STAGE3_DECISION_MEMO.md` Decision A1 — user-initiated,
/// never automatic).
@Observable
final class PhaseDetailViewModel {
    /// One component of an upcoming phase's *preview* mix, paired with
    /// whichever `ProgramDefinition` `LongTermPlanner.previewProgramCandidate`
    /// currently ranks first for it — purely informational, never a real
    /// `ProgramInstance`. `previewProgramDefinition` lives only in the
    /// disposable scratch context `load` builds for this computation; it
    /// is never the same object a real phase start would materialize.
    struct UpcomingComponentPreview: Identifiable {
        var id: UUID { component.id }
        var component: TrainingMixComponent
        var previewProgramDefinition: ProgramDefinition?
    }

    private(set) var phase: TrainingPhase?
    private(set) var recommendedMix: TrainingMix?
    private(set) var selectedMix: TrainingMix?
    /// The components actually driving execution — the selected mix's,
    /// falling back to the recommended mix's only when nothing was ever
    /// selected (mirrors `TrainingMix`'s own doc comment: a `.selected`
    /// mix always wins over the recommendation once one exists).
    private(set) var activeComponents: [TrainingMixComponent] = []
    /// Only populated for a phase that hasn't started and has no stored
    /// mix of its own yet (`recommendedMix`/`selectedMix` both `nil`) —
    /// a live, read-only re-run of the SAME `LongTermPlanner` ranking a
    /// real phase start would use, computed fresh on every `load` rather
    /// than cached, since a future phase's eventual real recommendation
    /// may legitimately differ once it actually starts — e.g. the
    /// preceding phase's own selected mix (`LongTermPlanner.PlanningContext
    /// .previousTrainingMix`) could still change between now and then.
    /// Never claims a "readiness" signal — no such concept exists
    /// anywhere in this app today. Never materializes a tactical window,
    /// never assigns a real date, never creates a Session — see `load`'s
    /// own scratch-context discipline.
    private(set) var upcomingPreviewMix: TrainingMix?
    private(set) var upcomingComponentPreviews: [UpcomingComponentPreview] = []
    /// The next phase in `TrainingPlan.orderedPhases`, if any — read-only
    /// lookup, never materialized or started merely by being shown.
    private(set) var nextPhase: TrainingPhase?
    /// `nil` unless the phase is `.active` and its primary component has
    /// a real materialized `ProgramInstance` — never fabricated for a
    /// phase that hasn't started or has already ended.
    private(set) var currentWeekIndex: Int?
    private(set) var totalWindowWeeks: Int?
    /// The real, already-persisted `PlannerDecision.explanation` for why
    /// this phase's mix was chosen — `nil` when no such decision exists,
    /// never a fabricated fallback string.
    private(set) var phaseExplanation: String?
    /// Keyed by `TrainingMixComponent.id` — the real, already-persisted
    /// `PlannerDecision.explanation` for why that component's specific
    /// program was selected, if one exists.
    private(set) var componentExplanations: [UUID: String] = [:]
    /// Stage 10R.2B, corrected by Stage 10R.7A
    /// (`STAGE10R7_STRATEGIC_PHASE_LIFECYCLE_DESIGN.md`, D-10R7-3): `true`
    /// only when this phase's primary component is an already-materialized
    /// Hypertrophy instance that is tactically EXHAUSTED and whose
    /// configuration has a real next mesocycle
    /// (`HypertrophyProgramJourney.orderedPhaseTypes`). **Never gated on
    /// whether a next STRATEGIC phase already exists in the plan** — a
    /// Hypertrophy mesocycle succession happens INSIDE this same strategic
    /// phase (`StartNextHypertrophyMesocycleUseCase` never creates a new
    /// `TrainingPhase`), so a pre-planned future phase must never suppress
    /// it. The idempotency signal instead comes from `primaryInstance`
    /// itself: once the succession succeeds, `phase.primaryInstance`
    /// (Stage 10R.7A: reads the mix component's current pointer) becomes
    /// the freshly-materialized next mesocycle, which is not yet
    /// exhausted — hiding the action automatically, the same self-hiding
    /// discipline `canAdvanceTacticalWeek` already uses.
    private(set) var canStartNextHypertrophyMesocycle = false
    /// The next mesocycle's display name, for the action's own label —
    /// `nil` whenever `canStartNextHypertrophyMesocycle` is `false`.
    private(set) var nextHypertrophyMesocycleTypeLabel: String?
    /// Stage 10R.4B: `true` only when `TacticalWeekCompletion
    /// .canAdvanceTacticalWeek(for:)` says every component this phase's
    /// active mix would actually roll is itself ready — a purely derived
    /// read, recomputed on every `load`, never a stored flag. This is
    /// display/gating state only; `advanceTacticalWeek` below
    /// independently re-derives the same thing at the moment it's
    /// actually invoked (`AdvanceTacticalWeekUseCase`'s own contract),
    /// so a stale read of this property can never cause a duplicate roll.
    private(set) var canAdvanceTacticalWeek = false
    /// 1-indexed display label for the button ("Start Week 2") — derived
    /// from the primary instance's own current materialized week, `nil`
    /// whenever `canAdvanceTacticalWeek` is `false`.
    private(set) var nextTacticalWeekNumber: Int?
    /// Stage 10R.7B (D-10R7B-2): `true` only when this ACTIVE phase is
    /// genuinely STRATEGIC-lifecycle terminal
    /// (`TrainingPhaseCompletion.isPhaseTerminal`) and has a real,
    /// still-`.planned` next strategic phase — the gate for showing the
    /// "Start Next Phase" action here (secondary to `PlanView`, D-10R7B-4).
    private(set) var canPresentStrategicTransition = false
    /// Stage 10R.7B (D-10R7B-10): `true` when this ACTIVE phase is
    /// strategic-lifecycle terminal but is the last phase in its plan's
    /// pre-planned sequence — a distinct, non-actionable, neutral state.
    /// Never implies `TrainingPlan`/`Goal` completion is persisted
    /// anywhere; nothing here mutates either.
    private(set) var isFinalStrategicPhaseComplete = false

    func load(phase: TrainingPhase, modelContext: ModelContext) {
        self.phase = phase
        recommendedMix = phase.recommendedTrainingMix
        selectedMix = phase.selectedTrainingMix
        activeComponents = (selectedMix ?? recommendedMix)?.orderedComponents ?? []

        if let plan = phase.plan,
           let index = plan.orderedPhases.firstIndex(where: { $0.id == phase.id }),
           plan.orderedPhases.indices.contains(index + 1) {
            nextPhase = plan.orderedPhases[index + 1]
        } else {
            nextPhase = nil
        }

        if phase.status == .active, let primaryInstance = phase.primaryInstance {
            currentWeekIndex = ProgramWeekGrouping.nextWeekIndex(for: primaryInstance)
            let primarySystem = activeComponents.first { $0.priority == .primary }?.programmingSystem
            let policyWindowDays = TacticalWindowPolicy.windowLengthInDays(
                primarySystem: primarySystem, asOf: phase.startDate, phaseEndDate: phase.endDate
            )
            // Mirrors the same widening `StartPhaseUseCase` applies before
            // scheduling — a non-primary component (Steady State, say)
            // can materialize further out than the primary system's own
            // natural block; this display must never claim a shorter
            // window than what was actually scheduled.
            let materializedDates = activeComponents.compactMap(\.programInstance).flatMap(\.sessions).compactMap { $0.day?.date }
            let effectiveWindowDays = TacticalWindowPolicy.effectiveWindowDays(
                policyWindowDays: policyWindowDays, materializedDates: materializedDates, windowStartDate: phase.startDate
            )
            totalWindowWeeks = max(1, effectiveWindowDays / 7)
        } else {
            currentWeekIndex = nil
            totalWindowWeeks = nil
        }

        let decisions = (try? modelContext.fetch(FetchDescriptor<PlannerDecision>())) ?? []
        phaseExplanation = decisions.first { $0.phase?.id == phase.id && $0.programInstance == nil }?.explanation

        var explanations: [UUID: String] = [:]
        for component in activeComponents {
            guard let instanceID = component.programInstance?.id else { continue }
            if let decision = decisions.first(where: { $0.programInstance?.id == instanceID }) {
                explanations[component.id] = decision.explanation
            }
        }
        componentExplanations = explanations

        // Strategic-intent preview for a phase that hasn't started and
        // has no stored mix yet — never touches `modelContext`, the
        // phase, or any other real persisted state; every object this
        // produces lives only in a throwaway in-memory container that is
        // discarded the moment `load` returns.
        if phase.status != .active, phase.status != .completed, recommendedMix == nil, selectedMix == nil, let goal = phase.plan?.goal {
            let scratchContext = ModelContext(PersistenceController.makeInMemoryContainer())
            let candidates = LongTermPlanner.proposeTrainingMix(phase: phase, goal: goal)
            let previewMix = (candidates.first { $0.roles.contains(.recommended) } ?? candidates.first)?.mix
            upcomingPreviewMix = previewMix
            upcomingComponentPreviews = (previewMix?.orderedComponents ?? []).map { component in
                UpcomingComponentPreview(
                    component: component,
                    previewProgramDefinition: LongTermPlanner.previewProgramCandidate(component: component, goal: goal, context: scratchContext)?.programDefinition
                )
            }
        } else {
            upcomingPreviewMix = nil
            upcomingComponentPreviews = []
        }

        // Stage 10R.4A fix: previously gated only on `!sessions.isEmpty`
        // ("has materialized at all"), which let a user reach "Start
        // [next mesocycle]" the moment Week 1 alone existed — Weeks 2
        // through deload never having been reached. Now requires the
        // outgoing instance to be TACTICALLY EXHAUSTED (its final
        // source-defined week is terminal) — a purely derived read, never
        // a persisted status (Locked Decision 4).
        //
        // Stage 10R.7A fix: previously ALSO required `nextPhase == nil`
        // (no next STRATEGIC phase already existed in the plan) — wrong,
        // since a Hypertrophy mesocycle succession happens inside this
        // SAME strategic phase and must never be suppressed merely
        // because a later, unrelated strategic phase already exists in
        // `TrainingPlan.orderedPhases`. See this property's own doc
        // comment for the corrected idempotency signal.
        canStartNextHypertrophyMesocycle = false
        nextHypertrophyMesocycleTypeLabel = nil
        if phase.status == .active,
           let primaryInstance = phase.primaryInstance,
           TacticalWeekCompletion.isInstanceExhausted(for: primaryInstance),
           activeComponents.first(where: { $0.priority == .primary })?.programmingSystem == .hypertrophy,
           let configuration = primaryInstance.programDefinition?.hypertrophyConfiguration,
           let currentIndex = HypertrophyProgramJourney.orderedPhaseTypes.firstIndex(of: configuration.phaseType),
           HypertrophyProgramJourney.orderedPhaseTypes.indices.contains(currentIndex + 1) {
            canStartNextHypertrophyMesocycle = true
            nextHypertrophyMesocycleTypeLabel = Self.phaseTypeDisplayName(HypertrophyProgramJourney.orderedPhaseTypes[currentIndex + 1])
        }

        // Stage 10R.4B: the tactical week-advancement gate — see this
        // property's own doc comment. Uses whichever mix `activeComponents`
        // itself is already sourced from (selected, falling back to
        // recommended), so this never disagrees with what's actually
        // displayed above.
        canAdvanceTacticalWeek = false
        nextTacticalWeekNumber = nil
        if phase.status == .active, let mix = selectedMix ?? recommendedMix,
           TacticalWeekCompletion.canAdvanceTacticalWeek(for: mix) {
            canAdvanceTacticalWeek = true
            if let primaryInstance = phase.primaryInstance,
               let currentWeekIndex = TacticalWeekCompletion.currentMaterializedWeekIndex(for: primaryInstance) {
                nextTacticalWeekNumber = currentWeekIndex + 2 // 1-indexed display, one past the current (also 1-indexed) week
            }
        }

        // Stage 10R.7B (D-10R7B-2/D-10R7B-10): the STRATEGIC transition
        // gate — a wholly separate question from `canStartNextHypertrophyMesocycle`
        // above (that's program-level succession INSIDE this same phase;
        // this is the phase itself ending). Never derived from dates,
        // never merely "current ProgramInstance exhausted."
        canPresentStrategicTransition = false
        isFinalStrategicPhaseComplete = false
        if phase.status == .active, TrainingPhaseCompletion.isPhaseTerminal(phase) {
            if TrainingPhaseCompletion.isFinalStrategicPhase(phase) {
                isFinalStrategicPhaseComplete = true
            } else if TrainingPhaseCompletion.nextStrategicPhase(for: phase)?.status == .planned {
                canPresentStrategicTransition = true
            }
        }
    }

    private static func phaseTypeDisplayName(_ phaseType: HypertrophyPhaseType) -> String {
        switch phaseType {
        case .basicHypertrophy: return "Basic Hypertrophy"
        case .metaboliteFocus: return "Metabolite Focus"
        case .resensitization: return "Resensitization"
        }
    }

    /// Stage 10R.2B: the one deliberate write this ViewModel performs —
    /// see this type's own top-level doc comment. Never called by `load`;
    /// only ever in direct response to an explicit user action (a button
    /// tap), matching `STAGE3_DECISION_MEMO.md` Decision A1's
    /// `transitionTrigger: .userInitiated`.
    @discardableResult
    func startNextHypertrophyMesocycle(modelContext: ModelContext) -> Bool {
        guard let phase, let primaryInstance = phase.primaryInstance else { return false }
        let candidates = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        do {
            try StartNextHypertrophyMesocycleUseCase.start(
                previousPhase: phase, previousInstance: primaryInstance, asOf: Date(),
                ownerUserID: primaryInstance.ownerUserID,
                availability: UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1),
                materializationContext: TacticalMaterializationContext(
                    // KNOWN DOMAIN GAP — see the identical note in
                    // `advanceTacticalWeek` below.
                    equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
                    strengthCandidateExercises: candidates,
                    functionalFitnessCandidateExercises: candidates
                ),
                context: modelContext
            )
            try? modelContext.save()
            return true
        } catch {
            return false
        }
    }

    /// Stage 10R.4B: the second deliberate write this ViewModel
    /// performs — same discipline as `startNextHypertrophyPhase` above
    /// (never called by `load`, only in direct response to an explicit
    /// user tap). Delegates entirely to `AdvanceTacticalWeekUseCase`,
    /// which re-derives eligibility from persisted state itself — this
    /// method's own `canAdvanceTacticalWeek` read is only ever used to
    /// decide whether to SHOW the button, never trusted as proof it's
    /// still safe to actually roll.
    @discardableResult
    func advanceTacticalWeek(modelContext: ModelContext) -> Bool {
        guard let phase, let primaryInstance = phase.primaryInstance else { return false }
        let candidates = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        do {
            let outcome = try AdvanceTacticalWeekUseCase.advance(
                phase: phase, asOf: Date(), ownerUserID: primaryInstance.ownerUserID,
                performanceProfile: nil,
                availability: UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1),
                materializationContext: TacticalMaterializationContext(
                    // KNOWN DOMAIN GAP (Stage 10R.6, D-10R6-11 — deferred by
                    // explicit product decision): TrainingOS has no
                    // persisted training-environment/equipment-inventory
                    // model yet, only a coarse per-equipment-key increment
                    // preference (`UserProfile.equipmentIncrements`). This
                    // placeholder is NOT an authoritative equipment profile
                    // — it is left exactly as it was before Stage 10R.6,
                    // deliberately not replaced with a more convincing but
                    // still-fabricated substitute. See
                    // `STAGE10R6_MIXED_MODALITY_ROLLFORWARD_IMPLEMENTATION_REPORT.md`.
                    equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
                    strengthCandidateExercises: candidates,
                    functionalFitnessCandidateExercises: candidates
                ),
                context: modelContext
            )
            return outcome == .advanced
        } catch {
            return false
        }
    }
}
