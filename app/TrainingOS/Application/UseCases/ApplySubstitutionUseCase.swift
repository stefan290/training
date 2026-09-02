import Foundation
import SwiftData

/// Stage 6B: the orchestrating use case behind every substitution/scaling
/// choice made during execution — wraps the existing Stage 4C
/// `SubstituteExerciseUseCase`/`SubstituteActivityUseCase` (both scopes:
/// Today only / Going forward) and saves immediately
/// (`WORKOUT_COMPLETION_PIPELINE.md` §1, `STRENGTH_EXECUTION_FLOW.md` §7,
/// `ENDURANCE_EXECUTION_FLOW.md` §3). Never saves on a thrown validation
/// failure — nothing succeeded, so nothing should persist.
enum ApplySubstitutionUseCase {
    @discardableResult
    static func substituteExerciseThisSessionOnly(
        prescription: ExercisePrescription,
        slot: ExerciseSlot,
        with exercise: Exercise,
        reason: SubstitutionReason? = nil,
        environment: TrainingEnvironment?,
        modelContext: ModelContext
    ) throws -> ExercisePrescription {
        let updated = try SubstituteExerciseUseCase.substituteThisSessionOnly(
            prescription: prescription, slot: slot, with: exercise, reason: reason, environment: environment
        )
        try modelContext.save()
        return updated
    }

    @discardableResult
    static func substituteExerciseGoingForward(
        instance: ProgramInstance,
        slot: ExerciseSlot,
        with exercise: Exercise,
        reason: SubstitutionReason? = nil,
        environment: TrainingEnvironment?,
        modelContext: ModelContext
    ) throws -> SlotSelectionOverride {
        let override = try SubstituteExerciseUseCase.substituteGoingForward(
            instance: instance, slot: slot, with: exercise, reason: reason, environment: environment, context: modelContext
        )
        try modelContext.save()
        return override
    }

    @discardableResult
    static func substituteActivityThisSessionOnly(
        prescription: SteadyStatePrescription,
        template: ActivitySubstitutionTemplate,
        with activityType: ActivityType,
        reason: SubstitutionReason? = nil,
        modelContext: ModelContext
    ) throws -> SteadyStatePrescription {
        let updated = try SubstituteActivityUseCase.substituteThisSessionOnly(
            prescription: prescription, template: template, with: activityType, reason: reason
        )
        try modelContext.save()
        return updated
    }

    @discardableResult
    static func substituteActivityThisSessionOnly(
        prescription: IntervalPrescription,
        template: ActivitySubstitutionTemplate,
        with activityType: ActivityType,
        reason: SubstitutionReason? = nil,
        modelContext: ModelContext
    ) throws -> IntervalPrescription {
        let updated = try SubstituteActivityUseCase.substituteThisSessionOnly(
            prescription: prescription, template: template, with: activityType, reason: reason
        )
        try modelContext.save()
        return updated
    }

    @discardableResult
    static func substituteActivityGoingForward(
        instance: ProgramInstance,
        templateBlock: WorkoutBlockTemplate,
        eligibilityTemplate: ActivitySubstitutionTemplate,
        with activityType: ActivityType,
        reason: SubstitutionReason? = nil,
        modelContext: ModelContext
    ) throws -> ActivitySelectionOverride {
        let override = try SubstituteActivityUseCase.substituteGoingForward(
            instance: instance, templateBlock: templateBlock, eligibilityTemplate: eligibilityTemplate,
            with: activityType, reason: reason, context: modelContext
        )
        try modelContext.save()
        return override
    }
}
