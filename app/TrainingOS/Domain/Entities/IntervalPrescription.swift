import Foundation
import SwiftData

/// The typed prescription for an `.intervals` `WorkoutBlock` — a repeated
/// work/recovery structure, modality-independent by design. Validated
/// against Running/Bike/Row 4x4 side by side and 5x1km running in
/// `ENDURANCE_PROGRAMMING_MODEL.md` §3-4; also backs Beginner Running's
/// run/walk sessions (`ENDURANCE_PROGRAMMING_MODEL.md` §7), where
/// `recoveryIntensity` is simply "walking" rather than "active jog."
///
/// Work/recovery legs each support duration *and/or* distance (5x1km sets
/// `workDistanceMeters`, never `workDurationSeconds`; 4x4-minute intervals
/// set `workDurationSeconds`, never `workDistanceMeters`) — never both
/// required, never neither meaningful.
@Model
final class IntervalPrescription {
    @Attribute(.unique) var id: UUID
    var workoutBlock: WorkoutBlock?
    var activityType: ActivityType
    var intervalCount: Int
    var workDurationSeconds: Int?
    var workDistanceMeters: Double?
    var workIntensity: IntensityTarget?
    var recoveryDurationSeconds: Int?
    var recoveryDistanceMeters: Double?
    var recoveryIntensity: IntensityTarget?

    init(
        id: UUID = UUID(),
        activityType: ActivityType,
        intervalCount: Int,
        workDurationSeconds: Int? = nil,
        workDistanceMeters: Double? = nil,
        workIntensity: IntensityTarget? = nil,
        recoveryDurationSeconds: Int? = nil,
        recoveryDistanceMeters: Double? = nil,
        recoveryIntensity: IntensityTarget? = nil
    ) {
        self.id = id
        self.activityType = activityType
        self.intervalCount = intervalCount
        self.workDurationSeconds = workDurationSeconds
        self.workDistanceMeters = workDistanceMeters
        self.workIntensity = workIntensity
        self.recoveryDurationSeconds = recoveryDurationSeconds
        self.recoveryDistanceMeters = recoveryDistanceMeters
        self.recoveryIntensity = recoveryIntensity
    }
}
