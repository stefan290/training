import Foundation
import SwiftData

/// The small canonical exercise set the seeded dev dataset exercises
/// against. Not a real exercise library — just enough distinct movements
/// to exercise every block type without reusing one exercise for
/// everything.
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
    let fran: Exercise

    static func makeAndInsert(context: ModelContext) -> ExerciseCatalog {
        func make(_ name: String, _ modality: TrainingModality, _ equipment: String, _ pattern: String) -> Exercise {
            let exercise = Exercise(canonicalName: name, modality: modality, equipment: equipment, movementPattern: pattern)
            context.insert(exercise)
            return exercise
        }

        let benchPress = make("Barbell Bench Press", .hypertrophy, "barbell", "horizontalPush")
        let inclineDumbbellPress = make("Incline Dumbbell Press", .hypertrophy, "dumbbell", "horizontalPush")

        // Demonstrates the alias/mapping shape (handoff section 10) without
        // an import pipeline: several source spellings resolve to one
        // canonical exercise.
        for aliasName in ["DB Incline Press", "Incline DB Press", "Incline Dumbbell Bench"] {
            let alias = ExerciseAlias(sourceName: aliasName, confidence: 0.94)
            context.insert(alias)
            inclineDumbbellPress.addAlias(alias)
        }

        let backSquat = make("Back Squat", .strength, "barbell", "squat")
        let easyRun = make("Easy Run (Zone 2)", .conditioning, "none", "locomotion")
        let trackIntervalRun = make("Track Interval Run", .conditioning, "none", "locomotion")
        let wallBall = make("Wall Ball", .functionalFitness, "medicineBall", "squatToPress")
        let burpee = make("Burpee", .functionalFitness, "bodyweight", "fullBody")
        let kettlebellSwing = make("Kettlebell Swing", .functionalFitness, "kettlebell", "hipHinge")
        let thruster = make("Thruster", .functionalFitness, "barbell", "squatToPress")
        let pullUp = make("Pull-up", .functionalFitness, "bodyweight", "verticalPull")

        // "Fran" is modelled as a canonical Exercise so it can carry a
        // PersonalRecord like any other movement — see Exercise.swift for
        // why a dedicated Benchmark entity was deferred.
        let fran = make("Fran", .functionalFitness, "barbell+bodyweight", "benchmark")

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
            fran: fran
        )
    }
}
