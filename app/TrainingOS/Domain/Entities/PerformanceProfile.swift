import Foundation
import SwiftData

/// Permanent memory, one per User, scoped to no program. This is the
/// container the handoff calls out as "must never be scoped to one
/// program" — it survives every ProgramDefinition/ProgramInstance it was
/// ever fed by.
///
/// `activityProfiles`/`benchmarkProfiles` are Stage 3C additions
/// (`PERFORMANCE_PROFILE_MODALITY_REVIEW.md` §2) — siblings of
/// `exerciseProfiles`, not replacements. `ExercisePerformanceProfile`
/// itself is unchanged.
@Model
final class PerformanceProfile {
    @Attribute(.unique) var id: UUID
    var user: User?

    @Relationship(deleteRule: .cascade, inverse: \ExercisePerformanceProfile.performanceProfile)
    var exerciseProfiles: [ExercisePerformanceProfile] = []

    @Relationship(deleteRule: .cascade, inverse: \ActivityPerformanceProfile.performanceProfile)
    var activityProfiles: [ActivityPerformanceProfile] = []

    @Relationship(deleteRule: .cascade, inverse: \BenchmarkPerformanceProfile.performanceProfile)
    var benchmarkProfiles: [BenchmarkPerformanceProfile] = []

    /// FUNCTIONAL FITNESS PROGRAMMING AUTHORITY V2, Section 5: a further
    /// sibling of the three relationships above, not a replacement for
    /// any of them.
    @Relationship(deleteRule: .cascade, inverse: \MovementCapabilityProfile.performanceProfile)
    var movementCapabilities: [MovementCapabilityProfile] = []

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

    /// The only way application code should attach an
    /// ActivityPerformanceProfile. Mutates exactly one side; SwiftData
    /// maintains the declared inverse.
    func addActivityProfile(_ activityProfile: ActivityPerformanceProfile) {
        activityProfiles.append(activityProfile)
    }

    /// The only way application code should attach a
    /// BenchmarkPerformanceProfile. Mutates exactly one side; SwiftData
    /// maintains the declared inverse.
    func addBenchmarkProfile(_ benchmarkProfile: BenchmarkPerformanceProfile) {
        benchmarkProfiles.append(benchmarkProfile)
    }

    func profile(for exercise: Exercise) -> ExercisePerformanceProfile? {
        exerciseProfiles.first { $0.exercise?.id == exercise.id }
    }

    /// `context` matches `ActivityPerformanceProfile.performanceContext`
    /// exactly (both `nil` means "the general profile for this activity") —
    /// never conflates a general Running profile with a "5K" one unless a
    /// caller explicitly asks for the general one by passing `nil`.
    func activityProfile(for activityType: ActivityType, context: String? = nil) -> ActivityPerformanceProfile? {
        activityProfiles.first { $0.activityType == activityType && $0.performanceContext == context }
    }

    func benchmarkProfile(for benchmark: BenchmarkDefinition) -> BenchmarkPerformanceProfile? {
        benchmarkProfiles.first { $0.benchmark?.id == benchmark.id }
    }

    /// FUNCTIONAL FITNESS PROGRAMMING AUTHORITY V2, Section 28
    /// (migration-safe): a `nil` return here — no row exists yet for this
    /// `(performanceProfile, exercise)` pair, whether because the profile
    /// predates this feature or the athlete simply never recorded one —
    /// must be read by every caller as `MovementProficiency.unknown`,
    /// never inferred as `.workoutReady`. See
    /// `MovementRoleExerciseSelector`'s own capability-gating call site.
    func movementCapability(for exercise: Exercise) -> MovementCapabilityProfile? {
        movementCapabilities.first { $0.exercise?.id == exercise.id }
    }

    /// The only way application code should attach a
    /// MovementCapabilityProfile. Mutates exactly one side; SwiftData
    /// maintains the declared inverse.
    func addMovementCapability(_ capability: MovementCapabilityProfile) {
        movementCapabilities.append(capability)
    }
}
