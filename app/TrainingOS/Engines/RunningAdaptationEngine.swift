import Foundation

/// Pure, deterministic in-workout adaptation rules — the Running
/// foundation's response to execution problems (can't hold pace on a
/// single rep, worn-down-but-pushable, can't complete the whole workout).
/// No SwiftData, no persistence, no randomness; every function is a
/// stateless mapping from documented inputs to a documented outcome plus
/// reason code.
///
/// **Authority boundary (R2.6):** this engine only ever RECOMMENDS —
/// `wholeWorkoutFallback`'s threshold-reduction branch is a
/// recommendation for the athlete/UI layer to act on explicitly via
/// `RecordRunningThresholdCalibrationUseCase`, never a value this engine
/// writes anywhere itself.
enum RunningAdaptationEngine {
    /// FAQ: single-rep inability to hold pace.
    static func repFailureResponse(prescribedPercentOfThreshold: Double) -> (action: RunningRepFailureAction, reasonCode: RunningAdaptationReasonCode) {
        if prescribedPercentOfThreshold >= 1.01 {
            return (.finishAtBestEffortThenExtraRest, .repFailureAboveThreshold)
        }
        if prescribedPercentOfThreshold < 1.00 {
            return (.stopAndWalkThenResumeWhenConfident, .repFailureBelowThreshold)
        }
        // [1.00, 1.01) — genuinely unaddressed by source text; see
        // `RunningRepFailureAction.sourceAmbiguousBandNotAddressed`'s own
        // doc comment.
        return (.sourceAmbiguousBandNotAddressed, .repFailureSourceAmbiguousBand)
    }

    /// FAQ: "worn down but pushable" banded response.
    static func wornDownResponse(
        prescribedPercentOfThreshold: Double,
        prescribedRPE: Int?,
        canStillHoldPrescribedPace: Bool
    ) -> (action: RunningWornDownAction, reasonCode: RunningAdaptationReasonCode) {
        let band = RunningIntensityBand.classify(percentOfThreshold: prescribedPercentOfThreshold, rpe: prescribedRPE)
        switch band {
        case .aboveThresholdInterval:
            return (.reduceVolumeNotIntensity, .wornDownAboveThresholdInterval)
        case .thresholdBand:
            if prescribedPercentOfThreshold > 0.90, !canStillHoldPrescribedPace {
                return (.slowWithinNinetyToNinetyFivePercentRange, .wornDownThresholdBandSlowWithinRange)
            }
            return (.holdAtOrAboveNinetyPercentOrShortenDistance, .wornDownThresholdBandHold)
        case .marathonPaceBand:
            return (.runToMarkThenWalkRecoverAtLeast800Meters, .wornDownMarathonPaceBand)
        case .easyBand:
            return (.slowByAnyAmount, .wornDownEasyBand)
        }
    }

    /// FAQ: whole-workout "too hard to complete as prescribed at all"
    /// fallback. `severity` is the caller's own honest judgment of which
    /// branch applies (the source itself frames this as the athlete's own
    /// assessment — "if you think it was a fluke" — not a computable
    /// input), so this function does not infer it from anything.
    static func wholeWorkoutFallback(severity: RunningWholeWorkoutFallback.Severity) -> (paceReductionFraction: ClosedRange<Double>, thresholdReductionRecommended: ClosedRange<Double>?, reasonCode: RunningAdaptationReasonCode) {
        switch severity {
        case .likelyFlukeNoFurtherAdjustment:
            return (RunningWholeWorkoutFallback.paceReductionFraction, nil, .wholeWorkoutFallbackPaceReduction)
        case .farOffNoExtenuatingCircumstanceConsiderThresholdReduction:
            return (
                RunningWholeWorkoutFallback.paceReductionFraction,
                RunningWholeWorkoutFallback.recommendedThresholdReductionFraction,
                .wholeWorkoutFallbackThresholdReductionRecommended
            )
        }
    }
}
