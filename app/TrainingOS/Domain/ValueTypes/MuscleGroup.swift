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
}
