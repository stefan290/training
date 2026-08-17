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

    static func makeAndInsert(context: ModelContext) -> ExerciseCatalog {
        func make(
            _ name: String, _ modality: TrainingModality, _ equipment: String, _ pattern: String,
            primaryTargets: [MuscleGroup] = [],
            movementFunctions: [MovementFunction] = [],
            functionalModality: FunctionalModality? = nil
        ) -> Exercise {
            let exercise = Exercise(
                canonicalName: name, modality: modality, equipment: equipment, movementPattern: pattern,
                primaryTargets: primaryTargets, movementFunctions: movementFunctions, functionalModality: functionalModality
            )
            context.insert(exercise)
            return exercise
        }

        let benchPress = make("Barbell Bench Press", .hypertrophy, "barbell", "horizontalPush", primaryTargets: [.chest, .triceps])
        let inclineDumbbellPress = make("Incline Dumbbell Press", .hypertrophy, "dumbbell", "horizontalPush", primaryTargets: [.chest, .triceps])

        // Demonstrates the alias/mapping shape (handoff section 10) without
        // an import pipeline: several source spellings resolve to one
        // canonical exercise.
        for aliasName in ["DB Incline Press", "Incline DB Press", "Incline Dumbbell Bench"] {
            let alias = ExerciseAlias(sourceName: aliasName, confidence: 0.94)
            context.insert(alias)
            inclineDumbbellPress.addAlias(alias)
        }

        let backSquat = make(
            "Back Squat", .strength, "barbell", "squat",
            primaryTargets: [.quadriceps, .glutes], movementFunctions: [.squatLoaded], functionalModality: .weightlifting
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
            primaryTargets: [.quadriceps, .shoulders], movementFunctions: [.squatLoaded, .pressLoaded], functionalModality: .weightlifting
        )
        let burpee = make(
            "Burpee", .functionalFitness, "bodyweight", "fullBody",
            movementFunctions: [.other], functionalModality: .gymnastics
        )
        let kettlebellSwing = make(
            "Kettlebell Swing", .functionalFitness, "kettlebell", "hipHinge",
            primaryTargets: [.glutes, .hamstrings], movementFunctions: [.hingeLoaded], functionalModality: .weightlifting
        )
        let thruster = make(
            "Thruster", .functionalFitness, "barbell", "squatToPress",
            primaryTargets: [.quadriceps, .shoulders], movementFunctions: [.squatLoaded, .pressLoaded], functionalModality: .weightlifting
        )
        let pullUp = make(
            "Pull-up", .functionalFitness, "bodyweight", "verticalPull",
            primaryTargets: [.back, .biceps], movementFunctions: [.gymnasticsPull], functionalModality: .gymnastics
        )

        // Monostructural.
        let bike = make(
            "Assault Bike", .functionalFitness, "bike", "locomotion",
            movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning
        )
        let row = make(
            "Row Erg", .functionalFitness, "rower", "locomotion",
            movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning
        )
        let skiErg = make(
            "SkiErg", .functionalFitness, "skiErg", "locomotion",
            movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning
        )

        // Gymnastics.
        let toesToBar = make(
            "Toes-to-Bar", .functionalFitness, "bodyweight", "coreFlexion",
            primaryTargets: [.core], movementFunctions: [.gymnasticsPull, .trunk], functionalModality: .gymnastics
        )
        let pushUp = make(
            "Push-up", .functionalFitness, "bodyweight", "horizontalPush",
            primaryTargets: [.chest, .triceps], movementFunctions: [.gymnasticsPush], functionalModality: .gymnastics
        )
        let handstandPushUp = make(
            "Handstand Push-up", .functionalFitness, "bodyweight", "verticalPush",
            primaryTargets: [.shoulders, .triceps], movementFunctions: [.gymnasticsPush], functionalModality: .gymnastics
        )

        // Weightlifting.
        let deadlift = make(
            "Deadlift", .functionalFitness, "barbell", "hinge",
            primaryTargets: [.back, .hamstrings, .glutes], movementFunctions: [.hingeLoaded], functionalModality: .weightlifting
        )
        let dumbbellSnatch = make(
            "Dumbbell Snatch", .functionalFitness, "dumbbell", "hingeToPress",
            primaryTargets: [.shoulders, .glutes], movementFunctions: [.hingeLoaded, .pressLoaded], functionalModality: .weightlifting
        )

        // Stage 6C additions — realistic Lower A acceptance fixture.
        let romanianDeadlift = make(
            "Romanian Deadlift", .strength, "barbell", "hinge",
            primaryTargets: [.hamstrings, .glutes]
        )
        let legPress = make(
            "Leg Press", .strength, "machine", "squat",
            primaryTargets: [.quadriceps, .glutes]
        )
        let bulgarianSplitSquat = make(
            "Bulgarian Split Squat", .strength, "dumbbell", "squat",
            primaryTargets: [.quadriceps, .glutes]
        )
        let legCurl = make(
            "Leg Curl", .strength, "machine", "kneeFlexion",
            primaryTargets: [.hamstrings]
        )
        let calfRaise = make(
            "Calf Raise", .strength, "machine", "ankleExtension",
            primaryTargets: [.calves]
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
            calfRaise: calfRaise
        )
    }
}
