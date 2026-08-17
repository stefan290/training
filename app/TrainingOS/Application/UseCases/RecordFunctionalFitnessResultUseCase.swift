import Foundation
import SwiftData

/// Attaches a typed `FunctionalFitnessResult` to its `WorkoutBlock` and,
/// when it's an attempt at a `BenchmarkDefinition`, folds the score into
/// permanent history exactly like `RecordWorkoutResultUseCase` does for
/// the legacy path — the canonical, sole way a Functional Fitness result
/// becomes a `PersonalRecord` as of Stage 4E's Fran consolidation (see
/// `STAGE4_IMPLEMENTATION_REPORT.md`'s Stage 4E §9 and
/// `FUNCTIONAL_FITNESS_ENGINE.md`).
enum RecordFunctionalFitnessResultUseCase {
    @discardableResult
    static func recordResult(
        _ result: FunctionalFitnessResult,
        for workoutBlock: WorkoutBlock,
        benchmark: BenchmarkDefinition?,
        performanceProfile: PerformanceProfile?,
        modelContext: ModelContext
    ) -> (result: FunctionalFitnessResult, isFirstEverEntry: Bool) {
        modelContext.insert(result)
        workoutBlock.attachFunctionalFitnessResult(result)

        guard let benchmark, let performanceProfile else { return (result, false) }
        result.benchmark = benchmark

        let benchmarkProfile = PerformanceProfileStore.benchmarkProfile(
            for: benchmark, in: performanceProfile, context: modelContext
        )
        benchmarkProfile.lastPerformedAt = result.completedAt
        benchmarkProfile.addResult(result)

        let scoringDirection = mapToScoringDirection(result.scoreDirection)
        let candidateValue = comparableValue(for: result.scoreValue)

        // §24: Rx and Scaled never compete for the same record —
        // `ScoringEngine.bestRecord` already enforces this via `context`.
        let existingBest = ScoringEngine.bestRecord(
            among: benchmarkProfile.personalRecords, context: result.resultContext, repBand: nil
        )
        // Stage 6B, `STAGE6A_DECISION_MEMO.md` §1b: same first-entry
        // presentation flag as `RecordSetResultUseCase` — data unchanged.
        let isFirstEverEntry = existingBest == nil
        if ScoringEngine.isNewPersonalRecord(candidateValue: candidateValue, direction: scoringDirection, existingBest: existingBest) {
            let record = PersonalRecord(
                value: candidateValue, repBand: nil, scoringDirection: scoringDirection,
                context: result.resultContext, achievedAt: result.completedAt
            )
            modelContext.insert(record)
            // sourceFunctionalFitnessResult is the declared inverse of
            // FunctionalFitnessResult.personalRecord — setting this side
            // is sufficient, mirroring RecordWorkoutResultUseCase's
            // identical sourceWorkoutResult pattern.
            record.sourceFunctionalFitnessResult = result
            benchmarkProfile.addPersonalRecord(record)
        }

        return (result, isFirstEverEntry)
    }

    /// `ScoreValue` stays a structured, typed union everywhere else in
    /// this codebase (§13: "do not flatten the final score into a
    /// display-only string") — this function exists solely to produce
    /// one comparable `Double` for `ScoringEngine`'s existing higher/
    /// lower-is-better comparison, never for display.
    ///
    /// `.roundsAndReps`' proxy (`rounds * 100_000 + partialReps`) is
    /// TRAININGOS_DESIGNED, not sourced: more completed rounds always
    /// beats fewer, and within the same round count more partial reps
    /// wins — the exact ordering every AMRAP scoring convention already
    /// uses, expressed as one comparable number rather than a tuple
    /// comparison, since `ScoringEngine`'s existing contract takes a
    /// single `Double`.
    static func comparableValue(for scoreValue: ScoreValue) -> Double {
        switch scoreValue {
        case .time(let seconds): return Double(seconds)
        case .roundsAndReps(let rounds, let partialReps): return Double(rounds) * 100_000 + Double(partialReps)
        case .repetitions(let reps): return Double(reps)
        case .calories(let calories): return Double(calories)
        case .distance(let meters): return meters
        case .load(let kilograms): return kilograms
        case .completedIntervals(let count): return Double(count)
        }
    }

    /// `ScoreDirection` (Stage 3C, 2 cases: always-comparable) bridges
    /// onto `ScoringDirection` (the pre-existing 4-case vocabulary
    /// `ScoringEngine`/`PersonalRecord` already use) — a 1:1 mapping,
    /// never inferred from score type or format name (§12).
    static func mapToScoringDirection(_ scoreDirection: ScoreDirection) -> ScoringDirection {
        switch scoreDirection {
        case .lowerIsBetter: return .lowerIsBetter
        case .higherIsBetter: return .higherIsBetter
        }
    }
}
