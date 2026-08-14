import Foundation
import SwiftData

/// Shared get-or-create logic for the permanent per-exercise history
/// record. Both set-based and block-result-based recording use this so
/// there is exactly one place that decides how an ExercisePerformanceProfile
/// comes into existence.
enum PerformanceProfileStore {
    static func exerciseProfile(
        for exercise: Exercise,
        in performanceProfile: PerformanceProfile,
        context: ModelContext
    ) -> ExercisePerformanceProfile {
        if let existing = performanceProfile.profile(for: exercise) {
            return existing
        }
        let created = ExercisePerformanceProfile()
        // `exercise` has no declared inverse collection, so a direct
        // assignment carries no dual-mutation risk. `performanceProfile`
        // does have one — established below via the single owning side.
        created.exercise = exercise
        context.insert(created)
        performanceProfile.addExerciseProfile(created)
        return created
    }
}
