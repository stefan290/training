import Foundation
import SwiftData

/// Permanent memory, one per User, scoped to no program. This is the
/// container the handoff calls out as "must never be scoped to one
/// program" — it survives every ProgramDefinition/ProgramInstance it was
/// ever fed by.
@Model
final class PerformanceProfile {
    @Attribute(.unique) var id: UUID
    var user: User?

    @Relationship(deleteRule: .cascade, inverse: \ExercisePerformanceProfile.performanceProfile)
    var exerciseProfiles: [ExercisePerformanceProfile] = []

    init(id: UUID = UUID()) {
        self.id = id
    }

    /// The only way application code should attach an
    /// ExercisePerformanceProfile. Mutates exactly one side (this array);
    /// SwiftData maintains `exerciseProfile.performanceProfile` from the
    /// declared inverse.
    func addExerciseProfile(_ exerciseProfile: ExercisePerformanceProfile) {
        exerciseProfiles.append(exerciseProfile)
    }

    func profile(for exercise: Exercise) -> ExercisePerformanceProfile? {
        exerciseProfiles.first { $0.exercise?.id == exercise.id }
    }
}
