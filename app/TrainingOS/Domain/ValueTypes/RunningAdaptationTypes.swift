import Foundation

/// A single rep's inability-to-hold-pace outcome — FAQ "What should I do
/// if I can't complete a rep during a workout?" (`RUNNING_PROGRAMMING_MODEL_R1.md`
/// §13/§14, item 1).
enum RunningRepFailureAction: String, Codable, CaseIterable {
    /// Prescribed ≥101% threshold: "complete the rep at whatever pace you
    /// can muster... then take 1-3 minutes extra rest before your next
    /// rep."
    case finishAtBestEffortThenExtraRest
    /// Prescribed <100% threshold: "stop running, and start walking
    /// immediately. Walk for 1-3 minutes, such that you are confident
    /// you'll be able to run the rest of the distance at the prescribed
    /// pace."
    case stopAndWalkThenResumeWhenConfident
    /// **Genuine source ambiguity, not invented.** The source text gives
    /// an unconditional rule for "101% or higher" and a separate
    /// unconditional rule for "anywhere under 100%" — the half-open band
    /// `[100%, 101%)` is never addressed by either clause. Per this
    /// checkpoint's own instruction ("if implementation exposes a source
    /// ambiguity not already covered by R1: STOP THAT SPECIFIC BEHAVIOR.
    /// Do not invent an answer."), this case exists so the engine can
    /// honestly report "the source does not say" instead of silently
    /// picking one of the two adjacent rules.
    case sourceAmbiguousBandNotAddressed
}

/// Which documented "worn down but pushable" band a struggling-but-still-
/// moving prescription falls into — FAQ "If I'm feeling very worn down
/// during a workout... should I still hit the paces as prescribed"
/// (R1 §13/§19, item Q).
enum RunningIntensityBand: String, Codable, CaseIterable {
    /// >100% threshold pace, OR RPE ≥7 — "the purpose is to stress your
    /// maximum oxygen utilization capacity... better off getting the
    /// higher intensity stimulus and cutting the workout short."
    case aboveThresholdInterval
    /// 90-100% threshold pace (inclusive both ends) — "better off keeping
    /// the intensity within 90% of threshold pace and completing the full
    /// workout or shortening the distance if you must."
    case thresholdBand
    /// Strictly between 80% and 90% threshold pace (exclusive both
    /// ends — 90% belongs to `.thresholdBand`, 80% belongs to
    /// `.easyBand`, matching the source's own adjacent-band wording) —
    /// "marathon-paced run... pick a pre-determined distance ahead to run
    /// the current pace to, and then run at least 800m at as slow of a
    /// pace as you like."
    case marathonPaceBand
    /// ≤80% threshold pace — "you may absolutely go slower, and SHOULD go
    /// slower by whatever magnitude you like."
    case easyBand

    /// Classifies a prescribed intensity into the band whose worn-down
    /// rule applies. `rpe`, when supplied, can independently push a
    /// %threshold value into `.aboveThresholdInterval` (RPE ≥7) even if
    /// the %threshold number alone would not — the source states both
    /// conditions ("(>100% threshold pace or a 7 out of 10 on the RPE
    /// scale)") as alternatives, not a conjunction.
    static func classify(percentOfThreshold: Double, rpe: Int?) -> RunningIntensityBand {
        if percentOfThreshold > 1.0 || (rpe.map { $0 >= 7 } ?? false) {
            return .aboveThresholdInterval
        }
        if percentOfThreshold >= 0.90 {
            return .thresholdBand
        }
        if percentOfThreshold > 0.80 {
            return .marathonPaceBand
        }
        return .easyBand
    }
}

/// What a struggling-but-still-moving athlete should do within a
/// `RunningIntensityBand` — the deterministic action paired with the
/// band's own source-established rule. Deliberately does not include a
/// magnitude the source never specifies (e.g. exactly how many reps to
/// cut in `.aboveThresholdInterval` — "a rep or two, or each rep short by
/// 200-400m" is the athlete's own judgment call per the source's own
/// wording, not a single deterministic number).
enum RunningWornDownAction: String, Codable, CaseIterable {
    /// `.aboveThresholdInterval`: cut the workout short (fewer reps, or
    /// each rep shortened) rather than reduce intensity.
    case reduceVolumeNotIntensity
    /// `.thresholdBand`, prescribed intensity exactly at the band's own
    /// floor or the athlete can still hold it: complete as prescribed, or
    /// shorten distance if truly necessary — never reduce below 90%.
    case holdAtOrAboveNinetyPercentOrShortenDistance
    /// `.thresholdBand`, prescribed above 90% and the athlete cannot hold
    /// it for the remainder: slow to a pace within the 90-95% threshold
    /// range, never below 90%.
    case slowWithinNinetyToNinetyFivePercentRange
    /// `.marathonPaceBand`: run to a pre-determined point at current pace,
    /// then walk-recover at least 800m; resume marathon pace only if
    /// confident of completing the remainder, otherwise finish at easy
    /// pace.
    case runToMarkThenWalkRecoverAtLeast800Meters
    /// `.easyBand`: no restriction — slow by any amount desired.
    case slowByAnyAmount
}

/// The whole-workout ("too hard to complete as prescribed at all")
/// fallback — FAQ "What happens if I can't complete a rep, set, or
/// workout as prescribed because it's too hard?" A recommendation only;
/// it never silently mutates a stored threshold (see
/// `RunningThresholdCalibration`/`RecordRunningThresholdCalibrationUseCase` —
/// any threshold change still requires an explicit, athlete-entered
/// record).
struct RunningWholeWorkoutFallback: Codable, Equatable {
    /// "Slow down all paces by 5-10% for the remainder of the workout."
    static let paceReductionFraction: ClosedRange<Double> = 0.05...0.10
    /// "...consider slowing your threshold pace by 2-5%." Surfaced as a
    /// RECOMMENDATION only — never applied automatically.
    static let recommendedThresholdReductionFraction: ClosedRange<Double> = 0.02...0.05

    /// Whether the source's own "fluke, no further adjustment" branch or
    /// its "far off, consider a threshold reduction" branch applies —
    /// "If you think it was a fluke... continue with no further
    /// adjustments. If you were very far from desired pace and there were
    /// no extenuating circumstances... consider slowing your threshold
    /// pace."
    enum Severity: String, Codable, CaseIterable {
        case likelyFlukeNoFurtherAdjustment
        case farOffNoExtenuatingCircumstanceConsiderThresholdReduction
    }
}

/// Every source-confirmed adaptation outcome is explainable via one of
/// these — the Running foundation's adaptation-engine reason-code
/// vocabulary, mirroring `StrengthReasonCode`/`SteadyStateReasonCode`/
/// `IntervalReasonCode`.
enum RunningAdaptationReasonCode: String, Codable, CaseIterable {
    case repFailureAboveThreshold
    case repFailureBelowThreshold
    case repFailureSourceAmbiguousBand
    case wornDownAboveThresholdInterval
    case wornDownThresholdBandHold
    case wornDownThresholdBandSlowWithinRange
    case wornDownMarathonPaceBand
    case wornDownEasyBand
    case wholeWorkoutFallbackPaceReduction
    case wholeWorkoutFallbackThresholdReductionRecommended
}
