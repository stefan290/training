import Foundation
import SwiftData

/// FUNCTIONAL FITNESS PROGRAMMING AUTHORITY V2, Section 5: athlete-
/// specific movement capability — permanent, cross-program memory,
/// scoped to `(PerformanceProfile, Exercise)` exactly like
/// `ExercisePerformanceProfile`/`ActivityPerformanceProfile`/
/// `BenchmarkPerformanceProfile` (its real siblings on `PerformanceProfile`,
/// never scoped to one `ProgramInstance` the way `SourceRMCalibration`
/// deliberately is). Separate from `Exercise.requiresDemonstratedCapability`
/// (a global, non-athlete-specific catalog flag) — this is the real,
/// per-athlete answer to "can THIS athlete be programmed THIS movement."
///
/// `capacityType`/`capacityValue` are optional and independent of
/// `proficiency` (Section 7): a missing capacity value does NOT mean the
/// athlete cannot perform the movement — proficiency answers whether it
/// may be used for a programming purpose; capacity answers how it may be
/// dosed once known. Not every movement carries the same capacity type
/// (a Snatch's capacity is a load/RM; a Double-Under's is max unbroken
/// reps) — see `MovementCapacityType`'s own doc comment for why this is a
/// flat discriminator + scalar pair, not an enum-with-payload.
@Model
final class MovementCapabilityProfile {
    @Attribute(.unique) var id: UUID
    var performanceProfile: PerformanceProfile?
    /// Un-inversed, like `SourceRMCalibration.exercise`/
    /// `SlotSelectionOverride.selectedExercise` — same documented,
    /// deferred risk (`DELETE_RULE_MATRIX.md`).
    var exercise: Exercise?

    var proficiency: MovementProficiency
    var capacityType: MovementCapacityType?
    var capacityValue: Double?

    var evidenceSource: CapabilityEvidenceSource
    var evidenceDate: Date

    init(
        id: UUID = UUID(),
        exercise: Exercise?,
        proficiency: MovementProficiency,
        capacityType: MovementCapacityType? = nil,
        capacityValue: Double? = nil,
        evidenceSource: CapabilityEvidenceSource,
        evidenceDate: Date = Date()
    ) {
        self.id = id
        self.exercise = exercise
        self.proficiency = proficiency
        self.capacityType = capacityType
        self.capacityValue = capacityValue
        self.evidenceSource = evidenceSource
        self.evidenceDate = evidenceDate
    }
}
