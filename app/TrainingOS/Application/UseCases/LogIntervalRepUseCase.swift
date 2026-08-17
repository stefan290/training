import Foundation
import SwiftData

/// Stage 6B: per-interval persistence for a live Interval block
/// (`ENDURANCE_EXECUTION_FLOW.md` §2c, CLAUDE.md rule 20) — each completed
/// work/recovery leg is logged and saved the moment it happens, never
/// held in memory until the whole interval session finishes.
/// `FinalizeIntervalResultUseCase` is the later, final consistency point
/// that fills in the session-level summary and runs PR detection; this
/// use case never does either — it only ever appends one more rep to
/// whichever `IntervalResult` this block already has (creating it, on
/// this block's very first rep, unattached to any
/// `ActivityPerformanceProfile` until finalize).
enum LogIntervalRepUseCase {
    @discardableResult
    static func logRep(
        _ repResult: IntervalRepResult,
        for block: WorkoutBlock,
        resultContext: ResultContext = .rx,
        modelContext: ModelContext
    ) throws -> IntervalResult {
        let result: IntervalResult
        if let existing = block.intervalResult {
            result = existing
        } else {
            result = IntervalResult(resultContext: resultContext)
            modelContext.insert(result)
            block.attachIntervalResult(result)
        }
        result.addRepResult(repResult)
        try modelContext.save()
        return result
    }
}
