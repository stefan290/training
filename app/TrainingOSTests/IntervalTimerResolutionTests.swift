import XCTest
@testable import TrainingOS

/// Pure, deterministic tests for `IntervalTimerResolution` — the
/// alternating-work/recovery timer derivation Part I's auto-progressing
/// interval screen relies on. Every case is expressed purely as
/// elapsed-seconds-in -> leg-out, matching this project's "recompute from
/// a persisted timestamp, never replay" discipline (CLAUDE.md rule 21).
final class IntervalTimerResolutionTests: XCTestCase {
    /// 6 x (30s work / 15s recovery).
    private let workDuration = 30
    private let recoveryDuration = 15
    private let intervalCount = 6

    func testEarlyInFirstWorkLegReportsCorrectRemaining() {
        let position = IntervalTimerResolution.resolve(
            elapsedSeconds: 10, workDurationSeconds: workDuration, recoveryDurationSeconds: recoveryDuration, intervalCount: intervalCount
        )
        XCTAssertEqual(position.legIndex, 0)
        XCTAssertTrue(position.isWork)
        XCTAssertEqual(position.intervalNumber, 1)
        XCTAssertEqual(position.remainingInLegSeconds, 20, accuracy: 0.001)
        XCTAssertFalse(position.isSessionComplete)
    }

    func testExactlyAtWorkBoundaryTransitionsToRecovery() {
        let position = IntervalTimerResolution.resolve(
            elapsedSeconds: 30, workDurationSeconds: workDuration, recoveryDurationSeconds: recoveryDuration, intervalCount: intervalCount
        )
        XCTAssertEqual(position.legIndex, 1)
        XCTAssertFalse(position.isWork)
        XCTAssertEqual(position.intervalNumber, 1)
        XCTAssertEqual(position.remainingInLegSeconds, 15, accuracy: 0.001)
    }

    func testAfterFirstRecoveryAdvancesToSecondWorkInterval() {
        let position = IntervalTimerResolution.resolve(
            elapsedSeconds: 45, workDurationSeconds: workDuration, recoveryDurationSeconds: recoveryDuration, intervalCount: intervalCount
        )
        XCTAssertEqual(position.legIndex, 2)
        XCTAssertTrue(position.isWork)
        XCTAssertEqual(position.intervalNumber, 2)
        XCTAssertEqual(position.remainingInLegSeconds, 30, accuracy: 0.001)
    }

    /// A relaunch long after backgrounding jumps straight to the correct
    /// leg — never replays every leg in between.
    func testLongBackgroundGapJumpsDirectlyToCorrectLegWithoutReplay() {
        // Cycle length = 45s. Elapsed 200s = 4 full cycles (180s) + 20s
        // into the 5th work leg (interval 5).
        let position = IntervalTimerResolution.resolve(
            elapsedSeconds: 200, workDurationSeconds: workDuration, recoveryDurationSeconds: recoveryDuration, intervalCount: intervalCount
        )
        XCTAssertEqual(position.legIndex, 8)
        XCTAssertTrue(position.isWork)
        XCTAssertEqual(position.intervalNumber, 5)
        XCTAssertEqual(position.remainingInLegSeconds, 10, accuracy: 0.001)
        XCTAssertFalse(position.isSessionComplete)
    }

    func testElapsedPastTheEntireSequenceReportsSessionCompleteClampedToFinalLeg() {
        let position = IntervalTimerResolution.resolve(
            elapsedSeconds: 10_000, workDurationSeconds: workDuration, recoveryDurationSeconds: recoveryDuration, intervalCount: intervalCount
        )
        XCTAssertTrue(position.isSessionComplete)
        XCTAssertEqual(position.legIndex, intervalCount * 2 - 2)
        XCTAssertEqual(position.remainingInLegSeconds, 0)
    }

    func testZeroIntervalCountDegradesGracefullyWithoutCrashing() {
        let position = IntervalTimerResolution.resolve(
            elapsedSeconds: 10, workDurationSeconds: workDuration, recoveryDurationSeconds: recoveryDuration, intervalCount: 0
        )
        XCTAssertEqual(position.legIndex, 0)
        XCTAssertTrue(position.isWork)
    }

    /// Same inputs must always produce the same output — no reliance on
    /// wall-clock reads inside the function itself.
    func testResolutionIsDeterministic() {
        let first = IntervalTimerResolution.resolve(
            elapsedSeconds: 77, workDurationSeconds: workDuration, recoveryDurationSeconds: recoveryDuration, intervalCount: intervalCount
        )
        let second = IntervalTimerResolution.resolve(
            elapsedSeconds: 77, workDurationSeconds: workDuration, recoveryDurationSeconds: recoveryDuration, intervalCount: intervalCount
        )
        XCTAssertEqual(first, second)
    }
}
