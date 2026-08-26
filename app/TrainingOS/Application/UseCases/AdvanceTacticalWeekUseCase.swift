import Foundation
import SwiftData

/// Stage 10R.4B: the ONLY production-safe entry point to
/// `RollTacticalWindowUseCase.rollForward`
/// (`STAGE10R4_TACTICAL_ROLLFORWARD_DESIGN.md` §6/§17 — "CRITICAL — SAFE
/// ROLLFORWARD WRAPPER"). `rollForward` itself has no idempotency guard
/// (proven by the Stage 10R.4 audit: calling it twice in a row silently
/// advances Week N -> N+1 -> N+2 with no intervening real week trained).
/// This use case re-derives eligibility from persisted state at
/// invocation time, every time — it never trusts a stale ViewModel
/// boolean, and a repeated immediate call is a safe no-op because the
/// newly-materialized week's Sessions are freshly `.scheduled` (not
/// terminal), so `TacticalWeekCompletion.canAdvanceTacticalWeek`
/// immediately re-evaluates to `false`.
///
/// Never starts a new mesocycle, never mutates `TrainingPhase`/
/// `ProgramInstance.status` (Locked Decision 4 — that remains
/// `StartNextHypertrophyPhaseUseCase`'s job, triggered separately, by
/// the user, once `TacticalWeekCompletion.isInstanceExhausted`), never
/// invokes `LongTermPlanner` or regenerates the strategic plan.
enum AdvanceTacticalWeekUseCase {
    enum Outcome: Equatable {
        /// The mix genuinely was not eligible at invocation time — no
        /// component was in a state where an advance was safe/possible.
        /// Not an error: this is the expected, safe result of a repeated
        /// or premature call.
        case notEligible
        /// `rollForward` ran and produced no new sessions for any
        /// component (e.g. every eligible component turned out already
        /// exhausted once actually checked against the definition's real
        /// week count) — distinct from `.notEligible` only in that the
        /// pre-check passed but `rollForward` itself still found nothing
        /// to roll; reported separately so a caller can tell the two
        /// apart if it ever matters, though both mean "nothing changed."
        case nothingRolled
        case advanced
    }

    /// Re-derives eligibility fresh from `context`, then — only if still
    /// eligible — invokes `RollTacticalWindowUseCase.rollForward` exactly
    /// once and saves. `phase` supplies the `TrainingMix` to advance
    /// (its `selectedTrainingMix`, falling back to `recommendedTrainingMix`
    /// — the same "selected wins once it exists" precedent
    /// `PhaseDetailViewModel.activeComponents` already uses).
    @discardableResult
    static func advance(
        phase: TrainingPhase,
        asOf: Date,
        ownerUserID: UUID,
        performanceProfile: PerformanceProfile?,
        availability: UserAvailability,
        userProfile: UserProfile? = nil,
        materializationContext: TacticalMaterializationContext,
        context: ModelContext
    ) throws -> Outcome {
        guard let mix = phase.selectedTrainingMix ?? phase.recommendedTrainingMix else { return .notEligible }

        // Step 1-5 of the conceptual sequence: re-read authoritative
        // persisted state and verify every affected component's current
        // week is terminal, a next source-defined week exists for it,
        // and none of them is exhausted — never trust anything computed
        // earlier (e.g. by a ViewModel's own `load()`), since state may
        // have changed since then.
        guard TacticalWeekCompletion.canAdvanceTacticalWeek(for: mix) else { return .notEligible }

        // Step 6: invoke rollForward exactly once.
        guard let result = try RollTacticalWindowUseCase.rollForward(
            mix: mix, asOf: asOf, ownerUserID: ownerUserID, performanceProfile: performanceProfile,
            availability: availability, userProfile: userProfile,
            materializationContext: materializationContext, context: context
        ) else {
            return .nothingRolled
        }
        guard !result.newSessionsByComponent.isEmpty else { return .nothingRolled }

        // Step 7: persist.
        try context.save()

        // Step 8 (reload UI state) is the caller's responsibility —
        // mirrors `StartNextHypertrophyPhaseUseCase`'s own precedent of
        // returning a plain result and leaving `load(...)` re-invocation
        // to the ViewModel/View layer.
        return .advanced
    }
}
