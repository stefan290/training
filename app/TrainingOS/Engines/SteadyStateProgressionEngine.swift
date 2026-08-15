import Foundation

/// Pure, deterministic steady-state progression — the endurance sibling
/// of `StrengthProgressionEngine`. Same discipline: no randomness, no
/// network calls, no reading the current date/time, same inputs always
/// produce the same output and reason code.
///
/// **One `SteadyStateProgrammingSystem`, not one engine per modality**
/// (Stage 4C §1). Nothing here branches on `ActivityType` at all — a
/// Zone 2 Bike, Run, Row or SkiErg template all resolve through the exact
/// same three functions below. `ActivityType` only ever selects *which
/// units a caller displays/logs* (already established by `ActivityType`'s
/// own Stage 3C doc comment); it never changes how duration/distance/
/// intensity progress.
enum SteadyStateProgressionEngine {
    /// Recovery-week reduction applies independently of which dimension
    /// is the template's *chosen* `progressionDimension` — a recovery
    /// week eases up on whatever duration/distance/intensity values are
    /// actually present, not only the one axis that happens to progress
    /// week to week. Each dimension's own `recoveryWeek*` field governs
    /// its own reduction; there is no single blanket "recovery multiplier."
    static func resolveDuration(
        rules: SteadyStateProgressionRules,
        weekIndex: Int,
        isRecoveryWeek: Bool
    ) -> (durationSeconds: Int?, reasonCode: SteadyStateReasonCode) {
        guard let weekOne = rules.weekOneDurationSeconds else {
            return (nil, .noProgressionConfigured)
        }
        let base: Int
        let reasonCode: SteadyStateReasonCode
        if rules.progressionDimension == .duration, weekIndex > 0 {
            let laterIndex = weekIndex - 1
            base = laterIndex < rules.laterWeekDurationSeconds.count
                ? rules.laterWeekDurationSeconds[laterIndex]
                : (rules.laterWeekDurationSeconds.last ?? weekOne)
            reasonCode = .durationProgressed
        } else {
            base = weekOne
            reasonCode = .noProgressionConfigured
        }
        if isRecoveryWeek {
            let reduced = Int((Double(base) * rules.recoveryWeekDurationFraction).rounded())
            return (reduced, .recoveryWeekReduction)
        }
        return (base, reasonCode)
    }

    static func resolveDistance(
        rules: SteadyStateProgressionRules,
        weekIndex: Int,
        isRecoveryWeek: Bool
    ) -> (distanceMeters: Double?, reasonCode: SteadyStateReasonCode) {
        guard let weekOne = rules.weekOneDistanceMeters else {
            return (nil, .noProgressionConfigured)
        }
        let base: Double
        let reasonCode: SteadyStateReasonCode
        if rules.progressionDimension == .distance, weekIndex > 0 {
            let laterIndex = weekIndex - 1
            base = laterIndex < rules.laterWeekDistanceMeters.count
                ? rules.laterWeekDistanceMeters[laterIndex]
                : (rules.laterWeekDistanceMeters.last ?? weekOne)
            reasonCode = .distanceProgressed
        } else {
            base = weekOne
            reasonCode = .noProgressionConfigured
        }
        if isRecoveryWeek {
            return (base * rules.recoveryWeekDistanceFraction, .recoveryWeekReduction)
        }
        return (base, reasonCode)
    }

    /// `staticPrimaryIntensity` is only consulted when
    /// `progressionDimension != .intensityZone` — a prescription that
    /// progresses duration/distance instead is free to carry a fixed
    /// intensity target (of *any* `IntensityTarget` case, not only
    /// `.heartRateZone`) for the whole block; only an explicit
    /// `.heartRateZone` static target receives the recovery-week
    /// step-down, since stepping any other case down (a pace, a power
    /// range) would require a numeric rule no source material specifies.
    static func resolveIntensity(
        rules: SteadyStateProgressionRules,
        weekIndex: Int,
        isRecoveryWeek: Bool,
        staticPrimaryIntensity: IntensityTarget?
    ) -> (intensity: IntensityTarget?, reasonCode: SteadyStateReasonCode) {
        if rules.progressionDimension == .intensityZone, let progression = rules.intensityZoneProgression {
            let zone = progression.zone(forWeekIndex: weekIndex)
            if isRecoveryWeek {
                return (.heartRateZone(steppedDown(zone, by: rules.recoveryWeekIntensityZoneStepDown)), .recoveryWeekReduction)
            }
            return (.heartRateZone(zone), .intensityZoneProgressed)
        }

        guard let staticPrimaryIntensity else {
            return (nil, .staticIntensity)
        }
        if isRecoveryWeek, case .heartRateZone(let zone) = staticPrimaryIntensity, rules.recoveryWeekIntensityZoneStepDown > 0 {
            return (.heartRateZone(steppedDown(zone, by: rules.recoveryWeekIntensityZoneStepDown)), .recoveryWeekReduction)
        }
        return (staticPrimaryIntensity, .staticIntensity)
    }

    private static func steppedDown(_ zone: HeartRateZone, by amount: Int) -> HeartRateZone {
        let clampedRaw = max(zone.rawValue - amount, HeartRateZone.one.rawValue)
        return HeartRateZone(rawValue: clampedRaw) ?? zone
    }
}
