import Foundation

/// Stage 8B: the Functional Fitness sibling of
/// `SubstituteExerciseUseCase.substituteThisSessionOnly` — mechanical
/// reuse of the exact established Stage 6B pattern (add a
/// `sourceExerciseSlot` back-reference, validate through the same
/// `SubstitutionValidator`), not a new mutation mechanism or new
/// training-science policy. Confirmed by the Stage 8B Functional Fitness
/// audit: Level 3 substitution follows mechanically from existing
/// architecture once this one additive field exists.
enum SubstituteFunctionalFitnessMovementUseCase {
    /// **THIS SESSION ONLY.** Directly edits an already-materialized
    /// `FunctionalFitnessMovement` — no new persisted row, no effect on
    /// any other Session, no effect on the `ProgramInstance`-level
    /// default. Only valid when `movement.sourceExerciseSlot` is set (a
    /// movement materialized outside the slot-based pipeline has nothing
    /// to validate the candidate against).
    @discardableResult
    static func substituteThisSessionOnly(
        movement: FunctionalFitnessMovement,
        with exercise: Exercise,
        reason: SubstitutionReason? = nil
    ) throws -> FunctionalFitnessMovement {
        guard let slot = movement.sourceExerciseSlot else {
            throw SubstitutionError.invalidForSlot
        }
        guard SubstitutionValidator.isValid(candidate: exercise, for: slot) else {
            throw SubstitutionError.invalidForSlot
        }
        movement.exercise = exercise
        movement.substitutionUsed = true
        movement.substitutionReason = reason
        return movement
    }
}
