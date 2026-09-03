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

// MARK: - Dated Objectives (Dated Objectives + 10K Strategic Reconciliation V1)

/// What family of dated objective this is — each kind resolves to its own
/// strategic phase type and its own lead-time policy. A strict superset of
/// the legacy `Goal.milestoneDate`/`.bodyCompositionDirection` pair, which
/// `bodyCompositionMilestone` mirrors exactly; `runningEvent` is new V1
/// scope (10K only — see `RunningStartingState`'s own doc comment for why
/// no other distance/discipline is modeled yet).
enum DatedObjectiveKind: String, Codable, CaseIterable {
    case bodyCompositionMilestone
    case runningEvent
}

/// No persisted "approaching" state — dominance/urgency is always
/// *derived* at planning time from how close `date` is, never stored.
/// `.completed`/`.cancelled` objectives are permanently excluded from
/// planning; editing or cancelling a still-`.planned` objective proposes a
/// new forward roadmap through the existing `TrainingPlan` revision
/// lineage — it never rewrites a phase that already happened.
enum DatedObjectiveStatus: String, Codable, CaseIterable {
    case planned
    case completed
    case cancelled
}

/// The athlete's own explicit self-report of where their running
/// currently stands — never inferred outright from `ActivityPerformanceProfile`
/// data (that data may only *suggest* a preselected answer within a
/// 6-week recency window; the athlete's own choice always wins). Locked
/// V1 lead-time policy: an explicit planning constant, never presented to
/// the athlete as a physiological promise.
enum RunningStartingState: String, Codable, CaseIterable {
    case notCurrentlyRunning
    case occasionalShorterDistances
    case comfortably10K

    var leadTimeWeeks: Int {
        switch self {
        case .notCurrentlyRunning: return 16
        case .occasionalShorterDistances: return 12
        case .comfortably10K: return 8
        }
    }
}

/// One athlete-stated dated objective — a small typed value, never a new
/// `@Model` (nothing here is queried independently of its owning `Goal`,
/// and it carries no performance data of its own — CLAUDE.md rule 2's
/// discipline extended to this new type). `kind` determines which of the
/// two payload fields is meaningful: `bodyCompositionDirection` for
/// `.bodyCompositionMilestone`, `runningStartingState` for `.runningEvent`.
/// `LongTermPlanner` is the only reader that turns this into a real
/// `ProposedPhase` — this type itself holds no phase/mix/duration logic.
struct DatedObjective: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: DatedObjectiveKind
    var date: Date
    var status: DatedObjectiveStatus
    var bodyCompositionDirection: BodyCompositionDirection?
    var runningStartingState: RunningStartingState?

    init(
        id: UUID = UUID(),
        kind: DatedObjectiveKind,
        date: Date,
        status: DatedObjectiveStatus = .planned,
        bodyCompositionDirection: BodyCompositionDirection? = nil,
        runningStartingState: RunningStartingState? = nil
    ) {
        self.id = id
        self.kind = kind
        self.date = date
        self.status = status
        self.bodyCompositionDirection = bodyCompositionDirection
        self.runningStartingState = runningStartingState
    }
}
