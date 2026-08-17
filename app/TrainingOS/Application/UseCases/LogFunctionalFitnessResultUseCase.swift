import Foundation
import SwiftData

/// Stage 6B: the orchestrating use case behind every logged Functional
/// Fitness result — wraps the existing `RecordFunctionalFitnessResultUseCase`
/// and saves immediately, matching `LogSetUseCase`'s exact shape
/// (`WORKOUT_COMPLETION_PIPELINE.md` §1).
enum LogFunctionalFitnessResultUseCase {
    @discardableResult
    static func logResult(
        _ result: FunctionalFitnessResult,
        for workoutBlock: WorkoutBlock,
        benchmark: BenchmarkDefinition?,
        performanceProfile: PerformanceProfile?,
        modelContext: ModelContext
    ) throws -> (result: FunctionalFitnessResult, isFirstEverEntry: Bool) {
        let outcome = RecordFunctionalFitnessResultUseCase.recordResult(
            result, for: workoutBlock, benchmark: benchmark, performanceProfile: performanceProfile, modelContext: modelContext
        )
        try modelContext.save()
        return outcome
    }
}
