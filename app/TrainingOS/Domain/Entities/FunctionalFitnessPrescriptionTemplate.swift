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
/// **`stimulus` is stored as a direct top-level property; `format` is
/// NOT (FF WorkoutFormat SwiftData fix, this pass).** `Stimulus` (which
/// contains `movementModalityMix: [ModalityCount]`, an array of a multi-
/// field struct) has round-tripped safely through SwiftData since Stage
/// 3C and remains a direct property. `WorkoutFormat` (an enum with
/// associated values, several optional) was ALSO believed safe on this
/// same evidence — but a real crash (`Could not cast value of type
/// 'Swift.Optional<Any>' to 'TrainingOS.WorkoutFormat'`) was reproduced
/// this pass for a real, multi-week materialized graph with several
/// sibling `FunctionalFitnessPrescription` rows carrying different cases
/// (at least one with a `nil` optional payload), fetched from a fresh
/// context — the pre-existing `ModalityPersistenceRoundTripTests` never
/// exercised that combination. `format` is now a computed property
/// backed by a manually flattened tagged union
/// (`WorkoutFormatKind`/`WorkoutFormatCoding`, `WorkoutFormat.swift`),
/// mirroring `StrengthProgressionRules`' own `LoadRule`/`SetCountRule`
/// fix for the identical class of bug.
@Model
final class FunctionalFitnessPrescriptionTemplate {
    @Attribute(.unique) var id: UUID
    var workoutBlockTemplate: WorkoutBlockTemplate?

    /// The target stimulus this template is generated/configured to hit
    /// (Stage 4E §2's Stage-A pipeline output) — never itself adjusted at
    /// generation time; see `FunctionalFitnessMaterializer` for where
    /// exposure-informed variance actually applies.
    var stimulus: Stimulus

    // MARK: - `format` — flattened tagged union (see this file's own doc
    // comment above and `WorkoutFormat.swift`'s doc comment for why).
    var workoutFormatKind: WorkoutFormatKind = WorkoutFormatKind.maxLoad
    var workoutFormatCapSeconds: Int?
    var workoutFormatRounds: Int?
    var workoutFormatIntervalSeconds: Int?
    var workoutFormatTotalSeconds: Int?
    var workoutFormatDirection: LadderDirection?
    var workoutFormatCount: Int?
    var workoutFormatWorkSeconds: Int?
    var workoutFormatRestSeconds: Int?

    var format: WorkoutFormat {
        get {
            WorkoutFormatCoding.reconstruct(WorkoutFormatCoding.Flat(
                kind: workoutFormatKind, capSeconds: workoutFormatCapSeconds, rounds: workoutFormatRounds,
                intervalSeconds: workoutFormatIntervalSeconds, totalSeconds: workoutFormatTotalSeconds,
                direction: workoutFormatDirection, count: workoutFormatCount,
                workSeconds: workoutFormatWorkSeconds, restSeconds: workoutFormatRestSeconds
            ))
        }
        set {
            let flat = WorkoutFormatCoding.flatten(newValue)
            workoutFormatKind = flat.kind
            workoutFormatCapSeconds = flat.capSeconds
            workoutFormatRounds = flat.rounds
            workoutFormatIntervalSeconds = flat.intervalSeconds
            workoutFormatTotalSeconds = flat.totalSeconds
            workoutFormatDirection = flat.direction
            workoutFormatCount = flat.count
            workoutFormatWorkSeconds = flat.workSeconds
            workoutFormatRestSeconds = flat.restSeconds
        }
    }

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

    /// Stage FF.M1: `true` (the default, including every legacy row — safe
    /// because zero authored/benchmark FF content exists in production
    /// today) means this template's movement slots are composed FRESH at
    /// each real tactical materialization (`FunctionalFitnessMaterializer`
    /// now owns Stage C, reading that week's FINAL stimulus — see
    /// `FunctionalFitnessMovementComposer`), never pre-baked at generation
    /// time. `false` marks a future fixed/authored/benchmark prescription
    /// whose `movementSlots` are generation-time content the materializer
    /// must never dynamically recompose. Deliberately NOT expressed via
    /// `ProgramProvenance` (`.sourced`/`.constructed` encode import
    /// traceability, an unrelated concept).
    var isDynamicallyComposed: Bool = true

    init(
        id: UUID = UUID(),
        stimulus: Stimulus,
        format: WorkoutFormat,
        requiresRecentExposureToProgress: Bool = false,
        varianceConstraints: VarianceConstraints? = nil,
        isDynamicallyComposed: Bool = true
    ) {
        self.id = id
        self.stimulus = stimulus
        self.requiresRecentExposureToProgress = requiresRecentExposureToProgress
        self.varianceConstraints = varianceConstraints
        self.isDynamicallyComposed = isDynamicallyComposed
        self.format = format
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
