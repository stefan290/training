import Foundation

/// Long-Term Planner Intelligence — Final Duration Fix: the ONLY place in
/// the strategic-planning stack that knows about a concrete program
/// engine's real executable mesocycle length. `StrategicPeriodizationPolicy`
/// deliberately does NOT know this (it only ever decides WHAT `PhaseType`
/// comes next and WHY) — this type exists precisely so that separation
/// holds: given whichever `TrainingMix` is ACTUALLY recommended/selected
/// for a phase (never `PhaseType` alone), it answers "does current
/// production capability give a stricter, known duration bound than the
/// generic `PhaseDurationDefaults` estimate."
///
/// **Why `PhaseType` alone was proven insufficient (Final Pre-Commit
/// Semantic Check):** `candidateMixTemplates(.strength)` returns TWO real
/// candidates — `strengthFocusedMix()` (`.powerlifting` engine,
/// `strengthContentSelector: .sourceBackedGeneralStrength` ->
/// `StrengthSourceContentLibrary` Family D/E, exactly
/// `PowerliftingProgramGenerator.mesocycleLengthWeeks` (5) real weeks, NO
/// within-phase succession) and `muscleGainVariedMix()` (`.hypertrophy`
/// engine, WITH real succession via `StartNextHypertrophyMesocycleUseCase`).
/// A genuine athlete preference can promote the second candidate to
/// `.recommended` for a `.strength`-typed phase (`rankCandidateMixes`'s
/// existing, unmodified §5b bounded-promotion logic) — so "this phase's
/// `PhaseType` is `.strength`" does NOT by itself imply "this phase's
/// executable capacity is 5 weeks." Only the ACTUAL resolved mix does.
///
/// The correct, materially different invariant this type encodes: **a
/// strategic phase whose ACTUAL recommended/selected TrainingMix's primary
/// component resolves to a single fixed-length, non-succession source
/// mesocycle is planned for that mesocycle's own real length** — never
/// "phases of this `PhaseType` are always N weeks."
enum ExecutablePhaseDurationResolver {
    /// `nil` means "no stricter bound is currently known — use the
    /// existing `PhaseDurationDefaults` estimate for the phase's own
    /// `PhaseType` unchanged." Only ever inspects `mix`'s PRIMARY
    /// component (`priority: .primary`) — a mix's own supporting
    /// components never determine the phase's overall executable
    /// capacity (mirrors how `TrainingPhaseCompletion.isComponentProgramLifecycleTerminal`
    /// is evaluated per-component but the phase itself is judged by
    /// ALL components in `isPhaseTerminal` — a stricter, separate
    /// question from "what's a reasonable duration ESTIMATE," which this
    /// type answers using only the primary component, exactly like
    /// `TrainingPhase.primaryInstance` is the one component every other
    /// part of this codebase already treats as "the phase's own defining
    /// content").
    ///
    /// Reads `PowerliftingProgramGenerator.mesocycleLengthWeeks` directly
    /// — never a second, independently-maintained copy of "5." Currently
    /// the ONLY known stricter bound: a primary component whose
    /// `programmingSystem == .powerlifting` AND
    /// `strengthContentSelector == .sourceBackedGeneralStrength` resolves
    /// to Family D/E, which has no within-phase succession mechanism at
    /// all (confirmed: no `HypertrophyProgramJourney`-shaped table, no
    /// `StartNextHypertrophyMesocycleUseCase`-shaped use case exists for
    /// Powerlifting). A primary component whose `programmingSystem ==
    /// .hypertrophy` (whether via `muscleGainFocusedHypertrophyMix()`,
    /// `muscleGainVariedMix()`, or any other Hypertrophy-primary mix) is
    /// NOT capped — Hypertrophy's own real, pre-existing succession
    /// mechanism can legitimately sustain a longer strategic phase.
    /// Every other engine/selector combination also returns `nil` — this
    /// resolver only ever TIGHTENS an estimate when it has real,
    /// confirmed evidence for a stricter bound, never guesses one.
    static func executablePlanningDuration(for mix: TrainingMix) -> PhaseDurationKind? {
        guard let primary = mix.orderedComponents.first(where: { $0.priority == .primary }) else { return nil }
        guard primary.programmingSystem == .powerlifting,
              primary.strengthContentSelector == .sourceBackedGeneralStrength
        else { return nil }
        return .fixed(weeks: PowerliftingProgramGenerator.mesocycleLengthWeeks)
    }
}
