import Foundation
import SwiftData

/// Stage FF.M1 closure: the GOING FORWARD half of dynamically-composed
/// Functional Fitness's substitution model — the semantic sibling of
/// `SlotSelectionOverride`/`ActivitySelectionOverride`, keyed by
/// `MovementFunction` rather than a specific `ExerciseSlot`.
///
/// **Why not `SlotSelectionOverride`:** that type's "at most one row per
/// (programInstance, templateSlot)" invariant assumes a stable, reused
/// `ExerciseSlot` — true for Hypertrophy/Powerlifting and for authored
/// (`isDynamicallyComposed == false`) Functional Fitness content, but
/// false for dynamically-composed FF, where `FunctionalFitnessMaterializer`
/// builds a brand-new `ExerciseSlot` every tactical week (never reused —
/// this is Stage C's whole point, not a bug to route around). A
/// slot-identity-keyed override therefore can never match a future week's
/// freshly-created slot. The correct, semantically-honest key for "when
/// this movement role is programmed again, prefer this Exercise" is the
/// `MovementFunction` itself — exactly the shape
/// `ActivitySelectionOverride`'s own doc comment already establishes the
/// precedent for ("genuinely different template object types and
/// selection value types, not two views of the same fact" — a separate,
/// single-purpose type, not a nullable dual-key mega-entity).
///
/// **Key sufficiency:** `MovementFunction` alone is sufficient — FF.M1's
/// accepted movement space maps every function to exactly one
/// `FunctionalModality` 1:1 (`FunctionalFitnessMaterializer.modality(for:)`),
/// so a separate modality component in the key would be redundant.
/// Critically, this also means a preference created while substituting a
/// `.hingeLoaded` role is keyed distinctly from one created for
/// `.pressLoaded`, even when the same multi-function Exercise (e.g.
/// Dumbbell Snatch) satisfies both — no cross-role leakage.
///
/// **Instance-scoped, matching the established precedent exactly** (not
/// user-scoped): `SlotSelectionOverride`/`ActivitySelectionOverride` are
/// both `ProgramInstance`-scoped, cascade-deleted with the instance, and
/// do not carry forward to a new instance created by a phase transition —
/// this type follows the same, already-proven lifecycle rather than
/// inventing a new cross-instance persistence concept.
///
/// **Persists semantic preference only** — never a concrete reps/distance/
/// calories/load value. The preferred `Exercise` is re-resolved through
/// the normal `FunctionalFitnessMovementTargetRule` at each future
/// materialization, exactly like any other resolved Exercise.
///
/// **Only consulted for dynamically-composed FF** (`isDynamicallyComposed
/// == true`) — the authored path keeps its pre-existing
/// `SlotSelectionOverride`-based behavior entirely unchanged.
@Model
final class FunctionalFitnessMovementFunctionOverride {
    @Attribute(.unique) var id: UUID
    var programInstance: ProgramInstance?
    var movementFunction: MovementFunction
    /// Un-inversed, like `SlotSelectionOverride.selectedExercise` — the
    /// same documented, deferred risk (`DELETE_RULE_MATRIX.md`).
    var selectedExercise: Exercise?
    var reason: SubstitutionReason?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        movementFunction: MovementFunction,
        selectedExercise: Exercise?,
        reason: SubstitutionReason? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.movementFunction = movementFunction
        self.selectedExercise = selectedExercise
        self.reason = reason
        self.createdAt = createdAt
    }
}
