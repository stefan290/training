import Foundation
import SwiftData

/// A movement-pattern slot in the template graph, resolved to a concrete
/// `Exercise` either when a curated built-in program is authored or when a
/// specific user's `ProgramInstance` is created from the template — never
/// hard-coded to one `Exercise` merely to avoid this schema (Stage 3
/// decision A6). `allowedTargets` survives resolution (never cleared once
/// `resolvedExercise` is set) so the original slot intent stays
/// inspectable even after a concrete choice was made.
///
/// **Stage 4E addition:** `allowedMovementFunctions`/`allowedModalities`
/// let a Functional Fitness movement slot (e.g. "moderate-loaded squat/
/// press," "gymnastics pull," "monostructural") reuse this exact same
/// type, and therefore the exact same substitution machinery
/// (`SubstitutionValidator`, `SlotSelectionOverride`,
/// `SubstituteExerciseUseCase`) already built and tested for strength —
/// rather than a second, parallel slot/override system for Functional
/// Fitness. `owningFunctionalFitnessSlot` is the new owning parent this
/// stage adds (`FunctionalFitnessMovementSlotTemplate` wraps one
/// `ExerciseSlot` plus FF-specific per-movement targets, mirroring how
/// `PrescriptionTemplate` already wraps one `ExerciseSlot` plus
/// strength-specific rule fields) — `ExerciseSlot` itself stays exactly
/// as general-purpose as it already was.
@Model
final class ExerciseSlot {
    @Attribute(.unique) var id: UUID
    /// The delete rule lives on `PrescriptionTemplate.exerciseSlot` — this
    /// is a plain inverse property, same pattern as
    /// `TrainingWeek.programDefinition`.
    var prescriptionTemplate: PrescriptionTemplate?
    /// The Stage 4E sibling of `prescriptionTemplate` above — the delete
    /// rule lives on `FunctionalFitnessMovementSlotTemplate.exerciseSlot`.
    /// At most one of `prescriptionTemplate`/`owningFunctionalFitnessSlot`
    /// is ever set on a given row — a slot belongs to exactly one
    /// template graph, never both.
    var owningFunctionalFitnessSlot: FunctionalFitnessMovementSlotTemplate?
    /// e.g. "Horizontal Push", "Chest Isolation or Triceps".
    var name: String
    /// Stable position among a Functional Fitness prescription's
    /// multiple slots (e.g. a triplet's 3 movements) — meaningless and
    /// always `0` for strength's single-slot-per-`PrescriptionTemplate`
    /// usage, assigned by `FunctionalFitnessMovementSlotTemplate`'s own
    /// attach method.
    var sortIndex: Int
    var allowedTargets: [MuscleGroup]
    /// Stage 4E addition, Functional Fitness's movement-pattern
    /// equivalent of `allowedTargets` — e.g. `[.squatLoaded, .pressLoaded]`
    /// for "moderate-loaded squat/push." Empty means no movement-
    /// function-based constraint (matched the same way an empty
    /// `allowedTargets` means no muscle-group-based constraint).
    var allowedMovementFunctions: [MovementFunction]
    /// Stage 4E addition — e.g. `[.gymnastics]` for a "gymnastics pull"
    /// slot, `[.metabolicConditioning]` for "monostructural."
    var allowedModalities: [FunctionalModality]
    /// Optional explicit constraint narrower than `allowedTargets` (e.g.
    /// "barbell bench press or dumbbell bench press, nothing else"). Empty
    /// means any `Exercise` matching `allowedTargets` is eligible.
    /// Un-inversed like `ExercisePrescription.exercise` — the same
    /// documented, deferred risk (`DELETE_RULE_MATRIX.md`).
    var allowedExercises: [Exercise]
    var resolvedExercise: Exercise?

    /// Stage 4C addition: `SlotSelectionOverride`'s required inverse —
    /// nothing reads this collection. Needed purely because an
    /// un-inversed to-one reference to a type that can be deleted (this
    /// one, unlike `Exercise`, genuinely is — `ExerciseSlot` cascades away
    /// with its `ProgramDefinition`) crashes instead of nullifying
    /// cleanly; same established pattern as
    /// `PrescriptionTemplate.referencedAsPairedSlotBy`.
    @Relationship(deleteRule: .nullify, inverse: \SlotSelectionOverride.templateSlot)
    var slotSelectionOverrides: [SlotSelectionOverride] = []

    /// Stage 6B addition: `ExercisePrescription.sourceExerciseSlot`'s
    /// required inverse — nothing reads this collection. Same reasoning as
    /// `slotSelectionOverrides` above: lets a live execution's Change
    /// Exercise flow trace a materialized movement back to the slot it
    /// came from, while `.nullify` keeps that movement (and every
    /// SetResult logged against it) intact if this slot's `ProgramDefinition`
    /// is later deleted (CLAUDE.md rule 1).
    @Relationship(deleteRule: .nullify, inverse: \ExercisePrescription.sourceExerciseSlot)
    var materializedPrescriptions: [ExercisePrescription] = []

    /// Stage 8B addition: `FunctionalFitnessMovement.sourceExerciseSlot`'s
    /// required inverse — nothing reads this collection. Exact same
    /// reasoning as `materializedPrescriptions` above, one level over, for
    /// Functional Fitness's live movements instead of strength's live
    /// prescriptions.
    @Relationship(deleteRule: .nullify, inverse: \FunctionalFitnessMovement.sourceExerciseSlot)
    var materializedFunctionalFitnessMovements: [FunctionalFitnessMovement] = []

    init(
        id: UUID = UUID(),
        name: String,
        allowedTargets: [MuscleGroup] = [],
        allowedMovementFunctions: [MovementFunction] = [],
        allowedModalities: [FunctionalModality] = [],
        allowedExercises: [Exercise] = [],
        resolvedExercise: Exercise? = nil
    ) {
        self.id = id
        self.name = name
        self.sortIndex = 0
        self.allowedTargets = allowedTargets
        self.allowedMovementFunctions = allowedMovementFunctions
        self.allowedModalities = allowedModalities
        self.allowedExercises = allowedExercises
        self.resolvedExercise = resolvedExercise
    }
}
