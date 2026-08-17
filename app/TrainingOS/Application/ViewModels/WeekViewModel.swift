import Foundation
import SwiftData
import Observation

/// Loads the seven days of one calendar week from the real `Day`/`Session`
/// graph — never a second, UI-only schedule (Part AH.7/AH.16). Fetches
/// broadly and filters in Swift, matching `TodayViewModel`'s own stated
/// tradeoff at seed-data scale.
@Observable
final class WeekViewModel {
    struct WeekDay: Identifiable {
        let id = UUID()
        let date: Date
        let sessions: [Session]
    }

    /// 0 = the calendar week containing today; +1/-1 = next/previous week.
    /// Browsing this never mutates anything — it only changes which real,
    /// already-persisted Sessions are being displayed (Part T).
    private(set) var weekOffset: Int = 0
    private(set) var days: [WeekDay] = []

    var isCurrentWeek: Bool { weekOffset == 0 }

    /// True only when every one of the seven days is empty — the signal
    /// this week hasn't been materialized at all yet, as opposed to an
    /// ordinary week that legitimately has one or more rest days mixed in
    /// with real Sessions (Part T/V — there is no separate "planned rest
    /// day" marker in the domain model to read instead).
    var weekHasNoMaterializedData: Bool { days.allSatisfy { $0.sessions.isEmpty } }

    func load(modelContext: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let referenceDate = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: today),
              let weekStart = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start else {
            days = []
            return
        }

        let allDays = (try? modelContext.fetch(FetchDescriptor<Day>())) ?? []
        var result: [WeekDay] = []
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            let matchingDay = allDays.first { calendar.isDate($0.date, inSameDayAs: date) }
            result.append(WeekDay(date: date, sessions: matchingDay?.orderedSessions ?? []))
        }
        days = result
    }

    func goToPreviousWeek(modelContext: ModelContext) {
        weekOffset -= 1
        load(modelContext: modelContext)
    }

    func goToNextWeek(modelContext: ModelContext) {
        weekOffset += 1
        load(modelContext: modelContext)
    }

    func goToCurrentWeek(modelContext: ModelContext) {
        weekOffset = 0
        load(modelContext: modelContext)
    }
}
