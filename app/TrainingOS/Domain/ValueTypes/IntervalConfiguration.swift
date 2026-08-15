import Foundation

/// Whether a configuration's work interval is prescribed by time or by
/// distance (Stage 4D §3's explicit "do not assume all work intervals
/// are time-based"). Never both for the same configuration — mirrors
/// `IntervalPrescription`'s own doc comment ("never both required, never
/// neither meaningful").
enum IntervalWorkBasis: String, Codable, CaseIterable {
    case duration
    case distance
}

/// The full "recipe" `IntervalProgramGenerator` needs to produce a
/// template graph — the interval sibling of
/// `SteadyStateProgramConfiguration`. Deliberately just data: no rule
/// logic lives here.
struct IntervalProgramConfiguration: Codable, Equatable {
    var activityType: ActivityType
    /// Substitution-eligible alternatives (Stage 4D §24) — may equal
    /// `[activityType]` for an activity-locked configuration (e.g. a
    /// running-specific 5×1km pace prescription that must reject Bike).
    var allowedActivityTypes: [ActivityType]
    var daysPerWeek: Int
    var lengthWeeks: Int
    /// The training purpose this interval session serves — VO2, Threshold,
    /// Tempo, Speed, or general conditioning (Stage 4D §22). Reuses the
    /// existing `SessionRole` enum (already has `.threshold`/`.tempo`/
    /// `.interval`/`.aerobicBase`) rather than inventing a parallel
    /// "purpose" vocabulary — this is metadata on the generated
    /// `TemplateSession`, never a distinct engine.
    var sessionRole: SessionRole
    var workBasis: IntervalWorkBasis
    var includeWarmUp: Bool
    var includeCoolDown: Bool
}
