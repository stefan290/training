import Foundation
import SwiftData

/// A canonical, stable exercise identity. All performance data references
/// this ID — never a source string — so renamed or re-imported exercises
/// never fragment a user's history. Benchmarks (e.g. "Fran") are **not**
/// modelled as Exercises — Stage 3C's `BenchmarkDefinition`/
/// `BenchmarkPerformanceProfile` is the sole canonical benchmark
/// representation as of Stage 4E's consolidation (see
/// `STAGE4_IMPLEMENTATION_REPORT.md`'s Stage 4E §9); this doc comment
/// previously said otherwise, from before that consolidation.
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
    /// Stage 4E addition: which `ExerciseSlot.allowedMovementFunctions`
    /// this Exercise satisfies — a Functional Fitness movement-slot
    /// sibling of `primaryTargets`, closing the identical gap for
    /// movement-pattern-based slot matching (§7: "Do not parse exercise
    /// names... Use canonical Exercise metadata"). A Thruster is both
    /// `.squatLoaded` and `.pressLoaded`, hence an array, not a single
    /// value. Empty means "no movement-function-based validity check
    /// possible," never "matches nothing."
    var movementFunctions: [MovementFunction] = []
    /// Stage 4E addition: which broad Functional Fitness category this
    /// Exercise belongs to (metabolic conditioning / gymnastics /
    /// weightlifting) — `nil` for exercises outside Functional Fitness
    /// programming entirely (e.g. Barbell Bench Press), matching
    /// `primaryTargets`' "empty/nil means not applicable, not wildcard"
    /// convention.
    var functionalModality: FunctionalModality?
    /// Stage 10C.1 addition: what physical equipment this exercise
    /// actually requires (see `EquipmentRequirement`'s own doc comment
    /// for why this is a separate concept from `equipment: String`
    /// above, which is unchanged and keeps its existing job). Empty is
    /// the default for every pre-Stage-10C.1 row and simply means "not
    /// yet recorded," not "requires nothing" — no code reads this field
    /// yet, so there is no behavioral difference either way.
    var requiredEquipment: [EquipmentRequirement] = []

    @Relationship(deleteRule: .cascade, inverse: \ExerciseAlias.exercise)
    var aliases: [ExerciseAlias] = []

    /// Stage 10R.7A-TX addition: `ExerciseSlot.resolvedExercise`'s required
    /// inverse — nothing reads this collection. Many `ExerciseSlot`s may
    /// legitimately resolve to the same shared canonical Exercise (that's
    /// the whole point of a canonical catalog); `.nullify` because a
    /// canonical Exercise is shared catalog data never owned by any one
    /// slot — deleting a slot (or its `ProgramDefinition`) must never
    /// touch the Exercise, and nothing in this app deletes a canonical
    /// Exercise out from under active slots. Without a declared inverse,
    /// SwiftData's own uniqueness-constraint conflict resolution (fired by
    /// `Exercise.canonicalName`'s `@Attribute(.unique)`) has no path to
    /// correctly repair a to-one relationship pointing at a row it merges
    /// away, and instead corrupts an unrelated `Exercise` row — see
    /// `STAGE10R7A_TX_ROOT_CAUSE_REPORT.md`.
    @Relationship(deleteRule: .nullify, inverse: \ExerciseSlot.resolvedExercise)
    var resolvedSlots: [ExerciseSlot] = []

    init(
        id: UUID = UUID(),
        canonicalName: String,
        modality: TrainingModality,
        equipment: String,
        movementPattern: String,
        primaryTargets: [MuscleGroup] = [],
        movementFunctions: [MovementFunction] = [],
        functionalModality: FunctionalModality? = nil,
        requiredEquipment: [EquipmentRequirement] = []
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.modality = modality
        self.equipment = equipment
        self.movementPattern = movementPattern
        self.primaryTargets = primaryTargets
        self.movementFunctions = movementFunctions
        self.functionalModality = functionalModality
        self.requiredEquipment = requiredEquipment
    }

    /// The only way application code should attach an ExerciseAlias.
    /// Mutates exactly one side (this array); SwiftData maintains
    /// `alias.exercise` from the declared inverse.
    func addAlias(_ alias: ExerciseAlias) {
        aliases.append(alias)
    }
}
