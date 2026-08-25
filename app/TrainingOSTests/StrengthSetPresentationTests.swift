import XCTest
@testable import TrainingOS

/// Stage 10R.1D UX correction: proves the pure presentation rules behind
/// `StrengthExecutionView`'s set-target/input display — extracted into
/// `StrengthSetPresentation` specifically so this is testable without a
/// UI-tap automation harness (this environment has none). Covers the
/// automated-acceptance checklist from the UX correction request.
final class StrengthSetPresentationTests: XCTestCase {
    // MARK: 1 — RIR-only prescription renders target RIR

    func testRIROnlyPrescriptionRendersTargetRIR() {
        let text = StrengthSetPresentation.targetText(repRangeLow: nil, repRangeHigh: nil, targetRir: 3)
        XCTAssertEqual(text, "RIR 3")
    }

    // MARK: 2/3 — explanatory guidance, dynamic for RIR 3/2/1/0

    func testGuidanceIsDynamicAcrossRIRValues() {
        XCTAssertEqual(StrengthSetPresentation.rirGuidance(for: 3), "Perform reps until you have about 3 reps in reserve.")
        XCTAssertEqual(StrengthSetPresentation.rirGuidance(for: 2), "Perform reps until you have about 2 reps in reserve.")
        XCTAssertEqual(StrengthSetPresentation.rirGuidance(for: 1), "Perform reps until you have about 1 rep in reserve.", "singular wording for RIR 1")
        XCTAssertEqual(StrengthSetPresentation.rirGuidance(for: 0), "Perform reps to failure — no reps in reserve.")
    }

    func testGuidanceNeverInventsAFabricatedRepRange() {
        for rir in 0...4 {
            let guidance = StrengthSetPresentation.rirGuidance(for: rir)
            for forbidden in ["8-12", "5-10", "10-20", "6-12"] {
                XCTAssertFalse(guidance.contains(forbidden), "guidance for RIR \(rir) must never invent a generic rep range")
            }
        }
    }

    // MARK: 4 — no rep range rendered for an RIR-only prescription

    func testNoRepRangeRenderedForAnRIROnlyPrescription() {
        XCTAssertNil(StrengthSetPresentation.repsText(repRangeLow: nil, repRangeHigh: nil))
        let text = StrengthSetPresentation.targetText(repRangeLow: nil, repRangeHigh: nil, targetRir: 2)
        XCTAssertFalse(text.contains("reps"), "an RIR-only target text must never contain a rep count")
    }

    // MARK: 5 — actual reps begins unset/placeholder, never a meaningful 0

    func testActualRepsBeginsAsAnExplicitPlaceholderNeverAMeaningfulZero() {
        XCTAssertEqual(StrengthSetPresentation.actualRepsLabel(nil), "Actual reps: —")
        XCTAssertNotEqual(StrengthSetPresentation.actualRepsLabel(nil), "Actual reps: 0", "unset must never render indistinguishably from a real zero")
        XCTAssertEqual(StrengthSetPresentation.actualRepsLabel(0), "Actual reps: 0", "a real, user-entered zero is shown as a real zero")
        XCTAssertEqual(StrengthSetPresentation.actualRepsLabel(8), "Actual reps: 8")
    }

    // MARK: 8 — actual RIR is clearly separate from target RIR

    func testActualRIRSelectorLabelIsDistinctFromTargetRIRText() {
        XCTAssertEqual(StrengthSetPresentation.actualRirSelectorLabel, "Actual RIR")
        let targetText = StrengthSetPresentation.targetText(repRangeLow: nil, repRangeHigh: nil, targetRir: 3)
        XCTAssertNotEqual(StrengthSetPresentation.actualRirSelectorLabel, targetText, "the actual-RIR input label must never read identically to the prescription's own target-RIR text")
    }

    // MARK: 9 — fixed-rep prescriptions still render correctly

    func testFixedRepPrescriptionStillRendersCorrectly() {
        XCTAssertEqual(StrengthSetPresentation.repsText(repRangeLow: 5, repRangeHigh: 5), "5 reps")
        XCTAssertEqual(StrengthSetPresentation.targetText(repRangeLow: 5, repRangeHigh: 5, targetRir: nil), "5 reps")
        XCTAssertEqual(StrengthSetPresentation.repsText(repRangeLow: 5, repRangeHigh: 10), "5-10 reps", "Stage 10B.6 honest range display when bounds genuinely differ")
    }

    func testHypertrophyV2HybridRendersBothWithoutGuidance() {
        // A genuine rep-range + explicit-RIR hybrid (Hypertrophy V2) has a
        // real rep count, so the RIR-only guidance sentence must never be
        // layered on top of it — the View gates guidance strictly on
        // `repsText == nil`.
        let repsText = StrengthSetPresentation.repsText(repRangeLow: 5, repRangeHigh: 10)
        XCTAssertNotNil(repsText, "a genuine fixed-rep-range prescription must never be treated as RIR-only")
        XCTAssertEqual(StrengthSetPresentation.targetText(repRangeLow: 5, repRangeHigh: 10, targetRir: 3), "5-10 reps · RIR 3")
    }
}
