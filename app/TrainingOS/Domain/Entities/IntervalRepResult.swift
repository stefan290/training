import Foundation
import SwiftData

/// One completed interval repetition inside an `IntervalResult` — never
/// collapsed into a session-average-only value, per Stage 3B §11's
/// explicit requirement that "the engine should be able to inspect
/// individual intervals later." `intervalResult` has no declared inverse
/// of its own; the inverse lives on `IntervalResult.repResults`.
@Model
final class IntervalRepResult {
    @Attribute(.unique) var id: UUID
    var intervalResult: IntervalResult?
    /// Stable position among the session's reps, assigned by
    /// `IntervalResult.addRepResult(_:)`.
    var sortIndex: Int

    var actualWorkDurationSeconds: Int?
    var actualWorkDistanceMeters: Double?
    var averagePaceSecondsPerKilometer: Double?
    var averagePower: Int?
    var averageHeartRate: Int?
    var wasCompletedAsPrescribed: Bool
    var actualRecoveryDurationSeconds: Int?

    init(
        id: UUID = UUID(),
        actualWorkDurationSeconds: Int? = nil,
        actualWorkDistanceMeters: Double? = nil,
        averagePaceSecondsPerKilometer: Double? = nil,
        averagePower: Int? = nil,
        averageHeartRate: Int? = nil,
        wasCompletedAsPrescribed: Bool = true,
        actualRecoveryDurationSeconds: Int? = nil
    ) {
        self.id = id
        self.sortIndex = 0
        self.actualWorkDurationSeconds = actualWorkDurationSeconds
        self.actualWorkDistanceMeters = actualWorkDistanceMeters
        self.averagePaceSecondsPerKilometer = averagePaceSecondsPerKilometer
        self.averagePower = averagePower
        self.averageHeartRate = averageHeartRate
        self.wasCompletedAsPrescribed = wasCompletedAsPrescribed
        self.actualRecoveryDurationSeconds = actualRecoveryDurationSeconds
    }
}
