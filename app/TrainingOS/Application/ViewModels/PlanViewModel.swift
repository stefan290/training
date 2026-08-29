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

    func load(modelContext: ModelContext) {
        let goals = (try? modelContext.fetch(FetchDescriptor<Goal>())) ?? []
        goal = goals.first { $0.status == .active }
        activePlan = goal?.plans.first { $0.status == .active }
        phases = activePlan?.orderedPhases ?? []
        phaseAwaitingStrategicTransition = phases.first { phase in
            phase.status == .active
                && TrainingPhaseCompletion.isPhaseTerminal(phase)
                && TrainingPhaseCompletion.nextStrategicPhase(for: phase)?.status == .planned
        }
    }
}
