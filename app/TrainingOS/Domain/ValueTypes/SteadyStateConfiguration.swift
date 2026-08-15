import Foundation

/// The full "recipe" `SteadyStateProgramGenerator` needs to produce a
/// template graph — the steady-state sibling of
/// `HypertrophyProgramConfiguration`/`PowerliftingProgramConfiguration`.
/// Deliberately just data: no rule logic lives here.
struct SteadyStateProgramConfiguration: Codable, Equatable {
    var activityType: ActivityType
    /// Substitution-eligible alternatives for every session this
    /// configuration generates (Stage 4C §35) — may equal `[activityType]`
    /// for a program that is deliberately activity-locked (e.g. a
    /// running-specific prescription that must reject Bike).
    var allowedActivityTypes: [ActivityType]
    var daysPerWeek: Int
    var lengthWeeks: Int
    var progressionDimension: SteadyStateProgressionDimension
}
