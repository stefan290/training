import Foundation

/// Stage FF.P1: the single pure function resolving a concrete structural
/// movement target (reps or distance) for a Functional Fitness movement —
/// reused identically by `FunctionalFitnessMaterializer` (initial
/// resolution, once Stage D has resolved a real `Exercise`) and
/// `SubstituteFunctionalFitnessMovementUseCase` (recomputation after a
/// valid same-session substitution). There is exactly one semantic
/// source for this mapping; neither caller may keep its own table.
///
/// **PROGRAMMING MODEL CORRECTION:** the original FF.P1 Design Lock gated
/// this entire rule on `format == .roundsForTime` — every other real
/// `WorkoutFormat` case degraded to no target at all. That gate was a
/// real domain/implementation bug, not a semantic requirement: every
/// value this rule returns (reps, distance, relative load guidance) is
/// already keyed ONLY on `modality`/`movementFunctions`/`exercise` — never
/// on `format` — so the gate was withholding a real, already-computed,
/// format-independent truth for no programming reason. A DB Squat does
/// not stop needing load guidance because it appears in an AMRAP,
/// interval, density block, or any other valid format. The `format`
/// parameter is now accepted but NOT consulted by this rule at all —
/// kept only so every call site's existing signature stays unchanged;
/// prescription semantics derive from movement + exercise identity, full
/// stop, and `FunctionalFitnessPhaseBiasPolicy`/the materializer choose
/// `WorkoutFormat` from the completed programmed content, never the
/// reverse. Only the 3 real production-reachable `MovementFunction`/
/// `FunctionalModality` pairs are classified;
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
        /// MUSCLE + 5FF FINAL CLOSURE, Section 9 (project-owner decision):
        /// a genuine, separate SUSTAINED_AEROBIC target dimension — "Run
        /// for 30 min at intended sustainable intensity" — never a fixed
        /// distance standing in for a long, continuous-effort stimulus.
        /// Populated instead of (never alongside) `distanceMeters` for a
        /// monostructural/distance-capable movement whose real
        /// `DurationDomain` is `.long` — see `resolve`'s own doc comment
        /// for exactly why `.short`/`.medium` are unaffected.
        var durationSeconds: Int? = nil
        /// Dogfood Round 1 — Final Close (Finding 3D): a real, authored
        /// RELATIVE load/intensity prescription for a loaded movement —
        /// `nil` for every non-loaded (gymnastics/monostructural) target,
        /// and for a loaded movement this rule doesn't cover (never
        /// invented for the "not production reachable" default case
        /// either). Locked PRODUCT VALUES, exactly like the reps table
        /// below — never a %1RM formula (CLAUDE.md rule 10; no validated
        /// one exists — see `FunctionalFitnessLoadGuidance`'s own doc
        /// comment).
        var loadGuidance: FunctionalFitnessLoadGuidance? = nil
    }

    /// MUSCLE + 5FF FINAL CLOSURE, Section 9 (project-owner decision):
    /// "Run for 30 min at intended sustainable intensity" — the order's
    /// own cited example, and the exact literal locked value used below.
    /// A real, separate SUSTAINED_AEROBIC duration target, never a
    /// %-of-something formula (CLAUDE.md rule 10; no validated formula
    /// exists) and never derived from the block's own `WorkoutFormat` cap
    /// (this rule's own doc comment: prescription semantics never derive
    /// from `format`).
    static let sustainedAerobicDurationSeconds = 1800

    /// Resolves this slot's concrete structural target given the ACTUAL
    /// resolved `Exercise` — required because the one real exception
    /// (Assault Bike) depends on the resolved `Exercise.equipment`, not
    /// merely the slot's own modality/movement-function classification.
    ///
    /// MUSCLE + 5FF FINAL CLOSURE, Section 9 (project-owner decision):
    /// `targetDurationDomain` is a NEW, required parameter — the real,
    /// previously-missing input this rule needed to stop conflating
    /// "SHORT_HIGH_OUTPUT: cover 200m as fast as possible" (a genuine,
    /// already-correct fixed-quantity stimulus) with "SUSTAINED_AEROBIC:
    /// hold an easy pace for a long continuous effort" (which a fixed
    /// 200m never truthfully represents, regardless of the block's own
    /// format/cap — the exact confirmed "For Time cap 20min / Easy Run
    /// 200m" defect). Consulted ONLY for the monostructural/distance
    /// branch below — every other branch's dosing already derives purely
    /// from movement+exercise identity (this rule's own established
    /// discipline) and is completely unaffected.
    static func resolve(
        format: WorkoutFormat,
        modality: FunctionalModality?,
        movementFunctions: [MovementFunction],
        exercise: Exercise?,
        targetDurationDomain: DurationDomain
    ) -> Target {
        // `format` is intentionally unused below — see this type's own
        // doc comment for why prescription semantics must never derive
        // from WorkoutFormat.
        guard let modality else { return Target(reps: nil, distanceMeters: nil) }

        if modality == .weightlifting, movementFunctions.contains(.squatLoaded) {
            // Stage FF.M1 / Dogfood Round 1 (Finding 3D): a squatLoaded
            // slot can resolve to Back Squat (barbell, genuinely heavier
            // relative to a metcon rep scheme) or Wall Ball/Thruster (both
            // squat+press expressions, lighter/moderate in this rep
            // range) — the SAME per-exercise-name distinction the
          // hinge/press branches below already make, applied here too so
            // this branch is never a single flat guess across exercises
            // that legitimately differ.
            switch exercise?.canonicalName {
            case "Wall Ball":
                return Target(reps: 12, distanceMeters: nil, loadGuidance: FunctionalFitnessLoadGuidance(
                    tier: .light, targetReserveRepsOpeningRound: 4, sustainableUnbrokenIntent: true
                ))
            case "Thruster":
                return Target(reps: 12, distanceMeters: nil, loadGuidance: FunctionalFitnessLoadGuidance(
                    tier: .moderate, targetReserveRepsOpeningRound: 3, sustainableUnbrokenIntent: false
                ))
            default:
                return Target(reps: 12, distanceMeters: nil, loadGuidance: FunctionalFitnessLoadGuidance(
                    tier: .moderate, targetReserveRepsOpeningRound: 3, sustainableUnbrokenIntent: true
                ))
            }
        }
        if modality == .gymnastics, movementFunctions.contains(.gymnasticsPull) {
            return Target(reps: 8, distanceMeters: nil)
        }
        // DOGFOOD — FIX ORDER 1, Section C: `exercise?.equipment ==
        // "bike"` (Assault Bike) is the one real monostructural exercise
        // with NO authored, locked quantity — 200m is a real locked
        // PRODUCT VALUE for Row Erg/SkiErg/running-pattern locomotion,
        // never validated or authorized for a bike, so falling through
        // to it for bike would be exactly the "arbitrary bike constant"
        // (200 metres, named explicitly) the project lead's fix order
        // forbids inventing. This rule still honestly reports "no target"
        // for bike-equipment monostructural work — the real fix is that
        // exercise SELECTION (`MovementRoleExerciseSelector`, via
        // `hasExecutableTarget` below) now excludes any candidate this
        // rule cannot truthfully dose, so an Assault Bike is never
        // actually CHOSEN for a monostructural role in the first place
        // when any other real candidate (Row Erg/SkiErg/Easy Run/Track
        // Interval Run) is eligible. This branch keeps reporting the
        // honest empty result rather than being removed, because the
        // underlying fact ("no authored bike quantity exists") is still
        // true and must remain discoverable by `hasExecutableTarget` and
        // the materialization invariant (Section D) as a real defense-in-
        // depth backstop, not merely relied upon via selection alone.
        //
        // FUNCTIONAL FITNESS PROGRAMMING AUTHORITY V2, Section 10/11/12
        // (real generalization of the above, closing the disclosed
        // "Double-Unders · 200m" defect the same way — not an added
        // Double-Unders-name special case): the prior gate keyed
        // literally on `exercise?.equipment == "bike"`, a hardcoded
        // string. The REAL domain boundary this rule should have
        // consulted all along is `Exercise.measuredDimensions` — the
        // exact field built for "which dimensions this exercise
        // supports" (Section 10). 200 metres is a real locked PRODUCT
        // VALUE for a monostructural exercise that actually declares
        // `.distance` support (Row Erg/SkiErg/Easy Run/Track Interval
        // Run, all tagged `[.distance, ...]` in the catalog) — it is
        // never truthful for one that doesn't (Assault Bike, tagged
        // `[.calories, .duration]`; Double-Unders, tagged `[.reps]`).
        // Neither exception name appears here any more: any exercise
        // failing this declared-dimension check falls through to the
        // same honest empty target, discoverable by the same
        // `hasExecutableTarget`/materialization-invariant backstops.
        if modality == .metabolicConditioning, movementFunctions.contains(.monostructural) {
            guard let exercise, exercise.measuredDimensions.contains(.distance) else {
                return Target(reps: nil, distanceMeters: nil)
            }
            // MUSCLE + 5FF FINAL CLOSURE, Section 9 (project-owner
            // decision): `.long` (SUSTAINED_AEROBIC-shaped, >15 min) work
            // is duration-based — "Run for 30 min," never a fixed 200m
            // standing in for a long continuous effort, regardless of
            // the block's own format/cap. `.short`/`.medium` are
            // completely unchanged — this is exactly the real, pre-
            // existing, already-shipped `aerobicEngine`-family pairing
            // (a fixed short/medium interval-repeat distance) this
            // checkpoint must not disturb; only the genuinely new `.long`
            // case gets the new duration dimension.
            if targetDurationDomain == .long {
                return Target(reps: nil, distanceMeters: nil, durationSeconds: sustainedAerobicDurationSeconds)
            }
            return Target(reps: nil, distanceMeters: 200)
        }
        // Stage FF.M1: per-Exercise branches, keyed on `canonicalName`
        // exactly like the Assault Bike exception above — these pools
        // each span too wide an honest rep range for one shared
        // family-level target (FF.M1 Numeric Dose Lock). Locked PRODUCT
        // VALUES, not exercise-science formulas. Dogfood Round 1 (Finding
        // 3D) extends this same locked-value discipline one column
        // further: a real, authored RELATIVE load/intensity guidance per
        // exercise, never a numeric formula.
        if modality == .weightlifting, movementFunctions.contains(.hingeLoaded) {
            switch exercise?.canonicalName {
            case "Kettlebell Swing":
                return Target(reps: 15, distanceMeters: nil, loadGuidance: FunctionalFitnessLoadGuidance(
                    tier: .light, targetReserveRepsOpeningRound: 5, sustainableUnbrokenIntent: true
                ))
            case "Deadlift":
                return Target(reps: 8, distanceMeters: nil, loadGuidance: FunctionalFitnessLoadGuidance(
                    tier: .heavy, targetReserveRepsOpeningRound: 3, sustainableUnbrokenIntent: false
                ))
            // hingeLoaded-context branch — structurally distinct from the
            // pressLoaded-context branch below even though both currently
            // resolve to 10 reps; a future dose change to one must never
            // silently affect the other.
            case "Dumbbell Snatch":
                return Target(reps: 10, distanceMeters: nil, loadGuidance: FunctionalFitnessLoadGuidance(
                    tier: .moderate, targetReserveRepsOpeningRound: 4, sustainableUnbrokenIntent: true
                ))
            default: return Target(reps: nil, distanceMeters: nil)
            }
        }
        if modality == .weightlifting, movementFunctions.contains(.pressLoaded) {
            switch exercise?.canonicalName {
            case "Wall Ball":
                return Target(reps: 15, distanceMeters: nil, loadGuidance: FunctionalFitnessLoadGuidance(
                    tier: .light, targetReserveRepsOpeningRound: 4, sustainableUnbrokenIntent: true
                ))
            case "Thruster":
                return Target(reps: 8, distanceMeters: nil, loadGuidance: FunctionalFitnessLoadGuidance(
                    tier: .heavy, targetReserveRepsOpeningRound: 2, sustainableUnbrokenIntent: false
                ))
            // pressLoaded-context branch — structurally distinct from the
            // hingeLoaded-context branch above.
            case "Dumbbell Snatch":
                return Target(reps: 10, distanceMeters: nil, loadGuidance: FunctionalFitnessLoadGuidance(
                    tier: .moderate, targetReserveRepsOpeningRound: 4, sustainableUnbrokenIntent: true
                ))
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

    /// DOGFOOD — FIX ORDER 1, Section C: whether a candidate `Exercise`
    /// would receive ANY real, executable target from `resolve` above —
    /// not only the bike case, but every other genuinely-empty outcome
    /// this rule already produces (e.g. an unrecognized `canonicalName`
    /// under the hinge/press per-exercise branches). `MovementRoleExerciseSelector`
    /// uses this to exclude a candidate this rule cannot truthfully dose
    /// BEFORE it is ever chosen for a role, rather than discovering the
    /// gap only after persistence. `format` is passed a fixed placeholder
    /// because `resolve` never consults it (see this type's own doc
    /// comment) — never interpreted as a real format here.
    static func hasExecutableTarget(modality: FunctionalModality?, movementFunctions: [MovementFunction], exercise: Exercise?, targetDurationDomain: DurationDomain) -> Bool {
        let target = resolve(format: .maxLoad, modality: modality, movementFunctions: movementFunctions, exercise: exercise, targetDurationDomain: targetDurationDomain)
        return target.reps != nil || target.distanceMeters != nil || target.durationSeconds != nil || target.loadGuidance != nil
    }
}
