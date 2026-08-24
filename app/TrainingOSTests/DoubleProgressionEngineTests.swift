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

    /// Stage 10B.6 revision: reaching the top of the range only by working
    /// HARDER than the target RIR (0 actual vs. 2 target) is no longer
    /// folded into the generic "on track, progress reps" `.repIncrease` —
    /// it's a plain `.hold`, since it isn't on-track performance at the
    /// intended effort (`STAGE10B6_HYPERTROPHY_PRESCRIPTION_REDESIGN.md`
    /// §6a step 6).
    func testTopOfRangeButHarderThanTargetRIRDoesNotCountAsLoadIncrease() {
        let targets = [SetTarget(repRangeLow: 8, repRangeHigh: 12, targetRir: 2)]
        let results = [SetOutcome(reps: 12, actualRir: 0)]
        let input = ProgressionInput(targets: targets, latestResults: results, hasUsableHistory: true, equipmentIncrement: 2.5, lastKnownWeight: 60)
        let output = engine.recommend(input)
        XCTAssertEqual(output.reasonCode, .hold)
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

    // MARK: - Stage 10B.6: performance-qualified load progression decision table
    // (STAGE10B6_HYPERTROPHY_PRESCRIPTION_REDESIGN.md §6a/§6b) — 5-10 reps
    // @ target 2 RIR, cases A-I exactly as approved.

    private func target5to10rir2() -> [SetTarget] { Array(repeating: SetTarget(repRangeLow: 5, repRangeHigh: 10, targetRir: 2), count: 3) }

    func testCaseA_10_10_10at2RIR_increasesLoad() {
        let results = Array(repeating: SetOutcome(reps: 10, actualRir: 2), count: 3)
        let output = engine.recommend(ProgressionInput(
            targets: target5to10rir2(), latestResults: results, hasUsableHistory: true, equipmentIncrement: 2.5, lastKnownWeight: 100
        ))
        XCTAssertEqual(output.reasonCode, .loadIncrease)
        XCTAssertEqual(output.recommendedWeight, 102.5)
    }

    func testCaseB_8_8_8at2RIR_holdsAndProgressesReps() {
        let results = Array(repeating: SetOutcome(reps: 8, actualRir: 2), count: 3)
        let output = engine.recommend(ProgressionInput(
            targets: target5to10rir2(), latestResults: results, hasUsableHistory: true, equipmentIncrement: 2.5, lastKnownWeight: 100
        ))
        XCTAssertEqual(output.reasonCode, .repIncrease)
        XCTAssertEqual(output.recommendedWeight, 100)
    }

    /// The case product decision D-10B6-3 was specifically written around:
    /// not at the ceiling, but with materially more reserve than
    /// prescribed — this still qualifies as strong performance.
    func testCaseC_8_8_8at4RIR_qualifiesForIncreaseViaRirSurplus() {
        let results = Array(repeating: SetOutcome(reps: 8, actualRir: 4), count: 3)
        let output = engine.recommend(ProgressionInput(
            targets: target5to10rir2(), latestResults: results, hasUsableHistory: true, equipmentIncrement: 2.5, lastKnownWeight: 100
        ))
        XCTAssertEqual(output.reasonCode, .loadIncrease)
        XCTAssertEqual(output.recommendedWeight, 102.5)
    }

    func testCaseD_6_6_6at2RIR_holdsAndProgressesReps() {
        let results = Array(repeating: SetOutcome(reps: 6, actualRir: 2), count: 3)
        let output = engine.recommend(ProgressionInput(
            targets: target5to10rir2(), latestResults: results, hasUsableHistory: true, equipmentIncrement: 2.5, lastKnownWeight: 100
        ))
        XCTAssertEqual(output.reasonCode, .repIncrease)
        XCTAssertEqual(output.recommendedWeight, 100)
    }

    /// Met the bottom of the range only by working harder than the
    /// target RIR allowed — plain HOLD, not credited as on-track.
    func testCaseE_5_5_5at1RIR_holds() {
        let results = Array(repeating: SetOutcome(reps: 5, actualRir: 1), count: 3)
        let output = engine.recommend(ProgressionInput(
            targets: target5to10rir2(), latestResults: results, hasUsableHistory: true, equipmentIncrement: 2.5, lastKnownWeight: 100
        ))
        XCTAssertEqual(output.reasonCode, .hold)
        XCTAssertEqual(output.recommendedWeight, 100)
    }

    func testCaseF_oneSetBelowMinimum_firstExposure_holds() {
        var results = Array(repeating: SetOutcome(reps: 8, actualRir: 2), count: 3)
        results[2] = SetOutcome(reps: 4, actualRir: 2)
        let output = engine.recommend(ProgressionInput(
            targets: target5to10rir2(), latestResults: results, hasUsableHistory: true, equipmentIncrement: 2.5, lastKnownWeight: 100
            // No previousTargets/previousResults supplied — no confirmed repeat, so REGRESS cannot fire.
        ))
        XCTAssertEqual(output.reasonCode, .hold)
        XCTAssertEqual(output.recommendedWeight, 100)
    }

    func testCaseG_oneSetSkipped_countMismatch_holds() {
        let results = Array(repeating: SetOutcome(reps: 8, actualRir: 2), count: 2) // 2 results for 3 prescribed sets
        let output = engine.recommend(ProgressionInput(
            targets: target5to10rir2(), latestResults: results, hasUsableHistory: true, equipmentIncrement: 2.5, lastKnownWeight: 100
        ))
        XCTAssertEqual(output.reasonCode, .hold)
        XCTAssertEqual(output.recommendedWeight, 100)
    }

    /// Strong performance (case C's own numbers), but the next available
    /// equipment increment is disproportionately large at this weight —
    /// the guard blocks the jump, not the credit.
    func testCaseH_strongPerformanceButOversizedIncrement_holdsAndProgressesReps() {
        let results = Array(repeating: SetOutcome(reps: 10, actualRir: 2), count: 3)
        let output = engine.recommend(ProgressionInput(
            targets: target5to10rir2(), latestResults: results, hasUsableHistory: true, equipmentIncrement: 15, lastKnownWeight: 100
        ))
        XCTAssertEqual(output.reasonCode, .repIncrease)
        XCTAssertEqual(output.recommendedWeight, 100)
    }

    /// Below-minimum performance for two consecutive valid exposures —
    /// regresses by exactly one equipment increment.
    func testCaseI_twoConsecutiveMisses_regressesByOneIncrement() {
        var results = Array(repeating: SetOutcome(reps: 8, actualRir: 2), count: 3)
        results[2] = SetOutcome(reps: 4, actualRir: 2)
        let output = engine.recommend(ProgressionInput(
            targets: target5to10rir2(), latestResults: results, hasUsableHistory: true, equipmentIncrement: 2.5, lastKnownWeight: 100,
            previousTargets: target5to10rir2(), previousResults: results
        ))
        XCTAssertEqual(output.reasonCode, .loadDecrease)
        XCTAssertEqual(output.recommendedWeight, 97.5)
    }

    // MARK: - Additional required boundary tests

    func testRirSurplusOfOneDoesNotQualifyForTheIncreasePath() {
        let results = Array(repeating: SetOutcome(reps: 8, actualRir: 3), count: 3) // surplus = 1
        let output = engine.recommend(ProgressionInput(
            targets: target5to10rir2(), latestResults: results, hasUsableHistory: true, equipmentIncrement: 2.5, lastKnownWeight: 100
        ))
        XCTAssertEqual(output.reasonCode, .repIncrease)
        XCTAssertEqual(output.recommendedWeight, 100)
    }

    func testRirSurplusOfTwoDoesQualifyForTheIncreasePath() {
        let results = Array(repeating: SetOutcome(reps: 8, actualRir: 4), count: 3) // surplus = 2
        let output = engine.recommend(ProgressionInput(
            targets: target5to10rir2(), latestResults: results, hasUsableHistory: true, equipmentIncrement: 2.5, lastKnownWeight: 100
        ))
        XCTAssertEqual(output.reasonCode, .loadIncrease)
    }

    func testExactlyTenPercentIncrementIsAllowed() {
        let results = Array(repeating: SetOutcome(reps: 10, actualRir: 2), count: 3)
        let output = engine.recommend(ProgressionInput(
            targets: target5to10rir2(), latestResults: results, hasUsableHistory: true, equipmentIncrement: 10, lastKnownWeight: 100
        ))
        XCTAssertEqual(output.reasonCode, .loadIncrease)
        XCTAssertEqual(output.recommendedWeight, 110)
    }

    func testOverTenPercentIncrementIsBlocked() {
        let results = Array(repeating: SetOutcome(reps: 10, actualRir: 2), count: 3)
        let output = engine.recommend(ProgressionInput(
            targets: target5to10rir2(), latestResults: results, hasUsableHistory: true, equipmentIncrement: 10.01, lastKnownWeight: 100
        ))
        XCTAssertEqual(output.reasonCode, .repIncrease)
        XCTAssertEqual(output.recommendedWeight, 100)
    }

    /// A single miss with no confirmed repeat never regresses — only two
    /// in a row does (distinguishes case F from case I).
    func testASingleMissNeverRegressesEvenWithPriorDataSupplied() {
        var results = Array(repeating: SetOutcome(reps: 8, actualRir: 2), count: 3)
        results[2] = SetOutcome(reps: 4, actualRir: 2)
        let previousResults = Array(repeating: SetOutcome(reps: 8, actualRir: 2), count: 3) // previous exposure was fine
        let output = engine.recommend(ProgressionInput(
            targets: target5to10rir2(), latestResults: results, hasUsableHistory: true, equipmentIncrement: 2.5, lastKnownWeight: 100,
            previousTargets: target5to10rir2(), previousResults: previousResults
        ))
        XCTAssertEqual(output.reasonCode, .hold)
        XCTAssertEqual(output.recommendedWeight, 100)
    }

    func testRegressNeverProducesANegativeLoad() {
        var results = Array(repeating: SetOutcome(reps: 8, actualRir: 2), count: 3)
        results[2] = SetOutcome(reps: 4, actualRir: 2)
        let output = engine.recommend(ProgressionInput(
            targets: target5to10rir2(), latestResults: results, hasUsableHistory: true, equipmentIncrement: 2.5, lastKnownWeight: 1,
            previousTargets: target5to10rir2(), previousResults: results
        ))
        XCTAssertEqual(output.reasonCode, .loadDecrease)
        XCTAssertGreaterThanOrEqual(output.recommendedWeight ?? -1, 0)
    }
}
