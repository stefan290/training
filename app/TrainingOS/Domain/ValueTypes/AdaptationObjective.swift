import Foundation

/// What adaptation a `TrainingMixComponent` is trying to produce — a
/// content/purpose signal, deliberately orthogonal to `GoalPriority`
/// (which answers "how protected is this component's stress budget,"
/// never "why is it here"). Stage CP.2's locked, closed 7-case taxonomy
/// (`TRAINING_MIX_CONCURRENT_PROGRAMMING_DESIGN.md`'s Review Decisions
/// section): every case survived a strict test — "show at least one real
/// programming decision this case could change, or it does not belong."
///
/// Deliberately excludes `maintenance` (a direction/state, already
/// modeled by `PhaseType.maintenance`, not an adaptation),
/// `movementVariability` (a programming STRATEGY
/// `FunctionalFitnessDecisionEngine` already implements, not an
/// adaptation), and `generalAthleticism` (too vague, redundant with the
/// union of the other cases). Do not expand this taxonomy speculatively —
/// a new case needs the same "changes a real decision" proof the
/// original 7 were held to.
///
/// Non-mutually-exclusive by design — `TrainingMixComponent
/// .adaptationObjectives` is an array, since a real component (e.g.
/// Functional Fitness in a "variety" mix) can legitimately serve more
/// than one at once.
enum AdaptationObjective: String, Codable, CaseIterable {
    case muscleGain
    case maxStrength
    case power
    case aerobicCapacity
    case anaerobicCapacity
    case workCapacity
    case skillAcquisition
}
