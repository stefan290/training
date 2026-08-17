import Foundation
import SwiftData

/// Stage 6B: the final consistency point for a live Interval block — not
/// the first durability point (CLAUDE.md rule 20). Every rep is already
/// durable via `LogIntervalRepUseCase` by the time this runs; this only
/// fills in the session-level summary on the already-existing
/// `IntervalResult`, attaches it to the permanent
/// `ActivityPerformanceProfile`, and runs PR detection exactly once.
/// **Idempotent**: a second call (e.g. a double-tapped Finish) is a
/// no-op — detected by whether the result is already attached to the
/// profile, mirroring `CompleteSessionUseCase`'s own idempotency guard.
enum FinalizeIntervalResultUseCase {
    @discardableResult
    static func finalize(
        _ result: IntervalResult,
        activityType: ActivityType,
        performanceContext: String? = nil,
        sessionDurationSeconds: Int?,
        sessionDistanceMeters: Double?,
        averagePaceSecondsPerKilometer: Double?,
        averageHeartRate: Int?,
        rpe: Int?,
        prCandidateValue: Double?,
        scoringDirection: ScoringDirection,
        performanceProfile: PerformanceProfile,
        modelContext: ModelContext
    ) throws -> (result: IntervalResult, isFirstEverEntry: Bool) {
        let activityProfile = PerformanceProfileStore.activityProfile(
            for: activityType, performanceContext: performanceContext, in: performanceProfile, context: modelContext
        )
        guard !activityProfile.intervalResults.contains(where: { $0.id == result.id }) else {
            return (result, false)
        }

        result.sessionDurationSeconds = sessionDurationSeconds
        result.sessionDistanceMeters = sessionDistanceMeters
        result.averagePaceSecondsPerKilometer = averagePaceSecondsPerKilometer
        result.averageHeartRate = averageHeartRate
        result.rpe = rpe

        activityProfile.addIntervalResult(result)
        activityProfile.lastPerformedAt = result.completedAt

        var isFirstEverEntry = false
        if let prCandidateValue {
            let existingBest = ScoringEngine.bestRecord(among: activityProfile.personalRecords, context: result.resultContext, repBand: nil)
            isFirstEverEntry = existingBest == nil
            if ScoringEngine.isNewPersonalRecord(candidateValue: prCandidateValue, direction: scoringDirection, existingBest: existingBest) {
                let record = PersonalRecord(
                    value: prCandidateValue, repBand: nil, scoringDirection: scoringDirection,
                    context: result.resultContext, achievedAt: result.completedAt
                )
                modelContext.insert(record)
                record.sourceIntervalResult = result
                activityProfile.addPersonalRecord(record)
            }
        }

        try modelContext.save()
        return (result, isFirstEverEntry)
    }
}
