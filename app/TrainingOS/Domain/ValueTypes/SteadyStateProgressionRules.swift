import Foundation

/// Which single dimension a `SteadyStatePrescriptionTemplate` progresses
/// week over week — Stage 4C §7's explicit requirement: "do not assume
/// duration always progresses." Exactly one dimension per template,
/// mirroring how Family A/B/C each choose one `LoadRule`/`SetCountRule`
/// rather than layering several progression mechanisms onto one slot.
/// `.none` is a first-class, common case — most Zone 2 aerobic-base
/// prescriptions in the real source material are genuinely static week to
/// week; "static" must never be represented as a degenerate/empty
/// progression rule.
enum SteadyStateProgressionDimension: String, Codable, CaseIterable {
    case duration
    case distance
    case intensityZone
    case none
}

/// Deterministic, TrainingOS-designed heart-rate-zone stepping — the only
/// `IntensityTarget` case this pass progresses week over week. Deliberately
/// narrow: stepping a numbered zone up by a fixed amount each week, capped
/// at a configured maximum, is expressible as three plain scalars with no
/// enum-with-payload persistence risk at all (unlike storing a per-week
/// `[IntensityTarget]` array directly, which has no existing SwiftData
/// round-trip precedent in this codebase — see
/// `SteadyStatePrescriptionTemplate`'s own doc comment for why that shape
/// was deliberately avoided rather than assumed safe). Every other
/// `IntensityTarget` case (pace, power, cadence, stroke rate, RPE, percent
/// of reference) holds a single static target for the whole block when
/// `progressionDimension != .intensityZone` — not because those dimensions
/// can never progress in principle, but because no source material this
/// pass reviewed specifies a numeric protocol for progressing them, and
/// CLAUDE.md rule 10 rules out inventing one.
struct IntensityZoneProgression: Codable, Equatable {
    var startZone: HeartRateZone
    var stepPerWeek: Int
    var maxZone: HeartRateZone

    /// The zone for a given (0-indexed) week, clamped at `maxZone` and
    /// never stepping below `startZone` even for a caller-supplied
    /// negative `weekIndex`.
    func zone(forWeekIndex weekIndex: Int) -> HeartRateZone {
        let steppedRaw = startZone.rawValue + stepPerWeek * max(weekIndex, 0)
        let clampedRaw = min(max(steppedRaw, startZone.rawValue), maxZone.rawValue)
        return HeartRateZone(rawValue: clampedRaw) ?? maxZone
    }
}

/// The engine-facing bundle `SteadyStateProgressionEngine` operates on —
/// the steady-state sibling of `StrengthProgressionRules`. Never stored
/// directly on `SteadyStatePrescriptionTemplate` (which flattens every
/// field individually, exactly like `PrescriptionTemplate` already does
/// for `StrengthProgressionRules` — see that type's own Bug 2/3 history);
/// this is purely the ergonomic, non-persisted shape callers/tests use.
struct SteadyStateProgressionRules: Codable, Equatable {
    var progressionDimension: SteadyStateProgressionDimension
    /// Absolute duration per week (not a multiplier) — `laterWeekDurationSeconds[0]`
    /// is week 2's duration, `[1]` is week 3's, and so on; index-aligned
    /// the same way `RMBasedLoad.laterWeekMultipliers` is, but additive
    /// rather than multiplicative, since real aerobic-duration progression
    /// (e.g. "+5 min/week") is naturally additive, not a percentage of a
    /// baseline. TRAININGOS_DESIGNED unless a specific built-in's
    /// provenance says otherwise.
    var weekOneDurationSeconds: Int?
    var laterWeekDurationSeconds: [Int]
    var weekOneDistanceMeters: Double?
    var laterWeekDistanceMeters: [Double]
    var intensityZoneProgression: IntensityZoneProgression?
    /// 1.0 = no reduction (the default — matches "do not invent a
    /// universal aerobic deload methodology" until a config explicitly
    /// sets otherwise).
    var recoveryWeekDurationFraction: Double
    var recoveryWeekDistanceFraction: Double
    /// Zones to step *down* on a recovery week — 0 by default (no
    /// reduction).
    var recoveryWeekIntensityZoneStepDown: Int

    init(
        progressionDimension: SteadyStateProgressionDimension,
        weekOneDurationSeconds: Int? = nil,
        laterWeekDurationSeconds: [Int] = [],
        weekOneDistanceMeters: Double? = nil,
        laterWeekDistanceMeters: [Double] = [],
        intensityZoneProgression: IntensityZoneProgression? = nil,
        recoveryWeekDurationFraction: Double = 1.0,
        recoveryWeekDistanceFraction: Double = 1.0,
        recoveryWeekIntensityZoneStepDown: Int = 0
    ) {
        self.progressionDimension = progressionDimension
        self.weekOneDurationSeconds = weekOneDurationSeconds
        self.laterWeekDurationSeconds = laterWeekDurationSeconds
        self.weekOneDistanceMeters = weekOneDistanceMeters
        self.laterWeekDistanceMeters = laterWeekDistanceMeters
        self.intensityZoneProgression = intensityZoneProgression
        self.recoveryWeekDurationFraction = recoveryWeekDurationFraction
        self.recoveryWeekDistanceFraction = recoveryWeekDistanceFraction
        self.recoveryWeekIntensityZoneStepDown = recoveryWeekIntensityZoneStepDown
    }
}

/// Steady-state's `StrengthReasonCode` sibling — every steady-state
/// resolution is explainable via one of these, never a bare number with
/// no accompanying reason.
enum SteadyStateReasonCode: String, Codable, CaseIterable {
    case durationProgressed
    case distanceProgressed
    case intensityZoneProgressed
    case staticIntensity
    case recoveryWeekReduction
    case noProgressionConfigured
}
