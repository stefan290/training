import Foundation
import SwiftData

/// Everything the app permanently knows about one user's history with one
/// canonical Exercise: an estimated 1RM, confidence in that estimate, when
/// it was last performed, every SetResult ever logged against it (across
/// every program instance that ever touched it), and the PersonalRecords
/// derived from that history. This is the entity the Progression Engine
/// reads and the one invariant tests in this pass exercise directly.
@Model
final class ExercisePerformanceProfile {
    @Attribute(.unique) var id: UUID
    var performanceProfile: PerformanceProfile?
    var exercise: Exercise?

    var estimatedOneRepMax: Double?
    /// 0...1. Lowered by RECENCY_DECAY, never by deleting data.
    var confidence: Double
    var lastPerformedAt: Date?

    /// Cascade here is intentional and the *only* cascade in the app that
    /// touches performance data: deleting the whole PerformanceProfile
    /// (i.e. deleting the user's account) is the one legitimate case where
    /// this history should go away with it. No other entity in the graph
    /// may cascade-delete a SetResult.
    @Relationship(deleteRule: .cascade, inverse: \SetResult.exercisePerformanceProfile)
    var setResults: [SetResult] = []

    @Relationship(deleteRule: .cascade, inverse: \PersonalRecord.exercisePerformanceProfile)
    var personalRecords: [PersonalRecord] = []

    init(
        id: UUID = UUID(),
        estimatedOneRepMax: Double? = nil,
        confidence: Double = 0,
        lastPerformedAt: Date? = nil
    ) {
        self.id = id
        self.estimatedOneRepMax = estimatedOneRepMax
        self.confidence = confidence
        self.lastPerformedAt = lastPerformedAt
    }

    /// The only way application code should attach a SetResult to this
    /// permanent record. Mutates exactly one side (this array); SwiftData
    /// maintains `result.exercisePerformanceProfile` from the declared
    /// inverse. Ordering is chronological (`completedAt`), a real domain
    /// timestamp — not insertion order — so no sortIndex is needed here.
    func addSetResult(_ result: SetResult) {
        setResults.append(result)
    }

    /// The only way application code should attach a PersonalRecord to
    /// this permanent record. Mutates exactly one side; SwiftData
    /// maintains the inverse.
    func addPersonalRecord(_ record: PersonalRecord) {
        personalRecords.append(record)
    }

    var orderedSetResults: [SetResult] {
        setResults.sorted { $0.completedAt < $1.completedAt }
    }
}
