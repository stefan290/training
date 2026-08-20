import SwiftUI

/// Pure display-string/icon/color mapping for a Session's status — never
/// a business decision, just what the Today card and Session Detail
/// header print for a given `SessionStatus`/`SessionRole`. Status is
/// always paired with an icon, never color alone (Part O accessibility
/// requirement).
enum SessionPresentation {
    static func statusLabel(_ status: SessionStatus) -> String {
        switch status {
        case .scheduled: "Ready"
        case .inProgress: "In Progress"
        case .completed: "Completed"
        case .skipped: "Skipped"
        case .missed: "Missed"
        case .abandoned: "Abandoned"
        }
    }

    static func statusIcon(_ status: SessionStatus) -> String {
        switch status {
        case .scheduled: "circle"
        case .inProgress: "play.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .skipped: "forward.circle"
        case .missed: "exclamationmark.circle"
        case .abandoned: "xmark.circle"
        }
    }

    static func statusColor(_ status: SessionStatus) -> Color {
        switch status {
        case .scheduled: Theme.textSecondary
        case .inProgress: Theme.primary
        case .completed: Theme.positive
        case .skipped: Theme.textSecondary
        case .missed: Theme.attention
        case .abandoned: Theme.textSecondary
        }
    }

    /// Stage 6C, Part P: Week's status label — "Upcoming" is the one
    /// presentation-only addition on top of the canonical `SessionStatus`
    /// (a `.scheduled` Session on a day other than today), never a second
    /// persisted status system. Every other case maps straight through
    /// `statusLabel`.
    static func weekStatusLabel(for status: SessionStatus, isToday: Bool) -> String {
        if status == .scheduled && !isToday { return "Upcoming" }
        return statusLabel(status)
    }

    /// Stage 7 (Tactical Planning Orchestration), Slice 4 acceptance
    /// finding: `scheduledTime` is genuinely non-nil real Date data
    /// (`AcceptScheduleProposalUseCase.accept` always writes one), but
    /// the real scheduling model has no time-of-day concept anywhere —
    /// every production-scheduled Session's `scheduledTime` is exactly
    /// midnight on its own date (inherited from `phase.startDate`'s own
    /// start-of-day anchoring). Presenting that midnight value as if
    /// TrainingOS deliberately chose "00:00" would misrepresent a value
    /// the system never actually decided to schedule at that hour —
    /// render it as "Anytime" instead. `nil` (never resolved through the
    /// scheduler at all) keeps its own existing meaning — the caller
    /// simply shows nothing, unchanged. A hand-authored fixture's own
    /// deliberately-chosen time (e.g. 07:00) still renders normally.
    static func scheduledTimeLabel(_ scheduledTime: Date) -> String {
        guard hasGenuineTimeOfDay(scheduledTime) else { return "Anytime" }
        return scheduledTime.formatted(date: .omitted, time: .shortened)
    }

    /// The single shared definition of "this `scheduledTime` is a real,
    /// meaningfully-assigned clock time, not just the date-only midnight
    /// anchor the real scheduler always produces" — used identically by
    /// `scheduledTimeLabel` above and `isPastDueUnstarted` below, so the
    /// two can never silently disagree on what counts as "genuinely
    /// timed."
    static func hasGenuineTimeOfDay(_ scheduledTime: Date) -> Bool {
        scheduledTime != Calendar.current.startOfDay(for: scheduledTime)
    }

    /// A date-only/"Anytime" Session (no genuine time-of-day ever
    /// assigned) is never "late" merely because the clock has passed
    /// midnight — it stays normally startable for its whole calendar day.
    /// Only a genuinely time-specific `scheduledTime` can make a Session
    /// late, and only once that specific time has passed. `asOf` defaults
    /// to the real current moment for `TodayView`'s own call site;
    /// injectable for deterministic tests.
    static func isPastDueUnstarted(status: SessionStatus, scheduledTime: Date?, asOf: Date = Date()) -> Bool {
        guard status == .scheduled, let scheduledTime, hasGenuineTimeOfDay(scheduledTime) else { return false }
        return scheduledTime < asOf
    }

    static func roleLabel(_ role: SessionRole) -> String {
        switch role {
        case .strength: "Strength"
        case .hypertrophy: "Hypertrophy"
        case .easy: "Easy"
        case .recovery: "Recovery"
        case .long: "Long"
        case .tempo: "Tempo"
        case .threshold: "Threshold"
        case .interval: "Interval"
        case .aerobicBase: "Aerobic Base"
        case .functionalFitness: "Functional Fitness"
        case .skill: "Skill"
        case .mixed: "Mixed"
        }
    }
}
