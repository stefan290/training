import Foundation
import SwiftData

/// Stage 9B: a small, curated warm-up/preparation catalog — enough
/// distinct movements to prove the architecture across horizontal
/// pressing, overhead pressing, squat, hinge, pulling, unilateral lower
/// body, jumping/plyometric, mixed functional fitness, and general
/// activation, per the approved Stage 9 scope. Deliberately not hundreds
/// of movements — quality over quantity. Minimal/no equipment by default;
/// no elaborate rehabilitation content.
///
/// Some rows link to an already-existing `Exercise` (`WarmupMovement
/// .exercise`) rather than duplicating its targets, per Stage 9 decision
/// D-W2 — only when a real overlap exists in the current
/// `ExerciseCatalog`. Pure mobility drills with no `Exercise` equivalent
/// own their tags directly.
enum WarmupCatalog {
    @discardableResult
    static func makeAndInsert(exerciseCatalog: ExerciseCatalog, context: ModelContext) -> [WarmupMovement] {
        func make(
            _ name: String,
            exercise: Exercise? = nil,
            targetMuscleGroups: [MuscleGroup] = [],
            emphasis: [PreparationEmphasis],
            instructionText: String,
            durationSeconds: Int? = nil,
            reps: Int? = nil,
            hasSides: Bool = false,
            requiresEquipment: Bool = false
        ) -> WarmupMovement {
            let movement = WarmupMovement(
                name: name, exercise: exercise, targetMuscleGroups: targetMuscleGroups,
                emphasis: emphasis, instructionText: instructionText,
                defaultDurationSeconds: durationSeconds, defaultReps: reps,
                hasSides: hasSides, requiresEquipment: requiresEquipment
            )
            context.insert(movement)
            return movement
        }

        var movements: [WarmupMovement] = []

        // Overhead / horizontal pressing preparation.
        movements.append(make(
            "Arm Circles", targetMuscleGroups: [.shoulders], emphasis: [.overheadShoulderMobility, .generalActivation],
            instructionText: "Small to large circles, both directions.", durationSeconds: 30
        ))
        movements.append(make(
            "Band Pull-Apart", targetMuscleGroups: [.shoulders, .back], emphasis: [.overheadShoulderMobility],
            instructionText: "Hold a light band at chest height, pull apart squeezing shoulder blades together.",
            reps: 12, requiresEquipment: true
        ))
        movements.append(make(
            "Scapular Wall Slide", targetMuscleGroups: [.shoulders, .back], emphasis: [.overheadShoulderMobility],
            instructionText: "Back against a wall, slide arms overhead keeping contact.", reps: 10
        ))
        movements.append(make(
            "Push-up", exercise: exerciseCatalog.pushUp, emphasis: [.generalActivation],
            instructionText: "Slow, controlled push-ups to prime the pressing pattern.", reps: 8
        ))
        movements.append(make(
            "Cat-Cow", targetMuscleGroups: [.core], emphasis: [.thoracicMobility],
            instructionText: "On hands and knees, alternate arching and rounding the spine.", durationSeconds: 30
        ))
        movements.append(make(
            "Inchworm to Push-up", targetMuscleGroups: [.hamstrings, .chest, .core],
            emphasis: [.generalActivation, .thoracicMobility],
            instructionText: "Walk hands out to a push-up, do one, walk back to standing.", reps: 5
        ))

        // Squat / lower-body preparation.
        movements.append(make(
            "Bodyweight Squat", targetMuscleGroups: [.quadriceps, .glutes],
            emphasis: [.hipMobility, .ankleMobility],
            instructionText: "Slow, controlled squats through a comfortable range of motion.", reps: 10
        ))
        movements.append(make(
            "Ankle Rocks", targetMuscleGroups: [.calves], emphasis: [.ankleMobility],
            instructionText: "Knee over toes rocking motion against a wall or unsupported, each side.",
            reps: 10, hasSides: true
        ))
        movements.append(make(
            "World's Greatest Stretch", targetMuscleGroups: [.hamstrings, .glutes],
            emphasis: [.hipMobility, .thoracicMobility],
            instructionText: "Lunge forward, rotate toward the front leg reaching upward, each side.",
            reps: 5, hasSides: true
        ))
        movements.append(make(
            "Leg Swings", targetMuscleGroups: [.hamstrings, .glutes, .quadriceps], emphasis: [.hipMobility],
            instructionText: "Controlled front-to-back and side-to-side leg swings, each side.",
            reps: 10, hasSides: true
        ))

        // Hinge preparation.
        movements.append(make(
            "Glute Bridge", targetMuscleGroups: [.glutes, .hamstrings], emphasis: [.hipMobility],
            instructionText: "Lying on back, drive hips up squeezing glutes at the top.", reps: 12
        ))
        movements.append(make(
            "Single-Leg RDL Reach (Bodyweight)", targetMuscleGroups: [.hamstrings, .glutes],
            emphasis: [.hipMobility, .unilateralStability],
            instructionText: "Hinge at the hip on one leg, reaching toward the floor, each side.",
            reps: 8, hasSides: true
        ))

        // Pulling / unilateral / plyometric preparation.
        movements.append(make(
            "Single-Leg Balance Reach", targetMuscleGroups: [.quadriceps, .glutes], emphasis: [.unilateralStability],
            instructionText: "Balance on one leg, reach the free foot forward and to the side, each side.",
            reps: 5, hasSides: true
        ))
        movements.append(make(
            "Pogo Hops", targetMuscleGroups: [.calves, .quadriceps], emphasis: [.plyometricReadiness, .ankleMobility],
            instructionText: "Small, quick, low-amplitude hops off the balls of the feet.", durationSeconds: 20
        ))
        movements.append(make(
            "Dead Bug", targetMuscleGroups: [.core], emphasis: [.generalActivation],
            instructionText: "Lying on back, extend opposite arm and leg while keeping the low back flat, each side.",
            reps: 8, hasSides: true
        ))

        // General activation fallback (minimal specific target — safe to
        // include broadly, per D-W3's fallback-tier requirement).
        movements.append(make(
            "Marching in Place", emphasis: [.generalActivation],
            instructionText: "Easy march in place, gradually raising the knees.", durationSeconds: 30
        ))

        return movements
    }
}
