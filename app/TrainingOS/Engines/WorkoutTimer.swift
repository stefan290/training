import Foundation

/// Stage 6B: the pure, wall-clock-anchored arithmetic every execution
/// timer (rest, AMRAP, EMOM, interval work/recovery, For Time) shares —
/// `TIMER_ARCHITECTURE.md` §2, CLAUDE.md rule 21. No `SwiftData` import,
/// no system-clock read of its own: `now` is always supplied by the
/// caller, exactly like `SchedulingWindow.startDate`/`LongTermPlanner`'s
/// `asOf` parameters. Same inputs always produce the same output.
enum WorkoutTimer {
    /// Elapsed running time, excluding any paused duration. Negative only
    /// if `now` precedes `startedAt`, which a caller should never do —
    /// never clamped here, so a caller bug surfaces as an obviously wrong
    /// number rather than being silently hidden.
    static func elapsedSeconds(_ state: TimerState, asOf now: Date) -> TimeInterval {
        let pauseSoFar = state.accumulatedPauseSeconds + (state.pausedAt.map { now.timeIntervalSince($0) } ?? 0)
        return now.timeIntervalSince(state.startedAt) - pauseSoFar
    }

    /// `nil` when the timer has no target duration (a pure count-up
    /// clock, e.g. For Time with no cap).
    static func remainingSeconds(_ state: TimerState, asOf now: Date) -> TimeInterval? {
        guard let target = state.targetDurationSeconds else { return nil }
        return TimeInterval(target) - elapsedSeconds(state, asOf: now)
    }

    /// Whether a countdown has reached (or passed) its target — always
    /// `false` for a timer with no `targetDurationSeconds`.
    static func isExpired(_ state: TimerState, asOf now: Date) -> Bool {
        guard let remaining = remainingSeconds(state, asOf: now) else { return false }
        return remaining <= 0
    }

    /// **Relaunch/catch-up derivation** (`TIMER_ARCHITECTURE.md` §4,
    /// `STAGE6A_DECISION_MEMO.md` §1c) — the current discrete unit (an
    /// EMOM minute, an interval index) recomputed deterministically from
    /// elapsed time, never replayed step by step. Clamped to the last
    /// valid unit so a timer recovered long after it should have ended
    /// lands on its final unit rather than an out-of-range index.
    static func currentUnitIndex(asOf now: Date, state: TimerState, unitDurationSeconds: Int, totalUnits: Int) -> Int {
        guard unitDurationSeconds > 0, totalUnits > 0 else { return 0 }
        let elapsed = max(0, elapsedSeconds(state, asOf: now))
        let derivedIndex = Int(elapsed) / unitDurationSeconds
        return min(derivedIndex, totalUnits - 1)
    }

    /// Starts a fresh, running timer — the only way a `TimerState` should
    /// be created, so every call site stamps `startedAt` from the same
    /// caller-supplied `now` rather than reading the clock ad hoc.
    static func start(asOf now: Date, targetDurationSeconds: Int? = nil, currentUnitIndex: Int? = nil) -> TimerState {
        TimerState(startedAt: now, targetDurationSeconds: targetDurationSeconds, currentUnitIndex: currentUnitIndex)
    }

    /// Pauses a running timer. A no-op (returns the same state) if
    /// already paused — pausing twice must never double-count pause time.
    static func pause(_ state: TimerState, asOf now: Date) -> TimerState {
        guard state.pausedAt == nil else { return state }
        var next = state
        next.pausedAt = now
        return next
    }

    /// Resumes a paused timer, folding the just-ended pause into
    /// `accumulatedPauseSeconds`. A no-op if not currently paused.
    static func resume(_ state: TimerState, asOf now: Date) -> TimerState {
        guard let pausedAt = state.pausedAt else { return state }
        var next = state
        next.accumulatedPauseSeconds += now.timeIntervalSince(pausedAt)
        next.pausedAt = nil
        return next
    }

    /// Advances to a new unit, restarting the per-unit countdown with a
    /// fresh `startedAt` — `TIMER_ARCHITECTURE.md` §7's "a fresh
    /// `startedAt` is stamped at each minute boundary so the per-minute
    /// countdown itself stays wall-clock anchored."
    static func advanceUnit(asOf now: Date, to unitIndex: Int, targetDurationSeconds: Int?) -> TimerState {
        TimerState(startedAt: now, targetDurationSeconds: targetDurationSeconds, currentUnitIndex: unitIndex)
    }
}
