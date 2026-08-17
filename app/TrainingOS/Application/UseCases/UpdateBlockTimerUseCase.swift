import Foundation
import SwiftData

/// Stage 6B: the orchestrating use case behind every rest/AMRAP/EMOM/
/// interval/For Time timer transition — wraps the pure `WorkoutTimer`
/// arithmetic and saves immediately, one call per meaningful transition
/// (start/pause/resume/clear), never per tick (`TIMER_ARCHITECTURE.md`
/// §3, CLAUDE.md rule 21). A running timer's live countdown display is
/// computed at render time from the persisted `TimerState` plus the
/// current moment — it never calls back into this use case just to
/// re-render.
enum UpdateBlockTimerUseCase {
    @discardableResult
    static func start(
        _ block: WorkoutBlock,
        asOf: Date,
        targetDurationSeconds: Int?,
        currentUnitIndex: Int? = nil,
        modelContext: ModelContext
    ) throws -> WorkoutBlock {
        block.timerState = WorkoutTimer.start(
            asOf: asOf, targetDurationSeconds: targetDurationSeconds, currentUnitIndex: currentUnitIndex
        )
        try modelContext.save()
        return block
    }

    @discardableResult
    static func pause(_ block: WorkoutBlock, asOf: Date, modelContext: ModelContext) throws -> WorkoutBlock {
        guard let state = block.timerState else { return block }
        block.timerState = WorkoutTimer.pause(state, asOf: asOf)
        try modelContext.save()
        return block
    }

    @discardableResult
    static func resume(_ block: WorkoutBlock, asOf: Date, modelContext: ModelContext) throws -> WorkoutBlock {
        guard let state = block.timerState else { return block }
        block.timerState = WorkoutTimer.resume(state, asOf: asOf)
        try modelContext.save()
        return block
    }

    @discardableResult
    static func advanceUnit(
        _ block: WorkoutBlock, asOf: Date, to unitIndex: Int, targetDurationSeconds: Int?, modelContext: ModelContext
    ) throws -> WorkoutBlock {
        block.timerState = WorkoutTimer.advanceUnit(asOf: asOf, to: unitIndex, targetDurationSeconds: targetDurationSeconds)
        try modelContext.save()
        return block
    }

    /// Skip/reset both resolve here — there is nothing left to recover
    /// from a relaunch once the timer's own job (e.g. this rest period)
    /// is done, so clearing it outright is correct, not a partial state.
    @discardableResult
    static func clear(_ block: WorkoutBlock, modelContext: ModelContext) throws -> WorkoutBlock {
        block.timerState = nil
        try modelContext.save()
        return block
    }
}
