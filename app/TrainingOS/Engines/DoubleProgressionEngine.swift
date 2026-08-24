import Foundation

/// Stage 10B.6 revision: PERFORMANCE-QUALIFIED LOAD PROGRESSION, not
/// classic ceiling-gated double progression. The prior version required
/// every set to reach the TOP of the rep range before any load increase —
/// rejected by product decision D-10B6-3 as rep-first in practice despite
/// the stated load-first principle. The rule below still handles exactly
/// five outcomes — CALIBRATION_REQUIRED, LOAD_INCREASE, HOLD (progress
/// reps), plain HOLD, LOAD_DECREASE — but a set now also qualifies as
/// strong performance when it stays inside the range while performed with
/// materially more reserve than the target RIR calls for, and a load
/// decrease is now reachable (two consecutive exposures missing the
/// bottom of the range), where it was previously declared but
/// unreachable. See `STAGE10B6_HYPERTROPHY_PRESCRIPTION_REDESIGN.md` §6a
/// for the full decision table this implements.
///
/// **One authoritative decision path:** this is the exact engine both
/// `CompleteSessionUseCase.progressionPreview` (the live "Next time"
/// display) and `HypertrophyV2ProgressionEngine`/`StrengthMaterializer`
/// (real week-N+1 materialization) call — never two independently
/// computed opinions.
struct DoubleProgressionEngine: ProgressionEngine {
    /// TRAININGOS-DESIGNED (D-10B6-3/approved): how much extra reserve
    /// beyond target RIR counts as "meaningfully easier than prescribed" —
    /// large enough to filter out ordinary RIR-estimation noise. A 1-RIR
    /// surplus does not qualify; a 2-RIR surplus does.
    static let rirSurplusThreshold = 2
    /// TRAININGOS-DESIGNED (D-10B6-3/approved): the ceiling ratio
    /// (equipment increment ÷ current working weight) past which an
    /// available increment is treated as disproportionate at this load —
    /// an otherwise-earned increase instead holds and progresses reps
    /// rather than forcing an oversized jump. Deliberately conservative
    /// for V1; kept isolated here, not folded into the decision logic
    /// around it, so it can be revisited independently.
    static let maxProportionalIncrementRatio = 0.10

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

        let pairs = Array(zip(input.targets, input.latestResults))

        func metMinimum(_ target: SetTarget, _ outcome: SetOutcome) -> Bool { outcome.reps >= target.repRangeLow }
        func metCeiling(_ target: SetTarget, _ outcome: SetOutcome) -> Bool { outcome.reps >= target.repRangeHigh }
        func metRirFloor(_ target: SetTarget, _ outcome: SetOutcome) -> Bool {
            guard let targetRir = target.targetRir, let actualRir = outcome.actualRir else { return true }
            return actualRir >= targetRir
        }
        func rirSurplus(_ target: SetTarget, _ outcome: SetOutcome) -> Int {
            guard let targetRir = target.targetRir, let actualRir = outcome.actualRir else { return 0 }
            return actualRir - targetRir
        }
        func isStrong(_ target: SetTarget, _ outcome: SetOutcome) -> Bool {
            (metCeiling(target, outcome) && metRirFloor(target, outcome))
                || (metMinimum(target, outcome) && rirSurplus(target, outcome) >= Self.rirSurplusThreshold)
        }
        func missedBottom(_ pair: (SetTarget, SetOutcome)) -> Bool { !metMinimum(pair.0, pair.1) }

        let allMetMinimum = pairs.allSatisfy { metMinimum($0.0, $0.1) }
        let allMetRirFloor = pairs.allSatisfy { metRirFloor($0.0, $0.1) }
        let allStrong = pairs.allSatisfy { isStrong($0.0, $0.1) }

        if allStrong {
            let proportionalRatio = input.equipmentIncrement / lastKnownWeight
            if proportionalRatio <= Self.maxProportionalIncrementRatio {
                let newWeight = lastKnownWeight + input.equipmentIncrement
                return ProgressionOutput(
                    recommendedWeight: newWeight,
                    reasonCode: .loadIncrease,
                    confidence: 0.9,
                    inputsSummary: "Every set met the qualifying bar — either the top of its range at target RIR, or in-range with materially more reserve than prescribed. Increasing load by \(input.equipmentIncrement) from \(lastKnownWeight)."
                )
            }
            return ProgressionOutput(
                recommendedWeight: lastKnownWeight,
                reasonCode: .repIncrease,
                confidence: 0.85,
                inputsSummary: "Performance qualified for a load increase, but the next available equipment increment (\(input.equipmentIncrement)) is disproportionately large at this weight (over \(Int(Self.maxProportionalIncrementRatio * 100))%). Holding load; reps expected to keep progressing."
            )
        }

        if allMetMinimum && allMetRirFloor {
            return ProgressionOutput(
                recommendedWeight: lastKnownWeight,
                reasonCode: .repIncrease,
                confidence: 0.85,
                inputsSummary: "Sets stayed within range at the intended effort but did not yet qualify for an increase. Load holds; reps are expected to advance next time."
            )
        }

        if !allMetMinimum {
            let previousAlsoMissed: Bool = {
                guard let previousTargets = input.previousTargets, let previousResults = input.previousResults,
                      !previousTargets.isEmpty, previousTargets.count == previousResults.count
                else { return false }
                return zip(previousTargets, previousResults).contains(where: missedBottom)
            }()

            if previousAlsoMissed {
                let newWeight = max(0, lastKnownWeight - input.equipmentIncrement)
                return ProgressionOutput(
                    recommendedWeight: newWeight,
                    reasonCode: .loadDecrease,
                    confidence: 0.7,
                    inputsSummary: "At least one set fell below the bottom of its rep range for the second exposure in a row. Reducing load by one equipment increment (\(input.equipmentIncrement))."
                )
            }
            return ProgressionOutput(
                recommendedWeight: lastKnownWeight,
                reasonCode: .hold,
                confidence: 0.75,
                inputsSummary: "At least one set fell below the bottom of its rep range. Repeating the same prescription — load only reduces after a second exposure like this in a row."
            )
        }

        // allMetMinimum && !allMetRirFloor: the range was only met by
        // working harder than the target RIR allowed.
        return ProgressionOutput(
            recommendedWeight: lastKnownWeight,
            reasonCode: .hold,
            confidence: 0.6,
            inputsSummary: "Reps stayed within range, but at least one set needed more effort than the target RIR to get there. Holding load rather than crediting this as on-track progress."
        )
    }
}
