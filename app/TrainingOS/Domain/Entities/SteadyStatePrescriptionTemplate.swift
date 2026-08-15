import Foundation
import SwiftData

/// The template-graph analogue of `SteadyStatePrescription` — reusable
/// methodology (a duration/distance/intensity *rule*, never a resolved
/// number), exactly mirroring `PrescriptionTemplate`'s relationship to
/// `ExercisePrescription`. Closes the gap `WorkoutBlockTemplate`'s own
/// Stage 4A doc comment explicitly deferred: "steady-state/interval/
/// functional-fitness template equivalents are a Stage 4C/D/E extension,
/// not built here."
///
/// **Rule storage is a manually flattened tagged union, not a directly
/// stored `SteadyStateProgressionRules` struct field** — the same Bug 2/3
/// discipline `PrescriptionTemplate` already established: a struct field
/// containing an enum-with-payload (`IntensityZoneProgression` contains no
/// such thing, but the *pattern itself* is what's proven safe, not any one
/// struct's specific shape) is not assumed safe without its own diagnostic
/// round-trip test. `primaryIntensity`/`secondaryIntensity` below **are**
/// stored directly as top-level `IntensityTarget?` properties — that
/// specific shape (an enum-with-payload as a *direct* top-level `@Model`
/// property, not nested in a wrapping struct) is the one already proven
/// safe by Stage 3C's `SteadyStatePrescription` itself and Stage 4A's own
/// `TemplateGraphPersistenceTests` diagnostics. What is deliberately
/// **not** attempted here is a per-week `[IntensityTarget]` array — no
/// existing test in this codebase proves an array of an enum-with-payload
/// round-trips safely, so intensity progression is restricted to the
/// flat-scalar `IntensityZoneProgression` shape instead (see
/// `SteadyStateProgressionRules`'s own doc comment) rather than risking an
/// untested persistence shape.
@Model
final class SteadyStatePrescriptionTemplate: ActivitySubstitutionTemplate {
    @Attribute(.unique) var id: UUID
    var workoutBlockTemplate: WorkoutBlockTemplate?

    /// The program's preferred/default activity — what a built-in
    /// configuration or a curated program author intends by default.
    var preferredActivityType: ActivityType
    /// Substitution-eligible alternatives (Stage 4C §35). A prescription
    /// that permits no substitution at all sets this to exactly
    /// `[preferredActivityType]` — never empty, so "no alternatives" and
    /// "unconfigured" are never confused; `SubstitutionValidator`
    /// treats anything not in this list as invalid for this template.
    var allowedActivityTypes: [ActivityType]

    var primaryIntensity: IntensityTarget?
    var secondaryIntensity: IntensityTarget?

    // MARK: - Progression rule storage (flattened, see doc comment above)

    var progressionDimension: SteadyStateProgressionDimension = SteadyStateProgressionDimension.none
    var weekOneDurationSeconds: Int?
    var laterWeekDurationSeconds: [Int] = []
    var weekOneDistanceMeters: Double?
    var laterWeekDistanceMeters: [Double] = []
    var intensityZoneProgressionStartZone: HeartRateZone?
    var intensityZoneProgressionStepPerWeek: Int?
    var intensityZoneProgressionMaxZone: HeartRateZone?
    var recoveryWeekDurationFraction: Double = 1.0
    var recoveryWeekDistanceFraction: Double = 1.0
    var recoveryWeekIntensityZoneStepDown: Int = 0

    init(
        id: UUID = UUID(),
        preferredActivityType: ActivityType,
        allowedActivityTypes: [ActivityType]? = nil,
        primaryIntensity: IntensityTarget? = nil,
        secondaryIntensity: IntensityTarget? = nil,
        progressionRules: SteadyStateProgressionRules? = nil
    ) {
        self.id = id
        self.preferredActivityType = preferredActivityType
        self.allowedActivityTypes = allowedActivityTypes ?? [preferredActivityType]
        self.primaryIntensity = primaryIntensity
        self.secondaryIntensity = secondaryIntensity
        self.progressionRules = progressionRules
    }

    /// Ergonomic bundle over the flat stored properties above — the
    /// steady-state sibling of `PrescriptionTemplate.rules`.
    var progressionRules: SteadyStateProgressionRules? {
        get {
            var zoneProgression: IntensityZoneProgression?
            if let start = intensityZoneProgressionStartZone,
               let step = intensityZoneProgressionStepPerWeek,
               let max = intensityZoneProgressionMaxZone {
                zoneProgression = IntensityZoneProgression(startZone: start, stepPerWeek: step, maxZone: max)
            }
            return SteadyStateProgressionRules(
                progressionDimension: progressionDimension,
                weekOneDurationSeconds: weekOneDurationSeconds,
                laterWeekDurationSeconds: laterWeekDurationSeconds,
                weekOneDistanceMeters: weekOneDistanceMeters,
                laterWeekDistanceMeters: laterWeekDistanceMeters,
                intensityZoneProgression: zoneProgression,
                recoveryWeekDurationFraction: recoveryWeekDurationFraction,
                recoveryWeekDistanceFraction: recoveryWeekDistanceFraction,
                recoveryWeekIntensityZoneStepDown: recoveryWeekIntensityZoneStepDown
            )
        }
        set {
            progressionDimension = newValue?.progressionDimension ?? .none
            weekOneDurationSeconds = newValue?.weekOneDurationSeconds
            laterWeekDurationSeconds = newValue?.laterWeekDurationSeconds ?? []
            weekOneDistanceMeters = newValue?.weekOneDistanceMeters
            laterWeekDistanceMeters = newValue?.laterWeekDistanceMeters ?? []
            intensityZoneProgressionStartZone = newValue?.intensityZoneProgression?.startZone
            intensityZoneProgressionStepPerWeek = newValue?.intensityZoneProgression?.stepPerWeek
            intensityZoneProgressionMaxZone = newValue?.intensityZoneProgression?.maxZone
            recoveryWeekDurationFraction = newValue?.recoveryWeekDurationFraction ?? 1.0
            recoveryWeekDistanceFraction = newValue?.recoveryWeekDistanceFraction ?? 1.0
            recoveryWeekIntensityZoneStepDown = newValue?.recoveryWeekIntensityZoneStepDown ?? 0
        }
    }
}
