import Foundation

/// Stage 8B: the shared 3-point ordinal for Tier 0's sleep/energy/overall-
/// recovery inputs — reuses the exact -1/0/+1 shape `HypertrophyFeedbackCopy
/// .options` already established for autoregulation feedback (Stage 8A
/// decision D3), for interaction-pattern consistency, not because a 3-point
/// scale is scientifically special. TRAININGOS-DESIGNED, not a validated
/// instrument, same discipline as every other illustrative default in this
/// repo (`PhaseDurationDefaults`, `TacticalWindowPolicy.fallbackWindowWeeks`).
enum ReadinessLevel: Int, Codable, CaseIterable {
    case poor = -1
    case ok = 0
    case good = 1
}

/// WHICH reported signal(s) drove a readiness adaptation decision —
/// independently queryable for longitudinal analysis (Stage 8A decision
/// D10), and where pain/stiffness/soreness stay the three distinct signals
/// D2 requires. See `READINESS_DECISION_MODEL.md` §6.
enum ReadinessSignalSource: String, Codable, CaseIterable {
    case poorSleep
    case lowEnergy
    case poorOverallRecovery
    case localSoreness
    case pain
    case stiffness
}

/// WHAT a readiness adaptation decision actually did — independent of why.
/// `.sessionConvertedToLowerDemand` (Level 5) is deliberately not a case
/// here yet — Level 5 is deferred to a dedicated future stage
/// (`READINESS_DECISION_MODEL.md` §4); adding it later is the expected
/// extension path.
enum ReadinessActionKind: String, Codable, CaseIterable {
    case noChangeConfirmed
    case setCountReduced
    /// Declared for schema completeness (Stage 8A decision D10 requires
    /// `ReadinessAdaptationDecision` be able to represent a load change
    /// generically) but **never produced by
    /// `EvaluateReadinessAdaptationUseCase` in Stage 8B** — no existing,
    /// already-approved load-reduction magnitude exists anywhere in this
    /// codebase (unlike `.setCountReduced`'s reused -1 autoregulation
    /// formula), and CLAUDE.md rule 10/this stage's own magnitude gate
    /// forbid inventing one silently. See the Stage 8B implementation
    /// report's open decision. Exercised directly by
    /// `ReadinessProgressionNeutralityTests` to prove the progression-
    /// neutral overlay is correct for this case whenever a future stage
    /// (or a manually-authored decision) does populate one.
    case loadReduced
    case exerciseSubstituted
    case blockRemoved
    case postponeRecommended
}

/// What the user actually did with a proposed readiness adaptation.
enum UserAdaptationResponse: String, Codable, CaseIterable {
    case accepted
    case rejectedKeptOriginal
    case rejectedChoseAlternative
}
