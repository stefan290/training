import XCTest
@testable import TrainingOS

/// Stage 6B: `WorkoutTimer`'s pure wall-clock arithmetic —
/// `TIMER_ARCHITECTURE.md`, CLAUDE.md rule 21. No `ModelContext`, no
/// system clock read.
final class WorkoutTimerTests: XCTestCase {
    private func date(_ offsetSeconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_800_000_000 + offsetSeconds)
    }

    func testElapsedSecondsCountsUpFromStart() {
        let state = TimerState(startedAt: date(0))
        XCTAssertEqual(WorkoutTimer.elapsedSeconds(state, asOf: date(90)), 90)
    }

    func testElapsedSecondsExcludesAccumulatedPauseTime() {
        let state = TimerState(startedAt: date(0), accumulatedPauseSeconds: 30)
        XCTAssertEqual(WorkoutTimer.elapsedSeconds(state, asOf: date(90)), 60)
    }

    func testElapsedSecondsExcludesTimeSpentInAnOngoingPause() {
        let state = TimerState(startedAt: date(0), pausedAt: date(30))
        // 60s wall-clock since start, but paused for the last 20s of it.
        XCTAssertEqual(WorkoutTimer.elapsedSeconds(state, asOf: date(50)), 30)
    }

    func testRemainingSecondsIsNilWithNoTargetDuration() {
        let state = TimerState(startedAt: date(0))
        XCTAssertNil(WorkoutTimer.remainingSeconds(state, asOf: date(10)))
    }

    func testRemainingSecondsCountsDownToZero() {
        let state = TimerState(startedAt: date(0), targetDurationSeconds: 180)
        XCTAssertEqual(WorkoutTimer.remainingSeconds(state, asOf: date(60)), 120)
    }

    func testIsExpiredFalseBeforeTargetReached() {
        let state = TimerState(startedAt: date(0), targetDurationSeconds: 180)
        XCTAssertFalse(WorkoutTimer.isExpired(state, asOf: date(179)))
    }

    func testIsExpiredTrueExactlyAtAndAfterTarget() {
        let state = TimerState(startedAt: date(0), targetDurationSeconds: 180)
        XCTAssertTrue(WorkoutTimer.isExpired(state, asOf: date(180)))
        XCTAssertTrue(WorkoutTimer.isExpired(state, asOf: date(400)))
    }

    func testIsExpiredAlwaysFalseWithNoTargetDuration() {
        let state = TimerState(startedAt: date(0))
        XCTAssertFalse(WorkoutTimer.isExpired(state, asOf: date(999_999)))
    }

    // MARK: - Pause / resume

    func testPauseIsANoOpWhenAlreadyPaused() {
        let state = TimerState(startedAt: date(0), pausedAt: date(10))
        let paused = WorkoutTimer.pause(state, asOf: date(20))
        XCTAssertEqual(paused.pausedAt, date(10), "never double-pauses or moves the pause timestamp")
    }

    func testResumeFoldsThePauseDurationIntoAccumulatedPauseSeconds() {
        let state = TimerState(startedAt: date(0), pausedAt: date(10))
        let resumed = WorkoutTimer.resume(state, asOf: date(40))
        XCTAssertNil(resumed.pausedAt)
        XCTAssertEqual(resumed.accumulatedPauseSeconds, 30)
    }

    func testResumeIsANoOpWhenNotPaused() {
        let state = TimerState(startedAt: date(0), accumulatedPauseSeconds: 15)
        let resumed = WorkoutTimer.resume(state, asOf: date(40))
        XCTAssertEqual(resumed, state)
    }

    func testPausedTimerNeverAdvancesElapsedTimeUntilResumed() {
        var state = WorkoutTimer.start(asOf: date(0), targetDurationSeconds: 180)
        state = WorkoutTimer.pause(state, asOf: date(30))
        let elapsedWhilePaused1 = WorkoutTimer.elapsedSeconds(state, asOf: date(60))
        let elapsedWhilePaused2 = WorkoutTimer.elapsedSeconds(state, asOf: date(120))
        XCTAssertEqual(elapsedWhilePaused1, elapsedWhilePaused2, "elapsed time is frozen while paused")
    }

    // MARK: - Relaunch/catch-up unit-index derivation (§1c)

    func testCurrentUnitIndexDerivesDeterministicallyFromElapsedTime() {
        // EMOM 12: 12 units, 60s each. App closed at minute 4 (index 3),
        // reopened when 8.5 minutes have elapsed -> should land on index 8.
        let state = TimerState(startedAt: date(0))
        let index = WorkoutTimer.currentUnitIndex(asOf: date(510), state: state, unitDurationSeconds: 60, totalUnits: 12)
        XCTAssertEqual(index, 8)
    }

    func testCurrentUnitIndexNeverReplaysThroughIntermediateUnits() {
        let state = TimerState(startedAt: date(0))
        // Directly jumping from t=0 to deep into the timeline must land on
        // the correct final index in one step, not iterate through 0...N.
        let index = WorkoutTimer.currentUnitIndex(asOf: date(719), state: state, unitDurationSeconds: 60, totalUnits: 12)
        XCTAssertEqual(index, 11)
    }

    func testCurrentUnitIndexClampsToTheLastValidUnitWhenElapsedExceedsTotal() {
        let state = TimerState(startedAt: date(0))
        let index = WorkoutTimer.currentUnitIndex(asOf: date(10_000), state: state, unitDurationSeconds: 60, totalUnits: 12)
        XCTAssertEqual(index, 11)
    }

    func testCurrentUnitIndexIsZeroBeforeTheFirstUnitElapses() {
        let state = TimerState(startedAt: date(0))
        let index = WorkoutTimer.currentUnitIndex(asOf: date(5), state: state, unitDurationSeconds: 60, totalUnits: 12)
        XCTAssertEqual(index, 0)
    }

    // MARK: - Determinism

    func testSameInputsAlwaysProduceTheSameOutput() {
        let state = TimerState(startedAt: date(0), accumulatedPauseSeconds: 12, targetDurationSeconds: 300, currentUnitIndex: 2)
        let firstElapsed = WorkoutTimer.elapsedSeconds(state, asOf: date(200))
        let secondElapsed = WorkoutTimer.elapsedSeconds(state, asOf: date(200))
        XCTAssertEqual(firstElapsed, secondElapsed)
    }
}
