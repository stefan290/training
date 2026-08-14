import Foundation
import SwiftData

/// Permanent, program-independent history for one `BenchmarkDefinition` —
/// the Functional Fitness sibling of `ExercisePerformanceProfile`. Rx and
/// Scaled attempts are both retained here (via each `FunctionalFitnessResult`'s
/// own `resultContext`), never merged or made indistinguishable — Stage
/// 3C §22's explicit requirement.
@Model
final class BenchmarkPerformanceProfile {
    @Attribute(.unique) var id: UUID
    var performanceProfile: PerformanceProfile?
    var benchmark: BenchmarkDefinition?
    var lastPerformedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \FunctionalFitnessResult.benchmarkPerformanceProfile)
    var results: [FunctionalFitnessResult] = []

    @Relationship(deleteRule: .cascade, inverse: \PersonalRecord.benchmarkPerformanceProfile)
    var personalRecords: [PersonalRecord] = []

    init(id: UUID = UUID(), lastPerformedAt: Date? = nil) {
        self.id = id
        self.lastPerformedAt = lastPerformedAt
    }

    /// The only way application code should attach a FunctionalFitnessResult.
    /// Mutates exactly one side (this array); SwiftData maintains the
    /// declared inverse.
    func addResult(_ result: FunctionalFitnessResult) {
        results.append(result)
    }

    /// The only way application code should attach a PersonalRecord.
    /// Mutates exactly one side; SwiftData maintains the declared inverse.
    func addPersonalRecord(_ record: PersonalRecord) {
        personalRecords.append(record)
    }
}
