import Foundation
import SwiftData

/// Stage 9B: everything the warm-up generator needs — the FINAL
/// EXECUTABLE workout (already-mutated by any accepted Stage 8B
/// adaptation, per `READINESS_ADAPTATION_PIPELINE.md`'s own
/// overlay-not-copy discipline) plus today's readiness signals.
///
/// **Home Gym / equipment seam (Stage 9 design §6, kept out of scope
/// here on purpose):** no `environmentConstraint` field exists — Stage
/// 9B does not invent an `EnvironmentConstraint` domain type merely to
/// leave it `nil`. The seam is structural instead: candidate filtering
/// below is one composed pipeline (pain-exclusion, then relevance
/// ranking) with a single, obviously-marked point where a future
/// equipment/environment filter step slots in without changing this
/// struct's shape or any caller — see the marker comment in
/// `GenerateWarmupSequenceUseCase.candidatePool`.
struct WarmupGenerationContext {
    let executableWorkout: Session
    let readiness: ReadinessCheckIn?
}

/// Stage 9B: the deterministic warm-up generator
/// (`STAGE9_WARMUP_DESIGN.md`). Reads the Session strictly AFTER any
/// Stage 8B adaptation has already been applied in place — there is no
/// separate "final workout" projection to build; `session.orderedBlocks`
/// at the moment this runs already IS the executable workout, because
/// Stage 8B substitution/removal mutates the live prescription/block
/// rather than producing a separate copy.
enum GenerateWarmupSequenceUseCase {
    /// `nil` means no warm-up is offered at all — either the Session has
    /// no in-scope block (Steady State/Interval/Running-only, or every
    /// in-scope block was removed by an accepted adaptation), or the
    /// safe/relevant candidate pool came up empty after pain exclusion
    /// (Stage 9 decision D-W3: a shorter or absent warm-up is always
    /// preferred over irrelevant/unsafe filler).
    static func generate(context: WarmupGenerationContext, modelContext: ModelContext) -> WarmupSequence? {
        let inScopeBlocks = context.executableWorkout.orderedBlocks.filter { $0.status != .skipped && isInScope($0.type) }
        guard !inScopeBlocks.isEmpty else { return nil }

        let catalog = (try? modelContext.fetch(FetchDescriptor<WarmupMovement>())) ?? []
        guard !catalog.isEmpty else { return nil }

        let demand = SessionDemand(blocks: inScopeBlocks)
        let stiffGroups = Set(context.readiness?.reportedStiffness ?? [])
        let painGroups = Set(context.readiness?.reportedPain ?? [])

        let prioritized = candidatePool(catalog: catalog, excludingPain: painGroups)
            .compactMap { movement -> (movement: WarmupMovement, priority: Int)? in
                priority(for: movement, stiffGroups: stiffGroups, demand: demand).map { (movement, $0) }
            }

        // REVISED after Stage 9B acceptance: the general-activation
        // fallback tier (priority 3) exists only for D-W3's original
        // purpose — "nothing specifically relevant survives at all" — not
        // as filler to top up an already-adequately-covered sequence.
        // Whenever at least one specifically relevant candidate exists
        // (priority 0-2, i.e. it matched stiffness or an actual session
        // demand), priority-3 candidates are excluded from consideration
        // entirely, so the greedy fill below can never reach for them.
        let hasSpecificallyRelevantCandidate = prioritized.contains { $0.priority < 3 }
        let eligible: [(movement: WarmupMovement, priority: Int)]
        if hasSpecificallyRelevantCandidate {
            eligible = prioritized.filter { $0.priority < 3 }
        } else {
            eligible = prioritized
        }
        let sortedEligible = eligible.sorted { lhs, rhs in
            lhs.priority != rhs.priority ? lhs.priority < rhs.priority : lhs.movement.name < rhs.movement.name
        }
        let ranked = sortedEligible.map(\.movement)

        var selected: [WarmupMovement] = []
        var totalSeconds = 0
        for movement in ranked {
            guard selected.count < WarmupPolicy.maxItemCount else { break }
            guard totalSeconds < WarmupPolicy.targetDurationSeconds else { break }
            selected.append(movement)
            totalSeconds += movement.estimatedSeconds
        }

        guard !selected.isEmpty else { return nil }

        let sequence = WarmupSequence(generatedAt: Date())
        for movement in selected {
            let item = WarmupSequenceItem(
                movement: movement,
                prescribedDurationSeconds: movement.defaultDurationSeconds,
                prescribedReps: movement.defaultReps
            )
            sequence.addItem(item)
        }
        return sequence
    }

    /// Pain excludes a candidate outright, before ranking even happens —
    /// the exact same "candidate's own targets disjoint from the pain
    /// areas" rule `EvaluateReadinessAdaptationUseCase.validSubstitute`
    /// already applies for Level 3 substitution (Stage 9 design §2 Q4).
    ///
    /// FUTURE SEAM (Home Gym, not built here): a future equipment/
    /// environment filter step attaches here, immediately after pain
    /// exclusion and before ranking — e.g.
    /// `.filter { environmentAllows($0, constraint) }` — without
    /// changing this function's signature or any caller.
    private static func candidatePool(catalog: [WarmupMovement], excludingPain painGroups: Set<MuscleGroup>) -> [WarmupMovement] {
        guard !painGroups.isEmpty else { return catalog }
        return catalog.filter { Set($0.effectiveMuscleGroups).isDisjoint(with: painGroups) }
    }

    /// Lower is higher priority. `nil` means "not relevant to today's
    /// session at all" — excluded from the candidate pool entirely
    /// rather than padded in as low-value filler (D-W3).
    private static func priority(for movement: WarmupMovement, stiffGroups: Set<MuscleGroup>, demand: SessionDemand) -> Int? {
        let groups = Set(movement.effectiveMuscleGroups)
        let emphasis = Set(movement.emphasis)

        if !groups.isDisjoint(with: stiffGroups) {
            return 0
        }
        if !groups.isDisjoint(with: demand.primaryMuscleGroups) || !emphasis.isDisjoint(with: demand.primaryEmphasis) {
            return 1
        }
        if !groups.isDisjoint(with: demand.secondaryMuscleGroups) || !emphasis.isDisjoint(with: demand.secondaryEmphasis) {
            return 2
        }
        if emphasis.contains(.generalActivation) {
            return 3
        }
        return nil
    }

    private static func isInScope(_ type: WorkoutBlockType) -> Bool {
        switch type {
        case .steadyState, .intervals, .warmup, .cooldown, .mobility:
            return false
        case .strength, .hypertrophy, .accessory, .amrap, .emom, .forTime, .functionalFitness:
            return true
        }
    }

    /// What today's executable, in-scope blocks actually demand —
    /// derived strictly from the CURRENT (post-adaptation)
    /// exercise/movement assignments, never the original template
    /// defaults (Stage 9 design §2 Q5). The first in-scope block (by
    /// `sortIndex`) is treated as primary; the rest are secondary — a
    /// simple, deterministic priority proxy, not a new "importance"
    /// concept.
    private struct SessionDemand {
        let primaryMuscleGroups: Set<MuscleGroup>
        let primaryEmphasis: Set<PreparationEmphasis>
        let secondaryMuscleGroups: Set<MuscleGroup>
        let secondaryEmphasis: Set<PreparationEmphasis>

        init(blocks: [WorkoutBlock]) {
            let ordered = blocks.sorted { $0.sortIndex < $1.sortIndex }
            let primaryExercises = ordered.first.map(Self.exercises(in:)) ?? []
            let secondaryExercises = ordered.dropFirst().flatMap(Self.exercises(in:))

            primaryMuscleGroups = Set(primaryExercises.flatMap(\.primaryTargets))
            primaryEmphasis = Set(primaryExercises.flatMap {
                WarmupEmphasisDerivation.derive(muscleGroups: $0.primaryTargets, movementFunctions: $0.movementFunctions)
            })
            secondaryMuscleGroups = Set(secondaryExercises.flatMap(\.primaryTargets))
            secondaryEmphasis = Set(secondaryExercises.flatMap {
                WarmupEmphasisDerivation.derive(muscleGroups: $0.primaryTargets, movementFunctions: $0.movementFunctions)
            })
        }

        private static func exercises(in block: WorkoutBlock) -> [Exercise] {
            if let ffPrescription = block.functionalFitnessPrescription {
                return ffPrescription.orderedMovements.compactMap(\.exercise)
            }
            return block.orderedPrescriptions.compactMap(\.exercise)
        }
    }
}
