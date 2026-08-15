import Foundation
import SwiftData

/// A canonical, stable exercise identity. All performance data references
/// this ID — never a source string — so renamed or re-imported exercises
/// never fragment a user's history. Benchmarks (e.g. "Fran") are modelled
/// as Exercises too in this pass rather than a separate Benchmark entity;
/// see ARCHITECTURE.md for the tradeoff.
@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var canonicalName: String
    var modality: TrainingModality
    var equipment: String
    var movementPattern: String
    /// Stage 4C addition: which `ExerciseSlot.allowedTargets` this Exercise
    /// satisfies — closes a real gap `ExerciseSlot`'s own doc comment
    /// already assumed was solvable ("any Exercise matching allowedTargets
    /// is eligible") but nothing on `Exercise` could actually be matched
    /// against until now. Empty is a legal, common state for every
    /// pre-Stage-4C seed exercise; it means "no target-based validity
    /// check possible for this Exercise," not "targets nothing" — slots
    /// that rely on `allowedTargets` should treat an empty array here as
    /// non-matching, never as wildcard-matching (see
    /// `SubstitutionValidator`).
    var primaryTargets: [MuscleGroup] = []

    @Relationship(deleteRule: .cascade, inverse: \ExerciseAlias.exercise)
    var aliases: [ExerciseAlias] = []

    init(
        id: UUID = UUID(),
        canonicalName: String,
        modality: TrainingModality,
        equipment: String,
        movementPattern: String,
        primaryTargets: [MuscleGroup] = []
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.modality = modality
        self.equipment = equipment
        self.movementPattern = movementPattern
        self.primaryTargets = primaryTargets
    }

    /// The only way application code should attach an ExerciseAlias.
    /// Mutates exactly one side (this array); SwiftData maintains
    /// `alias.exercise` from the declared inverse.
    func addAlias(_ alias: ExerciseAlias) {
        aliases.append(alias)
    }
}
