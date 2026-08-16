import Foundation

/// Which role a `CandidateTrainingMix` plays in the ranked result set —
/// `ADHERENCE_AWARE_PLANNING.md` §5. A candidate may carry more than one
/// role at once (e.g. `{.recommended, .bestGoalAlignment}` when nothing
/// was promoted).
enum CandidateMixRole: String, Codable, CaseIterable {
    /// Top of the ranked list AFTER §5b's promotion step.
    case recommended
    /// The single highest-`GoalAlignment` compatible candidate — ALWAYS
    /// shown, even when a promotion means it isn't also `.recommended`.
    case bestGoalAlignment
    case bestVarietyAlternative
    case userPreferenceAlternative
}

/// One ranked candidate `TrainingMix` — `mix.kind == .recommended`,
/// transient until a separate, explicit acceptance step persists it
/// (mirrors `ScheduleProposal`'s own "propose, never mutate" shape,
/// `LONG_TERM_PLANNER.md` §5). `alignment` comes from the exact,
/// unmodified Stage 4G `GoalAlignmentEvaluator` — never a second scoring
/// system (`ADHERENCE_AWARE_PLANNING.md` §6).
struct CandidateTrainingMix {
    var mix: TrainingMix
    var roles: Set<CandidateMixRole>
    var alignment: GoalAlignment
    var reasonCodes: [PlannerReasonCode]

    init(
        mix: TrainingMix,
        roles: Set<CandidateMixRole>,
        alignment: GoalAlignment,
        reasonCodes: [PlannerReasonCode]
    ) {
        self.mix = mix
        self.roles = roles
        self.alignment = alignment
        self.reasonCodes = reasonCodes
    }
}
