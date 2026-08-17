import Foundation
import SwiftData
import Observation

/// Drives Interval execution (`ENDURANCE_EXECUTION_FLOW.md`, Part I).
/// Time-based intervals auto-progress Work -> Recovery -> Work purely
/// from elapsed wall-clock time (`IntervalTimerResolution`, never a tick
/// count); distance-based intervals have no clock to derive progress
/// from and are logged manually, one interval at a time. Either way, each
/// interval is persisted the moment it's known to be done
/// (`LogIntervalRepUseCase`) — never held in memory until the whole
/// block finishes (CLAUDE.md rule 20).
@Observable
final class IntervalExecutionViewModel {
    let block: WorkoutBlock
    /// The highest work-leg index already logged this visit — transient;
    /// on a fresh relaunch this is re-derived from `block.intervalResult`'s
    /// already-persisted rep count, never assumed to start at zero.
    private(set) var lastSyncedLegIndex: Int
    private(set) var incompleteLegIndices: Set<Int> = []

    init(block: WorkoutBlock) {
        self.block = block
        let loggedReps = block.intervalResult?.repResults.count ?? 0
        self.lastSyncedLegIndex = loggedReps > 0 ? (loggedReps - 1) * 2 : -1
    }

    var prescription: IntervalPrescription? { block.intervalPrescription }
    var isTimeBased: Bool { prescription?.workDurationSeconds != nil }
    var loggedIntervalCount: Int { block.intervalResult?.repResults.count ?? 0 }

    func position(asOf now: Date) -> IntervalTimerResolution.Position? {
        guard let prescription, let state = block.timerState, let workDuration = prescription.workDurationSeconds else { return nil }
        return IntervalTimerResolution.resolve(
            elapsedSeconds: WorkoutTimer.elapsedSeconds(state, asOf: now),
            workDurationSeconds: workDuration,
            recoveryDurationSeconds: prescription.recoveryDurationSeconds ?? 0,
            intervalCount: prescription.intervalCount
        )
    }

    /// Logs one `IntervalRepResult` for every work leg that has now fully
    /// elapsed since the last sync — completed-as-prescribed unless the
    /// user explicitly marked that leg incomplete. Safe to call on every
    /// render tick: a no-op once nothing new has finished, and correct
    /// even after a long background gap (re-derives from elapsed time,
    /// never replays intermediate legs' cues).
    func syncCompletedLegs(asOf now: Date, modelContext: ModelContext) {
        guard let prescription, let workDuration = prescription.workDurationSeconds else { return }
        guard let position = position(asOf: now) else { return }
        let recoveryDuration = prescription.recoveryDurationSeconds ?? 0
        let lastLegIndex = prescription.intervalCount * 2 - 2
        let fullyElapsedUpTo = position.isSessionComplete ? lastLegIndex : position.legIndex - 1
        guard fullyElapsedUpTo > lastSyncedLegIndex else { return }

        var legIndex = lastSyncedLegIndex + 1
        while legIndex <= fullyElapsedUpTo {
            if legIndex % 2 == 0 {
                let repResult = IntervalRepResult(
                    actualWorkDurationSeconds: workDuration,
                    wasCompletedAsPrescribed: !incompleteLegIndices.contains(legIndex),
                    actualRecoveryDurationSeconds: recoveryDuration > 0 ? recoveryDuration : nil
                )
                try? LogIntervalRepUseCase.logRep(repResult, for: block, modelContext: modelContext)
            }
            legIndex += 1
        }
        lastSyncedLegIndex = fullyElapsedUpTo
    }

    /// Flags the work leg currently in progress so the next sync records
    /// it as not completed as prescribed — an explicit user action, never
    /// inferred from the clock alone.
    func markCurrentLegIncomplete(asOf now: Date) {
        guard let position = position(asOf: now), position.isWork else { return }
        incompleteLegIndices.insert(position.legIndex)
    }

    /// Distance-based path: no clock, so the user logs each interval by
    /// hand, one at a time.
    @discardableResult
    func logManualInterval(
        actualWorkDistanceMeters: Double?, wasCompletedAsPrescribed: Bool, modelContext: ModelContext
    ) -> IntervalResult? {
        let repResult = IntervalRepResult(
            actualWorkDistanceMeters: actualWorkDistanceMeters, wasCompletedAsPrescribed: wasCompletedAsPrescribed
        )
        return try? LogIntervalRepUseCase.logRep(repResult, for: block, modelContext: modelContext)
    }

    @discardableResult
    func finish(
        sessionDurationSeconds: Int?, sessionDistanceMeters: Double?, averageHeartRate: Int?, rpe: Int?,
        modelContext: ModelContext
    ) -> LoggedResultHighlight? {
        guard let prescription else { return nil }
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        guard let performanceProfile = users.first?.performanceProfile else { return nil }

        let result: IntervalResult
        if let existing = block.intervalResult {
            result = existing
        } else {
            result = IntervalResult()
            modelContext.insert(result)
            block.attachIntervalResult(result)
        }

        guard let outcome = try? FinalizeIntervalResultUseCase.finalize(
            result, activityType: prescription.activityType,
            sessionDurationSeconds: sessionDurationSeconds, sessionDistanceMeters: sessionDistanceMeters,
            averagePaceSecondsPerKilometer: nil, averageHeartRate: averageHeartRate, rpe: rpe,
            prCandidateValue: nil, scoringDirection: .none, performanceProfile: performanceProfile, modelContext: modelContext
        ) else { return nil }

        return LoggedResultHighlight(
            label: IntensityPresentation.activityLabel(prescription.activityType),
            value: "\(result.repResults.count) intervals",
            isPersonalRecord: false,
            isFirstEverEntry: outcome.isFirstEverEntry
        )
    }
}
