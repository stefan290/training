import Foundation
import SwiftData

/// Stage 8B: the deterministic readiness decision evaluator
/// (`READINESS_DECISION_MODEL.md`). Reads a `ReadinessCheckIn` and today's
/// already-materialized Session, and produces a `ReadinessAdaptationProposal`
/// — never mutates anything itself (`ReadinessAdaptationDecisionUseCase`
/// owns applying an accepted item). Per-modality: asks each block's own
/// `WorkoutBlockType` what it supports rather than one generic rule for
/// every modality (CLAUDE.md rule 7).
///
/// **Level 2's only implemented mechanism is a bounded set-count
/// reduction of exactly 1 set.** This is not an invented magnitude: it is
/// the same formula `StrengthProgressionEngine.resolveSetCount`'s
/// `.autoregulated` case already uses for a -1 rating
/// (`max(0, previousWeekSetCount + autoregulationRating)`), reused here
/// for a same-day context instead of a next-week one. Load, rep-range and
/// RIR adjustment are deliberately **not** implemented — no existing,
/// already-approved magnitude for those exists anywhere in this codebase,
/// and CLAUDE.md rule 10/Stage 8B's own §13 gate forbid inventing one
/// silently. See the Stage 8B implementation report for the exact
/// decision this leaves open.
///
/// The two thresholds below (how many poor Tier-0 signals escalate to a
/// postpone recommendation; that the set-count reduction is exactly 1)
/// are TRAININGOS-DESIGNED defaults, the same illustrative-default
/// discipline already applied to `PhaseDurationDefaults`/
/// `TacticalWindowPolicy.fallbackWindowWeeks` — not a validated
/// sports-science claim.
enum EvaluateReadinessAdaptationUseCase {
    /// TRAININGOS-DESIGNED: 2 or more of the 3 Tier-0 signals reported
    /// `.poor` means no single lower-level response (substitution, a
    /// 1-set reduction) is judged adequate — escalate to a postpone
    /// recommendation instead (`READINESS_DECISION_MODEL.md` §2's
    /// escalation rule).
    static let postponeThresholdPoorSignalCount = 2

    static func evaluate(session: Session, checkIn: ReadinessCheckIn, environment: TrainingEnvironment?, modelContext: ModelContext) -> ReadinessAdaptationProposal {
        var items: [ReadinessAdaptationProposalItem] = []

        let poorTier0: [(ReadinessSignalSource, ReadinessLevel?)] = [
            (.poorSleep, checkIn.sleep), (.lowEnergy, checkIn.energy), (.poorOverallRecovery, checkIn.overallRecovery)
        ]
        let poorSignals = poorTier0.filter { $0.1 == .poor }.map(\.0)

        if poorSignals.count >= postponeThresholdPoorSignalCount {
            items.append(ReadinessAdaptationProposalItem(
                triggeringSignals: poorSignals,
                actionKind: .postponeRecommended,
                explanation: "Multiple readiness signals are low today. TrainingOS recommends postponing this session rather than training through it — this is only a recommendation, not an automatic change.",
                workoutBlock: nil
            ))
        } else if poorSignals.count == 1, let signal = poorSignals.first {
            for block in session.orderedBlocks where isStrengthFamily(block.type) {
                for prescription in block.orderedPrescriptions {
                    guard prescription.executableSetPrescriptions.count > 1 else { continue }
                    let current = prescription.executableSetPrescriptions.count
                    items.append(ReadinessAdaptationProposalItem(
                        triggeringSignals: [signal],
                        actionKind: .setCountReduced,
                        explanation: "\(tier0Label(signal)) is reduced today. Keep the same load, but reduce \(prescription.exercise?.canonicalName ?? "this exercise") from \(current) sets to \(current - 1).",
                        exercisePrescription: prescription,
                        originalSetCount: current,
                        proposedSetCount: current - 1
                    ))
                }
            }
        }

        let allExercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []

        for block in session.orderedBlocks where isStrengthFamily(block.type) {
            for prescription in block.orderedPrescriptions {
                guard let exercise = prescription.exercise else { continue }
                let volumeReductionItem: () -> ReadinessAdaptationProposalItem? = {
                    let current = prescription.executableSetPrescriptions.count
                    guard current > 1 else { return nil }
                    return ReadinessAdaptationProposalItem(
                        triggeringSignals: [.pain], actionKind: .setCountReduced,
                        explanation: "\(exercise.canonicalName) may aggravate reported pain and no compatible alternative is available today. Reduce it from \(current) sets to \(current - 1) rather than removing the whole block, since other exercises share it.",
                        exercisePrescription: prescription, originalSetCount: current, proposedSetCount: current - 1
                    )
                }
                guard let item = localItem(
                    for: exercise, checkIn: checkIn, allExercises: allExercises,
                    slot: prescription.sourceExerciseSlot, environment: environment,
                    onSubstitute: { candidate in
                        ReadinessAdaptationProposalItem(
                            triggeringSignals: [.pain], actionKind: .exerciseSubstituted,
                            explanation: "\(exercise.canonicalName) may aggravate reported pain. Replace it with \(candidate.canonicalName)?",
                            exercisePrescription: prescription, originalExercise: exercise, proposedExercise: candidate
                        )
                    },
                    // No valid substitute: a multi-exercise block falls back
                    // to reducing just this one exercise's volume — never
                    // removing sibling exercises' work along with it.
                    // Removing the WHOLE block is reserved for a
                    // single-exercise block, where "reduce it" and "remove
                    // it" are the same choice anyway.
                    onRemoveBlock: {
                        if block.orderedPrescriptions.count > 1, let reduced = volumeReductionItem() {
                            return reduced
                        }
                        return ReadinessAdaptationProposalItem(
                            triggeringSignals: [.pain], actionKind: .blockRemoved,
                            explanation: "\(exercise.canonicalName) may aggravate reported pain and no compatible alternative is available today. Remove this block?",
                            workoutBlock: block
                        )
                    },
                    onReduceVolume: { signal in
                        let current = prescription.executableSetPrescriptions.count
                        guard current > 1 else { return nil }
                        return ReadinessAdaptationProposalItem(
                            triggeringSignals: [signal], actionKind: .setCountReduced,
                            explanation: "Reported \(signal == .stiffness ? "stiffness" : "soreness") near \(exercise.canonicalName). Reduce it from \(current) sets to \(current - 1)?",
                            exercisePrescription: prescription, originalSetCount: current, proposedSetCount: current - 1
                        )
                    }
                ) else { continue }
                items.append(item)
            }
        }

        for block in session.orderedBlocks where block.type == .functionalFitness {
            guard let prescription = block.functionalFitnessPrescription else { continue }
            for movement in prescription.orderedMovements {
                guard let exercise = movement.exercise else { continue }
                guard let item = localItem(
                    for: exercise, checkIn: checkIn, allExercises: allExercises,
                    slot: movement.sourceExerciseSlot, environment: environment,
                    onSubstitute: { candidate in
                        ReadinessAdaptationProposalItem(
                            triggeringSignals: [.pain], actionKind: .exerciseSubstituted,
                            explanation: "\(exercise.canonicalName) may aggravate reported pain. Replace it with \(candidate.canonicalName)?",
                            functionalFitnessMovement: movement, originalExercise: exercise, proposedExercise: candidate
                        )
                    },
                    onRemoveBlock: {
                        ReadinessAdaptationProposalItem(
                            triggeringSignals: [.pain], actionKind: .blockRemoved,
                            explanation: "\(exercise.canonicalName) may aggravate reported pain and no compatible alternative is available today. Remove this block?",
                            workoutBlock: block
                        )
                    },
                    // Functional Fitness has no implemented Level 2 mechanism
                    // (Stage 8B audit: reducing a scored metcon's internal
                    // demand requires a new training-science policy — see
                    // the implementation report). Stiffness/soreness near a
                    // Functional Fitness movement produce no proposal item
                    // in this stage rather than inventing one.
                    onReduceVolume: { _ in nil }
                ) else { continue }
                items.append(item)
            }
        }

        return ReadinessAdaptationProposal(items: items)
    }

    private static func isStrengthFamily(_ type: WorkoutBlockType) -> Bool {
        type == .strength || type == .hypertrophy || type == .accessory
    }

    private static func tier0Label(_ signal: ReadinessSignalSource) -> String {
        switch signal {
        case .poorSleep: return "Sleep"
        case .lowEnergy: return "Energy"
        case .poorOverallRecovery: return "Recovery"
        default: return "Readiness"
        }
    }

    /// Shared precedence for one exercise reference, regardless of whether
    /// it's a strength `ExercisePrescription` or a Functional Fitness
    /// `FunctionalFitnessMovement`: pain outranks stiffness outranks
    /// soreness (`READINESS_DECISION_MODEL.md` §2 — pain triggers more
    /// conservative handling than a milder signal on the same area).
    private static func localItem(
        for exercise: Exercise,
        checkIn: ReadinessCheckIn,
        allExercises: [Exercise],
        slot: ExerciseSlot?,
        environment: TrainingEnvironment?,
        onSubstitute: (Exercise) -> ReadinessAdaptationProposalItem,
        onRemoveBlock: () -> ReadinessAdaptationProposalItem,
        onReduceVolume: (ReadinessSignalSource) -> ReadinessAdaptationProposalItem?
    ) -> ReadinessAdaptationProposalItem? {
        let targets = Set(exercise.primaryTargets)
        guard !targets.isEmpty else { return nil }

        if !targets.isDisjoint(with: Set(checkIn.reportedPain)) {
            if let slot, let candidate = validSubstitute(excluding: exercise, targeting: checkIn.reportedPain, from: allExercises, slot: slot, environment: environment) {
                return onSubstitute(candidate)
            }
            return onRemoveBlock()
        }
        if !targets.isDisjoint(with: Set(checkIn.reportedStiffness)) {
            return onReduceVolume(.stiffness)
        }
        if !targets.isDisjoint(with: Set(checkIn.soreMuscleGroups)) {
            return onReduceVolume(.localSoreness)
        }
        return nil
    }

    /// A candidate that is valid for the slot AND whose own targets don't
    /// themselves overlap the reported pain area — never propose swapping
    /// one painful movement for another that hits the same area.
    private static func validSubstitute(
        excluding current: Exercise, targeting painAreas: [MuscleGroup], from allExercises: [Exercise], slot: ExerciseSlot, environment: TrainingEnvironment?
    ) -> Exercise? {
        allExercises.first { candidate in
            candidate.id != current.id
                && SubstitutionValidator.isValid(candidate: candidate, for: slot, environment: environment)
                && Set(candidate.primaryTargets).isDisjoint(with: Set(painAreas))
        }
    }
}
