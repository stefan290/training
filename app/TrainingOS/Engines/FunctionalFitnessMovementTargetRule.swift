import Foundation

/// Stage FF.P1: the single pure function resolving a concrete structural
/// movement target (reps or distance) for a Functional Fitness movement —
/// reused identically by `FunctionalFitnessMaterializer` (initial
/// resolution, once Stage D has resolved a real `Exercise`) and
/// `SubstituteFunctionalFitnessMovementUseCase` (recomputation after a
/// valid same-session substitution). There is exactly one semantic
/// source for this mapping; neither caller may keep its own table.
///
/// **Locked scope** (`FUNCTIONAL_FITNESS_PRESCRIPTION_DEPTH_DESIGN.md`'s
/// FF.P1 Design Lock + Numeric Dose Lock): only `.roundsForTime` receives
/// a target; every other real `WorkoutFormat` case degrades to no target,
/// unchanged from pre-FF.P1 behavior. Only the 3 real production-
/// reachable `MovementFunction`/`FunctionalModality` pairs are classified;
/// every other combination is NOT PRODUCTION REACHABLE and correctly
/// receives no target rather than a guessed rule. Calories and numeric
/// load are never populated by this rule — both stay exactly whatever
/// they already were. **This rule prescribes a repetition/distance COUNT
/// only — it does not encode, and must never be read as implying, any
/// load-selection semantic ("choose a weight that lets you complete
/// this") that TrainingOS has not defined; a 12-rep target with no
/// numeric load simply means TrainingOS prescribes 12 repetitions and
/// leaves numeric load genuinely unspecified.**
enum FunctionalFitnessMovementTargetRule {
    struct Target: Equatable {
        var reps: Int?
        var distanceMeters: Double?
    }

    /// Resolves this slot's concrete structural target given the ACTUAL
    /// resolved `Exercise` — required because the one real exception
    /// (Assault Bike) depends on the resolved `Exercise.equipment`, not
    /// merely the slot's own modality/movement-function classification.
    static func resolve(
        format: WorkoutFormat,
        modality: FunctionalModality?,
        movementFunctions: [MovementFunction],
        exercise: Exercise?
    ) -> Target {
        guard case .roundsForTime = format, let modality else { return Target(reps: nil, distanceMeters: nil) }

        if modality == .weightlifting, movementFunctions.contains(.squatLoaded) {
            return Target(reps: 12, distanceMeters: nil)
        }
        if modality == .gymnastics, movementFunctions.contains(.gymnasticsPull) {
            return Target(reps: 8, distanceMeters: nil)
        }
        if modality == .metabolicConditioning, movementFunctions.contains(.monostructural) {
            guard exercise?.equipment != "bike" else { return Target(reps: nil, distanceMeters: nil) }
            return Target(reps: nil, distanceMeters: 200)
        }
        return Target(reps: nil, distanceMeters: nil)
    }
}
