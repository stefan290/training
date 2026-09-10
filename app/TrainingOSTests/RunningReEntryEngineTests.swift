import XCTest
@testable import TrainingOS

/// Running R2.8/Testing K-P: missed-session/re-entry decision tests,
/// cited against FAQ Endrance Running.docx's exact wording (re-verified
/// via `textutil` this pass).
final class RunningReEntryEngineTests: XCTestCase {
    // MARK: K — missed single workout

    func testSingleMissedWorkoutMovesOneDayLaterWhenItWouldNotCompromiseNextSession() {
        let (decision, reason) = RunningReEntryEngine.singleMissedWorkout(wouldCompromiseNextSession: false)
        XCTAssertEqual(decision, .moveOneDayLater)
        XCTAssertEqual(reason, .singleWorkoutMovedOneDayLater)
    }

    func testSingleMissedWorkoutSkipsWhenMovingWouldCompromiseNextSession() {
        let (decision, reason) = RunningReEntryEngine.singleMissedWorkout(wouldCompromiseNextSession: true)
        XCTAssertEqual(decision, .skipRemainAsScheduled)
        XCTAssertEqual(reason, .singleWorkoutSkippedWouldCompromiseNextSession)
    }

    // MARK: L — missed illness week (previous week was NOT a deload)

    func testIllnessWeekRepeatsPreviousWeekWhenPreviousWasNotADeload() {
        let (decision, reason) = RunningReEntryEngine.wholeWeekMissed(cause: .illness, previousWeekWasDeload: false)
        XCTAssertEqual(decision, .repeatPreviousWeek)
        XCTAssertEqual(reason, .wholeWeekIllnessRepeatPreviousWeek)
    }

    // MARK: M — illness after a deload week

    func testIllnessWeekResumesWithMissedWeekWhenPreviousWasADeload() {
        let (decision, reason) = RunningReEntryEngine.wholeWeekMissed(cause: .illness, previousWeekWasDeload: true)
        XCTAssertEqual(decision, .resumeWithMissedWeek)
        XCTAssertEqual(reason, .wholeWeekIllnessPreviousWeekWasDeloadResumeWithMissed)
    }

    // MARK: N — travel-missed week (deload status irrelevant)

    func testTravelWeekAlwaysContinuesForwardRegardlessOfDeloadStatus() {
        let (decisionNotDeload, reasonNotDeload) = RunningReEntryEngine.wholeWeekMissed(cause: .travelOrObligations, previousWeekWasDeload: false)
        XCTAssertEqual(decisionNotDeload, .continueForwardNoRepeat)
        XCTAssertEqual(reasonNotDeload, .wholeWeekTravelContinueForward)

        let (decisionDeload, reasonDeload) = RunningReEntryEngine.wholeWeekMissed(cause: .travelOrObligations, previousWeekWasDeload: true)
        XCTAssertEqual(decisionDeload, .continueForwardNoRepeat)
        XCTAssertEqual(reasonDeload, .wholeWeekTravelContinueForward)
    }

    // MARK: O — multiple consecutive weeks missed

    func testMultipleWeeksMissedRestartsFromFirstWorkingWeekAfterPriorDeloadWhenAbsenceBeganAfterFirstDeload() {
        let (decision, reason) = RunningReEntryEngine.multipleConsecutiveWeeksMissed(absenceBeganBeforeFirstDeload: false)
        XCTAssertEqual(decision, .restartCurrentBlockFromFirstWorkingWeekAfterPriorDeload)
        XCTAssertEqual(reason, .multipleConsecutiveWeeksRestartFromAfterPriorDeload)
    }

    func testMultipleWeeksMissedRestartsFromBeginningWhenAbsenceBeganBeforeFirstDeload() {
        let (decision, reason) = RunningReEntryEngine.multipleConsecutiveWeeksMissed(absenceBeganBeforeFirstDeload: true)
        XCTAssertEqual(decision, .restartFromBeginningAbsenceBeforeFirstDeload)
        XCTAssertEqual(reason, .multipleConsecutiveWeeksRestartFromBeginningAbsenceBeforeFirstDeload)
    }

    // MARK: P — more than 1 month missed

    func testMoreThanOneMonthMissedReturnsBothSourceValidOptions() {
        let (decisions, reason) = RunningReEntryEngine.moreThanOneMonthMissed()
        XCTAssertEqual(Set(decisions), [.restartWholePlan, .moveBackAtLeastSixWeeksAndRepeat])
        XCTAssertEqual(reason, .moreThanOneMonthBothOptionsValid)
    }

    // MARK: Regression — no fabricated training debt

    func testSingleMissedWorkoutNeverProducesAThirdCatchUpLaterState() {
        // Exactly two outcomes exist in the type itself for this
        // function's return value's relevant cases — a third "banked
        // debt" state is not representable at all, not merely untested.
        let allRelevantCases: Set<RunningReEntryDecision> = [.moveOneDayLater, .skipRemainAsScheduled]
        let (decision1, _) = RunningReEntryEngine.singleMissedWorkout(wouldCompromiseNextSession: false)
        let (decision2, _) = RunningReEntryEngine.singleMissedWorkout(wouldCompromiseNextSession: true)
        XCTAssertTrue(allRelevantCases.contains(decision1))
        XCTAssertTrue(allRelevantCases.contains(decision2))
    }
}
