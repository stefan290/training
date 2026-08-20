import Foundation
import SwiftData

enum PhaseTransitionError: Error, Equatable {
    /// Mirrors `StartPhaseError.phaseNotPlanned`'s discipline — a
    /// transition only ever runs from a genuinely running phase, never
    /// re-runs on one already ended.
    case outgoingPhaseNotActive
    /// `TrainingPlan.orderedPhases` has nothing after `outgoingPhase` —
    /// never fabricated; the caller must extend the plan first
    /// (`LongTermPlanner.reviseStrategicPlan`, out of this use case's scope).
    case noNextPhaseInPlan
}

/// Stage 7 (Tactical Planning Orchestration), Slice 3 — closes the
/// runtime gap `RollTacticalWindowUseCase`'s own doc comment already
/// named: "extending a Steady State component beyond its own generated
/// ProgramDefinition... would mean generating a new ProgramInstance,
/// which is a phase-transition-shaped event... not built this pass."
///
/// Orchestration only, no new mechanism, no new domain rule: ends the
/// outgoing phase exactly the way `PhaseStatus`'s own documented
/// PLANNED -> ACTIVE -> COMPLETED lifecycle already describes, finds the
/// next phase via `TrainingPlan.orderedPhases` (already well-defined —
/// `TrainingPhase.swift`'s own doc comment: "the phase *sequencing*
/// concept... needed no new entity — `TrainingPlan.orderedPhases` already
/// provides it"), and starts it through the exact same
/// `StartPhaseUseCase.start` entry point every phase start already uses
/// — never a second phase-start mechanism.
///
/// **Never touches history.** Only `TrainingPhase.status`/`ProgramInstance.status`
/// are mutated on the OUTGOING phase — never its Sessions, SetResults,
/// PersonalRecords, PerformanceProfiles, or PlannerDecisions (CLAUDE.md
/// rule 1). `ProgramInstance.sessions` relates back with `.nullify`
/// precisely so this is safe.
///
/// **Never carries instance-specific state forward.** The next phase's
/// components are always not-yet-instantiated (fresh `TrainingMixComponent`s
/// from whichever `TrainingMix` the caller selected for the new phase),
/// so `StartPhaseUseCase.start` always creates brand-new `ProgramInstance`s
/// for it — `SlotSelectionOverride`/`ActivitySelectionOverride` are
/// `ProgramInstance`-scoped by construction and never referenced by the
/// new instances. The one thing that IS carried forward is real,
/// legitimately global user history — the same `PerformanceProfile`
/// object is simply passed through unchanged, exactly as it would be for
/// any other `StartPhaseUseCase.start` call; it was never phase-scoped to
/// begin with, so there is nothing to specially transfer.
enum TransitionPhaseUseCase {
    struct Result {
        var completedPhase: TrainingPhase
        var nextPhase: TrainingPhase
        var startResult: StartPhaseUseCase.Result
    }

    @discardableResult
    static func transition(
        from outgoingPhase: TrainingPhase,
        toNextPhaseWithMix nextMix: TrainingMix,
        asOf: Date,
        ownerUserID: UUID,
        performanceProfile: PerformanceProfile?,
        availability: UserAvailability,
        materializationContext: TacticalMaterializationContext,
        context: ModelContext
    ) throws -> Result {
        guard outgoingPhase.status == .active else { throw PhaseTransitionError.outgoingPhaseNotActive }
        guard let plan = outgoingPhase.plan else { throw PhaseTransitionError.noNextPhaseInPlan }
        let ordered = plan.orderedPhases
        guard let currentIndex = ordered.firstIndex(where: { $0.id == outgoingPhase.id }),
              ordered.indices.contains(currentIndex + 1) else {
            throw PhaseTransitionError.noNextPhaseInPlan
        }
        let nextPhase = ordered[currentIndex + 1]

        outgoingPhase.status = .completed
        for instance in outgoingPhase.programInstances {
            instance.status = .completed
        }

        let decision = PlannerDecision(
            decidedAt: asOf, decisionType: .phaseSelected, source: .systemRecommended,
            reasonCode: .phaseSelectedForGoal,
            factors: ["outgoingPhaseID": outgoingPhase.id.uuidString, "outgoingPhaseType": outgoingPhase.type.rawValue, "nextPhaseType": nextPhase.type.rawValue],
            explanation: "\(outgoingPhase.type.rawValue) phase completed; transitioning to \(nextPhase.type.rawValue) with \(nextMix.name).",
            phase: nextPhase, trainingMix: nextMix
        )
        context.insert(decision)

        let startResult = try StartPhaseUseCase.start(
            phase: nextPhase, mix: nextMix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: performanceProfile, availability: availability,
            materializationContext: materializationContext, context: context
        )

        return Result(completedPhase: outgoingPhase, nextPhase: nextPhase, startResult: startResult)
    }
}
