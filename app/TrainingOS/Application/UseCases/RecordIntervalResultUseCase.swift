import Foundation
import SwiftData

/// Stage 6B: logs one interval block's actual outcome (session summary
/// plus its already-populated `repResults`) and folds it into permanent
/// history — the sibling of `RecordSteadyStateResultUseCase`, identified
/// as a real gap during Stage 6A (`WORKOUT_COMPLETION_PIPELINE.md` §2).
/// This is the only place an `IntervalResult` should be created; per-rep
/// `IntervalRepResult`s are expected to already be attached via
/// `IntervalResult.addRepResult` before this is called
/// (`ENDURANCE_EXECUTION_FLOW.md` §2c — never collapsed into one
/// average).
enum RecordIntervalResultUseCase {
    /// See `RecordSteadyStateResultUseCase`'s identical doc note on why
    /// `prCandidateValue` is caller-supplied rather than derived here —
    /// an `IntervalResult` has no single unambiguous "the" comparable
    /// metric either.
    @discardableResult
    static func recordResult(
        _ result: IntervalResult,
        for workoutBlock: WorkoutBlock,
        activityType: ActivityType,
        performanceContext: String? = nil,
        prCandidateValue: Double?,
        scoringDirection: ScoringDirection,
        performanceProfile: PerformanceProfile,
        modelContext: ModelContext
    ) -> (result: IntervalResult, isFirstEverEntry: Bool) {
        let activityProfile = PerformanceProfileStore.activityProfile(
            for: activityType, performanceContext: performanceContext, in: performanceProfile, context: modelContext
        )

        modelContext.insert(result)
        workoutBlock.attachIntervalResult(result)
        activityProfile.addIntervalResult(result)
        activityProfile.lastPerformedAt = result.completedAt

        guard let prCandidateValue else { return (result, false) }

        let existingBest = ScoringEngine.bestRecord(
            among: activityProfile.personalRecords, context: result.resultContext, repBand: nil
        )
        let isFirstEverEntry = existingBest == nil
        if ScoringEngine.isNewPersonalRecord(candidateValue: prCandidateValue, direction: scoringDirection, existingBest: existingBest) {
            let record = PersonalRecord(
                value: prCandidateValue, repBand: nil, scoringDirection: scoringDirection,
                context: result.resultContext, achievedAt: result.completedAt
            )
            modelContext.insert(record)
            record.sourceIntervalResult = result
            activityProfile.addPersonalRecord(record)
        }

        return (result, isFirstEverEntry)
    }
}
