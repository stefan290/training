import XCTest
@testable import TrainingOS

/// `SessionExecutionState` is the only place deciding which logged
/// results are worth carrying to the completion screen — an ordinary
/// logged set is not a "highlight," only a PR or a first-ever entry is.
final class SessionExecutionStateTests: XCTestCase {
    private func highlight(isPersonalRecord: Bool = false, isFirstEverEntry: Bool = false) -> LoggedResultHighlight {
        LoggedResultHighlight(label: "Back Squat", value: "100 kg x 5", isPersonalRecord: isPersonalRecord, isFirstEverEntry: isFirstEverEntry)
    }

    func testOrdinaryLoggedResultIsNeverRecordedAsAHighlight() {
        let state = SessionExecutionState()
        state.record(highlight())
        XCTAssertTrue(state.highlights.isEmpty)
    }

    func testPersonalRecordIsRecorded() {
        let state = SessionExecutionState()
        state.record(highlight(isPersonalRecord: true))
        XCTAssertEqual(state.highlights.count, 1)
    }

    func testFirstEverEntryIsRecorded() {
        let state = SessionExecutionState()
        state.record(highlight(isFirstEverEntry: true))
        XCTAssertEqual(state.highlights.count, 1)
    }

    func testNilHighlightIsIgnored() {
        let state = SessionExecutionState()
        state.record(nil)
        XCTAssertTrue(state.highlights.isEmpty)
    }

    /// Multiple blocks across one Session all accumulate into the same
    /// list, in the order they happened.
    func testHighlightsFromMultipleBlocksAccumulateInOrder() {
        let state = SessionExecutionState()
        state.record(highlight(isPersonalRecord: true))
        state.record(highlight())
        state.record(highlight(isFirstEverEntry: true))
        XCTAssertEqual(state.highlights.count, 2)
    }
}
