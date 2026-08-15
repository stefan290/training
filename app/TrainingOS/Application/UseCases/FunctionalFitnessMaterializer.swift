import Foundation
import SwiftData

enum FunctionalFitnessMaterializationError: Error, Equatable {
    /// §15/§42: a template configured with `requiresRecentExposureToProgress`
    /// was asked to materialize a week beyond the first with no exposure
    /// history supplied — thrown rather than silently falling back to
    /// the unadjusted target stimulus, mirroring
    /// `IntervalMaterializationError.previousOutcomeRequired`'s identical
    /// precedent.
    case previousExposureRequired
    /// §38: the resolved workout failed Stage-E stimulus validation —
    /// thrown rather than shipping a workout that contradicts its
    /// requested stimulus. Carries the failing `StimulusValidation` for
    /// the caller to inspect.
    case stimulusValidationFailed(StimulusValidation)
}

/// Turns a Functional Fitness `ProgramDefinition`'s template graph into
/// real, dated execution rows — the Functional Fitness sibling of
/// `StrengthMaterializer`/`SteadyStateMaterializer`/`IntervalMaterializer`.
/// Runs Stage D (concrete exercise selection) and Stage E (stimulus
/// validation) of the pipeline — see `FunctionalFitnessProgramGenerator`'s
/// own doc comment for why those two stages live here, not in the
/// generator.
///
/// **Scope, stated plainly:** materializes one week at a time, always —
/// like `IntervalMaterializer`, a Functional Fitness template's rules may
/// require live exposure history this materializer cannot fabricate.
enum FunctionalFitnessMaterializer {
    @discardableResult
    static func materializeWeek(
        definition: ProgramDefinition,
        instance: ProgramInstance,
        weekIndex: Int,
        startDate: Date,
        ownerUserID: UUID,
        candidateExercises: [Exercise],
        exposureHistory: [VarianceExposureRecord],
        context: ModelContext
    ) throws -> [Session] {
        var sessions: [Session] = []
        let weekStartDate = Calendar.current.date(byAdding: .day, value: weekIndex * 7, to: startDate) ?? startDate
        let orderedTemplateSessions = definition.orderedTemplateSessions.filter { $0.activeFromWeek <= weekIndex }

        for (dayIndex, templateSession) in orderedTemplateSessions.enumerated() {
            let date = Calendar.current.date(byAdding: .day, value: dayIndex, to: weekStartDate) ?? weekStartDate
            let day = Day(ownerUserID: ownerUserID, date: date)
            context.insert(day)

            let session = Session(name: templateSession.name, modality: .functionalFitness, status: .scheduled, role: templateSession.role)
            context.insert(session)
            day.addSession(session)
            instance.addSession(session)
            sessions.append(session)

            for blockTemplate in templateSession.orderedBlockTemplates {
                if !blockTemplate.prescriptionTemplates.isEmpty {
                    materializeStrengthBlock(blockTemplate: blockTemplate, session: session, instance: instance, context: context)
                    continue
                }

                guard let ffTemplate = blockTemplate.functionalFitnessPrescriptionTemplate else { continue }

                if ffTemplate.requiresRecentExposureToProgress, weekIndex > 0, exposureHistory.isEmpty {
                    throw FunctionalFitnessMaterializationError.previousExposureRequired
                }

                let decision = FunctionalFitnessDecisionEngine().decide(ProgrammingDecisionInput(
                    exposureHistory: exposureHistory,
                    stimulusRequirements: ffTemplate.stimulus,
                    varianceConstraints: ffTemplate.varianceConstraints ?? VarianceConstraints()
                ))

                let block = WorkoutBlock(type: blockTemplate.type)
                context.insert(block)
                session.addBlock(block)
                block.trainingStressProfile = FunctionalFitnessStressProfileMapper.map(stimulus: decision.nextStimulus)

                let prescription = FunctionalFitnessPrescription(stimulus: decision.nextStimulus, format: ffTemplate.format)
                context.insert(prescription)
                block.attachFunctionalFitnessPrescription(prescription)

                var resolvedModalities: Set<FunctionalModality> = []
                var resolvedLoadingRoles: [LoadingClassification] = []

                for slotTemplate in ffTemplate.orderedMovementSlots {
                    guard let exerciseSlot = slotTemplate.exerciseSlot else { continue }
                    // Stage D: GOING FORWARD override wins, matching every
                    // other materializer's identical precedent; otherwise
                    // the first candidate satisfying the slot's typed
                    // constraints — deterministic, never a name-parsed or
                    // random pick (§9/§29).
                    let resolvedExercise = SubstituteExerciseUseCase.resolvedExercise(for: exerciseSlot, in: instance)
                        ?? candidateExercises.first { SubstitutionValidator.isValid(candidate: $0, for: exerciseSlot) }

                    let movement = FunctionalFitnessMovement(
                        exercise: resolvedExercise,
                        reps: slotTemplate.reps,
                        calories: slotTemplate.calories,
                        distanceMeters: slotTemplate.distanceMeters,
                        loadKilograms: slotTemplate.loadKilograms,
                        minuteSlot: slotTemplate.minuteSlot
                    )
                    context.insert(movement)
                    prescription.addMovement(movement)

                    if let modality = resolvedExercise?.functionalModality { resolvedModalities.insert(modality) }
                    if let loadingRole = slotTemplate.loadingRole { resolvedLoadingRoles.append(loadingRole) }
                }

                // Stage E: never ship a workout that contradicts its
                // requested stimulus (§38) — an empty `resolvedModalities`
                // (no candidate could fill any slot) also fails here,
                // which is correct: §37's "do not silently create
                // impossible workouts" applies just as much to "the
                // catalog has nothing valid for this slot" as to missing
                // equipment specifically.
                let validation = FunctionalFitnessStimulusValidator.validate(
                    format: ffTemplate.format, resolvedModalities: resolvedModalities,
                    resolvedLoadingRoles: resolvedLoadingRoles, against: decision.nextStimulus
                )
                guard validation.passes else {
                    throw FunctionalFitnessMaterializationError.stimulusValidationFailed(validation)
                }
            }
        }

        return sessions
    }

    /// §20: strength + metcon composition. Deliberately minimal — a
    /// fixed, non-autoregulated prescription (no live RM/equipment
    /// input), proving the composition itself (one Session, ordered
    /// heterogeneous blocks) rather than re-deriving
    /// `StrengthProgressionEngine`'s full machinery, which is already
    /// proven elsewhere (Stage 4A/4B). `targetWeight: nil` is a valid,
    /// honest "calibration required" state, not a gap.
    private static func materializeStrengthBlock(blockTemplate: WorkoutBlockTemplate, session: Session, instance: ProgramInstance, context: ModelContext) {
        guard let prescriptionTemplate = blockTemplate.prescriptionTemplates.first, let slot = prescriptionTemplate.exerciseSlot else { return }
        let block = WorkoutBlock(type: blockTemplate.type)
        context.insert(block)
        session.addBlock(block)

        let resolvedExercise = SubstituteExerciseUseCase.resolvedExercise(for: slot, in: instance)
        let prescription = ExercisePrescription(exercise: resolvedExercise)
        context.insert(prescription)
        block.addPrescription(prescription)

        let repGoal = prescriptionTemplate.repGoalSchedule.first
        var setCount = 0
        if case .fixed(let setsByWeek) = prescriptionTemplate.setCountRule {
            setCount = setsByWeek.first ?? 0
        }
        for _ in 0..<setCount {
            let setPrescription = SetPrescription(repRangeLow: repGoal?.reps ?? 0, repRangeHigh: repGoal?.reps ?? 0, targetWeight: nil)
            context.insert(setPrescription)
            prescription.addSetPrescription(setPrescription)
        }
    }
}
