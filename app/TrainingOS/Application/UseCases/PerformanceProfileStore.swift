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

    /// Stage 3C addition — the `ActivityType` sibling of `exerciseProfile`
    /// above, same get-or-create shape. `performanceContext` distinguishes
    /// a specific racing context (e.g. `"5K"`) from an activity's general
    /// history; `nil` (the default) is the general profile.
    static func activityProfile(
        for activityType: ActivityType,
        performanceContext: String? = nil,
        in performanceProfile: PerformanceProfile,
        context: ModelContext
    ) -> ActivityPerformanceProfile {
        if let existing = performanceProfile.activityProfile(for: activityType, context: performanceContext) {
            return existing
        }
        let created = ActivityPerformanceProfile(activityType: activityType, performanceContext: performanceContext)
        context.insert(created)
        performanceProfile.addActivityProfile(created)
        return created
    }

    /// Stage 3C addition — the `BenchmarkDefinition` sibling of
    /// `exerciseProfile` above, same get-or-create shape.
    static func benchmarkProfile(
        for benchmark: BenchmarkDefinition,
        in performanceProfile: PerformanceProfile,
        context: ModelContext
    ) -> BenchmarkPerformanceProfile {
        if let existing = performanceProfile.benchmarkProfile(for: benchmark) {
            return existing
        }
        let created = BenchmarkPerformanceProfile()
        // `benchmark` has no declared inverse collection read by
        // application code (only the delete-rule-only
        // `BenchmarkDefinition.performanceProfiles` exists), so a direct
        // assignment carries no dual-mutation risk — same reasoning as
        // `exercise` above.
        created.benchmark = benchmark
        context.insert(created)
        performanceProfile.addBenchmarkProfile(created)
        return created
    }
}
