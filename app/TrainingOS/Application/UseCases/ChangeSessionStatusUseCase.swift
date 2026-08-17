import Foundation
import SwiftData

/// Stage 6B: the orchestrating use case behind every `Session` status
/// change that isn't starting or completing it (`StartSessionUseCase`/
/// `CompleteSessionUseCase` own those) — the pre-start "Skip / Can't
/// train today" action and the missed-session write, both from
/// `SESSION_STATE_MACHINE.md` §4/§7. **Records state only — never
/// computes a reflow proposal itself**; that stays
/// `SchedulingPipeline`/`LongTermPlanner`'s job
/// (`WORKOUT_COMPLETION_PIPELINE.md` §6).
enum ChangeSessionStatusUseCase {
    /// The user explicitly said "Can't train today," before ever
    /// starting — a structured, intentional fact, distinct from
    /// `markMissed` below. Only valid from `.scheduled`; idempotent
    /// no-op otherwise (e.g. a Session already started cannot be
    /// retroactively "skipped" through this path).
    @discardableResult
    static func skip(_ session: Session, modelContext: ModelContext) throws -> Session {
        guard session.status == .scheduled else { return session }
        session.status = .skipped
        try modelContext.save()
        return session
    }

    /// Written only when the user views and interacts with the
    /// missed-session prompt — never a background process, never
    /// auto-applied just because a date comparison is true
    /// (`SESSION_STATE_MACHINE.md` §7). Only valid from `.scheduled`;
    /// idempotent no-op otherwise.
    @discardableResult
    static func markMissed(_ session: Session, modelContext: ModelContext) throws -> Session {
        guard session.status == .scheduled else { return session }
        session.status = .missed
        try modelContext.save()
        return session
    }
}
