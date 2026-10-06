import Foundation

/// CONDITIONING DOSE AUTHORITY V1: the real, locked TrainingOS product
/// prescriptions for each conditioning stimulus's concrete duration/
/// work-rest — resolving the STOP conditions a prior trace-only
/// checkpoint reported ("CONDITIONING V2 — CONCRETE DURATION AUTHORITY
/// REQUIRED" / "... INTERVAL WORK/REST AUTHORITY REQUIRED"). These are
/// deliberate product prescriptions inside evidence-supported stimulus
/// domains — never presented as a research-derived physiological optimum
/// (the project lead's own explicit instruction).
///
/// Every sequence is a pure function of `relativeWeek` — the same stable,
/// already-existing exposure index `FunctionalFitnessPhaseBiasPolicy`
/// already uses for its own squat/hinge pattern alternation
/// (`requiredLoadedPatternOverrides`'s `relativeWeek % 2`). No hidden
/// mutable counter is introduced (explicitly forbidden). Same
/// athlete/program/week/exposure always yields the same output.
enum ConditioningDoseAuthority {
    /// SHORT_HIGH_OUTPUT: 4 → 6 → 8 → 4 minutes, the exact locked cycle.
    private static let shortHighOutputMinutes = [4, 6, 8]
    static func shortHighOutputCapSeconds(relativeWeek: Int) -> Int {
        shortHighOutputMinutes[relativeWeek % shortHighOutputMinutes.count] * 60
    }

    /// MEDIUM_MIXED_MODAL: 10 → 12 → 15 → 10 minutes.
    private static let mediumMixedModalMinutes = [10, 12, 15]
    static func mediumMixedModalCapSeconds(relativeWeek: Int) -> Int {
        mediumMixedModalMinutes[relativeWeek % mediumMixedModalMinutes.count] * 60
    }

    /// SUSTAINED_AEROBIC: 24 → 30 → 40 → 24 minutes.
    private static let sustainedAerobicMinutes = [24, 30, 40]
    static func sustainedAerobicCapSeconds(relativeWeek: Int) -> Int {
        sustainedAerobicMinutes[relativeWeek % sustainedAerobicMinutes.count] * 60
    }

    /// AEROBIC_INTERVALS: fixed 3:00 work / 2:00 recovery; interval count
    /// cycles through {3,4,5}. The order's own two constraints — "default
    /// first exposure = 4" and "sequence: 3,4,5" — are jointly satisfied by
    /// indexing `[3,4,5]` with `relativeWeek % 3` directly: the first real
    /// production exposure of this stimulus in this checkpoint's own
    /// wiring (`relativeWeek == 1`, an odd week — see
    /// `FunctionalFitnessPhaseBiasPolicy.applyConditioningFamily`'s
    /// `.aerobicEngine` case) lands on index 1 → 4. A deterministic
    /// ordering choice within already-locked values, not a new physiology
    /// decision.
    static let aerobicIntervalsWorkSeconds = 180
    static let aerobicIntervalsRestSeconds = 120
    private static let aerobicIntervalsCounts = [3, 4, 5]
    static func aerobicIntervalsCount(relativeWeek: Int) -> Int {
        aerobicIntervalsCounts[relativeWeek % aerobicIntervalsCounts.count]
    }

    /// REPEATED_HIGH_OUTPUT_INTERVALS: fixed 6 x 30s work / 90s recovery —
    /// no cycling; the order specifies one fixed V1 prescription, not a
    /// sequence.
    static let repeatedHighOutputIntervalsCount = 6
    static let repeatedHighOutputIntervalsWorkSeconds = 30
    static let repeatedHighOutputIntervalsRestSeconds = 90
}
