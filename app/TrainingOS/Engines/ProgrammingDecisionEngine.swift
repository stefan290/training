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
    /// Stage FF.L1: `var`, not `let` — `FunctionalFitnessDecisionEngine
    /// .decideWithIntent` needs to evaluate its Phase 2 (CP.2 adaptation)
    /// check against Phase 1's own INTENDED output rather than this raw
    /// configured value, by constructing a copy with this one field
    /// overridden. Every other real caller still supplies the raw
    /// configured baseline exactly as before.
    var stimulusRequirements: Stimulus
    let varianceConstraints: VarianceConstraints
    /// Stage CP.2 addition. This component's own real, locked
    /// `AdaptationObjective`s (empty when the owning `LongTermPlanner`
    /// builder has no honest per-sub-objective signal yet — see
    /// `TRAINING_MIX_CONCURRENT_PROGRAMMING_DESIGN.md`'s product-decision
    /// table). Drives preference/objective-preservation only — never
    /// eligibility.
    var componentAdaptationObjectives: [AdaptationObjective] = []
    /// Stage CP.2 addition. Real, already-materialized SAME-TACTICAL-WEEK
    /// sibling sessions' `TrainingStressProfile`s, from `.primary`-priority
    /// components only (`GoalPriority` is what makes a dimension
    /// "protected" — never a materialization-order field). Same-week
    /// presence is not true calendar adjacency (that's `ConcurrentScheduler`'s
    /// own job, downstream and unchanged) — this can only ever produce a
    /// SOFT discouragement, never a hard pre-placement ineligibility.
    var protectedSiblingStressProfilesThisWeek: [TrainingStressProfile] = []
    /// Stage CP.2 addition. What this SAME component has already
    /// programmed earlier in the SAME `materializeWeek` call — see
    /// `CurrentWeekFunctionalFitnessProgrammingContext`'s own doc comment
    /// for why this is deliberately distinct from `exposureHistory`.
    var currentWeekContext: CurrentWeekFunctionalFitnessProgrammingContext = CurrentWeekFunctionalFitnessProgrammingContext()
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

/// Stage FF.L1 ("Intended vs. Final Stimulus Foundation") — makes the
/// intent/adaptation boundary `FunctionalFitnessDecisionEngine` already
/// reasons about internally (`FUNCTIONAL_FITNESS_LONGITUDINAL_PROGRAMMING_DESIGN.md`'s
/// Design Lock) an explicit, durable output shape rather than a single
/// collapsed `ProgrammingDecisionOutput`.
///
/// `intendedStimulus` is what Functional Fitness's own intent-shaping
/// checks (today: the 4 original variance checks; future: any real
/// longitudinal-programming/purposeful-variance check) decided BEFORE
/// concurrent-training adaptation ran. `finalStimulus` is what Stage
/// CP.2's cross-modality/same-week checks decided AFTER seeing that
/// intent — the only value ever exposed to execution, exposure history,
/// or `CurrentWeekFunctionalFitnessProgrammingContext` (all of which want
/// what was ACTUALLY prescribed, not what was originally intended).
///
/// Never reconstructed after the fact from a reason code or by re-running
/// current engine logic against historical state — an intended value that
/// isn't captured at the moment it's decided is not honestly recoverable
/// later, since a repair/mapping function's CURRENT behavior may not match
/// what an OLDER app version's engine actually did for a historical
/// session. See the design doc's Design Lock, item 5, for the full proof.
struct FunctionalFitnessProgrammingDecision {
    let intendedStimulus: Stimulus
    /// Why INTENDED differs from the configured baseline. Transient —
    /// never persisted (Stage FF.L1 explicitly declines to add a
    /// persisted `intendedReasonCode`, since no real intent-shaping
    /// behavior is active in production today; a future stage that adds
    /// one can do so when it becomes necessary, not before).
    let intendedReasonCode: FunctionalFitnessReasonCode
    let finalStimulus: Stimulus
    /// Why FINAL differs from INTENDED (or, if it doesn't, mirrors
    /// `intendedReasonCode`) — this is the one reason code
    /// `FunctionalFitnessPrescription` has ever persisted, unchanged in
    /// meaning by this stage.
    let finalReasonCode: FunctionalFitnessReasonCode
    let confidence: Double
    let inputsSummary: String
}
