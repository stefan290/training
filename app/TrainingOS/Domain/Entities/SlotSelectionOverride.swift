import Foundation
import SwiftData

/// The **GOING FORWARD** half of Stage 4C's substitution model — the one
/// authoritative, `ProgramInstance`-scoped source of "which Exercise this
/// user has selected for this template slot from now on," consulted by
/// the materializer whenever it builds a *not-yet-materialized* future
/// `ExercisePrescription` for that slot.
///
/// **THIS SESSION ONLY substitution is deliberately not modeled here at
/// all.** It needs no new persisted type: it's a direct edit of an
/// *already-materialized* `ExercisePrescription.exercise`/
/// `.substitutionUsed`/`.substitutionReason` for one specific Session —
/// exactly the same shape Stage 3C's
/// `FunctionalFitnessPerformedMovement.performedExercise` already uses for
/// "performed something other than prescribed, without touching the
/// prescription." Two scopes, two different aggregate roots (a single
/// already-existing Session vs. all of a ProgramInstance's future
/// materialization), not one entity awkwardly covering both with a scope
/// flag. See `SUBSTITUTION_MODEL.md`.
///
/// At most one row exists per `(programInstance, templateSlot)` pair —
/// `SubstituteExerciseUseCase.substituteGoingForward` updates the existing
/// row in place rather than appending a second one, so there is exactly
/// one place a materializer ever needs to look (Stage 4C §41's "avoid
/// duplicate truth" requirement). This is instance-specific *state*, never
/// methodology — it must never cause `ProgramDefinition`/its template
/// graph to be mutated or re-versioned (§20, §43).
@Model
final class SlotSelectionOverride {
    @Attribute(.unique) var id: UUID
    var programInstance: ProgramInstance?
    /// Which slot in the (frozen, shared) template graph this override
    /// applies to. Unlike `Exercise`, `ExerciseSlot` rows are genuinely
    /// deleted in this codebase already (cascading from a
    /// `ProgramDefinition` deletion), so this reference — unlike the
    /// `Exercise`-typed ones elsewhere in this file — gets a real declared
    /// inverse (`ExerciseSlot.slotSelectionOverrides`) rather than
    /// inheriting the deferred-risk exception.
    var templateSlot: ExerciseSlot?
    /// Un-inversed, like `ExerciseSlot.allowedExercises` — the same
    /// documented, deferred risk (`DELETE_RULE_MATRIX.md`).
    var selectedExercise: Exercise?
    var reason: SubstitutionReason?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        selectedExercise: Exercise?,
        reason: SubstitutionReason? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.selectedExercise = selectedExercise
        self.reason = reason
        self.createdAt = createdAt
    }
}
