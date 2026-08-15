import Foundation
import SwiftData

/// The template-graph analogue of `FunctionalFitnessPrescription` —
/// reusable methodology (a target stimulus + format + movement-slot
/// requirements, never a resolved concrete workout), mirroring
/// `SteadyStatePrescriptionTemplate`/`IntervalPrescriptionTemplate`'s
/// relationship to their execution-side siblings exactly. Closes the
/// Functional Fitness quarter of the gap `WorkoutBlockTemplate`'s Stage
/// 4A doc comment originally deferred.
///
/// **`stimulus`/`format` are stored as direct top-level properties, not
/// flattened.** Unlike `StrengthProgressionRules`/`SteadyStateProgressionRules`/
/// `IntervalProgressionRules` (all flattened after Stage 4A's Bug 2/3),
/// `Stimulus` (which contains `movementModalityMix: [ModalityCount]`, an
/// array of a multi-field struct) and `WorkoutFormat` (an enum with
/// associated values) have **already been round-tripping safely through
/// SwiftData since Stage 3C** — `FunctionalFitnessPrescription.stimulus`/
/// `.format` and `BenchmarkDefinition.stimulus`/`.format` store them this
/// exact way today, exercised by
/// `ModalityPersistenceRoundTripTests.testFunctionalFitnessPrescriptionAndScaledResultSurviveRoundTrip`/
/// `.testBenchmarkDefinitionAndPerformanceProfileSurviveRoundTrip`, both
/// part of the pre-Stage-4E passing suite. This is real, existing
/// evidence a multi-field-struct array *can* round-trip safely in this
/// codebase — not a new, untested assumption.
@Model
final class FunctionalFitnessPrescriptionTemplate {
    @Attribute(.unique) var id: UUID
    var workoutBlockTemplate: WorkoutBlockTemplate?

    /// The target stimulus this template is generated/configured to hit
    /// (Stage 4E §2's Stage-A pipeline output) — never itself adjusted at
    /// generation time; see `FunctionalFitnessMaterializer` for where
    /// exposure-informed variance actually applies.
    var stimulus: Stimulus
    var format: WorkoutFormat

    @Relationship(deleteRule: .cascade, inverse: \FunctionalFitnessMovementSlotTemplate.functionalFitnessPrescriptionTemplate)
    var movementSlots: [FunctionalFitnessMovementSlotTemplate] = []

    /// §15/§42: when `true`, the materializer must not resolve a future
    /// week's variance-adjusted stimulus without the decision engine
    /// having real completed exposure history to reason about — the
    /// Functional Fitness sibling of `IntervalProgressionRules.requiresSuccessfulCompletionToProgress`.
    var requiresRecentExposureToProgress: Bool
    /// Plain struct of two `Int?` fields, no enum-with-payload — the
    /// already-proven-safe "store directly" shape
    /// (`DeloadPositionOverride`/`TrainingStressProfile`'s precedent).
    var varianceConstraints: VarianceConstraints?

    init(
        id: UUID = UUID(),
        stimulus: Stimulus,
        format: WorkoutFormat,
        requiresRecentExposureToProgress: Bool = false,
        varianceConstraints: VarianceConstraints? = nil
    ) {
        self.id = id
        self.stimulus = stimulus
        self.format = format
        self.requiresRecentExposureToProgress = requiresRecentExposureToProgress
        self.varianceConstraints = varianceConstraints
    }

    /// The only way application code should attach a movement slot.
    /// Mutates exactly one side (this array); SwiftData maintains
    /// `slot.functionalFitnessPrescriptionTemplate` from the declared
    /// inverse.
    func addMovementSlot(_ slot: FunctionalFitnessMovementSlotTemplate) {
        slot.sortIndex = movementSlots.count
        movementSlots.append(slot)
    }

    var orderedMovementSlots: [FunctionalFitnessMovementSlotTemplate] {
        movementSlots.sorted { $0.sortIndex < $1.sortIndex }
    }
}
