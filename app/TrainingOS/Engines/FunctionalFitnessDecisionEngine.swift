import Foundation

/// The first concrete `ProgrammingDecisionEngine` conformer (Stage 4E) —
/// closes the boundary Stage 3C scaffolded between "repeatable parametric
/// work" (`BlockProgressionEngine`) and "exposure-informed decision-
/// making" (this). Pure and deterministic, same discipline as every
/// other engine in this codebase: identical `exposureHistory`/
/// `stimulusRequirements`/`varianceConstraints` always yield an identical
/// `nextStimulus`/`reasonCode` (§29) — no randomness, no system clock
/// reads, no hidden state.
///
/// **Deliberately simple, deterministic rule-following, not a scoring
/// model** (§25: "the exact scoring/balance model must be deterministic,"
/// §50: "assert deterministic configured behavior," not scientific
/// programming superiority). Checks exactly 4 dimensions, in a fixed,
/// documented priority order, and adjusts the *first* one it finds
/// violated — never several dimensions in the same call, mirroring Stage
/// 4D's progression-priority discipline ("do not change several things
/// at once").
struct FunctionalFitnessDecisionEngine: ProgrammingDecisionEngine {
    /// Stage FF.L1: the single source of truth for both INTENDED and
    /// FINAL. Two literal, ordered phases, never one flat "first match
    /// wins" list across both concerns — Phase 1 (intent: the original 4
    /// variance checks, unchanged, still "first match wins" among
    /// themselves) decides INTENDED; Phase 2 (adaptation: Stage CP.2's
    /// existing two checks, unchanged internally) evaluates against
    /// Phase 1's own INTENDED output — never the raw configured
    /// baseline directly — producing FINAL. This is the smallest
    /// refactor that lets a future longitudinal-programming/purposeful-
    /// variance check join Phase 1 without ever bypassing CP.2's safety
    /// checks (inserting before Phase 2 in the old flat list) or being
    /// starved by them (inserting after). Their own relative order
    /// within Phase 1 is deliberately undecided — variance != progression,
    /// and this stage adds neither.
    ///
    /// Calling both original phases here (never re-deriving one from the
    /// other, never calling this type twice with different arguments) is
    /// what keeps `decide(_:)` below and `decideWithIntent(_:)`
    /// impossible to desynchronize — one real decision flow, two views
    /// onto it.
    func decideWithIntent(_ input: ProgrammingDecisionInput) -> FunctionalFitnessProgrammingDecision {
        let intended = intentPhase(input)

        var adaptationInput = input
        adaptationInput.stimulusRequirements = intended.nextStimulus
        let final = adaptationPhase(adaptationInput) ?? intended

        return FunctionalFitnessProgrammingDecision(
            intendedStimulus: intended.nextStimulus,
            intendedReasonCode: intended.reasonCode,
            finalStimulus: final.nextStimulus,
            finalReasonCode: final.reasonCode,
            confidence: final.confidence,
            inputsSummary: final.inputsSummary
        )
    }

    /// Preserved for every existing caller that only ever wanted the
    /// single, final, actually-prescribed result (execution, exposure
    /// history, every pre-FF.L1 test) — delegates to `decideWithIntent`
    /// so there is exactly one real decision flow, never two that could
    /// diverge.
    func decide(_ input: ProgrammingDecisionInput) -> ProgrammingDecisionOutput {
        let decision = decideWithIntent(input)
        return ProgrammingDecisionOutput(
            nextStimulus: decision.finalStimulus,
            reasonCode: decision.finalReasonCode,
            confidence: decision.confidence,
            inputsSummary: decision.inputsSummary
        )
    }

    /// Phase 1 (intent): the original 4 variance checks, unchanged,
    /// "first match wins" among themselves — exactly today's pre-CP.2
    /// behavior, run against the raw configured baseline. In production
    /// this is always a no-op (`VarianceConstraints()` is all-`nil`,
    /// §Design Lock item 2) — no real longitudinal check exists yet.
    private func intentPhase(_ input: ProgrammingDecisionInput) -> ProgrammingDecisionOutput {
        if let output = adjustForDurationDomain(input) { return output }
        if let output = adjustForLoading(input) { return output }
        if let output = adjustForModality(input) { return output }
        if let output = adjustForMovementFunction(input) { return output }

        return ProgrammingDecisionOutput(
            nextStimulus: input.stimulusRequirements,
            reasonCode: .stimulusAsConfigured,
            confidence: 1.0,
            inputsSummary: "No configured variance constraint was violated by recent exposure (or none is configured); using the configured stimulus unchanged."
        )
    }

    /// Phase 2 (adaptation): Stage CP.2's existing two checks, unchanged
    /// internally — `nil` means CP.2 has nothing to add, in which case
    /// FINAL simply equals whatever Phase 1 already decided (INTENDED).
    private func adaptationPhase(_ input: ProgrammingDecisionInput) -> ProgrammingDecisionOutput? {
        if let output = adjustForCrossModalityConstraint(input) { return output }
        if let output = adjustForSameWeekComplementarity(input) { return output }
        return nil
    }

    // MARK: - Stage CP.2: cross-modality soft discouragement (checked first)

    /// Same-tactical-week `.primary` sibling stress is NEVER equivalent to
    /// true calendar adjacency (that's `ConcurrentScheduler`'s own,
    /// separate, downstream job) — so this can only ever produce a SOFT
    /// discouragement, repaired when a clean, objective-preserving
    /// one-field alternative exists, and left as the original, unmodified,
    /// still-eligible baseline when it does not. There is no hard
    /// `.ineligible` verdict anywhere in this check.
    private func adjustForCrossModalityConstraint(_ input: ProgrammingDecisionInput) -> ProgrammingDecisionOutput? {
        guard !input.protectedSiblingStressProfilesThisWeek.isEmpty else { return nil }
        let baseline = input.stimulusRequirements
        let candidateProfile = FunctionalFitnessStressProfileMapper.map(stimulus: baseline)

        guard let triggeringRule = InterferenceAvoidanceRule.conservativeDefault.first(where: { rule in
            input.protectedSiblingStressProfilesThisWeek.contains { rule.triggers($0, candidateProfile) }
        }) else { return nil }

        guard let repaired = CrossModalityStimulusRepair.minimalRepair(
            stimulus: baseline, for: triggeringRule.dimension, threshold: triggeringRule.threshold,
            preservingAtLeastOneOf: input.componentAdaptationObjectives
        ) else {
            // No clean one-field repair preserves this component's own
            // objectives — the baseline is discouraged but remains
            // eligible; never progressively destroyed to silence the
            // discouragement. Falls through unchanged to the remaining
            // checks.
            return nil
        }

        return ProgrammingDecisionOutput(
            nextStimulus: repaired,
            reasonCode: .crossModalityDiscouraged,
            confidence: 1.0,
            inputsSummary: "This week's real, already-materialized primary-priority training already carries \(triggeringRule.dimension) at or above \(triggeringRule.threshold); adjusted \(triggeringRule.dimension == .lowerBodyLoad ? "loading" : "the driving field") to avoid compounding it while still serving at least one of this component's own objectives."
        )
    }

    // MARK: - Stage CP.2: same-week FF complementarity (checked second)

    /// Reached only when the cross-modality check above did not fire.
    /// Never hardcodes which session is "first"/"second" — driven purely
    /// by which objectives `input.currentWeekContext` shows are already
    /// covered by whatever this SAME component already programmed earlier
    /// in this SAME tactical week.
    private func adjustForSameWeekComplementarity(_ input: ProgrammingDecisionInput) -> ProgrammingDecisionOutput? {
        guard !input.componentAdaptationObjectives.isEmpty, !input.currentWeekContext.alreadyProgrammedThisWeek.isEmpty else { return nil }

        let servedSoFar = Set(input.currentWeekContext.alreadyProgrammedThisWeek.flatMap {
            AdaptationObjectiveStimulusMapping.objectivesServed(by: $0.stimulus)
        })
        let underCovered = Set(input.componentAdaptationObjectives).subtracting(servedSoFar)
        guard !underCovered.isEmpty else { return nil }

        let baseline = input.stimulusRequirements
        let baselineServes = AdaptationObjectiveStimulusMapping.objectivesServed(by: baseline)
        // The baseline already covers something under-covered — nothing
        // to nudge toward.
        guard baselineServes.isDisjoint(with: underCovered) else { return nil }

        // Deterministic order: the enum's own declared case order, never
        // a random/unordered pick among candidates.
        for objective in AdaptationObjective.allCases where underCovered.contains(objective) {
            guard let nudged = AdaptationObjectiveStimulusMapping.nudge(baseline, toward: objective) else { continue }

            // Must not re-introduce the cross-modality soft
            // discouragement this same call already cleared (or never
            // triggered).
            let nudgedProfile = FunctionalFitnessStressProfileMapper.map(stimulus: nudged)
            let violatesProtection = InterferenceAvoidanceRule.conservativeDefault.contains { rule in
                input.protectedSiblingStressProfilesThisWeek.contains { rule.triggers($0, nudgedProfile) }
            }
            guard !violatesProtection else { continue }

            // Never abandon ALL objective alignment for the sake of
            // variety.
            guard !AdaptationObjectiveStimulusMapping.objectivesServed(by: nudged).isEmpty else { continue }

            return ProgrammingDecisionOutput(
                nextStimulus: nudged,
                reasonCode: .sameWeekComplementarityPreferred,
                confidence: 1.0,
                inputsSummary: "An earlier session this same tactical week already covers \(servedSoFar); nudging toward \(objective), one of this component's own real objectives that remains under-covered so far."
            )
        }
        return nil
    }

    // MARK: - Duration domain balance

    private func adjustForDurationDomain(_ input: ProgrammingDecisionInput) -> ProgrammingDecisionOutput? {
        guard let window = input.varianceConstraints.avoidRepeatingDurationDomainWithinSessions, window > 0 else { return nil }
        let recent = Array(input.exposureHistory.suffix(window))
        guard recent.count == window else { return nil }
        let target = input.stimulusRequirements.targetDurationDomain
        guard recent.allSatisfy({ $0.durationDomain == target }) else { return nil }

        let nextDomain = rotated(target, through: DurationDomain.allCases)
        var adjusted = input.stimulusRequirements
        adjusted.targetDurationDomain = nextDomain
        return ProgrammingDecisionOutput(
            nextStimulus: adjusted,
            reasonCode: .functionalDurationBalance,
            confidence: 1.0,
            inputsSummary: "The last \(window) sessions all used \(target) duration; rotating to \(nextDomain) for variance."
        )
    }

    // MARK: - Loading balance

    private func adjustForLoading(_ input: ProgrammingDecisionInput) -> ProgrammingDecisionOutput? {
        guard let window = input.varianceConstraints.avoidRepeatingLoadingWithinSessions, window > 0 else { return nil }
        let recent = Array(input.exposureHistory.suffix(window))
        guard recent.count == window else { return nil }
        let target = input.stimulusRequirements.loading
        guard recent.allSatisfy({ $0.loading == target }) else { return nil }

        let nextLoading = rotated(target, through: LoadingClassification.allCases)
        var adjusted = input.stimulusRequirements
        adjusted.loading = nextLoading
        return ProgrammingDecisionOutput(
            nextStimulus: adjusted,
            reasonCode: .functionalLoadingBalance,
            confidence: 1.0,
            inputsSummary: "The last \(window) sessions all used \(target) loading; rotating to \(nextLoading) for variance."
        )
    }

    // MARK: - Modality mix balance

    private func adjustForModality(_ input: ProgrammingDecisionInput) -> ProgrammingDecisionOutput? {
        guard let window = input.varianceConstraints.avoidRepeatingModalityMixWithinSessions, window > 0 else { return nil }
        let recent = Array(input.exposureHistory.suffix(window))
        guard recent.count == window else { return nil }
        let targetModalities = Set(input.stimulusRequirements.movementModalityMix.map(\.modality))
        guard !targetModalities.isEmpty else { return nil }
        let allRepeatSameMix = recent.allSatisfy { Set($0.movementModalityMix.map(\.modality)) == targetModalities }
        guard allRepeatSameMix else { return nil }

        var exposureCounts: [FunctionalModality: Int] = Dictionary(uniqueKeysWithValues: FunctionalModality.allCases.map { ($0, 0) })
        for record in input.exposureHistory {
            for modalityCount in record.movementModalityMix {
                exposureCounts[modalityCount.modality, default: 0] += modalityCount.count
            }
        }
        guard let leastExposed = FunctionalModality.allCases.min(by: { (exposureCounts[$0] ?? 0) < (exposureCounts[$1] ?? 0) }),
              !targetModalities.contains(leastExposed) else { return nil }

        var adjusted = input.stimulusRequirements
        adjusted.movementModalityMix.append(ModalityCount(modality: leastExposed, count: 1))
        return ProgrammingDecisionOutput(
            nextStimulus: adjusted,
            reasonCode: .functionalModalityBalance,
            confidence: 1.0,
            inputsSummary: "The last \(window) sessions all used the same modality mix (\(targetModalities)); adding \(leastExposed), the least-exposed modality overall, for variance."
        )
    }

    // MARK: - Movement function balance

    private func adjustForMovementFunction(_ input: ProgrammingDecisionInput) -> ProgrammingDecisionOutput? {
        guard let window = input.varianceConstraints.avoidRepeatingMovementFunctionWithinSessions, window > 0 else { return nil }
        let recent = Array(input.exposureHistory.suffix(window))
        guard recent.count == window else { return nil }
        let targetFunctions = Set(input.stimulusRequirements.movementFunctions)
        guard !targetFunctions.isEmpty else { return nil }
        let allRepeatSameFunctions = recent.allSatisfy { Set($0.movementFunctionsUsed) == targetFunctions }
        guard allRepeatSameFunctions else { return nil }

        var exposureCounts: [MovementFunction: Int] = Dictionary(uniqueKeysWithValues: MovementFunction.allCases.map { ($0, 0) })
        for record in input.exposureHistory {
            for function in record.movementFunctionsUsed {
                exposureCounts[function, default: 0] += 1
            }
        }
        let eligibleFunctions = MovementFunction.allCases.filter { $0 != .other }
        guard let leastExposed = eligibleFunctions.min(by: { (exposureCounts[$0] ?? 0) < (exposureCounts[$1] ?? 0) }),
              !targetFunctions.contains(leastExposed) else { return nil }

        var adjusted = input.stimulusRequirements
        adjusted.movementFunctions.append(leastExposed)
        return ProgrammingDecisionOutput(
            nextStimulus: adjusted,
            reasonCode: .functionalMovementBalance,
            confidence: 1.0,
            inputsSummary: "The last \(window) sessions all used the same movement function(s) (\(targetFunctions)); adding \(leastExposed), the least-exposed pattern overall, for variance."
        )
    }

    // MARK: - Deterministic rotation

    /// The next value after `current` in `allCases`' own declared order,
    /// wrapping around — a fixed, documented cycle, never a random pick
    /// among candidates (§29).
    private func rotated<T: CaseIterable & Equatable>(_ current: T, through allCases: [T]) -> T {
        guard let index = allCases.firstIndex(of: current) else { return current }
        let nextIndex = allCases.index(after: index) == allCases.endIndex ? allCases.startIndex : allCases.index(after: index)
        return allCases[nextIndex]
    }
}
