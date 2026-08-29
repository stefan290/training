import Foundation
import SwiftData

/// The small canonical exercise set the seeded dev dataset exercises
/// against. Not a real exercise library — just enough distinct movements
/// to exercise every block type without reusing one exercise for
/// everything.
///
/// **Stage 4E addition:** a small curated Functional Fitness set (§35) —
/// enough monostructural/gymnastics/weightlifting examples to prove
/// `FunctionalFitnessProgramGenerator`'s movement-slot resolution across
/// single-modality, couplet, triplet and benchmark shapes, tagged with
/// the new `Exercise.movementFunctions`/`.functionalModality` fields.
/// Deliberately not a full CrossFit movement library.
struct ExerciseCatalog {
    let benchPress: Exercise
    let backSquat: Exercise
    let inclineDumbbellPress: Exercise
    let easyRun: Exercise
    let trackIntervalRun: Exercise
    let wallBall: Exercise
    let burpee: Exercise
    let kettlebellSwing: Exercise
    let thruster: Exercise
    let pullUp: Exercise
    // Stage 4E additions.
    let bike: Exercise
    let row: Exercise
    let skiErg: Exercise
    let toesToBar: Exercise
    let pushUp: Exercise
    let handstandPushUp: Exercise
    let deadlift: Exercise
    let dumbbellSnatch: Exercise
    // Stage 6C additions — the realistic multi-exercise Lower A acceptance
    // fixture (STAGE6C_ACCEPTANCE_REPORT.md).
    let romanianDeadlift: Exercise
    let legPress: Exercise
    let bulgarianSplitSquat: Exercise
    let legCurl: Exercise
    let calfRaise: Exercise
    // Stage 6D additions — a real slot-valid alternative for every Lower A
    // exercise, not just the one Stage 6C added (STAGE6D §3: substitution
    // must work for a realistic acceptance fixture, not one slot only).
    let frontSquat: Exercise
    let conventionalDeadlift: Exercise
    let seatedLegCurl: Exercise
    let seatedCalfRaise: Exercise
    // Stage 10B additions — the 3-Day Full Body Hypertrophy reference
    // program's accessory tier (biceps/triceps) had no isolation
    // candidate anywhere in this catalog; D-10B-6 also asks for a
    // lateral-delt/shoulder accessory candidate even though no Day A/B/C
    // slot in this reference config isolates shoulders alone (see
    // `STAGE10B_IMPLEMENTATION_REPORT.md`). `barbellRow` closes a second,
    // independently-discovered gap: every existing `.back`-tagged
    // exercise in this catalog (Deadlift, Pull-up) is `.functionalFitness`
    // modality, outside the strength candidate pool `SeedAnnualPlanJourney`
    // supplies — leaving Day A/B/C's "Back" solo slot with no eligible
    // candidate at all (confirmed by direct resolution trace, not
    // assumption).
    let barbellCurl: Exercise
    let cableTricepsPushdown: Exercise
    let dumbbellLateralRaise: Exercise
    let barbellRow: Exercise
    // Stage 10C.1 additions — the exercise-catalog/movement-family
    // foundation for 4/5-Day Hypertrophy V2 (STAGE10C1_EXERCISE_CATALOG_AUDIT.md).
    // `overheadPress`/`legExtension`/`cableChestFly`/`facePull`/`latPulldown`
    // fill real, previously-nonexistent movement families (vertical
    // push, quadriceps isolation, chest isolation, rear delt, loaded
    // vertical pull); `seatedCableRow` is the approved second
    // horizontal-pull option alongside `barbellRow`.
    let overheadPress: Exercise
    let legExtension: Exercise
    let cableChestFly: Exercise
    let facePull: Exercise
    let latPulldown: Exercise
    let seatedCableRow: Exercise
    // Stage 10R.1 Slice 1A addition — recovered directly from the real
    // "3 day full body_Novice.xlsx" workbook's `Hamstrings_Hip_Hinge`
    // category table (`SOURCE_PROGRAM_MANIFEST.md` §5): the ONLY
    // catalog gap found while resolving the recovered Mesocycle-1
    // structure — no existing exercise (Romanian/Conventional Deadlift)
    // is a literal source-approved option for this specific category,
    // which is deliberately distinct from the "Glutes" category that
    // plain "Deadlift" belongs to.
    let stiffLeggedDeadlift: Exercise

    /// Stage 10R.7A-TX rename (was `makeAndInsert`) — the old name implied
    /// "always construct fresh objects," which is exactly the behavior
    /// that corrupted `Exercise` rows under repeated resolution
    /// (`STAGE10R7A_TX_ROOT_CAUSE_REPORT.md`). The real domain semantics
    /// are "resolve the canonical catalog into this context" — for a
    /// given store, repeated calls must resolve to the SAME persisted
    /// canonical `Exercise` identity for the same `canonicalName`, never
    /// construct a second colliding row and rely on the `@Attribute(.unique)`
    /// conflict-merge to paper over it.
    static func resolveOrInsert(context: ModelContext) -> ExerciseCatalog {
        func make(
            _ name: String, _ modality: TrainingModality, _ equipment: String, _ pattern: String,
            primaryTargets: [MuscleGroup] = [],
            movementFunctions: [MovementFunction] = [],
            functionalModality: FunctionalModality? = nil,
            requiredEquipment: [EquipmentRequirement] = []
        ) -> Exercise {
            if let existing = try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.canonicalName == name })).first {
                return existing
            }
            let exercise = Exercise(
                canonicalName: name, modality: modality, equipment: equipment, movementPattern: pattern,
                primaryTargets: primaryTargets, movementFunctions: movementFunctions, functionalModality: functionalModality,
                requiredEquipment: requiredEquipment
            )
            context.insert(exercise)
            return exercise
        }
        /// Aliases aren't the identity key (`canonicalName` is) and carry
        /// no uniqueness constraint, but attaching the same alias twice on
        /// a second resolution against an already-populated store would
        /// still silently accumulate duplicate `ExerciseAlias` rows — not
        /// a corruption risk, just not actually idempotent. Skip any
        /// `sourceName` already attached to this exercise.
        func addAliasIfMissing(_ sourceName: String, confidence: Double, to exercise: Exercise) {
            guard !exercise.aliases.contains(where: { $0.sourceName == sourceName }) else { return }
            let alias = ExerciseAlias(sourceName: sourceName, confidence: confidence)
            context.insert(alias)
            exercise.addAlias(alias)
        }

        // Stage 10B (Blocker 2): `.pressLoaded` distinguishes a genuine
        // loaded press from an isolation shoulder/chest movement (e.g.
        // Dumbbell Lateral Raise) that happens to share a target muscle
        // group with a "Horizontal Push" slot — see
        // `HypertrophyProgramGenerator.movementPatternGroupings`.
        let benchPress = make(
            "Barbell Bench Press", .hypertrophy, "barbell", "horizontalPush",
            primaryTargets: [.chest, .triceps], movementFunctions: [.pressLoaded],
            requiredEquipment: [.barbell, .rack, .bench]
        )
        let inclineDumbbellPress = make(
            "Incline Dumbbell Press", .hypertrophy, "dumbbell", "horizontalPush",
            primaryTargets: [.chest, .triceps], movementFunctions: [.pressLoaded],
            requiredEquipment: [.dumbbells, .bench]
        )

        // Demonstrates the alias/mapping shape (handoff section 10) without
        // an import pipeline: several source spellings resolve to one
        // canonical exercise.
        for aliasName in ["DB Incline Press", "Incline DB Press", "Incline Dumbbell Bench"] {
            addAliasIfMissing(aliasName, confidence: 0.94, to: inclineDumbbellPress)
        }

        let backSquat = make(
            "Back Squat", .strength, "barbell", "squat",
            primaryTargets: [.quadriceps, .glutes], movementFunctions: [.squatLoaded], functionalModality: .weightlifting,
            requiredEquipment: [.barbell, .rack]
        )
        let easyRun = make(
            "Easy Run (Zone 2)", .conditioning, "none", "locomotion",
            movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning
        )
        let trackIntervalRun = make(
            "Track Interval Run", .conditioning, "none", "locomotion",
            movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning
        )
        let wallBall = make(
            "Wall Ball", .functionalFitness, "medicineBall", "squatToPress",
            primaryTargets: [.quadriceps, .shoulders], movementFunctions: [.squatLoaded, .pressLoaded], functionalModality: .weightlifting,
            requiredEquipment: [.medicineBall]
        )
        let burpee = make(
            "Burpee", .functionalFitness, "bodyweight", "fullBody",
            movementFunctions: [.other], functionalModality: .gymnastics,
            requiredEquipment: [.bodyweight]
        )
        let kettlebellSwing = make(
            "Kettlebell Swing", .functionalFitness, "kettlebell", "hipHinge",
            primaryTargets: [.glutes, .hamstrings], movementFunctions: [.hingeLoaded], functionalModality: .weightlifting,
            requiredEquipment: [.kettlebell]
        )
        let thruster = make(
            "Thruster", .functionalFitness, "barbell", "squatToPress",
            primaryTargets: [.quadriceps, .shoulders], movementFunctions: [.squatLoaded, .pressLoaded], functionalModality: .weightlifting,
            requiredEquipment: [.barbell]
        )
        // Stage 10C.1: `.verticalPullLoaded` added alongside the
        // existing `.gymnasticsPull` (never replacing it) — Pull-up is
        // now also a real Hypertrophy V2 vertical-pull candidate
        // (D-10C1-1), while its Functional Fitness usage is completely
        // unaffected.
        let pullUp = make(
            "Pull-up", .functionalFitness, "bodyweight", "verticalPull",
            primaryTargets: [.back, .biceps], movementFunctions: [.gymnasticsPull, .verticalPullLoaded], functionalModality: .gymnastics,
            requiredEquipment: [.pullUpBar]
        )

        // Monostructural.
        let bike = make(
            "Assault Bike", .functionalFitness, "bike", "locomotion",
            movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning,
            requiredEquipment: [.bike]
        )
        let row = make(
            "Row Erg", .functionalFitness, "rower", "locomotion",
            movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning,
            requiredEquipment: [.rower]
        )
        let skiErg = make(
            "SkiErg", .functionalFitness, "skiErg", "locomotion",
            movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning,
            requiredEquipment: [.skiErg]
        )

        // Gymnastics.
        let toesToBar = make(
            "Toes-to-Bar", .functionalFitness, "bodyweight", "coreFlexion",
            primaryTargets: [.core], movementFunctions: [.gymnasticsPull, .trunk], functionalModality: .gymnastics,
            requiredEquipment: [.pullUpBar]
        )
        let pushUp = make(
            "Push-up", .functionalFitness, "bodyweight", "horizontalPush",
            primaryTargets: [.chest, .triceps], movementFunctions: [.gymnasticsPush], functionalModality: .gymnastics,
            requiredEquipment: [.bodyweight]
        )
        let handstandPushUp = make(
            "Handstand Push-up", .functionalFitness, "bodyweight", "verticalPush",
            primaryTargets: [.shoulders, .triceps], movementFunctions: [.gymnasticsPush], functionalModality: .gymnastics,
            requiredEquipment: [.bodyweight]
        )

        // Weightlifting.
        let deadlift = make(
            "Deadlift", .functionalFitness, "barbell", "hinge",
            primaryTargets: [.back, .hamstrings, .glutes], movementFunctions: [.hingeLoaded], functionalModality: .weightlifting,
            requiredEquipment: [.barbell]
        )
        let dumbbellSnatch = make(
            "Dumbbell Snatch", .functionalFitness, "dumbbell", "hingeToPress",
            primaryTargets: [.shoulders, .glutes], movementFunctions: [.hingeLoaded, .pressLoaded], functionalModality: .weightlifting,
            requiredEquipment: [.dumbbells]
        )

        // Stage 6C additions — realistic Lower A acceptance fixture.
        // Stage 10B (Blocker 2) adds `.hingeLoaded`/`.squatLoaded` to
        // these — genuine domain metadata (a Romanian Deadlift IS a hinge
        // movement, a Leg Press/Bulgarian Split Squat IS a squat-pattern
        // movement), not something invented merely to satisfy a slot; see
        // `HypertrophyProgramGenerator.movementPatternGroupings`.
        let romanianDeadlift = make(
            "Romanian Deadlift", .strength, "barbell", "hinge",
            primaryTargets: [.hamstrings, .glutes], movementFunctions: [.hingeLoaded],
            requiredEquipment: [.barbell]
        )
        let legPress = make(
            "Leg Press", .strength, "machine", "squat",
            primaryTargets: [.quadriceps, .glutes], movementFunctions: [.squatLoaded],
            requiredEquipment: [.machine]
        )
        let bulgarianSplitSquat = make(
            "Bulgarian Split Squat", .strength, "dumbbell", "squat",
            primaryTargets: [.quadriceps, .glutes], movementFunctions: [.squatLoaded],
            requiredEquipment: [.dumbbells, .bench]
        )
        // Stage 10R.1 Slice 1A: `.kneeFlexionLoaded` added additively —
        // see `MovementFunction`'s own doc comment for the exact
        // Hamstrings-Isolation-vs-hip-hinge collision this closes.
        let legCurl = make(
            "Leg Curl", .strength, "machine", "kneeFlexion",
            primaryTargets: [.hamstrings], movementFunctions: [.kneeFlexionLoaded],
            requiredEquipment: [.machine]
        )
        let calfRaise = make(
            "Calf Raise", .strength, "machine", "ankleExtension",
            primaryTargets: [.calves],
            requiredEquipment: [.machine]
        )

        // Stage 6D additions — real slot-valid alternatives. Same Stage
        // 10B movement-function tagging reasoning as above.
        let frontSquat = make(
            "Front Squat", .strength, "barbell", "squat",
            primaryTargets: [.quadriceps, .glutes], movementFunctions: [.squatLoaded],
            requiredEquipment: [.barbell, .rack]
        )
        let conventionalDeadlift = make(
            "Conventional Deadlift", .strength, "barbell", "hinge",
            primaryTargets: [.hamstrings, .glutes], movementFunctions: [.hingeLoaded],
            requiredEquipment: [.barbell]
        )
        let seatedLegCurl = make(
            "Seated Leg Curl", .strength, "machine", "kneeFlexion",
            primaryTargets: [.hamstrings],
            requiredEquipment: [.machine]
        )
        let seatedCalfRaise = make(
            "Seated Calf Raise", .strength, "machine", "ankleExtension",
            primaryTargets: [.calves],
            requiredEquipment: [.machine]
        )

        // Stage 10B additions.
        let barbellCurl = make(
            "Barbell Curl", .hypertrophy, "barbell", "elbowFlexion",
            primaryTargets: [.biceps],
            requiredEquipment: [.barbell]
        )
        let cableTricepsPushdown = make(
            "Cable Triceps Pushdown", .hypertrophy, "cable", "elbowExtension",
            primaryTargets: [.triceps],
            requiredEquipment: [.cableStation]
        )
        // Stage 10C.1: `.lateralDelt` added alongside the existing
        // generic `.shoulders` (never replacing it) — see `MuscleGroup`'s
        // own doc comment.
        let dumbbellLateralRaise = make(
            "Dumbbell Lateral Raise", .hypertrophy, "dumbbell", "shoulderAbduction",
            primaryTargets: [.shoulders, .lateralDelt],
            requiredEquipment: [.dumbbells]
        )
        // Stage 10C.1: `.horizontalPullLoaded` added — this template's
        // `movementFunctions` was previously empty (matched only via
        // `primaryTargets`); now distinguishable from vertical pull (see
        // `MovementFunction`'s own doc comment).
        let barbellRow = make(
            "Barbell Row", .hypertrophy, "barbell", "horizontalPull",
            primaryTargets: [.back, .biceps], movementFunctions: [.horizontalPullLoaded],
            requiredEquipment: [.barbell]
        )

        // Stage 10C.1 additions (STAGE10C1_EXERCISE_CATALOG_AUDIT.md §8) —
        // fills the vertical-push, quadriceps-isolation, chest-isolation,
        // rear-delt and loaded-vertical-pull gaps the audit found, plus
        // the approved second horizontal-pull option. `.verticalPushLoaded`
        // (not `.pressLoaded`) is deliberate — see `MovementFunction`'s
        // own doc comment for the exact collision this avoids.
        let overheadPress = make(
            "Barbell Overhead Press", .hypertrophy, "barbell", "verticalPush",
            primaryTargets: [.shoulders, .triceps], movementFunctions: [.verticalPushLoaded],
            requiredEquipment: [.barbell, .rack]
        )
        let legExtension = make(
            "Leg Extension", .strength, "machine", "kneeExtension",
            primaryTargets: [.quadriceps],
            requiredEquipment: [.machine]
        )
        let cableChestFly = make(
            "Cable Chest Fly", .hypertrophy, "cable", "chestFly",
            primaryTargets: [.chest],
            requiredEquipment: [.cableStation]
        )
        // `.rearDelt` added alongside generic `.shoulders` — see
        // `MuscleGroup`'s own doc comment; the model still cannot
        // distinguish this from `.lateralDelt` any further than these
        // two explicit tags (flagged as a known limit, not solved
        // further here).
        let facePull = make(
            "Face Pull", .hypertrophy, "cable", "facePull",
            primaryTargets: [.shoulders, .rearDelt],
            requiredEquipment: [.cableStation]
        )
        let latPulldown = make(
            "Lat Pulldown", .hypertrophy, "cable", "verticalPull",
            primaryTargets: [.back, .biceps], movementFunctions: [.verticalPullLoaded],
            requiredEquipment: [.cableStation]
        )
        let seatedCableRow = make(
            "Seated Cable Row", .hypertrophy, "cable", "horizontalPull",
            primaryTargets: [.back, .biceps], movementFunctions: [.horizontalPullLoaded],
            requiredEquipment: [.cableStation]
        )

        // Stage 10R.1 Slice 1A addition (see the stored property's own
        // doc comment above).
        let stiffLeggedDeadlift = make(
            "Stiff-Legged Deadlift", .hypertrophy, "barbell", "hinge",
            primaryTargets: [.hamstrings, .glutes], movementFunctions: [.hingeLoaded],
            requiredEquipment: [.barbell]
        )

        return ExerciseCatalog(
            benchPress: benchPress,
            backSquat: backSquat,
            inclineDumbbellPress: inclineDumbbellPress,
            easyRun: easyRun,
            trackIntervalRun: trackIntervalRun,
            wallBall: wallBall,
            burpee: burpee,
            kettlebellSwing: kettlebellSwing,
            thruster: thruster,
            pullUp: pullUp,
            bike: bike,
            row: row,
            skiErg: skiErg,
            toesToBar: toesToBar,
            pushUp: pushUp,
            handstandPushUp: handstandPushUp,
            deadlift: deadlift,
            dumbbellSnatch: dumbbellSnatch,
            romanianDeadlift: romanianDeadlift,
            legPress: legPress,
            bulgarianSplitSquat: bulgarianSplitSquat,
            legCurl: legCurl,
            calfRaise: calfRaise,
            frontSquat: frontSquat,
            conventionalDeadlift: conventionalDeadlift,
            seatedLegCurl: seatedLegCurl,
            seatedCalfRaise: seatedCalfRaise,
            barbellCurl: barbellCurl,
            cableTricepsPushdown: cableTricepsPushdown,
            dumbbellLateralRaise: dumbbellLateralRaise,
            barbellRow: barbellRow,
            overheadPress: overheadPress,
            legExtension: legExtension,
            cableChestFly: cableChestFly,
            facePull: facePull,
            latPulldown: latPulldown,
            seatedCableRow: seatedCableRow,
            stiffLeggedDeadlift: stiffLeggedDeadlift
        )
    }
}
