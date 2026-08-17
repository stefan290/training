import Foundation
import SwiftData

/// Stage 6B: logs one steady-state block's actual outcome and folds it
/// into the user's permanent, program-independent history — the
/// endurance sibling of `RecordSetResultUseCase`, identified as a real
/// gap during Stage 6A (`WORKOUT_COMPLETION_PIPELINE.md` §2). This is
/// the only place a `SteadyStateResult` should be created.
enum RecordSteadyStateResultUseCase {
    /// `prCandidateValue`/`scoringDirection` are supplied by the caller,
    /// never derived here — unlike `SetResult.weight` or
    /// `FunctionalFitnessResult.scoreValue`, a `SteadyStateResult` has no
    /// single typed metric that's unambiguously "the" comparable number
    /// (duration, distance, pace and power are all independently
    /// optional). Passing `prCandidateValue: nil` means "don't attempt PR
    /// detection for this result" — a real, legitimate choice (e.g. an
    /// easy Zone 2 session with no meaningful PR concept), never a
    /// silently-guessed metric (CLAUDE.md rule 10).
    @discardableResult
    static func recordResult(
        _ result: SteadyStateResult,
        for workoutBlock: WorkoutBlock,
        activityType: ActivityType,
        performanceContext: String? = nil,
        prCandidateValue: Double?,
        scoringDirection: ScoringDirection,
        performanceProfile: PerformanceProfile,
        modelContext: ModelContext
    ) -> (result: SteadyStateResult, isFirstEverEntry: Bool) {
        let activityProfile = PerformanceProfileStore.activityProfile(
            for: activityType, performanceContext: performanceContext, in: performanceProfile, context: modelContext
        )

        modelContext.insert(result)
        workoutBlock.attachSteadyStateResult(result)
        activityProfile.addSteadyStateResult(result)
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
            record.sourceSteadyStateResult = result
            activityProfile.addPersonalRecord(record)
        }

        return (result, isFirstEverEntry)
    }
}
