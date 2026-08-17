import Foundation

/// Pure, deterministic bucketing of a `ProgramInstance`'s real,
/// already-materialized `Session`s into 7-day windows from
/// `instance.startDate` — the only concept of "week" available (a
/// `Session` carries a real calendar date; the template graph itself has
/// none). Business logic belongs here, not in `ProgramDetailView`
/// (CLAUDE.md rule 5).
enum ProgramWeekGrouping {
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
