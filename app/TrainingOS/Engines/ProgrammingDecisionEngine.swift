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
/// exposure — deliberately narrow in this pass (only what's needed to
/// prove the contract compiles); additive fields, never a raw string rule.
struct VarianceConstraints: Codable, Equatable {
    var avoidRepeatingModalityMixWithinSessions: Int?
    var avoidRepeatingMovementFunctionWithinSessions: Int?
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
    let reasonCode: ProgressionReasonCode
    let confidence: Double
    let inputsSummary: String
}

/// No concrete conformer exists in this pass — per Stage 3C §24/§45, the
/// Functional Fitness generator is explicitly not implemented yet. This
/// protocol exists only to settle the contract boundary between
/// "repeatable parametric work" (`BlockProgressionEngine`) and
/// "exposure-informed decision-making" (this), so Stage 4 has an agreed
/// target rather than an open design question.
protocol ProgrammingDecisionEngine {
    func decide(_ input: ProgrammingDecisionInput) -> ProgrammingDecisionOutput
}
