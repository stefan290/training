import Foundation

/// Why `ConcurrentScheduler` placed (or could not place) a Session where
/// it did. Every non-trivial placement carries at least one of these —
/// the exact 10-case list is the kickoff's own authoritative set; codes
/// are additive and never renamed or repurposed once a `ScheduleProposal`
/// referencing one has been shown to a user.
enum SchedulingReasonCode: String, Codable, CaseIterable {
    /// This component's `GoalPriority` claimed a day/slot ahead of a
    /// lower-priority component competing for the same day.
    case primaryGoalPriority
    /// Placement respects `TrainingMixComponent.requiredSpacingDays` (or a
    /// component's own methodology-implied recovery need) between two of
    /// its own sessions.
    case recoverySpacing
    /// A soft interference rule (`InterferenceAvoidanceRule`) was
    /// satisfied by choosing a non-adjacent day when one was available.
    case interferenceAvoided
    /// A double session was paired with a lighter-stress partner
    /// specifically because that pairing was available and preferable to
    /// pairing with a heavier one.
    case lowIntensityPairing
    /// Two sessions were deliberately placed on the same calendar day
    /// (both the component and `UserAvailability` allowed it).
    case doubleSessionSelected
    /// The Session landed on one of its component's `preferredDays`.
    case preferredDayUsed
    /// Placement was shaped by a hard `UserAvailability` constraint
    /// (unavailable day, `maxSessionsPerDay`, minutes available).
    case availabilityConstraint
    /// A soft constraint (preferred day, interference avoidance) could
    /// not be honored given the other hard constraints, and was violated
    /// — always paired with an explanatory note, never left silent.
    case softConstraintViolated
    /// A component's own sessions were placed in the same relative order
    /// its materializer produced them in — the scheduler never reorders
    /// within a component.
    case programOrderPreserved
    /// The scheduled mix is the user's `.selected` `TrainingMix`, not the
    /// `.recommended` one — surfaced so the UI can distinguish "system
    /// chose this" from "you chose this."
    case userSelectedMix
    /// Hardening-pass addition (additive, per this file's own "codes are
    /// additive" rule): this session counts toward its component's
    /// required minimum (or target, when no minimum was set) frequency —
    /// true for every placement made during the scheduler's
    /// guarantee-minimums phase, regardless of whether a specific
    /// cross-component conflict existed for its exact day. Distinct from
    /// `primaryGoalPriority`, which is reserved for placements that won a
    /// *genuine* same-day contention against a lower-priority
    /// component's session — see `CONCURRENT_SCHEDULER.md`'s "conflict
    /// resolution" section for why these are deliberately two different,
    /// non-overlapping claims.
    case requiredFrequencyProtected
}

// MARK: - User availability

/// The full shape of what a user can train, never reduced to a single
/// "sessions per week" number. A scheduler-call input only — never
/// persisted itself, since it is always supplied fresh by whatever UI or
/// use case calls `ConcurrentScheduler`.
struct UserAvailability: Equatable {
    /// How many distinct calendar days per week the user wants to train.
    /// Informational for feasibility checks; the hard limits are
    /// `availableWeekdays`/`maxSessionsPerDay` below.
    var trainingDaysPerWeek: Int
    /// Weekdays the user can train at all. Empty means "no explicit
    /// restriction" — every day not in `unavailableWeekdays` is usable.
    var availableWeekdays: Set<Weekday>
    /// Hard constraint: never place a session here regardless of
    /// priority or flexibility.
    var unavailableWeekdays: Set<Weekday>
    /// Minutes available on each weekday, when known. A weekday absent
    /// from this dictionary has no known minutes ceiling.
    var minutesAvailablePerDay: [Weekday: Int]
    /// Weekdays the user has explicitly flagged as having more time than
    /// usual — a placement signal for a component's longer/harder
    /// sessions, not a hard constraint by itself.
    var longerDayWeekdays: Set<Weekday>
    /// Whether the user permits two sessions on the same calendar day at
    /// all. A component's own `allowsDoubleSessionPairing` must also be
    /// `true` — both gates must open for a double session to be placed.
    var allowsDoubleSessions: Bool
    /// Hard ceiling on sessions per day, independent of
    /// `allowsDoubleSessions` (e.g. a user might allow doubles but cap at
    /// 2/day even if three components compete for one day).
    var maxSessionsPerDay: Int

    init(
        trainingDaysPerWeek: Int,
        availableWeekdays: Set<Weekday> = [],
        unavailableWeekdays: Set<Weekday> = [],
        minutesAvailablePerDay: [Weekday: Int] = [:],
        longerDayWeekdays: Set<Weekday> = [],
        allowsDoubleSessions: Bool = false,
        maxSessionsPerDay: Int = 1
    ) {
        self.trainingDaysPerWeek = trainingDaysPerWeek
        self.availableWeekdays = availableWeekdays
        self.unavailableWeekdays = unavailableWeekdays
        self.minutesAvailablePerDay = minutesAvailablePerDay
        self.longerDayWeekdays = longerDayWeekdays
        self.allowsDoubleSessions = allowsDoubleSessions
        self.maxSessionsPerDay = maxSessionsPerDay
    }

    /// A weekday is usable at all when it isn't hard-excluded, and either
    /// no explicit allow-list was given or it's on the allow-list.
    func isUsable(_ weekday: Weekday) -> Bool {
        guard !unavailableWeekdays.contains(weekday) else { return false }
        guard !availableWeekdays.isEmpty else { return true }
        return availableWeekdays.contains(weekday)
    }
}

// MARK: - Interference avoidance

/// One `TrainingStressProfile` dimension a conservative interference rule
/// can key off of. Deliberately the same closed set `TrainingStressProfile`
/// itself uses — no separate vocabulary.
enum StressDimension: String, Codable, CaseIterable {
    case overallIntensity
    case systemicDemand
    case lowerBodyLoad
    case upperBodyLoad
    case impactLoading
    case metabolicDemand
    case recoveryDemand
}

/// A conservative, deterministic scheduling preference — e.g. "avoid
/// placing two sessions whose `lowerBodyLoad` is both `.high` on adjacent
/// calendar days." This is a soft constraint, expressed purely in terms of
/// the categorical `TrainingStressProfile` vocabulary, never as a
/// physiology claim ("cardio kills gains"). It is TRAININGOS_DESIGNED
/// product policy, not a citation of any exercise-science source — see
/// `CONCURRENT_SCHEDULER.md`.
struct InterferenceAvoidanceRule: Equatable {
    var dimension: StressDimension
    /// Two sessions trigger this rule when both have `dimension` at or
    /// above this `LoadLevel`.
    var threshold: LoadLevel

    init(dimension: StressDimension, threshold: LoadLevel) {
        self.dimension = dimension
        self.threshold = threshold
    }

    func value(of profile: TrainingStressProfile) -> LoadLevel {
        switch dimension {
        case .overallIntensity: return profile.overallIntensity
        case .systemicDemand: return profile.systemicDemand
        case .lowerBodyLoad: return profile.lowerBodyLoad
        case .upperBodyLoad: return profile.upperBodyLoad
        case .impactLoading: return profile.impactLoading
        case .metabolicDemand: return profile.metabolicDemand
        case .recoveryDemand: return profile.recoveryDemand
        }
    }

    func triggers(_ a: TrainingStressProfile, _ b: TrainingStressProfile) -> Bool {
        value(of: a).ordinal >= threshold.ordinal && value(of: b).ordinal >= threshold.ordinal
    }

    /// A minimal, explicitly-labeled conservative default — deliberately
    /// small rather than an attempt at a comprehensive, "scientifically
    /// tuned" interference model (CLAUDE.md rule 10: don't invent
    /// ambiguous training rules). Callers are expected to pass their own
    /// list; this exists only so a caller with no opinion isn't forced to
    /// invent one either.
    static let conservativeDefault: [InterferenceAvoidanceRule] = [
        InterferenceAvoidanceRule(dimension: .lowerBodyLoad, threshold: .high),
        InterferenceAvoidanceRule(dimension: .impactLoading, threshold: .high),
    ]
}

extension LoadLevel {
    /// Ordinal position for threshold comparisons only — never surfaced
    /// as a numeric score to the user (`TrainingStressProfile`'s own "no
    /// fabricated precision" doc comment applies here too).
    var ordinal: Int {
        switch self {
        case .none: return 0
        case .low: return 1
        case .moderate: return 2
        case .high: return 3
        }
    }
}

// MARK: - Scheduling window & constraints

/// The tactical placement window `ConcurrentScheduler` operates over — a
/// rolling week/short horizon, never the full annual plan. `startDate` is
/// always supplied explicitly by the caller; the scheduler itself never
/// reads the current date/time (mirrors CLAUDE.md rule 4's determinism
/// requirement, applied here to scheduling rather than progression).
struct SchedulingWindow: Equatable {
    var startDate: Date
    var numberOfDays: Int

    init(startDate: Date, numberOfDays: Int = 7) {
        self.startDate = startDate
        self.numberOfDays = numberOfDays
    }

    /// Uses `Calendar.current`, matching every existing materializer's own
    /// `startDate + dayIndex` convention (`StrengthMaterializer` etc.) —
    /// so a placement's `date` can round-trip through `Day.date` lookups
    /// without a normalization mismatch.
    func date(forDayOffset offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: startDate) ?? startDate
    }
}

/// Everything about the user (not the training methodology) that
/// `ConcurrentScheduler` needs: availability, the window it may place
/// sessions in, and which interference rules to honor as soft
/// constraints.
struct SchedulingConstraints: Equatable {
    var availability: UserAvailability
    var window: SchedulingWindow
    var interferenceRules: [InterferenceAvoidanceRule]

    init(
        availability: UserAvailability,
        window: SchedulingWindow,
        interferenceRules: [InterferenceAvoidanceRule] = InterferenceAvoidanceRule.conservativeDefault
    ) {
        self.availability = availability
        self.window = window
        self.interferenceRules = interferenceRules
    }
}

// MARK: - Scheduler inputs

/// One `TrainingMixComponent`'s already-materialized Sessions, exactly as
/// `ConcurrentScheduler` receives them — it does not generate methodology,
/// prescribe intensity or pick exercises; it only re-places Sessions its
/// `ProgrammingSystem` already produced.
struct ScheduledProgramInput {
    var component: TrainingMixComponent
    /// This component's own sessions, in their existing execution order
    /// (whatever naive order/dates the materializer assigned). The
    /// scheduler must preserve this relative order — see
    /// `SchedulingReasonCode.programOrderPreserved`.
    var sessions: [Session]
}

/// One real Session annotated with everything the placement algorithm
/// needs, flattened out of a `ScheduledProgramInput` so the algorithm can
/// reason session-by-session (sorted by priority) rather than
/// component-by-component. Never re-derives any of this from
/// `TrainingMixComponent`/`ProgramInstance` after construction — it is a
/// snapshot taken once per `schedule()` call.
struct SchedulableSession {
    var session: Session
    /// Kept only for identity (which real component this came from, for
    /// spacing tracking) and for reading `trainingMix?.kind` — every
    /// scheduling-relevant value is snapshotted into the fields below at
    /// construction time and the algorithm never re-reads this component
    /// mid-run.
    var component: TrainingMixComponent
    var componentLabel: String
    var priority: GoalPriority
    var flexibility: ComponentFlexibility
    var allowsDoubleSessionPairing: Bool
    var preferredDays: [Weekday]
    var requiredSpacingDays: Int?
    /// Worst-case/composed stress across the Session's own blocks — see
    /// `SessionStressComposer`. `nil` when none of the Session's blocks
    /// carry a `trainingStressProfile`.
    var stressProfile: TrainingStressProfile?
    /// This session's position within its own component's existing
    /// materialized order — used as a tie-break among same-importance
    /// sessions of the same component; see `isKeySession` below for the
    /// one thing that can outrank it.
    var componentSortIndex: Int
    /// Snapshot of `Session.isKeySession` — when a component has more
    /// sessions than the window can fit, a key session is preferred over
    /// a standard one from the same component, regardless of
    /// `componentSortIndex`. Never crosses component boundaries: it only
    /// affects which of THIS component's own sessions get first claim.
    var isKeySession: Bool
}

// MARK: - Goal alignment

/// A deterministic, qualitative rating — never a fabricated numeric
/// percentage ("85% optimal"). Ordered so callers may compare two
/// `GoalAlignment`s, but the ordering itself carries no claim of
/// interval-scale precision. `.infeasible` is its own tier, distinct from
/// `.poor` — a schedule that could not be produced at all is a different
/// kind of outcome than one that was produced but scores badly.
enum GoalAlignmentRating: String, Codable, CaseIterable, Comparable {
    case infeasible
    case poor
    case acceptable
    case good
    case excellent

    private var ordinal: Int {
        switch self {
        case .infeasible: return 0
        case .poor: return 1
        case .acceptable: return 2
        case .good: return 3
        case .excellent: return 4
        }
    }

    static func < (lhs: GoalAlignmentRating, rhs: GoalAlignmentRating) -> Bool {
        lhs.ordinal < rhs.ordinal
    }
}

/// Which dimension a single `GoalAlignmentFactor` speaks to — the 7
/// factors the hardening pass's own kickoff names explicitly. Every one
/// of these is computed from `ScheduleProposal.issues`/`.placements`
/// typed data only — never from `warnings` display text.
enum GoalAlignmentFactorKind: String, Codable, CaseIterable {
    /// Does the mix's primary-priority component get its stimulus in at
    /// all — i.e. no `.primaryGoalCompromise` issue.
    case primaryStimulusCoverage
    /// Did every `.required`-flexibility component reach its required
    /// minimum (or target, when no minimum was set) — i.e. no
    /// `.requiredFrequencyUnsatisfied` issue.
    case requiredComponentSatisfaction
    /// Did EVERY component, regardless of flexibility, reach its minimum
    /// (or target) frequency.
    case targetFrequencySatisfaction
    /// Did every secondary/supporting component get at least one session
    /// placed.
    case supportingGoalCoverage
    /// Was the `.selected` mix's own preference data (preferred days)
    /// honored — i.e. no `.preferenceCompromise` issue.
    case userSelectedPreferenceSatisfaction
    /// Could the mix be scheduled at all within the user's availability.
    case schedulingFeasibility
    /// Did placing this mix require any soft interference/recovery
    /// compromise — i.e. no `.interferenceConflict`/
    /// `.recoverySpacingCompromise` issue.
    case interferenceAndRecoveryCompromise
}

/// One transparent, inspectable input to an overall `GoalAlignment` — the
/// structured alternative to a fake score, per the kickoff's explicit
/// instruction.
struct GoalAlignmentFactor: Equatable {
    var kind: GoalAlignmentFactorKind
    var satisfied: Bool
    var note: String

    init(kind: GoalAlignmentFactorKind, satisfied: Bool, note: String) {
        self.kind = kind
        self.satisfied = satisfied
        self.note = note
    }
}

/// A `TrainingMix`'s (or `ScheduleProposal`'s) fit to its `TrainingPhase`
/// goal — a qualitative rating plus the fully transparent factors behind
/// it. Never collapsed into a single numeric percentage.
struct GoalAlignment: Equatable {
    var rating: GoalAlignmentRating
    var factors: [GoalAlignmentFactor]

    init(rating: GoalAlignmentRating, factors: [GoalAlignmentFactor]) {
        self.rating = rating
        self.factors = factors
    }
}
