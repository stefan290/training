import Foundation

/// Stage 10R.5: `LoadFirstOverlayEngine`'s own provenance vocabulary —
/// deliberately a new, standalone enum, never an extension of
/// `StrengthReasonCode` (which is kept meaning "this is what the source
/// itself says" throughout Stages 10R.1-10R.4) and never a reuse of the
/// generic `ProgressionReasonCode` (a different, Hypertrophy-V2-era
/// vocabulary). Exactly the 8 cases locked in
/// `STAGE10R5_LOAD_FIRST_PROGRESSION_OVERLAY_DESIGN.md` D-10R5-17.
enum LoadOverlayReasonCode: String, Codable, Equatable {
    /// Overlay disabled, not eligible, or made no adjustment — the
    /// source's own next-scheduled value stands unchanged.
    case sourceBaseline
    /// One clearly-easy exposure (every valid set at/above target RIR,
    /// meaningful surplus overall) authorized one increment above the
    /// source's own next-scheduled value.
    case loadIncreaseEasyPerformance
    /// Recent exposure(s) matched the prescribed effort, or were
    /// inconsistent (some sets easy, one below target) — never treated
    /// as easy — or this is the first too-hard exposure (hold, not yet
    /// a regression).
    case holdMatchedTarget
    /// No qualifying real exposure exists yet — new exercise, post-
    /// substitution, all-skipped history, fresh mesocycle, etc.
    case holdInsufficientData
    /// Evidence supports an increase, but the smallest available
    /// equipment increment would be disproportionate this exposure —
    /// deferred, not cancelled; the evidence is not discarded.
    case holdIncrementTooLarge
    /// Two consecutive eligible too-hard exposures — regress by one
    /// equipment increment from the previous reference weight.
    case loadDecreaseRepeatedHardPerformance
    /// This week is a deload — the overlay does not apply at all.
    case deloadSourceAuthority
    /// The most/only relevant recent exposure was readiness-adapted
    /// (an accepted adaptation) and is excluded from consideration.
    case readinessExcluded
}
