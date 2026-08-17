import Foundation

/// The alternating-work/recovery sibling of `WorkoutTimer.currentUnitIndex`
/// — that function assumes every unit shares one duration (EMOM's
/// per-minute cadence); a work leg and a recovery leg are usually
/// different lengths, so this derives the correct leg deterministically
/// from elapsed (already pause-adjusted) time instead
/// (`TIMER_ARCHITECTURE.md`, Part I: automatic Work -> Recovery -> Work
/// progression for time-based intervals). Only ever used for time-based
/// intervals — distance-based intervals have no clock to derive from and
/// are completed manually (`ENDURANCE_EXECUTION_FLOW.md`).
enum IntervalTimerResolution {
    struct Position: Equatable {
        /// 0-based across the full work/recovery sequence: leg 0 is work
        /// interval 1, leg 1 is its recovery, leg 2 is work interval 2, ...
        let legIndex: Int
        let isWork: Bool
        /// The 1-based interval number this leg belongs to, for display —
        /// "Interval 3 of 6."
        let intervalNumber: Int
        let remainingInLegSeconds: TimeInterval
        /// The whole prescribed sequence (every work leg, and every
        /// recovery leg except a trailing one after the final interval)
        /// has elapsed.
        let isSessionComplete: Bool
    }

    /// Never replays intermediate legs step by step — a relaunch long
    /// after the session should have ended lands directly on the final
    /// leg (clamped), exactly like `WorkoutTimer.currentUnitIndex`'s own
    /// clamping contract.
    static func resolve(
        elapsedSeconds: TimeInterval,
        workDurationSeconds: Int,
        recoveryDurationSeconds: Int,
        intervalCount: Int
    ) -> Position {
        guard workDurationSeconds > 0, intervalCount > 0 else {
            return Position(legIndex: 0, isWork: true, intervalNumber: 1, remainingInLegSeconds: TimeInterval(workDurationSeconds), isSessionComplete: false)
        }

        // The prescribed sequence is work,recovery,work,recovery,...,work —
        // no trailing recovery after the final interval.
        let lastLegIndex = intervalCount * 2 - 2
        var remaining = max(0, elapsedSeconds)
        var legIndex = 0

        while legIndex <= lastLegIndex {
            let isWork = legIndex % 2 == 0
            let legDuration = isWork ? workDurationSeconds : recoveryDurationSeconds
            if legDuration <= 0 || remaining < TimeInterval(legDuration) {
                let clampedRemaining = legDuration > 0 ? max(0, TimeInterval(legDuration) - remaining) : 0
                return Position(
                    legIndex: legIndex, isWork: isWork, intervalNumber: legIndex / 2 + 1,
                    remainingInLegSeconds: clampedRemaining, isSessionComplete: false
                )
            }
            remaining -= TimeInterval(legDuration)
            legIndex += 1
        }

        return Position(legIndex: lastLegIndex, isWork: true, intervalNumber: intervalCount, remainingInLegSeconds: 0, isSessionComplete: true)
    }
}
