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
        reason: SubstitutionReason? = nil,
        environment: TrainingEnvironment?
    ) throws -> FunctionalFitnessMovement {
        guard let slot = movement.sourceExerciseSlot else {
            throw SubstitutionError.invalidForSlot
        }
        guard SubstitutionValidator.isValid(candidate: exercise, for: slot, environment: environment) else {
            throw SubstitutionError.invalidForSlot
        }
        movement.exercise = exercise
        movement.substitutionUsed = true
        movement.substitutionReason = reason

        // Stage FF.P1: keep the concrete structural target consistent
        // with the newly substituted Exercise — e.g. a distance target
        // resolved for a Row Erg must not silently survive a
        // substitution to an Assault Bike (both share the same
        // `.metabolicConditioning`/`.monostructural` slot classification,
        // so `SubstitutionValidator` alone cannot catch this). Recomputed
        // via the exact same `FunctionalFitnessMovementTargetRule.resolve`
        // materialization itself calls — never a second table.
        //
        // Precedence: only ever overwrites a target this movement's own
        // OWNING TEMPLATE never explicitly authored. The real generator
        // never sets `reps`/`distanceMeters` on
        // `FunctionalFitnessMovementSlotTemplate` for generated content
        // (`FUNCTIONAL_FITNESS_PRESCRIPTION_DEPTH_DESIGN.md`), so a nil
        // template field is the reliable signal that THIS movement's
        // current value was itself FF.P1-generated at materialization
        // time (not authored) — safe to recompute. A non-nil template
        // field means the value is explicitly authored (hand-authored/
        // seed/benchmark content) and is never touched here.
        if let template = slot.owningFunctionalFitnessSlot, let format = template.functionalFitnessPrescriptionTemplate?.format {
            let target = FunctionalFitnessMovementTargetRule.resolve(
                format: format, modality: slot.allowedModalities.first,
                movementFunctions: slot.allowedMovementFunctions, exercise: exercise
            )
            if template.reps == nil { movement.reps = target.reps }
            if template.distanceMeters == nil { movement.distanceMeters = target.distanceMeters }
        }

        return movement
    }
}
