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

/// Stage 10B follow-up: the pure decision behind `SessionDetailView`'s
/// auto-advance-into-the-sole-block behavior — extracted from the View
/// so the actual business rule, not the SwiftUI lifecycle wiring around
/// it, is independently testable (mirrors `SessionDisplayMode.mode`'s
/// own precedent exactly). Closes a real reported gap: finishing
/// readiness/warm-up left the user on a plain Today list with no
/// indication where to go next, never inside the actual workout —
/// because nothing ever navigated into the Session's own detail screen,
/// and even once there, a single-block Session's one-row block list was
/// an extra, pointless tap before reaching execution.
enum SessionAutoAdvance {
    /// The one block to auto-open, or `nil` if no auto-advance should
    /// happen. Never fires for a not-yet-started (`.scheduled`) Session
    /// — that status transition is still the user's own explicit "Start
    /// Workout" tap on this same screen, never silently skipped. Never
    /// re-opens an already-finished block.
    ///
    /// Dogfood Round 2 Continuation (Finding O): generalized from "the
    /// Session has exactly one block" to "exactly one block still has
    /// real work left" — the SAME "no real choice exists" rationale the
    /// original, single-block-only version already encoded, just applied
    /// to REMAINING work instead of total block count. A brand-new
    /// multi-block Session (e.g. Muscle Gain's Functional Bodybuilding +
    /// Conditioning) still shows its real block-list choice while more
    /// than one block has work left — completely unchanged from before.
    /// Once every block but one is genuinely `.completed`/`.skipped`,
    /// that last block is exactly as "the sole remaining thing to do" as
    /// an originally-single-block Session always was, so it now auto-
    /// opens the same way — closing the real reported gap ("continue to
    /// Conditioning" after Functional Bodybuilding finishes) without a
    /// redundant overview step, and without ever forcing the athlete back
    /// into a block they backed out of mid-way (that block is still
    /// `.pending`/`.active`, not `.completed`, so it isn't "the sole
    /// remaining" thing whenever a DIFFERENT block also still has work).
    static func blockToAutoOpen(session: Session) -> WorkoutBlock? {
        guard session.status == .inProgress else { return nil }
        let remaining = session.orderedBlocks.filter { $0.status != .completed && $0.status != .skipped }
        guard remaining.count == 1, let onlyRemaining = remaining.first else { return nil }
        return onlyRemaining
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
