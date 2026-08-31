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
    /// The FINAL, actually-prescribed Stimulus — after Stage CP.2's
    /// cross-modality/same-week adaptation, if any ran. Kept as `stimulus`
    /// (not renamed to `finalStimulus`) since every real consumer
    /// (execution scoring, `FunctionalFitnessExposureHistoryBuilder`,
    /// `CurrentWeekFunctionalFitnessProgrammingContext`) already wants
    /// exactly this value and already reads this field name — this is
    /// the one, single persisted source of truth for FINAL.
    var stimulus: Stimulus
    /// Stage FF.L1 addition. What Functional Fitness's own intent-shaping
    /// checks decided BEFORE Stage CP.2 adaptation ran — a genuine,
    /// independent, immutable snapshot captured at materialization time,
    /// never reconstructed later from `stimulus`/`reasonCode`/current
    /// engine logic (`FUNCTIONAL_FITNESS_LONGITUDINAL_PROGRAMMING_DESIGN.md`'s
    /// Design Lock proves reconstruction is dishonest). `nil` for every
    /// prescription persisted before this field existed — Stage CP.2 may
    /// already have adapted that old prescription's single stored value,
    /// so it is NOT safe to assume a legacy record's intended equaled its
    /// final; representing that historical fact as genuinely unknown
    /// (`nil`) is the honest choice, never a fabricated guess.
    var intendedStimulus: Stimulus?
    var format: WorkoutFormat

    @Relationship(deleteRule: .cascade, inverse: \FunctionalFitnessMovement.functionalFitnessPrescription)
    var movements: [FunctionalFitnessMovement] = []

    init(
        id: UUID = UUID(),
        stimulus: Stimulus,
        intendedStimulus: Stimulus? = nil,
        format: WorkoutFormat
    ) {
        self.id = id
        self.stimulus = stimulus
        self.intendedStimulus = intendedStimulus
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
