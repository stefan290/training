import Foundation

/// Stage CP.1: pure, deterministic mapping from a real, already-resolved
/// `IntervalPrescription`'s programmed values to a `TrainingStressProfile`
/// — mirrors `FunctionalFitnessStressProfileMapper`'s own discipline
/// exactly (coarse categorical classification only, never a fabricated
/// numeric score). Observes the resolved prescription only; never
/// influences `IntervalProgressionEngine`'s own output.
enum IntervalTrainingStressMapper {
    /// Always produces a profile — `activityType` alone is always real and
    /// non-optional (`IntervalPrescription.activityType`).
    static func map(
        activityType: ActivityType,
        intervalCount: Int,
        workDurationSeconds: Int?,
        recoveryDurationSeconds: Int?,
        workIntensity: IntensityTarget?
    ) -> TrainingStressProfile {
        // A repeated work/recovery structure is, by construction, more
        // systemically/metabolically demanding than a single continuous
        // effort of the same total duration — a real, structural fact
        // about what "intervals" means (never true of a single steady
        // effort), not a guess layered on top of one. Escalated further
        // only when a real zone value on this prescription says so.
        let structuralFloor: LoadLevel = intervalCount > 1 ? .moderate : .low
        let zoneIntensity = ActivityTypeStressCharacteristics.intensityLevel(from: workIntensity)
        let intensity = worstCase([zoneIntensity, structuralFloor].compactMap { $0 })

        return TrainingStressProfile(
            overallIntensity: intensity,
            systemicDemand: intensity,
            lowerBodyLoad: ActivityTypeStressCharacteristics.lowerBodyLoad(for: activityType),
            upperBodyLoad: ActivityTypeStressCharacteristics.upperBodyLoad(for: activityType),
            impactLoading: ActivityTypeStressCharacteristics.impactLoading(for: activityType),
            metabolicDemand: intensity,
            durationClassification: durationDomain(intervalCount: intervalCount, workDurationSeconds: workDurationSeconds, recoveryDurationSeconds: recoveryDurationSeconds),
            modality: activityType,
            recoveryDemand: intensity
        )
    }

    /// Reuses `FunctionalFitnessStimulusValidator`'s own existing duration-
    /// domain thresholds against the total programmed time (work + recovery,
    /// across every interval) — never a second, competing threshold table.
    /// A distance-only prescription (e.g. "5x1km," no duration resolved)
    /// is the genuinely-uncertain case — documented conservative `.medium`
    /// default, since total time can't be honestly estimated without a
    /// pace this mapper has no authority to invent.
    private static func durationDomain(intervalCount: Int, workDurationSeconds: Int?, recoveryDurationSeconds: Int?) -> DurationDomain {
        guard let workDurationSeconds else { return .medium }
        let totalSeconds = intervalCount * (workDurationSeconds + (recoveryDurationSeconds ?? 0))
        return FunctionalFitnessStimulusValidator.durationDomain(forEstimatedSeconds: totalSeconds)
    }

    private static func worstCase(_ levels: [LoadLevel]) -> LoadLevel {
        levels.max { $0.ordinal < $1.ordinal } ?? .low
    }
}
