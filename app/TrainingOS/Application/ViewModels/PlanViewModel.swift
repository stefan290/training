import Foundation
import SwiftData
import Observation

/// Loads the active Goal, its active Plan, and that Plan's ordered Phases —
/// enough to prove Goal -> Phase -> Program are distinct, navigable
/// concepts (handoff section 2) without a planning engine behind them yet.
@Observable
final class PlanViewModel {
    private(set) var goal: Goal?
    private(set) var activePlan: TrainingPlan?
    private(set) var phases: [TrainingPhase] = []
    /// Stage 10R.7B (D-10R7B-2): the active phase, if — and only if — it
    /// is genuinely STRATEGIC-lifecycle terminal
    /// (`TrainingPhaseCompletion.isPhaseTerminal`) AND has a real,
    /// still-`.planned` next strategic phase to transition into. Never
    /// derived from dates, never merely "the current ProgramInstance is
    /// exhausted," never hidden merely because historical ProgramInstances
    /// exist. `nil` whenever nothing needs the user's attention here —
    /// including when this phase is the plan's last one
    /// (`TrainingPhaseCompletion.isFinalStrategicPhase`), which is a
    /// distinct, non-actionable state `PhaseDetailView` surfaces instead.
    private(set) var phaseAwaitingStrategicTransition: TrainingPhase?

    /// V1 R3 (Plan/strategic spine reconciliation): the real, still-live
    /// dated objectives from the active `Goal` — sorted chronologically,
    /// `.completed`/`.cancelled` ones excluded (they no longer influence
    /// forward planning, the same real convention `LongTermPlanner`
    /// itself already applies when proposing phases). Never a second,
    /// independently-derived objective list.
    private(set) var datedObjectives: [DatedObjective] = []
    /// The one `.active` `TrainingPhase`, if any — real domain truth,
    /// never re-derived from dates.
    private(set) var currentPhase: TrainingPhase?
    /// V1 R0 truth, reused unchanged (the same signal
    /// `TodayViewModel.upcomingPlanStart` already uses): non-nil only
    /// when `currentPhase` exists but its own already-resolved
    /// `startDate` truthfully hasn't arrived yet — a brand-new plan's
    /// first tactical week begins on a genuine calendar-week boundary,
    /// never assumed to already be "Week 1" the moment it's accepted.
    private(set) var upcomingStartDate: Date?
    /// Real week position within the current phase's own materialized
    /// tactical window — calling the exact same, already-existing,
    /// unmodified `ProgramWeekGrouping`/`TacticalWindowPolicy` functions
    /// `PhaseDetailViewModel` itself calls, never a second/approximate
    /// computation. `nil` whenever `currentPhase` hasn't truthfully
    /// started yet (`upcomingStartDate != nil`) or has no materialized
    /// primary instance — never a fabricated "Week 1".
    private(set) var currentWeekPosition: (index: Int, total: Int)?
    /// `true` only when the LAST phase in the plan's own pre-planned
    /// sequence is the current phase — `TrainingPhaseCompletion
    /// .isFinalStrategicPhase`, unchanged. Communicates "no later planned
    /// phase exists yet," never "the Goal itself is complete."
    private(set) var isFinalPhase = false

    /// `referenceDate` defaults to the real current moment for every
    /// existing caller (mirrors `TodayViewModel.load`'s own identical
    /// parameter) — a deterministic override exists only so tests can
    /// prove the R0 upcoming-start truth without depending on the real
    /// wall-clock date the suite happens to run on.
    func load(modelContext: ModelContext, referenceDate: Date = Date()) {
        let goals = (try? modelContext.fetch(FetchDescriptor<Goal>())) ?? []
        goal = goals.first { $0.status == .active }
        activePlan = goal?.plans.first { $0.status == .active }
        phases = activePlan?.orderedPhases ?? []
        phaseAwaitingStrategicTransition = phases.first { phase in
            phase.status == .active
                && TrainingPhaseCompletion.isPhaseTerminal(phase)
                && TrainingPhaseCompletion.nextStrategicPhase(for: phase)?.status == .planned
        }

        datedObjectives = (goal?.datedObjectives ?? [])
            .filter { $0.status == .planned }
            .sorted { $0.date < $1.date }

        currentPhase = phases.first { $0.status == .active }
        if let currentPhase, currentPhase.startDate > referenceDate {
            upcomingStartDate = currentPhase.startDate
            currentWeekPosition = nil
        } else {
            upcomingStartDate = nil
            currentWeekPosition = currentPhase.flatMap(Self.weekPosition(for:))
        }
        // "Final phase" means the CURRENT phase has no real successor —
        // never "the last element of `phases`," which is tautologically
        // always final and would say nothing about the athlete's actual
        // position in the journey.
        isFinalPhase = currentPhase.map(TrainingPhaseCompletion.isFinalStrategicPhase) ?? false
    }

    /// Mirrors `PhaseDetailViewModel.load`'s own real tactical-window
    /// computation exactly (same functions, same call shape) — reused,
    /// never duplicated business logic. Only ever called for the
    /// genuinely-active, truthfully-started current phase.
    private static func weekPosition(for phase: TrainingPhase) -> (index: Int, total: Int)? {
        guard phase.status == .active, let primaryInstance = phase.primaryInstance else { return nil }
        let currentWeekIndex = ProgramWeekGrouping.nextWeekIndex(for: primaryInstance)
        let activeComponents = (phase.selectedTrainingMix ?? phase.recommendedTrainingMix)?.orderedComponents ?? []
        let primarySystem = activeComponents.first { $0.priority == .primary }?.programmingSystem
        let policyWindowDays = TacticalWindowPolicy.windowLengthInDays(
            primarySystem: primarySystem, asOf: phase.startDate, phaseEndDate: phase.endDate
        )
        let materializedDates = activeComponents.compactMap(\.programInstance).flatMap(\.sessions).compactMap { $0.day?.date }
        let effectiveWindowDays = TacticalWindowPolicy.effectiveWindowDays(
            policyWindowDays: policyWindowDays, materializedDates: materializedDates, windowStartDate: phase.startDate
        )
        let totalWindowWeeks = max(1, effectiveWindowDays / 7)
        return (min(currentWeekIndex, totalWindowWeeks - 1) + 1, totalWindowWeeks)
    }
}
