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

    func load(modelContext: ModelContext) {
        let goals = (try? modelContext.fetch(FetchDescriptor<Goal>())) ?? []
        goal = goals.first { $0.status == .active }
        activePlan = goal?.plans.first { $0.status == .active }
        phases = activePlan?.orderedPhases ?? []
    }
}
