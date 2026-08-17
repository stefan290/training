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
        case .percentOfReference(let range, let metric): return "\(Int(range.lower))-\(Int(range.upper))% \(metricLabel(metric))"
        }
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
