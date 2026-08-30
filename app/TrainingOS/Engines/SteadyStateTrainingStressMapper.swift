import Foundation

/// Stage CP.1: pure, deterministic mapping from a real, already-resolved
/// `SteadyStatePrescription`'s programmed values to a `TrainingStressProfile`
/// — mirrors `FunctionalFitnessStressProfileMapper`'s own discipline
/// exactly (coarse categorical classification only, never a fabricated
/// numeric score). Observes the resolved prescription only; never
/// influences `SteadyStateProgressionEngine`'s own output.
enum SteadyStateTrainingStressMapper {
    /// Always produces a profile — `activityType` alone is always real and
    /// non-optional (`SteadyStatePrescription.activityType`), so there is
    /// always at least body-region/impact signal even when duration/
    /// intensity are genuinely unresolved.
    static func map(
        activityType: ActivityType,
        durationSeconds: Int?,
        primaryIntensity: IntensityTarget?
    ) -> TrainingStressProfile {
        // Genuinely uncertain without a real zone value on this
        // prescription — conservative `.moderate`, never `.none` (would
        // silently disable InterferenceAvoidanceRule's protection) and
        // never `.high` (would over-trigger).
        let intensity = ActivityTypeStressCharacteristics.intensityLevel(from: primaryIntensity) ?? .moderate

        return TrainingStressProfile(
            overallIntensity: intensity,
            systemicDemand: intensity,
            lowerBodyLoad: ActivityTypeStressCharacteristics.lowerBodyLoad(for: activityType),
            upperBodyLoad: ActivityTypeStressCharacteristics.upperBodyLoad(for: activityType),
            impactLoading: ActivityTypeStressCharacteristics.impactLoading(for: activityType),
            metabolicDemand: intensity,
            durationClassification: durationDomain(forSeconds: durationSeconds),
            modality: activityType,
            recoveryDemand: intensity
        )
    }

    /// Reuses `FunctionalFitnessStimulusValidator`'s own existing
    /// short(<5min)/medium(5-15min)/long(>15min) thresholds — never a
    /// second, competing threshold table for the same concept.
    /// `durationSeconds == nil` (a distance-only prescription, e.g. "10km,
    /// however long that takes") is the genuinely-uncertain case —
    /// documented conservative `.medium` default.
    private static func durationDomain(forSeconds seconds: Int?) -> DurationDomain {
        guard let seconds else { return .medium }
        return FunctionalFitnessStimulusValidator.durationDomain(forEstimatedSeconds: seconds)
    }
}
