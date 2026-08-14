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

    @Relationship(deleteRule: .cascade, inverse: \ExerciseAlias.exercise)
    var aliases: [ExerciseAlias] = []

    init(
        id: UUID = UUID(),
        canonicalName: String,
        modality: TrainingModality,
        equipment: String,
        movementPattern: String
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.modality = modality
        self.equipment = equipment
        self.movementPattern = movementPattern
    }

    /// The only way application code should attach an ExerciseAlias.
    /// Mutates exactly one side (this array); SwiftData maintains
    /// `alias.exercise` from the declared inverse.
    func addAlias(_ alias: ExerciseAlias) {
        aliases.append(alias)
    }
}
