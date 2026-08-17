import Foundation
import SwiftData

/// The typed result for an `.intervals` block. Holds per-interval detail
/// (`repResults`) plus session-level summary fields — both, not one or the
/// other, per Stage 3B §11.
///
/// `activityPerformanceProfile` is this result's permanent home, exactly
/// mirroring `SetResult.exercisePerformanceProfile`; it has no declared
/// inverse of its own, the inverse lives on
/// `ActivityPerformanceProfile.intervalResults`.
@Model
final class IntervalResult {
    @Attribute(.unique) var id: UUID
    var workoutBlock: WorkoutBlock?
    var activityPerformanceProfile: ActivityPerformanceProfile?
    var resultContext: ResultContext
    var completedAt: Date

    /// Stage 6B addition — same reasoning and mechanics as
    /// `SteadyStateResult.personalRecord`.
    @Relationship(deleteRule: .nullify, inverse: \PersonalRecord.sourceIntervalResult)
    var personalRecord: PersonalRecord?

    @Relationship(deleteRule: .cascade, inverse: \IntervalRepResult.intervalResult)
    var repResults: [IntervalRepResult] = []

    var sessionDurationSeconds: Int?
    var sessionDistanceMeters: Double?
    var averagePaceSecondsPerKilometer: Double?
    var averageHeartRate: Int?
    var rpe: Int?

    init(
        id: UUID = UUID(),
        resultContext: ResultContext = .rx,
        completedAt: Date = Date(),
        sessionDurationSeconds: Int? = nil,
        sessionDistanceMeters: Double? = nil,
        averagePaceSecondsPerKilometer: Double? = nil,
        averageHeartRate: Int? = nil,
        rpe: Int? = nil
    ) {
        self.id = id
        self.resultContext = resultContext
        self.completedAt = completedAt
        self.sessionDurationSeconds = sessionDurationSeconds
        self.sessionDistanceMeters = sessionDistanceMeters
        self.averagePaceSecondsPerKilometer = averagePaceSecondsPerKilometer
        self.averageHeartRate = averageHeartRate
        self.rpe = rpe
    }

    /// The only way application code should attach a per-interval result.
    /// Mutates exactly one side (this array); SwiftData maintains
    /// `repResult.intervalResult` from the declared inverse.
    func addRepResult(_ repResult: IntervalRepResult) {
        repResult.sortIndex = repResults.count
        repResults.append(repResult)
    }

    var orderedRepResults: [IntervalRepResult] {
        repResults.sorted { $0.sortIndex < $1.sortIndex }
    }
}
