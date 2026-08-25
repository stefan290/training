import Foundation
import SwiftData

/// Stage 10R.1C: explicit, source-program-required calibration state —
/// the literal, physically-tested RM value (10RM/8RM/5RM, per `rmType`)
/// a source workbook requires the user to supply before its `.rmBased`
/// prescriptions can be materialized
/// (`STAGE10R1C_SOURCE_RM_CALIBRATION_DESIGN.md`). Scoped to `(programInstance,
/// exercise, rmType)` — never global per `Exercise` — because the source
/// itself requires fresh input at each program/mesocycle boundary and
/// never carries a value forward automatically (Part 3 of the design
/// doc). `kilograms` is the literal entered number, never converted,
/// never estimated — `StrengthProgressionEngine` reads it as the exact
/// same opaque `rmKilograms` scalar it always has for every `.rmBased`
/// rule, regardless of family.
///
/// **Deliberately NOT `ExercisePerformanceProfile.estimatedOneRepMax`:**
/// that field means "an estimated 1RM" — a different quantity (basis and
/// scope both) from a literal, mesocycle-fresh 10RM/8RM/5RM test value.
/// The two are never merged, never converted into one another, and
/// `estimatedOneRepMax` is untouched by this feature — it remains
/// available for whatever future performance-estimate feature might
/// legitimately want it.
@Model
final class SourceRMCalibration {
    @Attribute(.unique) var id: UUID
    var programInstance: ProgramInstance?
    /// Un-inversed, like `SlotSelectionOverride.selectedExercise` — the
    /// same documented, deferred risk (`DELETE_RULE_MATRIX.md`).
    var exercise: Exercise?
    var rmType: RMType
    /// The literal, user-entered value for `rmType`'s basis — a real
    /// 10RM, 8RM, or 5RM, never a converted or estimated figure.
    var kilograms: Double
    var enteredAt: Date

    init(
        id: UUID = UUID(),
        exercise: Exercise?,
        rmType: RMType,
        kilograms: Double,
        enteredAt: Date = Date()
    ) {
        self.id = id
        self.exercise = exercise
        self.rmType = rmType
        self.kilograms = kilograms
        self.enteredAt = enteredAt
    }
}
