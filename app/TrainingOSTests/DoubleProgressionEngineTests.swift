import XCTest
@testable import TrainingOS

/// Table-driven cases at the boundaries called out in handoff section 16:
/// exactly at the top of the range, mixed sets, a single below-range set,
/// and missing history. Same inputs must always produce the same output.
final class DoubleProgressionEngineTests: XCTestCase {
    let engine = DoubleProgressionEngine()

    func testNoUsableHistoryRequiresCalibration() {
        let input = ProgressionInput(targets: [], latestResults: [], hasUsableHistory: false, equipmentIncrement: 2.5, lastKnownWeight: nil)
        let output = engine.recommend(input)
        XCTAssertEqual(output.reasonCode, .calibrationRequired)
        XCTAssertNil(output.recommendedWeight)
        XCTAssertEqual(output.confidence, 0)
    }

    func testEverySetAtTopOfRangeAtOrAboveTargetRIRIncreasesLoad() {
        let targets = [
            SetTarget(repRangeLow: 8, repRangeHigh: 12, targetRir: 2),
            SetTarget(repRangeLow: 8, repRangeHigh: 12, targetRir: 2),
        ]
        let results = [
            SetOutcome(reps: 12, actualRir: 2),
            SetOutcome(reps: 12, actualRir: 3),
        ]
        let input = ProgressionInput(targets: targets, latestResults: results, hasUsableHistory: true, equipmentIncrement: 2.5, lastKnownWeight: 60)
        let output = engine.recommend(input)
        XCTAssertEqual(output.reasonCode, .loadIncrease)
        XCTAssertEqual(output.recommendedWeight, 62.5)
    }

    func testMixedSetsWithinRangeHoldLoadAndAdvanceReps() {
        let targets = [
            SetTarget(repRangeLow: 8, repRangeHigh: 12, targetRir: 2),
            SetTarget(repRangeLow: 8, repRangeHigh: 12, targetRir: 2),
        ]
        let results = [
            SetOutcome(reps: 12, actualRir: 2),
            SetOutcome(reps: 9, actualRir: 2),
        ]
        let input = ProgressionInput(targets: targets, latestResults: results, hasUsableHistory: true, equipmentIncrement: 2.5, lastKnownWeight: 60)
        let output = engine.recommend(input)
        XCTAssertEqual(output.reasonCode, .repIncrease)
        XCTAssertEqual(output.recommendedWeight, 60)
    }

    func testASingleBelowRangeSetHoldsThePrescription() {
        let targets = [
            SetTarget(repRangeLow: 8, repRangeHigh: 12, targetRir: 2),
            SetTarget(repRangeLow: 8, repRangeHigh: 12, targetRir: 2),
        ]
        let results = [
            SetOutcome(reps: 12, actualRir: 2),
            SetOutcome(reps: 6, actualRir: 1),
        ]
        let input = ProgressionInput(targets: targets, latestResults: results, hasUsableHistory: true, equipmentIncrement: 2.5, lastKnownWeight: 60)
        let output = engine.recommend(input)
        XCTAssertEqual(output.reasonCode, .hold)
        XCTAssertEqual(output.recommendedWeight, 60)
    }

    func testTopOfRangeButHarderThanTargetRIRDoesNotCountAsLoadIncrease() {
        let targets = [SetTarget(repRangeLow: 8, repRangeHigh: 12, targetRir: 2)]
        let results = [SetOutcome(reps: 12, actualRir: 0)]
        let input = ProgressionInput(targets: targets, latestResults: results, hasUsableHistory: true, equipmentIncrement: 2.5, lastKnownWeight: 60)
        let output = engine.recommend(input)
        XCTAssertEqual(output.reasonCode, .repIncrease)
        XCTAssertEqual(output.recommendedWeight, 60)
    }

    func testMismatchedResultCountHoldsConservativelyRatherThanGuessing() {
        let targets = [SetTarget(repRangeLow: 8, repRangeHigh: 12, targetRir: 2)]
        let input = ProgressionInput(targets: targets, latestResults: [], hasUsableHistory: true, equipmentIncrement: 2.5, lastKnownWeight: 60)
        let output = engine.recommend(input)
        XCTAssertEqual(output.reasonCode, .hold)
        XCTAssertEqual(output.recommendedWeight, 60)
    }

    func testSameInputsAlwaysProduceTheSameOutput() {
        let targets = [SetTarget(repRangeLow: 8, repRangeHigh: 12, targetRir: 2)]
        let results = [SetOutcome(reps: 12, actualRir: 2)]
        let input = ProgressionInput(targets: targets, latestResults: results, hasUsableHistory: true, equipmentIncrement: 2.5, lastKnownWeight: 60)
        XCTAssertEqual(engine.recommend(input), engine.recommend(input))
    }
}
