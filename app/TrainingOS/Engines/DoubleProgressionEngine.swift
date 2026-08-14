import Foundation

/// The one progression method implemented in this pass. Handles exactly
/// four outcomes — CALIBRATION_REQUIRED, LOAD_INCREASE, REP_INCREASE, HOLD
/// — and nothing else. LOAD_DECREASE, DELOAD_PRESCRIBED,
/// DOUBLE_PROGRESSION_INCOMPLETE, PERCENTAGE_OF_ESTIMATE, RECENCY_DECAY and
/// SUBSTITUTION_ESTIMATE all need history/program context this minimal
/// engine does not model yet; they are declared on `ProgressionReasonCode`
/// but intentionally unreachable from here until a later pass.
struct DoubleProgressionEngine: ProgressionEngine {
    func recommend(_ input: ProgressionInput) -> ProgressionOutput {
        guard input.hasUsableHistory, let lastKnownWeight = input.lastKnownWeight else {
            return ProgressionOutput(
                recommendedWeight: nil,
                reasonCode: .calibrationRequired,
                confidence: 0,
                inputsSummary: "No usable history for this exercise. Opening with a calibration set instead of a guessed load."
            )
        }

        guard !input.targets.isEmpty, input.targets.count == input.latestResults.count else {
            return ProgressionOutput(
                recommendedWeight: lastKnownWeight,
                reasonCode: .hold,
                confidence: 0.5,
                inputsSummary: "Result count did not match the prescribed set count; holding the previous load rather than guessing."
            )
        }

        let pairs = zip(input.targets, input.latestResults)

        let anySetBelowBottom = pairs.contains { target, outcome in
            outcome.reps < target.repRangeLow
        }

        let everySetHitTopAtOrAboveTarget = pairs.allSatisfy { target, outcome in
            let hitTop = outcome.reps >= target.repRangeHigh
            let metRirTarget: Bool = {
                guard let targetRir = target.targetRir else { return true }
                guard let actualRir = outcome.actualRir else { return true }
                return actualRir >= targetRir
            }()
            return hitTop && metRirTarget
        }

        if everySetHitTopAtOrAboveTarget {
            let newWeight = lastKnownWeight + input.equipmentIncrement
            return ProgressionOutput(
                recommendedWeight: newWeight,
                reasonCode: .loadIncrease,
                confidence: 0.9,
                inputsSummary: "Every set reached the top of its rep range at or above the target RIR. Increasing load by \(input.equipmentIncrement) from \(lastKnownWeight)."
            )
        }

        if anySetBelowBottom {
            return ProgressionOutput(
                recommendedWeight: lastKnownWeight,
                reasonCode: .hold,
                confidence: 0.75,
                inputsSummary: "At least one set fell below the bottom of its rep range. Repeating the same prescription."
            )
        }

        return ProgressionOutput(
            recommendedWeight: lastKnownWeight,
            reasonCode: .repIncrease,
            confidence: 0.85,
            inputsSummary: "Sets stayed within range but did not all reach the top. Load holds; reps are expected to advance next time."
        )
    }
}
