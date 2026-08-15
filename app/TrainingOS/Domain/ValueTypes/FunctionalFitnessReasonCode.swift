import Foundation

/// `ProgrammingDecisionEngine`'s reason-code vocabulary — the Functional
/// Fitness sibling of `StrengthReasonCode`/`SteadyStateReasonCode`/
/// `IntervalReasonCode`, and the reason `ProgrammingDecisionOutput.reasonCode`'s
/// type changed from `ProgressionReasonCode` (Stage 4E correction, see
/// `FunctionalFitnessDecisionEngine`'s own doc comment): `ProgressionReasonCode`
/// is strength's "why did the load change" vocabulary (load increase/
/// decrease, deload, calibration) — reusing it for "why did the next
/// stimulus balance duration vs. modality" would be exactly the wrong-
/// vocabulary-reused-for-a-different-concept mismatch this codebase has
/// repeatedly corrected (Stage 4C's `SubstitutionReason`/`ProgressionReasonCode`
/// split is the direct precedent).
enum FunctionalFitnessReasonCode: String, Codable, CaseIterable {
    /// The requested duration domain repeated too often recently — the
    /// next stimulus rotates to a different domain.
    case functionalDurationBalance
    /// The requested modality mix repeated too often recently — the next
    /// stimulus's `movementModalityMix` is adjusted toward an
    /// under-exposed modality.
    case functionalModalityBalance
    /// The requested movement function(s) repeated too often recently —
    /// the next stimulus's `movementFunctions` is adjusted toward an
    /// under-exposed pattern.
    case functionalMovementBalance
    /// Recent exposure under-represents high-skill work relative to
    /// what's configured — reserved for a future, more elaborate skill-
    /// balancing rule than this pass implements; declared now so the
    /// vocabulary doesn't need to grow later for it.
    case functionalSkillExposure
    /// The requested loading classification repeated too often recently
    /// — the next stimulus rotates to a different loading level.
    case functionalLoadingBalance
    /// A variance adjustment was made, but not attributable to one single
    /// dimension above (e.g. a future multi-dimension balancing pass).
    /// Not produced by this pass's engine, declared for forward
    /// compatibility with `IntervalReasonCode`'s own "reserved code"
    /// precedent.
    case functionalVarianceBalance
    /// The generator/materializer substituted a movement for this slot
    /// (going forward or this-session-only) — mirrors `SubstitutionReason`
    /// at the FF-decision-output level.
    case movementSubstituted
    /// A scaled variant was used in place of the prescribed movement
    /// (§10/§38 — distinct from substitution; see `FUNCTIONAL_FITNESS_ENGINE.md`).
    case scalingApplied
    /// A candidate was rejected/replaced because required equipment isn't
    /// available.
    case equipmentConstraint
    /// No variance adjustment was needed or possible — the configured
    /// target stimulus is used exactly as requested. The common case when
    /// recent exposure history is empty or doesn't violate any configured
    /// `VarianceConstraints`.
    case stimulusAsConfigured
}
