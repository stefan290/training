import Foundation
import SwiftData

/// Builds `FunctionalFitnessDecisionEngine`'s `[VarianceExposureRecord]`
/// input from a `ProgramInstance`'s *actual* history — never from a
/// scheduled-but-not-yet-attempted prescription (§27: "do not assume a
/// scheduled workout that was skipped counts as completed exposure").
/// Lives in `Application/UseCases/`, not `Engines/`, because it touches
/// `@Model` types directly — `FunctionalFitnessDecisionEngine` itself
/// stays pure.
enum FunctionalFitnessExposureHistoryBuilder {
    /// Only a `Session` whose `status == .completed` contributes, and
    /// only a `WorkoutBlock` that carries *both* a real
    /// `FunctionalFitnessResult` (proof it was actually attempted) and
    /// its originating `FunctionalFitnessPrescription` (the stimulus it
    /// was attempted against) — a scheduled-but-untouched or explicitly
    /// skipped Session contributes nothing, exactly §27's requirement.
    static func build(fromCompletedSessionsIn instance: ProgramInstance) -> [VarianceExposureRecord] {
        instance.sessions
            .filter { $0.status == .completed }
            .flatMap { $0.orderedBlocks }
            .compactMap { block -> VarianceExposureRecord? in
                guard
                    let result = block.functionalFitnessResult,
                    let prescription = block.functionalFitnessPrescription
                else { return nil }
                let stimulus = prescription.stimulus
                return VarianceExposureRecord(
                    date: result.completedAt,
                    durationDomain: stimulus.targetDurationDomain,
                    loading: stimulus.loading,
                    movementModalityMix: stimulus.movementModalityMix,
                    movementFunctionsUsed: stimulus.movementFunctions,
                    skillDemand: stimulus.skillDemand,
                    wasHighIntensity: stimulus.intensity == .high
                )
            }
            .sorted { $0.date < $1.date }
    }
}
