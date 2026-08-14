import Foundation

/// A pace, stored as seconds per kilometer so `Comparable`/range math is
/// plain arithmetic — display formatting (e.g. "4:30/km") is a UI concern,
/// not this value type's job.
struct Pace: Codable, Equatable, Comparable {
    var secondsPerKilometer: Double
    static func < (lhs: Pace, rhs: Pace) -> Bool { lhs.secondsPerKilometer < rhs.secondsPerKilometer }
}

/// Power in watts. A distinct type from a plain `Double` so an
/// `IntensityTarget` case can never be constructed by accidentally passing
/// a pace or a heart-rate value where a power was meant.
struct Power: Codable, Equatable, Comparable {
    var watts: Double
    static func < (lhs: Power, rhs: Power) -> Bool { lhs.watts < rhs.watts }
}

typealias PaceRange = ClosedRange<Pace>
typealias PowerRange = ClosedRange<Power>

/// Coarse, numbered training zones — deliberately just a number, per
/// British Cycling's own usage (`PROGRAMMING_SOURCES.md` §2): the same
/// zone number is reused for HR or power depending on what the athlete has
/// tested, so the zone itself carries no unit; `IntensityTarget` picks the
/// case (`.heartRateZone` vs. `.powerZone`) to say which.
enum HeartRateZone: Int, Codable, CaseIterable {
    case one = 1, two, three, four, five
}

enum PowerZone: Int, Codable, CaseIterable {
    case one = 1, two, three, four, five
}

/// What a `SteadyStatePrescription`/`IntervalPrescription` leg is actually
/// benchmarked against. Stage 3B found this to be an open, growing concept
/// (a real modality-comparison proof surfaced a missing case — rowing's
/// stroke rate — during validation itself); this is the typed, extensible
/// design chosen instead of an unstructured metrics dictionary.
///
/// **Design rationale (also documented in `ARCHITECTURE.md`):** every case
/// is a small, named value — never a raw `Double`/`String` — so a target
/// can't be misread across units (a power value can never silently be
/// compared against a pace). The set of cases is expected to keep growing
/// as new modalities are exercised (this is the *point* of the design, not
/// a flaw): adding a case here is additive and safe, because nothing in
/// the codebase exhaustively switches over `IntensityTarget` without a
/// `default` — see the grep-verified absence of such a switch, noted in
/// `STAGE3C_IMPLEMENTATION_REPORT.md`.
enum IntensityTarget: Codable, Equatable {
    case heartRateZone(HeartRateZone)
    /// A percentage of the athlete's own HRmax, e.g. Helgerud's own
    /// "90-95% HRmax" (`PROGRAMMING_SOURCES.md` §3) — kept distinct from
    /// `.heartRateZone` because the source study specifies a percentage
    /// directly, not a zone number, and translating it into "zone" would
    /// be an uncited interpretation.
    case heartRatePercent(ClosedRange<Double>)
    case pace(PaceRange)
    case powerZone(PowerZone)
    case powerRange(PowerRange)
    case rpe(ClosedRange<Int>)
    /// Cycling cadence, revolutions per minute.
    case cadence(ClosedRange<Int>)
    /// Rowing/SkiErg stroke rate, strokes per minute — the case the
    /// cross-modality proof in `ENDURANCE_PROGRAMMING_MODEL.md` §4 found
    /// missing from the Stage 3B draft.
    case strokeRate(ClosedRange<Int>)
    /// A percentage of a named reference metric (e.g. 88-93% of FTP) —
    /// the metric is a closed, typed set, never a free-text label.
    case percentOfReference(ClosedRange<Double>, metric: ReferenceMetric)
}

enum ReferenceMetric: String, Codable, CaseIterable {
    case ftp
    case thresholdHeartRate
    case thresholdPace
    case heartRateMax
}
