import Foundation
import SwiftData

/// The Long-Term Planner's audit trail — mirrors `Recommendation`'s
/// existing precedent exactly one layer up: *"A Recommendation without a
/// reason code is a bug — there is deliberately no way to construct one
/// without it."* One `PlannerDecision` is persisted per strategically-
/// meaningful event (`PlannerDecisionType`'s own 6 cases are the
/// exhaustive list; nothing else produces one) — never a debug log of
/// every low-level scheduler comparison. `PLAN_REVISION_MODEL.md` §2.
@Model
final class PlannerDecision {
    @Attribute(.unique) var id: UUID
    var decidedAt: Date
    var decisionType: PlannerDecisionType
    var source: DecisionSource
    var reasonCode: PlannerReasonCode
    /// Small structured extras — mirrors `ScheduleIssue.metadata`'s exact
    /// shape and the exact same rule: never parsed back by any logic,
    /// display-generation input only.
    var factors: [String: String]
    /// What else was considered and why it wasn't chosen — empty when
    /// there was only ever one option (e.g. a temporary preference
    /// application).
    var alternativesConsidered: [ConsideredAlternative]
    /// Display copy only, generated FROM the structured fields above —
    /// CLAUDE.md rule 16's discipline extended to planning. Never
    /// business source of truth.
    var explanation: String

    // Optional back-references — as many as are relevant are set (e.g. a
    // `.roadmapRevised` decision sets `goal`+`planRevision` but no
    // `phase`), mirroring `WorkoutBlock`'s own established "multiple
    // optional typed children" pattern rather than an unsafe
    // enum-with-payload holding a `@Model` reference.
    var goal: Goal?
    var planRevision: TrainingPlan?
    var phase: TrainingPhase?
    var trainingMix: TrainingMix?
    var programInstance: ProgramInstance?

    init(
        id: UUID = UUID(),
        decidedAt: Date,
        decisionType: PlannerDecisionType,
        source: DecisionSource,
        reasonCode: PlannerReasonCode,
        factors: [String: String] = [:],
        alternativesConsidered: [ConsideredAlternative] = [],
        explanation: String,
        goal: Goal? = nil,
        planRevision: TrainingPlan? = nil,
        phase: TrainingPhase? = nil,
        trainingMix: TrainingMix? = nil,
        programInstance: ProgramInstance? = nil
    ) {
        self.id = id
        self.decidedAt = decidedAt
        self.decisionType = decisionType
        self.source = source
        self.reasonCode = reasonCode
        self.factors = factors
        self.alternativesConsidered = alternativesConsidered
        self.explanation = explanation
        self.goal = goal
        self.planRevision = planRevision
        self.phase = phase
        self.trainingMix = trainingMix
        self.programInstance = programInstance
    }
}
