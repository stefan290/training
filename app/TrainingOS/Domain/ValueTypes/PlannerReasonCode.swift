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
