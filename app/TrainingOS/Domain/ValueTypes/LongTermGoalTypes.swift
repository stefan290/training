import Foundation

/// Stage 5B: `Goal`'s compositional extension — a small number of typed
/// value fields, never one giant object of unrelated nullable scalars.
/// See `STRATEGIC_PLAN_MODEL.md` §1 for the full design reasoning.

/// Which tier a non-primary objective sits at. Downstream, this becomes
/// a `.secondary`+`.required` `TrainingMixComponent` when the planner
/// builds a phase's mix (`.protected`) — `PHASE_PLANNING_RULES.md` §2a's
/// exact "protected" pattern, traceable back to the goal that asked for
/// it.
enum SecondaryObjectiveRole: String, Codable, CaseIterable {
    case protected
    case supporting
}

/// One non-primary objective a `Goal` carries, paired with how strongly
/// it must be preserved. A strict superset of the old `[GoalType]` list
/// — `secondaryTypes.map(\.type)` recovers it exactly.
struct SecondaryObjective: Codable, Equatable {
    var type: GoalType
    var role: SecondaryObjectiveRole

    init(type: GoalType, role: SecondaryObjectiveRole) {
        self.type = type
        self.role = role
    }
}

/// Independent of `primaryType`/`secondaryObjectives` — body-composition
/// direction and training modality are different concepts
/// (`STRATEGIC_PLAN_MODEL.md` §1b).
enum BodyCompositionDirection: String, Codable, CaseIterable {
    case gainMuscle
    case loseFat
    case maintain
    case recomposition
}

/// Reuses existing vocabulary directly — `ProgrammingSystemKind`+
/// `ActivityType` — rather than inventing new modality identity.
/// `activityType` is only meaningful when `system` is `.steadyState`/
/// `.interval`. `STRATEGIC_PLAN_MODEL.md` §1d.
struct ModalityPreference: Codable, Equatable {
    var system: ProgrammingSystemKind
    var activityType: ActivityType?

    init(system: ProgrammingSystemKind, activityType: ActivityType? = nil) {
        self.system = system
        self.activityType = activityType
    }
}

/// `STRATEGIC_PLAN_MODEL.md` §13/`ADHERENCE_AWARE_PLANNING.md` §1 — a
/// stated input, never a predicted quantity. Default `.moderate`.
enum VarietyPreference: String, Codable, CaseIterable {
    case low
    case moderate
    case high
}

/// One bundled optional struct — not nine loose scalars on `Goal` itself.
/// A `Goal` with `preferences == nil` simply has no stated preference
/// context yet; every planner call degrades to coarser recommendations,
/// it never fails. `STRATEGIC_PLAN_MODEL.md` §1b/1e.
struct GoalPreferences: Codable, Equatable {
    var preferredModalities: [ModalityPreference]
    var dislikedModalities: [ModalityPreference]
    var varietyPreference: VarietyPreference
    var priorityMuscleGroups: [MuscleGroup]
    /// Freeform labels (e.g. "Sub-20 5K") — deliberately not a typed
    /// metric this pass; never read by structured comparison logic.
    /// `STRATEGIC_PLAN_MODEL.md` §1c.
    var performanceGoals: [String]
    /// Coarse, strategic-grain only — the real `UserAvailability` is
    /// always supplied fresh at tactical time and never duplicated here.
    /// `STRATEGIC_PLAN_MODEL.md` §1e.
    var availableTrainingDaysPerWeek: Int?
    var typicalSessionDurationMinutes: Int?
    var allowsDoubleSessions: Bool?

    init(
        preferredModalities: [ModalityPreference] = [],
        dislikedModalities: [ModalityPreference] = [],
        varietyPreference: VarietyPreference = .moderate,
        priorityMuscleGroups: [MuscleGroup] = [],
        performanceGoals: [String] = [],
        availableTrainingDaysPerWeek: Int? = nil,
        typicalSessionDurationMinutes: Int? = nil,
        allowsDoubleSessions: Bool? = nil
    ) {
        self.preferredModalities = preferredModalities
        self.dislikedModalities = dislikedModalities
        self.varietyPreference = varietyPreference
        self.priorityMuscleGroups = priorityMuscleGroups
        self.performanceGoals = performanceGoals
        self.availableTrainingDaysPerWeek = availableTrainingDaysPerWeek
        self.typicalSessionDurationMinutes = typicalSessionDurationMinutes
        self.allowsDoubleSessions = allowsDoubleSessions
    }
}
