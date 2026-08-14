import Foundation
import SwiftData

/// A movement-pattern slot in the template graph, resolved to a concrete
/// `Exercise` either when a curated built-in program is authored or when a
/// specific user's `ProgramInstance` is created from the template — never
/// hard-coded to one `Exercise` merely to avoid this schema (Stage 3
/// decision A6). `allowedTargets` survives resolution (never cleared once
/// `resolvedExercise` is set) so the original slot intent stays
/// inspectable even after a concrete choice was made.
@Model
final class ExerciseSlot {
    @Attribute(.unique) var id: UUID
    /// The delete rule lives on `PrescriptionTemplate.exerciseSlot` — this
    /// is a plain inverse property, same pattern as
    /// `TrainingWeek.programDefinition`.
    var prescriptionTemplate: PrescriptionTemplate?
    /// e.g. "Horizontal Push", "Chest Isolation or Triceps".
    var name: String
    var allowedTargets: [MuscleGroup]
    /// Optional explicit constraint narrower than `allowedTargets` (e.g.
    /// "barbell bench press or dumbbell bench press, nothing else"). Empty
    /// means any `Exercise` matching `allowedTargets` is eligible.
    /// Un-inversed like `ExercisePrescription.exercise` — the same
    /// documented, deferred risk (`DELETE_RULE_MATRIX.md`).
    var allowedExercises: [Exercise]
    var resolvedExercise: Exercise?

    init(
        id: UUID = UUID(),
        name: String,
        allowedTargets: [MuscleGroup] = [],
        allowedExercises: [Exercise] = [],
        resolvedExercise: Exercise? = nil
    ) {
        self.id = id
        self.name = name
        self.allowedTargets = allowedTargets
        self.allowedExercises = allowedExercises
        self.resolvedExercise = resolvedExercise
    }
}
