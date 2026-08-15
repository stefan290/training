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
/// **Scope, stated plainly (same discipline as `HypertrophyProgramGenerator`):**
/// this proves the *rule engine* mechanics — the mixed 5RM/8RM basis, the
/// Triples protocol, the Week-4 asymmetry/freeze, the Friday backoff
/// reference, and the per-family deload day-position split — with **one
/// representative slot per training day**, not Family B's full 10-slot
/// (Legs×2/Push×2/Deadlift/Hamstring/UpperPull×2/Shoulder×2) or Family
/// C's full day-by-day layout. The exact category-to-day mapping beyond
/// what's explicitly cited (`PROGRAM_LOGIC_SPEC.md`'s "Monday Bench,"
/// "Thursday Deadlift," "Friday backoff") isn't available in the
/// surviving source material, so it is not fabricated here with false
/// confidence — flagged as a follow-up for whoever has access to the
/// actual Family B/C exercise-slot content, exactly as
/// `HypertrophyProgramGenerator`'s own equivalent note.
///
/// **Also flagged, not invented:** neither family's deload documentation
/// mentions set count at all (only weight and reps) — `deloadSetCount`
/// is left at its default (`2`, Family A's confirmed number) for both
/// families here, without independent source confirmation; see
/// `StrengthProgressionRules.deloadSetCount`'s doc comment and
/// `STAGE4_IMPLEMENTATION_REPORT.md`'s Stage 4B section. Family C's
/// standard-row rep-goal schedule for non-deload weeks is *also*
/// unconfirmed — `PROGRAM_LOGIC_SPEC.md` §4 documents Family C's load,
/// autoregulation and deload rules but never states a rep-per-week
/// schedule the way Family A/B's docs do; the flat 8-reps-every-week
/// value used below is a representative placeholder, not a sourced
/// fixture.
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

    // MARK: - Family B: Monday Bench (Triples), Tuesday Squat (ordinary),
    // Thursday Deadlift (Triples, Week-4 asymmetry), Friday accessory
    // (8RM, fixed schedule).

    private static func generateFamilyB(definition: ProgramDefinition, context: ModelContext) {
        let ordinaryRepGoal: [RepGoal] = [
            RepGoal(reps: 2, toFailure: true), RepGoal(reps: 2, toFailure: true),
            RepGoal(reps: 2, toFailure: true), RepGoal(reps: 1, toFailure: true)
        ]
        // "Triples sessions never change" (`FAMILY_B_REP_GOAL`) — flat,
        // not stepping, and not phrased as "to failure."
        let triplesRepGoal: [RepGoal] = Array(repeating: RepGoal(reps: 3, toFailure: false), count: 4)
        let deloadWeightSplit = DeloadPositionOverride(boundaryDayIndex: 2, fullPositionFactor: 0.7, halfPositionFactor: 0.5)
        let deloadRepSplit = DeloadPositionOverride(boundaryDayIndex: 2, fullPositionFactor: 2.0 / 3.0, halfPositionFactor: 0.5)

        func addCentralLift(
            dayName: String, slotName: String, targets: [MuscleGroup],
            weekOneFactor: Double, repGoal: [RepGoal], applyRatingOnFinalWeek: Bool
        ) {
            let session = TemplateSession(name: dayName, role: .strength)
            context.insert(session)
            definition.addTemplateSession(session)
            let block = WorkoutBlockTemplate(type: .strength)
            context.insert(block)
            session.addBlockTemplate(block)

            let template = PrescriptionTemplate(rules: StrengthProgressionRules(
                loadRule: .rmBased(RMBasedLoad(rmType: .rm5, weekOneFactor: weekOneFactor, laterWeekMultipliers: laterWeekMultipliers)),
                setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 3, applyRatingOnFinalWeek: applyRatingOnFinalWeek)),
                repGoalSchedule: repGoal,
                deloadRepPositionOverride: deloadRepSplit,
                deloadWeightPositionOverride: deloadWeightSplit
            ))
            context.insert(template)
            let slot = ExerciseSlot(name: slotName, allowedTargets: targets)
            context.insert(slot)
            template.attachExerciseSlot(slot)
            block.addPrescriptionTemplate(template)
        }

        addCentralLift(dayName: "Monday", slotName: "Bench (Triples)", targets: [.chest, .triceps], weekOneFactor: 0.7, repGoal: triplesRepGoal, applyRatingOnFinalWeek: true)
        addCentralLift(dayName: "Tuesday", slotName: "Squat", targets: [.quadriceps, .glutes], weekOneFactor: 0.95, repGoal: ordinaryRepGoal, applyRatingOnFinalWeek: true)
        addCentralLift(dayName: "Thursday", slotName: "Deadlift (Triples)", targets: [.back, .hamstrings], weekOneFactor: 0.7, repGoal: triplesRepGoal, applyRatingOnFinalWeek: false)

        // Friday: 8RM accessory row — fixed, never-autoregulated schedule
        // (`FAMILY_B_AUTOREGULATION`).
        let fridaySession = TemplateSession(name: "Friday", role: .strength)
        context.insert(fridaySession)
        definition.addTemplateSession(fridaySession)
        let fridayBlock = WorkoutBlockTemplate(type: .strength)
        context.insert(fridayBlock)
        fridaySession.addBlockTemplate(fridayBlock)

        let accessoryTemplate = PrescriptionTemplate(rules: StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm8, weekOneFactor: 0.95, laterWeekMultipliers: laterWeekMultipliers)),
            setCountRule: .fixed(setsByWeek: [2, 2, 3, 3]),
            repGoalSchedule: ordinaryRepGoal,
            deloadRepPositionOverride: deloadRepSplit,
            deloadWeightPositionOverride: deloadWeightSplit
        ))
        context.insert(accessoryTemplate)
        let accessorySlot = ExerciseSlot(name: "Upper-Pull", allowedTargets: [.back, .biceps])
        context.insert(accessorySlot)
        accessoryTemplate.attachExerciseSlot(accessorySlot)
        fridayBlock.addPrescriptionTemplate(accessoryTemplate)
    }

    // MARK: - Family C: Monday/Tuesday/Wednesday autoregulate through
    // Week 4; Thursday/Friday freeze after Week 3; Friday also carries
    // the backoff exercise (`linkedToPairedSlot` -> Monday).

    private static func generateFamilyC(definition: ProgramDefinition, context: ModelContext) {
        // Placeholder, unconfirmed in source (see this file's own doc
        // comment) — Family C's non-deload rep-per-week schedule is not
        // documented anywhere in the surviving material.
        let standardRepGoal: [RepGoal] = Array(repeating: RepGoal(reps: 8, toFailure: true), count: 4)
        let deloadWeightSplit = DeloadPositionOverride(boundaryDayIndex: 2, fullPositionFactor: 1.0, halfPositionFactor: 0.5)

        @discardableResult
        func addStandardRow(dayName: String, slotName: String, targets: [MuscleGroup], freezeAfterWeek: Int?) -> PrescriptionTemplate {
            let session = TemplateSession(name: dayName, role: .strength)
            context.insert(session)
            definition.addTemplateSession(session)
            let block = WorkoutBlockTemplate(type: .strength)
            context.insert(block)
            session.addBlockTemplate(block)

            let template = PrescriptionTemplate(rules: StrengthProgressionRules(
                loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.95, laterWeekMultipliers: laterWeekMultipliers)),
                setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 3, freezeAfterWeek: freezeAfterWeek)),
                repGoalSchedule: standardRepGoal,
                deloadWeightPositionOverride: deloadWeightSplit
            ))
            context.insert(template)
            let slot = ExerciseSlot(name: slotName, allowedTargets: targets)
            context.insert(slot)
            template.attachExerciseSlot(slot)
            block.addPrescriptionTemplate(template)
            return template
        }

        let mondaySquat = addStandardRow(dayName: "Monday", slotName: "Squat", targets: [.quadriceps, .glutes], freezeAfterWeek: nil)
        addStandardRow(dayName: "Tuesday", slotName: "Bench", targets: [.chest, .triceps], freezeAfterWeek: nil)
        addStandardRow(dayName: "Wednesday", slotName: "Row", targets: [.back, .biceps], freezeAfterWeek: nil)
        addStandardRow(dayName: "Thursday", slotName: "Deadlift", targets: [.back, .hamstrings], freezeAfterWeek: 2)

        // Friday: the standard row (frozen after week 3, like Thursday)
        // plus the backoff exercise, structurally paired to Monday.
        let fridaySession = TemplateSession(name: "Friday", role: .strength)
        context.insert(fridaySession)
        definition.addTemplateSession(fridaySession)
        let fridayBlock = WorkoutBlockTemplate(type: .strength)
        context.insert(fridayBlock)
        fridaySession.addBlockTemplate(fridayBlock)

        let fridayPrimaryTemplate = PrescriptionTemplate(rules: StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.95, laterWeekMultipliers: laterWeekMultipliers)),
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 3, freezeAfterWeek: 2)),
            repGoalSchedule: standardRepGoal,
            deloadWeightPositionOverride: deloadWeightSplit
        ))
        context.insert(fridayPrimaryTemplate)
        let fridayPrimarySlot = ExerciseSlot(name: "Overhead Press", allowedTargets: [.shoulders, .triceps])
        context.insert(fridayPrimarySlot)
        fridayPrimaryTemplate.attachExerciseSlot(fridayPrimarySlot)
        fridayBlock.addPrescriptionTemplate(fridayPrimaryTemplate)

        // "A deliberate lighter backoff of the *same* Monday exercise"
        // (`FAMILY_C_WEEK1_BASELINE`) — modeled as `linkedToPairedSlot`,
        // pairing structurally to Monday's already-created slot.
        let backoffFraction = 0.85 / 0.95
        let backoffTemplate = PrescriptionTemplate(rules: StrengthProgressionRules(
            loadRule: .linkedToPairedSlot(fractionOfSourceResult: backoffFraction),
            setCountRule: .fixed(setsByWeek: [2, 2, 2, 2]),
            repGoalSchedule: standardRepGoal,
            // The sole exception (`FAMILY_C_DELOAD`): "Same reps as Week
            // 1" — no reduction. Deload weight still halves like every
            // other Wed-Fri row (the source's exception is reps-only),
            // so the weight-side override is unchanged.
            deloadRepFraction: 1.0,
            deloadWeightPositionOverride: deloadWeightSplit
        ))
        context.insert(backoffTemplate)
        backoffTemplate.pairedSlot = mondaySquat
        let backoffSlot = ExerciseSlot(name: "Squat Backoff", allowedTargets: [.quadriceps, .glutes])
        context.insert(backoffSlot)
        backoffTemplate.attachExerciseSlot(backoffSlot)
        fridayBlock.addPrescriptionTemplate(backoffTemplate)
    }

    private static func familyDisplayName(_ family: PowerliftingFamily) -> String {
        switch family {
        case .b: return "Strength"
        case .c: return "Hypertrophy-block"
        }
    }
}
