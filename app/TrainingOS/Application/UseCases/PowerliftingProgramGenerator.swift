import Foundation
import SwiftData

/// Builds and persists a Family B ("RP Powerlifting Strength") or Family C
/// ("RP Powerlifting Hypertrophy-block") `ProgramDefinition`'s template
/// graph from a `PowerliftingProgramConfiguration` — the same
/// generator/template-graph architecture Stage 4A validated for
/// Hypertrophy, reused unchanged; only `StrengthProgressionRules`' rule
/// *parameters* differ per family (`PROGRAM_LOGIC_SPEC.md` §3-4,
/// Stage 3 decisions B2-B4).
///
/// **Powerlifting Source Authority Repair (this pass):** the previous
/// version of this generator proved the rule-engine mechanics with one
/// representative slot per day. This pass migrates both families to their
/// COMPLETE real structure — Family B's full 15-row/4-day layout and
/// Family C's full 16-row/5-day layout — re-verified directly against the
/// live `RP-PowerliftingStr-4-Day.xlsx` (a filled real example, used as an
/// exact numeric golden fixture — see `PowerliftingSourceFidelityTests.swift`)
/// and `RP-PowerliftingHyp-5-Day.xlsx` (blank canonical template, verified
/// structurally) this session — not merely inherited from
/// `PROGRAM_LOGIC_SPEC.md`/`SOURCE_PROGRAM_MANIFEST.md`, though both agree
/// with this migration exactly.
///
/// **Dual-reference fix (this pass) — resolved, no longer a known
/// divergence.** Family C's Friday backoff row genuinely needs two
/// DIFFERENT targets simultaneously in the real source (load ← Monday-
/// Push1's resolved weight; set-count autoregulation rating ← Wednesday-
/// Push2's rating) — confirmed directly from the live workbook's own
/// formulas (`D42`/`H42` reference different rows), re-confirmed again
/// this pass. The prior pass's version of this file used the single
/// `PrescriptionTemplate.pairedSlot` field for both purposes (an initial
/// implementation that exposed a genuine one-reference domain limitation:
/// `pairedSlot` alone cannot represent two different targets on the same
/// row), and disclosed the resulting mismatch (rating incorrectly also
/// read Monday) as a tracked V1 simplification rather than hiding it.
/// This pass adds `PrescriptionTemplate.autoregulationReferenceSlot` — a
/// second, purely additive, optional cross-slot reference, `nil` for
/// every row except this one, read only by
/// `AutoregulationRatingResolver.rating(for:in:)` as a fallback-preferred
/// override of `pairedSlot` — so the backoff row's load and its
/// autoregulation rating now correctly resolve from Monday and Wednesday
/// respectively, exactly as the executable source formulas show. See
/// `POWERLIFTING_SOURCE_AUTHORITY_REPAIR_V1.md` §12 for the full writeup.
///
/// **Deferred, per this checkpoint's own explicit instruction:** the
/// source's RM self-calibration adjustment guidance (bump the weight if
/// first-week reps fall outside a target band) and any peaking-phase
/// content are NOT modeled here — both remain FOLLOW-UP/V2, not
/// implemented, not blocking.
///
/// **Still flagged, not invented:** neither family's deload documentation
/// mentions set count at all (only weight and reps) — `deloadSetCount`
/// is left at its default (`2`, Family A's confirmed number) for both
/// families, without independent source confirmation. Family C's
/// standard-row rep-goal schedule for non-deload weeks is *also*
/// unconfirmed anywhere in the surviving material — the flat RIR-8
/// value used below remains a representative placeholder, not a sourced
/// fixture, exactly as before this pass.
enum PowerliftingProgramGenerator {
    static let currentVersion = 1

    /// Identical across every family — `PROGRAM_FAMILY_MATRIX.md`'s
    /// cross-family proof table.
    static let laterWeekMultipliers: [Double] = [1.05, 1.075, 1.1]

    @discardableResult
    static func generate(
        configuration: PowerliftingProgramConfiguration,
        provenance: ProgramProvenance,
        context: ModelContext
    ) -> ProgramDefinition {
        let definition = ProgramDefinition(
            name: "\(configuration.dayCount)-Day Powerlifting \(familyDisplayName(configuration.family))",
            lengthWeeks: 5,
            intent: "RP Powerlifting \(familyDisplayName(configuration.family)), \(configuration.dayCount)-day",
            programmingSystem: .powerlifting,
            generatorVersion: currentVersion,
            provenance: provenance,
            powerliftingConfiguration: configuration
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

        switch configuration.family {
        case .b: generateFamilyB(definition: definition, context: context)
        case .c: generateFamilyC(definition: definition, context: context)
        }

        return definition
    }

    // MARK: - Family B: complete 15-row/4-day structure, re-verified
    // directly against `RP-PowerliftingStr-4-Day.xlsx` this pass.
    //
    // Monday: Deadlift, Legs1, Push1 (Triples), Hamstring.
    // Tuesday: Legs2, Push2, UpperPull1, Shoulder1.
    // Thursday: Deadlift (Triples, frozen wk4), UpperPull2, Shoulder2.
    // Friday: Push1 (ordinary, frozen wk4), Legs2 (frozen wk4), UpperPull1,
    // Shoulder1.
    //
    // Every category's RM cell is shared correctly across its repeated
    // day(s) — e.g. Monday-Deadlift and Thursday-Deadlift both read the
    // same calibrated Deadlift RM at different factors/protocols; the two
    // Push1 instances (Monday-Triples, Friday-ordinary) likewise share one
    // RM. `ExerciseSlot` identity is per-category (one slot per named
    // category, reused across its repeated days) so the calibration and
    // exercise-selection experience matches the real source's own
    // category-not-day-scoped selection sheet.

    private static func generateFamilyB(definition: ProgramDefinition, context: ModelContext) {
        // Stage 10R.1D correction: "N/fail" is an RIR/effort target, not a
        // fixed rep count.
        let ordinaryRepGoal: [RepGoal] = [.rir(2), .rir(2), .rir(2), .rir(1)]
        // "Triples sessions never change" (`FAMILY_B_REP_GOAL`) — a
        // genuine fixed rep count, flat, not stepping, and never phrased
        // as "N/fail" in the source.
        let triplesRepGoal: [RepGoal] = Array(repeating: .fixedReps(3), count: 4)
        // 8RM accessory rows never autoregulate at all
        // (`FAMILY_B_AUTOREGULATION`) — a fixed, source-confirmed
        // (2,2,3,3) schedule for every one of them.
        let fixedAccessorySets: [Int] = [2, 2, 3, 3]
        let deloadWeightSplit = DeloadPositionOverride(boundaryDayIndex: 2, fullPositionFactor: 0.7, halfPositionFactor: 0.5)
        let deloadRepSplit = DeloadPositionOverride(boundaryDayIndex: 2, fullPositionFactor: 2.0 / 3.0, halfPositionFactor: 0.5)

        // Category -> targets, for a fresh `ExerciseSlot` per row. NOTE:
        // `ExerciseSlot.prescriptionTemplate` is a one-to-one cascade
        // inverse (`PrescriptionTemplate.swift`) — a single `ExerciseSlot`
        // instance CANNOT be shared across two `PrescriptionTemplate`
        // rows (a second attach silently steals the inverse from the
        // first, confirmed empirically this pass by a failing round-trip
        // test before this fix). Each of a category's repeated-day rows
        // therefore gets its OWN `ExerciseSlot`, named identically — the
        // real exercise-level identity (and therefore calibration
        // sharing) comes from `SubstituteExerciseUseCase` resolving the
        // same selection across same-named slots, never from sharing one
        // `ExerciseSlot` object.
        let categoryTargets: [String: [MuscleGroup]] = [
            "Legs Move 1": [.quadriceps, .glutes], "Legs Move 2": [.quadriceps, .glutes],
            "Pushing Move 1": [.chest, .triceps], "Pushing Move 2": [.chest, .triceps],
            "Deadlift Move": [.back, .hamstrings], "Hamstring Move": [.hamstrings, .back],
            "Upper Body Pulling Move 1": [.back, .biceps], "Upper Body Pulling Move 2": [.back, .biceps],
            "Shoulder Move 1": [.shoulders, .lateralDelt], "Shoulder Move 2": [.shoulders, .lateralDelt],
        ]

        var blocksByDay: [String: WorkoutBlockTemplate] = [:]
        func dayBlock(_ dayName: String) -> WorkoutBlockTemplate {
            if let existing = blocksByDay[dayName] { return existing }
            let session = TemplateSession(name: dayName, role: .strength)
            context.insert(session)
            definition.addTemplateSession(session)
            let block = WorkoutBlockTemplate(type: .strength)
            context.insert(block)
            session.addBlockTemplate(block)
            blocksByDay[dayName] = block
            return block
        }

        @discardableResult
        func addRow(
            day: String, category: String, rmType: RMType, weekOneFactor: Double,
            repGoal: [RepGoal], setCount: SetCountRule
        ) -> PrescriptionTemplate {
            let block = dayBlock(day)
            let template = PrescriptionTemplate(rules: StrengthProgressionRules(
                loadRule: .rmBased(RMBasedLoad(rmType: rmType, weekOneFactor: weekOneFactor, laterWeekMultipliers: laterWeekMultipliers)),
                setCountRule: setCount,
                repGoalSchedule: repGoal,
                deloadRepPositionOverride: deloadRepSplit,
                deloadWeightPositionOverride: deloadWeightSplit
            ))
            context.insert(template)
            let slot = ExerciseSlot(name: category, allowedTargets: categoryTargets[category] ?? [])
            context.insert(slot)
            template.attachExerciseSlot(slot)
            block.addPrescriptionTemplate(template)
            return template
        }

        // Pass 1: create every row (real Week-1 baseline sets per
        // `RP-PowerliftingStr-4-Day.xlsx`, confirmed this pass).
        let monDeadlift = addRow(day: "Monday", category: "Deadlift Move", rmType: .rm5, weekOneFactor: 0.95, repGoal: ordinaryRepGoal,
            setCount: .autoregulated(AutoregulatedSetCount(baselineSets: 2, applyRatingOnFinalWeek: true)))
        let monLegs1 = addRow(day: "Monday", category: "Legs Move 1", rmType: .rm5, weekOneFactor: 0.95, repGoal: ordinaryRepGoal,
            setCount: .autoregulated(AutoregulatedSetCount(baselineSets: 2, applyRatingOnFinalWeek: true)))
        let monPush1Triples = addRow(day: "Monday", category: "Pushing Move 1", rmType: .rm5, weekOneFactor: 0.7, repGoal: triplesRepGoal,
            setCount: .autoregulated(AutoregulatedSetCount(baselineSets: 2, applyRatingOnFinalWeek: true)))
        addRow(day: "Monday", category: "Hamstring Move", rmType: .rm8, weekOneFactor: 0.95, repGoal: ordinaryRepGoal, setCount: .fixed(setsByWeek: fixedAccessorySets))

        let tueLegs2 = addRow(day: "Tuesday", category: "Legs Move 2", rmType: .rm5, weekOneFactor: 0.95, repGoal: ordinaryRepGoal,
            setCount: .autoregulated(AutoregulatedSetCount(baselineSets: 5, applyRatingOnFinalWeek: true)))
        let tuePush2 = addRow(day: "Tuesday", category: "Pushing Move 2", rmType: .rm5, weekOneFactor: 0.95, repGoal: ordinaryRepGoal,
            setCount: .autoregulated(AutoregulatedSetCount(baselineSets: 3, applyRatingOnFinalWeek: true)))
        addRow(day: "Tuesday", category: "Upper Body Pulling Move 1", rmType: .rm8, weekOneFactor: 0.95, repGoal: ordinaryRepGoal, setCount: .fixed(setsByWeek: fixedAccessorySets))
        addRow(day: "Tuesday", category: "Shoulder Move 1", rmType: .rm8, weekOneFactor: 0.95, repGoal: ordinaryRepGoal, setCount: .fixed(setsByWeek: fixedAccessorySets))

        let thuDeadliftTriples = addRow(day: "Thursday", category: "Deadlift Move", rmType: .rm5, weekOneFactor: 0.7, repGoal: triplesRepGoal,
            setCount: .autoregulated(AutoregulatedSetCount(baselineSets: 2, applyRatingOnFinalWeek: false)))
        addRow(day: "Thursday", category: "Upper Body Pulling Move 2", rmType: .rm8, weekOneFactor: 0.95, repGoal: ordinaryRepGoal, setCount: .fixed(setsByWeek: fixedAccessorySets))
        addRow(day: "Thursday", category: "Shoulder Move 2", rmType: .rm8, weekOneFactor: 0.95, repGoal: ordinaryRepGoal, setCount: .fixed(setsByWeek: fixedAccessorySets))

        let friPush1 = addRow(day: "Friday", category: "Pushing Move 1", rmType: .rm5, weekOneFactor: 0.95, repGoal: ordinaryRepGoal,
            setCount: .autoregulated(AutoregulatedSetCount(baselineSets: 3, applyRatingOnFinalWeek: false)))
        let friLegs2 = addRow(day: "Friday", category: "Legs Move 2", rmType: .rm5, weekOneFactor: 0.95, repGoal: ordinaryRepGoal,
            setCount: .autoregulated(AutoregulatedSetCount(baselineSets: 2, applyRatingOnFinalWeek: false)))
        addRow(day: "Friday", category: "Upper Body Pulling Move 1", rmType: .rm8, weekOneFactor: 0.95, repGoal: ordinaryRepGoal, setCount: .fixed(setsByWeek: fixedAccessorySets))
        addRow(day: "Friday", category: "Shoulder Move 1", rmType: .rm8, weekOneFactor: 0.95, repGoal: ordinaryRepGoal, setCount: .fixed(setsByWeek: fixedAccessorySets))

        // Pass 2: wire the cross-day autoregulation graph — re-verified
        // directly against the live workbook's own formulas this pass.
        // `pairedSlot` supplies BOTH the rating source AND, where the load
        // rule is `.linkedToPairedSlot`, the load source; every row below
        // uses `.rmBased` for load, so `pairedSlot` here is rating-only.
        monDeadlift.pairedSlot = thuDeadliftTriples   // G5  = B5+(F25)
        thuDeadliftTriples.pairedSlot = monDeadlift   // G25 = B25+(K5)
        monLegs1.pairedSlot = friLegs2                // G6  = B6+(F35)
        monPush1Triples.pairedSlot = friPush1         // G7  = B7+(F34)
        tueLegs2.pairedSlot = friLegs2                // G15 = B15+(F35)
        tuePush2.pairedSlot = friPush1                // G16 = B16+(F34)
        friPush1.pairedSlot = tuePush2                // G34 = B34+(K16)
        friLegs2.pairedSlot = tueLegs2                 // G35 = B35+(K15)
    }

    // MARK: - Family C: complete 16-row/5-day structure, re-verified
    // directly against `RP-PowerliftingHyp-5-Day.xlsx` this pass.
    //
    // Monday: Push1, Legs1, UpperPull1.
    // Tuesday: Legs1, Deadlift, Shoulder1.
    // Wednesday: Push2, UpperPull1, Shoulder1.
    // Thursday: Deadlift, Hamstring, Shoulder2 (all frozen wk4).
    // Friday: Legs2, Push1-backoff, UpperPull2, Shoulder2 (all frozen wk4).
    //
    // TWO DIFFERENT day-groupings exist for two DIFFERENT mechanics — kept
    // deliberately distinct, never conflated: the AUTOREGULATION freeze
    // boundary is Mon/Tue/Wed-continue vs. Thu/Fri-freeze; the DELOAD
    // WEIGHT boundary is Mon/Tue-unchanged vs. Wed/Thu/Fri-halved (a
    // different cutoff — Wednesday freezes with Mon/Tue for
    // autoregulation but halves with Thu/Fri for deload weight,
    // confirmed directly from the workbook's own Wednesday deload
    // formula `=MROUND(D×0.5,5)`).

    private static func generateFamilyC(definition: ProgramDefinition, context: ModelContext) {
        // Placeholder, unconfirmed in source (see this file's own doc
        // comment) — Family C's non-deload rep-per-week schedule is not
        // documented anywhere in the surviving material. Stage 10R.1D
        // mechanically migrates this placeholder's shape from a fabricated
        // fixed-rep count to the corresponding RIR reading ("N/fail" ->
        // `.rir(N)`) — this does NOT resolve or newly confirm the
        // placeholder's content; it remains exactly as unconfirmed as
        // before.
        let standardRepGoal: [RepGoal] = Array(repeating: .rir(8), count: 4)
        // Autoregulation-freeze deload weight split (Mon/Tue unchanged,
        // Wed/Thu/Fri halved) — genuinely different day boundary from the
        // freeze boundary above; `boundaryDayIndex: 2` here means
        // "after the 2nd day" (Monday=0, Tuesday=1), matching Wed/Thu/Fri
        // all falling on the halved side.
        let deloadWeightSplit = DeloadPositionOverride(boundaryDayIndex: 2, fullPositionFactor: 1.0, halfPositionFactor: 0.5)
        // 8RM-equivalent accessory rows never autoregulate
        // (`FAMILY_C_AUTOREGULATION`: confirmed dead rating inputs) —
        // fixed (2,2,3,3) for every one, same shape as Family B's
        // accessories.
        let fixedAccessorySets: [Int] = [2, 2, 3, 3]

        // See Family B's identical note above: `ExerciseSlot` is a
        // one-to-one cascade inverse of `PrescriptionTemplate` and CANNOT
        // be shared across two rows — a fresh slot is created per row,
        // named by category.
        let categoryTargets: [String: [MuscleGroup]] = [
            "Legs Move 1": [.quadriceps, .glutes], "Legs Move 2": [.quadriceps, .glutes],
            "Pushing Move 1": [.chest, .triceps], "Pushing Move 2": [.chest, .triceps],
            "Deadlift Move": [.back, .hamstrings], "Hamstring Move": [.hamstrings, .back],
            "Upper Body Pulling Move 1": [.back, .biceps], "Upper Body Pulling Move 2": [.back, .biceps],
            "Shoulder Move 1": [.shoulders, .lateralDelt], "Shoulder Move 2": [.shoulders, .lateralDelt],
        ]

        var blocksByDay: [String: WorkoutBlockTemplate] = [:]
        func dayBlock(_ dayName: String) -> WorkoutBlockTemplate {
            if let existing = blocksByDay[dayName] { return existing }
            let session = TemplateSession(name: dayName, role: .strength)
            context.insert(session)
            definition.addTemplateSession(session)
            let block = WorkoutBlockTemplate(type: .strength)
            context.insert(block)
            session.addBlockTemplate(block)
            blocksByDay[dayName] = block
            return block
        }

        @discardableResult
        func addRow(day: String, category: String, weekOneFactor: Double, setCount: SetCountRule, deloadRepFraction: Double = 0.5) -> PrescriptionTemplate {
            let block = dayBlock(day)
            let template = PrescriptionTemplate(rules: StrengthProgressionRules(
                loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: weekOneFactor, laterWeekMultipliers: laterWeekMultipliers)),
                setCountRule: setCount,
                repGoalSchedule: standardRepGoal,
                deloadRepFraction: deloadRepFraction,
                deloadWeightPositionOverride: deloadWeightSplit
            ))
            context.insert(template)
            let slot = ExerciseSlot(name: category, allowedTargets: categoryTargets[category] ?? [])
            context.insert(slot)
            template.attachExerciseSlot(slot)
            block.addPrescriptionTemplate(template)
            return template
        }

        // Pass 1: create every row (real Week-1 baseline sets per
        // `RP-PowerliftingHyp-5-Day.xlsx`, confirmed this pass).
        let monPush1 = addRow(day: "Monday", category: "Pushing Move 1", weekOneFactor: 0.95,
            setCount: .autoregulated(AutoregulatedSetCount(baselineSets: 3)))
        let monLegs1 = addRow(day: "Monday", category: "Legs Move 1", weekOneFactor: 0.95,
            setCount: .autoregulated(AutoregulatedSetCount(baselineSets: 2)))
        addRow(day: "Monday", category: "Upper Body Pulling Move 1", weekOneFactor: 0.95, setCount: .fixed(setsByWeek: fixedAccessorySets))

        let tueLegs1 = addRow(day: "Tuesday", category: "Legs Move 1", weekOneFactor: 0.95,
            setCount: .autoregulated(AutoregulatedSetCount(baselineSets: 5)))
        let tueDeadlift = addRow(day: "Tuesday", category: "Deadlift Move", weekOneFactor: 0.95,
            setCount: .autoregulated(AutoregulatedSetCount(baselineSets: 2)))
        addRow(day: "Tuesday", category: "Shoulder Move 1", weekOneFactor: 0.95, setCount: .fixed(setsByWeek: fixedAccessorySets))

        let wedPush2 = addRow(day: "Wednesday", category: "Pushing Move 2", weekOneFactor: 0.95,
            setCount: .autoregulated(AutoregulatedSetCount(baselineSets: 5)))
        addRow(day: "Wednesday", category: "Upper Body Pulling Move 1", weekOneFactor: 0.95, setCount: .fixed(setsByWeek: fixedAccessorySets))
        addRow(day: "Wednesday", category: "Shoulder Move 1", weekOneFactor: 0.95, setCount: .fixed(setsByWeek: fixedAccessorySets))

        let thuDeadlift = addRow(day: "Thursday", category: "Deadlift Move", weekOneFactor: 0.95,
            setCount: .autoregulated(AutoregulatedSetCount(baselineSets: 3, freezeAfterWeek: 2)))
        // "Hamstring's own rating is never used; its autoregulation is a
        // verbatim copy of Deadlift's" — confirmed directly: shares
        // Tuesday-Deadlift as its rating source, not its own row.
        let thuHamstring = addRow(day: "Thursday", category: "Hamstring Move", weekOneFactor: 0.95,
            setCount: .autoregulated(AutoregulatedSetCount(baselineSets: 2, freezeAfterWeek: 2)))
        addRow(day: "Thursday", category: "Shoulder Move 2", weekOneFactor: 0.95, setCount: .fixed(setsByWeek: fixedAccessorySets))

        let friLegs2 = addRow(day: "Friday", category: "Legs Move 2", weekOneFactor: 0.95,
            setCount: .autoregulated(AutoregulatedSetCount(baselineSets: 3, freezeAfterWeek: 2)))
        addRow(day: "Friday", category: "Upper Body Pulling Move 2", weekOneFactor: 0.95, setCount: .fixed(setsByWeek: fixedAccessorySets))
        addRow(day: "Friday", category: "Shoulder Move 2", weekOneFactor: 0.95, setCount: .fixed(setsByWeek: fixedAccessorySets))

        // Friday backoff: "a deliberate lighter backoff of the *same*
        // Monday exercise" (`FAMILY_C_WEEK1_BASELINE`) — load is
        // `.linkedToPairedSlot` to Monday-Push1, exactly as the live
        // workbook's own formula pairs it (`D42` reads Monday's RM cell,
        // not Wednesday's — this is the source authoring inconsistency:
        // the sheet's own footnote says "1/2 Thursday's" but the
        // executable formula and rep-goal cells both literally read
        // "1/2 Monday's"; the formula is executable source truth and
        // wins — see `POWERLIFTING_SOURCE_AUTHORITY_REPAIR_V1.md` §10, do
        // NOT "correct" this to Thursday. This is a SEPARATE fact from the
        // dual-reference fix below — do not conflate the two).
        //
        // DUAL-REFERENCE FIX (this pass): the real set-count autoregulation
        // rating for this row sources from Wednesday-Push2
        // (`H42: =C42+(L23)`), a DIFFERENT slot than the Monday-Push1 slot
        // the load pairs to. `pairedSlot` stays wired to Monday (load, and
        // the resolver's fallback target); `autoregulationReferenceSlot`
        // is now wired explicitly to Wednesday, so
        // `AutoregulationRatingResolver` resolves this row's rating from
        // Wednesday-Push2 exactly as the executable source shows — no
        // longer a disclosed simplification.
        let backoffFraction = 0.85 / 0.95
        let backoffTemplate = PrescriptionTemplate(rules: StrengthProgressionRules(
            loadRule: .linkedToPairedSlot(fractionOfSourceResult: backoffFraction),
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 2, freezeAfterWeek: 2)),
            repGoalSchedule: standardRepGoal,
            // The sole exception (`FAMILY_C_DELOAD`): "Same reps as Week
            // 1" — no reduction. Deload weight still halves like every
            // other Wed-Fri row (the source's exception is reps-only),
            // so the weight-side override is unchanged.
            deloadRepFraction: 1.0,
            deloadWeightPositionOverride: deloadWeightSplit
        ))
        context.insert(backoffTemplate)
        backoffTemplate.pairedSlot = monPush1
        // Dual-reference fix: the autoregulation rating for this row
        // comes from Wednesday-Push2, not Monday — see this function's
        // own comment above and `H42: =C42+(L23)` in the live workbook.
        backoffTemplate.autoregulationReferenceSlot = wedPush2
        let backoffSlot = ExerciseSlot(name: "Pushing Move 1 (Friday Backoff)", allowedTargets: [.chest, .triceps])
        context.insert(backoffSlot)
        backoffTemplate.attachExerciseSlot(backoffSlot)
        dayBlock("Friday").addPrescriptionTemplate(backoffTemplate)

        // Pass 2: wire the cross-day autoregulation graph — re-verified
        // directly against the live workbook's own formulas this pass.
        monPush1.pairedSlot = wedPush2       // H5  = C5+(G23)
        monLegs1.pairedSlot = friLegs2        // H6  = C6+(G41)
        tueLegs1.pairedSlot = friLegs2         // H14 = C14+(G41)
        tueDeadlift.pairedSlot = thuDeadlift   // H15 = C15+(G32)
        wedPush2.pairedSlot = monPush1         // H23 = C23+(L5)
        thuDeadlift.pairedSlot = tueDeadlift   // H32 = C32+(L15)
        thuHamstring.pairedSlot = tueDeadlift  // H33 = C33+(L15) — copy of Deadlift's, not its own
        friLegs2.pairedSlot = tueLegs1         // H41 = C41+(L14) — NOT Monday-Legs1
    }

    private static func familyDisplayName(_ family: PowerliftingFamily) -> String {
        switch family {
        case .b: return "Strength"
        case .c: return "Hypertrophy-block"
        }
    }
}
