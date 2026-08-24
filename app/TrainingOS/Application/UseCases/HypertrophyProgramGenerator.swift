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
    static let currentVersion = 1

    /// The 3 non-deload weeks' multipliers of the *resolved* Week-1 value
    /// — identical across every Family A phase and (per
    /// `PROGRAM_FAMILY_MATRIX.md`'s cross-family proof table) every
    /// family, so this is not itself configuration.
    static let laterWeekMultipliers: [Double] = [1.05, 1.075, 1.1]

    /// `FAMILY_A_REP_GOAL_SCHEDULE`: identical across every phase/split.
    static let repGoalSchedule: [RepGoal] = [
        RepGoal(reps: 3, toFailure: true),
        RepGoal(reps: 3, toFailure: true),
        RepGoal(reps: 2, toFailure: true),
        RepGoal(reps: 1, toFailure: true)
    ]

    /// The paired accessory's own, separate rep scheme — a plain higher-rep
    /// isolation target, unaffected by the primary's rep-goal-to-failure
    /// schedule.
    static let pairedRepGoalSchedule: [RepGoal] = Array(repeating: RepGoal(reps: 12, toFailure: false), count: 4)

    /// `FAMILY_A_WEEK1_BASELINE`'s per-phase primary-movement factor.
    /// `.legs` split's confirmed Heavy exception (`FAMILY_A_LEGS_HEAVY_EXCEPTION`)
    /// overrides this to `1.0` regardless of phase — applied separately in
    /// `makeSlotPair`, not folded into this table.
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
    /// markers (4 progressive + 1 deload) and one recurring weekly
    /// structure — and inserts it into `context`. Does not resolve any
    /// `ExerciseSlot` to a concrete `Exercise`; see `ExerciseSlot`'s doc
    /// comment for when that happens.
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
        if configuration.dayCount == 3, configuration.split == .fullBody {
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

    private static func generateDayFocusDriven(
        configuration: HypertrophyProgramConfiguration,
        provenance: ProgramProvenance,
        context: ModelContext
    ) throws -> ProgramDefinition {
        let definition = ProgramDefinition(
            name: "3-Day Full Body Hypertrophy — \(phaseName(configuration.phaseType))",
            lengthWeeks: 5,
            intent: "\(phaseName(configuration.phaseType)), 3-day Full Body — Mesocycle 1 Basic Hypertrophy, recovered verbatim from the real source workbook (SOURCE_PROGRAM_MANIFEST.md §3)",
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

        for day in threeDayFullBodyMesocycle1BasicHypertrophy {
            let session = TemplateSession(name: day.sourceEmphasisName, role: .hypertrophy)
            context.insert(session)
            definition.addTemplateSession(session)

            let block = WorkoutBlockTemplate(type: .hypertrophy)
            context.insert(block)
            session.addBlockTemplate(block)

            var templatesThisDay: [PrescriptionTemplate] = []
            var quadsSeenThisDay = 0

            for categorySlot in day.categories {
                let template = makeSourceCategoryTemplate(baselineSets: categorySlot.weekOneSets)
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

            // Stage 10B.6's self-attribution fix is preserved exactly
            // (Decision on Stage 10B.6 classification: KEEP this specific
            // mechanism) — every slot rates itself, so no sibling's
            // feedback can fan out onto another slot's set count.
            // **Not** the real source's chronological last-trained-
            // occurrence pairing web (`SOURCE_PROGRAM_MANIFEST.md` §3) —
            // that is explicitly deferred to Slice 1B, per the Stage 10R.1
            // autoregulation decision; this slice is content-only.
            for template in templatesThisDay {
                template.pairedSlot = template
            }
        }

        return definition
    }

    /// Builds one `PrescriptionTemplate`'s rules for the Slice 1A
    /// source-content path. **Deliberately, explicitly unchanged from
    /// Stage 10B.6's progression mechanism** — `.doubleProgression` load,
    /// the `.primary`-role rep range/RIR trajectory
    /// (`HypertrophyV2ProgressionEngine`), autoregulated set count — per
    /// the Stage 10R.1 instruction "do not modify progression yet." The
    /// only change from the pre-Slice-1A version is `baselineSets`, which
    /// is now the literal source Week-1 value for this specific category
    /// slot (a content/data input) instead of a flat role-derived
    /// constant — every real Mesocycle-1 category in this workbook
    /// autoregulates the same way (to-failure, rated set-count), so every
    /// slot uses `.primary`'s rule shape (proven numerically identical to
    /// `.secondary`'s — `STAGE10B5_HYPERTROPHY_PRESCRIPTION_AUDIT.md` §10);
    /// none of them match `.accessory`'s fixed/never-autoregulated shape.
    private static func makeSourceCategoryTemplate(baselineSets: Int) -> PrescriptionTemplate {
        PrescriptionTemplate(rules: StrengthProgressionRules(
            loadRule: .doubleProgression,
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: baselineSets)),
            repGoalSchedule: HypertrophyV2ProgressionEngine.makeRepGoalSchedule(for: .primary)
        ))
    }
}
