import Foundation

/// The fixed, closed set of strategically-meaningful events worth an
/// audit record — deliberately narrow. Every low-level scheduler
/// comparison, every `ConcurrentScheduler` placement decision, and every
/// intermediate ranking step stays exactly where it already lives
/// (`ScheduleIssue`/`SchedulingReasonCode`, Stage 4G) — none of that is
/// duplicated here. `PLAN_REVISION_MODEL.md` §2.
enum PlannerDecisionType: String, Codable, CaseIterable {
    case phaseSelected
    case programOrMixSelected
    case userChoseAlternative
    case temporaryPreferenceApplied
    case phaseExtendedOrShortened
    case roadmapRevised
}

/// Who/what actually made this decision — distinct from *why*
/// (`reasonCode`). A system recommendation the user then overrides
/// produces two different `PlannerDecision`s, each with its own honest
/// `source`, never one row with an ambiguous origin.
enum DecisionSource: String, Codable, CaseIterable {
    case systemRecommended
    case userSelected
    case userOverride
    case planRevision
}

/// One option that was on the table and not chosen — enough to answer
/// "why not X" later without needing to persist the full transient
/// proposal it came from. An array of a small struct — already a
/// proven-safe SwiftData persistence shape in this codebase
/// (`Stimulus.movementModalityMix: [ModalityCount]`, Stage 4E).
struct ConsideredAlternative: Codable, Equatable {
    var label: String
    var ratingSummary: GoalAlignmentRating?
    var rejectionReasonCode: PlannerReasonCode?

    init(label: String, ratingSummary: GoalAlignmentRating? = nil, rejectionReasonCode: PlannerReasonCode? = nil) {
        self.label = label
        self.ratingSummary = ratingSummary
        self.rejectionReasonCode = rejectionReasonCode
    }
}
