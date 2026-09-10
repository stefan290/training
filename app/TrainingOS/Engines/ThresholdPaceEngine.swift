import Foundation

/// Pure, deterministic threshold-relative pace math — the Running
/// foundation's sibling of `StrengthProgressionEngine`/
/// `SteadyStateProgressionEngine`/`IntervalProgressionEngine`. No
/// SwiftData import, no `ModelContext`, no athlete-specific threshold
/// hardcoded anywhere — every athlete's threshold pace is always a plain
/// caller-supplied input, never a constant.
///
/// **Source-established formula** (`RUNNING_PROGRAMMING_MODEL_R1.md` §6,
/// confirmed cell-level in `PercentThresholdPaceCalculator.xlsx` `F13`/
/// `G13`, independently cross-confirmed in prose by
/// `RP_5K_TrainingPeaks_Reference.xlsx` `Source & Inputs` row 7):
/// `adjusted_pace_seconds = threshold_pace_seconds / percent_of_threshold`.
///
/// **No artificial floor/ceiling on `percentOfThreshold`.** R1's
/// corrected finding (independent review, accepted): the ≤89% rule is an
/// ATHLETE EXECUTION OVERRIDE LIMIT (see `RunningExecutionOverrideEngine`),
/// never a restriction on what may be *prescribed*. The observed source
/// program legitimately prescribes ~60% through ~110% of threshold; this
/// engine performs the identical division for any positive fraction,
/// deliberately with no `guard` narrowing that range.
enum ThresholdPaceEngine {
    /// `adjusted_pace_seconds = threshold_pace_seconds / percent_of_threshold`,
    /// returned as a full-precision `Pace` (never pre-rounded) — display
    /// rounding is a separate, explicitly isolated concern (see
    /// `displayMinutesAndSeconds(for:)` below).
    static func targetPace(thresholdPaceSecondsPerKilometer: Double, percentOfThreshold: Double) -> Pace {
        Pace(secondsPerKilometer: thresholdPaceSecondsPerKilometer / percentOfThreshold)
    }

    /// Convenience overload operating on the domain's own `Pace` value
    /// type directly.
    static func targetPace(threshold: Pace, percentOfThreshold: Double) -> Pace {
        targetPace(thresholdPaceSecondsPerKilometer: threshold.secondsPerKilometer, percentOfThreshold: percentOfThreshold)
    }

    /// The inverse operation — given an absolute pace and the athlete's
    /// threshold, what percent of threshold does it represent. Used to
    /// classify an observed/requested pace against the intensity bands in
    /// `RunningAdaptationEngine`/`RunningExecutionOverrideEngine` without
    /// duplicating the division elsewhere.
    static func percentOfThreshold(pace: Pace, thresholdPaceSecondsPerKilometer: Double) -> Double {
        thresholdPaceSecondsPerKilometer / pace.secondsPerKilometer
    }

    /// **Isolated display-rounding boundary.** `PercentThresholdPaceCalculator.xlsx`
    /// establishes ONLY the minutes component's rounding (`F13`:
    /// `ROUNDDOWN(total/60, 0)` — floor to whole minutes) and the
    /// remainder-seconds component as whatever is left over (`G13`). The
    /// calculator does not establish how the leftover seconds themselves
    /// should round if a caller needed a whole-second display (R1 §20,
    /// "SAFE-TO-DEFER" — the calculator's own edge rounding is explicitly
    /// unresolved). This function reproduces ONLY the source-established
    /// part (floor-minutes + exact remainder) and never introduces a
    /// third rounding rule of its own — a caller wanting different
    /// display rounding changes this one function, never the programming
    /// semantics in `targetPace(_:_:)` above, which stays exact
    /// (`Double`) throughout.
    static func displayMinutesAndSeconds(for pace: Pace) -> (minutes: Int, seconds: Double) {
        let totalSeconds = pace.secondsPerKilometer
        let minutes = Int((totalSeconds / 60).rounded(.down))
        let seconds = totalSeconds - Double(minutes * 60)
        return (minutes, seconds)
    }
}
