import Foundation
import SwiftData

/// The template-graph analogue of `IntervalPrescription` — reusable
/// interval methodology (a repeated work/recovery *rule*, never a
/// resolved number), mirroring `SteadyStatePrescriptionTemplate`'s
/// relationship to `SteadyStatePrescription` exactly. Closes the interval
/// half of the gap `WorkoutBlockTemplate`'s Stage 4A doc comment
/// originally deferred.
///
/// **Rule storage is a manually flattened tagged union** — same Bug 2/3
/// discipline as every other template entity in this codebase.
/// `workIntensity`/`recoveryIntensity` are stored as direct top-level
/// `IntensityTarget?` properties (the proven-safe shape); progression is
/// restricted to flat scalars, including `priority`, which is an array of
/// the plain (no-associated-value) `IntervalProgressionVariable`/`Double`/
/// `Int` primitives via `IntervalProgressionStepKind`/`IntervalProgressionStepAmount`/
/// `IntervalProgressionStepCeiling` parallel arrays — **not** an array of
/// the `IntervalProgressionStep` struct directly. `IntervalProgressionStep`
/// is a plain struct of primitives (no enum-with-payload), which Stage
/// 4A/4B/4C already proved safe to store directly in several other
/// places (`DeloadPositionOverride`, `TrainingStressProfile`) — but those
/// precedents are all *singular* stored structs, never an *array* of a
/// multi-field struct. No existing test in this codebase proves an array
/// of a multi-field struct round-trips safely either, so this pass
/// flattens to parallel primitive arrays rather than assume the untested
/// shape is fine by analogy — the same conservative choice
/// `SteadyStatePrescriptionTemplate` already made for intensity
/// progression.
@Model
final class IntervalPrescriptionTemplate: ActivitySubstitutionTemplate {
    @Attribute(.unique) var id: UUID
    var workoutBlockTemplate: WorkoutBlockTemplate?

    var preferredActivityType: ActivityType
    var allowedActivityTypes: [ActivityType]

    var workIntensity: IntensityTarget?
    var recoveryIntensity: IntensityTarget?
    var recoveryType: RecoveryType

    // MARK: - Progression rule storage (flattened parallel arrays, see doc comment above)

    var priorityVariables: [IntervalProgressionVariable] = []
    var priorityIncrementsPerWeek: [Double] = []
    var priorityWeeksToCeiling: [Int] = []

    var weekOneIntervalCount: Int
    var weekOneWorkDurationSeconds: Int?
    var weekOneWorkDistanceMeters: Double?
    var intensityZoneProgressionStartZone: HeartRateZone?
    var intensityZoneProgressionStepPerWeek: Int?
    var intensityZoneProgressionMaxZone: HeartRateZone?
    var weekOneRecoveryDurationSeconds: Int?
    var recoveryDurationFloorSeconds: Int = 0

    var completionCriteriaMaxRpeAllowed: Int?
    var completionCriteriaMinimumFractionForProgress: Double = 1.0
    var completionCriteriaMinimumFractionForHold: Double = 0.75
    var completionCriteriaMinimumFractionForRepeat: Double = 0.5
    var completionCriteriaReductionStrategy: IntervalReductionStrategy = IntervalReductionStrategy.reduceIntervalCount
    var requiresSuccessfulCompletionToProgress: Bool = false

    init(
        id: UUID = UUID(),
        preferredActivityType: ActivityType,
        allowedActivityTypes: [ActivityType]? = nil,
        workIntensity: IntensityTarget? = nil,
        recoveryIntensity: IntensityTarget? = nil,
        recoveryType: RecoveryType = .active,
        progressionRules: IntervalProgressionRules? = nil
    ) {
        self.id = id
        self.preferredActivityType = preferredActivityType
        self.allowedActivityTypes = allowedActivityTypes ?? [preferredActivityType]
        self.workIntensity = workIntensity
        self.recoveryIntensity = recoveryIntensity
        self.recoveryType = recoveryType
        self.weekOneIntervalCount = progressionRules?.weekOneIntervalCount ?? 1
        self.progressionRules = progressionRules
    }

    /// Ergonomic bundle over the flat stored properties above — the
    /// interval sibling of `SteadyStatePrescriptionTemplate.progressionRules`.
    var progressionRules: IntervalProgressionRules? {
        get {
            var zoneProgression: IntensityZoneProgression?
            if let start = intensityZoneProgressionStartZone,
               let step = intensityZoneProgressionStepPerWeek,
               let max = intensityZoneProgressionMaxZone {
                zoneProgression = IntensityZoneProgression(startZone: start, stepPerWeek: step, maxZone: max)
            }
            let priority = zip(priorityVariables, zip(priorityIncrementsPerWeek, priorityWeeksToCeiling)).map {
                IntervalProgressionStep(variable: $0, incrementPerWeek: $1.0, weeksToCeiling: $1.1)
            }
            let criteria = IntervalCompletionCriteria(
                maxRpeAllowed: completionCriteriaMaxRpeAllowed,
                minimumCompletionFractionForProgress: completionCriteriaMinimumFractionForProgress,
                minimumCompletionFractionForHold: completionCriteriaMinimumFractionForHold,
                minimumCompletionFractionForRepeat: completionCriteriaMinimumFractionForRepeat,
                reductionStrategy: completionCriteriaReductionStrategy
            )
            return IntervalProgressionRules(
                priority: priority,
                weekOneIntervalCount: weekOneIntervalCount,
                weekOneWorkDurationSeconds: weekOneWorkDurationSeconds,
                weekOneWorkDistanceMeters: weekOneWorkDistanceMeters,
                intensityZoneProgression: zoneProgression,
                weekOneRecoveryDurationSeconds: weekOneRecoveryDurationSeconds,
                recoveryDurationFloorSeconds: recoveryDurationFloorSeconds,
                completionCriteria: criteria,
                requiresSuccessfulCompletionToProgress: requiresSuccessfulCompletionToProgress
            )
        }
        set {
            priorityVariables = newValue?.priority.map(\.variable) ?? []
            priorityIncrementsPerWeek = newValue?.priority.map(\.incrementPerWeek) ?? []
            priorityWeeksToCeiling = newValue?.priority.map(\.weeksToCeiling) ?? []
            weekOneIntervalCount = newValue?.weekOneIntervalCount ?? 1
            weekOneWorkDurationSeconds = newValue?.weekOneWorkDurationSeconds
            weekOneWorkDistanceMeters = newValue?.weekOneWorkDistanceMeters
            intensityZoneProgressionStartZone = newValue?.intensityZoneProgression?.startZone
            intensityZoneProgressionStepPerWeek = newValue?.intensityZoneProgression?.stepPerWeek
            intensityZoneProgressionMaxZone = newValue?.intensityZoneProgression?.maxZone
            weekOneRecoveryDurationSeconds = newValue?.weekOneRecoveryDurationSeconds
            recoveryDurationFloorSeconds = newValue?.recoveryDurationFloorSeconds ?? 0
            completionCriteriaMaxRpeAllowed = newValue?.completionCriteria.maxRpeAllowed
            completionCriteriaMinimumFractionForProgress = newValue?.completionCriteria.minimumCompletionFractionForProgress ?? 1.0
            completionCriteriaMinimumFractionForHold = newValue?.completionCriteria.minimumCompletionFractionForHold ?? 0.75
            completionCriteriaMinimumFractionForRepeat = newValue?.completionCriteria.minimumCompletionFractionForRepeat ?? 0.5
            completionCriteriaReductionStrategy = newValue?.completionCriteria.reductionStrategy ?? .reduceIntervalCount
            requiresSuccessfulCompletionToProgress = newValue?.requiresSuccessfulCompletionToProgress ?? false
        }
    }
}
