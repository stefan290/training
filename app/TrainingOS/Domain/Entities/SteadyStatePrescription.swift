import Foundation
import SwiftData

/// The typed prescription for a `.steadyState` `WorkoutBlock` — continuous
/// effort at a controlled intensity (Zone 2 bike, an easy/recovery/long
/// run). Validated in `ENDURANCE_PROGRAMMING_MODEL.md` §2, §5.
///
/// Only `durationSeconds` and/or `distanceMeters` need be set (a duration-
/// capped ride and a distance-capped time-trial are both legitimate); the
/// same applies to `primaryIntensity`/`secondaryIntensity` — a session with
/// no numeric target at all ("just go easy") is valid with both `nil`.
/// `workoutBlock` has no declared inverse of its own; the inverse lives on
/// `WorkoutBlock.steadyStatePrescription`, mirroring the existing
/// `ExercisePrescription.workoutBlock` pattern exactly.
@Model
final class SteadyStatePrescription {
    @Attribute(.unique) var id: UUID
    var workoutBlock: WorkoutBlock?
    var activityType: ActivityType
    var durationSeconds: Int?
    var distanceMeters: Double?
    /// The main prescribed constraint (e.g. an HR zone or a pace).
    var primaryIntensity: IntensityTarget?
    /// A secondary constraint alongside the primary (e.g. a cadence target
    /// alongside an HR-zone primary target) — deliberately one optional
    /// slot, not five separate HR/power/RPE/cadence fields, since
    /// `IntensityTarget` already discriminates the unit; see
    /// `ARCHITECTURE.md` for the full rationale.
    var secondaryIntensity: IntensityTarget?
    /// Stage 4C addition: THIS SESSION ONLY activity substitution's entire
    /// persisted footprint — mirrors `ExercisePrescription.substitutionUsed`/
    /// `.substitutionReason` exactly. Substituting for this occasion means
    /// directly editing `activityType` (and, if the new activity requires
    /// it, re-deriving `primaryIntensity`/`secondaryIntensity` via
    /// `IntensityTranslation`) on this already-materialized row — no new
    /// entity, same reasoning as the strength side.
    var substitutionUsed: Bool
    var substitutionReason: SubstitutionReason?

    init(
        id: UUID = UUID(),
        activityType: ActivityType,
        durationSeconds: Int? = nil,
        distanceMeters: Double? = nil,
        primaryIntensity: IntensityTarget? = nil,
        secondaryIntensity: IntensityTarget? = nil,
        substitutionUsed: Bool = false,
        substitutionReason: SubstitutionReason? = nil
    ) {
        self.id = id
        self.activityType = activityType
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.primaryIntensity = primaryIntensity
        self.secondaryIntensity = secondaryIntensity
        self.substitutionUsed = substitutionUsed
        self.substitutionReason = substitutionReason
    }
}
