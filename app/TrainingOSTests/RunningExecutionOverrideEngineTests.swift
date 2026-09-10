import XCTest
@testable import TrainingOS

/// Running R2.5/Testing C-F: pure execution-override rule tests. The
/// most load-bearing regression suite in this checkpoint — this is
/// exactly where the original (miscorrected) R1 draft and the corrected
/// R1 draft disagree, so every test here is written against the
/// CORRECTED interpretation only: the ≤89% rule constrains ATHLETE
/// EXECUTION relative to that block's own prescribed intensity, never
/// what may be prescribed.
final class RunningExecutionOverrideEngineTests: XCTestCase {
    // MARK: C — ≤89% execution semantics

    func testEightyPercentPrescriptionRejectsAnEightyFivePercentOverrideAttempt() {
        let (decision, reason) = RunningExecutionOverrideEngine.evaluateIntensityOverride(
            prescribedPercentOfThreshold: 0.80, prescribedRPE: nil,
            requestedPercentOfThreshold: 0.85, repIndexZeroBased: 1
        )
        XCTAssertEqual(decision, .rejected)
        XCTAssertEqual(reason, .rejectedExceedsPrescribedAtOrBelow89Percent)
    }

    func testSixtyPercentPrescriptionRejectsAnyOverrideAttempt() {
        let (decision, reason) = RunningExecutionOverrideEngine.evaluateIntensityOverride(
            prescribedPercentOfThreshold: 0.60, prescribedRPE: nil,
            requestedPercentOfThreshold: 0.65, repIndexZeroBased: 2
        )
        XCTAssertEqual(decision, .rejected)
        XCTAssertEqual(reason, .rejectedExceedsPrescribedAtOrBelow89Percent)
    }

    func testEightyNinePercentExactlyStillRejectsAnOverride() {
        let (decision, reason) = RunningExecutionOverrideEngine.evaluateIntensityOverride(
            prescribedPercentOfThreshold: 0.89, prescribedRPE: nil,
            requestedPercentOfThreshold: 0.90, repIndexZeroBased: 1
        )
        XCTAssertEqual(decision, .rejected)
        XCTAssertEqual(reason, .rejectedExceedsPrescribedAtOrBelow89Percent)
    }

    // MARK: D — rep-1 override refusal (unconditional)

    func testRepOneNeverAllowsAnOverrideEvenAtHighIntensity() {
        let (decision, reason) = RunningExecutionOverrideEngine.evaluateIntensityOverride(
            prescribedPercentOfThreshold: 1.05, prescribedRPE: nil,
            requestedPercentOfThreshold: 1.10, repIndexZeroBased: 0
        )
        XCTAssertEqual(decision, .rejected)
        XCTAssertEqual(reason, .rejectedRepOne)
    }

    // MARK: E — ≤95% override refusal

    func testNinetyFivePercentExactlyRejectsAnOverride() {
        let (decision, reason) = RunningExecutionOverrideEngine.evaluateIntensityOverride(
            prescribedPercentOfThreshold: 0.95, prescribedRPE: nil,
            requestedPercentOfThreshold: 0.97, repIndexZeroBased: 2
        )
        XCTAssertEqual(decision, .rejected)
        XCTAssertEqual(reason, .rejectedAtOrBelow95PercentThreshold)
    }

    func testNinetyPercentRejectsAnOverride() {
        let (decision, reason) = RunningExecutionOverrideEngine.evaluateIntensityOverride(
            prescribedPercentOfThreshold: 0.90, prescribedRPE: nil,
            requestedPercentOfThreshold: 0.93, repIndexZeroBased: 3
        )
        XCTAssertEqual(decision, .rejected)
        XCTAssertEqual(reason, .rejectedAtOrBelow95PercentThreshold)
    }

    // MARK: F — RPE ≤6 override refusal

    func testRPESixOrLowerRejectsAnOverrideRegardlessOfPercentThreshold() {
        let (decision, reason) = RunningExecutionOverrideEngine.evaluateIntensityOverride(
            prescribedPercentOfThreshold: 1.05, prescribedRPE: 6,
            requestedPercentOfThreshold: 1.08, repIndexZeroBased: 2
        )
        XCTAssertEqual(decision, .rejected)
        XCTAssertEqual(reason, .rejectedAtOrBelowRPE6)
    }

    // MARK: Allowed path — none of the flat refusals apply

    func testAboveNinetyFivePercentMidWorkoutNotRepOneIsAllowed() {
        let (decision, reason) = RunningExecutionOverrideEngine.evaluateIntensityOverride(
            prescribedPercentOfThreshold: 1.05, prescribedRPE: nil,
            requestedPercentOfThreshold: 1.08, repIndexZeroBased: 1
        )
        XCTAssertEqual(decision, .allowed)
        XCTAssertEqual(reason, .allowedWithinDocumentedConditions)
    }

    func testNoIncreaseRequestedIsNotApplicable() {
        let (decision, reason) = RunningExecutionOverrideEngine.evaluateIntensityOverride(
            prescribedPercentOfThreshold: 0.80, prescribedRPE: nil,
            requestedPercentOfThreshold: 0.80, repIndexZeroBased: 3
        )
        XCTAssertEqual(decision, .notApplicable)
        XCTAssertEqual(reason, .noIncreaseRequested)
    }

    func testRequestedLowerThanPrescribedIsNotApplicable() {
        let (decision, _) = RunningExecutionOverrideEngine.evaluateIntensityOverride(
            prescribedPercentOfThreshold: 0.80, prescribedRPE: nil,
            requestedPercentOfThreshold: 0.70, repIndexZeroBased: 3
        )
        XCTAssertEqual(decision, .notApplicable)
    }

    func testRPEOnlyPrescriptionWithNoPercentThresholdIsNotApplicable() {
        let (decision, reason) = RunningExecutionOverrideEngine.evaluateIntensityOverride(
            prescribedPercentOfThreshold: nil, prescribedRPE: 6,
            requestedPercentOfThreshold: nil, repIndexZeroBased: 0
        )
        XCTAssertEqual(decision, .notApplicable)
        XCTAssertEqual(reason, .noIncreaseRequested)
    }

    // MARK: Regression — PROGRAMMED INTENSITY vs. ATHLETE EXECUTION OVERRIDE stay distinct

    func testEightyPercentIsAlwaysAValidPrescriptionNeverRejectedForBeingLowIntensity() {
        // The engine has no code path that evaluates a *prescription* at
        // all — only a requested override against one. Constructing an
        // 80% (or 60%, or 110%) `IntensityTarget.percentOfReference` is
        // always representable; nothing in this engine, or anywhere in
        // this checkpoint's new code, rejects a prescription for being
        // ≤89%.
        let eighty = IntensityTarget.percentOfReference(BoundedRange(lower: 0.80, upper: 0.80), metric: .thresholdPace)
        let sixty = IntensityTarget.percentOfReference(BoundedRange(lower: 0.60, upper: 0.60), metric: .thresholdPace)
        if case .percentOfReference(let range, _) = eighty { XCTAssertEqual(range.lower, 0.80) } else { XCTFail() }
        if case .percentOfReference(let range, _) = sixty { XCTAssertEqual(range.lower, 0.60) } else { XCTFail() }

        // And no-override-requested at 80% confirms the engine treats an
        // as-prescribed 80% execution as entirely unremarkable.
        let (decision, _) = RunningExecutionOverrideEngine.evaluateIntensityOverride(
            prescribedPercentOfThreshold: 0.80, prescribedRPE: nil,
            requestedPercentOfThreshold: 0.80, repIndexZeroBased: 0
        )
        XCTAssertEqual(decision, .notApplicable)
    }

    func testAnAthleteCannotOverrideAnEightyPercentPrescriptionToEightyFive() {
        let (decision, reason) = RunningExecutionOverrideEngine.evaluateIntensityOverride(
            prescribedPercentOfThreshold: 0.80, prescribedRPE: nil,
            requestedPercentOfThreshold: 0.85, repIndexZeroBased: 1
        )
        XCTAssertEqual(decision, .rejected)
        XCTAssertEqual(reason, .rejectedExceedsPrescribedAtOrBelow89Percent)
    }
}
