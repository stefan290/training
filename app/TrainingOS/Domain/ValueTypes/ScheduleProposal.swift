import Foundation

/// Overall placeability of a `ScheduleProposal`. `.infeasible` is never
/// silently downgraded to a partial schedule that just drops sessions —
/// every session that couldn't be placed shows up in `conflicts` instead.
enum ScheduleFeasibility: String, Codable, CaseIterable {
    /// Every session placed with no soft-constraint violations.
    case feasible
    /// Every session placed, but at least one soft constraint (preferred
    /// day, interference avoidance) had to give way — see `warnings`.
    case feasibleWithSoftViolations
    /// At least one session could not be placed at all within the given
    /// `SchedulingConstraints` — see `conflicts` for why and what could
    /// change that.
    case infeasible
}

/// One concrete way a `SchedulingConflict` could be resolved. Never
/// auto-applied — `ConcurrentScheduler` only ever proposes these; only an
/// explicit, separate user action changes the user's requested mix or
/// availability.
enum ConflictResolutionOption: Equatable {
    /// Permit double sessions for this component (either the component's
    /// own `allowsDoubleSessionPairing` or `UserAvailability
    /// .allowsDoubleSessions` was the blocker).
    case allowDoubleSessions(componentLabel: String)
    /// Add this weekday to `UserAvailability.availableWeekdays`.
    case addAvailableDay(Weekday)
    /// Reduce this component's requested frequency down to the given
    /// count (never below its `SessionFrequency.minimum`, when set).
    case reduceFrequency(componentLabel: String, to: Int)
    /// Move or shorten one of this component's own flexible sessions
    /// (only ever offered when that component's `flexibility` is
    /// `.optional` or `.preferred` — never for `.required`).
    case shortenOrMoveFlexibleSession(componentLabel: String)
}

/// One or more of a component's sessions that could not be placed inside
/// the given `SchedulingConstraints`, plus every resolution option that
/// would actually fix it. Never a bare dropped count — every unplaced
/// session is named.
struct SchedulingConflict {
    var componentLabel: String
    var unplacedSessions: [SchedulableSession]
    var reason: String
    var resolutionOptions: [ConflictResolutionOption]

    init(
        componentLabel: String,
        unplacedSessions: [SchedulableSession],
        reason: String,
        resolutionOptions: [ConflictResolutionOption]
    ) {
        self.componentLabel = componentLabel
        self.unplacedSessions = unplacedSessions
        self.reason = reason
        self.resolutionOptions = resolutionOptions
    }
}

/// Where one real Session would land if this proposal were accepted.
/// Nothing here mutates the Session or its `Day` — acceptance is a
/// separate, explicit step (`AcceptScheduleProposalUseCase`).
struct SessionPlacement {
    var session: Session
    var componentLabel: String
    var date: Date
    /// Order among Sessions placed on the same `date`, already resolved
    /// by descending `GoalPriority` — whichever component is primary
    /// sorts first, data-driven rather than hardcoded by modality.
    var sortIndexInDay: Int
    var reasonCodes: [SchedulingReasonCode]
    var isDoubleSessionPairing: Bool

    init(
        session: Session,
        componentLabel: String,
        date: Date,
        sortIndexInDay: Int,
        reasonCodes: [SchedulingReasonCode],
        isDoubleSessionPairing: Bool = false
    ) {
        self.session = session
        self.componentLabel = componentLabel
        self.date = date
        self.sortIndexInDay = sortIndexInDay
        self.reasonCodes = reasonCodes
        self.isDoubleSessionPairing = isDoubleSessionPairing
    }
}

/// `ConcurrentScheduler`'s full, transient output — never persisted and
/// never mutates the active calendar by itself. The
/// Engine-recommendation -> Explanation -> User-approval pattern this
/// project follows elsewhere means a `ScheduleProposal` only becomes real
/// `Day`/`Session` state once `AcceptScheduleProposalUseCase` is
/// explicitly invoked with it.
struct ScheduleProposal {
    /// Identifies which version of the scheduler's placement logic
    /// produced this proposal (mirrors `ProgramDefinition.generatorVersion`)
    /// — so an already-accepted schedule's meaning never silently
    /// changes if the scheduler's algorithm changes later.
    var schedulerVersion: Int
    var window: SchedulingWindow
    var placements: [SessionPlacement]
    var conflicts: [SchedulingConflict]
    var feasibility: ScheduleFeasibility
    /// Structured, machine-readable facts about this proposal —
    /// `GoalAlignmentEvaluator` and any future UI must read this, never
    /// `warnings` (see below). Populated for every soft compromise and
    /// every hard conflict this proposal contains.
    var issues: [ScheduleIssue]
    /// Reserved for a future pass (the Long-Term Planner): alternative
    /// proposals worth comparing against this one (e.g. "allow doubles"
    /// or "add a day" applied). Always empty in this pass — nothing
    /// currently populates it — declared now so `ScheduleProposal`'s
    /// shape doesn't need to change again when that work starts.
    var alternatives: [ScheduleProposal]

    /// Pure display copy, generated FROM `issues` — never an independent
    /// source of truth. Business logic (including `GoalAlignmentEvaluator`)
    /// must never read this; it exists only so a caller that just wants
    /// something to show a user doesn't have to format `issues` itself.
    var warnings: [String] { issues.map(\.reason) }

    init(
        schedulerVersion: Int,
        window: SchedulingWindow,
        placements: [SessionPlacement],
        conflicts: [SchedulingConflict],
        feasibility: ScheduleFeasibility,
        issues: [ScheduleIssue] = [],
        alternatives: [ScheduleProposal] = []
    ) {
        self.schedulerVersion = schedulerVersion
        self.window = window
        self.placements = placements
        self.conflicts = conflicts
        self.feasibility = feasibility
        self.issues = issues
        self.alternatives = alternatives
    }
}
