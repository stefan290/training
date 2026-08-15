import Foundation
import SwiftData

/// Builds and persists a `SteadyStatePrescriptionTemplate`-based template
/// graph from a `SteadyStateProgramConfiguration` — one generator for
/// every aerobic modality (Stage 4C §1). Nothing here branches on
/// `ActivityType`; `configuration.activityType` is only ever threaded
/// through to `SteadyStatePrescriptionTemplate.preferredActivityType`, and
/// every day uses the identical rule-selection logic below regardless of
/// which activity it names.
///
/// **Scope, stated plainly (same discipline as
/// `HypertrophyProgramGenerator`/`PowerliftingProgramGenerator`):** this
/// proves the rule-engine mechanics — one selectable progression
/// dimension, a trailing recovery week, activity-substitution
/// eligibility — with one representative steady-state block per day. It
/// does not claim a curated, realistic V1 built-in library (no
/// `V1_PROGRAM_LIBRARY.md` entry names a steady-state configuration the
/// way Hypertrophy/Powerlifting's built-ins are named); building one is a
/// reasonable follow-up, not attempted here since Stage 4C's own kickoff
/// names no specific curated configuration to build.
///
/// **Every numeric default below is explicitly TRAININGOS_DESIGNED**
/// (`ProgramProvenance.constructed`), never presented as sourced: Stage 3B
/// already found real retrieval limitations verifying British Cycling/NHS/
/// research-literature protocols, and Stage 4C's own instruction is to
/// implement the generic capability with clearly-labeled TrainingOS-
/// designed test configurations rather than convert an unverified search
/// snippet into production methodology. Frequency progression is
/// deliberately **not** attempted by this generator at all — no source
/// material specifies *when* a program should add a session, and
/// inventing a specific week is exactly the "ambiguous training rule"
/// CLAUDE.md rule 10 rules out; the capability is proven directly at the
/// `TemplateSession.activeFromWeek`/materializer level instead
/// (`SteadyStateFrequencyProgressionTests`), not fabricated into a
/// built-in's numbers.
enum SteadyStateProgramGenerator {
    static let currentVersion = 1

    @discardableResult
    static func generate(
        configuration: SteadyStateProgramConfiguration,
        provenance: ProgramProvenance,
        context: ModelContext
    ) -> ProgramDefinition {
        let definition = ProgramDefinition(
            name: "\(configuration.daysPerWeek)-Day \(activityDisplayName(configuration.activityType)) (\(configuration.progressionDimension.rawValue) progression)",
            lengthWeeks: configuration.lengthWeeks + 1,
            intent: "Steady-state \(configuration.activityType.rawValue), \(configuration.progressionDimension.rawValue) progression",
            programmingSystem: .steadyState,
            generatorVersion: currentVersion,
            provenance: provenance,
            steadyStateConfiguration: configuration
        )
        context.insert(definition)

        for _ in 0..<configuration.lengthWeeks {
            let week = TrainingWeek(isDeload: false)
            context.insert(week)
            definition.addWeek(week)
        }
        // The trailing recovery week — reusing `TrainingWeek.isDeload`
        // exactly as Family A/B/C already do, not a new flag. Every
        // generated program supports recovery-week reduction (Stage 4C
        // §9); whether a given day's numbers actually reduce depends on
        // its `SteadyStateProgressionRules.recoveryWeek*` fields, which
        // this generator sets to a non-1.0/non-zero TrainingOS-designed
        // default for every dimension below.
        let recoveryWeek = TrainingWeek(isDeload: true)
        context.insert(recoveryWeek)
        definition.addWeek(recoveryWeek)

        let rules = progressionRules(for: configuration.progressionDimension, weekCount: configuration.lengthWeeks)
        // A `.intensityZone`-progressing day's intensity comes entirely
        // from `intensityZoneProgression`; every other dimension carries a
        // static Zone 2 target for the whole block (the common case this
        // pass's own required test fixtures — Zone 2 Bike/Run/Row/SkiErg,
        // 45 minutes — exercise directly).
        let staticIntensity: IntensityTarget? = configuration.progressionDimension == .intensityZone ? nil : .heartRateZone(.two)

        for dayIndex in 0..<configuration.daysPerWeek {
            let session = TemplateSession(name: "Day \(dayIndex + 1)", role: .aerobicBase)
            context.insert(session)
            definition.addTemplateSession(session)

            let block = WorkoutBlockTemplate(type: .steadyState)
            context.insert(block)
            session.addBlockTemplate(block)

            let template = SteadyStatePrescriptionTemplate(
                preferredActivityType: configuration.activityType,
                allowedActivityTypes: configuration.allowedActivityTypes,
                primaryIntensity: staticIntensity,
                progressionRules: rules
            )
            context.insert(template)
            block.attachSteadyStatePrescriptionTemplate(template)
        }

        return definition
    }

    /// TRAININGOS_DESIGNED defaults per dimension — see this file's own
    /// doc comment. `weekCount` excludes the trailing recovery week
    /// (`configuration.lengthWeeks`), so `laterWeek*` arrays have exactly
    /// `weekCount - 1` entries (weeks 2...weekCount).
    private static func progressionRules(for dimension: SteadyStateProgressionDimension, weekCount: Int) -> SteadyStateProgressionRules {
        switch dimension {
        case .duration:
            // Base 45 min, +5 min/week.
            let laterWeeks = (1..<max(weekCount, 1)).map { 2700 + $0 * 300 }
            return SteadyStateProgressionRules(
                progressionDimension: .duration,
                weekOneDurationSeconds: 2700,
                laterWeekDurationSeconds: laterWeeks,
                recoveryWeekDurationFraction: 0.7
            )
        case .distance:
            // Base 8 km, +1 km/week.
            let laterWeeks = (1..<max(weekCount, 1)).map { 8000 + Double($0) * 1000 }
            return SteadyStateProgressionRules(
                progressionDimension: .distance,
                weekOneDistanceMeters: 8000,
                laterWeekDistanceMeters: laterWeeks,
                recoveryWeekDistanceFraction: 0.7
            )
        case .intensityZone:
            return SteadyStateProgressionRules(
                progressionDimension: .intensityZone,
                weekOneDurationSeconds: 2700,
                intensityZoneProgression: IntensityZoneProgression(startZone: .two, stepPerWeek: 1, maxZone: .four),
                recoveryWeekIntensityZoneStepDown: 1
            )
        case .none:
            return SteadyStateProgressionRules(
                progressionDimension: .none,
                weekOneDurationSeconds: 2700,
                recoveryWeekDurationFraction: 0.7
            )
        }
    }

    private static func activityDisplayName(_ activityType: ActivityType) -> String {
        switch activityType {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .rowing: return "Rowing"
        case .skiErg: return "SkiErg"
        case .other: return "Other"
        }
    }
}
