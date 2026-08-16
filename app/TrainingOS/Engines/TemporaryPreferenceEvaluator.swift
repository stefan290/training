import Foundation

/// `ADHERENCE_AWARE_PLANNING.md` §2/§2a — pure, deterministic detection of
/// the two distinct temporary-mix prompts. Like `GoalAlignmentEvaluator`,
/// this only decides *whether* a prompt should fire; it never applies any
/// of the three options itself (`SwitchTrainingModalityUseCase` does
/// that, only when explicitly called).
enum TemporaryPreferenceEvaluator {
    /// TRAININGOS_DESIGNED, configurable default (§2a) — not read by
    /// `isExpired`/`hasCrossedMaterialityThreshold` themselves (both take
    /// the mix's own stated `validUntil`/phase duration), but the figure
    /// a caller may offer when first proposing a review window.
    static let typicalReviewWindowWeeks = 4

    /// §2's plain expiry check: `validUntil` has passed as of `asOf`. A
    /// mix with `validUntil == nil` is a stable preference, never
    /// "expired."
    static func isExpired(_ mix: TrainingMix, asOf: Date) -> Bool {
        guard let validUntil = mix.validUntil else { return false }
        return validUntil <= asOf
    }

    /// §2a's materiality check — distinct from plain expiry, and it can
    /// fire even while a temporary block is still within its own
    /// `validUntil` window (e.g. after repeated renewals). True when
    /// either:
    /// - it has been renewed more than once consecutively without a
    ///   stable resolution, or
    /// - its cumulative temporary duration (from `validFrom` to `asOf`)
    ///   reaches half the enclosing phase's `PhaseDurationKind.range`
    ///   `typical` value.
    static func hasCrossedMaterialityThreshold(
        _ mix: TrainingMix, asOf: Date, consecutiveRenewals: Int, enclosingPhaseDuration: PhaseDurationKind
    ) -> Bool {
        guard mix.validFrom != nil || mix.validUntil != nil else {
            // Not a temporary mix at all (no bounded window ever set) —
            // the materiality question does not apply.
            return false
        }
        if consecutiveRenewals > 1 { return true }
        guard let validFrom = mix.validFrom, let typicalWeeks = enclosingPhaseDuration.planningWeeks else { return false }
        let elapsedWeeks = wholeWeeksBetween(validFrom, asOf)
        return elapsedWeeks >= typicalWeeks / 2
    }

    private static func wholeWeeksBetween(_ start: Date, _ end: Date) -> Int {
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        return max(0, days) / 7
    }
}
