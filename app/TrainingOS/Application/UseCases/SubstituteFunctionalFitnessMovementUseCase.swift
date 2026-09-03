import Foundation
import SwiftData

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

    /// **GOING FORWARD, for dynamically-composed Functional Fitness only.**
    /// Writes (or updates in place — see
    /// `FunctionalFitnessMovementFunctionOverride`'s "at most one row per
    /// (instance, movementFunction)" invariant) the single authoritative
    /// Exercise preference future dynamic materialization will consult
    /// for this semantic movement role. `slot` is only used to validate
    /// the candidate (the currently-displayed movement's own
    /// `sourceExerciseSlot` — real `allowedMovementFunctions`/
    /// `allowedModalities` for this role); it is never itself persisted,
    /// since a future week's slot for the same function is a different
    /// object. Never touches `ProgramDefinition`/the template graph, and
    /// never rewrites any already-materialized Session — this only
    /// changes what a NOT-YET-materialized future week's Stage D
    /// prefers.
    @discardableResult
    static func substituteGoingForward(
        instance: ProgramInstance,
        movementFunction: MovementFunction,
        slot: ExerciseSlot,
        with exercise: Exercise,
        reason: SubstitutionReason? = nil,
        environment: TrainingEnvironment?,
        context: ModelContext
    ) throws -> FunctionalFitnessMovementFunctionOverride {
        guard SubstitutionValidator.isValid(candidate: exercise, for: slot, environment: environment) else {
            throw SubstitutionError.invalidForSlot
        }
        if let existing = instance.functionalFitnessMovementFunctionOverride(for: movementFunction) {
            existing.selectedExercise = exercise
            existing.reason = reason
            existing.createdAt = Date()
            return existing
        }
        let override = FunctionalFitnessMovementFunctionOverride(movementFunction: movementFunction, selectedExercise: exercise, reason: reason)
        context.insert(override)
        instance.addFunctionalFitnessMovementFunctionOverride(override)
        return override
    }
}
