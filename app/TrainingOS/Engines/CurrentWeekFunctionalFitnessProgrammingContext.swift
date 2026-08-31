import Foundation

/// One already-programmed Functional Fitness `Stimulus` decision within
/// the current tactical week — deliberately NOT completed exposure.
/// `FunctionalFitnessExposureHistoryBuilder` answers "what has the athlete
/// actually completed"; this answers "what has already been PROGRAMMED
/// this week, regardless of whether it's been performed yet." Kept to
/// exactly the `Stimulus` itself — "which objectives does it serve" is
/// always re-derivable on demand via `AdaptationObjectiveStimulusMapping
/// .objectivesServed(by:)`, never cached here, so the two can never
/// silently drift if that mapping is ever revised. Deliberately carries
/// no identity field: every real consumer (`FunctionalFitnessDecisionEngine`
/// .adjustForSameWeekComplementarity`) only ever reads this list
/// positionally/by-value (which objectives has ANY prior entry served?),
/// never by looking one entry up by an owning component — a
/// `componentID` field was audited (Stage CP.2 pre-commit verification)
/// and found unused by any real call site; since every real
/// `LongTermPlanner`-built mix has at most one Functional Fitness
/// component, an identity field here would answer a question ("which
/// component programmed this?") no real code ever asks. Removed rather
/// than left inert, per this project's own "do not invent an identity
/// nothing uses" discipline.
struct ProgrammedStimulusSummary: Equatable {
    var stimulus: Stimulus
}

/// Derived, non-persisted, built fresh for exactly one
/// `FunctionalFitnessMaterializer.materializeWeek` call and discarded at
/// the end of it — never read from or written to a `ModelContext`, never
/// crosses a materialization boundary. Since every real
/// `LongTermPlanner`-built `TrainingMix` carries at most ONE Functional
/// Fitness `TrainingMixComponent` (confirmed by direct audit of every
/// real candidate builder), "FF-A"/"FF-B" same-week coordination is not
/// cross-component — it's the SAME component's own multiple weekly
/// sessions, decided one after another within a single `materializeWeek`
/// call. This context is what lets the second (and any later) session see
/// what the first already decided, without the first needing to be
/// completed.
struct CurrentWeekFunctionalFitnessProgrammingContext: Equatable {
    var alreadyProgrammedThisWeek: [ProgrammedStimulusSummary] = []

    mutating func record(stimulus: Stimulus) {
        alreadyProgrammedThisWeek.append(ProgrammedStimulusSummary(stimulus: stimulus))
    }
}
