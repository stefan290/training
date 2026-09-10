import Foundation

/// Pure, deterministic missed-session/re-entry decisions — FAQ's own
/// answers to "What should I do if I miss or must skip a workout?"
/// through "What should I do if I miss more than 1 month of training?"
/// (`RUNNING_PROGRAMMING_MODEL_R1.md` §13/§14, R2.8). No SwiftData, no
/// persistence, no reading the current date — every input the source
/// actually branches on (which cause, whether the prior week was a
/// deload, whether the absence began before the first deload) is a plain
/// caller-supplied value, never inferred from a calendar this engine
/// reads itself.
///
/// Authorized for this checkpoint specifically: CLAUDE.md rule 11 lists
/// "missed-session recovery" as out of V1 scope "until explicitly
/// requested" — the Running R2 directive explicitly requests it (R2.8).
enum RunningReEntryEngine {
    /// "If you have time in your schedule to make it up the following
    /// day... without interfering with the quality of the next training
    /// session, you may move the workout to one day later. Otherwise,
    /// skip the workout, and continue the training plan as planned."
    /// Never fabricates a third, catch-up-later state — exactly these
    /// two outcomes, matching the source exactly.
    static func singleMissedWorkout(wouldCompromiseNextSession: Bool) -> (decision: RunningReEntryDecision, reasonCode: RunningReEntryReasonCode) {
        wouldCompromiseNextSession
            ? (.skipRemainAsScheduled, .singleWorkoutSkippedWouldCompromiseNextSession)
            : (.moveOneDayLater, .singleWorkoutMovedOneDayLater)
    }

    /// "If you miss an entire week of workouts due to illness... complete
    /// the previous week... again, unless that previous week was a
    /// deload week... prior to moving forward with the missed week...
    /// If the week of completed training preceding illness was a deload
    /// week, just start training again with the week... that you
    /// missed." / "If you miss a week of workouts due to travel or other
    /// life obligations, just move forward immediately."
    static func wholeWeekMissed(cause: RunningMissedWeekCause, previousWeekWasDeload: Bool) -> (decision: RunningReEntryDecision, reasonCode: RunningReEntryReasonCode) {
        switch cause {
        case .illness:
            return previousWeekWasDeload
                ? (.resumeWithMissedWeek, .wholeWeekIllnessPreviousWeekWasDeloadResumeWithMissed)
                : (.repeatPreviousWeek, .wholeWeekIllnessRepeatPreviousWeek)
        case .travelOrObligations:
            return (.continueForwardNoRepeat, .wholeWeekTravelContinueForward)
        }
    }

    /// "If you miss multiple weeks of workouts in a row... start the
    /// training block over again, starting with the first 'working week'
    /// of training after the previous deload week, or with the first
    /// week of the whole plan, if your absence from training started
    /// during the first training block (before the first deload)."
    static func multipleConsecutiveWeeksMissed(absenceBeganBeforeFirstDeload: Bool) -> (decision: RunningReEntryDecision, reasonCode: RunningReEntryReasonCode) {
        absenceBeganBeforeFirstDeload
            ? (.restartFromBeginningAbsenceBeforeFirstDeload, .multipleConsecutiveWeeksRestartFromBeginningAbsenceBeforeFirstDeload)
            : (.restartCurrentBlockFromFirstWorkingWeekAfterPriorDeload, .multipleConsecutiveWeeksRestartFromAfterPriorDeload)
    }

    /// "If you miss more than 1 month of training, it is recommended that
    /// you start the whole plan over again or move at least 6 weeks back
    /// in the training to repeat 6 weeks of what had been completed
    /// before." Both options are equally source-valid; this engine
    /// returns both rather than choosing one for the athlete.
    static func moreThanOneMonthMissed() -> (decisions: [RunningReEntryDecision], reasonCode: RunningReEntryReasonCode) {
        ([.restartWholePlan, .moveBackAtLeastSixWeeksAndRepeat], .moreThanOneMonthBothOptionsValid)
    }
}
