import Foundation
import SwiftData

/// The actual outcome of one set. Strictly separate from SetPrescription
/// (the target). `exercisePerformanceProfile` is the permanent home for
/// this record — it must remain populated even if the session, block or
/// program that produced it is later edited or deleted.
@Model
final class SetResult {
    @Attribute(.unique) var id: UUID
    var setPrescription: SetPrescription?
    var exercisePrescription: ExercisePrescription?
    var exercisePerformanceProfile: ExercisePerformanceProfile?

    /// Nullify, not cascade: a PersonalRecord must survive the deletion of
    /// the SetResult that produced it (see `PersonalRecord.sourceSetResult`
    /// and DELETE_RULE_MATRIX.md). `inverse:` is required even though
    /// nothing reads this property — an un-inversed to-one reference to
    /// this type produced a Core Data validation error on delete instead of
    /// a clean nullify (caught by
    /// `DeleteRuleMatrixTests.testDeletingWorkoutResultPreservesItsPersonalRecord`'s
    /// WorkoutResult counterpart).
    @Relationship(deleteRule: .nullify, inverse: \PersonalRecord.sourceSetResult)
    var personalRecord: PersonalRecord?

    var setIndex: Int
    var weight: Double
    var reps: Int
    var targetRir: Int?
    var actualRir: Int?
    var completedAt: Date
    var isPersonalRecord: Bool
    /// Rep-band identifier this set counts toward, e.g. "8-12". Nil for
    /// warmup or non-record-eligible sets.
    var prBand: String?

    init(
        id: UUID = UUID(),
        setIndex: Int,
        weight: Double,
        reps: Int,
        targetRir: Int? = nil,
        actualRir: Int? = nil,
        completedAt: Date = Date(),
        isPersonalRecord: Bool = false,
        prBand: String? = nil
    ) {
        self.id = id
        self.setIndex = setIndex
        self.weight = weight
        self.reps = reps
        self.targetRir = targetRir
        self.actualRir = actualRir
        self.completedAt = completedAt
        self.isPersonalRecord = isPersonalRecord
        self.prBand = prBand
    }
}
