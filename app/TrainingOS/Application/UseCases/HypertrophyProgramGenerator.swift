import Foundation
import SwiftData

/// Builds and persists a Family A hypertrophy `ProgramDefinition`'s
/// template graph from a `HypertrophyProgramConfiguration` — the
/// "Configuration = recipe -> Program Generator -> persisted Program
/// Template Graph" half of the Stage 4 architecture. Runs once per
/// definition; the generated graph is then treated as frozen (see
/// `ProgramDefinition.generatorVersion`'s doc comment).
///
/// **Scope, stated plainly:** this proves the *rule engine* mechanics —
/// day-count parameterization, the phase-specific week-1 load factors,
/// the confirmed Heavy exception, autoregulation, `linkedResultReference`,
/// and the deload-week marker — with **one representative primary +
/// paired-accessory slot pair per training day**. No source workbook
/// survives in this repository (confirmed by exhaustive search during
/// this pass's own research) to derive a complete, realistic per-day
/// exercise selection from for every day-count/split combination; that
/// content is flagged as a follow-up for whoever has access to the actual
/// Family A program content, not fabricated here with false confidence.
/// `STAGE4_IMPLEMENTATION_REPORT.md` restates this.
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
    /// superset partner"). Used for `.metaboliteFocus`; other phases pair
    /// the accessory via `linkedResultReference` instead (see
    /// `makeSlotPair`), since no other phase's superset-partner factor is
    /// documented in the surviving Stage 3 docs.
    static let metaboliteFocusPairedWeekOneFactor = 0.6

    /// Builds one complete template graph — `lengthWeeks` `TrainingWeek`
    /// markers (4 progressive + 1 deload) and one recurring weekly
    /// structure (`dayCount` `TemplateSession`s, one representative
    /// primary+paired slot pair each) — and inserts it into `context`.
    /// Does not resolve any `ExerciseSlot` to a concrete `Exercise`; see
    /// `ExerciseSlot`'s doc comment for when that happens.
    @discardableResult
    static func generate(
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
        let isHeavyLegsException = configuration.split == .legs && dayIndex == 0
        let weekOneFactor = isHeavyLegsException ? 1.0 : primaryWeekOneFactor(for: configuration.phaseType)

        let primary = PrescriptionTemplate(rules: StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: weekOneFactor, laterWeekMultipliers: laterWeekMultipliers)),
            setCountRule: .autoregulated(baselineSets: 3),
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
}
