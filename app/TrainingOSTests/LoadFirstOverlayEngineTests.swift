import XCTest
@testable import TrainingOS

/// Stage 10R.5: proves `LoadFirstOverlayEngine`'s pure classification and
/// recommendation logic against the locked decision table
/// (`STAGE10R5_LOAD_FIRST_PROGRESSION_OVERLAY_DESIGN.md`, D-10R5-2
/// through D-10R5-9). Pure engine, no SwiftData — every case constructs
/// its inputs directly.
final class LoadFirstOverlayEngineTests: XCTestCase {
    // MARK: Classification (D-10R5-2/3)

    func testAllSetsAtTargetIsMatched() {
        XCTAssertEqual(LoadFirstOverlayEngine.classify(surpluses: [0, 0, 0]), .matched)
    }

    /// D-10R5-3's own worked example: target RIR 3, actual 5/5/5 (surplus
    /// 2/2/2) — strong evidence the load is too light.
    func testAllSetsTwoOrMoreAboveTargetIsConsistentlyEasy() {
        XCTAssertEqual(LoadFirstOverlayEngine.classify(surpluses: [2, 2, 2]), .consistentlyEasy)
    }

    /// D-10R5-3's own worked example: 5/5/2 at target 3 (surplus 2/2/-1)
    /// — NOT easy, because one set was harder than prescribed. The
    /// "no set below target may qualify as easy" veto.
    func testOneSetBelowTargetVetoesConsistentlyEasy() {
        let classification = LoadFirstOverlayEngine.classify(surpluses: [2, 2, -1])
        XCTAssertNotEqual(classification, .consistentlyEasy)
    }

    func testWorstSetAtOrBelowNegativeThresholdIsTooHard() {
        XCTAssertEqual(LoadFirstOverlayEngine.classify(surpluses: [-2, -2, -2]), .tooHard)
        XCTAssertEqual(LoadFirstOverlayEngine.classify(surpluses: [0, 0, -2]), .tooHard, "a single set at -2 is meaningful evidence, even alongside matched sets")
    }

    func testMixedButNotAlarmingIsInconsistent() {
        // Every set >= 0 (no veto), but average surplus below the
        // meaningful threshold — not easy, not hard, not perfectly matched.
        XCTAssertEqual(LoadFirstOverlayEngine.classify(surpluses: [1, 0, 1]), .inconsistent)
    }

    func testAverageAloneNeverManufacturesEasyWhenAnySetIsBelowTarget() {
        // Average of [4, 4, -4] is +1.33, nowhere near easy once computed
        // correctly, but this specifically proves the veto fires even
        // when a naive average might otherwise look borderline.
        let classification = LoadFirstOverlayEngine.classify(surpluses: [4, 4, -4])
        XCTAssertNotEqual(classification, .consistentlyEasy)
    }

    // MARK: recommend() — D-10R5-5's exact precedence

    /// Test 1: matched RIR → source next load.
    func testMatchedPerformanceAcceptsSourceNextLoad() {
        let result = LoadFirstOverlayEngine.recommend(
            sourceWeight: 90, previousEffectiveWeight: 85, isDeloadWeek: false,
            recentEligibleExposureSurpluses: [[0, 0, 0]], equipmentIncrement: 2.5
        )
        XCTAssertEqual(result.finalWeight, 90, accuracy: 0.001)
        XCTAssertEqual(result.sourceWeight, 90, accuracy: 0.001)
        XCTAssertEqual(result.reasonCode, .holdMatchedTarget)
    }

    /// Test 2: +2 easy RIR across all sets → source next load + one increment.
    func testConsistentlyEasyAcceleratesOneIncrementAboveSource() {
        let result = LoadFirstOverlayEngine.recommend(
            sourceWeight: 90, previousEffectiveWeight: 85, isDeloadWeek: false,
            recentEligibleExposureSurpluses: [[2, 2, 2]], equipmentIncrement: 2.5
        )
        XCTAssertEqual(result.finalWeight, 92.5, accuracy: 0.001)
        XCTAssertEqual(result.reasonCode, .loadIncreaseEasyPerformance)
    }

    /// Test 3: one set below target → no acceleration.
    func testOneSetBelowTargetDoesNotAccelerate() {
        let result = LoadFirstOverlayEngine.recommend(
            sourceWeight: 90, previousEffectiveWeight: 85, isDeloadWeek: false,
            recentEligibleExposureSurpluses: [[2, 2, -1]], equipmentIncrement: 2.5
        )
        XCTAssertEqual(result.finalWeight, 90, accuracy: 0.001, "source's own next value stands, unchanged")
        XCTAssertNotEqual(result.reasonCode, .loadIncreaseEasyPerformance)
    }

    /// Test 4: first hard exposure → hold at the previous reference
    /// weight, not the source's fresh scheduled value.
    func testFirstHardExposureHoldsAtPreviousReferenceWeight() {
        let result = LoadFirstOverlayEngine.recommend(
            sourceWeight: 90, previousEffectiveWeight: 85, isDeloadWeek: false,
            recentEligibleExposureSurpluses: [[-2, -2, -2]], equipmentIncrement: 2.5
        )
        XCTAssertEqual(result.finalWeight, 85, accuracy: 0.001, "holds at 85 (the actual reference weight), never jumps to source's fresh 90")
        XCTAssertEqual(result.reasonCode, .holdMatchedTarget)
    }

    /// Test 5: second consecutive hard exposure → regress one increment
    /// from the previous reference weight.
    func testSecondConsecutiveHardExposureRegressesOneIncrement() {
        let result = LoadFirstOverlayEngine.recommend(
            sourceWeight: 90, previousEffectiveWeight: 85, isDeloadWeek: false,
            recentEligibleExposureSurpluses: [[-2, -2, -2], [-3, -2, -2]], equipmentIncrement: 2.5
        )
        XCTAssertEqual(result.finalWeight, 82.5, accuracy: 0.001)
        XCTAssertEqual(result.reasonCode, .loadDecreaseRepeatedHardPerformance)
    }

    /// D-10R5-9: the hard streak resets on any eligible non-hard exposure
    /// — a hard exposure preceded by a MATCHED one must hold, not regress.
    func testHardStreakResetsAfterAnEligibleNonHardExposure() {
        let result = LoadFirstOverlayEngine.recommend(
            sourceWeight: 90, previousEffectiveWeight: 85, isDeloadWeek: false,
            recentEligibleExposureSurpluses: [[-2, -2, -2], [0, 0, 0]], equipmentIncrement: 2.5
        )
        XCTAssertEqual(result.reasonCode, .holdMatchedTarget, "only the most recent is hard; the one before it was matched, so this is a first hard exposure again, not a repeat")
        XCTAssertEqual(result.finalWeight, 85, accuracy: 0.001)
    }

    /// Test 15: disproportionate equipment increment → hold, evidence not discarded.
    func testDisproportionateIncrementHoldsWithoutDiscardingEvidence() {
        // 20kg working weight, 2.5kg increment = 12.5%, above the 10% guard.
        let result = LoadFirstOverlayEngine.recommend(
            sourceWeight: 20, previousEffectiveWeight: 20, isDeloadWeek: false,
            recentEligibleExposureSurpluses: [[2, 2, 2]], equipmentIncrement: 2.5
        )
        XCTAssertEqual(result.finalWeight, 20, accuracy: 0.001, "held — the app must never invent a fractional load the equipment can't produce")
        XCTAssertEqual(result.reasonCode, .holdIncrementTooLarge)
    }

    func testProportionateIncrementIsNotBlocked() {
        // 100kg working weight, 2.5kg increment = 2.5%, well under the guard.
        let result = LoadFirstOverlayEngine.recommend(
            sourceWeight: 100, previousEffectiveWeight: 97.5, isDeloadWeek: false,
            recentEligibleExposureSurpluses: [[2, 2, 2]], equipmentIncrement: 2.5
        )
        XCTAssertEqual(result.finalWeight, 102.5, accuracy: 0.001)
        XCTAssertEqual(result.reasonCode, .loadIncreaseEasyPerformance)
    }

    /// Test 10: deload → source authority, unconditionally, regardless
    /// of how easy the (excluded) history looks.
    func testDeloadWeekIsSourceAuthorityRegardlessOfHistory() {
        let result = LoadFirstOverlayEngine.recommend(
            sourceWeight: 45, previousEffectiveWeight: 90, isDeloadWeek: true,
            recentEligibleExposureSurpluses: [[2, 2, 2]], equipmentIncrement: 2.5
        )
        XCTAssertEqual(result.finalWeight, 45, accuracy: 0.001)
        XCTAssertEqual(result.reasonCode, .deloadSourceAuthority)
    }

    func testNoEligibleExposureHoldsAtSourceWithInsufficientDataCode() {
        let result = LoadFirstOverlayEngine.recommend(
            sourceWeight: 90, previousEffectiveWeight: nil, isDeloadWeek: false,
            recentEligibleExposureSurpluses: [], equipmentIncrement: 2.5
        )
        XCTAssertEqual(result.finalWeight, 90, accuracy: 0.001)
        XCTAssertEqual(result.reasonCode, .holdInsufficientData)
    }

    /// Determinism (test 19, engine half): identical inputs always
    /// produce identical output — no randomness, no hidden clock read.
    func testRecommendIsDeterministic() {
        let inputs = (sourceWeight: 90.0, previousEffectiveWeight: 85.0, isDeloadWeek: false, exposures: [[2, 2, 2]], increment: 2.5)
        let first = LoadFirstOverlayEngine.recommend(sourceWeight: inputs.sourceWeight, previousEffectiveWeight: inputs.previousEffectiveWeight, isDeloadWeek: inputs.isDeloadWeek, recentEligibleExposureSurpluses: inputs.exposures, equipmentIncrement: inputs.increment)
        let second = LoadFirstOverlayEngine.recommend(sourceWeight: inputs.sourceWeight, previousEffectiveWeight: inputs.previousEffectiveWeight, isDeloadWeek: inputs.isDeloadWeek, recentEligibleExposureSurpluses: inputs.exposures, equipmentIncrement: inputs.increment)
        XCTAssertEqual(first, second)
    }
}
