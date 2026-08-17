import Foundation

/// Stage 6B: whether a `.completed` `Session` represents everything it
/// was scheduled to do, or an intentional early finish
/// (`SESSION_STATE_MACHINE.md` §2, `STAGE6A_DECISION_MEMO.md` §1a).
/// `nil` until `Session.status == .completed`. Never a substitute for
/// `SessionStatus` — `.scheduled`/`.inProgress`/`.skipped`/`.missed`/
/// `.abandoned` never set this.
enum SessionCompletionContext: String, Codable, CaseIterable {
    /// Every non-skipped block reached `.completed` with its own
    /// `completionContext == .full`.
    case full
    /// The user explicitly finished early via "Finish as Partial" — some
    /// blocks were flipped to `.skipped`, and/or a completed block was
    /// itself `.partial`. Logged results are kept exactly as recorded.
    case partial
}

/// The `WorkoutBlock` sibling of `SessionCompletionContext` — refines
/// `.completed` with "was every prescribed unit actually logged." `nil`
/// until `WorkoutBlock.status == .completed`; never set on `.skipped`
/// (zero attempt is a different fact than a partial attempt).
enum BlockCompletionContext: String, Codable, CaseIterable {
    /// Every unit the block's prescription called for (sets, rounds,
    /// intervals, movements) has a real logged result.
    case full
    /// The block was marked `.completed` with fewer results than its
    /// prescription called for.
    case partial
}

/// Stage 6B: the one persisted shape every timer in the execution UI
/// reuses — wall-clock anchored, never a tick count
/// (`TIMER_ARCHITECTURE.md` §2, CLAUDE.md rule 21). Stored inline as a
/// single optional field on `WorkoutBlock`; not a `@Model` entity, since
/// nothing about a timer's own state needs independent identity,
/// relationships, or a delete rule.
struct TimerState: Codable, Equatable {
    var startedAt: Date
    /// `nil` while running.
    var pausedAt: Date?
    /// Sum of every prior pause's duration — updated when a pause ends,
    /// never accumulated tick-by-tick.
    var accumulatedPauseSeconds: TimeInterval
    /// The timer's own target duration, when it counts down (AMRAP cap,
    /// EMOM per-minute interval, rest timer default, a capped For
    /// Time/interval leg) — `nil` for a pure count-up clock.
    var targetDurationSeconds: Int?
    /// Which discrete unit this timer is currently on — EMOM's current
    /// minute (0-based), an interval block's current interval index.
    /// `nil` for timers with no sub-unit concept (rest timer, AMRAP, For
    /// Time and its siblings).
    var currentUnitIndex: Int?

    init(
        startedAt: Date,
        pausedAt: Date? = nil,
        accumulatedPauseSeconds: TimeInterval = 0,
        targetDurationSeconds: Int? = nil,
        currentUnitIndex: Int? = nil
    ) {
        self.startedAt = startedAt
        self.pausedAt = pausedAt
        self.accumulatedPauseSeconds = accumulatedPauseSeconds
        self.targetDurationSeconds = targetDurationSeconds
        self.currentUnitIndex = currentUnitIndex
    }
}
