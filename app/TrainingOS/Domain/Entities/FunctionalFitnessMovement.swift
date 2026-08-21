import Foundation
import SwiftData

/// One prescribed movement inside a `FunctionalFitnessPrescription` — the
/// Functional Fitness equivalent of `ExercisePrescription`, but for a block
/// whose format (AMRAP/EMOM/For Time/etc.) requires several movements
/// combined, each with its own target shape (reps, calories, distance, or
/// load — only the ones that apply to that movement).
///
/// `minuteSlot` exists specifically for EMOM: which minute (1-based) this
/// movement rotates into, e.g. Stage 3B's 3-station EMOM 12 example
/// (`FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md` §3, Example 2). `nil` for
/// every other format.
@Model
final class FunctionalFitnessMovement {
    @Attribute(.unique) var id: UUID
    var functionalFitnessPrescription: FunctionalFitnessPrescription?
    var exercise: Exercise?
    /// Stable position among a prescription's movements, assigned by
    /// `FunctionalFitnessPrescription.addMovement(_:)`.
    var sortIndex: Int

    var reps: Int?
    var calories: Int?
    var distanceMeters: Double?
    var loadKilograms: Double?
    var minuteSlot: Int?

    /// Stage 8B addition, mirroring `ExercisePrescription.substitutionUsed`/
    /// `.substitutionReason` exactly: whether the user (or the readiness
    /// adaptation flow, on the user's behalf) substituted a different
    /// exercise than prescribed, and why.
    var substitutionUsed: Bool
    /// Stage 8B addition, mirroring `ExercisePrescription.sourceExerciseSlot`
    /// exactly (its own Stage 6B doc comment explains the reasoning in
    /// full): the `ExerciseSlot` this movement was materialized from, when
    /// known — lets `SubstituteFunctionalFitnessMovementUseCase` validate a
    /// same-session substitution through the same `SubstitutionValidator`
    /// every other slot-based substitution already uses. `nil` for a
    /// movement created outside the slot-based materializer path (an ad
    /// hoc/seed-authored movement) — substitution stays unavailable for
    /// those rather than inventing an unconstrained substitution (CLAUDE.md
    /// rule 10). The delete rule lives on
    /// `ExerciseSlot.materializedFunctionalFitnessMovements` — this is a
    /// plain inverse property.
    var sourceExerciseSlot: ExerciseSlot?
    var substitutionReason: SubstitutionReason?

    /// Nothing in application code reads this — it exists purely so
    /// `FunctionalFitnessPerformedMovement.prescribedMovement` has a real
    /// inverse to nullify against on delete (an un-inversed to-one
    /// reference to a `@Model` type does not nullify cleanly; see
    /// `DELETE_RULE_MATRIX.md`'s "One-directional references" section for
    /// the Stage 2 precedent this follows).
    @Relationship(deleteRule: .nullify, inverse: \FunctionalFitnessPerformedMovement.prescribedMovement)
    var performedAttempts: [FunctionalFitnessPerformedMovement] = []

    /// Stage 8B addition: `ReadinessAdaptationDecision
    /// .functionalFitnessMovement`'s required inverse — nothing reads this
    /// collection. Same established fix as `ExercisePrescription
    /// .readinessAdaptationDecisions`.
    @Relationship(deleteRule: .nullify, inverse: \ReadinessAdaptationDecision.functionalFitnessMovement)
    var readinessAdaptationDecisions: [ReadinessAdaptationDecision] = []

    init(
        id: UUID = UUID(),
        exercise: Exercise? = nil,
        reps: Int? = nil,
        calories: Int? = nil,
        distanceMeters: Double? = nil,
        loadKilograms: Double? = nil,
        minuteSlot: Int? = nil,
        substitutionUsed: Bool = false,
        substitutionReason: SubstitutionReason? = nil
    ) {
        self.id = id
        self.exercise = exercise
        self.sortIndex = 0
        self.reps = reps
        self.calories = calories
        self.distanceMeters = distanceMeters
        self.loadKilograms = loadKilograms
        self.minuteSlot = minuteSlot
        self.substitutionUsed = substitutionUsed
        self.substitutionReason = substitutionReason
    }
}
