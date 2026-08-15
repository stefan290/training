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
    ///    first because it is the more specific constraint), OR
    /// 2. `allowedExercises` is empty and the candidate's `primaryTargets`
    ///    intersects `allowedTargets` — exactly what `ExerciseSlot`'s own
    ///    doc comment already promises ("empty means any Exercise matching
    ///    allowedTargets is eligible"). A candidate with no
    ///    `primaryTargets` at all never matches a target-constrained slot
    ///    — empty is "unmatchable," never "wildcard."
    /// 3. A slot with both `allowedExercises` and `allowedTargets` empty
    ///    is unconstrained — any candidate is valid (mirrors the existing
    ///    "empty means no explicit constraint" convention throughout this
    ///    codebase, e.g. `HypertrophyConfiguration`'s split fields).
    static func isValid(candidate: Exercise, for slot: ExerciseSlot) -> Bool {
        if !slot.allowedExercises.isEmpty {
            return slot.allowedExercises.contains { $0.id == candidate.id }
        }
        if slot.allowedTargets.isEmpty {
            return true
        }
        return !Set(candidate.primaryTargets).isDisjoint(with: Set(slot.allowedTargets))
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
