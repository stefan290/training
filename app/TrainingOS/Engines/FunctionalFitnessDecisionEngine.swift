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
    func decide(_ input: ProgrammingDecisionInput) -> ProgrammingDecisionOutput {
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
