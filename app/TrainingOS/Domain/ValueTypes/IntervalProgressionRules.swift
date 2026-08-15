import Foundation

/// Whether the recovery leg between work intervals is actively moving
/// (an easy jog/spin/paddle) or fully passive (standing/lying rest) —
/// Stage 4D §6's explicit minimum. A third state, "walking" (Beginner
/// Running's run/walk sessions per `ENDURANCE_PROGRAMMING_MODEL.md` §7),
/// is represented as `.active` with a low-intensity `recoveryIntensity`
/// target rather than a third case — walking is a form of active
/// movement, not a structurally different recovery *type*.
enum RecoveryType: String, Codable, CaseIterable {
    case active
    case passive
}

/// Which single dimension an `IntervalPrescriptionTemplate` progresses —
/// the interval sibling of `SteadyStateProgressionDimension`. §14's own
/// requirement ("do NOT automatically increase count + duration +
/// intensity and reduce recovery at the same time") is enforced by
/// `IntervalProgressionRules.priority` being an ORDERED list of these,
/// not a set — see that type's own doc comment.
enum IntervalProgressionVariable: String, Codable, CaseIterable {
    case intervalCount
    case workDuration
    case workDistance
    case intensity
    case recoveryDuration
    case none
}

/// One prioritized progression variable and its own advancement rule —
/// `IntervalProgressionRules.priority: [IntervalProgressionStep]` is an
/// ORDERED list of these. §14's own example ("1. increase interval count
/// until ceiling, then 2. increase work duration") is expressed by an
/// earlier step in the array fully consuming its `weeksToCeiling` worth
/// of weekly progress before a later step in the array starts advancing
/// at all — see `IntervalProgressionEngine.incrementsConsumed` for the
/// exact algorithm.
struct IntervalProgressionStep: Codable, Equatable {
    var variable: IntervalProgressionVariable
    /// Interpreted per-variable: an interval count (whole reps), seconds
    /// (duration), metres (distance), heart-rate zones (intensity — see
    /// `IntensityZoneProgression`, reused unchanged from
    /// `SteadyStateProgressionRules`), or seconds (recovery reduction,
    /// subtracted rather than added).
    var incrementPerWeek: Double
    /// How many weeks this step keeps advancing before it's fully
    /// consumed (its "ceiling") and control passes to the next step in
    /// the priority list, if any.
    var weeksToCeiling: Int
}

/// Which lever a severely-failed session reduces — Stage 4D §16's "do
/// not invent physiological interpretation where not explicitly defined"
/// applied to failure handling specifically: rather than the engine
/// guessing whether to back off intensity or interval count on a bad
/// session, the configuration states the choice up front, so the
/// decision is explainable by pointing at configuration, not by
/// second-guessing a runtime heuristic.
enum IntervalReductionStrategy: String, Codable, CaseIterable {
    case reduceIntensity
    case reduceIntervalCount
}

/// Deterministic, configured success/failure thresholds for one
/// materialized interval session — §16's "keep criteria deterministic"
/// applied directly: every threshold below is a plain configured number,
/// never an inferred physiological judgment.
struct IntervalCompletionCriteria: Codable, Equatable {
    /// `nil` means no RPE ceiling is enforced.
    var maxRpeAllowed: Int?
    /// At or above this completed/total fraction (and within
    /// `maxRpeAllowed`), the session counts as fully successful and the
    /// configured progression is allowed to advance.
    var minimumCompletionFractionForProgress: Double
    /// At or above this fraction (but below the progress threshold), the
    /// session HOLDs — repeats the same prescription next time, no
    /// reduction.
    var minimumCompletionFractionForHold: Double
    /// At or above this fraction (but below the hold threshold), the
    /// session REPEATs — same prescription, more clearly a miss than a
    /// HOLD, but not yet severe enough to reduce anything.
    var minimumCompletionFractionForRepeat: Double
    /// Below every threshold above: a severe miss, reduced via
    /// `reductionStrategy`.
    var reductionStrategy: IntervalReductionStrategy

    init(
        maxRpeAllowed: Int? = nil,
        minimumCompletionFractionForProgress: Double = 1.0,
        minimumCompletionFractionForHold: Double = 0.75,
        minimumCompletionFractionForRepeat: Double = 0.5,
        reductionStrategy: IntervalReductionStrategy = .reduceIntervalCount
    ) {
        self.maxRpeAllowed = maxRpeAllowed
        self.minimumCompletionFractionForProgress = minimumCompletionFractionForProgress
        self.minimumCompletionFractionForHold = minimumCompletionFractionForHold
        self.minimumCompletionFractionForRepeat = minimumCompletionFractionForRepeat
        self.reductionStrategy = reductionStrategy
    }
}

/// What a completed (or not-yet-attempted) interval session implies for
/// the *next* materialized week — Stage 4D §17. `.progress` is not itself
/// one of §17's named failure outcomes; it's the "no failure" case that
/// lets `IntervalProgressionEngine`'s per-dimension resolvers advance
/// normally.
enum IntervalSessionOutcome: String, Codable, Equatable {
    case progress
    case hold
    case repeatSession
    case reduceIntensity
    case reduceIntervalCount
    case calibrationRequired
}

/// The interval sibling of `StrengthReasonCode`/`SteadyStateReasonCode` —
/// every resolution is explainable via one of these. Deliberately a
/// single enum covering both "why did this number change"
/// (`*Increase`/`recoveryReduced`) and "why didn't it"
/// (`hold`/`repeatSession`/`reduce*`/`calibrationRequired`), exactly
/// mirroring `StrengthReasonCode`'s own dual-purpose shape.
enum IntervalReasonCode: String, Codable, CaseIterable {
    case intervalCountIncrease
    case workDurationIncrease
    case workDistanceIncrease
    case intensityIncrease
    case recoveryReduced
    case hold
    case repeatSession
    case reduceIntensity
    case reduceIntervalCount
    case targetMissed
    case activityHistoryUsed
    case calibrationRequired
    /// No progression is configured for this dimension at all (it isn't
    /// in `priority`, or `priority` is empty) — the interval sibling of
    /// `SteadyStateReasonCode.noProgressionConfigured`.
    case noProgressionConfigured
}

/// The engine-facing bundle `IntervalProgressionEngine` operates on — the
/// interval sibling of `StrengthProgressionRules`/`SteadyStateProgressionRules`.
/// Never stored directly on `IntervalPrescriptionTemplate`, which
/// flattens every field individually — same Bug 2/3 discipline as ever.
struct IntervalProgressionRules: Codable, Equatable {
    /// Ordered — see `IntervalProgressionStep`'s own doc comment for how
    /// order enforces §14's explicit priority requirement.
    var priority: [IntervalProgressionStep]

    var weekOneIntervalCount: Int
    var weekOneWorkDurationSeconds: Int?
    var weekOneWorkDistanceMeters: Double?
    var intensityZoneProgression: IntensityZoneProgression?
    var weekOneRecoveryDurationSeconds: Int?
    /// Recovery duration is never reduced below this floor, regardless of
    /// how many weeks of `.recoveryDuration` progression have elapsed.
    var recoveryDurationFloorSeconds: Int

    var completionCriteria: IntervalCompletionCriteria
    /// §15/§33: when `true`, the next week's progression must not be
    /// materialized until the previous week's actual `IntervalSessionOutcome`
    /// is known — the interval sibling of Strength's autoregulation
    /// scope limitation. When `false` (e.g. Helgerud's fixed 4x4, which
    /// the source study never varies), every week is a deterministic
    /// function of week index alone and can materialize immediately,
    /// exactly like `SteadyStateMaterializer`.
    var requiresSuccessfulCompletionToProgress: Bool

    init(
        priority: [IntervalProgressionStep] = [],
        weekOneIntervalCount: Int,
        weekOneWorkDurationSeconds: Int? = nil,
        weekOneWorkDistanceMeters: Double? = nil,
        intensityZoneProgression: IntensityZoneProgression? = nil,
        weekOneRecoveryDurationSeconds: Int? = nil,
        recoveryDurationFloorSeconds: Int = 0,
        completionCriteria: IntervalCompletionCriteria = IntervalCompletionCriteria(),
        requiresSuccessfulCompletionToProgress: Bool = false
    ) {
        self.priority = priority
        self.weekOneIntervalCount = weekOneIntervalCount
        self.weekOneWorkDurationSeconds = weekOneWorkDurationSeconds
        self.weekOneWorkDistanceMeters = weekOneWorkDistanceMeters
        self.intensityZoneProgression = intensityZoneProgression
        self.weekOneRecoveryDurationSeconds = weekOneRecoveryDurationSeconds
        self.recoveryDurationFloorSeconds = recoveryDurationFloorSeconds
        self.completionCriteria = completionCriteria
        self.requiresSuccessfulCompletionToProgress = requiresSuccessfulCompletionToProgress
    }
}
