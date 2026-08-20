import Foundation

/// A machine-readable classification of a placement problem —
/// `GoalAlignmentEvaluator` (and any future UI) reads this, never a
/// human-facing string. Additive: never rename or repurpose a case once
/// something reads it, exactly like `SchedulingReasonCode`.
enum ScheduleIssueCode: String, Codable, CaseIterable {
    /// A session had no usable day at all because every candidate
    /// weekday was excluded by `UserAvailability`.
    case unavailableDay
    /// A session had no usable day because every candidate would have
    /// exceeded `UserAvailability.maxSessionsPerDay` (including "no room
    /// to double" cases).
    case maxSessionsExceeded
    /// A session had no usable day because `UserAvailability
    /// .minutesAvailablePerDay` was insufficient for its estimated
    /// duration on every candidate weekday.
    case insufficientTime
    /// A `.required`-flexibility component did not reach its required
    /// minimum (or target, when no minimum was set) frequency.
    case requiredFrequencyUnsatisfied
    /// A `.preferred`-flexibility component did not reach its minimum
    /// (or target) frequency.
    case preferredFrequencyUnsatisfied
    /// A soft `InterferenceAvoidanceRule` had to be violated to place a
    /// session at all.
    case interferenceConflict
    /// A component's own required spacing could not be honored for at
    /// least one of its sessions within the window. Declared for
    /// vocabulary completeness (mirrors the "reserved reason code"
    /// precedent from `FunctionalFitnessReasonCode` — see
    /// `STAGE4_IMPLEMENTATION_REPORT.md`'s Stage 4E section); spacing is
    /// currently enforced as a hard constraint that a session simply
    /// cannot be placed at all if it can't be honored, so this fires with
    /// `.hard` severity as the classification of *why* a session ended
    /// up in `ScheduleProposal.conflicts`.
    case recoverySpacingCompromise
    /// A `.primary`-priority component ended up with at least one
    /// unplaced session — the most serious compromise this system can
    /// report, since it means the phase's own primary adaptation goal
    /// was not fully honored.
    case primaryGoalCompromise
    /// A session could not land on any of its component's own
    /// `preferredDays` at all, even though it was still placed elsewhere.
    case preferenceCompromise
    /// A `.optional`-flexibility component ended up entirely unscheduled
    /// (zero sessions placed) — an accepted, non-urgent outcome, not a
    /// failure.
    case optionalComponentUnscheduled
    /// A session could only be placed by pairing it same-day with
    /// another component's session — every one of its own hard-valid
    /// candidate days was already occupied, so doubling was not a
    /// preference, it was the only option.
    case doubleSessionRequired
    /// A candidate day fell before the calendar week this session's own
    /// naive, materializer-assigned date belongs to. A component that
    /// materializes several weeks in one call (Steady State's whole
    /// natural block, for instance) produces sessions whose own week of
    /// origin is real, already-known data — a later week's session must
    /// never be pulled into an earlier week just because an earlier day
    /// happens to be free. See `ConcurrentScheduler.originWeekFloorOffset`.
    case earlierThanOriginWeek
}

/// Hard = a constraint was violated outright (a session or an entire
/// component's required minimum could not be satisfied at all). Soft = a
/// preference/compromise that was accepted so the schedule could still be
/// produced — the session or component IS placed/covered, just not
/// ideally.
enum IssueSeverity: String, Codable, CaseIterable {
    case hard
    case soft
}

/// One structured, typed fact about a `ScheduleProposal` — the
/// machine-readable alternative to inspecting `warnings` text.
/// `GoalAlignmentEvaluator` and any future UI must read `code`/`severity`/
/// `componentLabel`/`session`, never `reason` — `reason` is pure,
/// independently-changeable display copy generated FROM the structured
/// fields, and changing it must never change what any business logic
/// concludes (proven by `ConcurrentSchedulerTests
/// .testChangingIssueDisplayCopyNeverChangesGoalAlignment`).
struct ScheduleIssue {
    var code: ScheduleIssueCode
    var severity: IssueSeverity
    var componentLabel: String
    /// The specific affected Session, when this issue is about one
    /// particular placement rather than the component as a whole (e.g.
    /// `.primaryGoalCompromise`/`.requiredFrequencyUnsatisfied` are
    /// component-wide facts and leave this `nil`).
    var session: Session?
    /// Human-readable explanation — display copy only, generated from
    /// the fields above. Never parsed back by any business logic.
    var reason: String
    /// Small, optional structured extras (e.g. `"requiredMinimum": "3"`)
    /// for a future UI that wants more detail than `reason` alone.
    var metadata: [String: String]

    init(
        code: ScheduleIssueCode,
        severity: IssueSeverity,
        componentLabel: String,
        session: Session? = nil,
        reason: String,
        metadata: [String: String] = [:]
    ) {
        self.code = code
        self.severity = severity
        self.componentLabel = componentLabel
        self.session = session
        self.reason = reason
        self.metadata = metadata
    }
}
