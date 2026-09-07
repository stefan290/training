import Foundation
import SwiftData

/// V1 R5 (Training Environment product reconciliation), Part 1: "use
/// Home Gym for THIS workout" — minimum-necessary, this-session-only
/// exercise substitution driven by a real `TrainingEnvironment` other
/// than the one the Session was originally materialized/defaulted
/// against.
///
/// **Composes 100% pre-existing, already-tested production primitives —
/// no new rematerialization architecture, no new persisted prescription
/// model, no change to `ProgramInstance`/`TrainingMix`/any other
/// Session:**
/// - `TrainingEnvironmentCompatibilityRule.evaluate` decides which of
///   this Session's already-materialized `ExercisePrescription`s are
///   actually incompatible with the target environment — a compatible
///   prescription is never touched.
/// - `SubstitutionCandidateRanking.rank` (Stage 4C/6B, unmodified) finds
///   a real, semantically-eligible, environment-compatible replacement
///   for that exact `ExerciseSlot` — never a different slot, never a
///   fabricated exercise.
/// - `SubstituteExerciseUseCase.substituteThisSessionOnly` (Stage 4C,
///   unmodified) is the ONLY write this performs — it edits the
///   `ExercisePrescription` already attached to THIS Session in place;
///   it has no path to `ExerciseSlot.resolvedExercise` (the
///   `ProgramInstance`-level template default) or to any other Session,
///   and it never writes a `SlotSelectionOverride` (the distinct,
///   separate "going forward" mechanism) — so this adaptation can never
///   silently become a persistent substitution preference.
///
/// **Progression safety**, proven by `WorkoutEnvironmentAdaptationUseCaseTests`:
/// `RecordSetResultUseCase`/every execution ViewModel already reads
/// `exercisePrescription.exercise` LIVE at logging time (confirmed by
/// direct trace — `StrengthExecutionViewModel`'s own
/// `exercise = movement.exercise`) — so a result logged after this
/// adaptation is automatically attributed to the SUBSTITUTE exercise's
/// own `ExercisePerformanceProfile`, never to the original prescription's
/// exercise, with zero new bookkeeping required here.
///
/// **A prescription with no `sourceExerciseSlot`** (an ad hoc/seed-
/// authored movement — `ExercisePrescription.sourceExerciseSlot`'s own
/// doc comment: "Change Exercise stays unavailable for those") is left
/// untouched even if environment-incompatible — this checkpoint's own
/// "do not invent a large solution" instruction forbids fabricating slot
/// identity that was never real.
enum WorkoutEnvironmentAdaptationUseCase {
    /// One real, already-materialized exercise this adaptation would
    /// change (or already reports as unadaptable) — never a fabricated
    /// pairing.
    struct Adaptation: Identifiable {
        var id: UUID { prescription.id }
        let prescription: ExercisePrescription
        let originalExercise: Exercise
        /// `nil` when no real, environment-compatible, semantically-
        /// eligible candidate exists for this slot — an honest,
        /// disclosed gap (this checkpoint's own "no generic placeholder
        /// Session" principle extended to the per-prescription case),
        /// never silently left as the original (which would remain
        /// genuinely incompatible with the chosen environment).
        let replacementExercise: Exercise?
    }

    /// Read-only: computes what WOULD change without writing anything —
    /// the athlete-facing "N exercises adapted" preview this checkpoint's
    /// own UX example requires, shown before any commitment.
    static func preview(
        session: Session, targetEnvironment: TrainingEnvironment, candidateExercises: [Exercise],
        curatedRelationships: [ExerciseRelationship], profileLookup: @escaping (Exercise) -> ExercisePerformanceProfile?
    ) -> [Adaptation] {
        var adaptations: [Adaptation] = []
        for block in session.orderedBlocks {
            for prescription in block.orderedPrescriptions {
                guard let currentExercise = prescription.exercise, let slot = prescription.sourceExerciseSlot else { continue }
                let compatibility = TrainingEnvironmentCompatibilityRule.evaluate(required: currentExercise.requiredEquipment, environment: targetEnvironment)
                guard compatibility != .compatible else { continue }
                let ranked = SubstitutionCandidateRanking.rank(
                    slot: slot, excluding: currentExercise, allExercises: candidateExercises,
                    curatedRelationships: curatedRelationships, profileLookup: profileLookup, environment: targetEnvironment
                )
                adaptations.append(Adaptation(prescription: prescription, originalExercise: currentExercise, replacementExercise: ranked.first?.exercise))
            }
        }
        return adaptations
    }

    /// Commits exactly the adaptations `preview` already found — every
    /// prescription with a real `replacementExercise` is substituted via
    /// `SubstituteExerciseUseCase.substituteThisSessionOnly` (which
    /// re-validates independently; this never bypasses that check).
    /// Prescriptions with `replacementExercise == nil` are left exactly
    /// as they were — genuinely unadaptable in this environment is
    /// disclosed, never silently forced.
    @discardableResult
    static func apply(_ adaptations: [Adaptation], environment: TrainingEnvironment) throws -> [Adaptation] {
        for adaptation in adaptations {
            guard let replacement = adaptation.replacementExercise else { continue }
            guard let slot = adaptation.prescription.sourceExerciseSlot else { continue }
            try SubstituteExerciseUseCase.substituteThisSessionOnly(
                prescription: adaptation.prescription, slot: slot, with: replacement,
                reason: .equipmentUnavailable, environment: environment
            )
        }
        return adaptations
    }
}
