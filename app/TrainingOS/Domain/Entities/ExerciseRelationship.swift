import Foundation
import SwiftData

/// The curated half of the Exercise Library's substitution relationships
/// (Stage 4C §26). Only the two relationship kinds that genuinely require
/// human/product judgment are persisted here — `.directSubstitute` (an
/// authored equivalence, e.g. Barbell <-> Dumbbell Bench Press, which
/// share no single `Exercise` field that would let a query derive it) and
/// `.similarMovement` (a fuzzy, curated judgment call). The other three
/// kinds `ExerciseRelationshipType` names (`.sameMovementPattern`,
/// `.samePrimaryTarget`, `.sameEquipmentFamily`) are deliberately **not**
/// persisted as rows here — they're fully derivable by comparing two
/// `Exercise` rows' own `movementPattern`/`primaryTargets`/`equipment`
/// fields, and persisting a redundant relationship row for an already-
/// computable fact would itself be the "avoid duplicate truth" smell
/// Stage 4C explicitly warns against. `ExerciseRelationshipResolver`
/// presents both kinds through one uniform read API so callers never need
/// to know which three are computed and which two are stored.
///
/// Directed (`fromExercise -> toExercise`), not assumed symmetric — a
/// curator may reasonably consider Dumbbell Bench Press a direct
/// substitute for Barbell Bench Press without the reverse being equally
/// true (e.g. programming that specifically wants the stabilization
/// demand). Callers that want a symmetric check query both directions
/// explicitly; this type does not fabricate a mirrored row.
///
/// Never merges canonical identity — this table only ever links two
/// distinct, independently-tracked `Exercise` rows; nothing in this file
/// touches either exercise's `ExercisePerformanceProfile`.
@Model
final class ExerciseRelationship {
    @Attribute(.unique) var id: UUID
    /// Un-inversed, like `ExerciseSlot.allowedExercises`/
    /// `ExercisePrescription.exercise` — the same documented, deferred
    /// risk (`DELETE_RULE_MATRIX.md`): `Exercise` deletion is not a
    /// reachable operation anywhere in this codebase yet, so fixing this
    /// specific reference in isolation would be a narrower, inconsistent
    /// exception rather than closing the actual risk category.
    var fromExercise: Exercise?
    var toExercise: Exercise?
    var type: ExerciseRelationshipType

    init(id: UUID = UUID(), fromExercise: Exercise?, toExercise: Exercise?, type: ExerciseRelationshipType) {
        self.id = id
        self.fromExercise = fromExercise
        self.toExercise = toExercise
        self.type = type
    }
}

/// `.sameMovementPattern`/`.samePrimaryTarget`/`.sameEquipmentFamily` are
/// never constructed as `ExerciseRelationship` rows (see the type's own
/// doc comment) — they exist in this enum so
/// `ExerciseRelationshipResolver`'s uniform query API can report them
/// alongside the two curated kinds, not because a curator ever authors one
/// directly.
enum ExerciseRelationshipType: String, Codable, CaseIterable {
    case directSubstitute
    case similarMovement
    case sameMovementPattern
    case samePrimaryTarget
    case sameEquipmentFamily
}
