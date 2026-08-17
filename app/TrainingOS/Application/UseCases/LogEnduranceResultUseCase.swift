import Foundation
import SwiftData

/// Stage 6B: the orchestrating use case behind every logged steady-state
/// or interval result — wraps `RecordSteadyStateResultUseCase`/
/// `RecordIntervalResultUseCase` and saves immediately, matching
/// `LogSetUseCase`'s exact shape (`WORKOUT_COMPLETION_PIPELINE.md` §1).
enum LogEnduranceResultUseCase {
    @discardableResult
    static func logSteadyStateResult(
        _ result: SteadyStateResult,
        for workoutBlock: WorkoutBlock,
        activityType: ActivityType,
        performanceContext: String? = nil,
        prCandidateValue: Double?,
        scoringDirection: ScoringDirection,
        performanceProfile: PerformanceProfile,
        modelContext: ModelContext
    ) throws -> (result: SteadyStateResult, isFirstEverEntry: Bool) {
        let outcome = RecordSteadyStateResultUseCase.recordResult(
            result, for: workoutBlock, activityType: activityType, performanceContext: performanceContext,
            prCandidateValue: prCandidateValue, scoringDirection: scoringDirection,
            performanceProfile: performanceProfile, modelContext: modelContext
        )
        try modelContext.save()
        return outcome
    }

    @discardableResult
    static func logIntervalResult(
        _ result: IntervalResult,
        for workoutBlock: WorkoutBlock,
        activityType: ActivityType,
        performanceContext: String? = nil,
        prCandidateValue: Double?,
        scoringDirection: ScoringDirection,
        performanceProfile: PerformanceProfile,
        modelContext: ModelContext
    ) throws -> (result: IntervalResult, isFirstEverEntry: Bool) {
        let outcome = RecordIntervalResultUseCase.recordResult(
            result, for: workoutBlock, activityType: activityType, performanceContext: performanceContext,
            prCandidateValue: prCandidateValue, scoringDirection: scoringDirection,
            performanceProfile: performanceProfile, modelContext: modelContext
        )
        try modelContext.save()
        return outcome
    }
}
