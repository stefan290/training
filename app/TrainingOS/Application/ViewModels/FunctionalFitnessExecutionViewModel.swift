import Foundation
import SwiftData
import Observation

/// Drives Functional Fitness execution (Part J) across every typed
/// `WorkoutFormat` — AMRAP/EMOM/For Time/Rounds For Time/Chipper/Ladder/
/// Max Load/Max Reps/Intervals — using the existing typed prescription,
/// never rebuilding or parsing anything from a workout description
/// string. A generated (non-benchmark) workout only becomes a tracked
/// `BenchmarkDefinition` attempt if the user explicitly tags it so at
/// Finish — never inferred, matching `FunctionalFitnessResult.benchmark`'s
/// own doc comment.
@Observable
final class FunctionalFitnessExecutionViewModel {
    let block: WorkoutBlock
    /// Shared with every other block in this Session — accumulates
    /// PR/first-entry highlights so the eventual completion screen can
    /// show them (`SessionExecutionState`'s own doc comment).
    let executionState: SessionExecutionState?
    /// AMRAP / Rounds For Time's live round counter — a plain in-memory
    /// tap count (the whole result is logged atomically at Finish, unlike
    /// Interval's per-rep persistence, since there is no meaningful
    /// smaller durable unit mid-AMRAP: Part J's own "no live rep logging
    /// every movement" requirement).
    private(set) var roundsCompleted: Int = 0
    private(set) var incompleteMinuteIndices: Set<Int> = []

    init(block: WorkoutBlock, executionState: SessionExecutionState? = nil) {
        self.block = block
        self.executionState = executionState
    }

    var prescription: FunctionalFitnessPrescription? { block.functionalFitnessPrescription }
    var format: WorkoutFormat? { prescription?.format }

    func incrementRound() { roundsCompleted += 1 }
    func decrementRound() { roundsCompleted = max(0, roundsCompleted - 1) }

    /// EMOM's current/next station — `WorkoutTimer.currentUnitIndex`
    /// already fits exactly (every minute shares one duration), unlike
    /// Intervals' alternating work/recovery legs.
    func emomPosition(asOf now: Date) -> (minuteIndex: Int, totalMinutes: Int, remaining: TimeInterval)? {
        guard case .emom(let intervalSeconds, let totalSeconds) = format, intervalSeconds > 0, let state = block.timerState else { return nil }
        let totalMinutes = max(1, totalSeconds / intervalSeconds)
        let index = WorkoutTimer.currentUnitIndex(asOf: now, state: state, unitDurationSeconds: intervalSeconds, totalUnits: totalMinutes)
        let elapsed = WorkoutTimer.elapsedSeconds(state, asOf: now)
        let unitElapsed = elapsed - Double(index * intervalSeconds)
        let remaining = max(0, Double(intervalSeconds) - unitElapsed)
        return (index, totalMinutes, remaining)
    }

    func markMinuteIncomplete(asOf now: Date) {
        guard let position = emomPosition(asOf: now) else { return }
        incompleteMinuteIndices.insert(position.minuteIndex)
    }

    /// The FF `.intervals` format's own auto Work -> Recovery -> Work
    /// progression — reuses the same pure derivation as Endurance
    /// Intervals (`IntervalTimerResolution`), since the mechanics are
    /// identical regardless of which modality's block owns the clock.
    func intervalsPosition(asOf now: Date) -> IntervalTimerResolution.Position? {
        guard case .intervals(let count, let work, let rest) = format, let state = block.timerState else { return nil }
        return IntervalTimerResolution.resolve(
            elapsedSeconds: WorkoutTimer.elapsedSeconds(state, asOf: now),
            workDurationSeconds: work, recoveryDurationSeconds: rest, intervalCount: count
        )
    }

    private func describeScore(_ value: ScoreValue) -> String {
        switch value {
        case .time(let seconds): String(format: "%d:%02d", seconds / 60, seconds % 60)
        case .roundsAndReps(let rounds, let reps): "\(rounds) rounds + \(reps) reps"
        case .repetitions(let reps): "\(reps) reps"
        case .calories(let cal): "\(cal) cal"
        case .distance(let meters): "\(Int(meters)) m"
        case .load(let kg): "\(kg.formattedWeight) kg"
        case .completedIntervals(let count): "\(count) completed"
        }
    }

    @discardableResult
    func finish(
        scoreValue: ScoreValue,
        completionContext: BlockCompletionContext,
        benchmark: BenchmarkDefinition?,
        modelContext: ModelContext
    ) -> LoggedResultHighlight? {
        guard let prescription else { return nil }
        let scoreDirection = FunctionalFitnessScoring.scoreDirection(for: prescription.format)
        let result = FunctionalFitnessResult(scoreType: prescription.stimulus.scoreType, scoreValue: scoreValue, scoreDirection: scoreDirection)
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        let performanceProfile = users.first?.performanceProfile

        guard let outcome = try? LogFunctionalFitnessResultUseCase.logResult(
            result, for: block, benchmark: benchmark, performanceProfile: performanceProfile, modelContext: modelContext
        ) else { return nil }

        try? CompleteBlockUseCase.complete(block, context: completionContext, modelContext: modelContext)

        let highlight = LoggedResultHighlight(
            label: benchmark?.name ?? "Functional Fitness",
            value: describeScore(scoreValue),
            isPersonalRecord: outcome.result.personalRecord != nil,
            isFirstEverEntry: outcome.isFirstEverEntry
        )
        executionState?.record(highlight)
        return highlight
    }
}
