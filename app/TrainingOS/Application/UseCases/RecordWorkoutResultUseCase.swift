import Foundation
import SwiftData

/// Attaches a legacy block-level result (steady state, intervals, ad-hoc
/// AMRAP/EMOM) to its WorkoutBlock.
///
/// **Stage 4E correction:** this previously also accepted
/// `benchmarkExercise`/`prCandidateValue` and folded a benchmark's score
/// into `ExercisePerformanceProfile` — modeling a repeatable benchmark
/// (e.g. "Fran") as a canonical `Exercise` so it could carry a
/// `PersonalRecord` like any other movement. That was the exact "two
/// competing canonical identities for the same benchmark" duplication
/// Stage 3C deferred and Stage 4E was asked to resolve: `BenchmarkDefinition`/
/// `BenchmarkPerformanceProfile`/`RecordFunctionalFitnessResultUseCase` is
/// now the sole sanctioned path for benchmark PRs (see
/// `STAGE4_IMPLEMENTATION_REPORT.md`'s Stage 4E §9 and
/// `FUNCTIONAL_FITNESS_ENGINE.md`). Removed here rather than left dead —
/// its only real caller (`SeedScenarios.forTimeBenchmarkSession`) was
/// migrated in the same pass, so no code depends on the old branch.
enum RecordWorkoutResultUseCase {
    @discardableResult
    static func recordResult(
        _ result: WorkoutResult,
        for workoutBlock: WorkoutBlock,
        modelContext: ModelContext
    ) -> WorkoutResult {
        modelContext.insert(result)
        workoutBlock.attachResult(result)
        return result
    }
}
