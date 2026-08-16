import Foundation
import SwiftData

/// Applies any of `ADHERENCE_AWARE_PLANNING.md` §2/§2a's three-option
/// choices — a temporary modality switch, a renewal, "continue" (promotes
/// a temporary desire into a stable preference), or "return to
/// recommended" — through exactly one mechanism: attach a new `.selected`
/// `TrainingMix` to the phase and close whichever mix was previously
/// active. Never touches `TrainingPlan`/`TrainingPhase`/`Goal`, never
/// deletes a prior mix (kept as inert historical record, mirroring
/// `PLAN_REVISION_MODEL.md` §4a's "abandoned, never deleted" discipline),
/// and never resets any `PerformanceProfile`/`SetResult`/`WorkoutResult`
/// (CLAUDE.md rule 1) — this only ever changes which mix is currently
/// active on the phase.
enum SwitchTrainingModalityUseCase {
    @discardableResult
    static func apply(
        _ mix: TrainingMix,
        to phase: TrainingPhase,
        asOf: Date,
        reasonCode: PlannerReasonCode,
        source: DecisionSource,
        explanation: String,
        context: ModelContext
    ) -> PlannerDecision {
        // Close out whichever mix was active immediately before this
        // switch — never mutates its `validFrom`/history, only stamps an
        // end to its active window if it did not already have one.
        if let previouslyActive = phase.activeTrainingMix(asOf: asOf), previouslyActive.id != mix.id, previouslyActive.validUntil == nil {
            previouslyActive.validUntil = asOf
        }

        if mix.phase == nil {
            phase.addTrainingMix(mix)
        }
        context.insert(mix)

        let decision = PlannerDecision(
            decidedAt: asOf,
            decisionType: .temporaryPreferenceApplied,
            source: source,
            reasonCode: reasonCode,
            factors: ["mixName": mix.name],
            explanation: explanation,
            phase: phase,
            trainingMix: mix
        )
        context.insert(decision)
        return decision
    }
}
