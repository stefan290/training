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
        // Stage FF.M1: per-Exercise branches, keyed on `canonicalName`
        // exactly like the Assault Bike exception above — these pools
        // each span too wide an honest rep range for one shared
        // family-level target (FF.M1 Numeric Dose Lock). Locked PRODUCT
        // VALUES, not exercise-science formulas.
        if modality == .weightlifting, movementFunctions.contains(.hingeLoaded) {
            switch exercise?.canonicalName {
            case "Kettlebell Swing": return Target(reps: 15, distanceMeters: nil)
            case "Deadlift": return Target(reps: 8, distanceMeters: nil)
            // hingeLoaded-context branch — structurally distinct from the
            // pressLoaded-context branch below even though both currently
            // resolve to 10 reps; a future dose change to one must never
            // silently affect the other.
            case "Dumbbell Snatch": return Target(reps: 10, distanceMeters: nil)
            default: return Target(reps: nil, distanceMeters: nil)
            }
        }
        if modality == .weightlifting, movementFunctions.contains(.pressLoaded) {
            switch exercise?.canonicalName {
            case "Wall Ball": return Target(reps: 15, distanceMeters: nil)
            case "Thruster": return Target(reps: 8, distanceMeters: nil)
            // pressLoaded-context branch — structurally distinct from the
            // hingeLoaded-context branch above.
            case "Dumbbell Snatch": return Target(reps: 10, distanceMeters: nil)
            default: return Target(reps: nil, distanceMeters: nil)
            }
        }
        if modality == .gymnastics, movementFunctions.contains(.gymnasticsPush) {
            switch exercise?.canonicalName {
            case "Push-up": return Target(reps: 15, distanceMeters: nil)
            case "Handstand Push-up": return Target(reps: 5, distanceMeters: nil)
            default: return Target(reps: nil, distanceMeters: nil)
            }
        }
        return Target(reps: nil, distanceMeters: nil)
    }
}
