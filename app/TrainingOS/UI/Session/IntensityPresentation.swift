import Foundation

/// Pure display-string mapping for an `IntensityTarget`/`ActivityType` —
/// never a business decision, just what to print. Shared by Steady State
/// and Interval execution screens.
enum IntensityPresentation {
    static func label(_ target: IntensityTarget?) -> String? {
        guard let target else { return nil }
        switch target {
        case .heartRateZone(let zone): return "Zone \(zone.rawValue)"
        case .heartRatePercent(let range): return "\(Int(range.lower))-\(Int(range.upper))% HRmax"
        case .pace(let range): return "\(paceLabel(range.lower))-\(paceLabel(range.upper))/km"
        case .powerZone(let zone): return "Power Zone \(zone.rawValue)"
        case .powerRange(let range): return "\(Int(range.lower.watts))-\(Int(range.upper.watts))W"
        case .rpe(let range): return "RPE \(range.lower)-\(range.upper)"
        case .cadence(let range): return "\(range.lower)-\(range.upper) rpm"
        case .strokeRate(let range): return "\(range.lower)-\(range.upper) spm"
        // Running Athlete Journey Completion (Vertical Completion V1) bug
        // fix: `range.lower`/`range.upper` are stored as fractions
        // (`RunningProgramGenerator.intensityTarget(for:)` writes e.g.
        // `0.8` for 80%, confirmed directly against its own literal
        // source-derived fixture data), never whole-number percentages —
        // `Int(range.lower)` on a fraction like `0.8` truncates to `0`,
        // so every %threshold-prescribed Running block was displaying as
        // the literal string "0-0% Threshold Pace" before this fix. Scale
        // by 100 for display, exactly like every other percent-based case
        // above already expects a whole-number range.
        case .percentOfReference(let range, let metric): return "\(Int(range.lower * 100))-\(Int(range.upper * 100))% \(metricLabel(metric))"
        }
    }

    /// Running Athlete Journey Completion (Vertical Completion V1): the
    /// athlete-facing, ACTIONABLE resolution of a %threshold-prescribed
    /// target — never duplicates `ThresholdPaceEngine`'s own division
    /// here, only calls it. For every other `IntensityTarget` case, and
    /// for a `.percentOfReference` target whose metric isn't
    /// `.thresholdPace` (Running is the only current producer of this
    /// case), this is identical to `label(_:)` — no special handling
    /// needed. For a `.percentOfReference(_, .thresholdPace)` target:
    /// - with a real calibration, resolves both bounds through
    ///   `ThresholdPaceEngine.targetPace` and renders both the resolved
    ///   pace range AND the original percent text (source intensity and
    ///   athlete-facing resolved pace stay visibly distinct — never a
    ///   rewrite of the source prescription, just a second, derived
    ///   fact appended alongside it).
    /// - with no calibration yet (`thresholdPaceSecondsPerKilometer ==
    ///   nil`), falls back to `label(_:)`'s own (now-fixed) raw-percent
    ///   text — an honest, non-fabricated state. This should be
    ///   unreachable in practice once `RootTabView`'s Running calibration
    ///   gate is satisfied before Today is ever reachable, but this
    ///   function never assumes that invariant holds elsewhere (e.g. a
    ///   future caller rendering a different program instance) and always
    ///   degrades safely rather than guessing a pace.
    static func resolvedLabel(_ target: IntensityTarget?, thresholdPaceSecondsPerKilometer: Double?) -> String? {
        guard let target else { return nil }
        guard case .percentOfReference(let range, let metric) = target, metric == .thresholdPace,
              let threshold = thresholdPaceSecondsPerKilometer
        else {
            return label(target)
        }
        // A higher percent-of-threshold is a FASTER (smaller
        // seconds/km) pace — the percent bounds and the resulting pace
        // bounds are inversely ordered, so sort the two resolved paces
        // rather than assuming `range.lower` maps to the slower pace.
        let paces = [range.lower, range.upper]
            .map { ThresholdPaceEngine.targetPace(thresholdPaceSecondsPerKilometer: threshold, percentOfThreshold: $0) }
            .sorted { $0.secondsPerKilometer < $1.secondsPerKilometer }
        let percentText = "\(Int(range.lower * 100))-\(Int(range.upper * 100))% \(metricLabel(metric))"
        return "\(paceLabel(paces[0]))-\(paceLabel(paces[1]))/km · \(percentText)"
    }

    static func activityLabel(_ type: ActivityType) -> String {
        switch type {
        case .running: "Running"
        case .cycling: "Cycling"
        case .rowing: "Rowing"
        case .skiErg: "SkiErg"
        case .other: "Activity"
        }
    }

    private static func paceLabel(_ pace: Pace) -> String {
        let total = Int(pace.secondsPerKilometer.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Stage 6E: the identical mm:ss/km formatting above, exposed for an
    /// *actual* logged pace (a plain `Double`, not a prescribed `Pace`
    /// range) — completed history reuses this rather than a second
    /// formatter.
    static func paceLabel(secondsPerKilometer: Double) -> String {
        let total = Int(secondsPerKilometer.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private static func metricLabel(_ metric: ReferenceMetric) -> String {
        switch metric {
        case .ftp: "FTP"
        case .thresholdHeartRate: "Threshold HR"
        case .thresholdPace: "Threshold Pace"
        case .heartRateMax: "HRmax"
        }
    }
}
