import XCTest
@testable import TrainingOS

/// Deterministic coverage for `FunctionalFitnessScoring.scoreDirection` —
/// the one piece of scoring vocabulary a live, non-benchmark Functional
/// Fitness execution has no authored source for (`ScoreType` itself
/// always comes from `Stimulus.scoreType`, never re-derived).
final class FunctionalFitnessScoringTests: XCTestCase {
    func testAMRAPIsHigherIsBetter() {
        XCTAssertEqual(FunctionalFitnessScoring.scoreDirection(for: .amrap(capSeconds: 600)), .higherIsBetter)
    }

    func testForTimeChipperAndLadderAreLowerIsBetter() {
        XCTAssertEqual(FunctionalFitnessScoring.scoreDirection(for: .forTime(capSeconds: nil)), .lowerIsBetter)
        XCTAssertEqual(FunctionalFitnessScoring.scoreDirection(for: .chipper(capSeconds: nil)), .lowerIsBetter)
        XCTAssertEqual(FunctionalFitnessScoring.scoreDirection(for: .ladder(direction: .ascending, capSeconds: nil)), .lowerIsBetter)
    }

    func testRoundsForTimeIsLowerIsBetter() {
        XCTAssertEqual(FunctionalFitnessScoring.scoreDirection(for: .roundsForTime(rounds: 5, capSeconds: 1200)), .lowerIsBetter)
    }

    func testMaxLoadAndMaxRepsAreHigherIsBetter() {
        XCTAssertEqual(FunctionalFitnessScoring.scoreDirection(for: .maxLoad), .higherIsBetter)
        XCTAssertEqual(FunctionalFitnessScoring.scoreDirection(for: .maxReps(capSeconds: 60)), .higherIsBetter)
    }

    func testEmomAndIntervalsAreHigherIsBetter() {
        XCTAssertEqual(FunctionalFitnessScoring.scoreDirection(for: .emom(intervalSeconds: 60, totalSeconds: 720)), .higherIsBetter)
        XCTAssertEqual(FunctionalFitnessScoring.scoreDirection(for: .intervals(count: 5, workSeconds: 40, restSeconds: 20)), .higherIsBetter)
    }

    /// Same input always produces the same output — no hidden state.
    func testDeterministic() {
        let first = FunctionalFitnessScoring.scoreDirection(for: .forTime(capSeconds: 900))
        let second = FunctionalFitnessScoring.scoreDirection(for: .forTime(capSeconds: 900))
        XCTAssertEqual(first, second)
    }
}
