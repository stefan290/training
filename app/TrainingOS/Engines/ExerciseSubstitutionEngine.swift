import Foundation

/// Pure, deterministic substitution-validity checking (Stage 4C §27).
/// "Keep validation deterministic and explainable" rules out anything
/// probabilistic or string-heuristic (item 57's "parsing exercise names to
/// determine compatibility" smell) — this only ever compares typed fields
/// already on `ExerciseSlot`/`Exercise`.
enum SubstitutionValidator {
    /// A candidate is valid for a slot when:
    /// 1. `allowedExercises` is non-empty and contains the candidate by
    ///    identity (the slot's own explicit, narrower allow-list — checked
    ///    first because it is the more specific constraint, and it
    ///    short-circuits every other dimension below, unchanged since
    ///    Stage 4C), OR
    /// 2. `allowedExercises` is empty and the candidate satisfies *every*
    ///    non-empty constraint dimension among `allowedTargets`/
    ///    `allowedMovementFunctions`/`allowedModalities` (Stage 4E
    ///    addition, for Functional Fitness movement slots) — each
    ///    non-empty dimension must intersect the candidate's
    ///    corresponding field (OR within a dimension's own array, AND
    ///    across dimensions); an empty dimension imposes no constraint at
    ///    all. A candidate with no matching metadata at all never matches
    ///    a dimension-constrained slot — empty is "unmatchable," never
    ///    "wildcard," exactly `allowedTargets`' own existing rule,
    ///    generalized.
    /// 3. A slot with every dimension empty is fully unconstrained — any
    ///    candidate is valid (mirrors the existing "empty means no
    ///    explicit constraint" convention throughout this codebase, e.g.
    ///    `HypertrophyConfiguration`'s split fields).
    static func isValid(candidate: Exercise, for slot: ExerciseSlot) -> Bool {
        if !slot.allowedExercises.isEmpty {
            return slot.allowedExercises.contains { $0.id == candidate.id }
        }
        if !slot.allowedTargets.isEmpty, Set(candidate.primaryTargets).isDisjoint(with: Set(slot.allowedTargets)) {
            return false
        }
        if !slot.allowedMovementFunctions.isEmpty, Set(candidate.movementFunctions).isDisjoint(with: Set(slot.allowedMovementFunctions)) {
            return false
        }
        if !slot.allowedModalities.isEmpty {
            guard let candidateModality = candidate.functionalModality, slot.allowedModalities.contains(candidateModality) else {
                return false
            }
        }
        return true
    }
}

/// One relationship between two `Exercise`s, from `ExerciseRelationshipResolver`'s
/// uniform query API — regardless of whether it came from a curated
/// `ExerciseRelationship` row or was derived on the fly from shared
/// `Exercise` fields.
struct ExerciseRelationshipMatch: Equatable {
    let relatedExercise: Exercise
    let type: ExerciseRelationshipType
}

/// Merges curated `ExerciseRelationship` rows with relationships derivable
/// directly from `Exercise`'s own fields into one read API — see
/// `ExerciseRelationship`'s own doc comment for why only 2 of the 5
/// `ExerciseRelationshipType` cases are ever persisted.
enum ExerciseRelationshipResolver {
    /// All known relationships from `exercise` to every other exercise in
    /// `candidates`, curated and derived alike. Never includes `exercise`
    /// itself (an exercise is not "related" to itself in this vocabulary).
    static func relationships(
        from exercise: Exercise,
        candidates: [Exercise],
        curated: [ExerciseRelationship]
    ) -> [ExerciseRelationshipMatch] {
        var matches: [ExerciseRelationshipMatch] = []

        for curatedRow in curated where curatedRow.fromExercise?.id == exercise.id {
            guard let related = curatedRow.toExercise else { continue }
            matches.append(ExerciseRelationshipMatch(relatedExercise: related, type: curatedRow.type))
        }

        for candidate in candidates where candidate.id != exercise.id {
            if !exercise.primaryTargets.isEmpty && !Set(exercise.primaryTargets).isDisjoint(with: Set(candidate.primaryTargets)) {
                matches.append(ExerciseRelationshipMatch(relatedExercise: candidate, type: .samePrimaryTarget))
            }
            if candidate.movementPattern == exercise.movementPattern {
                matches.append(ExerciseRelationshipMatch(relatedExercise: candidate, type: .sameMovementPattern))
            }
            if candidate.equipment == exercise.equipment {
                matches.append(ExerciseRelationshipMatch(relatedExercise: candidate, type: .sameEquipmentFamily))
            }
        }

        return matches
    }

    /// The best related exercise to source a fallback recommendation
    /// estimate from (Stage 4C §25/§44) — curated relationships (an
    /// explicit product/human judgment) outrank derived ones, and
    /// `.directSubstitute` outranks `.similarMovement`, since a closer,
    /// more deliberately-authored relationship is a more trustworthy basis
    /// for an estimate than a coincidentally-shared field.
    static func bestEstimateSource(
        from exercise: Exercise,
        candidates: [Exercise],
        curated: [ExerciseRelationship]
    ) -> ExerciseRelationshipMatch? {
        let all = relationships(from: exercise, candidates: candidates, curated: curated)
        let rank: (ExerciseRelationshipType) -> Int = { type in
            switch type {
            case .directSubstitute: return 0
            case .similarMovement: return 1
            case .samePrimaryTarget: return 2
            case .sameMovementPattern: return 3
            case .sameEquipmentFamily: return 4
            }
        }
        return all.min { rank($0.type) < rank($1.type) }
    }
}
