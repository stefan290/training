import Foundation
import SwiftData

/// A stable, repeatable Functional Fitness prescription with a stable
/// scoring definition and an identity suitable for longitudinal
/// comparison ("Fran," "Murph," a gym's own named benchmark) — the
/// smallest correct abstraction found in Stage 3B (§22): not a new result
/// type, not a dedicated prescription-sharing mechanism, just a named,
/// stable `Stimulus`/`WorkoutFormat`/scoring definition that attempts can
/// reference.
///
/// `canonicalID` is the stable string identity (e.g. `"benchmark.fran"`),
/// mirroring the canonical-ID discipline `Exercise` already uses — see
/// `PERFORMANCE_PROFILE_MODALITY_REVIEW.md` §4. `results` is `.nullify`,
/// not `.cascade`: deleting a benchmark's definition (a methodology-like
/// edit) must never delete a user's historical attempts at it, exactly
/// mirroring `ProgramDefinition.instances`.
///
/// This is intentionally separate from, and does not replace, the
/// Stage 1-2 "Fran modelled as a canonical Exercise" shortcut still used
/// by `SeedScenarios.forTimeBenchmarkSession` — see
/// `STAGE3C_IMPLEMENTATION_REPORT.md` for why both are left in place for
/// now rather than migrating the existing scenario.
@Model
final class BenchmarkDefinition {
    @Attribute(.unique) var id: UUID
    var canonicalID: String
    var name: String
    var stimulus: Stimulus

    // MARK: - `format` — flattened tagged union (FF WorkoutFormat SwiftData
    // fix, this pass). See `FunctionalFitnessPrescriptionTemplate.swift`'s
    // doc comment for the real crash this fixes and `WorkoutFormat.swift`
    // for the shared coding logic.
    var workoutFormatKind: WorkoutFormatKind = WorkoutFormatKind.maxLoad
    var workoutFormatCapSeconds: Int?
    var workoutFormatRounds: Int?
    var workoutFormatIntervalSeconds: Int?
    var workoutFormatTotalSeconds: Int?
    var workoutFormatDirection: LadderDirection?
    var workoutFormatCount: Int?
    var workoutFormatWorkSeconds: Int?
    var workoutFormatRestSeconds: Int?

    var format: WorkoutFormat {
        get {
            WorkoutFormatCoding.reconstruct(WorkoutFormatCoding.Flat(
                kind: workoutFormatKind, capSeconds: workoutFormatCapSeconds, rounds: workoutFormatRounds,
                intervalSeconds: workoutFormatIntervalSeconds, totalSeconds: workoutFormatTotalSeconds,
                direction: workoutFormatDirection, count: workoutFormatCount,
                workSeconds: workoutFormatWorkSeconds, restSeconds: workoutFormatRestSeconds
            ))
        }
        set {
            let flat = WorkoutFormatCoding.flatten(newValue)
            workoutFormatKind = flat.kind
            workoutFormatCapSeconds = flat.capSeconds
            workoutFormatRounds = flat.rounds
            workoutFormatIntervalSeconds = flat.intervalSeconds
            workoutFormatTotalSeconds = flat.totalSeconds
            workoutFormatDirection = flat.direction
            workoutFormatCount = flat.count
            workoutFormatWorkSeconds = flat.workSeconds
            workoutFormatRestSeconds = flat.restSeconds
        }
    }
    var scoreType: ScoreType
    var scoreDirection: ScoreDirection

    @Relationship(deleteRule: .nullify, inverse: \FunctionalFitnessResult.benchmark)
    var results: [FunctionalFitnessResult] = []

    /// Nothing in application code reads this — it exists purely so
    /// `BenchmarkPerformanceProfile.benchmark` has a real inverse to
    /// nullify against on delete, the same required-inverse mechanics as
    /// `ProgramDefinition.instances`. Caught during this pass's own
    /// relationship audit (see `STAGE3C_IMPLEMENTATION_REPORT.md`), not by
    /// a real Xcode build — worth re-confirming once the local build runs.
    @Relationship(deleteRule: .nullify, inverse: \BenchmarkPerformanceProfile.benchmark)
    var performanceProfiles: [BenchmarkPerformanceProfile] = []

    init(
        id: UUID = UUID(),
        canonicalID: String,
        name: String,
        stimulus: Stimulus,
        format: WorkoutFormat,
        scoreType: ScoreType,
        scoreDirection: ScoreDirection
    ) {
        self.id = id
        self.canonicalID = canonicalID
        self.name = name
        self.stimulus = stimulus
        self.scoreType = scoreType
        self.scoreDirection = scoreDirection
        self.format = format
    }
}
