import Foundation
import SwiftData
import Observation

/// Loads every ExercisePerformanceProfile for the current user, most
/// recently trained first — the permanent record the rest of the app
/// (including a future Progress tab with real detail screens) reads from.
@Observable
final class ProgressViewModel {
    private(set) var exerciseProfiles: [ExercisePerformanceProfile] = []

    func load(modelContext: ModelContext) {
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        let profiles = users.first?.performanceProfile?.exerciseProfiles ?? []
        exerciseProfiles = profiles.sorted {
            ($0.lastPerformedAt ?? .distantPast) > ($1.lastPerformedAt ?? .distantPast)
        }
    }
}
