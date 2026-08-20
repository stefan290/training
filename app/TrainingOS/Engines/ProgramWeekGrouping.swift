import Foundation

/// Pure, deterministic bucketing of a `ProgramInstance`'s real,
/// already-materialized `Session`s into 7-day windows from
/// `instance.startDate` — the only concept of "week" available (a
/// `Session` carries a real calendar date; the template graph itself has
/// none). Business logic belongs here, not in `ProgramDetailView`
/// (CLAUDE.md rule 5).
enum ProgramWeekGrouping {
    /// The smallest `weekIndex` with no real materialized Sessions yet —
    /// "which week is next to roll forward," and equally, for read-only
    /// display, "which week is currently in progress." Moved here from
    /// `RollTacticalWindowUseCase` (Stage 7) so a read-only UI can show
    /// honest tactical-window status without a second week-counting
    /// mechanism.
    static func nextWeekIndex(for instance: ProgramInstance) -> Int {
        var week = 0
        while !realSessions(in: instance, forWeek: week).isEmpty {
            week += 1
        }
        return week
    }

    static func realSessions(in instance: ProgramInstance, forWeek weekIndex: Int) -> [Session] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: instance.startDate)
        return instance.sessions.filter { session in
            guard let date = session.day?.date else { return false }
            let daysSinceStart = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? -1
            guard daysSinceStart >= 0 else { return false }
            return daysSinceStart / 7 == weekIndex
        }.sorted { lhs, rhs in
            let lhsDate = lhs.day?.date ?? .distantPast
            let rhsDate = rhs.day?.date ?? .distantPast
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return lhs.sortIndex < rhs.sortIndex
        }
    }
}
