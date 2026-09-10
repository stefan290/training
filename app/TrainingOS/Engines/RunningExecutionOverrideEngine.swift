import Foundation

/// Pure, deterministic evaluation of an athlete's requested in-session
/// intensity increase against RP's documented override rules
/// (`RUNNING_PROGRAMMING_MODEL_R1.md` §13, FAQ lines 57-59; HowTo.txt
/// line 9, corrected per the accepted R1 correction). No SwiftData, no
/// persistence, no randomness — same inputs always produce the same
/// `(decision, reasonCode)`.
///
/// **The critical, previously-miscorrected distinction this engine
/// enforces:** PROGRAMMED INTENSITY (what `HypertrophyProgramGenerator`-
/// sibling code may prescribe — any observed value from ~60% to ~110%,
/// no artificial floor) is never confused with ATHLETE EXECUTION OVERRIDE
/// (what the athlete may do differently in the moment). This engine only
/// ever evaluates the latter. It never rejects a *prescription* for being
/// ≤89% — see `ThresholdPaceEngine`'s own doc comment and
/// `RunningExecutionOverrideEngineTests.testEightyPercentIsAlwaysAValidPrescription`.
enum RunningExecutionOverrideEngine {
    /// - Parameters:
    ///   - prescribedPercentOfThreshold: the block's own prescribed
    ///     intensity, when it is a %threshold prescription. `nil` when
    ///     the block is prescribed by RPE instead (use
    ///     `prescribedRPE`) — never both meaningful at once, mirroring
    ///     `IntensityTarget`'s own one-case-at-a-time design.
    ///   - prescribedRPE: the block's own prescribed RPE, when it is an
    ///     RPE-based prescription (e.g. the observed race-week block).
    ///   - requestedPercentOfThreshold: what the athlete is asking to run
    ///     instead, for this same rep/block. Compared only against
    ///     `prescribedPercentOfThreshold` — evaluating an RPE-prescribed
    ///     block's pace override is out of scope for this source
    ///     material (no source text ever describes overriding an
    ///     RPE-only prescription's intensity) and always returns
    ///     `.notApplicable`.
    ///   - repIndexZeroBased: 0 for the first rep of the block/workout,
    ///     1 for the second, etc. FAQ's rep-1 refusal is unconditional
    ///     regardless of every other input.
    static func evaluateIntensityOverride(
        prescribedPercentOfThreshold: Double?,
        prescribedRPE: Int?,
        requestedPercentOfThreshold: Double?,
        repIndexZeroBased: Int
    ) -> (decision: RunningOverrideDecision, reasonCode: RunningOverrideReasonCode) {
        // An RPE-prescribed block has no source-described pace-override
        // rule at all; a %threshold-prescribed block with no requested
        // value is trivially "nothing to evaluate."
        guard let prescribedPercentOfThreshold, let requestedPercentOfThreshold else {
            return (.notApplicable, .noIncreaseRequested)
        }
        guard requestedPercentOfThreshold > prescribedPercentOfThreshold else {
            return (.notApplicable, .noIncreaseRequested)
        }

        if repIndexZeroBased == 0 {
            return (.rejected, .rejectedRepOne)
        }
        if let prescribedRPE, prescribedRPE <= 6 {
            return (.rejected, .rejectedAtOrBelowRPE6)
        }
        if prescribedPercentOfThreshold <= 0.89 {
            return (.rejected, .rejectedExceedsPrescribedAtOrBelow89Percent)
        }
        if prescribedPercentOfThreshold <= 0.95 {
            return (.rejected, .rejectedAtOrBelow95PercentThreshold)
        }
        return (.allowed, .allowedWithinDocumentedConditions)
    }
}
