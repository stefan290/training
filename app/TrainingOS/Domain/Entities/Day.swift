import Foundation
import SwiftData

/// A calendar day holding zero or more Sessions. Two Sessions on the same
/// Day (e.g. morning strength + evening Zone 2) is the normal case, not a
/// special one — see handoff's Day -> Session -> WorkoutBlock hierarchy.
@Model
final class Day {
    @Attribute(.unique) var id: UUID
    var ownerUserID: UUID
    /// Calendar date at midnight, local-independent (stored as the start of
    /// day in UTC by callers). One Day per user per date.
    var date: Date

    @Relationship(deleteRule: .cascade, inverse: \Session.day)
    var sessions: [Session] = []

    init(id: UUID = UUID(), ownerUserID: UUID, date: Date) {
        self.id = id
        self.ownerUserID = ownerUserID
        self.date = date
    }

    /// The only way application code should attach a Session to a Day.
    /// Mutates exactly one side of the relationship (this array); SwiftData
    /// maintains `session.day` from the declared inverse. Never set
    /// `session.day` directly elsewhere — see CLAUDE.md and
    /// DELETE_RULE_MATRIX.md.
    ///
    /// Always assigns `sortIndex` as the next position, so callers never
    /// compute or pass one. Reordering after the fact (e.g. drag-to-
    /// reschedule) is not implemented in this pass — see ARCHITECTURE.md.
    func addSession(_ session: Session) {
        session.sortIndex = sessions.count
        sessions.append(session)
    }

    /// Sessions in their persisted, stable order. Never rely on
    /// `sessions`'s raw collection order — SwiftData does not guarantee it
    /// survives a save/refetch cycle.
    var orderedSessions: [Session] {
        sessions.sorted { $0.sortIndex < $1.sortIndex }
    }
}
