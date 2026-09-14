import Foundation
import SwiftData
@testable import TrainingOS

/// Stage 10R.1C, revised by Dogfood Round 1 (Finding 1): shared
/// test-fixture helper — completes every outstanding required source RM
/// calibration for `phase`'s selected mix with a fixed, arbitrary value
/// (never an estimate; just a deterministic test number). This is the
/// test-fixture equivalent of a real user finishing "Set your starting
/// weights."
///
/// **Behavior changed by Dogfood Round 1:** `StartPhaseUseCase.start` no
/// longer defers materialization for a component with missing
/// calibration — every component's Sessions/prescriptions already exist
/// (with the affected slot's weight honestly unresolved) by the time this
/// helper runs. This helper now only records the calibration and resolves
/// those already-materialized dependent prescriptions
/// (`ResolveCalibrationDependentPrescriptionsUseCase`) — it never
/// materializes or schedules anything itself, since `start()` already did.
/// Returns `[]` always (kept for existing call-site compatibility, e.g.
/// `result.scheduleProposal.placements.append(contentsOf: proposals.flatMap(\.placements))`,
/// which is now correctly a no-op — `start()`'s own single combined
/// scheduling pass already placed every component together).
@MainActor
enum CalibrationTestSupport {
    @discardableResult
    static func completeAnyPendingCalibrationAndMaterialize(
        phase: TrainingPhase,
        ownerUserID: UUID? = nil,
        performanceProfile: PerformanceProfile?,
        availability: UserAvailability,
        materializationContext: TacticalMaterializationContext,
        asOf: Date = Date(),
        rmKilograms: Double = 100,
        // Dogfood Round 1 — Final Close (Finding 1 correction): real
        // per-exercise equipment resolution now happens inside
        // `ResolveCalibrationDependentPrescriptionsUseCase` itself, from
        // a real `UserProfile` — `nil` here preserves every existing
        // caller's exact prior behavior (the same TRAININGOS_DESIGNED
        // barbell/2.5kg fallback), while a test proving differentiated
        // equipment resolution can pass a real one.
        userProfile: UserProfile? = nil,
        context: ModelContext
    ) throws -> [ScheduleProposal] {
        guard let mix = phase.selectedTrainingMix ?? phase.recommendedTrainingMix else { return [] }
        for component in mix.orderedComponents {
            guard let instance = component.programInstance, let definition = instance.programDefinition else { continue }
            let required = RequiredSourceCalibrationsUseCase.stillRequired(for: definition, instance: instance)
            guard !required.isEmpty else { continue }
            for requirement in required {
                try ResolveCalibrationDependentPrescriptionsUseCase.resolve(
                    exercise: requirement.exercise, rmType: requirement.rmType, kilograms: rmKilograms,
                    instance: instance, userProfile: userProfile,
                    enteredAt: asOf, modelContext: context
                )
            }
        }
        return []
    }
}
