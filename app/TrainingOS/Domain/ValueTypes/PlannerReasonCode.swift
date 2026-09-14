import Foundation

/// The authoritative, additive reason-code vocabulary every planner
/// decision draws from — exactly like `SchedulingReasonCode`/
/// `ScheduleIssueCode`, never renamed or repurposed once a
/// `PlannerDecision` referencing one exists. `PLAN_REVISION_MODEL.md` §3
/// is the canonical documentation; this is its direct implementation.
enum PlannerReasonCode: String, Codable, CaseIterable {
    // MARK: Phase selection / composition
    case phaseSelectedForGoal
    case fatLossTimedToMilestone
    case muscleRetentionPriority
    case transitionPhaseInserted
    case recoveryPhaseInserted
    /// Dated Objectives + 10K Strategic Reconciliation V1: this dated
    /// objective's own phase actually started later than its ideal
    /// lead-time would have preferred, because an earlier dated objective's
    /// own phase was still running — the locked "too-soon"/best-effort
    /// semantics, never a blocked plan. Never means the objective was
    /// dropped; it still gets a real phase, just a compressed one.
    case objectivePrepCompressed
    /// Long-Term Planner Intelligence (Vertical Completion V2): this phase
    /// uses a DIFFERENT `PhaseType` than the goal's own primary type
    /// (e.g. a `.muscleGain`-typed phase inside a `GoalType.generalStrength`
    /// plan) as a deliberate TrainingOS strategic-policy choice — the
    /// phase's own adaptation emphasis (e.g. hypertrophy-oriented capacity
    /// building) is judged to legitimately support the athlete's primary
    /// goal later in the same long-term cycle. Never means the athlete's
    /// Goal changed — `Goal.primaryType` is never touched by any phase
    /// carrying this code (`StrategicPeriodizationPolicy`'s own doc
    /// comment has the full reasoning).
    case developmentPhaseSupportsPrimaryGoal

    // MARK: Mix/program recommendation
    case varietyPreferenceApplied
    case programMatchAvailability
    case programMatchExperience
    case programMatchPerformanceProfile
    case programMatchGoal
    case userSelectedAlternative
    case adherencePreferencePromotedAlternative

    // MARK: Temporary preference
    case temporaryPreferenceApplied
    case temporaryPreferenceExpired
    case temporaryPreferenceMaterialityThreshold
    case temporaryPreferenceConvertedToPhase

    // MARK: Revision
    case phaseExtended
    case phaseShortened
    case milestoneDateChanged
    case longTermGoalChanged
    case planRevised
    case missedProgressAdjustmentRecommended

    // MARK: Transition triggers
    case phaseDateReached
    case phaseDurationReached
    case milestonePhaseCompleted
    case userRequestedTransition
    case plannerRecommendedTransition
    case programJourneyCompleted
}
