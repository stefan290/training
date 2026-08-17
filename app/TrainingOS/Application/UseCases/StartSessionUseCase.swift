import Foundation
import SwiftData

/// Stage 6B: the orchestrating use case behind Today's "Start session"
/// action — `WORKOUT_EXECUTION.md` §5's save-owning layer
/// (`STAGE6A_DECISION_MEMO.md` §1d). Leaves every prescription untouched;
/// starting a Session is pure bookkeeping, never a materialization step.
enum StartSessionUseCase {
    /// Idempotent: starting an already-`.inProgress` Session is a no-op,
    /// never a duplicate `startedAt` stamp — safe to call again if a
    /// crash happened between tapping Start and the screen appearing.
    @discardableResult
    static func start(_ session: Session, asOf: Date, modelContext: ModelContext) throws -> Session {
        guard session.status != .inProgress else { return session }
        session.status = .inProgress
        session.startedAt = asOf
        try modelContext.save()
        return session
    }
}
