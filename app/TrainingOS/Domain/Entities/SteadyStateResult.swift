import Foundation
import SwiftData

/// The typed result for a `.steadyState` block. Every field but
/// `actualDurationSeconds` is optional — a treadmill run might have no
/// distance sensor, a bike ride might have no power meter — never require
/// values a given activity/equipment combination can't supply.
///
/// `activityPerformanceProfile` is this result's permanent home, exactly
/// mirroring `SetResult.exercisePerformanceProfile` — see
/// `PERFORMANCE_PROFILE_MODALITY_REVIEW.md` §2. It has no declared inverse
/// collection of its own; the inverse lives on
/// `ActivityPerformanceProfile.steadyStateResults`.
@Model
final class SteadyStateResult {
    @Attribute(.unique) var id: UUID
    var workoutBlock: WorkoutBlock?
    var activityPerformanceProfile: ActivityPerformanceProfile?
    var resultContext: ResultContext
    var completedAt: Date

    var actualDurationSeconds: Int
    var actualDistanceMeters: Double?
    var averageHeartRate: Int?
    var averagePower: Int?
    var averagePaceSecondsPerKilometer: Double?
    var rpe: Int?

    init(
        id: UUID = UUID(),
        resultContext: ResultContext = .rx,
        completedAt: Date = Date(),
        actualDurationSeconds: Int,
        actualDistanceMeters: Double? = nil,
        averageHeartRate: Int? = nil,
        averagePower: Int? = nil,
        averagePaceSecondsPerKilometer: Double? = nil,
        rpe: Int? = nil
    ) {
        self.id = id
        self.resultContext = resultContext
        self.completedAt = completedAt
        self.actualDurationSeconds = actualDurationSeconds
        self.actualDistanceMeters = actualDistanceMeters
        self.averageHeartRate = averageHeartRate
        self.averagePower = averagePower
        self.averagePaceSecondsPerKilometer = averagePaceSecondsPerKilometer
        self.rpe = rpe
    }
}
