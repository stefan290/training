import Foundation

/// Pure, deterministic interval progression — the sibling of
/// `StrengthProgressionEngine`/`SteadyStateProgressionEngine`. Same
/// discipline: no randomness, no network calls, no reading the current
/// date/time, same inputs always produce the same output and reason
/// code.
///
/// **One `IntervalProgrammingSystem`, not one engine per modality**
/// (Stage 4D §1). Nothing here branches on `ActivityType` — a Running,
/// Cycling, Rowing or SkiErg 4×4 template all resolve through the exact
/// same functions below.
///
/// **Week-to-week resolution takes the previous week's actual
/// `IntervalSessionOutcome` as an explicit parameter** (§15/§17/§33) —
/// when `rules.requiresSuccessfulCompletionToProgress` is `false` (the
/// common case for a fixed protocol like Helgerud's 4×4, which the
/// source study never varies), callers pass `previousOutcome: nil` and
/// every week resolves as a pure function of week index alone, exactly
/// like `SteadyStateProgressionEngine`. When `true`, a caller must not
/// resolve week N+1 until week N's actual outcome exists — this engine
/// does not fabricate one.
enum IntervalProgressionEngine {
    // MARK: - Priority consumption

    /// How many weeks `variable` has actually been the *active* priority
    /// dimension by `weekIndex`, per `IntervalProgressionStep`'s own doc
    /// comment: an earlier step in `priority` fully consumes its
    /// `weeksToCeiling` worth of elapsed weeks before a later step starts
    /// advancing at all. `weekIndex == 0` (week one) always yields zero
    /// active weeks for every variable — week one is the baseline, never
    /// itself progressed.
    ///
    /// Deliberately returns a plain week **count**, not a pre-multiplied
    /// increment amount — each resolver below applies its own per-week
    /// scale (`step.incrementPerWeek` for count/duration/distance/
    /// recovery; `intensityZoneProgression.stepPerWeek` for intensity,
    /// since that struct is reused unchanged from `SteadyStateProgressionRules`
    /// and already owns its own step size — see `resolveIntensity`'s own
    /// doc comment for why a `.intensity` priority entry's own
    /// `incrementPerWeek` is deliberately ignored rather than doubling up
    /// with a second, competing step-size source).
    static func weeksActive(for variable: IntervalProgressionVariable, priority: [IntervalProgressionStep], weekIndex: Int) -> Int {
        guard weekIndex > 0 else { return 0 }
        var remainingWeeks = weekIndex
        for step in priority {
            let weeksAvailableToThisStep = min(remainingWeeks, step.weeksToCeiling)
            if step.variable == variable {
                return weeksAvailableToThisStep
            }
            remainingWeeks -= weeksAvailableToThisStep
            if remainingWeeks <= 0 { return 0 }
        }
        return 0
    }

    private static func isPrioritized(_ variable: IntervalProgressionVariable, in priority: [IntervalProgressionStep]) -> Bool {
        priority.contains { $0.variable == variable }
    }

    /// Whether a dimension's *resolved value* actually differs from what
    /// it would have resolved to the previous week — used for reason
    /// codes instead of "has `weeksActive` grown at all," so a dimension
    /// that maxed out its priority ceiling (or its own further clamp,
    /// e.g. `intensityZoneProgression.maxZone`) several weeks ago
    /// correctly reports "no change this week," not "still increasing."
    private static func changed<T: Equatable>(current: T, previous: T) -> Bool {
        current != previous
    }

    // MARK: - Interval count

    static func resolveIntervalCount(
        rules: IntervalProgressionRules,
        weekIndex: Int,
        previousActualCount: Int?,
        previousOutcome: IntervalSessionOutcome?
    ) -> (count: Int, reasonCode: IntervalReasonCode) {
        if let previousOutcome, weekIndex > 0 {
            switch previousOutcome {
            case .reduceIntervalCount:
                let reduced = max((previousActualCount ?? rules.weekOneIntervalCount) - 1, 1)
                return (reduced, .reduceIntervalCount)
            case .hold, .repeatSession, .calibrationRequired, .reduceIntensity:
                if let previousActualCount {
                    return (previousActualCount, reasonCodeForNonProgress(previousOutcome))
                }
            case .progress:
                break
            }
        }
        guard let step = rules.priority.first(where: { $0.variable == .intervalCount }) else {
            return (rules.weekOneIntervalCount, .noProgressionConfigured)
        }
        let weeks = weeksActive(for: .intervalCount, priority: rules.priority, weekIndex: weekIndex)
        let previousWeeks = weeksActive(for: .intervalCount, priority: rules.priority, weekIndex: weekIndex - 1)
        let count = rules.weekOneIntervalCount + Int(Double(weeks) * step.incrementPerWeek)
        let previousCount = rules.weekOneIntervalCount + Int(Double(previousWeeks) * step.incrementPerWeek)
        return (count, changed(current: count, previous: previousCount) ? .intervalCountIncrease : .noProgressionConfigured)
    }

    // MARK: - Work duration

    static func resolveWorkDuration(
        rules: IntervalProgressionRules,
        weekIndex: Int,
        previousActualDurationSeconds: Int?,
        previousOutcome: IntervalSessionOutcome?
    ) -> (durationSeconds: Int?, reasonCode: IntervalReasonCode) {
        guard let weekOne = rules.weekOneWorkDurationSeconds else {
            return (nil, .noProgressionConfigured)
        }
        if let previousOutcome, weekIndex > 0, previousOutcome != .progress {
            if let previousActualDurationSeconds, previousOutcome != .reduceIntervalCount {
                return (previousActualDurationSeconds, reasonCodeForNonProgress(previousOutcome))
            }
            if previousOutcome == .reduceIntervalCount {
                return (previousActualDurationSeconds ?? weekOne, .hold)
            }
        }
        guard let step = rules.priority.first(where: { $0.variable == .workDuration }) else {
            return (weekOne, .noProgressionConfigured)
        }
        let weeks = weeksActive(for: .workDuration, priority: rules.priority, weekIndex: weekIndex)
        let previousWeeks = weeksActive(for: .workDuration, priority: rules.priority, weekIndex: weekIndex - 1)
        let duration = weekOne + Int(Double(weeks) * step.incrementPerWeek)
        let previousDuration = weekOne + Int(Double(previousWeeks) * step.incrementPerWeek)
        return (duration, changed(current: duration, previous: previousDuration) ? .workDurationIncrease : .noProgressionConfigured)
    }

    // MARK: - Work distance

    static func resolveWorkDistance(
        rules: IntervalProgressionRules,
        weekIndex: Int,
        previousActualDistanceMeters: Double?,
        previousOutcome: IntervalSessionOutcome?
    ) -> (distanceMeters: Double?, reasonCode: IntervalReasonCode) {
        guard let weekOne = rules.weekOneWorkDistanceMeters else {
            return (nil, .noProgressionConfigured)
        }
        if let previousOutcome, weekIndex > 0, previousOutcome != .progress {
            if let previousActualDistanceMeters, previousOutcome != .reduceIntervalCount {
                return (previousActualDistanceMeters, reasonCodeForNonProgress(previousOutcome))
            }
            if previousOutcome == .reduceIntervalCount {
                return (previousActualDistanceMeters ?? weekOne, .hold)
            }
        }
        guard let step = rules.priority.first(where: { $0.variable == .workDistance }) else {
            return (weekOne, .noProgressionConfigured)
        }
        let weeks = weeksActive(for: .workDistance, priority: rules.priority, weekIndex: weekIndex)
        let previousWeeks = weeksActive(for: .workDistance, priority: rules.priority, weekIndex: weekIndex - 1)
        let distance = weekOne + Double(weeks) * step.incrementPerWeek
        let previousDistance = weekOne + Double(previousWeeks) * step.incrementPerWeek
        return (distance, changed(current: distance, previous: previousDistance) ? .workDistanceIncrease : .noProgressionConfigured)
    }

    // MARK: - Intensity (heart-rate-zone stepping, same shape as SteadyState)

    /// **`priority`'s `.intensity` entry contributes only its
    /// `weeksToCeiling`** (when intensity starts/stops being the active
    /// dimension relative to the others) — its `incrementPerWeek` is
    /// deliberately ignored. The actual per-week zone step size comes
    /// from `rules.intensityZoneProgression.stepPerWeek` instead, since
    /// that struct (reused unchanged from `SteadyStateProgressionRules`)
    /// already fully owns its own step size; letting a second field also
    /// claim to set it would be two competing sources of truth for the
    /// same number.
    static func resolveIntensity(
        rules: IntervalProgressionRules,
        weekIndex: Int,
        previousActualZone: HeartRateZone?,
        previousOutcome: IntervalSessionOutcome?
    ) -> (intensity: IntensityTarget?, reasonCode: IntervalReasonCode) {
        guard let progression = rules.intensityZoneProgression else {
            return (nil, .noProgressionConfigured)
        }
        if let previousOutcome, weekIndex > 0 {
            switch previousOutcome {
            case .reduceIntensity:
                let currentRaw = (previousActualZone ?? progression.startZone).rawValue
                let reducedRaw = max(currentRaw - 1, HeartRateZone.one.rawValue)
                return (.heartRateZone(HeartRateZone(rawValue: reducedRaw) ?? .one), .reduceIntensity)
            case .hold, .repeatSession, .calibrationRequired, .reduceIntervalCount:
                if let previousActualZone {
                    return (.heartRateZone(previousActualZone), reasonCodeForNonProgress(previousOutcome))
                }
            case .progress:
                break
            }
        }
        guard isPrioritized(.intensity, in: rules.priority) else {
            return (.heartRateZone(progression.startZone), .noProgressionConfigured)
        }
        let weeks = weeksActive(for: .intensity, priority: rules.priority, weekIndex: weekIndex)
        let previousWeeks = weeksActive(for: .intensity, priority: rules.priority, weekIndex: weekIndex - 1)
        let zoneRaw = min(progression.startZone.rawValue + weeks * progression.stepPerWeek, progression.maxZone.rawValue)
        let previousZoneRaw = min(progression.startZone.rawValue + previousWeeks * progression.stepPerWeek, progression.maxZone.rawValue)
        let zone = HeartRateZone(rawValue: zoneRaw) ?? progression.maxZone
        return (.heartRateZone(zone), changed(current: zoneRaw, previous: previousZoneRaw) ? .intensityIncrease : .noProgressionConfigured)
    }

    // MARK: - Recovery duration

    static func resolveRecoveryDuration(
        rules: IntervalProgressionRules,
        weekIndex: Int,
        previousActualRecoverySeconds: Int?,
        previousOutcome: IntervalSessionOutcome?
    ) -> (recoveryDurationSeconds: Int?, reasonCode: IntervalReasonCode) {
        guard let weekOne = rules.weekOneRecoveryDurationSeconds else {
            return (nil, .noProgressionConfigured)
        }
        if let previousOutcome, weekIndex > 0, previousOutcome != .progress {
            if let previousActualRecoverySeconds {
                return (previousActualRecoverySeconds, reasonCodeForNonProgress(previousOutcome))
            }
        }
        guard let step = rules.priority.first(where: { $0.variable == .recoveryDuration }) else {
            return (weekOne, .noProgressionConfigured)
        }
        let weeks = weeksActive(for: .recoveryDuration, priority: rules.priority, weekIndex: weekIndex)
        let previousWeeks = weeksActive(for: .recoveryDuration, priority: rules.priority, weekIndex: weekIndex - 1)
        let reduced = max(weekOne - Int(Double(weeks) * step.incrementPerWeek), rules.recoveryDurationFloorSeconds)
        let previousReduced = max(weekOne - Int(Double(previousWeeks) * step.incrementPerWeek), rules.recoveryDurationFloorSeconds)
        return (reduced, changed(current: reduced, previous: previousReduced) ? .recoveryReduced : .noProgressionConfigured)
    }

    // MARK: - Session outcome evaluation (§16-17)

    /// `totalCount == 0` (no reps attempted/logged at all) always yields
    /// `.calibrationRequired` — never inventing a completion fraction
    /// from no data.
    static func evaluateSessionOutcome(
        criteria: IntervalCompletionCriteria,
        completedCount: Int,
        totalCount: Int,
        worstRpe: Int?
    ) -> IntervalSessionOutcome {
        guard totalCount > 0 else { return .calibrationRequired }
        let completionFraction = Double(completedCount) / Double(totalCount)
        let rpeExceeded = criteria.maxRpeAllowed.map { (worstRpe ?? 0) > $0 } ?? false

        if completionFraction >= criteria.minimumCompletionFractionForProgress && !rpeExceeded {
            return .progress
        }
        if completionFraction >= criteria.minimumCompletionFractionForHold {
            return .hold
        }
        if completionFraction >= criteria.minimumCompletionFractionForRepeat {
            return .repeatSession
        }
        return criteria.reductionStrategy == .reduceIntensity ? .reduceIntensity : .reduceIntervalCount
    }

    private static func reasonCodeForNonProgress(_ outcome: IntervalSessionOutcome) -> IntervalReasonCode {
        switch outcome {
        case .hold: return .hold
        case .repeatSession: return .repeatSession
        case .reduceIntensity: return .reduceIntensity
        case .reduceIntervalCount: return .reduceIntervalCount
        case .calibrationRequired: return .calibrationRequired
        case .progress: return .noProgressionConfigured
        }
    }
}
