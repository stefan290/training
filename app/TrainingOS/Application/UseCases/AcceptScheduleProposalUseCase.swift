import Foundation
import SwiftData

enum ScheduleAcceptanceError: Error, Equatable {
    /// An `.infeasible` `ScheduleProposal` must never be silently
    /// accepted — the caller must resolve its `conflicts` (or explicitly
    /// accept a reduced mix) and produce a new proposal first.
    case infeasible
}

/// The Engine-recommendation -> Explanation -> User-approval pattern's
/// final step for `ConcurrentScheduler`: turns an already-approved
/// `ScheduleProposal` into real, persisted `Day`/`Session` state. A
/// `ScheduleProposal` itself never mutates anything — only this use case
/// does, and only when explicitly called.
///
/// Every `Session` a proposal places already exists (materialized, with a
/// naive date, by some `ProgrammingSystem`) — this use case re-parents it
/// onto the real target `Day` and stamps `schedulerVersion`; it never
/// creates a new `Session` or touches any prescription/result.
enum AcceptScheduleProposalUseCase {
    static func accept(
        _ proposal: ScheduleProposal,
        ownerUserID: UUID,
        context: ModelContext
    ) throws {
        guard proposal.feasibility != .infeasible else {
            throw ScheduleAcceptanceError.infeasible
        }

        for placement in proposal.placements {
            let session = placement.session

            if let oldDay = session.day {
                oldDay.sessions.removeAll { $0.id == session.id }
            }

            let targetDay = try findOrCreateDay(date: placement.date, ownerUserID: ownerUserID, context: context)
            targetDay.addSession(session)
            // `addSession` assigns `sortIndex` from the target Day's
            // current count, which may not match the proposal's own
            // within-day ordering if that Day already held other Sessions
            // — the explicit overwrite below is what actually keeps
            // placement order authoritative.
            session.sortIndex = placement.sortIndexInDay
            session.scheduledTime = placement.date
            session.schedulerVersion = proposal.schedulerVersion
        }
    }

    private static func findOrCreateDay(date: Date, ownerUserID: UUID, context: ModelContext) throws -> Day {
        let descriptor = FetchDescriptor<Day>(
            predicate: #Predicate { $0.ownerUserID == ownerUserID && $0.date == date }
        )
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let day = Day(ownerUserID: ownerUserID, date: date)
        context.insert(day)
        return day
    }
}
