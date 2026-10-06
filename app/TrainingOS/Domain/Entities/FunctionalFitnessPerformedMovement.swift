import Foundation
import SwiftData

/// What actually happened for one movement inside a
/// `FunctionalFitnessResult`. `prescribedMovement` is a traceability
/// pointer, never mutated to represent scaling — Stage 3B/3C's explicit
/// requirement (`FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md` §6): the original
/// prescription is preserved exactly as prescribed, and the performed
/// variant (a substituted exercise, a different load) is recorded
/// alongside it, never overwriting it.
///
/// `performedExercise == nil` means "performed exactly as prescribed";
/// a non-nil value (e.g. Knee Raises where Toes-to-Bar was prescribed)
/// means a scaled substitution. `prescribedMovement` has no inverse
/// collection needed for application logic, but SwiftData requires a
/// declared inverse somewhere for a to-one `@Model` reference to nullify
/// cleanly on delete — that inverse is
/// `FunctionalFitnessMovement.performedAttempts`, mirroring the
/// established `ProgramDefinition.instances`-style fix from Stage 2.
@Model
final class FunctionalFitnessPerformedMovement {
    @Attribute(.unique) var id: UUID
    var functionalFitnessResult: FunctionalFitnessResult?
    var prescribedMovement: FunctionalFitnessMovement?
    var sortIndex: Int

    var performedExercise: Exercise?
    var performedReps: Int?
    var performedCalories: Int?
    var performedDistanceMeters: Double?
    /// MUSCLE + 5FF FINAL CLOSURE, Section 9: the actual-result sibling of
    /// `FunctionalFitnessMovement.durationSeconds`, added for the same
    /// reason `performedDistanceMeters` exists alongside
    /// `FunctionalFitnessMovement.distanceMeters` — never merges
    /// prescribed and actual (CLAUDE.md rule 3).
    var performedDurationSeconds: Int?
    var performedLoadKilograms: Double?

    init(
        id: UUID = UUID(),
        prescribedMovement: FunctionalFitnessMovement? = nil,
        performedExercise: Exercise? = nil,
        performedReps: Int? = nil,
        performedCalories: Int? = nil,
        performedDistanceMeters: Double? = nil,
        performedDurationSeconds: Int? = nil,
        performedLoadKilograms: Double? = nil
    ) {
        self.id = id
        self.prescribedMovement = prescribedMovement
        self.sortIndex = 0
        self.performedExercise = performedExercise
        self.performedReps = performedReps
        self.performedCalories = performedCalories
        self.performedDistanceMeters = performedDistanceMeters
        self.performedDurationSeconds = performedDurationSeconds
        self.performedLoadKilograms = performedLoadKilograms
    }
}
