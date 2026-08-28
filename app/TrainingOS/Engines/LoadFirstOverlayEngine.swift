import Foundation

/// Stage 10R.5: TrainingOS's own, optional load-progression overlay for
/// `.rmBased` (recovered Family A, 3-Day Full Body) exposures —
/// `STAGE10R5_LOAD_FIRST_PROGRESSION_OVERLAY_DESIGN.md`, "Model 2 —
/// Performance-Qualified Source Schedule" (D-10R5-1). **Never source
/// behavior**: the source's own next-scheduled load
/// (`SetPrescription.targetWeight`, produced by `StrengthMaterializer`,
/// never mutated by this engine) is always the default; this engine only
/// ever decides whether actual performance supports accepting it,
/// accelerating past it, or holding/regressing below it. Pure,
/// deterministic, no randomness, no reading the current date/time
/// (CLAUDE.md rule 4) — every input is caller-supplied.
enum LoadFirstOverlayEngine {
    /// D-10R5-2: the exposure-level RIR-pattern classification — computed
    /// from the COMPLETE per-set surplus vector, never a single averaged
    /// number, so a strong exposure with one weak set is never silently
    /// laundered into "easy."
    enum ExposureClassification: Equatable {
        case consistentlyEasy
        case matched
        case inconsistent
        case tooHard
    }

    struct Recommendation: Equatable {
        /// The source's own resolved, rounded next-scheduled value —
        /// always present, always equal to `SetPrescription.targetWeight`
        /// as already materialized. Never touched by this engine.
        var sourceWeight: Double
        /// The value the execution UI should actually show/prefill when
        /// LOAD_FOCUSED mode is active — equal to `sourceWeight` whenever
        /// `reasonCode` is anything other than an increase/decrease.
        var finalWeight: Double
        var reasonCode: LoadOverlayReasonCode
    }

    /// D-10R5-3: a set's actual RIR at least this much above its target
    /// is "meaningfully" easier than prescribed — reused from the
    /// Stage 10B.6 `DoubleProgressionEngine` precedent (filters ordinary
    /// RIR-estimation noise), re-applied here to RIR-only source content.
    static let meaningfulRirSurplusThreshold = 2

    /// D-10R5-8: reused from Stage 10B.6's `maxProportionalIncrementRatio`
    /// — never force an equipment increment that would exceed this
    /// fraction of the current working weight in one step.
    static let maxProportionalIncrementRatio = 0.10

    /// The `StrengthReasonCode` cases that mark a prescription as
    /// materialized during a deload week — the same seam
    /// `appliedLoadReasonCode` already provides (Stage 10R.4 audit
    /// finding), reused here so no new deload-detection plumbing is
    /// needed anywhere in this engine or its resolver.
    static let deloadReasonCodes: Set<StrengthReasonCode> = [
        .deloadWeightPrescribed, .deloadWeightOmitted,
        .deloadRepPrescribed, .deloadRepOmitted,
        .deloadRepsRequireLoggedPerformanceData,
    ]

    /// D-10R5-2: classifies one exposure's complete set-level RIR-surplus
    /// vector (`actualRir - targetRir` per valid, completed set — never
    /// pre-averaged away before this call). `surpluses` must be
    /// non-empty; callers only invoke this for an already-confirmed
    /// eligible exposure (see `LoadFirstExposureResolver`).
    ///
    /// - CONSISTENTLY EASY: every valid set at/above target RIR (no set
    ///   below target may qualify as easy — the "hardest set" veto, per
    ///   D-10R5-2's explicit safety property) AND the exposure's average
    ///   surplus meets the meaningful threshold. `5/5/2` at target 3
    ///   (surpluses `[2,2,-1]`) is NOT easy — the one below-target set
    ///   vetoes it (D-10R5-3's own worked example).
    /// - TOO HARD: the single worst set's surplus is at or below the
    ///   negative meaningful threshold — "meaningful evidence the
    ///   prescribed load exceeded intended effort."
    /// - MATCHED: every valid set exactly at target (surplus `0`).
    /// - INCONSISTENT: neither of the above — some real variability, but
    ///   nothing alarming enough to call it clearly easy or clearly hard.
    static func classify(surpluses: [Int]) -> ExposureClassification {
        guard !surpluses.isEmpty else { return .inconsistent }
        let minSurplus = surpluses.min() ?? 0
        let averageSurplus = Double(surpluses.reduce(0, +)) / Double(surpluses.count)

        if surpluses.allSatisfy({ $0 >= 0 }) && averageSurplus >= Double(meaningfulRirSurplusThreshold) {
            return .consistentlyEasy
        }
        if minSurplus <= -meaningfulRirSurplusThreshold {
            return .tooHard
        }
        if surpluses.allSatisfy({ $0 == 0 }) {
            return .matched
        }
        return .inconsistent
    }

    /// The main entry point — D-10R5-5's exact edge-case precedence,
    /// documented in order:
    ///
    /// 1. Deload week (current exposure) → `.deloadSourceAuthority`,
    ///    unconditionally, source value stands. Checked first: nothing
    ///    else in this function ever overrides deload authority.
    /// 2. No eligible recent exposure at all (new exercise, fresh
    ///    mesocycle, all-skipped history, most-recent-only-readiness-
    ///    adapted) → `.holdInsufficientData`, source value stands. This
    ///    is also where an ineligible gap correctly does NOT erase an
    ///    already-established hard streak — `recentEligibleExposures`
    ///    already excludes ineligible exposures entirely (never inserts
    ///    a neutral placeholder that would reset anything), so the
    ///    streak check below sees the same 2 real exposures regardless
    ///    of how many ineligible ones separated them in real time.
    /// 3. Most recent eligible exposure is CONSISTENTLY EASY → one
    ///    increment above `sourceWeight` (D-10R5-4: one exposure is
    ///    sufficient, no streak needed for an increase) — unless the
    ///    proportional guard blocks it (`.holdIncrementTooLarge`,
    ///    evidence not discarded, simply not acted on this exposure).
    /// 4. Most recent eligible exposure is TOO HARD:
    ///    - if the one before it was ALSO too hard (2 consecutive) →
    ///      regress one increment from `previousEffectiveWeight`.
    ///    - otherwise (first hard exposure) → hold at
    ///      `previousEffectiveWeight`, never at a fresh `sourceWeight`
    ///      (D-10R5-5: "HOLD the current performed/reference load
    ///      initially," not the source's own scheduled increase).
    /// 5. MATCHED or INCONSISTENT → accept `sourceWeight` unchanged.
    static func recommend(
        sourceWeight: Double,
        previousEffectiveWeight: Double?,
        isDeloadWeek: Bool,
        recentEligibleExposureSurpluses: [[Int]],
        equipmentIncrement: Double
    ) -> Recommendation {
        guard !isDeloadWeek else {
            return Recommendation(sourceWeight: sourceWeight, finalWeight: sourceWeight, reasonCode: .deloadSourceAuthority)
        }
        guard let mostRecent = recentEligibleExposureSurpluses.first else {
            return Recommendation(sourceWeight: sourceWeight, finalWeight: sourceWeight, reasonCode: .holdInsufficientData)
        }

        let referenceWeight = previousEffectiveWeight ?? sourceWeight

        switch classify(surpluses: mostRecent) {
        case .consistentlyEasy:
            guard sourceWeight > 0, equipmentIncrement / sourceWeight <= maxProportionalIncrementRatio else {
                return Recommendation(sourceWeight: sourceWeight, finalWeight: sourceWeight, reasonCode: .holdIncrementTooLarge)
            }
            return Recommendation(sourceWeight: sourceWeight, finalWeight: sourceWeight + equipmentIncrement, reasonCode: .loadIncreaseEasyPerformance)

        case .tooHard:
            if recentEligibleExposureSurpluses.count >= 2, classify(surpluses: recentEligibleExposureSurpluses[1]) == .tooHard {
                let regressed = max(equipmentIncrement, referenceWeight - equipmentIncrement)
                return Recommendation(sourceWeight: sourceWeight, finalWeight: regressed, reasonCode: .loadDecreaseRepeatedHardPerformance)
            }
            return Recommendation(sourceWeight: sourceWeight, finalWeight: referenceWeight, reasonCode: .holdMatchedTarget)

        case .matched, .inconsistent:
            return Recommendation(sourceWeight: sourceWeight, finalWeight: sourceWeight, reasonCode: .holdMatchedTarget)
        }
    }
}
