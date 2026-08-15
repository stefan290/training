import Foundation

/// Stage E of the pipeline (§2/§38) — "analyze the programmed workout for
/// accuracy against the goal," per CrossFit's own described sequence
/// (`FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md` §1.5). A plain value, not a
/// `@Model` — this is a computed check, never persisted.
struct StimulusValidation: Equatable {
    /// `nil` when the format has no explicit cap and this pass has no
    /// honest way to estimate one (§39: "do not pretend exact completion
    /// time is knowable") — e.g. an uncapped For Time or Max Load.
    let estimatedDurationSeconds: Int?
    let matchesDurationDomain: Bool
    let matchesModalityMix: Bool
    let matchesLoadingClassification: Bool
    let matchesSkillDemand: Bool
    let matchesScoreType: Bool
    let passes: Bool
    let notes: [String]
}
