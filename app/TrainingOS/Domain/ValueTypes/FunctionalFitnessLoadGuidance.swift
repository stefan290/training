import Foundation

/// Dogfood Round 1 — Final Close (Finding 3D): a real, **TrainingOS
/// PRODUCT DECISION** authored RELATIVE load/intensity prescription for a
/// loaded Functional Fitness movement — real PROGRAMMING DATA, never
/// improvised display copy, and never a %1RM-or-equivalent numeric
/// formula (no validated one exists anywhere in this codebase, and
/// CLAUDE.md rule 10 forbids inventing one — see
/// `POST_FFP1_FUNCTIONAL_FITNESS_GAP_AUDIT.md` §K/§V's own finding on
/// this exact point). This is the sanctioned alternative: TrainingOS may
/// author a relative-load/intensity intent for its own generated content,
/// same as it already authors reps/format/duration domain.
enum RelativeLoadTier: String, Codable, CaseIterable {
    case light
    case moderate
    case heavy

    /// Athlete-facing label — kept alongside the enum itself since this
    /// is the one, single vocabulary every real caller shares (mirrors
    /// `PlanPresentation`'s own "one shared label per domain enum"
    /// convention).
    var displayLabel: String {
        switch self {
        case .light: "Light load"
        case .moderate: "Moderate load"
        case .heavy: "Heavy load"
        }
    }
}

/// Attached to a loaded `FunctionalFitnessMovement` at materialization
/// time via `FunctionalFitnessMovementTargetRule`'s own locked per-
/// exercise table (never a formula) — every field here is real,
/// authored PROGRAMMING DATA, not a UI-layer improvisation.
struct FunctionalFitnessLoadGuidance: Codable, Equatable {
    var tier: RelativeLoadTier
    /// Reps-in-reserve target for the OPENING round only — deliberately
    /// never a whole-workout claim, since fatigue changes what's
    /// sustainable as the workout progresses.
    var targetReserveRepsOpeningRound: Int?
    /// Whether the intent is a genuinely sustainable/unbroken pace vs. a
    /// harder, more likely-to-break effort.
    var sustainableUnbrokenIntent: Bool
}
