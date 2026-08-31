import Foundation
import SwiftData

/// The typed result for a `.functionalFitness` block. `scoreDirection` is
/// always set explicitly at creation time (never derived from `scoreType`
/// or from the workout's name) — see `ScoreTypes.swift` and
/// `FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md` §4.
///
/// `benchmark` is `nil` for a generated (non-benchmark) workout —
/// generated Functional Fitness workouts are permanent training history
/// exactly like any other logged result, but are never automatically a
/// tracked benchmark (Stage 3B/3C §14/§22). Setting `benchmark` is what
/// makes an attempt count toward that benchmark's longitudinal history via
/// `benchmarkPerformanceProfile`.
///
/// Four independent parent relationships, mirroring `SetResult`'s
/// three-parent shape: `workoutBlock` (session context, `.nullify` —
/// declared on `WorkoutBlock.functionalFitnessResult`),
/// `benchmarkPerformanceProfile` (permanent home, `.cascade` — declared on
/// `BenchmarkPerformanceProfile.results`, only fires on account deletion),
/// `benchmark` (which benchmark this was an attempt at, `.nullify` —
/// declared on `BenchmarkDefinition.results`), and `personalRecord` (this
/// result's own `.nullify` declaration, mirroring `WorkoutResult.personalRecord`
/// exactly).
@Model
final class FunctionalFitnessResult {
    @Attribute(.unique) var id: UUID
    var workoutBlock: WorkoutBlock?
    var benchmarkPerformanceProfile: BenchmarkPerformanceProfile?
    var benchmark: BenchmarkDefinition?

    var scoreType: ScoreType
    var scoreValue: ScoreValue
    var scoreDirection: ScoreDirection
    var resultContext: ResultContext
    /// Stage FF.E1 addition. Separate from `resultContext` — see
    /// `PrescriptionAdherence`'s own doc comment for why. Additive,
    /// defaults `.unknown`: every prescription persisted before this
    /// field existed reads `.unknown`, never fabricated as `.asPrescribed`
    /// from `resultContext`'s own unconditional `.rx` default.
    var adherence: PrescriptionAdherence
    var completedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \FunctionalFitnessPerformedMovement.functionalFitnessResult)
    var performedMovements: [FunctionalFitnessPerformedMovement] = []

    /// Nullify, not cascade: a PersonalRecord must survive the deletion of
    /// the FunctionalFitnessResult that produced it — same reasoning and
    /// same required-inverse mechanics as `WorkoutResult.personalRecord`.
    @Relationship(deleteRule: .nullify, inverse: \PersonalRecord.sourceFunctionalFitnessResult)
    var personalRecord: PersonalRecord?

    init(
        id: UUID = UUID(),
        scoreType: ScoreType,
        scoreValue: ScoreValue,
        scoreDirection: ScoreDirection,
        resultContext: ResultContext = .rx,
        adherence: PrescriptionAdherence = .unknown,
        completedAt: Date = Date()
    ) {
        self.id = id
        self.scoreType = scoreType
        self.scoreValue = scoreValue
        self.scoreDirection = scoreDirection
        self.resultContext = resultContext
        self.adherence = adherence
        self.completedAt = completedAt
    }

    /// The only way application code should attach a performed movement.
    /// Mutates exactly one side (this array); SwiftData maintains
    /// `movement.functionalFitnessResult` from the declared inverse.
    func addPerformedMovement(_ movement: FunctionalFitnessPerformedMovement) {
        movement.sortIndex = performedMovements.count
        performedMovements.append(movement)
    }

    var orderedPerformedMovements: [FunctionalFitnessPerformedMovement] {
        performedMovements.sorted { $0.sortIndex < $1.sortIndex }
    }
}
