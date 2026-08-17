import Foundation

/// Stage 6E: which of the three conceptually distinct ways a `Session`
/// can be shown — never collapsed into one screen that special-cases
/// itself into oblivion. Computed purely from `SessionStatus` (a
/// completed/skipped/missed/abandoned Session is ALWAYS history,
/// regardless of what a caller's `readOnly` flag says) with `readOnly`
/// only disambiguating a `.scheduled` Session (a not-yet-started Session
/// viewed ahead of time from Week/Plan vs. Today's own actionable one).
/// An `.inProgress` Session is always resumable when opened, wherever
/// it's opened from — matches the explicit Week requirement that
/// in-progress routes to execution/resume regardless of which day it's
/// viewed from.
enum SessionDisplayMode {
    case execution
    case futurePreview
    case completedHistory

    static func mode(for status: SessionStatus, readOnly: Bool) -> SessionDisplayMode {
        switch status {
        case .completed, .skipped, .missed, .abandoned:
            return .completedHistory
        case .scheduled:
            return readOnly ? .futurePreview : .execution
        case .inProgress:
            return .execution
        }
    }
}

/// Stage 6E: re-derives, for a PersonalRecord already sitting in
/// completed history, whether it was this profile's first-ever entry in
/// its context/repBand group or a genuine improvement over an earlier
/// one — the same comparison `RecordSetResultUseCase` makes at log time
/// (`existingBest == nil`), just re-run later over the now-persisted
/// `PersonalRecord` rows instead of a transient return value. Pure read,
/// never mutates, never a second PR-detection mechanism.
enum CompletedResultPresentation {
    static func isFirstEverEntry(_ record: PersonalRecord, in profile: ExercisePerformanceProfile) -> Bool {
        let sameGroup = profile.personalRecords.filter { $0.context == record.context && $0.repBand == record.repBand }
        guard let earliest = sameGroup.min(by: { $0.achievedAt < $1.achievedAt }) else { return true }
        return earliest.id == record.id
    }
}

/// Stage 6E Part 6: the smallest clean presentation mapper for
/// `StrengthReasonCode`'s set-count cases — friendly copy for "why is
/// this week's volume what it is," never a second decision engine. Only
/// the autoregulation-shaped cases have anything user-facing to say;
/// every other case (a fixed schedule, a deload variant, calibration)
/// means nothing autoregulation-specific happened this week, so there's
/// nothing worth surfacing here.
enum StrengthReasonCodePresentation {
    static func setCountReasonText(_ reasonCode: StrengthReasonCode) -> String? {
        switch reasonCode {
        case .autoregulatedSetIncrease:
            return "One set was added based on your recovery/stimulus feedback."
        case .autoregulatedSetHold:
            return "Sets held steady based on your recovery/stimulus feedback."
        case .autoregulatedSetDecrease:
            return "One set was removed based on your recovery/stimulus feedback."
        case .autoregulatedSetFinalWeekUnchanged:
            return "Sets were left unchanged for the final week of this block."
        case .autoregulatedSetFrozen:
            return "Sets are held at this block's frozen value."
        default:
            return nil
        }
    }
}
