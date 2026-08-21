import Foundation
import SwiftData

enum ReadinessAdaptationDecisionError: Error, Equatable {
    case missingRequiredField
}

/// Stage 8B: applies an accepted (or records a rejected)
/// `ReadinessAdaptationProposalItem` — the only place a same-day readiness
/// adaptation is actually written to the model graph. Every mutation goes
/// through an EXISTING mechanism (`SubstituteExerciseUseCase`/
/// `SubstituteFunctionalFitnessMovementUseCase`, `SetPrescription
/// .isAdaptedAway`, `WorkoutBlock.status`, `ChangeSessionStatusUseCase.skip`)
/// — never a new bespoke mutation path, and never a change to
/// `ProgramDefinition`/the template graph (`READINESS_ADAPTATION_PIPELINE.md`
/// §3). Persists a `ReadinessAdaptationDecision` either way, so a rejected
/// proposal is exactly as durably recorded as an accepted one
/// (Stage 8B §7/§8 — "persist whether the user accepted or rejected").
enum ReadinessAdaptationDecisionUseCase {
    @discardableResult
    static func accept(
        _ item: ReadinessAdaptationProposalItem,
        session: Session,
        checkIn: ReadinessCheckIn,
        decidedAt: Date,
        modelContext: ModelContext
    ) throws -> ReadinessAdaptationDecision {
        switch item.actionKind {
        case .loadReduced:
            // Not automatically produced by `EvaluateReadinessAdaptationUseCase`
            // in Stage 8B (see `ReadinessActionKind.loadReduced`'s own doc
            // comment) — nothing to apply to the model graph beyond
            // recording the decision itself below, since no automatic path
            // constructs one of these yet.
            break

        case .setCountReduced:
            guard let prescription = item.exercisePrescription, let proposed = item.proposedSetCount else {
                throw ReadinessAdaptationDecisionError.missingRequiredField
            }
            let executable = prescription.executableSetPrescriptions
            let numberToAdaptAway = max(0, executable.count - proposed)
            for setPrescription in executable.suffix(numberToAdaptAway) {
                setPrescription.isAdaptedAway = true
            }

        case .exerciseSubstituted:
            guard let candidate = item.proposedExercise else {
                throw ReadinessAdaptationDecisionError.missingRequiredField
            }
            if let prescription = item.exercisePrescription, let slot = prescription.sourceExerciseSlot {
                try SubstituteExerciseUseCase.substituteThisSessionOnly(
                    prescription: prescription, slot: slot, with: candidate, reason: .readinessAdaptation
                )
            } else if let movement = item.functionalFitnessMovement {
                try SubstituteFunctionalFitnessMovementUseCase.substituteThisSessionOnly(
                    movement: movement, with: candidate, reason: .readinessAdaptation
                )
            } else {
                throw ReadinessAdaptationDecisionError.missingRequiredField
            }

        case .blockRemoved:
            guard let block = item.workoutBlock else { throw ReadinessAdaptationDecisionError.missingRequiredField }
            block.status = .skipped

        case .postponeRecommended:
            try ChangeSessionStatusUseCase.skip(session, modelContext: modelContext)

        case .noChangeConfirmed:
            break
        }

        let decision = makeDecision(item, checkIn: checkIn, decidedAt: decidedAt, userResponse: .accepted)
        modelContext.insert(decision)
        try modelContext.save()
        return decision
    }

    /// Rejecting mutates nothing — the executable prescription/block/
    /// session status is left exactly as originally materialized. Still
    /// persists a decision record so "the user was shown this and said no"
    /// is as durable and explainable as an acceptance.
    @discardableResult
    static func reject(
        _ item: ReadinessAdaptationProposalItem,
        checkIn: ReadinessCheckIn,
        decidedAt: Date,
        choseAlternative: Bool = false,
        modelContext: ModelContext
    ) throws -> ReadinessAdaptationDecision {
        let decision = makeDecision(
            item, checkIn: checkIn, decidedAt: decidedAt,
            userResponse: choseAlternative ? .rejectedChoseAlternative : .rejectedKeptOriginal
        )
        modelContext.insert(decision)
        try modelContext.save()
        return decision
    }

    private static func makeDecision(
        _ item: ReadinessAdaptationProposalItem, checkIn: ReadinessCheckIn, decidedAt: Date, userResponse: UserAdaptationResponse
    ) -> ReadinessAdaptationDecision {
        ReadinessAdaptationDecision(
            decidedAt: decidedAt,
            triggeringSignals: item.triggeringSignals,
            actionKind: item.actionKind,
            userResponse: userResponse,
            explanation: item.explanation,
            originalSetCount: item.originalSetCount,
            proposedSetCount: item.proposedSetCount,
            originalExercise: item.originalExercise,
            proposedExercise: item.proposedExercise,
            exercisePrescription: item.exercisePrescription,
            functionalFitnessMovement: item.functionalFitnessMovement,
            workoutBlock: item.workoutBlock,
            readinessCheckIn: checkIn
        )
    }
}
