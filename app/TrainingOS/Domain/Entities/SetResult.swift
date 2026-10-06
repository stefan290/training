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
    /// Kept non-optional: bodyweight rep-based results already log a real,
    /// meaningful `0` here (no external load) — the same honest "zero load"
    /// convention extends cleanly to a duration-only result (e.g. an
    /// unweighted Plank also truthfully logs `0`, never a placeholder).
    /// Confirmed no real case this checkpoint touches requires `nil`
    /// weight, so this is left unchanged rather than made optional "for
    /// symmetry" alone.
    var weight: Double
    /// Dogfood Round 2 Continuation (Finding J): `nil` for a distance/
    /// duration-based result (e.g. Farmer's Carry) — never a fabricated
    /// `0`, which would be indistinguishable from a real zero-rep
    /// strength result. Every rep-based reader across this codebase was
    /// audited to explicitly exclude a `nil`-reps result from rep-only
    /// computations (progression, PR bands, RM calculations) rather than
    /// coercing it to `0`.
    var reps: Int?
    var targetRir: Int?
    /// GENERIC STRENGTH PRESCRIPTION AUTHORITY V1: snapshot of
    /// `SetPrescription.targetRirHigh` at logging time, mirroring
    /// `targetRir`'s own existing snapshot pattern. `nil` for every
    /// pre-existing row (a single-value RIR target).
    var targetRirHigh: Int?
    var actualRir: Int?
    var completedAt: Date
    var isPersonalRecord: Bool
    /// Rep-band identifier this set counts toward, e.g. "8-12". Nil for
    /// warmup or non-record-eligible sets.
    var prBand: String?
    /// Dogfood Round 2 Continuation (Finding J): the actual distance/
    /// duration recorded for a non-rep-based result — composable with
    /// `weight` (Farmer's Carry: real load + real distance), never a
    /// second, parallel result model. `nil` for every rep-based result,
    /// including every existing row.
    var distanceMeters: Double?
    var durationSeconds: Int?

    init(
        id: UUID = UUID(),
        setIndex: Int,
        weight: Double,
        reps: Int?,
        targetRir: Int? = nil,
        targetRirHigh: Int? = nil,
        actualRir: Int? = nil,
        completedAt: Date = Date(),
        isPersonalRecord: Bool = false,
        prBand: String? = nil,
        distanceMeters: Double? = nil,
        durationSeconds: Int? = nil
    ) {
        self.id = id
        self.setIndex = setIndex
        self.weight = weight
        self.reps = reps
        self.targetRir = targetRir
        self.targetRirHigh = targetRirHigh
        self.actualRir = actualRir
        self.completedAt = completedAt
        self.isPersonalRecord = isPersonalRecord
        self.prBand = prBand
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
    }
}
