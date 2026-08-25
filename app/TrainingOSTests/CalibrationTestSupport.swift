import Foundation
import SwiftData
@testable import TrainingOS

/// Stage 10R.1C: shared test-fixture helper — completes every outstanding
/// required source RM calibration for `phase`'s selected mix with a fixed,
/// arbitrary value (never an estimate; just a deterministic test number)
/// and performs the deferred first-window materialization. This is the
/// test-fixture equivalent of a real user finishing "Set your starting
/// weights": every pre-existing test that previously assumed
/// `StartPhaseUseCase.start` alone produced real materialized Sessions
/// for an `.rmBased` component now needs this one extra step, since that
/// materialization is deliberately deferred until calibration exists.
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
        context: ModelContext
    ) throws -> [ScheduleProposal] {
        guard let mix = phase.selectedTrainingMix ?? phase.recommendedTrainingMix else { return [] }
        var proposals: [ScheduleProposal] = []
        for component in mix.orderedComponents {
            guard let instance = component.programInstance, let definition = instance.programDefinition else { continue }
            let required = RequiredSourceCalibrationsUseCase.stillRequired(for: definition, instance: instance)
            guard !required.isEmpty else { continue }
            for requirement in required {
                RecordSourceRMCalibrationUseCase.record(
                    exercise: requirement.exercise, rmType: requirement.rmType, kilograms: rmKilograms,
                    for: instance, modelContext: context
                )
            }
            // One explicit save for the whole batch, after every required
            // row is recorded and before materialization is attempted —
            // see `RecordSourceRMCalibrationUseCase.record`'s own doc
            // comment for why NOT saving per-row matters.
            try context.save()
            // `ownerUserID` defaults to the instance's own already-stored
            // value — the caller need not separately track/thread it.
            let proposal = try StartPhaseUseCase.materializeOnceCalibrationComplete(
                component: component, instance: instance, phase: phase, mix: mix, asOf: asOf,
                ownerUserID: ownerUserID ?? instance.ownerUserID,
                performanceProfile: performanceProfile, availability: availability,
                materializationContext: materializationContext, context: context
            )
            proposals.append(proposal)
        }
        return proposals
    }
}
