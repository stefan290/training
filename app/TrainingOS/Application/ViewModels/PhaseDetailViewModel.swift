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
    /// Stage 10R.2B: `true` only when this phase's primary component is
    /// an already-materialized Hypertrophy instance whose configuration
    /// has a real next mesocycle (`HypertrophyProgramJourney.orderedPhaseTypes`)
    /// AND no next phase already exists in the plan yet — the second half
    /// doubles as the idempotency signal: once `startNextHypertrophyPhase`
    /// succeeds, `nextPhase` becomes non-nil on the next `load`, hiding
    /// the action rather than offering to repeat it.
    private(set) var canStartNextHypertrophyPhase = false
    /// The next mesocycle's display name, for the action's own label —
    /// `nil` whenever `canStartNextHypertrophyPhase` is `false`.
    private(set) var nextHypertrophyPhaseTypeLabel: String?

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

        canStartNextHypertrophyPhase = false
        nextHypertrophyPhaseTypeLabel = nil
        if phase.status == .active, nextPhase == nil,
           let primaryInstance = phase.primaryInstance, !primaryInstance.sessions.isEmpty,
           activeComponents.first(where: { $0.priority == .primary })?.programmingSystem == .hypertrophy,
           let configuration = primaryInstance.programDefinition?.hypertrophyConfiguration,
           let currentIndex = HypertrophyProgramJourney.orderedPhaseTypes.firstIndex(of: configuration.phaseType),
           HypertrophyProgramJourney.orderedPhaseTypes.indices.contains(currentIndex + 1) {
            canStartNextHypertrophyPhase = true
            nextHypertrophyPhaseTypeLabel = Self.phaseTypeDisplayName(HypertrophyProgramJourney.orderedPhaseTypes[currentIndex + 1])
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
    func startNextHypertrophyPhase(modelContext: ModelContext) -> Bool {
        guard let phase, let primaryInstance = phase.primaryInstance else { return false }
        let candidates = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        do {
            try StartNextHypertrophyPhaseUseCase.start(
                previousPhase: phase, previousInstance: primaryInstance, asOf: Date(),
                ownerUserID: primaryInstance.ownerUserID,
                availability: UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1),
                materializationContext: TacticalMaterializationContext(
                    equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
                    strengthCandidateExercises: candidates
                ),
                context: modelContext
            )
            try? modelContext.save()
            return true
        } catch {
            return false
        }
    }
}
