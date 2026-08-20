import Foundation
import SwiftData
import Observation

/// Loads everything one `TrainingPhase` needs for its detail screen —
/// mirrors `PlanViewModel`'s exact shape (`@Observable`, plain
/// `load(...)`, broad fetch + Swift-side filtering). One ViewModel,
/// branching on `phase.status` at the View layer, never a parallel
/// phase-detail mechanism per system/status.
///
/// **Never writes anything.** Every property here is derived from
/// already-persisted state — `load` never creates, materializes, or
/// mutates a `Session`/`ProgramInstance`/`TrainingMix`.
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
    }
}
