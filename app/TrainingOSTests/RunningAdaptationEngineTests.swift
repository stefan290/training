import XCTest
@testable import TrainingOS

/// Running R2.6/Testing Q: pure in-workout adaptation rule tests, cited
/// against FAQ Endrance Running.docx's exact wording (re-verified via
/// `textutil` this pass) — rep-failure bands, worn-down bands, and the
/// whole-workout fallback.
final class RunningAdaptationEngineTests: XCTestCase {
    // MARK: Rep failure — "inability to complete a rep"

    func testRepFailureAtOrAboveOneHundredOnePercentFinishesAtBestEffort() {
        let (action, reason) = RunningAdaptationEngine.repFailureResponse(prescribedPercentOfThreshold: 1.01)
        XCTAssertEqual(action, .finishAtBestEffortThenExtraRest)
        XCTAssertEqual(reason, .repFailureAboveThreshold)
    }

    func testRepFailureWellAboveOneHundredOnePercentFinishesAtBestEffort() {
        let (action, _) = RunningAdaptationEngine.repFailureResponse(prescribedPercentOfThreshold: 1.10)
        XCTAssertEqual(action, .finishAtBestEffortThenExtraRest)
    }

    func testRepFailureBelowOneHundredPercentStopsAndWalks() {
        let (action, reason) = RunningAdaptationEngine.repFailureResponse(prescribedPercentOfThreshold: 0.95)
        XCTAssertEqual(action, .stopAndWalkThenResumeWhenConfident)
        XCTAssertEqual(reason, .repFailureBelowThreshold)
    }

    func testRepFailureInTheUnaddressedOneHundredToOneHundredOnePercentBandIsHonestlyAmbiguous() {
        // Genuine source ambiguity (R1/R2 instruction: do not invent an
        // answer) — the source gives an unconditional rule for "101% or
        // higher" and a separate unconditional rule for "anywhere under
        // 100%," and never addresses [100%, 101%) at all.
        let (action, reason) = RunningAdaptationEngine.repFailureResponse(prescribedPercentOfThreshold: 1.00)
        XCTAssertEqual(action, .sourceAmbiguousBandNotAddressed)
        XCTAssertEqual(reason, .repFailureSourceAmbiguousBand)

        let (action2, _) = RunningAdaptationEngine.repFailureResponse(prescribedPercentOfThreshold: 1.005)
        XCTAssertEqual(action2, .sourceAmbiguousBandNotAddressed)
    }

    // MARK: Worn-down bands

    func testAboveThresholdIntervalBandReducesVolumeNotIntensity() {
        let (action, reason) = RunningAdaptationEngine.wornDownResponse(prescribedPercentOfThreshold: 1.05, prescribedRPE: nil, canStillHoldPrescribedPace: true)
        XCTAssertEqual(action, .reduceVolumeNotIntensity)
        XCTAssertEqual(reason, .wornDownAboveThresholdInterval)
    }

    func testRPESevenOrHigherIsAboveThresholdIntervalBandEvenAtLowPercentThreshold() {
        // Source: "(>100% threshold pace OR a 7 out of 10 on the RPE
        // scale)" — an explicit alternative, not a conjunction.
        let (action, _) = RunningAdaptationEngine.wornDownResponse(prescribedPercentOfThreshold: 0.75, prescribedRPE: 7, canStillHoldPrescribedPace: true)
        XCTAssertEqual(action, .reduceVolumeNotIntensity)
    }

    func testThresholdBandAtNinetyHoldsOrShortensDistance() {
        let (action, reason) = RunningAdaptationEngine.wornDownResponse(prescribedPercentOfThreshold: 0.90, prescribedRPE: nil, canStillHoldPrescribedPace: true)
        XCTAssertEqual(action, .holdAtOrAboveNinetyPercentOrShortenDistance)
        XCTAssertEqual(reason, .wornDownThresholdBandHold)
    }

    func testThresholdBandAboveNinetyStrugglingSlowsWithinNinetyToNinetyFiveRange() {
        let (action, reason) = RunningAdaptationEngine.wornDownResponse(prescribedPercentOfThreshold: 0.98, prescribedRPE: nil, canStillHoldPrescribedPace: false)
        XCTAssertEqual(action, .slowWithinNinetyToNinetyFivePercentRange)
        XCTAssertEqual(reason, .wornDownThresholdBandSlowWithinRange)
    }

    func testThresholdBandAtExactlyOneHundredStillClassifiesAsThresholdBand() {
        let (action, _) = RunningAdaptationEngine.wornDownResponse(prescribedPercentOfThreshold: 1.00, prescribedRPE: nil, canStillHoldPrescribedPace: true)
        XCTAssertEqual(action, .holdAtOrAboveNinetyPercentOrShortenDistance)
    }

    func testMarathonPaceBandRunsToMarkThenWalkRecovers() {
        let (action, reason) = RunningAdaptationEngine.wornDownResponse(prescribedPercentOfThreshold: 0.85, prescribedRPE: nil, canStillHoldPrescribedPace: false)
        XCTAssertEqual(action, .runToMarkThenWalkRecoverAtLeast800Meters)
        XCTAssertEqual(reason, .wornDownMarathonPaceBand)
    }

    func testEightyPercentExactlyIsEasyBandNotMarathonBand() {
        // Source: marathon band is "80-90%", easy band is "80% threshold
        // pace or under" — 80% itself belongs to easy, per the easy
        // band's own inclusive wording.
        let (action, reason) = RunningAdaptationEngine.wornDownResponse(prescribedPercentOfThreshold: 0.80, prescribedRPE: nil, canStillHoldPrescribedPace: false)
        XCTAssertEqual(action, .slowByAnyAmount)
        XCTAssertEqual(reason, .wornDownEasyBand)
    }

    func testEasyBandBelowEightyPercentAlwaysAllowsSlowingByAnyAmount() {
        let (action, _) = RunningAdaptationEngine.wornDownResponse(prescribedPercentOfThreshold: 0.60, prescribedRPE: nil, canStillHoldPrescribedPace: false)
        XCTAssertEqual(action, .slowByAnyAmount)
    }

    // MARK: Whole-workout fallback — never silently mutates threshold

    func testLikelyFlukeYieldsPaceReductionOnlyNoThresholdRecommendation() {
        let (paceRange, thresholdRange, reason) = RunningAdaptationEngine.wholeWorkoutFallback(severity: .likelyFlukeNoFurtherAdjustment)
        XCTAssertEqual(paceRange, 0.05...0.10)
        XCTAssertNil(thresholdRange)
        XCTAssertEqual(reason, .wholeWorkoutFallbackPaceReduction)
    }

    func testFarOffWithNoExtenuatingCircumstanceRecommendsButDoesNotApplyAThresholdReduction() {
        let (paceRange, thresholdRange, reason) = RunningAdaptationEngine.wholeWorkoutFallback(severity: .farOffNoExtenuatingCircumstanceConsiderThresholdReduction)
        XCTAssertEqual(paceRange, 0.05...0.10)
        XCTAssertEqual(thresholdRange, 0.02...0.05)
        XCTAssertEqual(reason, .wholeWorkoutFallbackThresholdReductionRecommended)
        // This is a RECOMMENDATION only — the engine has no mutation
        // side-effect; only `RecordRunningThresholdCalibrationUseCase`
        // (an explicit, athlete-entered, gated write) can ever change a
        // stored threshold.
    }
}
