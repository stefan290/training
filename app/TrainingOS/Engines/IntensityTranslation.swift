import Foundation

/// Stage 4C §37: "do not assume intensity metrics transfer directly across
/// modalities." A physiological target (a heart-rate zone, a heart-rate
/// percent, an RPE) describes the *athlete's* effort and is meaningful
/// regardless of which activity produces it, so it survives an activity
/// substitution unchanged. An equipment/modality-specific target (a pace,
/// a power zone/range, a cadence, a stroke rate, a percent-of-reference
/// tied to a specific metric like FTP) does not — Bike watts and Row watts
/// are not the same number, and this codebase has no verified translation
/// rule between them (CLAUDE.md rule 10 rules out inventing one). Dropping
/// it to `nil` — "requires calibration for the new activity" — is the
/// honest behavior, not silently carrying the old modality's number
/// forward.
enum IntensityTranslation {
    static func translate(_ target: IntensityTarget?, from originalActivity: ActivityType, to newActivity: ActivityType) -> IntensityTarget? {
        guard let target else { return nil }
        guard originalActivity != newActivity else { return target }

        switch target {
        case .heartRateZone, .heartRatePercent, .rpe:
            return target
        case .pace, .powerZone, .powerRange, .cadence, .strokeRate, .percentOfReference:
            return nil
        }
    }
}
