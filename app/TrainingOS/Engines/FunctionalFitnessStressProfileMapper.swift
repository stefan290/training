import Foundation

/// Pure, deterministic mapping from a resolved `Stimulus` to a
/// `TrainingStressProfile` (§31) — coarse classifications only, never a
/// fabricated numeric "stress score" (`TrainingStressProfile`'s own doc
/// comment: "there is no formula here, and none should be added under
/// the guise of more precision").
enum FunctionalFitnessStressProfileMapper {
    static func map(stimulus: Stimulus) -> TrainingStressProfile {
        let overall = loadLevel(from: stimulus.intensity)
        let systemic = loadLevel(from: stimulus.systemicDemand)
        let loadingLevel = loadLevel(from: stimulus.loading)

        let hasLowerBodyFunction = stimulus.movementFunctions.contains { [.squatLoaded, .hingeLoaded].contains($0) }
        let hasUpperBodyFunction = stimulus.movementFunctions.contains { [.pressLoaded, .gymnasticsPull, .gymnasticsPush].contains($0) }
        let hasLocomotionFunction = stimulus.movementFunctions.contains { [.monostructural, .locomotion].contains($0) }

        return TrainingStressProfile(
            overallIntensity: overall,
            systemicDemand: systemic,
            lowerBodyLoad: hasLowerBodyFunction ? loadingLevel : .none,
            upperBodyLoad: hasUpperBodyFunction ? loadingLevel : .none,
            // Locomotion/monostructural work (running, rowing, jumping) is
            // the only Functional Fitness movement family this pass treats
            // as carrying meaningful impact loading — a coarse, explicit
            // simplification, not a biomechanical claim.
            impactLoading: hasLocomotionFunction ? .moderate : .none,
            // Metabolic demand mirrors overall intensity — this pass has
            // no independent signal to distinguish them (both stem from
            // the same `IntensityClassification` input).
            metabolicDemand: overall,
            durationClassification: stimulus.targetDurationDomain,
            modality: nil,
            // Recovery demand mirrors systemic demand — same reasoning.
            recoveryDemand: systemic
        )
    }

    private static func loadLevel(from intensity: IntensityClassification) -> LoadLevel {
        switch intensity {
        case .low: return .low
        case .moderate: return .moderate
        case .high: return .high
        }
    }

    private static func loadLevel(from systemicDemand: SystemicDemandLevel) -> LoadLevel {
        switch systemicDemand {
        case .low: return .low
        case .moderate: return .moderate
        case .high: return .high
        }
    }

    private static func loadLevel(from loading: LoadingClassification) -> LoadLevel {
        switch loading {
        case .bodyweightOnly: return .low
        case .light: return .low
        case .moderate: return .moderate
        case .heavy: return .high
        }
    }
}
