import Foundation

/// Stage 10R.7A: pure, derived STRATEGIC-lifecycle queries — the phase-
/// level sibling of `TacticalWeekCompletion` (which answers "is this
/// week/instance done"). Nothing here is a persisted status; every answer
/// is recomputed from real `ProgramInstance`/`TrainingMixComponent`/
/// `TrainingPlan` state, exactly the same discipline
/// `TacticalWeekCompletion`/`ProgramWeekGrouping` already established.
///
/// **Locked hierarchy (`STAGE10R7_STRATEGIC_PHASE_LIFECYCLE_DESIGN.md`,
/// D-10R7-1 through D-10R7-3):** a `TrainingPhase` is a strategic period in
/// the accepted annual plan. Program-specific succession (Hypertrophy
/// Mesocycle 1 -> 2 -> 3) is progression INSIDE a phase's program
/// lifecycle, never strategic phase creation — so "is the Hypertrophy
/// program lifecycle done" and "is the whole strategic phase done" are
/// two different, explicitly distinct questions, answered here by two
/// different functions.
///
/// **Date boundaries are never treated as proof of completion**
/// (D-10R7-6): nothing here reads `TrainingPhase.endDate`/the current
/// date. A phase can sit `.active`, past its own planned `endDate`, with
/// real required work still unfinished — this is a real, currently
/// undefined product state, deliberately not silently resolved by this
/// stage. `isPhaseTerminal` answers only "has every required component's
/// program lifecycle actually finished," never "has enough time passed."
enum TrainingPhaseCompletion {
    /// `true` when `instance` is a Hypertrophy/Powerlifting instance whose
    /// `HypertrophyPhaseType` has a real next entry in
    /// `HypertrophyProgramJourney.orderedPhaseTypes` — the same "is there
    /// a next mesocycle" check `PhaseDetailViewModel`/
    /// `StartNextHypertrophyMesocycleUseCase` already each computed
    /// independently; factored here as the one shared, testable answer.
    /// `false` for every non-Hypertrophy system (no such succession
    /// mechanism exists for Interval/Functional Fitness/Steady State
    /// today) and for a Hypertrophy instance with no
    /// `hypertrophyConfiguration` at all.
    static func hasNextHypertrophyMesocycle(for instance: ProgramInstance) -> Bool {
        guard let configuration = instance.programDefinition?.hypertrophyConfiguration,
              let currentIndex = HypertrophyProgramJourney.orderedPhaseTypes.firstIndex(of: configuration.phaseType)
        else { return false }
        return HypertrophyProgramJourney.orderedPhaseTypes.indices.contains(currentIndex + 1)
    }

    /// `true` when `component`'s own program lifecycle has genuinely
    /// finished — never merely "the current tactical week is terminal"
    /// (`TacticalWeekCompletion.isWeekTerminal`), which says nothing about
    /// whether a further mesocycle/program block is still expected.
    ///
    /// - Hypertrophy/Powerlifting: the current instance must be tactically
    ///   EXHAUSTED (`TacticalWeekCompletion.isInstanceExhausted`) AND no
    ///   next mesocycle may exist (`hasNextHypertrophyMesocycle`) — a
    ///   component sitting at "Mesocycle 1 exhausted, Mesocycle 2 not yet
    ///   started" is NOT program-lifecycle-terminal; the succession itself
    ///   is still pending.
    /// - Every other system (Interval, Functional Fitness, Steady State):
    ///   no further succession mechanism exists today, so tactical
    ///   exhaustion of the current instance IS the whole program
    ///   lifecycle's own completion.
    static func isComponentProgramLifecycleTerminal(_ component: TrainingMixComponent) -> Bool {
        guard let instance = component.programInstance else { return false }
        guard TacticalWeekCompletion.isInstanceExhausted(for: instance) else { return false }
        if component.programmingSystem == .hypertrophy || component.programmingSystem == .powerlifting {
            return !hasNextHypertrophyMesocycle(for: instance)
        }
        return true
    }

    /// `true` only when EVERY component of `phase`'s active mix
    /// (`selectedTrainingMix ?? recommendedTrainingMix`) has a genuinely
    /// terminal program lifecycle. A phase with no mix yet, or an empty
    /// mix, is never terminal (nothing to have finished). A component
    /// that was never instantiated (`programInstance == nil` — e.g. an
    /// optional component nothing ever selected) is treated as NOT
    /// terminal — a conservative, explicitly documented judgment call
    /// (`STAGE10R7_STRATEGIC_PHASE_LIFECYCLE_DESIGN.md` §25.2): "never
    /// started" is never silently read as "done." This does not
    /// distinguish `ComponentFlexibility` (`.required`/`.preferred`/
    /// `.optional`) — it mirrors `TacticalWeekCompletion
    /// .canAdvanceTacticalWeek(for:)`'s own existing precedent of treating
    /// every real component uniformly; whether an `.optional` component
    /// should be excluded from this gate is an open product question, not
    /// decided here.
    static func isPhaseTerminal(_ phase: TrainingPhase) -> Bool {
        guard let mix = phase.selectedTrainingMix ?? phase.recommendedTrainingMix else { return false }
        let components = mix.orderedComponents
        guard !components.isEmpty else { return false }
        return components.allSatisfy { isComponentProgramLifecycleTerminal($0) }
    }

    /// The next `TrainingPhase` already pre-planned in `phase.plan
    /// .orderedPhases`, if any — never fabricated, never a newly-created
    /// phase (D-10R7-1: strategic phases are pre-planned by
    /// `AcceptStrategicPlanUseCase`, never generated on the fly by
    /// program-level succession). Identical lookup to
    /// `PhaseDetailViewModel.nextPhase`'s own existing logic and to
    /// `TransitionPhaseUseCase`'s own next-phase resolution — factored
    /// here as the one shared, testable answer.
    static func nextStrategicPhase(for phase: TrainingPhase) -> TrainingPhase? {
        guard let plan = phase.plan,
              let currentIndex = plan.orderedPhases.firstIndex(where: { $0.id == phase.id }),
              plan.orderedPhases.indices.contains(currentIndex + 1)
        else { return nil }
        return plan.orderedPhases[currentIndex + 1]
    }

    /// `true` when `phase` is the last phase in its plan's pre-planned
    /// sequence — the point at which "Start Next Phase" no longer applies
    /// and the `TrainingPlan` itself becomes eligible for its own
    /// completion question (out of this stage's scope — see the design
    /// doc's §17-19/§25).
    static func isFinalStrategicPhase(_ phase: TrainingPhase) -> Bool {
        nextStrategicPhase(for: phase) == nil
    }
}
