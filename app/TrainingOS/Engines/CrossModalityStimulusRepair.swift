import Foundation

/// Stage CP.2's minimum-sufficient repair — deliberately NOT a reuse of
/// `FunctionalFitnessDecisionEngine`'s own generic `rotated(_:through:)`
/// variance-rotation helper. That helper exists to produce PLANNED
/// VARIETY (a fixed, harmless cycle through every case); this repair
/// exists to CLEAR A SPECIFIC DISCOURAGED STRESS CONDITION while
/// preserving as much of the intended `Stimulus` as possible — reusing
/// the variance helper for this purpose would have silently wrapped
/// `.heavy` all the way to `.bodyweightOnly` even when one smaller step
/// already sufficed, destroying more of the programmed intent than the
/// condition required.
///
/// Narrow by design: a repair table exists ONLY for the `StressDimension`s
/// Stage CP.2's cross-modality discouragement rule actually checks
/// (`InterferenceAvoidanceRule.conservativeDefault`: `.lowerBodyLoad`,
/// `.impactLoading`). `.impactLoading` never needs a repair table here —
/// `FunctionalFitnessStressProfileMapper` caps every FF candidate's
/// `impactLoading` at `.moderate`, so it can never itself clear a `.high`
/// threshold rule. Do not extend this table to a `StressDimension` no
/// real CP.2 rule checks.
enum CrossModalityStimulusRepair {
    /// Returns the smallest categorical step that clears `dimension` below
    /// `threshold`, or `nil` when no such one-field repair exists (either
    /// because this dimension has no repair table, or because the single
    /// available step would abandon every one of `objectives`) — in
    /// which case the caller must keep the ORIGINAL, discouraged-but-
    /// eligible `Stimulus` unmodified rather than progressively
    /// destroying it.
    static func minimalRepair(
        stimulus: Stimulus,
        for dimension: StressDimension,
        threshold: LoadLevel,
        preservingAtLeastOneOf objectives: [AdaptationObjective]
    ) -> Stimulus? {
        guard dimension == .lowerBodyLoad else {
            // No repair table for any other dimension — see this type's
            // own doc comment on why that is correct, not a gap.
            return nil
        }
        return repairLoadingDriven(stimulus: stimulus, threshold: threshold, objectives: objectives)
    }

    /// `lowerBodyLoad`/`upperBodyLoad` are BOTH driven by
    /// `FunctionalFitnessStressProfileMapper`'s single `loading`-derived
    /// `LoadLevel` (gated by which movement functions are present) — the
    /// minimal repair is therefore always: step `LoadingClassification`
    /// back exactly ONE case (never a full wrap), and only if that one
    /// step actually clears `threshold`.
    private static func repairLoadingDriven(stimulus: Stimulus, threshold: LoadLevel, objectives: [AdaptationObjective]) -> Stimulus? {
        let cases = LoadingClassification.allCases
        guard let index = cases.firstIndex(of: stimulus.loading), index > cases.startIndex else { return nil }

        var repaired = stimulus
        repaired.loading = cases[cases.index(before: index)]

        let repairedLevel = FunctionalFitnessStressProfileMapper.map(stimulus: repaired).lowerBodyLoad
        guard repairedLevel.ordinal < threshold.ordinal else {
            // One step wasn't enough to clear the threshold — this
            // function only ever attempts the single minimal step, never
            // escalates further within one call (a second, larger step
            // would no longer be "minimal" for THIS decision).
            return nil
        }

        guard !objectives.isEmpty else { return repaired }
        let served = AdaptationObjectiveStimulusMapping.objectivesServed(by: repaired)
        guard !served.isDisjoint(with: Set(objectives)) else {
            // The only available repair would abandon every one of this
            // component's own stated objectives — no valid repair exists;
            // keep the original, discouraged-but-eligible baseline.
            return nil
        }
        return repaired
    }
}
