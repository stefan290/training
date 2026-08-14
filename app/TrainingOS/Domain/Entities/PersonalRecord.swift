import Foundation
import SwiftData

/// A durable PR snapshot. The value, band, direction and context are
/// copied at creation time so the record stands on its own even if its
/// source SetResult/WorkoutResult is later edited — only the source links
/// are traceability, never a dependency for correctness.
@Model
final class PersonalRecord {
    @Attribute(.unique) var id: UUID
    var exercisePerformanceProfile: ExercisePerformanceProfile?

    var value: Double
    /// e.g. "1RM", "5RM", "8-12", or nil for a time/rounds-based record.
    var repBand: String?
    var scoringDirection: ScoringDirection
    var context: ResultContext
    var achievedAt: Date

    var sourceSetResult: SetResult?
    var sourceWorkoutResult: WorkoutResult?

    init(
        id: UUID = UUID(),
        value: Double,
        repBand: String? = nil,
        scoringDirection: ScoringDirection,
        context: ResultContext = .rx,
        achievedAt: Date = Date()
    ) {
        self.id = id
        self.value = value
        self.repBand = repBand
        self.scoringDirection = scoringDirection
        self.context = context
        self.achievedAt = achievedAt
    }
}
