import Foundation

/// Reason codes for `StrengthProgressionEngine`'s rule-arithmetic outputs
/// — kept separate from `ProgressionReasonCode` (`DoubleProgressionEngine`'s
/// strength-specific codes) since this rule vocabulary (RM-based loads,
/// autoregulated sets, linked references, deload) is a different
/// mechanism entirely, not a specialization of double progression.
/// Shared by every family that uses `StrengthProgressionRules` — Family A
/// (Hypertrophy, Stage 4A) and Families B/C (Powerlifting, Stage 4B); see
/// `STAGE4_IMPLEMENTATION_REPORT.md`'s Stage 4B section for the rename
/// from `HypertrophyReasonCode`. Additive: never rename or repurpose a
/// case once introduced, since a stored `Recommendation` could reference
/// it.
enum StrengthReasonCode: String, Codable, CaseIterable {
    case rmBasedLoad
    case linkedToPairedSlotLoad
    case noLoadProgression
    case fixedSetSchedule
    case autoregulatedSetIncrease
    case autoregulatedSetHold
    case autoregulatedSetDecrease
    /// Family B's Week-4 asymmetry (`applyRatingOnFinalWeek == false`):
    /// the final week's set count is the previous week's value, unchanged
    /// — distinct from `.autoregulatedSetHold` (a rating of exactly 0),
    /// since this fires regardless of what the rating *would* have been.
    case autoregulatedSetFinalWeekUnchanged
    /// Family C's Week-4 freeze (`freezeAfterWeek` reached): the set
    /// count is pinned to whichever week `freezeAfterWeek` computed,
    /// ignoring every later week's own rating entirely.
    case autoregulatedSetFrozen
    case repGoalSchedule
    case deloadWeightPrescribed
    case deloadWeightOmitted
    case deloadRepPrescribed
    case deloadRepOmitted
    case calibrationRequired
}

/// Which 1RM-family basis a `rmBasedWeekOneLoad` rule is anchored to.
/// `.rm10` covers Family A (Hypertrophy) and Family C (Powerlifting
/// Hypertrophy-block); `.rm8`/`.rm5` cover Family B (Powerlifting
/// Strength)'s per-slot mixed basis (`FAMILY_B_RM_BASIS`).
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
/// legal week (e.g. Family B's flat "2/fail" weeks 1-3, or its
/// never-changing "Triples" sessions).
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
    /// exception; Family B's 0.95 ordinary / 0.7 Triples factor;
    /// Family C's 0.95 standard / 0.85 Friday-backoff factor).
    /// `laterWeekMultipliers[0]` is week 2's multiplier of the *resolved*
    /// (rounded) Week-1 value, `[1]` week 3's, and so on — never
    /// compounding week over week (`FAMILY_A_WEEKLY_PROGRESSION`/
    /// `FAMILY_B_WEEKLY_PROGRESSION`/`FAMILY_C_WEEKLY_PROGRESSION`, all
    /// identically week2=week1×1.05, week3=week1×1.075, week4=week1×1.1,
    /// off the same rounded Week-1 cell). Bundled into one `RMBasedLoad`
    /// payload rather than 3 separate associated values — an enum case
    /// with 3 associated values crashed SwiftData's synthesized
    /// `Decodable.init(from:)` with a dynamic-cast failure (caught by
    /// `TemplateGraphPersistenceTests`), regardless of the individual
    /// value types; every case in this codebase now proven to persist
    /// safely carries exactly 0 or 1 associated value.
    case rmBased(RMBasedLoad)
    /// `linkedResultReference`: this slot's load is a fraction of its
    /// `pairedSlot`'s resolved result. The paired slot itself is a
    /// structural, authoring-time entity reference —
    /// `PrescriptionTemplate.pairedSlot` — never resolved dynamically
    /// through recent training history (Stage 3 decision A5). Used by
    /// Family A's Metabolite Focus superset partner (Stage 4A) and Family
    /// C's Friday backoff exercise (`FAMILY_C_WEEK1_BASELINE`, Stage 4B):
    /// "a deliberate lighter backoff of the *same* Monday exercise" is
    /// modeled as a fraction of Monday's own resolved weight, the same
    /// structural mechanism, not a separate rule type.
    case linkedToPairedSlot(fractionOfSourceResult: Double)
    /// No load progression at all (e.g. a bodyweight accessory movement).
    case none
}

/// `SetCountRule.autoregulated`'s payload — bundled into one struct
/// (matching `RMBasedLoad`'s reasoning) both to avoid the 3-associated-
/// value crash and because Swift enum cases cannot carry default
/// parameter values, which this type's initializer needs so every
/// pre-existing Family A call site (`.autoregulated(baselineSets: 3)`,
/// updated to `.autoregulated(AutoregulatedSetCount(baselineSets: 3))`)
/// continues to mean exactly what it always meant.
struct AutoregulatedSetCount: Codable, Equatable {
    var baselineSets: Int
    /// Family B's Week-4 asymmetry (`FAMILY_B_AUTOREGULATION`, Stage 3
    /// decision B3): Monday/Tuesday rows keep adding the rating in the
    /// final progressive week exactly as weeks 2-3 do (`true`, the
    /// default — matches every Family A slot, which has no such
    /// exception); Thursday/Friday rows freeze the *addition*, carrying
    /// the previous week's count forward unchanged (`false`). Kept a
    /// distinct parameter from `freezeAfterWeek` below per the decision
    /// memo's own instruction — the two shapes are not the same
    /// mechanism, even though they produce identical numbers in the one
    /// mesocycle length this pass implements.
    var applyRatingOnFinalWeek: Bool
    /// Family C's Week-4 freeze (`FAMILY_C_AUTOREGULATION`, Stage 3
    /// decision B4): once `weekIndex` exceeds this value, the set count
    /// is pinned to whatever `weekIndex == freezeAfterWeek` computed,
    /// ignoring every later week's own rating entirely — not merely
    /// "don't add this week's rating" (that's `applyRatingOnFinalWeek`
    /// above), but "this value no longer changes at all, permanently."
    /// `nil` (every Family A and Family B slot) means never freeze.
    var freezeAfterWeek: Int?

    init(baselineSets: Int, applyRatingOnFinalWeek: Bool = true, freezeAfterWeek: Int? = nil) {
        self.baselineSets = baselineSets
        self.applyRatingOnFinalWeek = applyRatingOnFinalWeek
        self.freezeAfterWeek = freezeAfterWeek
    }
}

/// An in-memory convenience value only — never stored directly on an
/// `@Model` type. See `LoadRuleKind`'s doc comment. How a slot's set
/// count is progressed week to week.
enum SetCountRule: Codable, Equatable {
    /// A literal per-week schedule (`fixedSetSchedule`), one entry per
    /// non-deload week, index 0 = week 1. Also covers Family B's 8RM
    /// accessory rows, which never autoregulate at all
    /// (`FAMILY_B_AUTOREGULATION`: "the 8RM accessory rows... use a
    /// fixed, never-autoregulated schedule").
    case fixed(setsByWeek: [Int])
    /// `autoregulatedSetCount`: `baselineSets` for week 1; from week 2 on,
    /// each week's set count is the *previous* week's count (same slot)
    /// plus a live rating (-1/0/+1) sourced from the paired slot's logged
    /// feedback for that week — subject to `AutoregulatedSetCount`'s
    /// `applyRatingOnFinalWeek`/`freezeAfterWeek` overrides for Families
    /// B/C. The rating is a runtime engine input, not storable here — it
    /// doesn't exist until the user actually trains that week. The
    /// reference to which slot supplies the rating lives on
    /// `PrescriptionTemplate.pairedSlot`, mirroring
    /// `LoadRule.linkedToPairedSlot`'s pattern, not duplicated here.
    case autoregulated(AutoregulatedSetCount)
}

/// Whether a slot participates normally in a deload week or is skipped
/// entirely — the confirmed Family-A-Mesocycle-2 superset-partner case
/// (Stage 3 decision A2). Two cases only, deliberately not a generic
/// "blank cell means omit" inference.
enum DeloadExerciseAction: String, Codable, CaseIterable {
    case standard
    case omit
}

/// Overrides `SourceCompatibleDeloadStrategy`'s default deload
/// day-boundary formula (`ceil(dayCount/2)`, full=1.0×/half=0.5× —
/// Family A's exact, unparameterized shape) for families whose boundary
/// position and/or factor values differ. Family B's weight split
/// (`FAMILY_B_DELOAD`) coincidentally shares Family A's `ceil(dayCount/2)`
/// boundary formula but uses 0.7×/0.5× factors, not 1.0×/0.5×; Family C's
/// weight split uses a *fixed* boundary of 2 (Monday/Tuesday unchanged,
/// Wednesday–Friday halved) which does **not** equal
/// `ceil(5/2) == 3` — proof the boundary itself cannot be derived from a
/// shared formula and must be an explicit, per-slot, generator-supplied
/// value for any family beyond A. `nil` (every Family A slot) preserves
/// the original formula exactly.
struct DeloadPositionOverride: Codable, Equatable {
    var boundaryDayIndex: Int
    var fullPositionFactor: Double
    var halfPositionFactor: Double
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
    /// `deloadRepInstruction`'s *uniform* (day-position-independent)
    /// fraction of week 1's rep goal — Family A's own documented value is
    /// `0.5` ("1/2 reps of Week 1"), applied identically regardless of
    /// which day of the week a slot falls on. Used only when
    /// `deloadRepPositionOverride` below is `nil`.
    /// `PROGRAM_REGRESSION_TEST_PLAN.md` §9.1 explicitly tests a non-half
    /// fraction (2/3) too, to prove the rounding-down rule holds
    /// generally rather than by round-to-nearest coincidence.
    var deloadRepFraction: Double
    /// Overrides `deloadRepFraction` with a day-position-dependent split
    /// — Family B's deload reps genuinely differ by day (`FAMILY_B_DELOAD`:
    /// "2/3 reps of Week 1" Monday/Tuesday, "1/2 reps of Week 1"
    /// Thursday/Friday), unlike Family A's single uniform fraction. `nil`
    /// (every Family A slot) means "use `deloadRepFraction` uniformly,"
    /// preserving the exact original behavior.
    var deloadRepPositionOverride: DeloadPositionOverride?
    /// Overrides `SourceCompatibleDeloadStrategy`'s default
    /// `ceil(dayCount/2)`-derived, 1.0×/0.5× weight split — see
    /// `DeloadPositionOverride`'s doc comment. `nil` (every Family A slot)
    /// preserves the original formula exactly.
    var deloadWeightPositionOverride: DeloadPositionOverride?
    /// Deload-week set count — Family A's own data explicitly confirms
    /// this is a hardcoded constant (`2`), never autoregulated
    /// (`PROGRAM_LOGIC_SPEC.md` §2.1). **Families B and C's source
    /// documentation covers deload weight and reps but never mentions
    /// deload set count at all** — there is no citation to confirm `2`
    /// (or any other number) applies to them. Kept configurable, default
    /// `2`, specifically so this gap stays visible rather than silently
    /// assuming Family A's number transfers; see Stage 4B's own note in
    /// `STAGE4_IMPLEMENTATION_REPORT.md` before treating a Family B/C
    /// deload set count as source-confirmed.
    var deloadSetCount: Int

    init(
        loadRule: LoadRule,
        setCountRule: SetCountRule,
        repGoalSchedule: [RepGoal],
        deloadWeightAction: DeloadExerciseAction = .standard,
        deloadRepAction: DeloadExerciseAction = .standard,
        deloadRepFraction: Double = 0.5,
        deloadRepPositionOverride: DeloadPositionOverride? = nil,
        deloadWeightPositionOverride: DeloadPositionOverride? = nil,
        deloadSetCount: Int = 2
    ) {
        self.loadRule = loadRule
        self.setCountRule = setCountRule
        self.repGoalSchedule = repGoalSchedule
        self.deloadWeightAction = deloadWeightAction
        self.deloadRepAction = deloadRepAction
        self.deloadRepFraction = deloadRepFraction
        self.deloadRepPositionOverride = deloadRepPositionOverride
        self.deloadWeightPositionOverride = deloadWeightPositionOverride
        self.deloadSetCount = deloadSetCount
    }
}
