import Foundation
import SwiftData

/// Stage 10B addition: `generate()`'s typed failure for the one case
/// this generator can now actually detect as wrong before persisting
/// anything — its own structural muscle-group coverage check
/// (`validateWeeklyCoverage`) failing for the day-focus-driven reference
/// configuration (3-Day Full Body). **Never thrown for any of the other
/// 5 curated configurations** — those still run the original,
/// unconditional single-primary-slot-pair-per-day logic this file has
/// always had, completely unchanged (`STAGE10B_IMPLEMENTATION_PLAN.md`
/// §17/§18: other splits/day-counts are explicitly out of Stage 10B's
/// scope and behave exactly as before). Never persisted when thrown —
/// every `context.insert` for the reference-config path happens only
/// after this check passes.
enum HypertrophyGenerationError: Error, Equatable {
    /// One or more of `HypertrophyProgramGenerator.trackedMuscleGroups`
    /// exposed a weekly count that doesn't match
    /// `HypertrophyProgramGenerator.expectedWeeklyExposure` — either zero
    /// (never appears at all) or any other mismatch against the approved
    /// per-group policy (most groups 3×, calves 2×). Proves the actual
    /// *programming contract*, never mathematical symmetry — see
    /// `MuscleGroupExposureMismatch`'s doc comment.
    case weeklyExposurePolicyViolated(mismatches: [MuscleGroupExposureMismatch])
    /// Two days in the same week produced an identical
    /// `(primary, secondary, accessory)` triple — "no muscle group
    /// disappears, no day repeats" would be violated even though every
    /// individual group technically appears somewhere in the week.
    case duplicateDayFocus(dayNames: [String])
    /// Stage 10R.2A: the day-focus-driven path (3-Day Full Body) has no
    /// recovered source content for this phase yet — thrown rather than
    /// silently falling back to another phase's content (the exact
    /// pre-10R.2A bug this stage corrects) or fabricating placeholder
    /// content. Stage 10R.3A adds real content for `.resensitization`, so
    /// no phase currently throws this for the 3-Day Full Body
    /// configuration — the case is retained (never removed) for the same
    /// reason a future family/split/day-count combination without
    /// recovered content should throw it too, not silently reuse another
    /// configuration's content.
    case phaseNotYetRecovered(phaseType: HypertrophyPhaseType)
}

/// One muscle group whose actual weekly exposure count (across the
/// day-focus table's own primary/secondary/accessory unions) doesn't
/// match `HypertrophyProgramGenerator.expectedWeeklyExposure`'s
/// approved policy for that group.
struct MuscleGroupExposureMismatch: Equatable {
    var group: MuscleGroup
    var expected: Int
    var actual: Int
}

/// Builds and persists a Family A hypertrophy `ProgramDefinition`'s
/// template graph from a `HypertrophyProgramConfiguration` — the
/// "Configuration = recipe -> Program Generator -> persisted Program
/// Template Graph" half of the Stage 4 architecture. Runs once per
/// definition; the generated graph is then treated as frozen (see
/// `ProgramDefinition.generatorVersion`'s doc comment).
///
/// **Stage 10B addition:** the 3-Day Full Body Hypertrophy configuration
/// (`dayCount == 3, split == .fullBody`) now runs through a genuinely
/// content-driven day-focus/variable-slot-count path
/// (`generateDayFocusDriven`) — see `STAGE10B_IMPLEMENTATION_PLAN.md` for
/// the full design. **Every other configuration (every other split, and
/// every other `.fullBody` day count) still runs the original Stage 4A
/// logic below (`generateLegacyFixedPair`), completely unchanged** — this
/// is a deliberate one-split-first scope boundary, not an oversight;
/// Stage 10C is the named follow-up that extends the day-focus model to
/// the other curated configurations.
///
/// **Scope, stated plainly, for the legacy path:** this proves the *rule
/// engine* mechanics — day-count parameterization, the phase-specific
/// week-1 load factors, the confirmed Heavy exception, autoregulation,
/// `linkedResultReference`, and the deload-week marker — with **one
/// representative primary + paired-accessory slot pair per training
/// day**. No source workbook survives in this repository (confirmed by
/// exhaustive search during this pass's own research) to derive a
/// complete, realistic per-day exercise selection from for every
/// day-count/split combination beyond the reference configuration; that
/// content is flagged as a follow-up for whoever has access to the
/// actual Family A program content, not fabricated here with false
/// confidence. `STAGE4_IMPLEMENTATION_REPORT.md` restates this.
enum HypertrophyProgramGenerator {
    /// `1`: pre-source-recovery — every configuration, including 3-Day
    /// Full Body, used TrainingOS-invented content and/or Stage 10B.6's
    /// `.doubleProgression` engine. `2`: Stage 10R.1 Slices 1A+1B —
    /// 3-Day Full Body's day-focus-driven path now generates the literal,
    /// cell-cited Mesocycle 1 "Basic Hypertrophy" content AND progression
    /// (source-compatible `.rmBased` load, the real 24-slot rating-pairing
    /// web, `SourceCompatibleDeloadStrategy`) recovered from
    /// `3 day full body_Novice.xlsx`. `3`: Stage 10R.2A — the day-focus
    /// path is now phase-aware; `.metaboliteFocus` generates the real,
    /// cell-cited Mesocycle 2 "Metabolite Focus" content (27 slots, the
    /// superset mechanic, 0.75/0.6 load factors) instead of silently
    /// reusing Mesocycle 1's content/factor regardless of phase (the
    /// pre-10R.2A bug this stage corrects). Existing `ProgramDefinition`s
    /// keep whichever version they were generated under (`generatorVersion`
    /// doc comment); only a newly-generated definition receives the
    /// current version's content. `4`: Stage 10R.3A — the day-focus path
    /// now also generates the real, cell-cited Mesocycle 3
    /// "Resensitization" content (22 slots, no supersets, a shorter
    /// 2-progressive-week + 1-deload structure, `lengthWeeks == 3`)
    /// instead of throwing `phaseNotYetRecovered`.
    static let currentVersion = 4

    /// The 3 non-deload weeks' multipliers of the *resolved* Week-1 value
    /// — identical across every Family A phase and (per
    /// `PROGRAM_FAMILY_MATRIX.md`'s cross-family proof table) every
    /// family, so this is not itself configuration. **Used by Mesocycle
    /// 1/2 only** (4 progressive weeks) — Mesocycle 3 has just 2
    /// progressive weeks and its own, shorter
    /// `resensitizationLaterWeekMultipliers` (Stage 10R.3A).
    static let laterWeekMultipliers: [Double] = [1.05, 1.075, 1.1]

    /// Stage 10R.3A: Mesocycle 3's own later-week multiplier — a single
    /// `×1.05` step off the resolved Week-1 value, confirmed universal
    /// across all 11 Family A workbooks (`P = MROUND(J*1.05, 5)`), and the
    /// ONLY progressive step, since Mesocycle 3 has just 2 progressive
    /// weeks (not 4). A separate, shorter array rather than truncating
    /// `laterWeekMultipliers` at call time — the two mesocycle shapes are
    /// genuinely different lengths, not a subset of one another.
    static let resensitizationLaterWeekMultipliers: [Double] = [1.05]

    /// `FAMILY_A_REP_GOAL_SCHEDULE`: identical across every phase/split.
    /// Stage 10R.1D correction: the source's "N/fail" notation is an
    /// RIR/effort target, never a fixed rep count — `3/fail` means "stop
    /// with about 3 reps left," not "3 reps to failure." **Used by
    /// Mesocycle 1/2 only** — see `resensitizationRepGoalSchedule`.
    static let repGoalSchedule: [RepGoal] = [
        .rir(3), .rir(3), .rir(2), .rir(1)
    ]

    /// Stage 10R.3A: Mesocycle 3's own rep/RIR schedule — literal `3/fail`
    /// for both of its 2 progressive weeks (RIR 3, unchanged from Week 1
    /// to Week 2 — there simply is no Week 3/4 to decline further across,
    /// confirmed universal across all 11 Family A workbooks). Never a
    /// fabricated rep count (Stage 10R.1D semantics preserved).
    static let resensitizationRepGoalSchedule: [RepGoal] = [.rir(3), .rir(3)]

    /// Stage 10R.3A: how many non-deload `TrainingWeek`s the day-focus
    /// path builds for a given phase — `4` for Mesocycle 1/2 (unchanged),
    /// `2` for Mesocycle 3 (`STAGE10R3_MESOCYCLE3_SOURCE_RECOVERY_DESIGN.md`
    /// §12: the generator previously hardcoded 4 regardless of phase,
    /// which would have silently given Mesocycle 3 two extra, source-
    /// unsupported progressive weeks and a wrong `lengthWeeks`).
    private static func progressiveWeekCount(for phaseType: HypertrophyPhaseType) -> Int {
        switch phaseType {
        case .basicHypertrophy, .metaboliteFocus: return 4
        case .resensitization: return 2
        }
    }

    /// The day-focus path's own rep/RIR schedule for `phaseType` — see
    /// `repGoalSchedule`/`resensitizationRepGoalSchedule`'s doc comments.
    /// Never used by the legacy fixed-pair path, which always uses the
    /// top-level `repGoalSchedule` directly (unchanged by this stage).
    private static func dayFocusRepGoalSchedule(for phaseType: HypertrophyPhaseType) -> [RepGoal] {
        switch phaseType {
        case .basicHypertrophy, .metaboliteFocus: return repGoalSchedule
        case .resensitization: return resensitizationRepGoalSchedule
        }
    }

    /// The day-focus path's own later-week multipliers for `phaseType` —
    /// see `laterWeekMultipliers`/`resensitizationLaterWeekMultipliers`'s
    /// doc comments. Never used by the legacy fixed-pair path.
    private static func dayFocusLaterWeekMultipliers(for phaseType: HypertrophyPhaseType) -> [Double] {
        switch phaseType {
        case .basicHypertrophy, .metaboliteFocus: return laterWeekMultipliers
        case .resensitization: return resensitizationLaterWeekMultipliers
        }
    }

    /// The paired accessory's own, separate rep scheme — a genuine fixed
    /// rep target, unaffected by the primary's RIR-based schedule.
    static let pairedRepGoalSchedule: [RepGoal] = Array(repeating: .fixedReps(12), count: 4)

    /// `FAMILY_A_WEEK1_BASELINE`'s per-phase primary-movement factor.
    /// `.legs` split's confirmed Heavy exception (`FAMILY_A_LEGS_HEAVY_EXCEPTION`)
    /// overrides this to `1.0` regardless of phase — applied separately in
    /// `makeSlotPair`, not folded into this table. `.resensitization`'s
    /// `1.0` predates the day-focus path's own Mesocycle 3 recovery (it
    /// was a legacy-path value, previously unverified for the day-focus
    /// path specifically); Stage 10R.3A's archaeology now independently
    /// confirms `1.0` is the real Mesocycle 3 Week-1 factor, universal
    /// across all 11 Family A workbooks, with zero row-level exceptions.
    static func primaryWeekOneFactor(for phaseType: HypertrophyPhaseType) -> Double {
        switch phaseType {
        case .basicHypertrophy: return 0.85
        case .metaboliteFocus: return 0.75
        case .resensitization: return 1.0
        }
    }

    /// The paired accessory's own week-1 factor when it independently
    /// tests against its own RM (Metabolite Focus's documented "×0.6
    /// superset partner"). Used for `.metaboliteFocus` in the legacy
    /// path; other phases pair the accessory via `linkedResultReference`
    /// instead (see `makeSlotPair`), since no other phase's superset-
    /// partner factor is documented in the surviving Stage 3 docs.
    ///
    /// **Stage 10B reuse, flagged explicitly (not silently extended):**
    /// the day-focus-driven path's accessory slots (§10 of the
    /// implementation plan) reuse this exact constant for *every* phase,
    /// not just Metabolite Focus — because that path's accessory slots
    /// (biceps/triceps isolation) have no sensible "superset partner"
    /// relationship to any specific primary/secondary slot the way the
    /// old single-pair-per-day design's paired accessory did (loading a
    /// bicep curl as a fraction of an unrelated compound lift's absolute
    /// weight would be physically nonsensical — see the implementation
    /// report's limitations section). Reusing this already-sourced
    /// number as an independently-tested-RM factor (exactly how
    /// Metabolite Focus already uses it) is the smallest non-invented
    /// choice available; it is not itself a new training-science number.
    static let metaboliteFocusPairedWeekOneFactor = 0.6

    /// Builds one complete template graph — `lengthWeeks` `TrainingWeek`
    /// markers and one recurring weekly structure — and inserts it into
    /// `context`. Does not resolve any `ExerciseSlot` to a concrete
    /// `Exercise`; see `ExerciseSlot`'s doc comment for when that happens.
    /// The legacy fixed-pair path always builds 4 progressive + 1 deload
    /// week, for every configuration it handles, unchanged since Stage
    /// 4A. The day-focus-driven path (3-Day Full Body) is phase-aware
    /// (Stage 10R.3A): 4 progressive + 1 deload for Mesocycle 1/2, but
    /// only 2 progressive + 1 deload for Mesocycle 3 — see
    /// `progressiveWeekCount(for:)`.
    ///
    /// Throws `HypertrophyGenerationError` only for the Stage 10B
    /// reference configuration, and only if its own internal structural-
    /// coverage check fails — nothing is inserted into `context` when
    /// this throws. Every other configuration never throws (unchanged
    /// from before this stage).
    @discardableResult
    static func generate(
        configuration: HypertrophyProgramConfiguration,
        provenance: ProgramProvenance,
        context: ModelContext
    ) throws -> ProgramDefinition {
        if (configuration.dayCount == 3 || configuration.dayCount == 4 || configuration.dayCount == 5 || configuration.dayCount == 6), configuration.split == .fullBody {
            return try generateDayFocusDriven(configuration: configuration, provenance: provenance, context: context)
        }
        return generateLegacyFixedPair(configuration: configuration, provenance: provenance, context: context)
    }

    // MARK: - Legacy fixed-pair path (unchanged — every non-reference configuration)

    private static func generateLegacyFixedPair(
        configuration: HypertrophyProgramConfiguration,
        provenance: ProgramProvenance,
        context: ModelContext
    ) -> ProgramDefinition {
        let definition = ProgramDefinition(
            name: "\(configuration.dayCount)-Day \(splitName(configuration.split)) — \(phaseName(configuration.phaseType))",
            lengthWeeks: 5,
            intent: "\(phaseName(configuration.phaseType)), \(configuration.dayCount)-day \(splitName(configuration.split))",
            programmingSystem: .hypertrophy,
            generatorVersion: currentVersion,
            provenance: provenance,
            hypertrophyConfiguration: configuration
        )
        context.insert(definition)

        for _ in 0..<4 {
            let week = TrainingWeek(isDeload: false)
            context.insert(week)
            definition.addWeek(week)
        }
        let deloadWeek = TrainingWeek(isDeload: true)
        context.insert(deloadWeek)
        definition.addWeek(deloadWeek)

        for dayIndex in 0..<configuration.dayCount {
            let session = TemplateSession(name: "Day \(dayIndex + 1)", role: .hypertrophy)
            context.insert(session)
            definition.addTemplateSession(session)

            let block = WorkoutBlockTemplate(type: .hypertrophy)
            context.insert(block)
            session.addBlockTemplate(block)

            let (primary, primarySlot, paired, pairedSlot) = makeSlotPair(dayIndex: dayIndex, configuration: configuration)
            context.insert(primary)
            context.insert(primarySlot)
            primary.attachExerciseSlot(primarySlot)
            block.addPrescriptionTemplate(primary)

            context.insert(paired)
            context.insert(pairedSlot)
            paired.attachExerciseSlot(pairedSlot)
            paired.pairedSlot = primary
            block.addPrescriptionTemplate(paired)

            // `primary.setCountRule` is always `.autoregulated`, whose
            // rating source is `pairedSlot` (`StrengthProgressionRules.swift`'s
            // `SetCountRule.autoregulated` doc comment: "mirroring
            // `LoadRule.linkedToPairedSlot`'s pattern, not duplicated
            // here") — the same field `paired` above uses for its own load
            // link, just read for a different rule on a different row.
            // Without this, `AutoregulationRatingResolver.rating(for: primary)`
            // can never find a rating source and week 1+ set counts stay
            // permanently `.calibrationRequired`, regardless of any real
            // feedback collected on `paired`.
            primary.pairedSlot = paired
        }

        return definition
    }

    private static func makeSlotPair(
        dayIndex: Int,
        configuration: HypertrophyProgramConfiguration
    ) -> (primary: PrescriptionTemplate, primarySlot: ExerciseSlot, paired: PrescriptionTemplate, pairedSlot: ExerciseSlot) {
        // `.legs` split's confirmed Heavy exception: the Heavy Quads/Glutes
        // category uses the full (1.0) baseline instead of the phase's
        // usual primary factor (`FAMILY_A_LEGS_HEAVY_EXCEPTION`) — applied
        // to day 1 of a `.legs` program as the representative "Heavy" day.
        // **Left exactly as-is for this legacy path** (positional, day-
        // index-based) — Stage 10B does not touch `.legs`; see
        // `isHeavyQuadsGlutesException` below for the content-based
        // reformulation Stage 10C should switch this path to once it
        // generalizes `.legs` to the day-focus model (D-10B-5).
        let isHeavyLegsException = configuration.split == .legs && dayIndex == 0
        let weekOneFactor = isHeavyLegsException ? 1.0 : primaryWeekOneFactor(for: configuration.phaseType)

        let primary = PrescriptionTemplate(rules: StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: weekOneFactor, laterWeekMultipliers: laterWeekMultipliers)),
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 3)),
            repGoalSchedule: repGoalSchedule
        ))
        let primarySlot = ExerciseSlot(
            name: isHeavyLegsException ? "Heavy Quads/Glutes" : primarySlotName(dayIndex: dayIndex, split: configuration.split),
            allowedTargets: primaryTargets(dayIndex: dayIndex, split: configuration.split)
        )

        // Metabolite Focus's superset partner independently tests against
        // its own RM at a lower factor (documented); every other phase
        // pairs the accessory via `linkedResultReference` instead, since
        // no other phase's superset-partner factor survives in the Stage 3
        // docs — this is the one place this generator demonstrates
        // `linkedResultReference` specifically, with a representative
        // (not source-cited) 0.6 fraction.
        let pairedLoadRule: LoadRule = configuration.phaseType == .metaboliteFocus
            ? .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: metaboliteFocusPairedWeekOneFactor, laterWeekMultipliers: laterWeekMultipliers))
            : .linkedToPairedSlot(fractionOfSourceResult: 0.6)

        let paired = PrescriptionTemplate(rules: StrengthProgressionRules(
            loadRule: pairedLoadRule,
            setCountRule: .fixed(setsByWeek: [2, 2, 2, 2]),
            repGoalSchedule: pairedRepGoalSchedule,
            // The confirmed Family-A-Mesocycle-2 superset-partner deload
            // case (Stage 3 decision A2) — this representative paired slot
            // is exactly that slot.
            deloadWeightAction: .omit,
            deloadRepAction: .omit
        ))
        let pairedSlot = ExerciseSlot(name: "Chest Isolation or Triceps", allowedTargets: [.chest, .triceps])

        return (primary, primarySlot, paired, pairedSlot)
    }

    private static func primarySlotName(dayIndex: Int, split: HypertrophySplit) -> String {
        switch split {
        case .fullBody: return "Horizontal Push"
        case .legs: return "Squat Pattern"
        case .armsShoulders: return "Overhead Press"
        case .backChest: return "Horizontal Pull"
        }
    }

    private static func primaryTargets(dayIndex: Int, split: HypertrophySplit) -> [MuscleGroup] {
        switch split {
        case .fullBody: return [.chest, .shoulders]
        case .legs: return [.quadriceps, .glutes]
        case .armsShoulders: return [.shoulders, .triceps]
        case .backChest: return [.back, .biceps]
        }
    }

    private static func splitName(_ split: HypertrophySplit) -> String {
        switch split {
        case .fullBody: return "Full Body"
        case .legs: return "Legs"
        case .armsShoulders: return "Arms/Shoulders"
        case .backChest: return "Back/Chest"
        }
    }

    private static func phaseName(_ phaseType: HypertrophyPhaseType) -> String {
        switch phaseType {
        case .basicHypertrophy: return "Basic Hypertrophy"
        case .metaboliteFocus: return "Metabolite Focus"
        case .resensitization: return "Resensitization"
        }
    }

    // MARK: - Stage 10B: day-focus-driven path (3-Day Full Body Hypertrophy only)

    /// One training day's programming *intent*, expressed purely as
    /// muscle-group emphasis tiers — never exercise names
    /// (`STAGE10B_IMPLEMENTATION_PLAN.md` §4). `secondary`/`accessory` may
    /// legitimately be empty (Day C has no secondary tier) — a session is
    /// never forced to contain every `SlotRole`.
    struct HypertrophyDayFocus: Equatable {
        var name: String
        var primary: [MuscleGroup]
        var secondary: [MuscleGroup]
        var accessory: [MuscleGroup]
    }

    /// **Retired, Stage 10R.1 Slice 1A** — this TrainingOS-invented Day
    /// A/B/C rotation is no longer authoritative for any generated
    /// program. It has been replaced by the literal, cell-cited Mesocycle
    /// 1 "Basic Hypertrophy" category sequence recovered from the real
    /// `3 day full body_Novice.xlsx` workbook — see
    /// `threeDayFullBodyMesocycle1BasicHypertrophy` below and
    /// `SOURCE_PROGRAM_MANIFEST.md` §3. `HypertrophyDayFocus`/
    /// `validateWeeklyCoverage`/`trackedMuscleGroups`/
    /// `expectedWeeklyExposure` remain declared below — they are a generic
    /// coverage-checking *mechanism*, still exercised by their own
    /// pure-function unit tests, not themselves invented program content —
    /// but nothing in production calls them with this retired rotation
    /// any longer.

    /// The 9 muscle groups Stage 10B's coverage check reasons over —
    /// exactly `STAGE10A_PROGRAMMING_ENGINE_AUDIT.md`'s originally
    /// approved list. (Blocker 1: an earlier draft of this stage excluded
    /// `.calves` because the Day A/B/C prose never named it — the product
    /// owner corrected this: the 9-group requirement stands, and calves'
    /// intentional placement is `threeDayFullBodyRotation`'s job, not
    /// this list's.)
    static let trackedMuscleGroups: [MuscleGroup] = [
        .chest, .back, .quadriceps, .hamstrings, .glutes, .shoulders, .biceps, .triceps, .calves
    ]

    /// The approved Stage 10B V1 weekly exposure **policy** — an explicit,
    /// intentional exposure count per tracked group, never a derived
    /// "however many days happen to include it" count and never a
    /// mathematically-symmetric "every group 3×" rule. 8 of the 9 groups
    /// are exposed on all 3 days — an outcome of the approved Day A/B/C
    /// emphasis definitions, not a separate symmetry rule. `.calves` is
    /// the one deliberately different case: 2×/week, accessory-only, per
    /// the product owner's explicit V1 policy (historical Stage 10B
    /// placement reasoning, now retired along with the rotation itself —
    /// see the retirement note above). `validateWeeklyCoverage` checks
    /// whatever table it's given against this policy
    /// against this policy exactly — a group appearing MORE or FEWER
    /// times than its expected count is a reportable mismatch, not just a
    /// "did it appear at all" check.
    static let expectedWeeklyExposure: [MuscleGroup: Int] = [
        .chest: 3, .back: 3, .quadriceps: 3, .hamstrings: 3, .glutes: 3,
        .shoulders: 3, .biceps: 3, .triceps: 3, .calves: 2
    ]

    /// TRAININGOS-designed movement-pattern groupings — which muscle
    /// groups a single compound movement realistically trains together,
    /// mirroring the exact multi-target-slot shape the legacy path
    /// already used (e.g. its own "Squat Pattern" -> `[.quadriceps,
    /// .glutes]`, "Horizontal Push" -> `[.chest, .shoulders]`). Not
    /// sourced from an external hypertrophy spec — a content/grouping
    /// heuristic, matching this generator's own established discipline of
    /// TRAININGOS-designed illustrative defaults where no source survives
    /// (see this file's own top-level doc comment). Checked in this
    /// fixed order — most-specific/most-already-established pairings
    /// first — so a well-known 2-group pattern claims its groups before
    /// the smaller "whatever's left, one solo slot each" fallback runs.
    /// `.biceps`/`.triceps` deliberately have no grouping entry — Stage
    /// 10B's accessory tier always resolves them as 2 distinct solo slots
    /// (D-10B-6 asks for separate biceps/triceps candidates specifically,
    /// not one combined "arms" slot).
    ///
    /// **Blocker 2 fix — `movementFunctions` (Stage 10B slot-intent seam):**
    /// each grouping now also carries the `MovementFunction`(s) that
    /// distinguish it from every OTHER compound pattern sharing an
    /// overlapping muscle-group target. "Squat Pattern" and "Hinge
    /// Pattern" both include `.glutes` — muscle-group overlap alone
    /// therefore cannot tell them apart (the exact bug that let Front
    /// Squat satisfy a hinge-intent slot). This reuses the **existing**,
    /// already-generic `ExerciseSlot.allowedMovementFunctions`/
    /// `Exercise.movementFunctions` seam Stage 4E already built for
    /// Functional Fitness movement slots and `SubstitutionValidator.isValid`
    /// already enforces — no new field, no new enum case, no second
    /// selection engine. Solo leftover slots (a single muscle group with
    /// no compound-pattern competitor in this reference config — e.g.
    /// "Quadriceps," "Hamstrings," "Back," every accessory slot) are
    /// deliberately left with an empty `[MovementFunction]` (no
    /// constraint): nothing else in the catalog could plausibly satisfy
    /// them via muscle-group overlap alone, so adding a constraint there
    /// would narrow legitimate candidates (e.g. Leg Curl for a solo
    /// "Hamstrings" slot) without fixing any demonstrated ambiguity.
    private static let movementPatternGroupings: [(name: String, groups: Set<MuscleGroup>, movementFunctions: [MovementFunction])] = [
        ("Squat Pattern", [.quadriceps, .glutes], [.squatLoaded]),
        ("Horizontal Push", [.chest, .shoulders], [.pressLoaded]),
        ("Hinge Pattern", [.hamstrings, .glutes], [.hingeLoaded]),
    ]

    /// The `MovementFunction` intent to constrain a generated slot with —
    /// `[]` (no constraint) unless `targets` exactly matches one of
    /// `movementPatternGroupings`' known compound patterns. See that
    /// table's own doc comment for why solo slots are intentionally left
    /// unconstrained.
    private static func movementFunctionIntent(for targets: [MuscleGroup]) -> [MovementFunction] {
        let set = Set(targets)
        return movementPatternGroupings.first(where: { $0.groups == set })?.movementFunctions ?? []
    }

    /// Groups a tier's raw muscle-group list into slots — the "variable
    /// count is an output" mechanic (D-10B-2). Walks
    /// `movementPatternGroupings` in priority order, claiming every
    /// pattern whose full group-set is still uncovered; whatever remains
    /// afterward becomes one solo slot per group, in original list order
    /// (deterministic — no randomness, no dependency on `Set` iteration
    /// order). Never invents a slot for a muscle group not present in
    /// `groups`, and never merges two groups the fixed table above
    /// doesn't already pair.
    static func groupMuscleGroups(_ groups: [MuscleGroup]) -> [[MuscleGroup]] {
        guard !groups.isEmpty else { return [] }
        var remaining = Set(groups)
        var result: [[MuscleGroup]] = []

        for pattern in movementPatternGroupings where pattern.groups.isSubset(of: remaining) {
            // Preserve `groups`' own original ordering within the emitted
            // slot, rather than `Set`'s unordered storage order.
            result.append(groups.filter { pattern.groups.contains($0) })
            remaining.subtract(pattern.groups)
        }
        for group in groups where remaining.contains(group) {
            result.append([group])
            remaining.remove(group)
        }
        return result
    }

    /// A friendly, content-derived label — reuses `movementPatternGroupings`'s
    /// own name when a slot's targets exactly match a known pattern, else
    /// falls back to the muscle group name(s) themselves. Display only;
    /// never read by any matching/validation logic.
    private static func slotLabel(for groups: [MuscleGroup]) -> String {
        let set = Set(groups)
        if let pattern = movementPatternGroupings.first(where: { $0.groups == set }) {
            return pattern.name
        }
        return groups.map { $0.rawValue.capitalized }.joined(separator: "/")
    }

    /// Stage 10B's structural weekly-coverage report — see
    /// `STAGE10B_IMPLEMENTATION_PLAN.md` §6. Purely derived from the
    /// day-focus table itself; never persisted, never re-derived from
    /// live user history (mirrors `StrengthMaterializer`'s own "no stored
    /// `Recommendation` reasoning, just re-run the pure function"
    /// precedent).
    struct WeeklyCoverageReport: Equatable {
        var mismatches: [MuscleGroupExposureMismatch]
        var duplicateDayNames: [String]
        var exposureCountByGroup: [MuscleGroup: Int]
    }

    /// Checks the approved programming contract exactly (Blocker 1's
    /// correction): every tracked muscle group's actual weekly exposure
    /// must match `expectedWeeklyExposure`'s explicit per-group policy —
    /// most groups 3×, calves 2× — never "must appear at least once" and
    /// never "must appear exactly 3× because this is a 3-day program."
    /// Also checks no two days share an identical `(primary, secondary,
    /// accessory)` triple. Deliberately **not** bounded by any MEV/MAV/
    /// MRV-style ceiling beyond this explicit policy — `exposureCountByGroup`
    /// is always reported so a caller can display the real map (e.g. the
    /// implementation report's exposure table), not just pass/fail.
    static func validateWeeklyCoverage(dayFocuses: [HypertrophyDayFocus]) -> WeeklyCoverageReport {
        var exposureCountByGroup: [MuscleGroup: Int] = [:]
        for group in trackedMuscleGroups { exposureCountByGroup[group] = 0 }

        for focus in dayFocuses {
            let unionForDay = Set(focus.primary + focus.secondary + focus.accessory)
            for group in unionForDay where exposureCountByGroup[group] != nil {
                exposureCountByGroup[group, default: 0] += 1
            }
        }

        let mismatches = trackedMuscleGroups.compactMap { group -> MuscleGroupExposureMismatch? in
            let expected = expectedWeeklyExposure[group] ?? 0
            let actual = exposureCountByGroup[group] ?? 0
            return expected == actual ? nil : MuscleGroupExposureMismatch(group: group, expected: expected, actual: actual)
        }

        // Keys on the 3 tiers *separately joined*, not concatenated, so
        // two days whose flattened muscle-group lists happen to coincide
        // but whose primary/secondary/accessory boundaries differ are
        // never mistaken for identical focus.
        var seenTriples: [String: String] = [:]
        var duplicateDayNames: [String] = []
        for focus in dayFocuses {
            let key = [focus.primary, focus.secondary, focus.accessory]
                .map { tier in tier.map(\.rawValue).joined(separator: ",") }
                .joined(separator: "|")
            if let firstName = seenTriples[key] {
                duplicateDayNames.append(contentsOf: [firstName, focus.name])
            } else {
                seenTriples[key] = focus.name
            }
        }

        return WeeklyCoverageReport(
            mismatches: mismatches, duplicateDayNames: Array(Set(duplicateDayNames)).sorted(),
            exposureCountByGroup: exposureCountByGroup
        )
    }

    /// Content-based detection of the confirmed `.legs`-split Heavy
    /// Quads/Glutes exception (D-10B-5) — matches on *what a slot trains
    /// and how central it is to the day*, never on day index or slot
    /// position. Written generically so both this stage's day-focus path
    /// and a future Stage 10C generalization of `.legs` can share one
    /// definition; **always evaluates `false` under Stage 10B's actual
    /// scope**, since the exception is source-gated to `.legs` and this
    /// stage's day-focus path only ever runs for `.fullBody` — see
    /// `generate()`'s branch condition. The legacy `.legs` path above
    /// deliberately keeps its own original, unrelated positional check
    /// (`dayIndex == 0`) rather than being switched to call this helper,
    /// since doing so would change which days receive the exception for
    /// every existing `.legs` program (every day's primary slot targets
    /// `[.quadriceps, .glutes]` under the legacy generator, so content-
    /// based matching would fire on all of them, not just day 0) — an
    /// unrequested behavior change to a configuration Stage 10B does not
    /// touch. Left here, ready for Stage 10C to wire in once `.legs`
    /// itself moves to a day-focus table where the exception's target
    /// slot is no longer every day's primary.
    static func isHeavyQuadsGlutesException(role: SlotRole, targets: [MuscleGroup], split: HypertrophySplit) -> Bool {
        role == .primary && split == .legs && Set(targets) == Set([.quadriceps, .glutes])
    }

    // MARK: - Stage 10R.1 Slice 1A: real source content, Mesocycle 1 only

    /// One category slot exactly as it appears in the real source
    /// workbook — `sourceLabel` preserves the literal display text found
    /// in the cell (Decision 3: provenance audit trail), `category` is
    /// the canonical identity it normalizes to, `weekOneSets` is the
    /// literal Week-1 baseline sets recovered from the workbook's own `I`
    /// column. Nothing here is derived, rebalanced, or invented — see
    /// `SOURCE_PROGRAM_MANIFEST.md` §3 for the cell-by-cell citation.
    struct SourceCategorySlot: Equatable {
        var sourceLabel: String
        var category: SourceHypertrophyCategory
        var weekOneSets: Int
        /// Stage 10R.2A: Mesocycle 2's confirmed superset mechanic
        /// (`3 day full body_Novice.xlsx`, cells `'Super set this
        /// exercise'`/`'with this one'`) — `true` only for the 3
        /// confirmed partner rows. Defaults to `false`, so
        /// `threeDayFullBodyMesocycle1BasicHypertrophy` needs zero
        /// changes. Governs 3 cell-confirmed things: the partner's own RM
        /// tests at `metaboliteFocusPairedWeekOneFactor` (0.6) rather than
        /// the phase's normal primary factor (0.75); the partner is
        /// completely omitted from deload (its deload-week cells are
        /// blank, not zero — `STAGE3_DECISION_MEMO.md` Decision A2); and
        /// its rating-pairing target is the SAME external row its own
        /// primary reads (`SourceRatingPairing`, not a new mechanism).
        var isSupersetPartner: Bool = false
        /// Stage 10R.2A: confirmed by direct formula trace that exactly
        /// one of the 3 Mesocycle 2 superset partners (Pull Emphasis's
        /// Biceps partner) does not cascade through its primary's later-
        /// week values the way the other two do — its Week 2 value
        /// (`=I38+(S16)`) is reused unchanged for Weeks 3 and 4 rather
        /// than advancing. Mathematically identical to `AutoregulatedSetCount
        /// .freezeAfterWeek`'s existing semantics (already proven for
        /// Family C) — `1` (0-indexed weekIndex) pins this slot's set
        /// count at whatever weekIndex 1 (Week 2) resolves to. `nil`
        /// (default) for every other row, including the other 2 superset
        /// partners, which cascade normally.
        var freezeAfterWeek: Int? = nil
    }

    /// One real source training day — `sourceEmphasisName` is the literal
    /// workbook day-emphasis label ("Push Emphasis," etc.), `categories`
    /// is the literal, exact-order category sequence for that day.
    struct SourceDay: Equatable {
        var sourceEmphasisName: String
        var categories: [SourceCategorySlot]
    }

    /// Recovered verbatim from `3 day full body_Novice.xlsx`, sheet
    /// "Mesocycle 1 Basic Hypertrophy," rows 10-40
    /// (`SOURCE_PROGRAM_MANIFEST.md` §3) — the ONLY source of day/category
    /// truth for this configuration's Mesocycle 1. Mesocycle 2 ("Metabolite
    /// Focus," with its superset mechanic) and Mesocycle 3
    /// ("Resensitization") are recovered and documented but deliberately
    /// **not** implemented yet — Slice 1A's explicit scope is Mesocycle 1
    /// only (see the Stage 10R.1 recovery-order decision).
    static let threeDayFullBodyMesocycle1BasicHypertrophy: [SourceDay] = [
        SourceDay(sourceEmphasisName: "Push Emphasis", categories: [
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Chest Isolation or Triceps", category: .chestIsolationOrTriceps, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Incline Push or Front Delts", category: .inclinePushOrFrontDelts, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Side Delts", category: .sideDelts, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Hamstrings Isolation", category: .hamstringsIsolation, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 2),
        ]),
        SourceDay(sourceEmphasisName: "Legs Emphasis", categories: [
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Hamstrings Hip Hinge", category: .hamstringsHipHinge, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Side Delts", category: .sideDelts, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Incline Push or Front Delts", category: .inclinePushOrFrontDelts, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 2),
        ]),
        SourceDay(sourceEmphasisName: "Pull Emphasis", categories: [
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Rear Delts or Side Delts", category: .rearOrSideDelts, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Incline Push", category: .inclinePush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Glutes", category: .glutes, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Hamstrings Isolation", category: .hamstringsIsolation, weekOneSets: 2),
        ]),
    ]

    // MARK: - Stage 10R.1 Slice 1B: real source progression + autoregulation pairing

    /// Stage 10R.1 Slice 1B: the source workbook's real, fixed,
    /// authoring-time rating-pairing web, recovered cell-by-cell
    /// (`STAGE10R1_SLICE1B_SOURCE_PROGRESSION_DESIGN.md` Part 2) — the
    /// slot at `(dayIndex, slotIndex)` (indices into
    /// `threeDayFullBodyMesocycle1BasicHypertrophy` itself: `dayIndex`
    /// selects the `SourceDay`, `slotIndex` the 0-based position within
    /// that day's `categories`, matching workbook row order exactly)
    /// rates itself using the paired slot at `(pairedDayIndex,
    /// pairedSlotIndex)`'s most recently logged rating. This is a
    /// structural, per-row reference fixed at authoring time — **not** a
    /// dynamically-recomputed "most recent occurrence of this category"
    /// search: every one of the 24 rows was confirmed to reference the
    /// identical source row for all 3 week transitions (Week1->2 reads
    /// column M, Week2->3 reads S, Week3->4 reads Y, always the same
    /// row). Mechanically identical to `PrescriptionTemplate.pairedSlot`'s
    /// existing shape (Stage 3 decision A5) — this table only supplies
    /// the correct *target* for that existing field, replacing Slice 1A's
    /// temporary self-reference.
    struct SourceRatingPairing: Equatable {
        var dayIndex: Int
        var slotIndex: Int
        var pairedDayIndex: Int
        var pairedSlotIndex: Int
    }

    static let threeDayFullBodyMesocycle1RatingPairings: [SourceRatingPairing] = [
        // Push Emphasis (day 0), rows 11-18
        SourceRatingPairing(dayIndex: 0, slotIndex: 0, pairedDayIndex: 1, pairedSlotIndex: 7), // Horizontal Push <- Legs Horizontal Push (row11<-row29)
        SourceRatingPairing(dayIndex: 0, slotIndex: 1, pairedDayIndex: 1, pairedSlotIndex: 7), // Chest Isolation or Triceps <- Legs Horizontal Push (row12<-row29)
        SourceRatingPairing(dayIndex: 0, slotIndex: 2, pairedDayIndex: 1, pairedSlotIndex: 6), // Incline Push or Front Delts <- Legs Incline Push or Front Delts (row13<-row28)
        SourceRatingPairing(dayIndex: 0, slotIndex: 3, pairedDayIndex: 1, pairedSlotIndex: 3), // Side Delts <- Legs Side Delts (row14<-row25)
        SourceRatingPairing(dayIndex: 0, slotIndex: 4, pairedDayIndex: 1, pairedSlotIndex: 4), // Vertical Pull <- Legs Vertical Pull (row15<-row26)
        SourceRatingPairing(dayIndex: 0, slotIndex: 5, pairedDayIndex: 1, pairedSlotIndex: 5), // Horizontal Pull <- Legs Horizontal Pull (row16<-row27)
        SourceRatingPairing(dayIndex: 0, slotIndex: 6, pairedDayIndex: 1, pairedSlotIndex: 2), // Hamstrings Isolation <- Legs Hamstrings Hip Hinge (row17<-row24)
        SourceRatingPairing(dayIndex: 0, slotIndex: 7, pairedDayIndex: 1, pairedSlotIndex: 0), // Quads <- Legs Quads 1st (row18<-row22)

        // Legs Emphasis (day 1), rows 22-29
        SourceRatingPairing(dayIndex: 1, slotIndex: 0, pairedDayIndex: 0, pairedSlotIndex: 7), // Quads 1st <- Push Quads (row22<-row18)
        SourceRatingPairing(dayIndex: 1, slotIndex: 1, pairedDayIndex: 0, pairedSlotIndex: 7), // Quads 2nd <- Push Quads (row23<-row18)
        SourceRatingPairing(dayIndex: 1, slotIndex: 2, pairedDayIndex: 2, pairedSlotIndex: 7), // Hamstrings Hip Hinge <- Pull Hamstrings Isolation (row24<-row40)
        SourceRatingPairing(dayIndex: 1, slotIndex: 3, pairedDayIndex: 2, pairedSlotIndex: 2), // Side Delts <- Pull Rear Delts or Side Delts (row25<-row35)
        SourceRatingPairing(dayIndex: 1, slotIndex: 4, pairedDayIndex: 2, pairedSlotIndex: 0), // Vertical Pull <- Pull Vertical Pull (row26<-row33)
        SourceRatingPairing(dayIndex: 1, slotIndex: 5, pairedDayIndex: 2, pairedSlotIndex: 1), // Horizontal Pull <- Pull Horizontal Pull (row27<-row34)
        SourceRatingPairing(dayIndex: 1, slotIndex: 6, pairedDayIndex: 2, pairedSlotIndex: 5), // Incline Push or Front Delts <- Pull Incline Push (row28<-row38)
        SourceRatingPairing(dayIndex: 1, slotIndex: 7, pairedDayIndex: 2, pairedSlotIndex: 4), // Horizontal Push <- Pull Horizontal Push (row29<-row37)

        // Pull Emphasis (day 2), rows 33-40
        SourceRatingPairing(dayIndex: 2, slotIndex: 0, pairedDayIndex: 0, pairedSlotIndex: 4), // Vertical Pull <- Push Vertical Pull (row33<-row15)
        SourceRatingPairing(dayIndex: 2, slotIndex: 1, pairedDayIndex: 0, pairedSlotIndex: 5), // Horizontal Pull <- Push Horizontal Pull (row34<-row16)
        SourceRatingPairing(dayIndex: 2, slotIndex: 2, pairedDayIndex: 0, pairedSlotIndex: 3), // Rear Delts or Side Delts <- Push Side Delts (row35<-row14)
        SourceRatingPairing(dayIndex: 2, slotIndex: 3, pairedDayIndex: 0, pairedSlotIndex: 4), // Biceps <- Push Vertical Pull (row36<-row15)
        SourceRatingPairing(dayIndex: 2, slotIndex: 4, pairedDayIndex: 0, pairedSlotIndex: 0), // Horizontal Push <- Push Horizontal Push (row37<-row11)
        SourceRatingPairing(dayIndex: 2, slotIndex: 5, pairedDayIndex: 0, pairedSlotIndex: 0), // Incline Push <- Push Horizontal Push (row38<-row11)
        SourceRatingPairing(dayIndex: 2, slotIndex: 6, pairedDayIndex: 1, pairedSlotIndex: 2), // Glutes <- Legs Hamstrings Hip Hinge (row39<-row24)
        SourceRatingPairing(dayIndex: 2, slotIndex: 7, pairedDayIndex: 0, pairedSlotIndex: 6), // Hamstrings Isolation <- Push Hamstrings Isolation (row40<-row17)
    ]

    // MARK: - Stage 10R.2A: real source content, Mesocycle 2 (Metabolite Focus)

    /// Recovered verbatim from `3 day full body_Novice.xlsx`, sheet
    /// "Mesocycle 2 Metabolite Focus," rows 11-19 (Push), 23-31 (Legs),
    /// 35-43 (Pull) — the ONLY source of day/category truth for this
    /// configuration's Mesocycle 2. Same day names, and largely the same
    /// categories, as Mesocycle 1, but NOT copied from it — every row
    /// below was independently read from the Mesocycle 2 sheet itself,
    /// including its own Week-1 baseline sets (which differ from
    /// Mesocycle 1's in several rows) and its own superset mechanic (3
    /// pairs, one per day, cell-confirmed via `'Super set this
    /// exercise'`/`'with this one'` markers — not present in Mesocycle 1
    /// at all). Mesocycle 3 ("Resensitization") is out of this stage's
    /// scope — see `HypertrophyGenerationError.phaseNotYetRecovered`.
    static let threeDayFullBodyMesocycle2MetaboliteFocus: [SourceDay] = [
        SourceDay(sourceEmphasisName: "Push Emphasis", categories: [
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Chest Isolation or Triceps", category: .chestIsolationOrTriceps, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Incline Push or Front Delts", category: .inclinePushOrFrontDelts, weekOneSets: 4, isSupersetPartner: true),
            SourceCategorySlot(sourceLabel: "Incline Push or Front Delts", category: .inclinePushOrFrontDelts, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Side Delts", category: .sideDelts, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Hamstrings Isolation", category: .hamstringsIsolation, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 2),
        ]),
        SourceDay(sourceEmphasisName: "Legs Emphasis", categories: [
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Hamstrings Hip Hinge", category: .hamstringsHipHinge, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Side Delts", category: .sideDelts, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Side Delts", category: .sideDelts, weekOneSets: 3, isSupersetPartner: true),
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Incline Push or Front Delts", category: .inclinePushOrFrontDelts, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 2),
        ]),
        SourceDay(sourceEmphasisName: "Pull Emphasis", categories: [
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Rear Delts or Side Delts", category: .rearOrSideDelts, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 3, isSupersetPartner: true, freezeAfterWeek: 1),
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Incline Push", category: .inclinePush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Glutes", category: .glutes, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Hamstrings Isolation", category: .hamstringsIsolation, weekOneSets: 2),
        ]),
    ]

    /// Stage 10R.2A: Mesocycle 2's real, fixed, authoring-time rating-
    /// pairing web, recovered cell-by-cell from the same sheet — same
    /// `(dayIndex, slotIndex)` convention as `threeDayFullBodyMesocycle1RatingPairings`,
    /// indexing into `threeDayFullBodyMesocycle2MetaboliteFocus` itself.
    /// Every superset partner's own pairing target is confirmed to be the
    /// SAME external row its own primary reads (never its own,
    /// independent rating column, and never a different target) — the
    /// existing `PrescriptionTemplate.pairedSlot`/`SourceRatingPairing`
    /// mechanism reproduces this exactly with no new architecture: giving
    /// the partner an ordinary `.autoregulated` rule pointed at the same
    /// external target its primary uses means the partner's resolved set
    /// count is mathematically identical to (or, for the one frozen pair,
    /// derived once from) the primary's own — never the partner's own
    /// independent feedback.
    static let threeDayFullBodyMesocycle2RatingPairings: [SourceRatingPairing] = [
        // Push Emphasis (day 0), rows 11-19
        SourceRatingPairing(dayIndex: 0, slotIndex: 0, pairedDayIndex: 1, pairedSlotIndex: 8), // Horizontal Push <- Legs Horizontal Push
        SourceRatingPairing(dayIndex: 0, slotIndex: 1, pairedDayIndex: 1, pairedSlotIndex: 8), // Chest Isolation or Triceps <- Legs Horizontal Push
        SourceRatingPairing(dayIndex: 0, slotIndex: 2, pairedDayIndex: 1, pairedSlotIndex: 8), // Incline Push or Front Delts (partner) <- same target as slot 1's own primary
        SourceRatingPairing(dayIndex: 0, slotIndex: 3, pairedDayIndex: 1, pairedSlotIndex: 7), // Incline Push or Front Delts (standalone) <- Legs Incline Push or Front Delts
        SourceRatingPairing(dayIndex: 0, slotIndex: 4, pairedDayIndex: 1, pairedSlotIndex: 3), // Side Delts <- Legs Side Delts
        SourceRatingPairing(dayIndex: 0, slotIndex: 5, pairedDayIndex: 1, pairedSlotIndex: 5), // Vertical Pull <- Legs Vertical Pull
        SourceRatingPairing(dayIndex: 0, slotIndex: 6, pairedDayIndex: 1, pairedSlotIndex: 6), // Horizontal Pull <- Legs Horizontal Pull
        SourceRatingPairing(dayIndex: 0, slotIndex: 7, pairedDayIndex: 1, pairedSlotIndex: 2), // Hamstrings Isolation <- Legs Hamstrings Hip Hinge
        SourceRatingPairing(dayIndex: 0, slotIndex: 8, pairedDayIndex: 1, pairedSlotIndex: 0), // Quads <- Legs Quads 1st

        // Legs Emphasis (day 1), rows 23-31
        SourceRatingPairing(dayIndex: 1, slotIndex: 0, pairedDayIndex: 0, pairedSlotIndex: 8), // Quads 1st <- Push Quads
        SourceRatingPairing(dayIndex: 1, slotIndex: 1, pairedDayIndex: 0, pairedSlotIndex: 8), // Quads 2nd <- Push Quads
        SourceRatingPairing(dayIndex: 1, slotIndex: 2, pairedDayIndex: 2, pairedSlotIndex: 8), // Hamstrings Hip Hinge <- Pull Hamstrings Isolation
        SourceRatingPairing(dayIndex: 1, slotIndex: 3, pairedDayIndex: 2, pairedSlotIndex: 2), // Side Delts (primary) <- Pull Rear Delts or Side Delts
        SourceRatingPairing(dayIndex: 1, slotIndex: 4, pairedDayIndex: 2, pairedSlotIndex: 2), // Side Delts (partner) <- same target as slot 3's own primary
        SourceRatingPairing(dayIndex: 1, slotIndex: 5, pairedDayIndex: 2, pairedSlotIndex: 0), // Vertical Pull <- Pull Vertical Pull
        SourceRatingPairing(dayIndex: 1, slotIndex: 6, pairedDayIndex: 2, pairedSlotIndex: 1), // Horizontal Pull <- Pull Horizontal Pull
        SourceRatingPairing(dayIndex: 1, slotIndex: 7, pairedDayIndex: 2, pairedSlotIndex: 6), // Incline Push or Front Delts <- Pull Incline Push
        SourceRatingPairing(dayIndex: 1, slotIndex: 8, pairedDayIndex: 2, pairedSlotIndex: 5), // Horizontal Push <- Pull Horizontal Push

        // Pull Emphasis (day 2), rows 35-43
        SourceRatingPairing(dayIndex: 2, slotIndex: 0, pairedDayIndex: 0, pairedSlotIndex: 5), // Vertical Pull <- Push Vertical Pull
        SourceRatingPairing(dayIndex: 2, slotIndex: 1, pairedDayIndex: 0, pairedSlotIndex: 6), // Horizontal Pull <- Push Horizontal Pull
        SourceRatingPairing(dayIndex: 2, slotIndex: 2, pairedDayIndex: 0, pairedSlotIndex: 4), // Rear Delts or Side Delts <- Push Side Delts
        SourceRatingPairing(dayIndex: 2, slotIndex: 3, pairedDayIndex: 0, pairedSlotIndex: 5), // Biceps (primary) <- Push Vertical Pull
        SourceRatingPairing(dayIndex: 2, slotIndex: 4, pairedDayIndex: 0, pairedSlotIndex: 5), // Biceps (partner) <- same target as slot 3's own primary
        SourceRatingPairing(dayIndex: 2, slotIndex: 5, pairedDayIndex: 0, pairedSlotIndex: 0), // Horizontal Push <- Push Horizontal Push
        SourceRatingPairing(dayIndex: 2, slotIndex: 6, pairedDayIndex: 0, pairedSlotIndex: 0), // Incline Push <- Push Horizontal Push
        SourceRatingPairing(dayIndex: 2, slotIndex: 7, pairedDayIndex: 1, pairedSlotIndex: 2), // Glutes <- Legs Hamstrings Hip Hinge
        SourceRatingPairing(dayIndex: 2, slotIndex: 8, pairedDayIndex: 0, pairedSlotIndex: 7), // Hamstrings Isolation <- Push Hamstrings Isolation
    ]

    // MARK: - Stage 10R.3A: real source content, Mesocycle 3 (Resensitization)

    /// Recovered verbatim from `3 day full body_Novice.xlsx`, sheet
    /// "Mesocycle 3 Resensitization," rows 11-17 (Push), 21-27 (Legs),
    /// 31-38 (Pull) — the ONLY source of day/category truth for this
    /// configuration's Mesocycle 3
    /// (`STAGE10R3_MESOCYCLE3_SOURCE_RECOVERY_DESIGN.md` §2). A genuinely
    /// shorter/different structure from Mesocycle 1/2, not a copy: 22
    /// total slots (not 24 or 27), "Chest Isolation or Triceps" is
    /// entirely absent, and **no row is a superset partner** — the source
    /// column that carries the Mesocycle-2 superset markers is empty for
    /// every one of these 22 rows, confirmed across all 11 Family A
    /// workbooks, not just this one. Every `weekOneSets` value below is
    /// independently read from the Mesocycle 3 sheet itself, not copied
    /// from Mesocycle 1/2.
    static let threeDayFullBodyMesocycle3Resensitization: [SourceDay] = [
        SourceDay(sourceEmphasisName: "Push Emphasis", categories: [
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Incline Push or Front Delts", category: .inclinePushOrFrontDelts, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Side Delts", category: .sideDelts, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Hamstrings Isolation", category: .hamstringsIsolation, weekOneSets: 1),
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 1),
        ]),
        SourceDay(sourceEmphasisName: "Legs Emphasis", categories: [
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Hamstrings Hip Hinge", category: .hamstringsHipHinge, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Side Delts", category: .sideDelts, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Incline Push or Front Delts", category: .inclinePushOrFrontDelts, weekOneSets: 1),
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 1),
        ]),
        SourceDay(sourceEmphasisName: "Pull Emphasis", categories: [
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Rear Delts or Side Delts", category: .rearOrSideDelts, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Incline Push", category: .inclinePush, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Glutes", category: .glutes, weekOneSets: 1),
            SourceCategorySlot(sourceLabel: "Hamstrings Isolation", category: .hamstringsIsolation, weekOneSets: 1),
        ]),
    ]

    /// Stage 10R.3A: Mesocycle 3's real, fixed, authoring-time rating-
    /// pairing web, recovered cell-by-cell from the same sheet — same
    /// `(dayIndex, slotIndex)` convention as the other two mesocycles'
    /// tables, indexing into `threeDayFullBodyMesocycle3Resensitization`
    /// itself. No row is a superset partner (§ above), so unlike
    /// Mesocycle 2's table, nothing here represents a "reads the same
    /// target as its own primary" relationship — every row's pairing is
    /// an ordinary cross-day rating reference, structurally identical to
    /// Mesocycle 1's own pattern.
    static let threeDayFullBodyMesocycle3RatingPairings: [SourceRatingPairing] = [
        // Push Emphasis (day 0), rows 11-17
        SourceRatingPairing(dayIndex: 0, slotIndex: 0, pairedDayIndex: 1, pairedSlotIndex: 6), // Horizontal Push <- Legs Horizontal Push
        SourceRatingPairing(dayIndex: 0, slotIndex: 1, pairedDayIndex: 1, pairedSlotIndex: 5), // Incline Push or Front Delts <- Legs Incline Push or Front Delts
        SourceRatingPairing(dayIndex: 0, slotIndex: 2, pairedDayIndex: 1, pairedSlotIndex: 2), // Side Delts <- Legs Side Delts
        SourceRatingPairing(dayIndex: 0, slotIndex: 3, pairedDayIndex: 1, pairedSlotIndex: 3), // Vertical Pull <- Legs Vertical Pull
        SourceRatingPairing(dayIndex: 0, slotIndex: 4, pairedDayIndex: 1, pairedSlotIndex: 4), // Horizontal Pull <- Legs Horizontal Pull
        SourceRatingPairing(dayIndex: 0, slotIndex: 5, pairedDayIndex: 1, pairedSlotIndex: 1), // Hamstrings Isolation <- Legs Hamstrings Hip Hinge
        SourceRatingPairing(dayIndex: 0, slotIndex: 6, pairedDayIndex: 1, pairedSlotIndex: 0), // Quads <- Legs Quads

        // Legs Emphasis (day 1), rows 21-27
        SourceRatingPairing(dayIndex: 1, slotIndex: 0, pairedDayIndex: 0, pairedSlotIndex: 6), // Quads <- Push Quads
        SourceRatingPairing(dayIndex: 1, slotIndex: 1, pairedDayIndex: 2, pairedSlotIndex: 7), // Hamstrings Hip Hinge <- Pull Hamstrings Isolation
        SourceRatingPairing(dayIndex: 1, slotIndex: 2, pairedDayIndex: 2, pairedSlotIndex: 2), // Side Delts <- Pull Rear Delts or Side Delts
        SourceRatingPairing(dayIndex: 1, slotIndex: 3, pairedDayIndex: 2, pairedSlotIndex: 0), // Vertical Pull <- Pull Vertical Pull
        SourceRatingPairing(dayIndex: 1, slotIndex: 4, pairedDayIndex: 2, pairedSlotIndex: 1), // Horizontal Pull <- Pull Horizontal Pull
        SourceRatingPairing(dayIndex: 1, slotIndex: 5, pairedDayIndex: 2, pairedSlotIndex: 5), // Incline Push or Front Delts <- Pull Incline Push
        SourceRatingPairing(dayIndex: 1, slotIndex: 6, pairedDayIndex: 2, pairedSlotIndex: 4), // Horizontal Push <- Pull Horizontal Push

        // Pull Emphasis (day 2), rows 31-38
        SourceRatingPairing(dayIndex: 2, slotIndex: 0, pairedDayIndex: 0, pairedSlotIndex: 3), // Vertical Pull <- Push Vertical Pull
        SourceRatingPairing(dayIndex: 2, slotIndex: 1, pairedDayIndex: 0, pairedSlotIndex: 4), // Horizontal Pull <- Push Horizontal Pull
        SourceRatingPairing(dayIndex: 2, slotIndex: 2, pairedDayIndex: 0, pairedSlotIndex: 2), // Rear Delts or Side Delts <- Push Side Delts
        SourceRatingPairing(dayIndex: 2, slotIndex: 3, pairedDayIndex: 0, pairedSlotIndex: 3), // Biceps <- Push Vertical Pull
        SourceRatingPairing(dayIndex: 2, slotIndex: 4, pairedDayIndex: 0, pairedSlotIndex: 0), // Horizontal Push <- Push Horizontal Push
        SourceRatingPairing(dayIndex: 2, slotIndex: 5, pairedDayIndex: 0, pairedSlotIndex: 0), // Incline Push <- Push Horizontal Push
        // Glutes <- Legs Hamstrings Hip Hinge (row37<-row22): a synthesis
        // error in an earlier draft of the design doc mistranscribed this
        // as (1,6) — self-inconsistent with its own row37/row22 citation
        // (row22 is Legs slotIndex 1, not 6) and corrected before this
        // table was written, using the same Glutes<-Hamstrings-Hip-Hinge
        // relationship Mesocycle 1's own table already establishes
        // (`threeDayFullBodyMesocycle1RatingPairings`, row39<-row24).
        SourceRatingPairing(dayIndex: 2, slotIndex: 6, pairedDayIndex: 1, pairedSlotIndex: 1), // Glutes <- Legs Hamstrings Hip Hinge
        SourceRatingPairing(dayIndex: 2, slotIndex: 7, pairedDayIndex: 0, pairedSlotIndex: 5), // Hamstrings Isolation <- Push Hamstrings Isolation
    ]

    /// Source Authority Repair — 4-Day Full Body, Mesocycle 1 "Basic
    /// Hypertrophy": recovered directly from `source_workbooks/4 day
    /// full body.xlsx`, sheet "Mesocycle 1 Basic Hypertrophy", rows
    /// 10-45 (cell-cited: `J11='=MROUND(((G11)*0.85),2.5)'` — factor
    /// 0.85, matching `primaryWeekOneFactor(.basicHypertrophy)` exactly;
    /// the workbook's own `2.5` MROUND unit is a display-only convention
    /// TrainingOS does not model — the real equipment-resolved rounding
    /// already happens in `StrengthProgressionEngine.resolveWeight`,
    /// exactly as already established for 3-Day). 26 slots/week (7+6+7+6),
    /// confirmed against `SOURCE_PROGRAM_MANIFEST.md` §0/§6's own slot-
    /// count claim. Day emphasis names ("Upper Body"/"Lower Body")
    /// preserved verbatim from source column B/C.
    static let fourDayFullBodyMesocycle1BasicHypertrophy: [SourceDay] = [
        SourceDay(sourceEmphasisName: "Upper Body", categories: [
            SourceCategorySlot(sourceLabel: "Incline Push", category: .inclinePush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Chest Isolation or Triceps", category: .chestIsolationOrTriceps, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Side Delts", category: .sideDelts, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Abs", category: .abs, weekOneSets: 2),
        ]),
        SourceDay(sourceEmphasisName: "Lower Body", categories: [
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Hamstring Isolation", category: .hamstringsIsolation, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Calves", category: .calves, weekOneSets: 6),
            SourceCategorySlot(sourceLabel: "Triceps", category: .triceps, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Front Delts", category: .frontDelts, weekOneSets: 3),
        ]),
        SourceDay(sourceEmphasisName: "Upper Body", categories: [
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Rear or Side Delts", category: .rearOrSideDelts, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Incline Push", category: .inclinePush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Abs", category: .abs, weekOneSets: 2),
        ]),
        SourceDay(sourceEmphasisName: "Lower Body", categories: [
            SourceCategorySlot(sourceLabel: "Glutes", category: .glutes, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Hamstring Hip Hinge", category: .hamstringsHipHinge, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Traps", category: .traps, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Calves", category: .calves, weekOneSets: 6),
        ]),
    ]

    /// Source Authority Repair — 4-Day Full Body Mesocycle 1's real
    /// rating web, recovered cell-by-cell from the workbook's "Week 2
    /// Sets" formulas (`O{row}='=I{row}+({ratingCol}{pairedRow})'` — the
    /// same chronological, most-recently-trained-related-category
    /// mechanism already established for 3-Day, confirmed here
    /// independently: Day1 rows 11-17 rate off Day3 rows 30-36 (the
    /// previous week's later day), Day2 rows 21-26 rate mostly off Day4
    /// rows 40-45 (same relationship, one week back) with two rows
    /// (Triceps/Front Delts) falling back to Day3's Incline Push since
    /// neither Triceps nor Front Delts has a same-category predecessor
    /// on Day4; Day3 rows 30-36 rate off Day1 rows 11-17; Day4 rows
    /// 40-45 rate off Day2 rows 21-24 with two rows (Biceps/Traps)
    /// falling back to Day1 (Vertical Pull/Side Delts respectively) —
    /// the exact same "no same-category predecessor two days back, so
    /// reach further" shape 3-Day's own Mesocycle 1 table already
    /// documents for its own Biceps row.
    static let fourDayFullBodyMesocycle1RatingPairings: [SourceRatingPairing] = [
        // Day 1 (Upper) <- Day 3 (Upper), previous week
        SourceRatingPairing(dayIndex: 0, slotIndex: 0, pairedDayIndex: 2, pairedSlotIndex: 5), // Incline Push <- Day3 Incline Push (row11<-row35)
        SourceRatingPairing(dayIndex: 0, slotIndex: 1, pairedDayIndex: 2, pairedSlotIndex: 4), // Chest Isolation or Triceps <- Day3 Horizontal Push (row12<-row34)
        SourceRatingPairing(dayIndex: 0, slotIndex: 2, pairedDayIndex: 2, pairedSlotIndex: 4), // Horizontal Push <- Day3 Horizontal Push (row13<-row34)
        SourceRatingPairing(dayIndex: 0, slotIndex: 3, pairedDayIndex: 2, pairedSlotIndex: 2), // Horizontal Pull <- Day3 Horizontal Pull (row14<-row32)
        SourceRatingPairing(dayIndex: 0, slotIndex: 4, pairedDayIndex: 2, pairedSlotIndex: 0), // Vertical Pull <- Day3 Vertical Pull 1st (row15<-row30)
        SourceRatingPairing(dayIndex: 0, slotIndex: 5, pairedDayIndex: 2, pairedSlotIndex: 3), // Side Delts <- Day3 Rear or Side Delts (row16<-row33)
        SourceRatingPairing(dayIndex: 0, slotIndex: 6, pairedDayIndex: 2, pairedSlotIndex: 6), // Abs <- Day3 Abs (row17<-row36)
        // Day 2 (Lower) <- Day 4 (Lower), previous week; Triceps/Front Delts <- Day 3 Incline Push
        SourceRatingPairing(dayIndex: 1, slotIndex: 0, pairedDayIndex: 3, pairedSlotIndex: 2), // Quads 1st <- Day4 Quads (row21<-row42)
        SourceRatingPairing(dayIndex: 1, slotIndex: 1, pairedDayIndex: 3, pairedSlotIndex: 2), // Quads 2nd <- Day4 Quads (row22<-row42)
        SourceRatingPairing(dayIndex: 1, slotIndex: 2, pairedDayIndex: 3, pairedSlotIndex: 1), // Hamstring Isolation <- Day4 Hamstring Hip Hinge (row23<-row41)
        SourceRatingPairing(dayIndex: 1, slotIndex: 3, pairedDayIndex: 3, pairedSlotIndex: 5), // Calves <- Day4 Calves (row24<-row45)
        SourceRatingPairing(dayIndex: 1, slotIndex: 4, pairedDayIndex: 2, pairedSlotIndex: 5), // Triceps <- Day3 Incline Push (row25<-row35)
        SourceRatingPairing(dayIndex: 1, slotIndex: 5, pairedDayIndex: 2, pairedSlotIndex: 5), // Front Delts <- Day3 Incline Push (row26<-row35)
        // Day 3 (Upper) <- Day 1 (Upper), same week
        SourceRatingPairing(dayIndex: 2, slotIndex: 0, pairedDayIndex: 0, pairedSlotIndex: 4), // Vertical Pull 1st <- Day1 Vertical Pull (row30<-row15)
        SourceRatingPairing(dayIndex: 2, slotIndex: 1, pairedDayIndex: 0, pairedSlotIndex: 4), // Vertical Pull 2nd <- Day1 Vertical Pull (row31<-row15)
        SourceRatingPairing(dayIndex: 2, slotIndex: 2, pairedDayIndex: 0, pairedSlotIndex: 3), // Horizontal Pull <- Day1 Horizontal Pull (row32<-row14)
        SourceRatingPairing(dayIndex: 2, slotIndex: 3, pairedDayIndex: 0, pairedSlotIndex: 5), // Rear or Side Delts <- Day1 Side Delts (row33<-row16)
        SourceRatingPairing(dayIndex: 2, slotIndex: 4, pairedDayIndex: 0, pairedSlotIndex: 2), // Horizontal Push <- Day1 Horizontal Push (row34<-row13)
        SourceRatingPairing(dayIndex: 2, slotIndex: 5, pairedDayIndex: 0, pairedSlotIndex: 0), // Incline Push <- Day1 Incline Push (row35<-row11)
        SourceRatingPairing(dayIndex: 2, slotIndex: 6, pairedDayIndex: 0, pairedSlotIndex: 6), // Abs <- Day1 Abs (row36<-row17)
        // Day 4 (Lower) <- Day 2 (Lower), same week; Biceps/Traps <- Day 1 Vertical Pull/Side Delts
        SourceRatingPairing(dayIndex: 3, slotIndex: 0, pairedDayIndex: 1, pairedSlotIndex: 0), // Glutes <- Day2 Quads 1st (row40<-row21)
        SourceRatingPairing(dayIndex: 3, slotIndex: 1, pairedDayIndex: 1, pairedSlotIndex: 2), // Hamstring Hip Hinge <- Day2 Hamstring Isolation (row41<-row23)
        SourceRatingPairing(dayIndex: 3, slotIndex: 2, pairedDayIndex: 1, pairedSlotIndex: 0), // Quads <- Day2 Quads 1st (row42<-row21)
        SourceRatingPairing(dayIndex: 3, slotIndex: 3, pairedDayIndex: 0, pairedSlotIndex: 4), // Biceps <- Day1 Vertical Pull (row43<-row15)
        SourceRatingPairing(dayIndex: 3, slotIndex: 4, pairedDayIndex: 0, pairedSlotIndex: 5), // Traps <- Day1 Side Delts (row44<-row16)
        SourceRatingPairing(dayIndex: 3, slotIndex: 5, pairedDayIndex: 1, pairedSlotIndex: 3), // Calves <- Day2 Calves (row45<-row24)
    ]

    /// Source Authority Repair — 4-Day Full Body, Mesocycle 2 "Metabolite
    /// Focus": recovered directly from `source_workbooks/4 day full
    /// body.xlsx`, sheet "Mesocycle 2 Metabolite Focus", rows 11-18
    /// (Day1), 22-28 (Day2), 32-39 (Day3), 43-49 (Day4). Confirmed
    /// factor 0.75 (`J11='=MROUND(((G11)*0.75),5)'`) and rounding unit 5
    /// (differs from M1's 2.5). 30 slots/week (8+7+8+7) — each day gains
    /// exactly one slot over M1 from its own real superset partner row.
    /// Four real supersets, one per day, cell-confirmed via the 'Super
    /// set this exercise'/'with this one' column-A markers: Day1 Chest
    /// Isolation or Triceps + Horizontal Push (cross-category, rows
    /// 12-13); Day2 Triceps + Front Delts (cross-category, rows 26-27);
    /// Day3 Rear or Side Delts + Rear or Side Delts (same-category-
    /// doubled, rows 35-36); Day4 Biceps + Biceps (same-category-doubled,
    /// rows 46-47) — every partner's own weight formula independently
    /// confirmed at factor 0.6 (`=MROUND(((G13)*0.6),5)` etc.), matching
    /// `metaboliteFocusPairedWeekOneFactor` exactly. Unlike 3-Day's own
    /// Mesocycle 2 (where the Pull Emphasis Biceps partner freezes after
    /// Week 2), all 4 of THIS workbook's superset partners were traced
    /// through their real Week-3/4 formulas (`U13='=O12+(S37)'`,
    /// `AA13='=U12+(Y37)'`, etc.) and confirmed to cascade normally off
    /// their own primary's accumulating value every week — none freeze
    /// (`freezeAfterWeek` stays `nil` for all 4 partner rows here; the
    /// parameter still exists on `SourceCategorySlot` for the case where
    /// a future recovery does find one, never removed just because this
    /// workbook doesn't use it).
    static let fourDayFullBodyMesocycle2MetaboliteFocus: [SourceDay] = [
        SourceDay(sourceEmphasisName: "Upper Body", categories: [
            SourceCategorySlot(sourceLabel: "Incline Push", category: .inclinePush, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Chest Isolation or Triceps", category: .chestIsolationOrTriceps, weekOneSets: 3, isSupersetPartner: false),
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 3, isSupersetPartner: true),
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Side Delts", category: .sideDelts, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Abs", category: .abs, weekOneSets: 2),
        ]),
        SourceDay(sourceEmphasisName: "Lower Body", categories: [
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Hamstring Isolation", category: .hamstringsIsolation, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Calves", category: .calves, weekOneSets: 6),
            SourceCategorySlot(sourceLabel: "Triceps", category: .triceps, weekOneSets: 3, isSupersetPartner: false),
            SourceCategorySlot(sourceLabel: "Front Delts", category: .frontDelts, weekOneSets: 3, isSupersetPartner: true),
            SourceCategorySlot(sourceLabel: "Front Delts", category: .frontDelts, weekOneSets: 3),
        ]),
        SourceDay(sourceEmphasisName: "Upper Body", categories: [
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Rear or Side Delts", category: .rearOrSideDelts, weekOneSets: 4, isSupersetPartner: false),
            SourceCategorySlot(sourceLabel: "Rear or Side Delts", category: .rearOrSideDelts, weekOneSets: 4, isSupersetPartner: true),
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Incline Push", category: .inclinePush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Abs", category: .abs, weekOneSets: 2),
        ]),
        SourceDay(sourceEmphasisName: "Lower Body", categories: [
            SourceCategorySlot(sourceLabel: "Glutes", category: .glutes, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Hamstring Hip Hinge", category: .hamstringsHipHinge, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 3, isSupersetPartner: false),
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 3, isSupersetPartner: true),
            SourceCategorySlot(sourceLabel: "Traps", category: .traps, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Calves", category: .calves, weekOneSets: 6),
        ]),
    ]

    /// Source Authority Repair — 4-Day Full Body Mesocycle 2's real
    /// rating web, recovered cell-by-cell from the workbook's "Week 2
    /// Sets" formulas (same `(dayIndex, slotIndex)` convention as
    /// Mesocycle 1's table, indexing into
    /// `fourDayFullBodyMesocycle2MetaboliteFocus` itself). Every superset
    /// partner's own pairing target is confirmed to be the SAME external
    /// row its own primary reads (`O13='=I12+(M37)'`, identical to
    /// `O12='=I12+(M37)'`) — never its own independent target.
    static let fourDayFullBodyMesocycle2RatingPairings: [SourceRatingPairing] = [
        // Day 1 (Upper), rows 11-18
        SourceRatingPairing(dayIndex: 0, slotIndex: 0, pairedDayIndex: 2, pairedSlotIndex: 6), // Incline Push <- Day3 Incline Push (row11<-row38)
        SourceRatingPairing(dayIndex: 0, slotIndex: 1, pairedDayIndex: 2, pairedSlotIndex: 5), // Chest Isolation or Triceps (primary) <- Day3 Horizontal Push (row12<-row37)
        SourceRatingPairing(dayIndex: 0, slotIndex: 2, pairedDayIndex: 2, pairedSlotIndex: 5), // Horizontal Push (superset partner) <- same target as slot1 (row13<-row37)
        SourceRatingPairing(dayIndex: 0, slotIndex: 3, pairedDayIndex: 2, pairedSlotIndex: 5), // Horizontal Push (standalone) <- Day3 Horizontal Push (row14<-row37)
        SourceRatingPairing(dayIndex: 0, slotIndex: 4, pairedDayIndex: 2, pairedSlotIndex: 2), // Horizontal Pull <- Day3 Horizontal Pull (row15<-row34)
        SourceRatingPairing(dayIndex: 0, slotIndex: 5, pairedDayIndex: 2, pairedSlotIndex: 0), // Vertical Pull <- Day3 Vertical Pull 1st (row16<-row32)
        SourceRatingPairing(dayIndex: 0, slotIndex: 6, pairedDayIndex: 2, pairedSlotIndex: 3), // Side Delts <- Day3 Rear or Side Delts (primary) (row17<-row35)
        SourceRatingPairing(dayIndex: 0, slotIndex: 7, pairedDayIndex: 2, pairedSlotIndex: 7), // Abs <- Day3 Abs (row18<-row39)
        // Day 2 (Lower), rows 22-28
        SourceRatingPairing(dayIndex: 1, slotIndex: 0, pairedDayIndex: 3, pairedSlotIndex: 2), // Quads 1st <- Day4 Quads (row22<-row45)
        SourceRatingPairing(dayIndex: 1, slotIndex: 1, pairedDayIndex: 3, pairedSlotIndex: 2), // Quads 2nd <- Day4 Quads (row23<-row45)
        SourceRatingPairing(dayIndex: 1, slotIndex: 2, pairedDayIndex: 3, pairedSlotIndex: 1), // Hamstring Isolation <- Day4 Hamstring Hip Hinge (row24<-row44)
        SourceRatingPairing(dayIndex: 1, slotIndex: 3, pairedDayIndex: 3, pairedSlotIndex: 6), // Calves <- Day4 Calves (row25<-row49)
        SourceRatingPairing(dayIndex: 1, slotIndex: 4, pairedDayIndex: 2, pairedSlotIndex: 6), // Triceps (primary) <- Day3 Incline Push (row26<-row38)
        SourceRatingPairing(dayIndex: 1, slotIndex: 5, pairedDayIndex: 2, pairedSlotIndex: 6), // Front Delts (superset partner) <- same target as slot4 (row27<-row38)
        SourceRatingPairing(dayIndex: 1, slotIndex: 6, pairedDayIndex: 2, pairedSlotIndex: 6), // Front Delts (standalone) <- Day3 Incline Push (row28<-row38)
        // Day 3 (Upper), rows 32-39
        SourceRatingPairing(dayIndex: 2, slotIndex: 0, pairedDayIndex: 0, pairedSlotIndex: 5), // Vertical Pull 1st <- Day1 Vertical Pull (row32<-row16)
        SourceRatingPairing(dayIndex: 2, slotIndex: 1, pairedDayIndex: 0, pairedSlotIndex: 5), // Vertical Pull 2nd <- Day1 Vertical Pull (row33<-row16)
        SourceRatingPairing(dayIndex: 2, slotIndex: 2, pairedDayIndex: 0, pairedSlotIndex: 4), // Horizontal Pull <- Day1 Horizontal Pull (row34<-row15)
        SourceRatingPairing(dayIndex: 2, slotIndex: 3, pairedDayIndex: 0, pairedSlotIndex: 6), // Rear or Side Delts (primary) <- Day1 Side Delts (row35<-row17)
        SourceRatingPairing(dayIndex: 2, slotIndex: 4, pairedDayIndex: 0, pairedSlotIndex: 6), // Rear or Side Delts (superset partner) <- same target as slot3 (row36<-row17)
        SourceRatingPairing(dayIndex: 2, slotIndex: 5, pairedDayIndex: 0, pairedSlotIndex: 3), // Horizontal Push <- Day1 Horizontal Push (standalone) (row37<-row14)
        SourceRatingPairing(dayIndex: 2, slotIndex: 6, pairedDayIndex: 0, pairedSlotIndex: 0), // Incline Push <- Day1 Incline Push (row38<-row11)
        SourceRatingPairing(dayIndex: 2, slotIndex: 7, pairedDayIndex: 0, pairedSlotIndex: 7), // Abs <- Day1 Abs (row39<-row18)
        // Day 4 (Lower), rows 43-49
        SourceRatingPairing(dayIndex: 3, slotIndex: 0, pairedDayIndex: 1, pairedSlotIndex: 0), // Glutes <- Day2 Quads 1st (row43<-row22)
        SourceRatingPairing(dayIndex: 3, slotIndex: 1, pairedDayIndex: 1, pairedSlotIndex: 2), // Hamstring Hip Hinge <- Day2 Hamstring Isolation (row44<-row24)
        SourceRatingPairing(dayIndex: 3, slotIndex: 2, pairedDayIndex: 1, pairedSlotIndex: 0), // Quads <- Day2 Quads 1st (row45<-row22)
        SourceRatingPairing(dayIndex: 3, slotIndex: 3, pairedDayIndex: 0, pairedSlotIndex: 5), // Biceps (primary) <- Day1 Vertical Pull (row46<-row16)
        SourceRatingPairing(dayIndex: 3, slotIndex: 4, pairedDayIndex: 0, pairedSlotIndex: 5), // Biceps (superset partner) <- same target as slot3 (row47<-row16)
        SourceRatingPairing(dayIndex: 3, slotIndex: 5, pairedDayIndex: 0, pairedSlotIndex: 6), // Traps <- Day1 Side Delts (row48<-row17)
        SourceRatingPairing(dayIndex: 3, slotIndex: 6, pairedDayIndex: 1, pairedSlotIndex: 3), // Calves <- Day2 Calves (row49<-row25)
    ]

    /// Source Authority Repair — 4-Day Full Body, Mesocycle 3
    /// "Resensitization": recovered directly from `source_workbooks/4
    /// day full body.xlsx`, sheet "Mesocycle 3 Resensitization", rows
    /// 11-16 (Day1), 20-24 (Day2), 28-33 (Day3), 37-42 (Day4). Confirmed
    /// factor 1.0 (`J11='=MROUND(((G11)),5)'`, no multiplier) and
    /// rounding unit 5. 23 slots/week (6+5+6+6) — no supersets anywhere
    /// (no 'Super set this exercise' marker found on any of these 23
    /// rows). Deload confirmed 3-week block (`T8='Week 3: Deload'`, i.e.
    /// only ONE progressive week beyond Week 1 — `progressiveWeekCount`
    /// already returns 2 for `.resensitization`, unchanged). Deload
    /// weight independently confirmed to follow the SAME generic
    /// full-weight-first-half/half-weight-second-half split
    /// `SourceCompatibleDeloadStrategy.resolveDeloadWeight`'s existing,
    /// unmodified default formula already computes for `dayCount == 4`
    /// (`boundary = ceil(4/2) = 2`): Day1/Day2 deload at full Week-1
    /// weight (`V11='=J11'`), Day3/Day4 at half (`V28='=MROUND((J28*0.5),5)'`)
    /// — this exact split, verified cell-by-cell, needs zero code change
    /// since the strategy already derives it from `dayCount` generically.
    static let fourDayFullBodyMesocycle3Resensitization: [SourceDay] = [
        SourceDay(sourceEmphasisName: "Upper Body", categories: [
            SourceCategorySlot(sourceLabel: "Incline Push", category: .inclinePush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 1),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Side Delts", category: .sideDelts, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Abs", category: .abs, weekOneSets: 1),
        ]),
        SourceDay(sourceEmphasisName: "Lower Body", categories: [
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Hamstring Isolation", category: .hamstringsIsolation, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Calves", category: .calves, weekOneSets: 5),
            SourceCategorySlot(sourceLabel: "Triceps", category: .triceps, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Front Delts", category: .frontDelts, weekOneSets: 2),
        ]),
        SourceDay(sourceEmphasisName: "Upper Body", categories: [
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 1),
            SourceCategorySlot(sourceLabel: "Rear or Side Delts", category: .rearOrSideDelts, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Incline Push", category: .inclinePush, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Abs", category: .abs, weekOneSets: 1),
        ]),
        SourceDay(sourceEmphasisName: "Lower Body", categories: [
            SourceCategorySlot(sourceLabel: "Glutes", category: .glutes, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Hamstring Hip Hinge", category: .hamstringsHipHinge, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Traps", category: .traps, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Calves", category: .calves, weekOneSets: 5),
        ]),
    ]

    /// Source Authority Repair — 4-Day Full Body Mesocycle 3's real
    /// rating web, recovered cell-by-cell — same `(dayIndex, slotIndex)`
    /// convention, indexing into `fourDayFullBodyMesocycle3Resensitization`
    /// itself. No superset partners exist in this mesocycle (confirmed
    /// above), so every row here is an ordinary cross-day rating
    /// reference.
    static let fourDayFullBodyMesocycle3RatingPairings: [SourceRatingPairing] = [
        // Day 1 (Upper), rows 11-16
        SourceRatingPairing(dayIndex: 0, slotIndex: 0, pairedDayIndex: 2, pairedSlotIndex: 4), // Incline Push <- Day3 Incline Push (row11<-row32)
        SourceRatingPairing(dayIndex: 0, slotIndex: 1, pairedDayIndex: 2, pairedSlotIndex: 3), // Horizontal Push <- Day3 Horizontal Push (row12<-row31)
        SourceRatingPairing(dayIndex: 0, slotIndex: 2, pairedDayIndex: 2, pairedSlotIndex: 1), // Horizontal Pull <- Day3 Horizontal Pull (row13<-row29)
        SourceRatingPairing(dayIndex: 0, slotIndex: 3, pairedDayIndex: 2, pairedSlotIndex: 0), // Vertical Pull <- Day3 Vertical Pull (row14<-row28)
        SourceRatingPairing(dayIndex: 0, slotIndex: 4, pairedDayIndex: 2, pairedSlotIndex: 2), // Side Delts <- Day3 Rear or Side Delts (row15<-row30)
        SourceRatingPairing(dayIndex: 0, slotIndex: 5, pairedDayIndex: 2, pairedSlotIndex: 5), // Abs <- Day3 Abs (row16<-row33)
        // Day 2 (Lower), rows 20-24
        SourceRatingPairing(dayIndex: 1, slotIndex: 0, pairedDayIndex: 3, pairedSlotIndex: 2), // Quads <- Day4 Quads (row20<-row39)
        SourceRatingPairing(dayIndex: 1, slotIndex: 1, pairedDayIndex: 3, pairedSlotIndex: 1), // Hamstring Isolation <- Day4 Hamstring Hip Hinge (row21<-row38)
        SourceRatingPairing(dayIndex: 1, slotIndex: 2, pairedDayIndex: 3, pairedSlotIndex: 5), // Calves <- Day4 Calves (row22<-row42)
        SourceRatingPairing(dayIndex: 1, slotIndex: 3, pairedDayIndex: 2, pairedSlotIndex: 4), // Triceps <- Day3 Incline Push (row23<-row32)
        SourceRatingPairing(dayIndex: 1, slotIndex: 4, pairedDayIndex: 2, pairedSlotIndex: 4), // Front Delts <- Day3 Incline Push (row24<-row32)
        // Day 3 (Upper), rows 28-33
        SourceRatingPairing(dayIndex: 2, slotIndex: 0, pairedDayIndex: 0, pairedSlotIndex: 3), // Vertical Pull <- Day1 Vertical Pull (row28<-row14)
        SourceRatingPairing(dayIndex: 2, slotIndex: 1, pairedDayIndex: 0, pairedSlotIndex: 2), // Horizontal Pull <- Day1 Horizontal Pull (row29<-row13)
        SourceRatingPairing(dayIndex: 2, slotIndex: 2, pairedDayIndex: 0, pairedSlotIndex: 4), // Rear or Side Delts <- Day1 Side Delts (row30<-row15)
        SourceRatingPairing(dayIndex: 2, slotIndex: 3, pairedDayIndex: 0, pairedSlotIndex: 1), // Horizontal Push <- Day1 Horizontal Push (row31<-row12)
        SourceRatingPairing(dayIndex: 2, slotIndex: 4, pairedDayIndex: 0, pairedSlotIndex: 0), // Incline Push <- Day1 Incline Push (row32<-row11)
        SourceRatingPairing(dayIndex: 2, slotIndex: 5, pairedDayIndex: 0, pairedSlotIndex: 5), // Abs <- Day1 Abs (row33<-row16)
        // Day 4 (Lower), rows 37-42
        SourceRatingPairing(dayIndex: 3, slotIndex: 0, pairedDayIndex: 1, pairedSlotIndex: 0), // Glutes <- Day2 Quads (row37<-row20)
        SourceRatingPairing(dayIndex: 3, slotIndex: 1, pairedDayIndex: 1, pairedSlotIndex: 1), // Hamstring Hip Hinge <- Day2 Hamstring Isolation (row38<-row21)
        SourceRatingPairing(dayIndex: 3, slotIndex: 2, pairedDayIndex: 1, pairedSlotIndex: 0), // Quads <- Day2 Quads (row39<-row20)
        SourceRatingPairing(dayIndex: 3, slotIndex: 3, pairedDayIndex: 0, pairedSlotIndex: 3), // Biceps <- Day1 Vertical Pull (row40<-row14)
        SourceRatingPairing(dayIndex: 3, slotIndex: 4, pairedDayIndex: 0, pairedSlotIndex: 4), // Traps <- Day1 Side Delts (row41<-row15)
        SourceRatingPairing(dayIndex: 3, slotIndex: 5, pairedDayIndex: 1, pairedSlotIndex: 2), // Calves <- Day2 Calves (row42<-row22)
    ]

    /// Source Authority Repair — 5-Day Full Body, Mesocycle 1 "Basic
    /// Hypertrophy": recovered directly from `source_workbooks/5 day
    /// full body.xlsx`, sheet "Mesocycle 1 Basic Hypertrophy", rows
    /// 10-50 (a "Finished programs" copy — real athlete-entered 10RMs/
    /// exercise picks in columns C/G, but per `SOURCE_PROGRAM_MANIFEST.md`
    /// §2, design fields — category/B-column, sets/I-column, formula/
    /// J-column — never disagree with the "Original templates" copy;
    /// only those design fields are used here, never the real athlete's
    /// own numbers). Factor 0.85 confirmed (`J11='=MROUND(((G11)*0.85),5)'`),
    /// rounding unit 5. 28 slots/week (6+4+6+5+7), matching
    /// `SOURCE_PROGRAM_MANIFEST.md` §1/§6's own slot-count claim. Day
    /// emphasis names ("Chest Upper," etc.) preserved verbatim from
    /// source column B/C. Two per-workbook display-label variants
    /// confirmed via real exercise content and resolved through
    /// `SourceHypertrophyCategory.labelAliases`, never invented as new
    /// categories: "Horizontal Chest" -> `.horizontalPush` (its real
    /// exercise, "Flat Dumbbell Bench Press," is a literal
    /// `.horizontalPush`-approved name) and "Incline Chest" ->
    /// `.inclinePush` (its real exercise, "Incline Wide Grip Bench
    /// Press," is a literal `.inclinePush`-approved name). "Chest
    /// Isolation" here is genuinely standalone (never dual-tagged with
    /// Triceps the way 3-/4-Day's workbooks pair it) — the new
    /// `.chestIsolation` category exists for exactly this real,
    /// observed difference.
    ///
    /// Known real source anomaly, disclosed rather than silently
    /// resolved: cell `G32` (Day 3's Abs row, this "Finished programs"
    /// copy) reads the literal text `"?"` instead of a real 10RM number
    /// — an athlete's own not-yet-filled-in value in this specific
    /// personal copy. This does not affect anything recovered here: `G`
    /// is never design authority (`SOURCE_PROGRAM_MANIFEST.md` §2); the
    /// design fields for that exact row (category "Abs," 3 sets, the
    /// same `*0.85` formula shape as every other Day 3 row) are entirely
    /// normal and were used unchanged.
    static let fiveDayFullBodyMesocycle1BasicHypertrophy: [SourceDay] = [
        SourceDay(sourceEmphasisName: "Chest Upper", categories: [
            SourceCategorySlot(sourceLabel: "Incline Chest", category: .inclinePush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Chest Isolation", category: .chestIsolation, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Chest", category: .horizontalPush, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Rear or Side Delts", category: .rearOrSideDelts, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Abs", category: .abs, weekOneSets: 3),
        ]),
        SourceDay(sourceEmphasisName: "Quads Focused Legs", categories: [
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Hamstrings Isolation", category: .hamstringsIsolation, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Calves", category: .calves, weekOneSets: 6),
        ]),
        SourceDay(sourceEmphasisName: "Back Upper", categories: [
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Chest", category: .horizontalPush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Rear or Side Delts", category: .rearOrSideDelts, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Abs", category: .abs, weekOneSets: 3),
        ]),
        SourceDay(sourceEmphasisName: "Glute/Ham Focused Legs", categories: [
            SourceCategorySlot(sourceLabel: "Glutes", category: .glutes, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Glutes", category: .glutes, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Hamstrings Hip Hinge", category: .hamstringsHipHinge, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Calves", category: .calves, weekOneSets: 6),
        ]),
        SourceDay(sourceEmphasisName: "Shoulders/Arms Upper", categories: [
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Triceps", category: .triceps, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Front Delts", category: .frontDelts, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Traps", category: .traps, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Incline Chest", category: .inclinePush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Abs", category: .abs, weekOneSets: 3),
        ]),
    ]

    /// Source Authority Repair — 5-Day Full Body Mesocycle 1's real
    /// rating web, recovered cell-by-cell from the workbook's "Week 2
    /// Sets" formulas. Preserved exactly as authored — several rows
    /// reference a related-but-different category rather than the
    /// nearest same-category occurrence (e.g. Day3 slot2/"Horizontal
    /// Pull" rates off Day5's "Vertical Pull," and Day5 slot4/"Vertical
    /// Pull" rates off Day1's "Horizontal Pull" rather than Day3's own,
    /// more recent, real Vertical Pull slots) — this is a real, observed
    /// authoring choice in the source spreadsheet, not normalized or
    /// "corrected" to a cleaner rule here.
    static let fiveDayFullBodyMesocycle1RatingPairings: [SourceRatingPairing] = [
        // Day 1 (Chest Upper), rows 11-16
        SourceRatingPairing(dayIndex: 0, slotIndex: 0, pairedDayIndex: 2, pairedSlotIndex: 3), // Incline Chest <- Day3 Horizontal Chest (row11<-row30)
        SourceRatingPairing(dayIndex: 0, slotIndex: 1, pairedDayIndex: 2, pairedSlotIndex: 3), // Chest Isolation <- Day3 Horizontal Chest (row12<-row30)
        SourceRatingPairing(dayIndex: 0, slotIndex: 2, pairedDayIndex: 2, pairedSlotIndex: 3), // Horizontal Chest <- Day3 Horizontal Chest (row13<-row30)
        SourceRatingPairing(dayIndex: 0, slotIndex: 3, pairedDayIndex: 2, pairedSlotIndex: 2), // Horizontal Pull <- Day3 Horizontal Pull (row14<-row29)
        SourceRatingPairing(dayIndex: 0, slotIndex: 4, pairedDayIndex: 2, pairedSlotIndex: 4), // Rear or Side Delts <- Day3 Rear or Side Delts (row15<-row31)
        SourceRatingPairing(dayIndex: 0, slotIndex: 5, pairedDayIndex: 2, pairedSlotIndex: 5), // Abs <- Day3 Abs (row16<-row32)
        // Day 2 (Quads Focused Legs), rows 20-23
        SourceRatingPairing(dayIndex: 1, slotIndex: 0, pairedDayIndex: 3, pairedSlotIndex: 4), // Quads 1st <- Day4 Quads (row20<-row39)
        SourceRatingPairing(dayIndex: 1, slotIndex: 1, pairedDayIndex: 3, pairedSlotIndex: 4), // Quads 2nd <- Day4 Quads (row21<-row39)
        SourceRatingPairing(dayIndex: 1, slotIndex: 2, pairedDayIndex: 3, pairedSlotIndex: 2), // Hamstrings Isolation <- Day4 Hamstrings Hip Hinge (row22<-row38)
        SourceRatingPairing(dayIndex: 1, slotIndex: 3, pairedDayIndex: 3, pairedSlotIndex: 5), // Calves <- Day4 Calves (row23<-row40)
        // Day 3 (Back Upper), rows 27-32
        SourceRatingPairing(dayIndex: 2, slotIndex: 0, pairedDayIndex: 4, pairedSlotIndex: 5), // Vertical Pull 1st <- Day5 Incline Chest (row27<-row49)
        SourceRatingPairing(dayIndex: 2, slotIndex: 1, pairedDayIndex: 4, pairedSlotIndex: 5), // Vertical Pull 2nd <- Day5 Incline Chest (row28<-row49)
        SourceRatingPairing(dayIndex: 2, slotIndex: 2, pairedDayIndex: 4, pairedSlotIndex: 4), // Horizontal Pull <- Day5 Vertical Pull (row29<-row48)
        SourceRatingPairing(dayIndex: 2, slotIndex: 3, pairedDayIndex: 4, pairedSlotIndex: 4), // Horizontal Chest <- Day5 Vertical Pull (row30<-row48)
        SourceRatingPairing(dayIndex: 2, slotIndex: 4, pairedDayIndex: 0, pairedSlotIndex: 4), // Rear or Side Delts <- Day1 Rear or Side Delts (row31<-row15)
        SourceRatingPairing(dayIndex: 2, slotIndex: 5, pairedDayIndex: 4, pairedSlotIndex: 6), // Abs <- Day5 Abs (row32<-row50)
        // Day 4 (Glute/Ham Focused Legs), rows 36-40
        SourceRatingPairing(dayIndex: 3, slotIndex: 0, pairedDayIndex: 1, pairedSlotIndex: 0), // Glutes 1st <- Day2 Quads (row36<-row20)
        SourceRatingPairing(dayIndex: 3, slotIndex: 1, pairedDayIndex: 1, pairedSlotIndex: 0), // Glutes 2nd <- Day2 Quads (row37<-row20)
        SourceRatingPairing(dayIndex: 3, slotIndex: 2, pairedDayIndex: 1, pairedSlotIndex: 2), // Hamstrings Hip Hinge <- Day2 Hamstrings Isolation (row38<-row22)
        SourceRatingPairing(dayIndex: 3, slotIndex: 3, pairedDayIndex: 1, pairedSlotIndex: 0), // Quads <- Day2 Quads (row39<-row20)
        SourceRatingPairing(dayIndex: 3, slotIndex: 4, pairedDayIndex: 1, pairedSlotIndex: 3), // Calves <- Day2 Calves (row40<-row23)
        // Day 5 (Shoulders/Arms Upper), rows 44-50
        SourceRatingPairing(dayIndex: 4, slotIndex: 0, pairedDayIndex: 0, pairedSlotIndex: 3), // Biceps <- Day1 Horizontal Pull (row44<-row14)
        SourceRatingPairing(dayIndex: 4, slotIndex: 1, pairedDayIndex: 0, pairedSlotIndex: 0), // Triceps <- Day1 Incline Chest (row45<-row11)
        SourceRatingPairing(dayIndex: 4, slotIndex: 2, pairedDayIndex: 0, pairedSlotIndex: 0), // Front Delts <- Day1 Incline Chest (row46<-row11)
        SourceRatingPairing(dayIndex: 4, slotIndex: 3, pairedDayIndex: 0, pairedSlotIndex: 4), // Traps <- Day1 Rear or Side Delts (row47<-row15)
        SourceRatingPairing(dayIndex: 4, slotIndex: 4, pairedDayIndex: 0, pairedSlotIndex: 3), // Vertical Pull <- Day1 Horizontal Pull (row48<-row14)
        SourceRatingPairing(dayIndex: 4, slotIndex: 5, pairedDayIndex: 0, pairedSlotIndex: 0), // Incline Chest <- Day1 Incline Chest (row49<-row11)
        SourceRatingPairing(dayIndex: 4, slotIndex: 6, pairedDayIndex: 0, pairedSlotIndex: 5), // Abs <- Day1 Abs (row50<-row16)
    ]

    /// Source Authority Repair — 5-Day Full Body, Mesocycle 2 "Metabolite
    /// Focus": recovered directly from `source_workbooks/5 day full
    /// body.xlsx`, sheet "Mesocycle 2 Metabolite Focus", rows 11-54.
    /// Factor 0.75 confirmed (`J11='=MROUND(((G11)*0.75),5)'`), rounding
    /// unit 5. 32 slots/week (7+4+7+5+9) — unlike 4-Day's M2 (exactly
    /// one superset per day, every day), this workbook's 4 real supersets
    /// are unevenly distributed: Day1 has one (Chest Isolation + primary
    /// / Horizontal Chest partner, cross-category), Day3 has one (Rear
    /// or Side Delts + Rear or Side Delts, same-category-doubled), Day5
    /// has TWO (Biceps + Biceps same-category-doubled; Triceps + Front
    /// Delts cross-category) — Day2 and Day4 have none. All 4 partners
    /// confirmed at factor 0.6 (`metaboliteFocusPairedWeekOneFactor`)
    /// and confirmed via real Week-3/4 formula trace to cascade normally
    /// (none freeze — `freezeAfterWeek` stays `nil` for all 4, exactly
    /// as 4-Day's own M2 partners do).
    static let fiveDayFullBodyMesocycle2MetaboliteFocus: [SourceDay] = [
        SourceDay(sourceEmphasisName: "Chest Upper", categories: [
            SourceCategorySlot(sourceLabel: "Incline Chest", category: .inclinePush, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Chest Isolation", category: .chestIsolation, weekOneSets: 3, isSupersetPartner: false),
            SourceCategorySlot(sourceLabel: "Horizontal Chest", category: .horizontalPush, weekOneSets: 3, isSupersetPartner: true),
            SourceCategorySlot(sourceLabel: "Horizontal Chest", category: .horizontalPush, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Rear or Side Delts", category: .rearOrSideDelts, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Abs", category: .abs, weekOneSets: 3),
        ]),
        SourceDay(sourceEmphasisName: "Quads Focused Legs", categories: [
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Hamstrings Isolation", category: .hamstringsIsolation, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Calves", category: .calves, weekOneSets: 6),
        ]),
        SourceDay(sourceEmphasisName: "Back Upper", categories: [
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Chest", category: .horizontalPush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Rear or Side Delts", category: .rearOrSideDelts, weekOneSets: 3, isSupersetPartner: false),
            SourceCategorySlot(sourceLabel: "Rear or Side Delts", category: .rearOrSideDelts, weekOneSets: 3, isSupersetPartner: true),
            SourceCategorySlot(sourceLabel: "Abs", category: .abs, weekOneSets: 3),
        ]),
        SourceDay(sourceEmphasisName: "Glute/Ham Focused Legs", categories: [
            SourceCategorySlot(sourceLabel: "Glutes", category: .glutes, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Glutes", category: .glutes, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Hamstrings Hip Hinge", category: .hamstringsHipHinge, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Calves", category: .calves, weekOneSets: 6),
        ]),
        SourceDay(sourceEmphasisName: "Shoulders/Arms Upper", categories: [
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 4, isSupersetPartner: false),
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 4, isSupersetPartner: true),
            SourceCategorySlot(sourceLabel: "Triceps", category: .triceps, weekOneSets: 4, isSupersetPartner: false),
            SourceCategorySlot(sourceLabel: "Front Delts", category: .frontDelts, weekOneSets: 4, isSupersetPartner: true),
            SourceCategorySlot(sourceLabel: "Front Delts", category: .frontDelts, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Traps", category: .traps, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Incline Chest", category: .inclinePush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Abs", category: .abs, weekOneSets: 3),
        ]),
    ]

    /// Source Authority Repair — 5-Day Full Body Mesocycle 2's real
    /// rating web. Every superset partner's own pairing target confirmed
    /// to be the SAME external row its own primary reads (e.g.
    /// `O13='=I12+(M31)'`, identical target to `O12`, with SETS sourced
    /// from the primary's own `I12`, never the partner's own `I13`) —
    /// the same slaved-sets mechanism already proven for 3-/4-Day.
    static let fiveDayFullBodyMesocycle2RatingPairings: [SourceRatingPairing] = [
        // Day 1 (Chest Upper), rows 11-17
        SourceRatingPairing(dayIndex: 0, slotIndex: 0, pairedDayIndex: 2, pairedSlotIndex: 3), // Incline Chest <- Day3 Horizontal Chest (row11<-row31)
        SourceRatingPairing(dayIndex: 0, slotIndex: 1, pairedDayIndex: 2, pairedSlotIndex: 3), // Chest Isolation (primary) <- Day3 Horizontal Chest (row12<-row31)
        SourceRatingPairing(dayIndex: 0, slotIndex: 2, pairedDayIndex: 2, pairedSlotIndex: 3), // Horizontal Chest (partner) <- same target as slot1 (row13<-row31)
        SourceRatingPairing(dayIndex: 0, slotIndex: 3, pairedDayIndex: 2, pairedSlotIndex: 4), // Horizontal Chest (standalone) <- Day3 Rear or Side Delts (row14<-row32)
        SourceRatingPairing(dayIndex: 0, slotIndex: 4, pairedDayIndex: 2, pairedSlotIndex: 2), // Horizontal Pull <- Day3 Horizontal Pull (row15<-row30)
        SourceRatingPairing(dayIndex: 0, slotIndex: 5, pairedDayIndex: 2, pairedSlotIndex: 4), // Rear or Side Delts <- Day3 Rear or Side Delts (row16<-row32)
        SourceRatingPairing(dayIndex: 0, slotIndex: 6, pairedDayIndex: 2, pairedSlotIndex: 6), // Abs <- Day3 Abs (row17<-row34)
        // Day 2 (Quads Focused Legs), rows 21-24
        SourceRatingPairing(dayIndex: 1, slotIndex: 0, pairedDayIndex: 3, pairedSlotIndex: 3), // Quads 1st <- Day4 Quads (row21<-row41)
        SourceRatingPairing(dayIndex: 1, slotIndex: 1, pairedDayIndex: 3, pairedSlotIndex: 3), // Quads 2nd <- Day4 Quads (row22<-row41)
        SourceRatingPairing(dayIndex: 1, slotIndex: 2, pairedDayIndex: 3, pairedSlotIndex: 2), // Hamstrings Isolation <- Day4 Hamstrings Hip Hinge (row23<-row40)
        SourceRatingPairing(dayIndex: 1, slotIndex: 3, pairedDayIndex: 3, pairedSlotIndex: 4), // Calves <- Day4 Calves (row24<-row42)
        // Day 3 (Back Upper), rows 28-34
        SourceRatingPairing(dayIndex: 2, slotIndex: 0, pairedDayIndex: 4, pairedSlotIndex: 6), // Vertical Pull 1st <- Day5 Vertical Pull (row28<-row52)
        SourceRatingPairing(dayIndex: 2, slotIndex: 1, pairedDayIndex: 4, pairedSlotIndex: 6), // Vertical Pull 2nd <- Day5 Vertical Pull (row29<-row52)
        SourceRatingPairing(dayIndex: 2, slotIndex: 2, pairedDayIndex: 4, pairedSlotIndex: 6), // Horizontal Pull <- Day5 Vertical Pull (row30<-row52)
        SourceRatingPairing(dayIndex: 2, slotIndex: 3, pairedDayIndex: 4, pairedSlotIndex: 7), // Horizontal Chest <- Day5 Incline Chest (row31<-row53)
        SourceRatingPairing(dayIndex: 2, slotIndex: 4, pairedDayIndex: 0, pairedSlotIndex: 5), // Rear or Side Delts (primary) <- Day1 Rear or Side Delts (row32<-row16)
        SourceRatingPairing(dayIndex: 2, slotIndex: 5, pairedDayIndex: 0, pairedSlotIndex: 5), // Rear or Side Delts (partner) <- same target as slot4 (row33<-row16)
        SourceRatingPairing(dayIndex: 2, slotIndex: 6, pairedDayIndex: 4, pairedSlotIndex: 8), // Abs <- Day5 Abs (row34<-row54)
        // Day 4 (Glute/Ham Focused Legs), rows 38-42
        SourceRatingPairing(dayIndex: 3, slotIndex: 0, pairedDayIndex: 1, pairedSlotIndex: 0), // Glutes 1st <- Day2 Quads (row38<-row21)
        SourceRatingPairing(dayIndex: 3, slotIndex: 1, pairedDayIndex: 1, pairedSlotIndex: 0), // Glutes 2nd <- Day2 Quads (row39<-row21)
        SourceRatingPairing(dayIndex: 3, slotIndex: 2, pairedDayIndex: 1, pairedSlotIndex: 2), // Hamstrings Hip Hinge <- Day2 Hamstrings Isolation (row40<-row23)
        SourceRatingPairing(dayIndex: 3, slotIndex: 3, pairedDayIndex: 1, pairedSlotIndex: 0), // Quads <- Day2 Quads (row41<-row21)
        SourceRatingPairing(dayIndex: 3, slotIndex: 4, pairedDayIndex: 1, pairedSlotIndex: 3), // Calves <- Day2 Calves (row42<-row24)
        // Day 5 (Shoulders/Arms Upper), rows 46-54
        SourceRatingPairing(dayIndex: 4, slotIndex: 0, pairedDayIndex: 0, pairedSlotIndex: 4), // Biceps (primary) <- Day1 Horizontal Pull (row46<-row15)
        SourceRatingPairing(dayIndex: 4, slotIndex: 1, pairedDayIndex: 0, pairedSlotIndex: 4), // Biceps (partner) <- same target as slot0 (row47<-row15)
        SourceRatingPairing(dayIndex: 4, slotIndex: 2, pairedDayIndex: 0, pairedSlotIndex: 1), // Triceps (primary) <- Day1 Chest Isolation (row48<-row12)
        SourceRatingPairing(dayIndex: 4, slotIndex: 3, pairedDayIndex: 0, pairedSlotIndex: 1), // Front Delts (partner) <- same target as slot2 (row49<-row12)
        SourceRatingPairing(dayIndex: 4, slotIndex: 4, pairedDayIndex: 0, pairedSlotIndex: 0), // Front Delts (standalone) <- Day1 Incline Chest (row50<-row11)
        SourceRatingPairing(dayIndex: 4, slotIndex: 5, pairedDayIndex: 0, pairedSlotIndex: 5), // Traps <- Day1 Rear or Side Delts (row51<-row16)
        SourceRatingPairing(dayIndex: 4, slotIndex: 6, pairedDayIndex: 0, pairedSlotIndex: 4), // Vertical Pull <- Day1 Horizontal Pull (row52<-row15)
        SourceRatingPairing(dayIndex: 4, slotIndex: 7, pairedDayIndex: 0, pairedSlotIndex: 0), // Incline Chest <- Day1 Incline Chest (row53<-row11)
        SourceRatingPairing(dayIndex: 4, slotIndex: 8, pairedDayIndex: 0, pairedSlotIndex: 6), // Abs <- Day1 Abs (row54<-row17)
    ]

    /// Source Authority Repair — 5-Day Full Body, Mesocycle 3
    /// "Resensitization": recovered directly from `source_workbooks/5
    /// day full body.xlsx`, sheet "Mesocycle 3 Resensitization", rows
    /// 10-46. 3-week block confirmed (`T8='Week 3: Deload'`), factor 1.0
    /// confirmed (`J11='=MROUND(((G11)),5)'`, no multiplier), rounding
    /// unit 5. 24 slots/week (5+3+5+4+7), no superset markers found on
    /// any row.
    static let fiveDayFullBodyMesocycle3Resensitization: [SourceDay] = [
        SourceDay(sourceEmphasisName: "Chest Upper", categories: [
            SourceCategorySlot(sourceLabel: "Incline Chest", category: .inclinePush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Chest", category: .horizontalPush, weekOneSets: 1),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Rear or Side Delts", category: .rearOrSideDelts, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Abs", category: .abs, weekOneSets: 2),
        ]),
        SourceDay(sourceEmphasisName: "Quads Focused Legs", categories: [
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Hamstrings Isolation", category: .hamstringsIsolation, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Calves", category: .calves, weekOneSets: 5),
        ]),
        SourceDay(sourceEmphasisName: "Back Upper", categories: [
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Horizontal Chest", category: .horizontalPush, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Rear or Side Delts", category: .rearOrSideDelts, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Abs", category: .abs, weekOneSets: 2),
        ]),
        SourceDay(sourceEmphasisName: "Glute/Ham Focused Legs", categories: [
            SourceCategorySlot(sourceLabel: "Glutes", category: .glutes, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Hamstrings Hip Hinge", category: .hamstringsHipHinge, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Quads", category: .quads, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Calves", category: .calves, weekOneSets: 5),
        ]),
        SourceDay(sourceEmphasisName: "Shoulders/Arms Upper", categories: [
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Triceps", category: .triceps, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Front Delts", category: .frontDelts, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Traps", category: .traps, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Incline Chest", category: .inclinePush, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Abs", category: .abs, weekOneSets: 2),
        ]),
    ]

    /// Source Authority Repair — 5-Day Full Body Mesocycle 3's real
    /// rating web (Week 1 -> Week 2 only — a 3-week block has no Week
    /// 2 -> Week 3, since Week 3 is deload). Real deload boundary
    /// confirmed directly (`V` column, "Week 3: Deload" weight):
    /// Days 1-3 read full Week-1 weight unchanged, Days 4-5 read
    /// `MROUND(J*0.5,5)` — exactly `DeloadStrategy`'s existing, UNMODIFIED
    /// `ceil(dayCount/2)` boundary formula (`ceil(5/2)=3`) already
    /// produces for a 5-day program; zero code change required.
    static let fiveDayFullBodyMesocycle3RatingPairings: [SourceRatingPairing] = [
        // Day 1 (Chest Upper), rows 11-15
        SourceRatingPairing(dayIndex: 0, slotIndex: 0, pairedDayIndex: 2, pairedSlotIndex: 2), // Incline Chest <- Day3 Horizontal Chest (row11<-row27)
        SourceRatingPairing(dayIndex: 0, slotIndex: 1, pairedDayIndex: 2, pairedSlotIndex: 2), // Horizontal Chest <- Day3 Horizontal Chest (row12<-row27)
        SourceRatingPairing(dayIndex: 0, slotIndex: 2, pairedDayIndex: 2, pairedSlotIndex: 1), // Horizontal Pull <- Day3 Horizontal Pull (row13<-row26)
        SourceRatingPairing(dayIndex: 0, slotIndex: 3, pairedDayIndex: 2, pairedSlotIndex: 3), // Rear or Side Delts <- Day3 Rear or Side Delts (row14<-row28)
        SourceRatingPairing(dayIndex: 0, slotIndex: 4, pairedDayIndex: 2, pairedSlotIndex: 4), // Abs <- Day3 Abs (row15<-row29)
        // Day 2 (Quads Focused Legs), rows 19-21
        SourceRatingPairing(dayIndex: 1, slotIndex: 0, pairedDayIndex: 3, pairedSlotIndex: 2), // Quads <- Day4 Quads (row19<-row35)
        SourceRatingPairing(dayIndex: 1, slotIndex: 1, pairedDayIndex: 3, pairedSlotIndex: 1), // Hamstrings Isolation <- Day4 Hamstrings Hip Hinge (row20<-row34)
        SourceRatingPairing(dayIndex: 1, slotIndex: 2, pairedDayIndex: 3, pairedSlotIndex: 3), // Calves <- Day4 Calves (row21<-row36)
        // Day 3 (Back Upper), rows 25-29
        SourceRatingPairing(dayIndex: 2, slotIndex: 0, pairedDayIndex: 4, pairedSlotIndex: 4), // Vertical Pull <- Day5 Vertical Pull (row25<-row44)
        SourceRatingPairing(dayIndex: 2, slotIndex: 1, pairedDayIndex: 4, pairedSlotIndex: 4), // Horizontal Pull <- Day5 Vertical Pull (row26<-row44)
        SourceRatingPairing(dayIndex: 2, slotIndex: 2, pairedDayIndex: 4, pairedSlotIndex: 5), // Horizontal Chest <- Day5 Incline Chest (row27<-row45)
        SourceRatingPairing(dayIndex: 2, slotIndex: 3, pairedDayIndex: 0, pairedSlotIndex: 3), // Rear or Side Delts <- Day1 Rear or Side Delts (row28<-row14)
        SourceRatingPairing(dayIndex: 2, slotIndex: 4, pairedDayIndex: 4, pairedSlotIndex: 6), // Abs <- Day5 Abs (row29<-row46)
        // Day 4 (Glute/Ham Focused Legs), rows 33-36
        SourceRatingPairing(dayIndex: 3, slotIndex: 0, pairedDayIndex: 1, pairedSlotIndex: 0), // Glutes <- Day2 Quads (row33<-row19)
        SourceRatingPairing(dayIndex: 3, slotIndex: 1, pairedDayIndex: 1, pairedSlotIndex: 1), // Hamstrings Hip Hinge <- Day2 Hamstrings Isolation (row34<-row20)
        SourceRatingPairing(dayIndex: 3, slotIndex: 2, pairedDayIndex: 1, pairedSlotIndex: 0), // Quads <- Day2 Quads (row35<-row19)
        SourceRatingPairing(dayIndex: 3, slotIndex: 3, pairedDayIndex: 1, pairedSlotIndex: 2), // Calves <- Day2 Calves (row36<-row21)
        // Day 5 (Shoulders/Arms Upper), rows 40-46
        SourceRatingPairing(dayIndex: 4, slotIndex: 0, pairedDayIndex: 0, pairedSlotIndex: 2), // Biceps <- Day1 Horizontal Pull (row40<-row13)
        SourceRatingPairing(dayIndex: 4, slotIndex: 1, pairedDayIndex: 0, pairedSlotIndex: 0), // Triceps <- Day1 Incline Chest (row41<-row11)
        SourceRatingPairing(dayIndex: 4, slotIndex: 2, pairedDayIndex: 0, pairedSlotIndex: 0), // Front Delts <- Day1 Incline Chest (row42<-row11)
        SourceRatingPairing(dayIndex: 4, slotIndex: 3, pairedDayIndex: 0, pairedSlotIndex: 3), // Traps <- Day1 Rear or Side Delts (row43<-row14)
        SourceRatingPairing(dayIndex: 4, slotIndex: 4, pairedDayIndex: 0, pairedSlotIndex: 2), // Vertical Pull <- Day1 Horizontal Pull (row44<-row13)
        SourceRatingPairing(dayIndex: 4, slotIndex: 5, pairedDayIndex: 0, pairedSlotIndex: 0), // Incline Chest <- Day1 Incline Chest (row45<-row11)
        SourceRatingPairing(dayIndex: 4, slotIndex: 6, pairedDayIndex: 0, pairedSlotIndex: 4), // Abs <- Day1 Abs (row46<-row15)
    ]

    /// Source Authority Repair — 6-Day Full Body, Mesocycle 1 "Basic
    /// Hypertrophy": recovered directly from `source_workbooks/6 day full
    /// body.xlsx`, sheet "Mesocycle 1 Basic Hypertrophy", rows 11-55.
    /// Factor 0.85 confirmed (`J11='=MROUND(((G11)*0.85),5)'`), rounding
    /// unit 5. 30 slots/week (5+5+5+5+5+5 — "perfectly uniform 5 slots/
    /// day," matching `SOURCE_PROGRAM_MANIFEST.md` §6's own claim). Day
    /// emphasis names preserved verbatim from source column B ("Chest
    /// Focused Upper," "Quad Focused Lower," "Arms Focused Upper," "Glute
    /// Focused Lower," "Back Focused Upper," "Ham Calf Shoulder Focused"
    /// — Day 6 genuinely omits the "Upper/Lower" suffix in the source
    /// itself, not a transcription simplification). This workbook's own
    /// category labels are singular ("Quad," "Glute," "Hamstring
    /// Isolation," "Hamstring Hip Hinge") — resolved via
    /// `SourceHypertrophyCategory.labelAliases`' new entries to the SAME
    /// existing categories every other Family A file labels in plural.
    static let sixDayFullBodyMesocycle1BasicHypertrophy: [SourceDay] = [
        SourceDay(sourceEmphasisName: "Chest Focused Upper", categories: [
            SourceCategorySlot(sourceLabel: "Incline Push", category: .inclinePush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Chest Isolation", category: .chestIsolation, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Rear or Side Delts", category: .rearOrSideDelts, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 2),
        ]),
        SourceDay(sourceEmphasisName: "Quad Focused Lower", categories: [
            SourceCategorySlot(sourceLabel: "Quad", category: .quads, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Quad", category: .quads, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Hamstring Isolation", category: .hamstringsIsolation, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Calves", category: .calves, weekOneSets: 6),
            SourceCategorySlot(sourceLabel: "Abs", category: .abs, weekOneSets: 3),
        ]),
        SourceDay(sourceEmphasisName: "Arms Focused Upper", categories: [
            SourceCategorySlot(sourceLabel: "Triceps", category: .triceps, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Triceps", category: .triceps, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
        ]),
        SourceDay(sourceEmphasisName: "Glute Focused Lower", categories: [
            SourceCategorySlot(sourceLabel: "Glute", category: .glutes, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Glute", category: .glutes, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Quad", category: .quads, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Calves", category: .calves, weekOneSets: 6),
            SourceCategorySlot(sourceLabel: "Abs", category: .abs, weekOneSets: 3),
        ]),
        SourceDay(sourceEmphasisName: "Back Focused Upper", categories: [
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 3),
        ]),
        SourceDay(sourceEmphasisName: "Ham Calf Shoulder Focused", categories: [
            SourceCategorySlot(sourceLabel: "Hamstring Hip Hinge", category: .hamstringsHipHinge, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Calves", category: .calves, weekOneSets: 6),
            SourceCategorySlot(sourceLabel: "Front Delts", category: .frontDelts, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Rear or Side Delts", category: .rearOrSideDelts, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Traps", category: .traps, weekOneSets: 3),
        ]),
    ]

    /// Source Authority Repair — 6-Day Full Body Mesocycle 1's real
    /// rating web, recovered cell-by-cell from the workbook's "Week 2
    /// Sets" formulas (30 relationships, rows 11-55). Same chronological
    /// most-recently-trained-related-category mechanism already
    /// established for 3/4/5-Day.
    static let sixDayFullBodyMesocycle1RatingPairings: [SourceRatingPairing] = [
        // Day 1 (Chest Focused Upper), rows 11-15
        SourceRatingPairing(dayIndex: 0, slotIndex: 0, pairedDayIndex: 2, pairedSlotIndex: 2), // Incline Push <- Day3 Horizontal Push (row11<-row29)
        SourceRatingPairing(dayIndex: 0, slotIndex: 1, pairedDayIndex: 2, pairedSlotIndex: 2), // Chest Isolation <- Day3 Horizontal Push (row12<-row29)
        SourceRatingPairing(dayIndex: 0, slotIndex: 2, pairedDayIndex: 2, pairedSlotIndex: 2), // Horizontal Push <- Day3 Horizontal Push (row13<-row29)
        SourceRatingPairing(dayIndex: 0, slotIndex: 3, pairedDayIndex: 5, pairedSlotIndex: 3), // Rear or Side Delts <- Day6 Rear or Side Delts (row14<-row54)
        SourceRatingPairing(dayIndex: 0, slotIndex: 4, pairedDayIndex: 2, pairedSlotIndex: 4), // Horizontal Pull <- Day3 Vertical Pull (row15<-row31)
        // Day 2 (Quad Focused Lower), rows 19-23
        SourceRatingPairing(dayIndex: 1, slotIndex: 0, pairedDayIndex: 3, pairedSlotIndex: 2), // Quad 1st <- Day4 Quad (row19<-row37)
        SourceRatingPairing(dayIndex: 1, slotIndex: 1, pairedDayIndex: 3, pairedSlotIndex: 2), // Quad 2nd <- Day4 Quad (row20<-row37)
        SourceRatingPairing(dayIndex: 1, slotIndex: 2, pairedDayIndex: 5, pairedSlotIndex: 0), // Hamstring Isolation <- Day6 Hamstring Hip Hinge (row21<-row51)
        SourceRatingPairing(dayIndex: 1, slotIndex: 3, pairedDayIndex: 3, pairedSlotIndex: 3), // Calves <- Day4 Calves (row22<-row38)
        SourceRatingPairing(dayIndex: 1, slotIndex: 4, pairedDayIndex: 3, pairedSlotIndex: 4), // Abs <- Day4 Abs (row23<-row39)
        // Day 3 (Arms Focused Upper), rows 27-31
        SourceRatingPairing(dayIndex: 2, slotIndex: 0, pairedDayIndex: 5, pairedSlotIndex: 2), // Triceps 1st <- Day6 Front Delts (row27<-row53)
        SourceRatingPairing(dayIndex: 2, slotIndex: 1, pairedDayIndex: 5, pairedSlotIndex: 2), // Triceps 2nd <- Day6 Front Delts (row28<-row53)
        SourceRatingPairing(dayIndex: 2, slotIndex: 2, pairedDayIndex: 0, pairedSlotIndex: 2), // Horizontal Push <- Day1 Horizontal Push (row29<-row13)
        SourceRatingPairing(dayIndex: 2, slotIndex: 3, pairedDayIndex: 4, pairedSlotIndex: 3), // Biceps <- Day5 Biceps (row30<-row46)
        SourceRatingPairing(dayIndex: 2, slotIndex: 4, pairedDayIndex: 4, pairedSlotIndex: 0), // Vertical Pull <- Day5 Vertical Pull (row31<-row43)
        // Day 4 (Glute Focused Lower), rows 35-39
        SourceRatingPairing(dayIndex: 3, slotIndex: 0, pairedDayIndex: 1, pairedSlotIndex: 0), // Glute 1st <- Day2 Quad (row35<-row19)
        SourceRatingPairing(dayIndex: 3, slotIndex: 1, pairedDayIndex: 1, pairedSlotIndex: 0), // Glute 2nd <- Day2 Quad (row36<-row19)
        SourceRatingPairing(dayIndex: 3, slotIndex: 2, pairedDayIndex: 1, pairedSlotIndex: 0), // Quad <- Day2 Quad (row37<-row19)
        SourceRatingPairing(dayIndex: 3, slotIndex: 3, pairedDayIndex: 5, pairedSlotIndex: 1), // Calves <- Day6 Calves (row38<-row52)
        SourceRatingPairing(dayIndex: 3, slotIndex: 4, pairedDayIndex: 1, pairedSlotIndex: 4), // Abs <- Day2 Abs (row39<-row23)
        // Day 5 (Back Focused Upper), rows 43-47
        SourceRatingPairing(dayIndex: 4, slotIndex: 0, pairedDayIndex: 0, pairedSlotIndex: 4), // Vertical Pull 1st <- Day1 Horizontal Pull (row43<-row15)
        SourceRatingPairing(dayIndex: 4, slotIndex: 1, pairedDayIndex: 0, pairedSlotIndex: 4), // Vertical Pull 2nd <- Day1 Horizontal Pull (row44<-row15)
        SourceRatingPairing(dayIndex: 4, slotIndex: 2, pairedDayIndex: 0, pairedSlotIndex: 4), // Horizontal Pull <- Day1 Horizontal Pull (row45<-row15)
        SourceRatingPairing(dayIndex: 4, slotIndex: 3, pairedDayIndex: 2, pairedSlotIndex: 3), // Biceps 1st <- Day3 Biceps (row46<-row30)
        SourceRatingPairing(dayIndex: 4, slotIndex: 4, pairedDayIndex: 2, pairedSlotIndex: 3), // Biceps 2nd <- Day3 Biceps (row47<-row30)
        // Day 6 (Ham Calf Shoulder Focused), rows 51-55
        SourceRatingPairing(dayIndex: 5, slotIndex: 0, pairedDayIndex: 1, pairedSlotIndex: 2), // Hamstring Hip Hinge <- Day2 Hamstring Isolation (row51<-row21)
        SourceRatingPairing(dayIndex: 5, slotIndex: 1, pairedDayIndex: 1, pairedSlotIndex: 3), // Calves <- Day2 Calves (row52<-row22)
        SourceRatingPairing(dayIndex: 5, slotIndex: 2, pairedDayIndex: 0, pairedSlotIndex: 0), // Front Delts <- Day1 Incline Push (row53<-row11)
        SourceRatingPairing(dayIndex: 5, slotIndex: 3, pairedDayIndex: 0, pairedSlotIndex: 3), // Rear or Side Delts 1st <- Day1 Rear or Side Delts (row54<-row14)
        SourceRatingPairing(dayIndex: 5, slotIndex: 4, pairedDayIndex: 0, pairedSlotIndex: 3), // Traps <- Day1 Rear or Side Delts (row55<-row14)
    ]

    /// Source Authority Repair — 6-Day Full Body, Mesocycle 2 "Metabolite
    /// Focus": recovered directly from `source_workbooks/6 day full
    /// body.xlsx`, sheet "Mesocycle 2 Metabolite Focus", rows 11-59.
    /// Factor 0.75 confirmed (`J11='=MROUND(((G11)*0.75),5)'`), rounding
    /// unit 5. 34 slots/week (6+5+6+5+6+6) — a NEW distribution not seen
    /// in 4-/5-Day: real supersets on 4 of 6 days (Days 1, 3, 5, 6 — cell-
    /// confirmed via the 'Super set this exercise'/'with this one'
    /// column-A markers), Days 2 and 4 have NONE. All 4 partner rows'
    /// weight formula independently confirmed at factor 0.6
    /// (`=MROUND(((G13)*0.6),5)` etc.), matching
    /// `metaboliteFocusPairedWeekOneFactor`. All 4 traced through their
    /// real Week-3/4 formulas and confirmed to cascade normally off their
    /// own primary's accumulating value (none freeze, same as 4-/5-Day's
    /// own findings for this file family).
    static let sixDayFullBodyMesocycle2MetaboliteFocus: [SourceDay] = [
        SourceDay(sourceEmphasisName: "Chest Focused Upper", categories: [
            SourceCategorySlot(sourceLabel: "Incline Push", category: .inclinePush, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Chest Isolation", category: .chestIsolation, weekOneSets: 3, isSupersetPartner: false),
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 3, isSupersetPartner: true),
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Rear or Side Delts", category: .rearOrSideDelts, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 2),
        ]),
        SourceDay(sourceEmphasisName: "Quad Focused Lower", categories: [
            SourceCategorySlot(sourceLabel: "Quad", category: .quads, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Quad", category: .quads, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Hamstring Isolation", category: .hamstringsIsolation, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Calves", category: .calves, weekOneSets: 6),
            SourceCategorySlot(sourceLabel: "Abs", category: .abs, weekOneSets: 3),
        ]),
        SourceDay(sourceEmphasisName: "Arms Focused Upper", categories: [
            SourceCategorySlot(sourceLabel: "Triceps", category: .triceps, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Triceps", category: .triceps, weekOneSets: 3, isSupersetPartner: false),
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 3, isSupersetPartner: true),
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
        ]),
        SourceDay(sourceEmphasisName: "Glute Focused Lower", categories: [
            SourceCategorySlot(sourceLabel: "Glute", category: .glutes, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Glute", category: .glutes, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Quad", category: .quads, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Calves", category: .calves, weekOneSets: 6),
            SourceCategorySlot(sourceLabel: "Abs", category: .abs, weekOneSets: 3),
        ]),
        SourceDay(sourceEmphasisName: "Back Focused Upper", categories: [
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 4, isSupersetPartner: false),
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 4, isSupersetPartner: true),
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 4),
        ]),
        SourceDay(sourceEmphasisName: "Ham Calf Shoulder Focused", categories: [
            SourceCategorySlot(sourceLabel: "Hamstring Hip Hinge", category: .hamstringsHipHinge, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Calves", category: .calves, weekOneSets: 6),
            SourceCategorySlot(sourceLabel: "Front Delts", category: .frontDelts, weekOneSets: 4),
            SourceCategorySlot(sourceLabel: "Rear or Side Delts", category: .rearOrSideDelts, weekOneSets: 4, isSupersetPartner: false),
            SourceCategorySlot(sourceLabel: "Rear or Side Delts", category: .rearOrSideDelts, weekOneSets: 4, isSupersetPartner: true),
            SourceCategorySlot(sourceLabel: "Traps", category: .traps, weekOneSets: 4),
        ]),
    ]

    /// Source Authority Repair — 6-Day Full Body Mesocycle 2's real
    /// rating web (34 relationships, rows 11-59). Every superset
    /// partner's own pairing target confirmed to be the SAME external row
    /// its own primary reads, never its own independent target — same
    /// convention already established for 3/4/5-Day.
    static let sixDayFullBodyMesocycle2RatingPairings: [SourceRatingPairing] = [
        // Day 1 (Chest Focused Upper), rows 11-16
        SourceRatingPairing(dayIndex: 0, slotIndex: 0, pairedDayIndex: 2, pairedSlotIndex: 3), // Incline Push <- Day3 Horizontal Push standalone (row11<-row31)
        SourceRatingPairing(dayIndex: 0, slotIndex: 1, pairedDayIndex: 2, pairedSlotIndex: 3), // Chest Isolation (primary) <- Day3 Horizontal Push standalone (row12<-row31)
        SourceRatingPairing(dayIndex: 0, slotIndex: 2, pairedDayIndex: 2, pairedSlotIndex: 3), // Horizontal Push (partner) <- same target as slot1 (row13<-row31)
        SourceRatingPairing(dayIndex: 0, slotIndex: 3, pairedDayIndex: 2, pairedSlotIndex: 3), // Horizontal Push (standalone) <- Day3 Horizontal Push standalone (row14<-row31)
        SourceRatingPairing(dayIndex: 0, slotIndex: 4, pairedDayIndex: 5, pairedSlotIndex: 3), // Rear or Side Delts <- Day6 Rear or Side Delts (primary) (row15<-row57)
        SourceRatingPairing(dayIndex: 0, slotIndex: 5, pairedDayIndex: 2, pairedSlotIndex: 5), // Horizontal Pull <- Day3 Vertical Pull (row16<-row33)
        // Day 2 (Quad Focused Lower), rows 20-24
        SourceRatingPairing(dayIndex: 1, slotIndex: 0, pairedDayIndex: 3, pairedSlotIndex: 2), // Quad 1st <- Day4 Quad (row20<-row39)
        SourceRatingPairing(dayIndex: 1, slotIndex: 1, pairedDayIndex: 3, pairedSlotIndex: 2), // Quad 2nd <- Day4 Quad (row21<-row39)
        SourceRatingPairing(dayIndex: 1, slotIndex: 2, pairedDayIndex: 5, pairedSlotIndex: 0), // Hamstring Isolation <- Day6 Hamstring Hip Hinge (row22<-row54)
        SourceRatingPairing(dayIndex: 1, slotIndex: 3, pairedDayIndex: 3, pairedSlotIndex: 3), // Calves <- Day4 Calves (row23<-row40)
        SourceRatingPairing(dayIndex: 1, slotIndex: 4, pairedDayIndex: 3, pairedSlotIndex: 4), // Abs <- Day4 Abs (row24<-row41)
        // Day 3 (Arms Focused Upper), rows 28-33
        SourceRatingPairing(dayIndex: 2, slotIndex: 0, pairedDayIndex: 5, pairedSlotIndex: 2), // Triceps (standalone) <- Day6 Front Delts (row28<-row56)
        SourceRatingPairing(dayIndex: 2, slotIndex: 1, pairedDayIndex: 5, pairedSlotIndex: 2), // Triceps (primary) <- Day6 Front Delts (row29<-row56)
        SourceRatingPairing(dayIndex: 2, slotIndex: 2, pairedDayIndex: 5, pairedSlotIndex: 2), // Horizontal Push (partner) <- same target as slot1 (row30<-row56)
        SourceRatingPairing(dayIndex: 2, slotIndex: 3, pairedDayIndex: 0, pairedSlotIndex: 3), // Horizontal Push (standalone) <- Day1 Horizontal Push standalone (row31<-row14)
        SourceRatingPairing(dayIndex: 2, slotIndex: 4, pairedDayIndex: 4, pairedSlotIndex: 3), // Biceps <- Day5 Biceps (primary) (row32<-row48)
        SourceRatingPairing(dayIndex: 2, slotIndex: 5, pairedDayIndex: 4, pairedSlotIndex: 0), // Vertical Pull <- Day5 Vertical Pull (row33<-row45)
        // Day 4 (Glute Focused Lower), rows 37-41
        SourceRatingPairing(dayIndex: 3, slotIndex: 0, pairedDayIndex: 1, pairedSlotIndex: 0), // Glute 1st <- Day2 Quad (row37<-row20)
        SourceRatingPairing(dayIndex: 3, slotIndex: 1, pairedDayIndex: 1, pairedSlotIndex: 0), // Glute 2nd <- Day2 Quad (row38<-row20)
        SourceRatingPairing(dayIndex: 3, slotIndex: 2, pairedDayIndex: 1, pairedSlotIndex: 0), // Quad <- Day2 Quad (row39<-row20)
        SourceRatingPairing(dayIndex: 3, slotIndex: 3, pairedDayIndex: 5, pairedSlotIndex: 1), // Calves <- Day6 Calves (row40<-row55)
        SourceRatingPairing(dayIndex: 3, slotIndex: 4, pairedDayIndex: 1, pairedSlotIndex: 4), // Abs <- Day2 Abs (row41<-row24)
        // Day 5 (Back Focused Upper), rows 45-50
        SourceRatingPairing(dayIndex: 4, slotIndex: 0, pairedDayIndex: 0, pairedSlotIndex: 5), // Vertical Pull 1st <- Day1 Horizontal Pull (row45<-row16)
        SourceRatingPairing(dayIndex: 4, slotIndex: 1, pairedDayIndex: 0, pairedSlotIndex: 5), // Vertical Pull 2nd <- Day1 Horizontal Pull (row46<-row16)
        SourceRatingPairing(dayIndex: 4, slotIndex: 2, pairedDayIndex: 0, pairedSlotIndex: 5), // Horizontal Pull <- Day1 Horizontal Pull (row47<-row16)
        SourceRatingPairing(dayIndex: 4, slotIndex: 3, pairedDayIndex: 2, pairedSlotIndex: 4), // Biceps (primary) <- Day3 Biceps (row48<-row32)
        SourceRatingPairing(dayIndex: 4, slotIndex: 4, pairedDayIndex: 2, pairedSlotIndex: 4), // Biceps (partner) <- same target as slot3 (row49<-row32)
        SourceRatingPairing(dayIndex: 4, slotIndex: 5, pairedDayIndex: 2, pairedSlotIndex: 4), // Biceps (standalone) <- Day3 Biceps (row50<-row32)
        // Day 6 (Ham Calf Shoulder Focused), rows 54-59
        SourceRatingPairing(dayIndex: 5, slotIndex: 0, pairedDayIndex: 1, pairedSlotIndex: 2), // Hamstring Hip Hinge <- Day2 Hamstring Isolation (row54<-row22)
        SourceRatingPairing(dayIndex: 5, slotIndex: 1, pairedDayIndex: 1, pairedSlotIndex: 3), // Calves <- Day2 Calves (row55<-row23)
        SourceRatingPairing(dayIndex: 5, slotIndex: 2, pairedDayIndex: 0, pairedSlotIndex: 0), // Front Delts <- Day1 Incline Push (row56<-row11)
        SourceRatingPairing(dayIndex: 5, slotIndex: 3, pairedDayIndex: 0, pairedSlotIndex: 4), // Rear or Side Delts (primary) <- Day1 Rear or Side Delts (row57<-row15)
        SourceRatingPairing(dayIndex: 5, slotIndex: 4, pairedDayIndex: 0, pairedSlotIndex: 4), // Rear or Side Delts (partner) <- same target as slot3 (row58<-row15)
        SourceRatingPairing(dayIndex: 5, slotIndex: 5, pairedDayIndex: 0, pairedSlotIndex: 4), // Traps <- Day1 Rear or Side Delts (row59<-row15)
    ]

    /// Source Authority Repair — 6-Day Full Body, Mesocycle 3
    /// "Resensitization": recovered directly from `source_workbooks/6 day
    /// full body.xlsx`, sheet "Mesocycle 3 Resensitization", rows 11-50.
    /// 3-week block (`T8='Week 3: Deload'`), factor 1.0
    /// (`J11='=MROUND(((G11)),5)'`, no multiplier), rounding unit 5. 25
    /// slots/week (4+4+4+4+4+5) — the only mesocycle where Day 6 gains an
    /// extra slot over the other five days (no supersets in this
    /// mesocycle at all — none of the 25 rows carry a 'Super set this
    /// exercise'/'with this one' marker).
    static let sixDayFullBodyMesocycle3Resensitization: [SourceDay] = [
        SourceDay(sourceEmphasisName: "Chest Focused Upper", categories: [
            SourceCategorySlot(sourceLabel: "Incline Push", category: .inclinePush, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Rear or Side Delts", category: .rearOrSideDelts, weekOneSets: 1),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 1),
        ]),
        SourceDay(sourceEmphasisName: "Quad Focused Lower", categories: [
            SourceCategorySlot(sourceLabel: "Quad", category: .quads, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Hamstring Isolation", category: .hamstringsIsolation, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Calves", category: .calves, weekOneSets: 5),
            SourceCategorySlot(sourceLabel: "Abs", category: .abs, weekOneSets: 2),
        ]),
        SourceDay(sourceEmphasisName: "Arms Focused Upper", categories: [
            SourceCategorySlot(sourceLabel: "Triceps", category: .triceps, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Horizontal Push", category: .horizontalPush, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 2),
        ]),
        SourceDay(sourceEmphasisName: "Glute Focused Lower", categories: [
            SourceCategorySlot(sourceLabel: "Glute", category: .glutes, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Quad", category: .quads, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Calves", category: .calves, weekOneSets: 5),
            SourceCategorySlot(sourceLabel: "Abs", category: .abs, weekOneSets: 2),
        ]),
        SourceDay(sourceEmphasisName: "Back Focused Upper", categories: [
            SourceCategorySlot(sourceLabel: "Vertical Pull", category: .verticalPull, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Horizontal Pull", category: .horizontalPull, weekOneSets: 2),
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Biceps", category: .biceps, weekOneSets: 3),
        ]),
        SourceDay(sourceEmphasisName: "Ham Calf Shoulder Focused", categories: [
            SourceCategorySlot(sourceLabel: "Hamstring Hip Hinge", category: .hamstringsHipHinge, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Calves", category: .calves, weekOneSets: 5),
            SourceCategorySlot(sourceLabel: "Front Delts", category: .frontDelts, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Rear or Side Delts", category: .rearOrSideDelts, weekOneSets: 3),
            SourceCategorySlot(sourceLabel: "Traps", category: .traps, weekOneSets: 3),
        ]),
    ]

    /// Source Authority Repair — 6-Day Full Body Mesocycle 3's real
    /// rating web (25 relationships, rows 11-50).
    static let sixDayFullBodyMesocycle3RatingPairings: [SourceRatingPairing] = [
        // Day 1 (Chest Focused Upper), rows 11-14
        SourceRatingPairing(dayIndex: 0, slotIndex: 0, pairedDayIndex: 2, pairedSlotIndex: 1), // Incline Push <- Day3 Horizontal Push (row11<-row26)
        SourceRatingPairing(dayIndex: 0, slotIndex: 1, pairedDayIndex: 2, pairedSlotIndex: 1), // Horizontal Push <- Day3 Horizontal Push (row12<-row26)
        SourceRatingPairing(dayIndex: 0, slotIndex: 2, pairedDayIndex: 5, pairedSlotIndex: 3), // Rear or Side Delts <- Day6 Rear or Side Delts (row13<-row49)
        SourceRatingPairing(dayIndex: 0, slotIndex: 3, pairedDayIndex: 2, pairedSlotIndex: 3), // Horizontal Pull <- Day3 Vertical Pull (row14<-row28)
        // Day 2 (Quad Focused Lower), rows 18-21
        SourceRatingPairing(dayIndex: 1, slotIndex: 0, pairedDayIndex: 3, pairedSlotIndex: 1), // Quad <- Day4 Quad (row18<-row33)
        SourceRatingPairing(dayIndex: 1, slotIndex: 1, pairedDayIndex: 5, pairedSlotIndex: 0), // Hamstring Isolation <- Day6 Hamstring Hip Hinge (row19<-row46)
        SourceRatingPairing(dayIndex: 1, slotIndex: 2, pairedDayIndex: 3, pairedSlotIndex: 2), // Calves <- Day4 Calves (row20<-row34)
        SourceRatingPairing(dayIndex: 1, slotIndex: 3, pairedDayIndex: 3, pairedSlotIndex: 3), // Abs <- Day4 Abs (row21<-row35)
        // Day 3 (Arms Focused Upper), rows 25-28
        SourceRatingPairing(dayIndex: 2, slotIndex: 0, pairedDayIndex: 5, pairedSlotIndex: 2), // Triceps <- Day6 Front Delts (row25<-row48)
        SourceRatingPairing(dayIndex: 2, slotIndex: 1, pairedDayIndex: 0, pairedSlotIndex: 1), // Horizontal Push <- Day1 Horizontal Push (row26<-row12)
        SourceRatingPairing(dayIndex: 2, slotIndex: 2, pairedDayIndex: 4, pairedSlotIndex: 2), // Biceps <- Day5 Biceps (row27<-row41)
        SourceRatingPairing(dayIndex: 2, slotIndex: 3, pairedDayIndex: 4, pairedSlotIndex: 0), // Vertical Pull <- Day5 Vertical Pull (row28<-row39)
        // Day 4 (Glute Focused Lower), rows 32-35
        SourceRatingPairing(dayIndex: 3, slotIndex: 0, pairedDayIndex: 1, pairedSlotIndex: 0), // Glute <- Day2 Quad (row32<-row18)
        SourceRatingPairing(dayIndex: 3, slotIndex: 1, pairedDayIndex: 1, pairedSlotIndex: 0), // Quad <- Day2 Quad (row33<-row18)
        SourceRatingPairing(dayIndex: 3, slotIndex: 2, pairedDayIndex: 5, pairedSlotIndex: 1), // Calves <- Day6 Calves (row34<-row47)
        SourceRatingPairing(dayIndex: 3, slotIndex: 3, pairedDayIndex: 1, pairedSlotIndex: 3), // Abs <- Day2 Abs (row35<-row21)
        // Day 5 (Back Focused Upper), rows 39-42
        SourceRatingPairing(dayIndex: 4, slotIndex: 0, pairedDayIndex: 0, pairedSlotIndex: 3), // Vertical Pull <- Day1 Horizontal Pull (row39<-row14)
        SourceRatingPairing(dayIndex: 4, slotIndex: 1, pairedDayIndex: 0, pairedSlotIndex: 3), // Horizontal Pull <- Day1 Horizontal Pull (row40<-row14)
        SourceRatingPairing(dayIndex: 4, slotIndex: 2, pairedDayIndex: 2, pairedSlotIndex: 2), // Biceps 1st <- Day3 Biceps (row41<-row27)
        SourceRatingPairing(dayIndex: 4, slotIndex: 3, pairedDayIndex: 2, pairedSlotIndex: 2), // Biceps 2nd <- Day3 Biceps (row42<-row27)
        // Day 6 (Ham Calf Shoulder Focused), rows 46-50
        SourceRatingPairing(dayIndex: 5, slotIndex: 0, pairedDayIndex: 1, pairedSlotIndex: 1), // Hamstring Hip Hinge <- Day2 Hamstring Isolation (row46<-row19)
        SourceRatingPairing(dayIndex: 5, slotIndex: 1, pairedDayIndex: 1, pairedSlotIndex: 2), // Calves <- Day2 Calves (row47<-row20)
        SourceRatingPairing(dayIndex: 5, slotIndex: 2, pairedDayIndex: 0, pairedSlotIndex: 0), // Front Delts <- Day1 Incline Push (row48<-row11)
        SourceRatingPairing(dayIndex: 5, slotIndex: 3, pairedDayIndex: 0, pairedSlotIndex: 2), // Rear or Side Delts <- Day1 Rear or Side Delts (row49<-row13)
        SourceRatingPairing(dayIndex: 5, slotIndex: 4, pairedDayIndex: 0, pairedSlotIndex: 2), // Traps <- Day1 Rear or Side Delts (row50<-row13)
    ]

    /// **TrainingOS execution-layer selection** (explicitly distinct from
    /// source content, per the Stage 10R.1 architecture) — which ONE of a
    /// category's several source-approved exercises this configuration
    /// currently resolves to, by canonical name. Every value here is
    /// either a literal source-approved name or a documented, narrow
    /// equivalence to one (e.g. "Barbell Bench Press" ≈ the source's
    /// "Medium Grip Bench Press"; "Conventional Deadlift" ≈ the source's
    /// plain "Deadlift" — never an unrelated substitute). `.quads` has two
    /// distinct occurrences on "Legs Emphasis"; `quadsOccurrenceNames`
    /// gives each a different, still source-approved exercise rather than
    /// prescribing the same movement twice in one day. This table may grow
    /// as the catalog gains more literal source-named exercises (Slice 2)
    /// — it is not itself the source-approved option set (see
    /// `SourceHypertrophyCategory.sourceApprovedExerciseNames`), only
    /// today's deterministic pick from within it.
    private static let sourceCategoryResolvedExerciseName: [SourceHypertrophyCategory: String] = [
        .horizontalPush: "Barbell Bench Press",
        .inclinePush: "Incline Dumbbell Press",
        .inclinePushOrFrontDelts: "Barbell Overhead Press",
        .chestIsolationOrTriceps: "Cable Chest Fly",
        .horizontalPull: "Barbell Row",
        .verticalPull: "Lat Pulldown",
        .sideDelts: "Dumbbell Lateral Raise",
        .rearOrSideDelts: "Face Pull",
        .biceps: "Barbell Curl",
        .glutes: "Conventional Deadlift",
        .hamstringsHipHinge: "Stiff-Legged Deadlift",
        .hamstringsIsolation: "Seated Leg Curl",
        // Source Authority Repair (4-Day Full Body): real, cataloged,
        // source-approved resolutions for the 4 additional categories
        // the 4-Day workbook's own slots require.
        .triceps: "Cable Triceps Pushdown",
        .frontDelts: "Barbell Overhead Press",
        .calves: "Seated Calf Raise",
        .abs: "Hanging Knee Raise",
        .traps: "Barbell Shrug",
        // Source Authority Repair (5-Day Full Body): "Cable Chest Fly" is
        // already a real, cataloged, source-approved exercise (shared
        // with `.chestIsolationOrTriceps`'s own resolution) — the exact
        // workbook cell for this slot literally reads "Cable Flye," the
        // same movement, so no new catalog exercise is needed.
        .chestIsolation: "Cable Chest Fly",
    ]
    private static let quadsOccurrenceNames = ["Front Squat", "Leg Press"]

    /// Looks up an already-persisted `Exercise` by exact canonical name —
    /// never creates one. Slice 1A never expands the catalog with a
    /// TrainingOS-invented exercise during resolution (Decision-required
    /// item 8); the one new catalog row this slice adds (`Stiff-Legged
    /// Deadlift`) is a real, source-named exercise added to
    /// `ExerciseCatalog` itself, not fabricated here.
    private static func findCatalogedExercise(named name: String, context: ModelContext) -> Exercise? {
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.canonicalName == name })
        return try? context.fetch(descriptor).first
    }

    /// Stage 10R.2A: the one place `generateDayFocusDriven` decides which
    /// mesocycle's real content to generate — a typed switch over
    /// `HypertrophyPhaseType`, never a week-index/display-string check.
    /// `.resensitization` throws rather than falling back to another
    /// phase's content or fabricating placeholder content — the exact
    /// pre-10R.2A bug (this path silently reused Mesocycle 1's content/
    /// factor "regardless of which `HypertrophyPhaseType` a caller
    /// passes") this stage corrects.
    /// Source Authority Repair: `dayCount` added so this same dispatch
    /// point can serve more than one day-focus-driven configuration.
    /// 4-Day Full Body's real Mesocycle 1/2/3 content is now fully
    /// recovered and wired here (Phase A2 completes Phase A1's M1-only
    /// slice) — no 4-Day phase throws `.phaseNotYetRecovered` any
    /// longer; the case itself is retained (never removed) for the same
    /// reason a future frequency/split without recovered content should
    /// throw it too, not silently reuse another configuration's content.
    private static func sourceContent(
        for phaseType: HypertrophyPhaseType, dayCount: Int
    ) throws -> (days: [SourceDay], pairings: [SourceRatingPairing]) {
        switch (dayCount, phaseType) {
        case (3, .basicHypertrophy):
            return (threeDayFullBodyMesocycle1BasicHypertrophy, threeDayFullBodyMesocycle1RatingPairings)
        case (3, .metaboliteFocus):
            return (threeDayFullBodyMesocycle2MetaboliteFocus, threeDayFullBodyMesocycle2RatingPairings)
        case (3, .resensitization):
            return (threeDayFullBodyMesocycle3Resensitization, threeDayFullBodyMesocycle3RatingPairings)
        case (4, .basicHypertrophy):
            return (fourDayFullBodyMesocycle1BasicHypertrophy, fourDayFullBodyMesocycle1RatingPairings)
        case (4, .metaboliteFocus):
            return (fourDayFullBodyMesocycle2MetaboliteFocus, fourDayFullBodyMesocycle2RatingPairings)
        case (4, .resensitization):
            return (fourDayFullBodyMesocycle3Resensitization, fourDayFullBodyMesocycle3RatingPairings)
        case (5, .basicHypertrophy):
            return (fiveDayFullBodyMesocycle1BasicHypertrophy, fiveDayFullBodyMesocycle1RatingPairings)
        case (5, .metaboliteFocus):
            return (fiveDayFullBodyMesocycle2MetaboliteFocus, fiveDayFullBodyMesocycle2RatingPairings)
        case (5, .resensitization):
            return (fiveDayFullBodyMesocycle3Resensitization, fiveDayFullBodyMesocycle3RatingPairings)
        case (6, .basicHypertrophy):
            return (sixDayFullBodyMesocycle1BasicHypertrophy, sixDayFullBodyMesocycle1RatingPairings)
        case (6, .metaboliteFocus):
            return (sixDayFullBodyMesocycle2MetaboliteFocus, sixDayFullBodyMesocycle2RatingPairings)
        case (6, .resensitization):
            return (sixDayFullBodyMesocycle3Resensitization, sixDayFullBodyMesocycle3RatingPairings)
        default:
            throw HypertrophyGenerationError.phaseNotYetRecovered(phaseType: phaseType)
        }
    }

    private static func generateDayFocusDriven(
        configuration: HypertrophyProgramConfiguration,
        provenance: ProgramProvenance,
        context: ModelContext
    ) throws -> ProgramDefinition {
        let (days, pairings) = try sourceContent(for: configuration.phaseType, dayCount: configuration.dayCount)
        let progressiveWeeks = progressiveWeekCount(for: configuration.phaseType)

        let definition = ProgramDefinition(
            name: "\(configuration.dayCount)-Day Full Body Hypertrophy — \(phaseName(configuration.phaseType))",
            lengthWeeks: progressiveWeeks + 1,
            intent: "\(phaseName(configuration.phaseType)), \(configuration.dayCount)-day Full Body — \(phaseName(configuration.phaseType)), recovered verbatim from the real source workbook (SOURCE_PROGRAM_MANIFEST.md §0/§3)",
            programmingSystem: .hypertrophy,
            generatorVersion: currentVersion,
            provenance: provenance,
            hypertrophyConfiguration: configuration
        )
        context.insert(definition)

        // Stage 10R.3A: phase-aware — Mesocycle 1/2 still build 4
        // progressive weeks + 1 deload (unchanged); Mesocycle 3 builds
        // only 2 + 1, per `progressiveWeekCount(for:)`'s doc comment.
        for _ in 0..<progressiveWeeks {
            let week = TrainingWeek(isDeload: false)
            context.insert(week)
            definition.addWeek(week)
        }
        let deloadWeek = TrainingWeek(isDeload: true)
        context.insert(deloadWeek)
        definition.addWeek(deloadWeek)

        // Built up per day/slot-index so `threeDayFullBodyMesocycle1RatingPairings`'
        // (dayIndex, slotIndex) coordinates can be resolved into real
        // `PrescriptionTemplate` references once every day's slots exist —
        // the pairing table deliberately indexes into
        // `threeDayFullBodyMesocycle1BasicHypertrophy` itself, not any
        // per-day-local numbering.
        var templatesByDayIndex: [[PrescriptionTemplate]] = []

        for day in days {
            let session = TemplateSession(name: day.sourceEmphasisName, role: .hypertrophy)
            context.insert(session)
            definition.addTemplateSession(session)

            let block = WorkoutBlockTemplate(type: .hypertrophy)
            context.insert(block)
            session.addBlockTemplate(block)

            var templatesThisDay: [PrescriptionTemplate] = []
            var quadsSeenThisDay = 0

            for categorySlot in day.categories {
                let template = makeSourceCategoryTemplate(
                    phaseType: configuration.phaseType,
                    baselineSets: categorySlot.weekOneSets,
                    isSupersetPartner: categorySlot.isSupersetPartner,
                    freezeAfterWeek: categorySlot.freezeAfterWeek
                )
                let slot = ExerciseSlot(
                    name: categorySlot.sourceLabel,
                    allowedTargets: categorySlot.category.allowedTargets,
                    allowedMovementFunctions: categorySlot.category.allowedMovementFunctions
                )

                // Deterministic, source-approved-set resolution — see
                // `sourceCategoryResolvedExerciseName`'s doc comment.
                // Pre-setting `resolvedExercise` here (rather than relying
                // on `ResolveProgramInstanceExerciseSlotsUseCase`'s
                // shared-pool overlap matching) is exactly the "idempotent,
                // already-resolved slot" seam that use case's own doc
                // comment already anticipates for curated content — it
                // never overwrites a slot that already has one.
                let exerciseName: String
                if categorySlot.category == .quads {
                    exerciseName = quadsOccurrenceNames[min(quadsSeenThisDay, quadsOccurrenceNames.count - 1)]
                    quadsSeenThisDay += 1
                } else {
                    exerciseName = sourceCategoryResolvedExerciseName[categorySlot.category] ?? ""
                }
                slot.resolvedExercise = findCatalogedExercise(named: exerciseName, context: context)

                context.insert(template)
                context.insert(slot)
                template.attachExerciseSlot(slot)
                template.slotRole = .primary
                block.addPrescriptionTemplate(template)
                templatesThisDay.append(template)
            }

            templatesByDayIndex.append(templatesThisDay)
        }

        // Stage 10R.1 Slice 1B / Stage 10R.2A: wire every slot's real,
        // fixed source rating-pairing target for whichever mesocycle
        // `sourceContent(for:)` selected above. Each pairing is a
        // structural, authoring-time `PrescriptionTemplate` reference
        // (Stage 3 decision A5), never re-derived from live training
        // history or from which exercise a slot happens to resolve to
        // (`SourceHypertrophyCategory` resolution is completely orthogonal
        // to this table — Part 3 of the Slice 1B design). A superset
        // partner's pairing target is set exactly like any other row's —
        // it happens to be the same external target its own primary uses
        // (confirmed cell-by-cell), which is what makes its resolved set
        // count track the primary's, with no separate mechanism needed.
        for pairing in pairings {
            guard
                templatesByDayIndex.indices.contains(pairing.dayIndex),
                templatesByDayIndex[pairing.dayIndex].indices.contains(pairing.slotIndex),
                templatesByDayIndex.indices.contains(pairing.pairedDayIndex),
                templatesByDayIndex[pairing.pairedDayIndex].indices.contains(pairing.pairedSlotIndex)
            else { continue }
            templatesByDayIndex[pairing.dayIndex][pairing.slotIndex].pairedSlot =
                templatesByDayIndex[pairing.pairedDayIndex][pairing.pairedSlotIndex]
        }

        return definition
    }

    /// Builds one `PrescriptionTemplate`'s rules for the real, recovered
    /// source progression of whichever mesocycle `phaseType` selects
    /// (Stage 10R.1 Slice 1B for Mesocycle 1, Stage 10R.2A for Mesocycle
    /// 2) — source-compatible `.rmBased` load (Week 1 = 10RM × the
    /// phase's own factor, Weeks 2-4 = the resolved Week-1 value × the
    /// shared Family A `laterWeekMultipliers`, both already-existing
    /// top-level constants on this type — confirmed by direct trace to be
    /// the exact mechanism `StrengthProgressionEngine.resolveWeight`'s
    /// `.rmBased` case already implements), the literal fixed rep/failure
    /// schedule (`repGoalSchedule`, also an existing top-level constant:
    /// `3/fail, 3/fail, 2/fail, 1/fail`, identical across both recovered
    /// mesocycles and every slot in each), and autoregulated set count
    /// with `treatMissingRatingAsNoChange: true` (Decision A — a blank
    /// source rating is "no change," never `.calibrationRequired,"
    /// confirmed identical Excel-arithmetic convention in both recovered
    /// mesocycles).
    ///
    /// **Stage 10R.2A addition:** `isSupersetPartner`/`freezeAfterWeek`
    /// (both default `false`/`nil`, so every Mesocycle 1 call site is
    /// byte-for-byte unaffected) represent Mesocycle 2's confirmed
    /// superset mechanic — a partner's own RM tests at
    /// `metaboliteFocusPairedWeekOneFactor` (0.6) rather than the phase's
    /// normal primary factor, off its own independently-entered RM
    /// (never the primary's resolved weight — `LoadRule.rmBased`, never
    /// `.linkedToPairedSlot`, for either row), and is completely omitted
    /// from deload (`STAGE3_DECISION_MEMO.md` Decision A2 — the source's
    /// own deload-week cells for these 3 rows are blank, not zero).
    /// **Deliberately, explicitly unchanged:** the deload path
    /// (`SourceCompatibleDeloadStrategy`, reached automatically once
    /// `loadRule` is `.rmBased`, never `.doubleProgression`) and every
    /// other `StrengthProgressionRules` default.
    private static func makeSourceCategoryTemplate(
        phaseType: HypertrophyPhaseType,
        baselineSets: Int,
        isSupersetPartner: Bool = false,
        freezeAfterWeek: Int? = nil
    ) -> PrescriptionTemplate {
        // `isSupersetPartner` is always `false` for Mesocycle 3 (positively
        // source-proven to have no supersets — §11/§14 of
        // `STAGE10R3_MESOCYCLE3_SOURCE_RECOVERY_DESIGN.md`), so this
        // branch always resolves to `primaryWeekOneFactor(for: .resensitization)`
        // (1.0) for that phase — no separate partner-factor constant
        // needed.
        let weekOneFactor = isSupersetPartner ? metaboliteFocusPairedWeekOneFactor : primaryWeekOneFactor(for: phaseType)
        return PrescriptionTemplate(rules: StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(
                rmType: .rm10,
                weekOneFactor: weekOneFactor,
                laterWeekMultipliers: dayFocusLaterWeekMultipliers(for: phaseType)
            )),
            setCountRule: .autoregulated(AutoregulatedSetCount(
                baselineSets: baselineSets, freezeAfterWeek: freezeAfterWeek, treatMissingRatingAsNoChange: true
            )),
            repGoalSchedule: dayFocusRepGoalSchedule(for: phaseType),
            deloadWeightAction: isSupersetPartner ? .omit : .standard,
            deloadRepAction: isSupersetPartner ? .omit : .standard
        ))
    }
}
