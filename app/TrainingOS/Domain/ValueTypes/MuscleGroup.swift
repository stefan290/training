import Foundation

/// A coarse target-muscle tag for `ExerciseSlot.allowedTargets` (Stage 3
/// decision A6 — a real multi-target schema, e.g. "Chest Isolation or
/// Triceps" needs both `.chest` and `.triceps` representable on the same
/// slot). Deliberately not exhaustive physiology — this is a programming
/// tag, the same spirit as `TrainingModality`/`SessionRole`.
enum MuscleGroup: String, Codable, CaseIterable {
    case chest
    case back
    case shoulders
    case triceps
    case biceps
    case quadriceps
    case hamstrings
    case glutes
    case calves
    case core
    case forearms
    /// Stage 10C.1 additions: `.shoulders` alone could not distinguish
    /// a lateral-delt-isolation slot intent (e.g. Lateral Raise) from a
    /// rear-delt/upper-back-accessory intent (e.g. Face Pull) — two
    /// meaningfully different hypertrophy programming targets that
    /// happened to collapse onto one tag. Purely additive: existing
    /// exercises keep `.shoulders` unchanged and gain the more specific
    /// tag alongside it, never in place of it, so any slot still
    /// matching on generic `.shoulders` is unaffected. Deliberately not
    /// a full anatomical subdivision (no front-delt case, no separate
    /// rotator-cuff tag) — only the two distinctions Stage 10C's own
    /// audit found a concrete near-term programming need for.
    case lateralDelt
    case rearDelt
}
