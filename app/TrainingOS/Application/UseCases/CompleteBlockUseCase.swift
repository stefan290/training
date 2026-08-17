import Foundation
import SwiftData

/// Stage 6B: the orchestrating use case behind every `WorkoutBlock`
/// status change — start, complete (full or partial), skip. Never
/// touches a block's prescription; only its own execution bookkeeping
/// (`SESSION_STATE_MACHINE.md` §5). Saves immediately, one call per
/// meaningful action.
enum CompleteBlockUseCase {
    /// Marks a block `.active` — idempotent, a no-op if already active
    /// or further along.
    @discardableResult
    static func start(_ block: WorkoutBlock, modelContext: ModelContext) throws -> WorkoutBlock {
        guard block.status == .pending else { return block }
        block.status = .active
        try modelContext.save()
        return block
    }

    /// `completionContext` reflects whether every unit the block's
    /// prescription called for actually has a logged result — the
    /// caller (which already knows the block's modality-specific result
    /// shape) decides `.full` vs. `.partial`; this use case never
    /// re-derives it from a generic count comparison, since "how many
    /// units were prescribed" means something different per
    /// `WorkoutBlockType`. Idempotent: completing an already-`.completed`
    /// block again is a no-op — never re-marks or re-saves.
    @discardableResult
    static func complete(_ block: WorkoutBlock, context: BlockCompletionContext, modelContext: ModelContext) throws -> WorkoutBlock {
        guard block.status != .completed else { return block }
        block.status = .completed
        block.completionContext = context
        try modelContext.save()
        return block
    }

    /// The kickoff's "mark incomplete" actions (an EMOM minute, a For
    /// Time round not attempted, an entire block the user chooses not to
    /// do) resolve here — always an explicit user action, never inferred
    /// by a timer expiring silently. Idempotent.
    @discardableResult
    static func skip(_ block: WorkoutBlock, modelContext: ModelContext) throws -> WorkoutBlock {
        guard block.status != .skipped else { return block }
        block.status = .skipped
        try modelContext.save()
        return block
    }
}
