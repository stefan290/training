import Foundation
import SwiftData

/// A durable PR snapshot. The value, band, direction and context are
/// copied at creation time so the record stands on its own even if its
/// source SetResult/WorkoutResult is later edited — only the source links
/// are traceability, never a dependency for correctness.
///
/// `activityPerformanceProfile`/`benchmarkPerformanceProfile` are Stage 3C
/// additions, siblings of `exercisePerformanceProfile` — exactly one of
/// the three is set on any given record, mirroring how `SetResult` has
/// three independent parent relationships and only the relevant ones are
/// ever populated for a given result.
@Model
final class PersonalRecord {
    @Attribute(.unique) var id: UUID
    var exercisePerformanceProfile: ExercisePerformanceProfile?
    var activityPerformanceProfile: ActivityPerformanceProfile?
    var benchmarkPerformanceProfile: BenchmarkPerformanceProfile?

    var value: Double
    /// e.g. "1RM", "5RM", "8-12", or nil for a time/rounds-based record.
    var repBand: String?
    var scoringDirection: ScoringDirection
    var context: ResultContext
    var achievedAt: Date

    /// The delete rule lives on `SetResult.personalRecord` /
    /// `WorkoutResult.personalRecord` / `FunctionalFitnessResult.personalRecord` /
    /// `SteadyStateResult.personalRecord` / `IntervalResult.personalRecord`
    /// (see DELETE_RULE_MATRIX.md) — these are plain inverse properties.
    var sourceSetResult: SetResult?
    var sourceWorkoutResult: WorkoutResult?
    var sourceFunctionalFitnessResult: FunctionalFitnessResult?
    /// Stage 6B addition — the endurance siblings of the above, added
    /// alongside `RecordSteadyStateResultUseCase`/`RecordIntervalResultUseCase`.
    var sourceSteadyStateResult: SteadyStateResult?
    var sourceIntervalResult: IntervalResult?

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
