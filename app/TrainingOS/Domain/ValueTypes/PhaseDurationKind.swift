import Foundation

/// A phase's duration is one of four distinct *kinds*, not just a
/// min/target/max range — "runs until a milestone" and "a program's own
/// fixed block" are genuinely different shapes, not different numbers
/// within one range. `STRATEGIC_PLAN_MODEL.md` §4a.
///
/// Deliberately **not** in this type: "planner-recommended" and
/// "user-extended/shortened" are `PlannerDecision` provenance (who chose
/// this value and why), never a separate case here — a user-extended
/// phase still resolves to one of these four kinds (typically `.range`
/// with an adjusted `typical`); the fact that it was user-extended is
/// recorded as a `.phaseExtended`-reason-coded `PlannerDecision`, not
/// encoded into the duration value itself.
enum PhaseDurationKind: Codable, Equatable {
    /// An exact length — e.g. a selected Strict program's own fixed
    /// mesocycle (commonly 4-week blocks in this codebase).
    case fixed(weeks: Int)
    /// The common case for a phase with no externally-fixed length.
    case range(typical: Int, minimum: Int?, maximum: Int?)
    /// Runs until an explicit, already-resolved date.
    case untilDate(Date)
    /// Runs until `Goal.milestoneDate` — computed relative to the goal,
    /// not a literal stored date, so it stays correct if the milestone
    /// itself is later revised.
    case untilMilestone

    /// The concrete week count `proposeStrategicPlan`/duration math
    /// should use as its planning figure — `typical` for `.range`,
    /// `weeks` for `.fixed`, and `nil` for the two date-anchored kinds
    /// (their length is derived from actual dates, not a week count).
    var planningWeeks: Int? {
        switch self {
        case .fixed(let weeks): return weeks
        case .range(let typical, _, _): return typical
        case .untilDate, .untilMilestone: return nil
        }
    }
}

/// TRAININGOS_DESIGNED, explicitly unvalidated against any source — a
/// caller-overridable default table, exactly like
/// `InterferenceAvoidanceRule.conservativeDefault`. Deliberately built so
/// the *source* of these numbers can migrate to a persisted, owner-
/// editable settings surface later without any caller changing, since
/// every consumer already takes the resolved `PhaseDurationKind` as a
/// value, never reads this table directly.
enum PhaseDurationDefaults {
    private struct WeekRange {
        let typical: Int
        let minimum: Int?
        let maximum: Int?
    }

    /// `enduranceEvent` is deliberately absent — its duration normally
    /// resolves to `.untilMilestone`/`.untilDate` (an event date),
    /// decided by the caller, not looked up here.
    private static let defaults: [PhaseType: WeekRange] = [
        .muscleGain: WeekRange(typical: 12, minimum: 6, maximum: 20),
        .fatLoss: WeekRange(typical: 8, minimum: 4, maximum: 12),
        .maintenance: WeekRange(typical: 4, minimum: 2, maximum: 8),
        .recovery: WeekRange(typical: 2, minimum: 1, maximum: 4),
        .transition: WeekRange(typical: 2, minimum: 1, maximum: 3),
        .strength: WeekRange(typical: 8, minimum: 4, maximum: 12),
        .functionalFitness: WeekRange(typical: 8, minimum: 4, maximum: 12),
    ]
    private static let genericFallback = WeekRange(typical: 8, minimum: 4, maximum: 12)

    static func range(for phaseType: PhaseType) -> PhaseDurationKind {
        let value = defaults[phaseType] ?? genericFallback
        return .range(typical: value.typical, minimum: value.minimum, maximum: value.maximum)
    }
}
