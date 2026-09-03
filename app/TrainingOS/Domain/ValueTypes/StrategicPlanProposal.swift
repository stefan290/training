import Foundation

/// The narrow, mechanical meaning only (CLAUDE.md rule 18/19) — required
/// hard constraints (enough calendar time for even the minimum-duration
/// phases) could not be satisfied. Never a training-science/safety
/// judgment, and never conflated with `GoalAlignmentRating`/
/// `ScheduleFeasibility`'s own separate vocabularies.
enum StrategicPlanFeasibility: String, Codable, CaseIterable {
    case feasible
    case infeasible
    /// Dated Objectives + 10K Strategic Reconciliation V1's own locked
    /// "OVERLAP != CONFLICT" principle: an overlap between two dated
    /// objectives is reconciled (sequenced, gracefully compressed) using
    /// only real, already-supported `CandidateTrainingMix` output whenever
    /// possible — this case is reserved for the one narrower, genuinely
    /// unrepresentable situation the reconciliation algorithm can
    /// structurally prove: two dated objectives that share the exact same
    /// calendar date but require two different `PhaseType`s (a single
    /// `ProposedPhase` has exactly one type, and no blended type is ever
    /// fabricated). Distinct from `.infeasible` — this is a real,
    /// executable-calendar situation with a genuine goal/goal conflict,
    /// never a "not enough time at all" situation.
    case objectivesConflict
}

/// One phase in a proposed roadmap — not yet a persisted `TrainingPhase`.
/// `AcceptStrategicPlanUseCase` is what turns this into a real row.
struct ProposedPhase {
    var type: PhaseType
    var priorityRule: TrainingPriority
    var startDate: Date
    var endDate: Date?
    /// The duration *policy* this phase resolved from — `startDate`/
    /// `endDate` above are the actual, possibly horizon-clipped boundary;
    /// `durationKind` records which policy produced it
    /// (`STRATEGIC_PLAN_MODEL.md` §4a).
    var durationKind: PhaseDurationKind
    var reasonCodes: [PlannerReasonCode]

    init(
        type: PhaseType,
        priorityRule: TrainingPriority,
        startDate: Date,
        endDate: Date?,
        durationKind: PhaseDurationKind,
        reasonCodes: [PlannerReasonCode]
    ) {
        self.type = type
        self.priorityRule = priorityRule
        self.startDate = startDate
        self.endDate = endDate
        self.durationKind = durationKind
        self.reasonCodes = reasonCodes
    }
}

/// `LongTermPlanner.proposeStrategicPlan`'s return value — a plain,
/// non-persisted proposal (mirrors `ScheduleProposal`'s own transient
/// shape, `STRATEGIC_PLAN_MODEL.md` §2). Only `AcceptStrategicPlanUseCase`
/// turns this into real `TrainingPlan`/`TrainingPhase` rows.
struct StrategicPlanProposal {
    var goal: Goal
    var phases: [ProposedPhase]
    var feasibility: StrategicPlanFeasibility
    /// Display copy only, generated FROM `feasibility`/`phases` — never
    /// itself a source of truth (CLAUDE.md rule 16, extended to planning).
    var explanation: String

    init(goal: Goal, phases: [ProposedPhase], feasibility: StrategicPlanFeasibility, explanation: String) {
        self.goal = goal
        self.phases = phases
        self.feasibility = feasibility
        self.explanation = explanation
    }
}
