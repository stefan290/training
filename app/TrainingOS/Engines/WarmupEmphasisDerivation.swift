import Foundation

/// Stage 9B: derives which `PreparationEmphasis` values a workout's own
/// already-existing `MuscleGroup`/`MovementFunction` tags imply —
/// **automatic, deterministic derivation**, never a second manually-
/// maintained tag authored on every `Exercise` (Stage 9 design decision
/// D-W5). Only `WarmupMovement` catalog rows themselves explicitly
/// declare what emphasis they provide; this engine is the other half —
/// what emphasis today's session NEEDS.
///
/// Pure, deterministic, no randomness — identical inputs always produce
/// an identical result (same discipline as every other engine in this
/// codebase).
enum WarmupEmphasisDerivation {
    static func derive(muscleGroups: [MuscleGroup], movementFunctions: [MovementFunction]) -> Set<PreparationEmphasis> {
        let groups = Set(muscleGroups)
        let functions = Set(movementFunctions)
        var result: Set<PreparationEmphasis> = []

        if functions.contains(.squatLoaded) || groups.contains(.quadriceps) || groups.contains(.glutes) {
            result.insert(.hipMobility)
        }
        if functions.contains(.squatLoaded) {
            result.insert(.ankleMobility)
        }
        if functions.contains(.hingeLoaded) || groups.contains(.hamstrings) {
            result.insert(.hipMobility)
        }
        if functions.contains(.jumping) {
            result.insert(.plyometricReadiness)
            result.insert(.ankleMobility)
        }
        // Pressing/pulling upper-body preparation — REVISED after Stage
        // 9B acceptance found this branch produced NOTHING for the
        // seeded Hypertrophy catalog's own Bench Press/Incline Dumbbell
        // Press (both have empty `movementFunctions`, so the original
        // `MovementFunction`-gated condition never fired). `MuscleGroup`
        // is the primary, always-populated signal — any pressing/pulling
        // involvement of chest, shoulders or back benefits from
        // scapular/thoracic preparation regardless of whether
        // `MovementFunction` also happens to be tagged; `MovementFunction`
        // is no longer required to unlock this branch.
        if groups.contains(.chest) || groups.contains(.shoulders) || groups.contains(.back) {
            result.insert(.overheadShoulderMobility)
        }
        if groups.contains(.chest) {
            result.insert(.thoracicMobility)
        }
        // Deliberately NEVER falls back to `.generalActivation` here —
        // REVISED after Stage 9B acceptance found this fallback caused
        // every `.generalActivation`-tagged catalog candidate (Arm
        // Circles, Dead Bug, etc.) to falsely match the priority-1/2
        // "specific relevance" tiers whenever ANY exercise in the session
        // (e.g. Calf Raise, whose only target is `.calves`) derived
        // nothing more specific and leaked `.generalActivation` into the
        // session's own derived demand set. `.generalActivation` must
        // only ever be evaluated as the CANDIDATE's own fallback-tier
        // self-declaration (`GenerateWarmupSequenceUseCase.priority`),
        // never as something a session can be considered to "need."
        // Returning an empty set here is the correct, honest answer for
        // "this exercise implies no specific preparation emphasis."
        return result
    }
}
