import Foundation
import SwiftData

/// Stage 9B: one candidate pre-workout preparation movement — the
/// warm-up/mobility catalog's own row shape, seeded once like
/// `ExerciseCatalog` (`WarmupCatalog.makeAndInsert`).
///
/// **Never performance-tracked** — no path to `PerformanceProfile`/
/// `SetResult`/`PersonalRecord` exists anywhere on this type (CLAUDE.md
/// rules 1/2 trivially satisfied). Not the same concept as
/// `SetPrescription.isWarmup` (an exercise-specific ramp-up set within a
/// Strength exercise) — this is a general pre-session mobility/
/// preparation drill, a different product, deliberately not built here
/// (`STAGE9_WARMUP_DESIGN.md` §0).
///
/// **Stage 9A decision D-W2 (approved, revised model):** `exercise` is
/// an optional link to an existing, already-canonical `Exercise` for the
/// real overlap case (bodyweight squat, push-up, glute bridge — movements
/// that are legitimately both a warm-up drill and something a user might
/// separately program/track). When `exercise != nil`, that `Exercise`'s
/// own `primaryTargets`/`movementFunctions` are the sole source of truth
/// for matching — `targetMuscleGroups`/`targetMovementFunctions` below
/// are **never populated** in that case, avoiding a duplicate, driftable
/// copy. They are authoritative only for a pure preparation/mobility
/// drill with no `Exercise` equivalent (cat-cow, ankle rocks, band
/// pull-apart) — mirrors the same "lightweight reference to canonical
/// Exercise" pattern this codebase already uses
/// (`FunctionalFitnessMovement.exercise`, `ExerciseAlias`), not a new
/// abstraction layer.
@Model
final class WarmupMovement {
    @Attribute(.unique) var id: UUID
    var name: String
    /// Optional link to an existing canonical Exercise — see the type's
    /// own doc comment. `nil` for a pure mobility/preparation drill.
    var exercise: Exercise?
    /// Authoritative only when `exercise == nil`.
    var targetMuscleGroups: [MuscleGroup]
    /// Authoritative only when `exercise == nil`.
    var targetMovementFunctions: [MovementFunction]
    /// What preparation QUALITY this movement itself provides — always
    /// explicitly declared here (never derived), matched against the
    /// session's own automatically-DERIVED emphasis needs
    /// (`WarmupEmphasisDerivation`).
    var emphasis: [PreparationEmphasis]
    var instructionText: String
    /// Exactly one of `defaultDurationSeconds`/`defaultReps` is set,
    /// never both.
    var defaultDurationSeconds: Int?
    var defaultReps: Int?
    /// e.g. "10 each side" — doubles the estimated time for a rep-based
    /// item when true.
    var hasSides: Bool
    /// Favors minimal-equipment preparation by default
    /// (`STAGE9_WARMUP_DESIGN.md` §6) — also the seam a future Home Gym
    /// stage filters on, without redesigning this type.
    var requiresEquipment: Bool

    /// `WarmupSequenceItem.movement`'s required inverse — nothing reads
    /// this collection. Same established "un-inversed to-one reference
    /// to a deletable type crashes instead of nullifying" fix already
    /// used throughout this codebase (`ExerciseSlot.materializedPrescriptions`).
    @Relationship(deleteRule: .nullify, inverse: \WarmupSequenceItem.movement)
    var usedInSequenceItems: [WarmupSequenceItem] = []

    init(
        id: UUID = UUID(),
        name: String,
        exercise: Exercise? = nil,
        targetMuscleGroups: [MuscleGroup] = [],
        targetMovementFunctions: [MovementFunction] = [],
        emphasis: [PreparationEmphasis] = [],
        instructionText: String,
        defaultDurationSeconds: Int? = nil,
        defaultReps: Int? = nil,
        hasSides: Bool = false,
        requiresEquipment: Bool = false
    ) {
        self.id = id
        self.name = name
        self.exercise = exercise
        self.targetMuscleGroups = targetMuscleGroups
        self.targetMovementFunctions = targetMovementFunctions
        self.emphasis = emphasis
        self.instructionText = instructionText
        self.defaultDurationSeconds = defaultDurationSeconds
        self.defaultReps = defaultReps
        self.hasSides = hasSides
        self.requiresEquipment = requiresEquipment
    }

    /// The effective muscle groups to match against — the linked
    /// `Exercise`'s own tags when present, this row's own tags otherwise.
    /// Never both, never a merge — exactly one source of truth per row.
    var effectiveMuscleGroups: [MuscleGroup] {
        exercise?.primaryTargets ?? targetMuscleGroups
    }

    /// See `effectiveMuscleGroups`.
    var effectiveMovementFunctions: [MovementFunction] {
        exercise?.movementFunctions ?? targetMovementFunctions
    }

    /// This candidate's own estimated duration, capped at
    /// `WarmupPolicy.perItemMaxSeconds` so one item can never itself
    /// dominate the time budget.
    var estimatedSeconds: Int {
        let raw: Int
        if let defaultDurationSeconds {
            raw = defaultDurationSeconds
        } else if let defaultReps {
            raw = defaultReps * WarmupPolicy.secondsPerRep * (hasSides ? 2 : 1)
        } else {
            raw = 0
        }
        return min(raw, WarmupPolicy.perItemMaxSeconds)
    }
}
