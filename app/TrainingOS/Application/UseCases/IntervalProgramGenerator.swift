import Foundation
import SwiftData

/// Builds and persists an `IntervalPrescriptionTemplate`-based template
/// graph from an `IntervalProgramConfiguration` — one generator for every
/// aerobic modality (Stage 4D §1). Nothing here branches on
/// `ActivityType`; `configuration.activityType` only ever flows through
/// to `IntervalPrescriptionTemplate.preferredActivityType`.
///
/// **Warm-up/cool-down use the existing ordered `WorkoutBlock`
/// architecture** (Stage 4D §7): `Session -> WarmUp Block -> Interval
/// Block -> CoolDown Block`, each an ordinary `WorkoutBlockTemplate` —
/// the warm-up/cool-down blocks are typed `.steadyState` (a plain, low-
/// intensity `SteadyStatePrescriptionTemplate`, reusing Stage 4C's type
/// rather than inventing a third "warm-up prescription" shape), never an
/// opaque field buried inside the interval block itself.
///
/// **Scope, stated plainly (same discipline as every other Stage 4
/// generator):** proves the rule-engine mechanics — one representative
/// interval block per day, a configurable work basis (duration or
/// distance), activity-substitution eligibility, and the full
/// progression-priority/completion-criteria plumbing — with
/// TRAININGOS_DESIGNED default numbers. It does not claim a curated V1
/// built-in library (no `V1_PROGRAM_LIBRARY.md` entry names one, exactly
/// as Stage 4C's `SteadyStateProgramGenerator` also found).
///
/// **No trailing recovery/taper week is fabricated** — unlike the
/// strength/steady-state generators, nothing in this stage's source
/// material or kickoff asks for an interval-specific taper week, and
/// inventing one would be exactly the "ambiguous training rule" CLAUDE.md
/// rule 10 rules out. A caller who wants a taper week can still append a
/// `TrainingWeek(isDeload: true)` manually; the generator itself just
/// doesn't assume one is wanted.
enum IntervalProgramGenerator {
    static let currentVersion = 1

    /// TRAININGOS_DESIGNED — see this file's own doc comment. 10 min
    /// easy warm-up, 5 min easy cool-down, both Zone 1.
    private static let warmUpDurationSeconds = 600
    private static let coolDownDurationSeconds = 300

    @discardableResult
    static func generate(
        configuration: IntervalProgramConfiguration,
        provenance: ProgramProvenance,
        context: ModelContext
    ) -> ProgramDefinition {
        let definition = ProgramDefinition(
            name: "\(configuration.daysPerWeek)-Day \(activityDisplayName(configuration.activityType)) Intervals (\(configuration.sessionRole.rawValue))",
            lengthWeeks: configuration.lengthWeeks,
            intent: "Interval \(configuration.activityType.rawValue), \(configuration.sessionRole.rawValue) purpose",
            programmingSystem: .interval,
            generatorVersion: currentVersion,
            provenance: provenance,
            intervalConfiguration: configuration
        )
        context.insert(definition)

        for _ in 0..<configuration.lengthWeeks {
            let week = TrainingWeek(isDeload: false)
            context.insert(week)
            definition.addWeek(week)
        }

        let rules = progressionRules(for: configuration.workBasis)

        for dayIndex in 0..<configuration.daysPerWeek {
            let session = TemplateSession(name: "Day \(dayIndex + 1)", role: configuration.sessionRole)
            context.insert(session)
            definition.addTemplateSession(session)

            if configuration.includeWarmUp {
                addStructureBlock(
                    to: session, type: .warmup, activityType: configuration.activityType,
                    durationSeconds: warmUpDurationSeconds, context: context
                )
            }

            let intervalBlock = WorkoutBlockTemplate(type: .intervals)
            context.insert(intervalBlock)
            session.addBlockTemplate(intervalBlock)

            let intervalTemplate = IntervalPrescriptionTemplate(
                preferredActivityType: configuration.activityType,
                allowedActivityTypes: configuration.allowedActivityTypes,
                workIntensity: workIntensity(for: configuration.workBasis),
                recoveryIntensity: .heartRateZone(.one),
                recoveryType: .active,
                progressionRules: rules
            )
            context.insert(intervalTemplate)
            intervalBlock.attachIntervalPrescriptionTemplate(intervalTemplate)

            if configuration.includeCoolDown {
                addStructureBlock(
                    to: session, type: .cooldown, activityType: configuration.activityType,
                    durationSeconds: coolDownDurationSeconds, context: context
                )
            }
        }

        return definition
    }

    private static func addStructureBlock(
        to session: TemplateSession, type: WorkoutBlockType, activityType: ActivityType,
        durationSeconds: Int, context: ModelContext
    ) {
        let block = WorkoutBlockTemplate(type: type)
        context.insert(block)
        session.addBlockTemplate(block)
        let steadyState = SteadyStatePrescriptionTemplate(
            preferredActivityType: activityType,
            primaryIntensity: .heartRateZone(.one),
            progressionRules: SteadyStateProgressionRules(progressionDimension: .none, weekOneDurationSeconds: durationSeconds)
        )
        context.insert(steadyState)
        block.attachSteadyStatePrescriptionTemplate(steadyState)
    }

    /// TRAININGOS_DESIGNED defaults per work basis — see this file's own
    /// doc comment. Duration basis: 4 intervals of 4 min (Helgerud-
    /// flavored shape, but with progression enabled — the verified
    /// Helgerud fixture itself, which the source study never progresses,
    /// is constructed directly in `IntervalRegressionTests`, not through
    /// this generator). Distance basis: 5 intervals of 1 km.
    private static func progressionRules(for workBasis: IntervalWorkBasis) -> IntervalProgressionRules {
        switch workBasis {
        case .duration:
            return IntervalProgressionRules(
                priority: [
                    IntervalProgressionStep(variable: .intervalCount, incrementPerWeek: 1, weeksToCeiling: 3),
                    IntervalProgressionStep(variable: .workDuration, incrementPerWeek: 60, weeksToCeiling: 4)
                ],
                weekOneIntervalCount: 4,
                weekOneWorkDurationSeconds: 240,
                weekOneRecoveryDurationSeconds: 180,
                recoveryDurationFloorSeconds: 120,
                completionCriteria: IntervalCompletionCriteria(maxRpeAllowed: 9)
            )
        case .distance:
            return IntervalProgressionRules(
                priority: [
                    IntervalProgressionStep(variable: .intervalCount, incrementPerWeek: 1, weeksToCeiling: 3)
                ],
                weekOneIntervalCount: 5,
                weekOneWorkDistanceMeters: 1000,
                weekOneRecoveryDurationSeconds: 120,
                recoveryDurationFloorSeconds: 90,
                completionCriteria: IntervalCompletionCriteria(maxRpeAllowed: 9)
            )
        }
    }

    private static func workIntensity(for workBasis: IntervalWorkBasis) -> IntensityTarget {
        switch workBasis {
        case .duration:
            return .heartRatePercent(BoundedRange(lower: 0.90, upper: 0.95))
        case .distance:
            return .pace(PaceRange(lower: Pace(secondsPerKilometer: 270), upper: Pace(secondsPerKilometer: 280)))
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
