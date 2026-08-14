import XCTest
@testable import TrainingOS

final class ScoringEngineTests: XCTestCase {
    func testHigherIsBetterIsAPRWithNoExistingRecord() {
        XCTAssertTrue(ScoringEngine.isNewPersonalRecord(candidateValue: 100, direction: .higherIsBetter, existingBest: nil))
    }

    func testHigherIsBetterRequiresStrictImprovement() {
        let existing = PersonalRecord(value: 100, scoringDirection: .higherIsBetter)
        XCTAssertFalse(ScoringEngine.isNewPersonalRecord(candidateValue: 100, direction: .higherIsBetter, existingBest: existing))
        XCTAssertTrue(ScoringEngine.isNewPersonalRecord(candidateValue: 100.5, direction: .higherIsBetter, existingBest: existing))
    }

    func testLowerIsBetterForATimedBenchmark() {
        let existing = PersonalRecord(value: 300, scoringDirection: .lowerIsBetter)
        XCTAssertTrue(ScoringEngine.isNewPersonalRecord(candidateValue: 245, direction: .lowerIsBetter, existingBest: existing))
        XCTAssertFalse(ScoringEngine.isNewPersonalRecord(candidateValue: 310, direction: .lowerIsBetter, existingBest: existing))
    }

    func testNoneAndCompletionBasedAreNeverPersonalRecords() {
        XCTAssertFalse(ScoringEngine.isNewPersonalRecord(candidateValue: 999, direction: .completionBased, existingBest: nil))
        XCTAssertFalse(ScoringEngine.isNewPersonalRecord(candidateValue: 999, direction: .none, existingBest: nil))
    }

    func testRxAndScaledResultsNeverCompeteForTheSameRecord() {
        let rxRecord = PersonalRecord(value: 200, scoringDirection: .higherIsBetter, context: .rx)
        let scaledRecord = PersonalRecord(value: 50, scoringDirection: .higherIsBetter, context: .scaled)

        let bestScaled = ScoringEngine.bestRecord(among: [rxRecord, scaledRecord], context: .scaled, repBand: nil)
        XCTAssertEqual(bestScaled?.value, 50)

        let bestRx = ScoringEngine.bestRecord(among: [rxRecord, scaledRecord], context: .rx, repBand: nil)
        XCTAssertEqual(bestRx?.value, 200)
    }
}
