import Foundation
import SwiftData

/// The template-graph analogue of `FunctionalFitnessMovement` — one
/// movement requirement inside a `FunctionalFitnessPrescriptionTemplate`
/// (Stage 4D §8's "movement slot," e.g. "moderate-loaded squat/push")
/// paired with its own prescription target rule, mirroring how
/// `PrescriptionTemplate` wraps one `ExerciseSlot` plus strength-specific
/// rule fields for the strength system. `ExerciseSlot` itself stays
/// exactly as general-purpose as it already was — this type only adds
/// the Functional-Fitness-specific "how many reps/calories/etc." layer on
/// top.
@Model
final class FunctionalFitnessMovementSlotTemplate {
    @Attribute(.unique) var id: UUID
    var functionalFitnessPrescriptionTemplate: FunctionalFitnessPrescriptionTemplate?
    /// Stable position among a prescription template's movement slots
    /// (e.g. a triplet's 3 movements, in stated order), assigned by
    /// `FunctionalFitnessPrescriptionTemplate.addMovementSlot(_:)`.
    var sortIndex: Int

    /// Cascade: an `ExerciseSlot` has no independent meaning outside its
    /// owning template — same reasoning as `PrescriptionTemplate.exerciseSlot`.
    @Relationship(deleteRule: .cascade, inverse: \ExerciseSlot.owningFunctionalFitnessSlot)
    var exerciseSlot: ExerciseSlot?

    // MARK: - Prescription target (mirrors FunctionalFitnessMovement's
    // execution-side fields exactly — only the ones relevant to a given
    // movement are ever set, per §4's "do not introduce dummy values
    // where a dimension does not apply.")

    var reps: Int?
    var calories: Int?
    var distanceMeters: Double?
    var loadKilograms: Double?
    /// EMOM only — which minute (1-based) this movement rotates into.
    var minuteSlot: Int?
    /// How heavy this slot should be, independent of which Exercise ends
    /// up filling it (Stage 4D §3/§8's "loadingRole"). Informational for
    /// the generator/decision engine, not itself a hard substitution
    /// filter — see `ExerciseSlot.allowedTargets`/`.allowedMovementFunctions`
    /// for the actual filtering constraints.
    var loadingRole: LoadingClassification?
    /// Explicit rep-scheme sequence, e.g. `[21, 15, 9]` for Fran's
    /// descending ladder, or `[1, 2, 3, 4, 5]` for an ascending ladder
    /// (§18) — a typed array, never a parsed "21-15-9" string. `reps`
    /// above (when set) is this movement's flat total-volume figure at
    /// the execution layer (e.g. 45 = 21+15+9); this field is the
    /// methodology-level source of truth for the actual per-rung
    /// breakdown. Empty for any non-laddered format.
    var repScheme: [Int]

    init(
        id: UUID = UUID(),
        reps: Int? = nil,
        calories: Int? = nil,
        distanceMeters: Double? = nil,
        loadKilograms: Double? = nil,
        minuteSlot: Int? = nil,
        loadingRole: LoadingClassification? = nil,
        repScheme: [Int] = []
    ) {
        self.id = id
        self.sortIndex = 0
        self.reps = reps
        self.calories = calories
        self.distanceMeters = distanceMeters
        self.loadKilograms = loadKilograms
        self.minuteSlot = minuteSlot
        self.loadingRole = loadingRole
        self.repScheme = repScheme
    }

    /// The only way application code should attach this slot's
    /// `ExerciseSlot`. Mutates exactly one side; SwiftData maintains
    /// `slot.owningFunctionalFitnessSlot` from the declared inverse.
    func attachExerciseSlot(_ slot: ExerciseSlot) {
        exerciseSlot = slot
    }
}
