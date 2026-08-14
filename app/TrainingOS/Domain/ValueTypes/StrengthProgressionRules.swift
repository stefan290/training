import Foundation

/// Reason codes for `HypertrophyProgressionEngine`'s rule-arithmetic
/// outputs — kept separate from `ProgressionReasonCode`
/// (`DoubleProgressionEngine`'s strength-specific codes) since Family A's
/// rule vocabulary (RM-based loads, autoregulated sets, linked
/// references, deload) is a different mechanism entirely, not a
/// specialization of double progression. Additive: never rename or
/// repurpose a case once introduced, since a stored `Recommendation`
/// could reference it.
enum HypertrophyReasonCode: String, Codable, CaseIterable {
    case rmBasedLoad
    case linkedToPairedSlotLoad
    case noLoadProgression
    case fixedSetSchedule
    case autoregulatedSetIncrease
    case autoregulatedSetHold
    case autoregulatedSetDecrease
    case repGoalSchedule
    case deloadWeightPrescribed
    case deloadWeightOmitted
    case deloadRepPrescribed
    case deloadRepOmitted
    case calibrationRequired
}

/// Which 1RM-family basis a `rmBasedWeekOneLoad` rule is anchored to.
/// `.rm10` covers Family A hypertrophy programs; `.rm8`/`.rm5` exist here
/// for Family B/C powerlifting programs (Stage 4B) since all three share
/// this rule type — see `PROGRAM_FAMILY_MATRIX.md`'s cross-family proof
/// table.
enum RMType: String, Codable, CaseIterable {
    case rm10
    case rm8
    case rm5
}

/// `LoadRule.rmBased`'s payload, bundled into one struct rather than 3
/// separate associated values — see that case's doc comment for why.
struct RMBasedLoad: Codable, Equatable {
    var rmType: RMType
    var weekOneFactor: Double
    var laterWeekMultipliers: [Double]
}

/// One week's rep target, e.g. "3 reps, to failure" or "1 rep, to failure"
/// (`FAMILY_A_REP_GOAL_SCHEDULE`). `toFailure` is a flag, not folded into
/// `reps`, because a fixed rep count without a failure qualifier is also a
/// legal week.
struct RepGoal: Codable, Equatable {
    var reps: Int
    var toFailure: Bool

    init(reps: Int, toFailure: Bool = false) {
        self.reps = reps
        self.toFailure = toFailure
    }
}

/// How a slot's weight is progressed week to week. Deliberately does not
/// carry a rounding increment — rounding is `EquipmentProfile.resolve()`'s
/// job alone (`METRIC_LOAD_MODEL.md`), never baked into the rule itself.
/// No case here holds a `ClosedRange` — see `BoundedRange`'s doc comment
/// in `IntensityTarget.swift` for why that would be a persistence risk.
/// `LoadRule`'s persisted discriminator. **`LoadRule`/`SetCountRule`
/// themselves are never stored directly on an `@Model` type** — see
/// `PrescriptionTemplate`'s flat `loadRuleKind`/`loadRuleRMType`/etc.
/// properties and their doc comment for why: two `PrescriptionTemplate`
/// rows in the same store, differing only in which `LoadRule` case they
/// hold, silently decoded the second row's case as `nil` (confirmed by
/// `TemplateGraphPersistenceTests`'s diagnostic tests) — a SwiftData
/// limitation distinct from both the Stage 3C `ClosedRange` crash and the
/// separate 3-associated-value crash also found in this pass. This kind
/// enum plus flat scalar/array fields is the same "manually flattened
/// tagged union" shape used everywhere else in this codebase for anything
/// that varies per row (e.g. `WorkoutResult`'s per-block-type optional
/// fields) — the one persistence pattern proven safe under heterogeneous
/// sibling rows.
enum LoadRuleKind: String, Codable, CaseIterable {
    case rmBased
    case linkedToPairedSlot
    case none
}

/// `SetCountRule`'s persisted discriminator — see `LoadRuleKind`'s doc
/// comment.
enum SetCountRuleKind: String, Codable, CaseIterable {
    case fixed
    case autoregulated
}

/// An in-memory convenience value only — never stored directly on an
/// `@Model` type. See `LoadRuleKind`'s doc comment.
enum LoadRule: Codable, Equatable {
    /// Week 1's baseline: `rmType`'s tested value × `weekOneFactor`
    /// (`FAMILY_A_WEEK1_BASELINE`, e.g. 0.85 for Basic Hypertrophy's
    /// primary movement, 1.0 for the confirmed Heavy-Quads/Glutes
    /// exception). `laterWeekMultipliers[0]` is week 2's multiplier of the
    /// *resolved* (rounded) Week-1 value, `[1]` week 3's, and so on —
    /// never compounding week over week (`FAMILY_A_WEEKLY_PROGRESSION`:
    /// week2=week1×1.05, week3=week1×1.075, week4=week1×1.1, all off the
    /// same rounded Week-1 cell). Bundled into one `RMBasedLoad` payload
    /// rather than 3 separate associated values — an enum case with 3
    /// associated values crashed SwiftData's synthesized
    /// `Decodable.init(from:)` with a dynamic-cast failure (caught by
    /// `TemplateGraphPersistenceTests`), regardless of the individual
    /// value types; every case in this codebase now proven to persist
    /// safely carries exactly 0 or 1 associated value.
    case rmBased(RMBasedLoad)
    /// `linkedResultReference`: this slot's load is a fraction of its
    /// `pairedSlot`'s resolved result. The paired slot itself is a
    /// structural, authoring-time entity reference —
    /// `PrescriptionTemplate.pairedSlot` — never resolved dynamically
    /// through recent training history (Stage 3 decision A5).
    case linkedToPairedSlot(fractionOfSourceResult: Double)
    /// No load progression at all (e.g. a bodyweight accessory movement).
    case none
}

/// An in-memory convenience value only — never stored directly on an
/// `@Model` type. See `LoadRuleKind`'s doc comment. How a slot's set
/// count is progressed week to week.
enum SetCountRule: Codable, Equatable {
    /// A literal per-week schedule (`fixedSetSchedule`), one entry per
    /// non-deload week, index 0 = week 1.
    case fixed(setsByWeek: [Int])
    /// `autoregulatedSetCount`: `baselineSets` for week 1; from week 2 on,
    /// each week's set count is the *previous* week's count (same slot)
    /// plus a live rating (-1/0/+1) sourced from the paired slot's logged
    /// feedback for that week. The rating is a runtime engine input, not
    /// storable here — it doesn't exist until the user actually trains
    /// that week. The reference to which slot supplies the rating lives on
    /// `PrescriptionTemplate.pairedSlot`, mirroring
    /// `LoadRule.linkedToPairedSlot`'s pattern, not duplicated here.
    case autoregulated(baselineSets: Int)
}

/// Whether a slot participates normally in a deload week or is skipped
/// entirely — the confirmed Family-A-Mesocycle-2 superset-partner case
/// (Stage 3 decision A2). Two cases only, deliberately not a generic
/// "blank cell means omit" inference.
enum DeloadExerciseAction: String, Codable, CaseIterable {
    case standard
    case omit
}

/// The full rule bundle for one `PrescriptionTemplate` slot. Deload
/// behavior is split into weight and rep actions because
/// `deloadWeightBySchedulePosition` and `deloadRepInstruction` are two
/// distinct rule types in `PROGRAM_LOGIC_SPEC.md`, even though every
/// observed Family A fixture sets them identically.
struct StrengthProgressionRules: Codable, Equatable {
    var loadRule: LoadRule
    var setCountRule: SetCountRule
    /// Index 0 = week 1's rep goal, through the last non-deload week.
    var repGoalSchedule: [RepGoal]
    var deloadWeightAction: DeloadExerciseAction
    var deloadRepAction: DeloadExerciseAction
    /// `deloadRepInstruction`'s fraction of week 1's rep goal — Family A's
    /// own documented value is `0.5` ("1/2 reps of Week 1"), but
    /// `PROGRAM_REGRESSION_TEST_PLAN.md` §9.1 explicitly tests a non-half
    /// fraction (2/3) too, to prove the rounding-down rule holds
    /// generally rather than by round-to-nearest coincidence — so this is
    /// a configurable rule parameter, not a hardcoded constant, even
    /// though every current Family A fixture sets it to `0.5`.
    var deloadRepFraction: Double

    init(
        loadRule: LoadRule,
        setCountRule: SetCountRule,
        repGoalSchedule: [RepGoal],
        deloadWeightAction: DeloadExerciseAction = .standard,
        deloadRepAction: DeloadExerciseAction = .standard,
        deloadRepFraction: Double = 0.5
    ) {
        self.loadRule = loadRule
        self.setCountRule = setCountRule
        self.repGoalSchedule = repGoalSchedule
        self.deloadWeightAction = deloadWeightAction
        self.deloadRepAction = deloadRepAction
        self.deloadRepFraction = deloadRepFraction
    }
}
