import Foundation
import SwiftData
import Observation

/// Loads today's Sessions. Fetches broadly and filters/sorts in Swift
/// rather than a SwiftData `#Predicate` — safe and simple at seed-data
/// scale; replace with a predicate-based `FetchDescriptor` once real
/// datasets make a full-table scan wasteful. See ARCHITECTURE.md.
@Observable
final class TodayViewModel {
    private(set) var sessions: [Session] = []

    func load(modelContext: ModelContext) {
        let days = (try? modelContext.fetch(FetchDescriptor<Day>())) ?? []
        let startOfToday = Calendar.current.startOfDay(for: Date())
        guard let today = days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: startOfToday) }) else {
            sessions = []
            return
        }
        sessions = today.orderedSessions
    }
}
