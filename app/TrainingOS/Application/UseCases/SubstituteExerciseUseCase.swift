import Foundation
import SwiftData

enum SubstitutionError: Error, Equatable {
    /// The candidate `Exercise` doesn't satisfy the slot's
    /// `allowedExercises`/`allowedTargets` constraint (`SubstitutionValidator`).
    case invalidForSlot
}

/// The application-layer entry point for Stage 4C's two substitution
/// scopes (§18). Both scopes validate through the same
/// `SubstitutionValidator` — a substitution invalid for the slot is
/// rejected identically regardless of which scope requested it.
enum SubstituteExerciseUseCase {
    /// **THIS SESSION ONLY.** Directly edits an *already-materialized*
    /// `ExercisePrescription` — no new persisted row, no effect on any
    /// other Session, no effect on the `ProgramInstance`-level default.
    /// Future Sessions materialized for this slot are entirely unaffected
    /// (§18, proven by `SubstitutionRegressionTests`).
    @discardableResult
    static func substituteThisSessionOnly(
        prescription: ExercisePrescription,
        slot: ExerciseSlot,
        with exercise: Exercise,
        reason: SubstitutionReason? = nil
    ) throws -> ExercisePrescription {
        guard SubstitutionValidator.isValid(candidate: exercise, for: slot) else {
            throw SubstitutionError.invalidForSlot
        }
        prescription.exercise = exercise
        prescription.substitutionUsed = true
        prescription.substitutionReason = reason
        return prescription
    }

    /// **GOING FORWARD.** Writes (or updates in place — see
    /// `SlotSelectionOverride`'s "at most one row per pair" invariant) the
    /// single authoritative override future materialization for this
    /// `ProgramInstance`/slot pair will read. Never touches
    /// `ProgramDefinition`/the template graph (§20, §43) — this is
    /// instance-specific state only, and never rewrites any
    /// already-materialized Session (§30, §42).
    @discardableResult
    static func substituteGoingForward(
        instance: ProgramInstance,
        slot: ExerciseSlot,
        with exercise: Exercise,
        reason: SubstitutionReason? = nil,
        context: ModelContext
    ) throws -> SlotSelectionOverride {
        guard SubstitutionValidator.isValid(candidate: exercise, for: slot) else {
            throw SubstitutionError.invalidForSlot
        }
        if let existing = instance.slotSelectionOverride(for: slot) {
            existing.selectedExercise = exercise
            existing.reason = reason
            existing.createdAt = Date()
            return existing
        }
        let override = SlotSelectionOverride(selectedExercise: exercise, reason: reason)
        override.templateSlot = slot
        context.insert(override)
        instance.addSlotSelectionOverride(override)
        return override
    }

    /// What a materializer should call instead of reading
    /// `slot.resolvedExercise` directly — the GOING FORWARD override, if
    /// one exists for this instance/slot, always wins over the template's
    /// own default; the template default is the fallback, never mutated
    /// by the override's existence (§20, §21).
    static func resolvedExercise(for slot: ExerciseSlot, in instance: ProgramInstance) -> Exercise? {
        instance.slotSelectionOverride(for: slot)?.selectedExercise ?? slot.resolvedExercise
    }
}
