import Foundation

/// Why a whole week was missed — FAQ branches the outcome entirely on
/// this distinction ("due to illness" vs. "due to travel or other life
/// obligations"), so it must be an explicit, typed input, never inferred.
enum RunningMissedWeekCause: String, Codable, CaseIterable {
    case illness
    case travelOrObligations
}

/// The outcome of a missed-session/missed-week/missed-block decision —
/// FAQ lines covering "miss or must skip a workout" through "miss more
/// than 1 month of training" (`RUNNING_PROGRAMMING_MODEL_R1.md` §13/§14,
/// R2.8).
enum RunningReEntryDecision: String, Codable, CaseIterable {
    case moveOneDayLater
    case skipRemainAsScheduled
    case repeatPreviousWeek
    case resumeWithMissedWeek
    case continueForwardNoRepeat
    case restartCurrentBlockFromFirstWorkingWeekAfterPriorDeload
    case restartFromBeginningAbsenceBeforeFirstDeload
    case restartWholePlan
    case moveBackAtLeastSixWeeksAndRepeat
}

enum RunningReEntryReasonCode: String, Codable, CaseIterable {
    case singleWorkoutMovedOneDayLater
    case singleWorkoutSkippedWouldCompromiseNextSession
    case wholeWeekIllnessRepeatPreviousWeek
    case wholeWeekIllnessPreviousWeekWasDeloadResumeWithMissed
    case wholeWeekTravelContinueForward
    case multipleConsecutiveWeeksRestartFromAfterPriorDeload
    case multipleConsecutiveWeeksRestartFromBeginningAbsenceBeforeFirstDeload
    /// The source explicitly offers TWO valid options here ("restart the
    /// whole plan over again OR move at least 6 weeks back... to repeat
    /// 6 weeks of what had been completed") with no tie-breaker given —
    /// `RunningReEntryEngine.moreThanOneMonthMissed()` returns both as an
    /// array rather than this engine inventing a preference the source
    /// never states (CLAUDE.md rule 10).
    case moreThanOneMonthBothOptionsValid
}
