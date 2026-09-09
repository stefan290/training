import Foundation
import SwiftData

/// The canonical exercise catalog this app resolves/substitutes against.
/// Originally a 38-exercise placeholder ("just enough distinct movements
/// to exercise every block type"); the Exercise Library V1 checkpoint
/// expanded it to a credible V1 library (58 exercises) covering common
/// Full Gym / Home Gym / minimal-equipment movement families for
/// Hypertrophy, Strength, and Functional Fitness — still V1-complete,
/// deliberately not encyclopedic (no full CrossFit movement library, no
/// exhaustive machine catalog).
///
/// **Stage 4E addition:** a small curated Functional Fitness set (§35) —
/// enough monostructural/gymnastics/weightlifting examples to prove
/// `FunctionalFitnessProgramGenerator`'s movement-slot resolution across
/// single-modality, couplet, triplet and benchmark shapes, tagged with
/// the new `Exercise.movementFunctions`/`.functionalModality` fields.
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
    // Exercise Library V1 additions (see `resolveOrInsert`'s own
    // in-context comments for the concrete gap each one closes).
    let flatDumbbellBenchPress: Exercise
    let dumbbellChestFly: Exercise
    let singleArmDumbbellRow: Exercise
    let gobletSquat: Exercise
    let singleLegRomanianDeadlift: Exercise
    let nordicHamstringCurl: Exercise
    let barbellHipThrust: Exercise
    let gluteBridge: Exercise
    let standingDumbbellCalfRaise: Exercise
    let dumbbellBicepCurl: Exercise
    let hammerCurl: Exercise
    let dumbbellOverheadTricepsExtension: Exercise
    let benchDip: Exercise
    let bentOverReverseFly: Exercise
    let dumbbellShoulderPress: Exercise
    let sumoDeadlift: Exercise
    let chestToBarPullUp: Exercise
    let doubleUnders: Exercise
    let farmersCarry: Exercise
    let boxJump: Exercise

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
            requiredEquipment: [EquipmentRequirement] = [],
            isExplosiveExpression: Bool = false
        ) -> Exercise {
            if let existing = try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.canonicalName == name })).first {
                return existing
            }
            let exercise = Exercise(
                canonicalName: name, modality: modality, equipment: equipment, movementPattern: pattern,
                primaryTargets: primaryTargets, movementFunctions: movementFunctions, functionalModality: functionalModality,
                requiredEquipment: requiredEquipment, isExplosiveExpression: isExplosiveExpression
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
            movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning,
            requiredEquipment: []
        )
        let trackIntervalRun = make(
            "Track Interval Run", .conditioning, "none", "locomotion",
            movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning,
            requiredEquipment: []
        )
        let wallBall = make(
            "Wall Ball", .functionalFitness, "medicineBall", "squatToPress",
            primaryTargets: [.quadriceps, .shoulders], movementFunctions: [.squatLoaded, .pressLoaded], functionalModality: .weightlifting,
            requiredEquipment: [.medicineBall], isExplosiveExpression: true
        )
        let burpee = make(
            "Burpee", .functionalFitness, "bodyweight", "fullBody",
            movementFunctions: [.other], functionalModality: .gymnastics,
            requiredEquipment: [.bodyweight]
        )
        // Exercise Library V1: `.isExplosiveExpression` on these three —
        // and Dumbbell Snatch below — is genuine domain metadata (all
        // four ARE ballistic/power movements where speed is the point),
        // not something invented merely to satisfy a slot. See
        // `Exercise.isExplosiveExpression`'s own doc comment for why
        // `movementFunctions`/`primaryTargets` alone cannot carry this
        // distinction (a Dumbbell Snatch is legitimately `.hingeLoaded`
        // too).
        let kettlebellSwing = make(
            "Kettlebell Swing", .functionalFitness, "kettlebell", "hipHinge",
            primaryTargets: [.glutes, .hamstrings], movementFunctions: [.hingeLoaded], functionalModality: .weightlifting,
            requiredEquipment: [.kettlebell], isExplosiveExpression: true
        )
        let thruster = make(
            "Thruster", .functionalFitness, "barbell", "squatToPress",
            primaryTargets: [.quadriceps, .shoulders], movementFunctions: [.squatLoaded, .pressLoaded], functionalModality: .weightlifting,
            requiredEquipment: [.barbell], isExplosiveExpression: true
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
            requiredEquipment: [.dumbbells], isExplosiveExpression: true
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
        // Source Authority Repair (4-Day Full Body): both real, source-
        // approved names (SOURCE_PROGRAM_MANIFEST.md §5's Abs/Traps
        // category rows) — added only because the 4-Day workbook's real
        // per-day slots require them, exactly the "exact source-slot
        // requirements" exception to leaving Exercise Library untouched.
        let hangingKneeRaise = make(
            "Hanging Knee Raise", .hypertrophy, "bodyweight", "coreFlexion",
            primaryTargets: [.core],
            requiredEquipment: [.pullUpBar]
        )
        let barbellShrug = make(
            "Barbell Shrug", .hypertrophy, "barbell", "shrug",
            primaryTargets: [.back],
            requiredEquipment: [.barbell]
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

        // Exercise Library V1: a real, intentional expansion beyond the
        // 38-exercise placeholder — every addition below fills a
        // concrete, previously-missing movement family/equipment
        // combination (never mechanically generated), prioritized
        // Hypertrophy > Strength > Functional Fitness > common
        // conditioning per this checkpoint's own locked scope.

        // Hypertrophy — Home Gym / dumbbell-equipped alternatives for
        // families that previously only had a barbell/machine/cable
        // option, closing the exact "no real substitute" gap the
        // preceding V1 completion review found live.
        let flatDumbbellBenchPress = make(
            "Flat Dumbbell Bench Press", .hypertrophy, "dumbbell", "horizontalPush",
            primaryTargets: [.chest, .triceps], movementFunctions: [.pressLoaded],
            requiredEquipment: [.dumbbells, .bench]
        )
        let dumbbellChestFly = make(
            "Dumbbell Chest Fly", .hypertrophy, "dumbbell", "chestFly",
            primaryTargets: [.chest],
            requiredEquipment: [.dumbbells, .bench]
        )
        let singleArmDumbbellRow = make(
            "Single-Arm Dumbbell Row", .hypertrophy, "dumbbell", "horizontalPull",
            primaryTargets: [.back, .biceps], movementFunctions: [.horizontalPullLoaded],
            requiredEquipment: [.dumbbells, .bench]
        )
        // Goblet Squat is tagged both `.hypertrophy` (a real chest/quad-
        // slot-eligible squat alternative) AND `functionalModality:
        // .weightlifting` (a real FF squatLoaded movement) — a single,
        // honestly-dual-purpose entry, never two separate fabricated rows
        // for the same real movement.
        let gobletSquat = make(
            "Goblet Squat", .hypertrophy, "dumbbell", "squat",
            primaryTargets: [.quadriceps, .glutes], movementFunctions: [.squatLoaded], functionalModality: .weightlifting,
            requiredEquipment: [.dumbbells]
        )
        let singleLegRomanianDeadlift = make(
            "Single-Leg Romanian Deadlift", .hypertrophy, "dumbbell", "hinge",
            primaryTargets: [.hamstrings, .glutes], movementFunctions: [.hingeLoaded],
            requiredEquipment: [.dumbbells]
        )
        let nordicHamstringCurl = make(
            "Nordic Hamstring Curl", .hypertrophy, "bodyweight", "kneeFlexion",
            primaryTargets: [.hamstrings], movementFunctions: [.kneeFlexionLoaded],
            requiredEquipment: [.bodyweight]
        )
        let barbellHipThrust = make(
            "Barbell Hip Thrust", .hypertrophy, "barbell", "hipExtension",
            primaryTargets: [.glutes, .hamstrings], movementFunctions: [.hingeLoaded],
            requiredEquipment: [.barbell, .bench]
        )
        let gluteBridge = make(
            "Bodyweight Glute Bridge", .hypertrophy, "bodyweight", "hipExtension",
            primaryTargets: [.glutes],
            requiredEquipment: [.bodyweight]
        )
        let standingDumbbellCalfRaise = make(
            "Standing Dumbbell Calf Raise", .hypertrophy, "dumbbell", "ankleExtension",
            primaryTargets: [.calves],
            requiredEquipment: [.dumbbells]
        )
        let dumbbellBicepCurl = make(
            "Dumbbell Bicep Curl", .hypertrophy, "dumbbell", "elbowFlexion",
            primaryTargets: [.biceps],
            requiredEquipment: [.dumbbells]
        )
        let hammerCurl = make(
            "Hammer Curl", .hypertrophy, "dumbbell", "elbowFlexion",
            primaryTargets: [.biceps, .forearms],
            requiredEquipment: [.dumbbells]
        )
        let dumbbellOverheadTricepsExtension = make(
            "Dumbbell Overhead Triceps Extension", .hypertrophy, "dumbbell", "elbowExtension",
            primaryTargets: [.triceps],
            requiredEquipment: [.dumbbells]
        )
        let benchDip = make(
            "Bench Dip", .hypertrophy, "bodyweight", "elbowExtension",
            primaryTargets: [.triceps, .chest],
            requiredEquipment: [.bodyweight, .bench]
        )
        let bentOverReverseFly = make(
            "Bent-Over Dumbbell Reverse Fly", .hypertrophy, "dumbbell", "rearDeltFly",
            primaryTargets: [.shoulders, .rearDelt],
            requiredEquipment: [.dumbbells]
        )
        let dumbbellShoulderPress = make(
            "Dumbbell Shoulder Press", .hypertrophy, "dumbbell", "verticalPush",
            primaryTargets: [.shoulders, .triceps], movementFunctions: [.verticalPushLoaded],
            requiredEquipment: [.dumbbells]
        )

        // Strength — real frequency/variety within the same Squat/Bench/
        // Deadlift target families the Powerlifting source programs use;
        // never a new slot/category, only a real additional candidate.
        let sumoDeadlift = make(
            "Sumo Deadlift", .strength, "barbell", "hinge",
            primaryTargets: [.hamstrings, .glutes, .back], movementFunctions: [.hingeLoaded],
            requiredEquipment: [.barbell]
        )

        // Functional Fitness — real content within the EXISTING, locked
        // movement-function space (squatLoaded/hingeLoaded/pressLoaded/
        // gymnasticsPull/gymnasticsPush/monostructural), plus `.carry`/
        // `.jumping` (both already-existing cases with almost no real
        // catalog content before this checkpoint).
        let chestToBarPullUp = make(
            "Chest-to-Bar Pull-up", .functionalFitness, "bodyweight", "verticalPull",
            primaryTargets: [.back, .biceps], movementFunctions: [.gymnasticsPull, .verticalPullLoaded], functionalModality: .gymnastics,
            requiredEquipment: [.pullUpBar]
        )
        let doubleUnders = make(
            "Double-Unders", .functionalFitness, "bodyweight", "jumpRope",
            movementFunctions: [.jumping, .monostructural], functionalModality: .metabolicConditioning,
            requiredEquipment: [.bodyweight]
        )
        let farmersCarry = make(
            "Farmer's Carry", .functionalFitness, "dumbbell", "carry",
            primaryTargets: [.forearms, .core], movementFunctions: [.carry], functionalModality: .weightlifting,
            requiredEquipment: [.dumbbells]
        )
        let boxJump = make(
            "Box Jump", .functionalFitness, "bodyweight", "jump",
            primaryTargets: [.quadriceps, .glutes], movementFunctions: [.jumping], functionalModality: .gymnastics,
            requiredEquipment: [.bodyweight]
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
            stiffLeggedDeadlift: stiffLeggedDeadlift,
            flatDumbbellBenchPress: flatDumbbellBenchPress,
            dumbbellChestFly: dumbbellChestFly,
            singleArmDumbbellRow: singleArmDumbbellRow,
            gobletSquat: gobletSquat,
            singleLegRomanianDeadlift: singleLegRomanianDeadlift,
            nordicHamstringCurl: nordicHamstringCurl,
            barbellHipThrust: barbellHipThrust,
            gluteBridge: gluteBridge,
            standingDumbbellCalfRaise: standingDumbbellCalfRaise,
            dumbbellBicepCurl: dumbbellBicepCurl,
            hammerCurl: hammerCurl,
            dumbbellOverheadTricepsExtension: dumbbellOverheadTricepsExtension,
            benchDip: benchDip,
            bentOverReverseFly: bentOverReverseFly,
            dumbbellShoulderPress: dumbbellShoulderPress,
            sumoDeadlift: sumoDeadlift,
            chestToBarPullUp: chestToBarPullUp,
            doubleUnders: doubleUnders,
            farmersCarry: farmersCarry,
            boxJump: boxJump
        )
    }
}
