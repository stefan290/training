import Foundation
import SwiftData

/// Attaches a block-level result (AMRAP, EMOM, For Time, steady state,
/// intervals) to its WorkoutBlock and, when the block has a scoreable
/// benchmark identity, folds the score into permanent history exactly like
/// a set result does. `benchmarkExercise` and `prCandidateValue` are nil
/// for blocks that aren't PR-eligible (a plain Zone 2 run, a warmup).
///
/// Every relationship below is established from exactly one side, via the
/// owning model's `addX`/`attachX` method — never by setting both sides
/// manually. See CLAUDE.md and DELETE_RULE_MATRIX.md.
enum RecordWorkoutResultUseCase {
    @discardableResult
    static func recordResult(
        _ result: WorkoutResult,
        for workoutBlock: WorkoutBlock,
        benchmarkExercise: Exercise?,
        prCandidateValue: Double?,
        performanceProfile: PerformanceProfile?,
        modelContext: ModelContext
    ) -> WorkoutResult {
        modelContext.insert(result)
        workoutBlock.attachResult(result)

        guard
            let benchmarkExercise,
            let prCandidateValue,
            let performanceProfile,
            result.scoringDirection == .higherIsBetter || result.scoringDirection == .lowerIsBetter
        else {
            return result
        }

        let exerciseProfile = PerformanceProfileStore.exerciseProfile(
            for: benchmarkExercise,
            in: performanceProfile,
            context: modelContext
        )
        exerciseProfile.lastPerformedAt = result.completedAt

        let existingBest = ScoringEngine.bestRecord(
            among: exerciseProfile.personalRecords,
            context: result.resultContext,
            repBand: nil
        )
        if ScoringEngine.isNewPersonalRecord(
            candidateValue: prCandidateValue,
            direction: result.scoringDirection,
            existingBest: existingBest
        ) {
            let record = PersonalRecord(
                value: prCandidateValue,
                repBand: nil,
                scoringDirection: result.scoringDirection,
                context: result.resultContext,
                achievedAt: result.completedAt
            )
            modelContext.insert(record)
            // sourceWorkoutResult is a one-directional traceability
            // pointer (no inverse collection declared), safe to set
            // directly.
            record.sourceWorkoutResult = result
            exerciseProfile.addPersonalRecord(record)
        }

        return result
    }
}
