import Foundation

/// Stage 9B: what preparation QUALITY a movement provides — the smallest
/// useful extension beyond `MuscleGroup`/`MovementFunction` (Stage 9
/// design decision D-W5), closing gaps those two axes cannot express on
/// their own (overhead vs. thoracic mobility both reducing to "shoulders";
/// no axis at all for jumping/plyometric or unilateral-stability needs).
///
/// **This vocabulary is deliberately small and closed — never a mobility
/// ontology.** Only `WarmupMovement` catalog rows explicitly declare
/// which emphasis they provide; a session's own NEEDED emphases are
/// always DERIVED automatically from its existing `MuscleGroup`/
/// `MovementFunction` data (`WarmupEmphasisDerivation.swift`), never a
/// second tag manually authored on every `Exercise`.
enum PreparationEmphasis: String, Codable, CaseIterable {
    case ankleMobility
    case hipMobility
    case thoracicMobility
    case overheadShoulderMobility
    case plyometricReadiness
    case unilateralStability
    case generalActivation
}

/// Stage 9B: the one central source for every warm-up generation
/// constant — explicit product decision D-W4. Never scattered as magic
/// numbers through generation/UI code; changeable later without a schema
/// change or architectural redesign.
enum WarmupPolicy {
    /// Nominal target for the generated sequence's total estimated
    /// duration — a target, never a required minimum (D-W3/D-W4).
    static let targetDurationSeconds = 300
    /// No single candidate's own estimated duration may exceed this,
    /// so one long item can never itself dominate the budget.
    static let perItemMaxSeconds = 60
    /// TRAININGOS-DESIGNED conversion for rep-based items — same
    /// illustrative-default discipline as every other such constant in
    /// this repo (the 3-point readiness scale, `TacticalWindowPolicy
    /// .fallbackWindowWeeks`).
    static let secondsPerRep = 3
    /// Safety cap on total item count, independent of the time budget.
    static let maxItemCount = 8
}
