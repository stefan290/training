import Foundation

/// A mechanically-derived summary of one past block's exposure —
/// deliberately not the raw `BlockResult`, and deliberately typed rather
/// than a dictionary/JSON blob (Stage 3C §30's smell audit). Mirrors
/// `FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md` §7's `VarianceExposureRecord`.
struct VarianceExposureRecord: Codable, Equatable {
    let date: Date
    let durationDomain: DurationDomain
    let loading: LoadingClassification
    let movementModalityMix: [ModalityCount]
    let movementFunctionsUsed: [MovementFunction]
    let skillDemand: SkillDemand
    let wasHighIntensity: Bool
}

/// Typed constraints on how a next stimulus should relate to recent
/// exposure — additive fields, never a raw string rule. Stage 4E extends
/// the original 2 fields (proving the contract compiles) with 2 more, one
/// per additional dimension its concrete `FunctionalFitnessDecisionEngine`
/// actually evaluates (§25).
struct VarianceConstraints: Codable, Equatable {
    var avoidRepeatingModalityMixWithinSessions: Int?
    var avoidRepeatingMovementFunctionWithinSessions: Int?
    /// Stage 4E addition.
    var avoidRepeatingDurationDomainWithinSessions: Int?
    /// Stage 4E addition.
    var avoidRepeatingLoadingWithinSessions: Int?

    init(
        avoidRepeatingModalityMixWithinSessions: Int? = nil,
        avoidRepeatingMovementFunctionWithinSessions: Int? = nil,
        avoidRepeatingDurationDomainWithinSessions: Int? = nil,
        avoidRepeatingLoadingWithinSessions: Int? = nil
    ) {
        self.avoidRepeatingModalityMixWithinSessions = avoidRepeatingModalityMixWithinSessions
        self.avoidRepeatingMovementFunctionWithinSessions = avoidRepeatingMovementFunctionWithinSessions
        self.avoidRepeatingDurationDomainWithinSessions = avoidRepeatingDurationDomainWithinSessions
        self.avoidRepeatingLoadingWithinSessions = avoidRepeatingLoadingWithinSessions
    }
}

/// Stage 3B (§35) found that Functional Fitness cannot honestly be forced
/// through `BlockProgressionEngine`'s "current prescription -> next
/// prescription" shape: its next workout is not a parametric adjustment of
/// the current one, it's a decision informed by recent exposure and a
/// stimulus target — closer to "generate a new workout, informed by
/// history" than "increase this number." Rather than twist
/// `ProgressionEngine`/`BlockProgressionEngine` into a poor fit for that
/// (Stage 3C §24's explicit instruction), this is a genuinely separate,
/// higher-level contract. `ProgrammingDecisionEngine` and
/// `BlockProgressionEngine` share the same *shape philosophy* (typed
/// input -> typed output + reason code, pure and deterministic) without
/// pretending the algorithms underneath are the same
/// (`MODALITY_ARCHITECTURE_VALIDATION.md` §5; Stage 3C §25).
struct ProgrammingDecisionInput {
    let exposureHistory: [VarianceExposureRecord]
    let stimulusRequirements: Stimulus
    let varianceConstraints: VarianceConstraints
}

/// Deliberately produces the *next stimulus*, not a fully materialized
/// `FunctionalFitnessPrescription`. Resolving a `Stimulus` into a concrete
/// format/movement-slots/exercises is `FunctionalFitnessProgrammingSystem`'s
/// own multi-stage pipeline (`FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md` §1,
/// stages B-D) — a `ProgrammingDecisionEngine` only owns stage A's
/// decision, keeping this type free of any `@Model` dependency, exactly
/// like `BlockProgressionOutput`.
struct ProgrammingDecisionOutput {
    let nextStimulus: Stimulus
    let reasonCode: FunctionalFitnessReasonCode
    let confidence: Double
    let inputsSummary: String
}

/// **Stage 4E correction:** `reasonCode` was originally typed
/// `ProgressionReasonCode` — a reasonable placeholder when this protocol
/// was scaffolded (Stage 3C, "no concrete conformer exists in this
/// pass"), but `ProgressionReasonCode` is strength's own "why did the
/// load change" vocabulary (load increase/decrease, deload,
/// calibration), not Functional Fitness's "why did the next stimulus
/// balance duration vs. modality" one. Corrected to `FunctionalFitnessReasonCode`
/// now that `FunctionalFitnessDecisionEngine` (this stage's concrete
/// conformer) needs a real vocabulary — painless, since nothing produced
/// or consumed a `ProgrammingDecisionOutput` before this pass.
///
/// `FunctionalFitnessDecisionEngine` (Application/UseCases or Engines —
/// see that type) is the first concrete conformer, closing the boundary
/// this protocol existed to settle.
protocol ProgrammingDecisionEngine {
    func decide(_ input: ProgrammingDecisionInput) -> ProgrammingDecisionOutput
}
