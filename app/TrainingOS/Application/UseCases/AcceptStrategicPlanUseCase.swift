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
        decisionSource: DecisionSource = .systemRecommended,
        /// V1 R0 (mid-week start / no-double production bug fix): whether
        /// this acceptance should apply the "a brand-new plan's first
        /// tactical week begins on a genuine calendar-week boundary" rule
        /// (`LongTermPlanner.resolvedInitialPlanStartDate`). Defaults to
        /// `true` for every REAL athlete acceptance path. `SeedAnnualPlanJourney`
        /// is the one disclosed, deliberate exception: it simulates an
        /// athlete already MONTHS into an existing plan for internal
        /// dev/demo purposes, with every phase's date deliberately
        /// computed relative to its own `planAcceptedAt` — never a real
        /// athlete's actual first-run acceptance moment — so it explicitly
        /// passes `false` here. This is a narrow, disclosed opt-out, never
        /// a second start-date concept.
        alignFirstPhaseToFullCalendarWeek: Bool = true
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

        // V1 R0 (mid-week start / no-double production bug fix): a
        // BRAND-NEW plan's first tactical/source-backed week may only
        // ever be a genuine full calendar week (`LongTermPlanner
        // .resolvedInitialPlanStartDate`'s own doc comment has the full
        // architectural reasoning). `supersedes == nil` is this method's
        // own already-existing, exact signal for "this is a first-ever
        // plan, not a revision" — a revision/transition's own proposal
        // (`supersedes` set) is deliberately never shifted, matching the
        // locked "start-of-plan rule only" scope. Every phase in the
        // proposal shifts by the SAME fixed time interval, so the whole
        // already-reconciled sequence's contiguity/duration is preserved
        // exactly — this never re-derives or repeats any dated-objective/
        // reconciliation math, only moves where on the calendar the
        // already-correct sequence lands.
        let startDateShift: TimeInterval
        if alignFirstPhaseToFullCalendarWeek, supersedes == nil, let firstPhaseStart = proposal.phases.first?.startDate {
            let resolvedStart = LongTermPlanner.resolvedInitialPlanStartDate(asOf: firstPhaseStart)
            startDateShift = resolvedStart.timeIntervalSince(firstPhaseStart)
        } else {
            startDateShift = 0
        }

        for proposedPhase in proposal.phases {
            let phase = TrainingPhase(
                type: proposedPhase.type,
                startDate: proposedPhase.startDate.addingTimeInterval(startDateShift),
                endDate: proposedPhase.endDate.map { $0.addingTimeInterval(startDateShift) },
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
