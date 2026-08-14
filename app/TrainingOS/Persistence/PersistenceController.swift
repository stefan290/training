import Foundation
import SwiftData

/// Single source of truth for the SwiftData schema and container
/// construction. Nothing outside this file should construct a
/// `ModelContainer` or list the `@Model` types by hand — that keeps the
/// schema from drifting between the app target, previews and tests.
enum PersistenceController {
    /// Every persisted entity in the app. Add new `@Model` types here as
    /// they're introduced; SwiftData will refuse to open a store that
    /// doesn't match this list.
    static let schema = Schema([
        User.self,
        UserProfile.self,
        Goal.self,
        TrainingPlan.self,
        TrainingPhase.self,
        ProgramDefinition.self,
        TrainingWeek.self,
        ProgramInstance.self,
        Day.self,
        Session.self,
        WorkoutBlock.self,
        Exercise.self,
        ExerciseAlias.self,
        ExercisePrescription.self,
        SetPrescription.self,
        SetResult.self,
        WorkoutResult.self,
        PerformanceProfile.self,
        ExercisePerformanceProfile.self,
        PersonalRecord.self,
        Recommendation.self,
    ])

    /// The app's on-disk, offline-first store. Local storage is
    /// authoritative per handoff section 12 — there is no network
    /// precondition to construct or use this container.
    static func makeAppContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create the on-disk ModelContainer: \(error)")
        }
    }

    /// An isolated in-memory container for SwiftUI previews and unit tests.
    /// Every test that needs persistence should build its own instance so
    /// tests never share state.
    static func makeInMemoryContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create the in-memory ModelContainer: \(error)")
        }
    }
}
