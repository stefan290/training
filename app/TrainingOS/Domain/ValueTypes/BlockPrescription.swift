import Foundation

/// The generalized prescription abstraction validated in Stage 3B
/// (`PRESCRIPTION_RESULT_MODEL_REVIEW.md` §2) and implemented here.
///
/// **Not persisted directly.** SwiftData has no first-class polymorphism,
/// so this enum is never stored as a `@Model` property — it's a *computed*
/// domain-level view, synthesized by `WorkoutBlock.blockPrescription` from
/// whichever of its typed, persisted relationships is populated
/// (`ExercisePrescription`, `SteadyStatePrescription`, `IntervalPrescription`,
/// `FunctionalFitnessPrescription` — all unchanged or newly added `@Model`
/// types). This is the "cleaner boundary between persisted entities and
/// domain value types" the brief anticipated: the persistence layer stores
/// typed relationships; the application/engine layer reasons about one
/// typed enum.
///
/// `.exercise` carries an array, not a single `ExercisePrescription` —
/// a `WorkoutBlock` can hold several movements (e.g. an AMRAP's three
/// exercises), so the brief's own illustrative single-value case was
/// adapted to match the existing domain model rather than the reverse.
enum BlockPrescription {
    case exercise([ExercisePrescription])
    case steadyState(SteadyStatePrescription)
    case intervals(IntervalPrescription)
    case functionalFitness(FunctionalFitnessPrescription)
}
