import Foundation
import SwiftData

enum StrategicPlanAcceptanceError: Error, Equatable {
    /// An `.infeasible` `StrategicPlanProposal` must never be silently
    /// accepted — mirrors `ScheduleAcceptanceError.infeasible` exactly.
    case infeasible
    /// Dated Objectives + 10K Strategic Reconciliation V1: a genuine
    /// `.objectivesConflict` proposal must never be silently accepted
    /// either — the athlete must see the explicit trade-off and resolve it
    /// (e.g. by moving one of the conflicting dates) before anything is
    /// persisted.
    case objectivesConflict
}

/// The Engine-recommendation -> Explanation -> User-approval pattern's
/// final step for `LongTermPlanner.proposeStrategicPlan`/
/// `.reviseStrategicPlan`: turns an already-approved `StrategicPlanProposal`
/// into a real, persisted `TrainingPlan` + ordered `TrainingPhase` rows,
/// plus exactly one auditing `PlannerDecision` (`PLAN_REVISION_MODEL.md`
/// §2/§4). A proposal itself never mutates anything — only this use case
/// does, and only when explicitly called.
enum AcceptStrategicPlanUseCase {
    @discardableResult
    static func accept(
        _ proposal: StrategicPlanProposal,
        context: ModelContext,
        decidedAt: Date,
        supersedes: TrainingPlan? = nil,
        lineageID: UUID? = nil,
        decisionType: PlannerDecisionType = .phaseSelected,
        decisionReasonCode: PlannerReasonCode = .phaseSelectedForGoal,
        decisionSource: DecisionSource = .systemRecommended
    ) throws -> TrainingPlan {
        switch proposal.feasibility {
        case .feasible: break
        case .infeasible: throw StrategicPlanAcceptanceError.infeasible
        case .objectivesConflict: throw StrategicPlanAcceptanceError.objectivesConflict
        }

        // §4a: superseding a plan never mutates it — the prior revision's
        // own still-`.planned` future phases become `.abandoned` (inert
        // historical record), and the prior revision's own status becomes
        // `.superseded`. Completed/active-elapsed phases are untouched;
        // only `.planned` ones are eligible to move to `.abandoned` at all.
        if let supersedes {
            for phase in supersedes.orderedPhases where phase.status == .planned {
                phase.status = .abandoned
            }
            supersedes.status = .superseded
        }

        let plan = TrainingPlan(status: .active, createdAt: decidedAt, supersedes: supersedes, lineageID: lineageID)
        context.insert(plan)
        proposal.goal.addPlan(plan)

        for proposedPhase in proposal.phases {
            let phase = TrainingPhase(
                type: proposedPhase.type, startDate: proposedPhase.startDate, endDate: proposedPhase.endDate,
                priorityRule: proposedPhase.priorityRule, status: .planned
            )
            context.insert(phase)
            plan.addPhase(phase)
        }

        let decision = PlannerDecision(
            decidedAt: decidedAt,
            decisionType: decisionType,
            source: decisionSource,
            reasonCode: decisionReasonCode,
            factors: ["phaseCount": String(proposal.phases.count)],
            explanation: proposal.explanation,
            goal: proposal.goal,
            planRevision: plan
        )
        context.insert(decision)

        return plan
    }
}
