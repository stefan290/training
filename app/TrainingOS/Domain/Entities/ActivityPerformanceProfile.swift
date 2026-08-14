import Foundation
import SwiftData

/// Permanent, program-independent history for one activity — the
/// endurance-modality sibling of `ExercisePerformanceProfile`, added
/// without changing that type at all (`PERFORMANCE_PROFILE_MODALITY_REVIEW.md`
/// §2). Survives every `ProgramInstance`/`ProgramDefinition` it was ever
/// fed by, exactly like its strength-side sibling.
///
/// `performanceContext` distinguishes a specific racing/training context
/// (e.g. `"5K"`) from the activity's general history — Stage 3C §21's
/// explicit requirement: "do not make '5K' the same identity as generic
/// Running activity unless the model explicitly distinguishes performance
/// context." `nil` means the general, all-distance profile for that
/// `ActivityType`.
@Model
final class ActivityPerformanceProfile {
    @Attribute(.unique) var id: UUID
    var performanceProfile: PerformanceProfile?
    var activityType: ActivityType
    var performanceContext: String?
    var lastPerformedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \SteadyStateResult.activityPerformanceProfile)
    var steadyStateResults: [SteadyStateResult] = []

    @Relationship(deleteRule: .cascade, inverse: \IntervalResult.activityPerformanceProfile)
    var intervalResults: [IntervalResult] = []

    @Relationship(deleteRule: .cascade, inverse: \PersonalRecord.activityPerformanceProfile)
    var personalRecords: [PersonalRecord] = []

    init(
        id: UUID = UUID(),
        activityType: ActivityType,
        performanceContext: String? = nil,
        lastPerformedAt: Date? = nil
    ) {
        self.id = id
        self.activityType = activityType
        self.performanceContext = performanceContext
        self.lastPerformedAt = lastPerformedAt
    }

    /// The only way application code should attach a SteadyStateResult.
    /// Mutates exactly one side (this array); SwiftData maintains
    /// `result.activityPerformanceProfile` from the declared inverse.
    func addSteadyStateResult(_ result: SteadyStateResult) {
        steadyStateResults.append(result)
    }

    /// The only way application code should attach an IntervalResult.
    /// Mutates exactly one side; SwiftData maintains the declared inverse.
    func addIntervalResult(_ result: IntervalResult) {
        intervalResults.append(result)
    }

    /// The only way application code should attach a PersonalRecord.
    /// Mutates exactly one side; SwiftData maintains the declared inverse.
    func addPersonalRecord(_ record: PersonalRecord) {
        personalRecords.append(record)
    }
}
