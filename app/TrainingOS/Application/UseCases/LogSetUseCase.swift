import Foundation
import SwiftData

/// Stage 6B: the orchestrating use case behind every logged strength
/// set — wraps the existing, pure `RecordSetResultUseCase` and saves
/// immediately, one call per meaningful action
/// (`WORKOUT_COMPLETION_PIPELINE.md` §1, `STAGE6A_DECISION_MEMO.md` §1d).
/// This is the only entry point `STRENGTH_EXECUTION_FLOW.md`'s set
/// logging UI should call — never `RecordSetResultUseCase` directly.
enum LogSetUseCase {
    @discardableResult
    static func logSet(
        setIndex: Int,
        weight: Double,
        reps: Int,
        targetRir: Int?,
        actualRir: Int?,
        prBand: String?,
        scoringDirection: ScoringDirection,
        context resultContext: ResultContext,
        setPrescription: SetPrescription?,
        exercisePrescription: ExercisePrescription,
        exercise: Exercise,
        performanceProfile: PerformanceProfile,
        completedAt: Date,
        modelContext: ModelContext
    ) throws -> (result: SetResult, isFirstEverEntry: Bool) {
        let outcome = RecordSetResultUseCase.recordSet(
            setIndex: setIndex, weight: weight, reps: reps, targetRir: targetRir, actualRir: actualRir,
            prBand: prBand, scoringDirection: scoringDirection, context: resultContext,
            setPrescription: setPrescription, exercisePrescription: exercisePrescription, exercise: exercise,
            performanceProfile: performanceProfile, completedAt: completedAt, modelContext: modelContext
        )
        try modelContext.save()
        return outcome
    }
}
