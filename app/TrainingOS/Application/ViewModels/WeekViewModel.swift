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

    /// A deterministic label for the "return to the current week"
    /// control — derived purely from `weekOffset`, never from which
    /// direction the last navigation happened to come from. Only
    /// `weekOffset == 0` is ever "This Week"; exactly one step away is
    /// unambiguously "Next"/"Previous Week"; anything further shows the
    /// real calendar date range instead of a relative word that would
    /// otherwise misdescribe which week is actually on screen (e.g.
    /// calling week 3 "Current Week" merely because the user arrived via
    /// the forward arrow).
    var weekNavigationLabel: String {
        switch weekOffset {
        case 0: return "This Week"
        case 1: return "Next Week"
        case -1: return "Previous Week"
        default:
            guard let start = days.first?.date, let end = days.last?.date else { return "" }
            return "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }

    /// True only when every one of the seven days is empty — the signal
    /// this week hasn't been materialized at all yet, as opposed to an
    /// ordinary week that legitimately has one or more rest days mixed in
    /// with real Sessions (Part T/V — there is no separate "planned rest
    /// day" marker in the domain model to read instead).
    var weekHasNoMaterializedData: Bool { days.allSatisfy { $0.sessions.isEmpty } }

    /// `referenceDate` defaults to the real current moment for every
    /// existing caller — the injection point exists solely so a
    /// deterministic date can be supplied in tests (mirrors
    /// `TodayViewModel.load`'s identical discipline).
    func load(modelContext: ModelContext, referenceDate now: Date = Date()) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let referenceDate = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: today),
              let weekStart = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start else {
            days = []
            return
        }

        let allDays = (try? modelContext.fetch(FetchDescriptor<Day>())) ?? []
        var result: [WeekDay] = []
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            // More than one `Day` row can legitimately share a calendar
            // date — see `TodayViewModel.load`'s identical fix/rationale
            // (`AcceptScheduleProposalUseCase.accept` empties a Session's
            // naive materialized Day without deleting it). Aggregate every
            // matching Day's Sessions, never just the first found.
            let matchingDays = allDays.filter { calendar.isDate($0.date, inSameDayAs: date) }
            let sessions = matchingDays.flatMap(\.orderedSessions).sorted { $0.sortIndex < $1.sortIndex }
            result.append(WeekDay(date: date, sessions: sessions))
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
