import Foundation
import SwiftData

enum StartPhaseError: Error, Equatable {
    /// Never re-runs orchestration on a phase that already has it —
    /// mirrors `AcceptScheduleProposalUseCase.infeasible`'s "never
    /// silently re-apply" discipline.
    case phaseNotPlanned
    case mixHasNoComponents
    /// Every component's `proposeProgram` call produced zero executable
    /// candidates — nothing was materialized, nothing was scheduled.
    case noExecutableComponents
}

/// Additional per-system inputs `StartPhaseUseCase`/`RollTacticalWindowUseCase`
/// cannot derive on their own — threaded through explicitly rather than
/// guessed, matching every materializer's own "the caller supplies what
/// the template graph itself cannot know" contract.
struct TacticalMaterializationContext {
    var equipmentProfile: EquipmentProfile
    /// Stage 7 addition: the pool `ResolveProgramInstanceExerciseSlotsUseCase`
    /// draws from to resolve a Hypertrophy/Powerlifting `ExerciseSlot` to a
    /// concrete `Exercise` at instance-creation time — the strength-family
    /// sibling of `functionalFitnessCandidateExercises` below. Never
    /// hardcoded inside the materializer/generator; supplied by the
    /// caller, same discipline as the Functional Fitness pool.
    var strengthCandidateExercises: [Exercise] = []
    var functionalFitnessCandidateExercises: [Exercise] = []
    var functionalFitnessExposureHistory: [VarianceExposureRecord] = []

    init(
        equipmentProfile: EquipmentProfile,
        strengthCandidateExercises: [Exercise] = [],
        functionalFitnessCandidateExercises: [Exercise] = [],
        functionalFitnessExposureHistory: [VarianceExposureRecord] = []
    ) {
        self.equipmentProfile = equipmentProfile
        self.strengthCandidateExercises = strengthCandidateExercises
        self.functionalFitnessCandidateExercises = functionalFitnessCandidateExercises
        self.functionalFitnessExposureHistory = functionalFitnessExposureHistory
    }
}

/// `TACTICAL_PLANNING_HANDOFF.md` §3 — orchestration only, no new
/// mechanism. Turns an accepted phase's mix into a real, running program:
/// activates the phase, attaches the mix (idempotent — never re-attaches
/// or duplicates), instantiates every not-yet-instantiated component via
/// the existing `LongTermPlanner.proposeProgram`/generator path exactly
/// as it already works today, materializes each component's first
/// honestly-executable week, and schedules + accepts the resulting real
/// Sessions via the existing `SchedulingPipeline`/`AcceptScheduleProposalUseCase`
/// — never a new generator, never a new scheduler, never a load/rep/pace
/// decision made here.
///
/// **Never depends on how the mix/phase came to be `.planned`/accepted.**
/// This works identically whether `phase`/`mix` came from seed data (this
/// pass's own manual acceptance) or a real future onboarding flow's
/// `AcceptStrategicPlanUseCase` + `SwitchTrainingModalityUseCase` calls —
/// nothing here reads anything seed-specific.
///
/// **Never fabricates ahead of what real performance data can support.**
/// Hypertrophy/Powerlifting/Interval/Functional Fitness materialize only
/// week 0 here — `StrengthMaterializer`'s own doc comment states plainly
/// that week 1+ "needs the *actual* outcome of the previous week," which
/// does not exist yet at phase start. Steady State has no such
/// dependency (`SteadyStateProgressionEngine` resolves every dimension
/// from `weekIndex` alone) and materializes its whole natural block in
/// one call, per its own documented architecture — this is a genuine
/// per-system difference, not an inconsistency. `RollTacticalWindowUseCase`
/// is what materializes week N+1 once week N's real results exist.
enum StartPhaseUseCase {
    struct Result {
        var phase: TrainingPhase
        var mix: TrainingMix
        /// Keyed by `TrainingMixComponent.id` — every component this call
        /// actually instantiated (already-instantiated components from an
        /// earlier call are skipped, never re-instantiated).
        var instancesByComponent: [UUID: ProgramInstance]
        var scheduleProposal: ScheduleProposal
    }

    @discardableResult
    static func start(
        phase: TrainingPhase,
        mix: TrainingMix,
        asOf: Date,
        ownerUserID: UUID,
        performanceProfile: PerformanceProfile?,
        availability: UserAvailability,
        materializationContext: TacticalMaterializationContext,
        context: ModelContext
    ) throws -> Result {
        guard phase.status == .planned else { throw StartPhaseError.phaseNotPlanned }
        guard !mix.orderedComponents.isEmpty else { throw StartPhaseError.mixHasNoComponents }

        // Starting a phase with this mix — whether it's the system's own
        // top recommendation (the user accepted it as-is) or an explicit
        // user-chosen alternative — is definitionally what makes it the
        // phase's `.selected` mix; `LongTermPlanner.proposeTrainingMix`'s
        // candidates are all `kind: .recommended` (comparison/proposal
        // objects only, per `TrainingMix`'s own doc comment: only a
        // `.selected` mix is ever actually scheduled). Every existing
        // `SwitchTrainingModalityUseCase.apply` caller already promotes
        // to `.selected` before calling it — this mirrors that same
        // convention rather than inventing a new one.
        let source: DecisionSource = mix.kind == .selected ? .userSelected : .systemRecommended
        mix.kind = .selected

        if mix.phase == nil {
            SwitchTrainingModalityUseCase.apply(
                mix, to: phase, asOf: asOf,
                reasonCode: source == .userSelected ? .userSelectedAlternative : .phaseSelectedForGoal, source: source,
                explanation: "\(mix.name) starts this \(phase.type.rawValue) phase.",
                decisionType: .programOrMixSelected, context: context
            )
        }
        phase.status = .active

        let primarySystem = mix.orderedComponents.first { $0.priority == .primary }?.programmingSystem
        let windowDays = TacticalWindowPolicy.windowLengthInDays(primarySystem: primarySystem, asOf: asOf, phaseEndDate: phase.endDate)
        let windowWeeks = max(1, windowDays / 7)

        var instancesByComponent: [UUID: ProgramInstance] = [:]
        var inputs: [ScheduledProgramInput] = []

        for component in mix.orderedComponents {
            guard component.programInstance == nil else { continue }
            guard let system = component.programmingSystem else { continue }

            let (candidates, _) = LongTermPlanner.proposeProgram(
                component: component, profile: performanceProfile, availability: availability, goal: phase.plan?.goal, context: context
            )
            guard let chosen = candidates.first else { continue }

            let instance = ProgramInstance(ownerUserID: ownerUserID, startDate: phase.startDate, status: .active, priority: component.priority)
            instance.programDefinition = chosen.programDefinition
            context.insert(instance)
            phase.addProgramInstance(instance)
            component.programInstance = instance

            // Resolve every ExerciseSlot to a concrete Exercise exactly
            // once, at this specific instance's creation — never inside
            // the generator (which stays user-independent) and never
            // repeated on every materialization call.
            if system == .hypertrophy || system == .powerlifting {
                ResolveProgramInstanceExerciseSlotsUseCase.resolve(
                    definition: chosen.programDefinition, candidateExercises: materializationContext.strengthCandidateExercises
                )
            }
            instancesByComponent[component.id] = instance

            let decision = PlannerDecision(
                decidedAt: asOf, decisionType: .programOrMixSelected, source: .systemRecommended,
                reasonCode: chosen.reasonCodes.first ?? .programMatchGoal,
                factors: ["programName": chosen.programDefinition.name, "componentLabel": component.label],
                explanation: "Selected \(chosen.programDefinition.name) for \(component.label).",
                phase: phase, trainingMix: mix, programInstance: instance
            )
            context.insert(decision)

            let sessions = try RollTacticalWindowUseCase.materializeFirstWindow(
                system: system, definition: chosen.programDefinition, instance: instance,
                startDate: phase.startDate, ownerUserID: ownerUserID,
                performanceProfile: performanceProfile, materializationContext: materializationContext, context: context
            )
            inputs.append(ScheduledProgramInput(component: component, sessions: sessions))
        }

        guard !inputs.isEmpty else { throw StartPhaseError.noExecutableComponents }

        // A non-primary component can materialize further out than the
        // primary system's own natural block (Steady State's whole
        // natural block, materialized in one call regardless of the
        // primary system's block length) — widen the window just enough
        // to cover every session actually being scheduled, never fewer.
        let materializedDates = inputs.flatMap(\.sessions).compactMap { $0.day?.date }
        let effectiveWindowDays = TacticalWindowPolicy.effectiveWindowDays(
            policyWindowDays: windowDays, materializedDates: materializedDates, windowStartDate: phase.startDate
        )
        let constraints = SchedulingConstraints(availability: availability, window: SchedulingWindow(startDate: phase.startDate, numberOfDays: effectiveWindowDays))
        let scheduled = SchedulingPipeline.propose(mix: mix, inputs: inputs, constraints: constraints)
        try AcceptScheduleProposalUseCase.accept(scheduled.proposal, ownerUserID: ownerUserID, context: context)

        return Result(phase: phase, mix: mix, instancesByComponent: instancesByComponent, scheduleProposal: scheduled.proposal)
    }
}
