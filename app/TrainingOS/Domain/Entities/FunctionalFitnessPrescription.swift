import Foundation
import SwiftData

/// The typed prescription for a `.functionalFitness` `WorkoutBlock`.
/// `stimulus` and `format` are stored as two separate, strongly-typed
/// attributes — never merged into one — per
/// `FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md` §2's explicit requirement
/// that two workouts sharing a format can have completely different
/// stimuli.
///
/// `workoutBlock` is `nil` for a `FunctionalFitnessPrescription` that only
/// exists as part of a `BenchmarkDefinition`'s stable template data (no
/// live attempt yet) — every *attempt* at a benchmark creates its own
/// prescription, attached to its own `WorkoutBlock`, referencing the
/// `BenchmarkDefinition` via its result, not by sharing this object.
@Model
final class FunctionalFitnessPrescription {
    @Attribute(.unique) var id: UUID
    var workoutBlock: WorkoutBlock?
    var stimulus: Stimulus
    var format: WorkoutFormat

    @Relationship(deleteRule: .cascade, inverse: \FunctionalFitnessMovement.functionalFitnessPrescription)
    var movements: [FunctionalFitnessMovement] = []

    init(
        id: UUID = UUID(),
        stimulus: Stimulus,
        format: WorkoutFormat
    ) {
        self.id = id
        self.stimulus = stimulus
        self.format = format
    }

    /// The only way application code should attach a movement. Mutates
    /// exactly one side (this array); SwiftData maintains
    /// `movement.functionalFitnessPrescription` from the declared inverse.
    func addMovement(_ movement: FunctionalFitnessMovement) {
        movement.sortIndex = movements.count
        movements.append(movement)
    }

    var orderedMovements: [FunctionalFitnessMovement] {
        movements.sorted { $0.sortIndex < $1.sortIndex }
    }
}
