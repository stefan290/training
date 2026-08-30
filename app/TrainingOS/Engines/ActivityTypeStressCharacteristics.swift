import Foundation

/// Stage CP.1: coarse, categorical facts about an `ActivityType` that are
/// genuinely a function of WHICH activity this is, independent of its
/// duration/intensity that day — shared by `SteadyStateTrainingStressMapper`
/// and `IntervalTrainingStressMapper` so this one classification can never
/// drift between them (both already resolve a real, non-optional
/// `ActivityType` per prescription, so this is never a guess). Real,
/// uncontroversial physiological distinctions — running's repeated
/// ground-contact impact vs. cycling/rowing/skiErg's non-impact nature,
/// rowing/skiErg's genuine full-body (leg-drive + pull) demand vs.
/// running/cycling's leg-only demand — never invented precision.
///
/// `.other` is the one genuinely uncertain case (its own doc comment:
/// "an activity it hasn't anticipated") — every dimension conservatively
/// defaults to `.moderate` for it, never silently `.none` (CP.1's own
/// "never turn uncertainty into artificially low stress" rule).
enum ActivityTypeStressCharacteristics {
    static func impactLoading(for activityType: ActivityType) -> LoadLevel {
        switch activityType {
        case .running: return .moderate
        case .cycling, .rowing, .skiErg: return .none
        case .other: return .moderate
        }
    }

    static func lowerBodyLoad(for activityType: ActivityType) -> LoadLevel {
        switch activityType {
        case .running, .cycling: return .moderate
        case .rowing: return .moderate
        case .skiErg: return .low
        case .other: return .moderate
        }
    }

    static func upperBodyLoad(for activityType: ActivityType) -> LoadLevel {
        switch activityType {
        case .rowing, .skiErg: return .moderate
        case .running, .cycling: return .none
        case .other: return .moderate
        }
    }

    /// `nil` means "genuinely uncertain from this target" — deliberately
    /// only reads the domain's own already-modeled zone number
    /// (`HeartRateZone`/`PowerZone`, 1-5). Every other `IntensityTarget`
    /// case (pace, RPE, cadence, stroke rate, percent-of-reference/HRmax)
    /// is intentionally NOT converted into a zone here — CP.1's own rule
    /// against inventing HR-zone semantics the domain doesn't already
    /// model. Callers apply their own documented conservative fallback.
    static func intensityLevel(from target: IntensityTarget?) -> LoadLevel? {
        switch target {
        case .heartRateZone(let zone): return zoneLevel(zone.rawValue)
        case .powerZone(let zone): return zoneLevel(zone.rawValue)
        default: return nil
        }
    }

    private static func zoneLevel(_ zone: Int) -> LoadLevel {
        switch zone {
        case 1, 2: return .low
        case 3: return .moderate
        default: return .high
        }
    }
}
