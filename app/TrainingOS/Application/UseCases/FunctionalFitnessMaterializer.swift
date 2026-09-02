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
    /// Stage TE.1: no `TrainingEnvironment` was supplied at all — thrown
    /// BEFORE any candidate-resolution loop runs, never silently treated
    /// as "everything is compatible." Distinct from
    /// `.environmentIncompatible` below (a real environment exists, it
    /// just can't satisfy this one slot).
    case trainingEnvironmentRequired
    /// Stage TE.1: a real, configured environment exists, but no
    /// candidate in the pool for this movement slot satisfies it (every
    /// candidate's `requiredEquipment` came back `.incompatible`) —
    /// thrown rather than leaving the slot unresolved or silently
    /// substituting an unrelated movement.
    case environmentIncompatible(slot: String, missingEquipment: [EquipmentRequirement])
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
        /// Stage CP.2 addition. Real, already-materialized SAME-WEEK
        /// `.primary`-priority sibling stress (computed by the caller,
        /// e.g. `RollTacticalWindowUseCase.rollForward`'s producer pass)
        /// — empty when no such context is available (e.g. week 0, via
        /// `materializeFirstWindow`, which has no cross-component pass to
        /// draw this from). See `ProgrammingDecisionInput`'s own doc
        /// comment.
        protectedSiblingStressProfilesThisWeek: [TrainingStressProfile] = [],
        /// Stage CP.2 addition. This component's own real, locked
        /// `AdaptationObjective`s — see `TrainingMixComponent
        /// .adaptationObjectives`.
        componentAdaptationObjectives: [AdaptationObjective] = [],
        /// Stage TE.1: read fresh from `TacticalMaterializationContext
        /// .trainingEnvironment` at each real call — never cached/frozen.
        /// `nil` is a valid, honest "not yet configured" state; it is
        /// never treated as "anything goes" (see the fail-fast guard
        /// below and `TrainingEnvironmentCompatibilityRule`).
        environment: TrainingEnvironment?,
        context: ModelContext
    ) throws -> [Session] {
        var sessions: [Session] = []
        let weekStartDate = Calendar.current.date(byAdding: .day, value: weekIndex * 7, to: startDate) ?? startDate
        let orderedTemplateSessions = definition.orderedTemplateSessions.filter { $0.activeFromWeek <= weekIndex }

        // Stage CP.2: every real `LongTermPlanner`-built `TrainingMix` has
        // at most ONE Functional Fitness `TrainingMixComponent` (confirmed
        // by audit) — so "FF-A"/"FF-B" same-week coordination is not
        // cross-component, it's this SAME component's own multiple weekly
        // sessions, decided one after another within THIS one call.
        // Started fresh per call, never persisted, never read from a
        // `ModelContext`.
        var currentWeekContext = CurrentWeekFunctionalFitnessProgrammingContext()

        for (dayIndex, templateSession) in orderedTemplateSessions.enumerated() {
            let date = Calendar.current.date(byAdding: .day, value: dayIndex, to: weekStartDate) ?? weekStartDate
            let day = Day(ownerUserID: ownerUserID, date: date)
            context.insert(day)

            let session = Session(name: templateSession.name, modality: .functionalFitness, status: .scheduled, role: templateSession.role)
            session.materializedInEnvironment = environment
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

                // Stage FF.L1: one real decision flow yields both INTENDED
                // (Phase 1, pre-CP.2 intent) and FINAL (Phase 2, post-CP.2
                // adaptation) — everything below that used to read
                // `decision.nextStimulus` wants FINAL specifically (what
                // was actually prescribed), exactly as before.
                let decision = FunctionalFitnessDecisionEngine().decideWithIntent(ProgrammingDecisionInput(
                    exposureHistory: exposureHistory,
                    stimulusRequirements: ffTemplate.stimulus,
                    varianceConstraints: ffTemplate.varianceConstraints ?? VarianceConstraints(),
                    componentAdaptationObjectives: componentAdaptationObjectives,
                    protectedSiblingStressProfilesThisWeek: protectedSiblingStressProfilesThisWeek,
                    currentWeekContext: currentWeekContext
                ))
                // Same-week FF complementarity coordinates against what a
                // sibling session is ACTUALLY programmed to do after CP.2
                // adaptation, not its pre-adaptation intent — FINAL, not
                // INTENDED (verified against CP.2's own same-week pairing
                // contract; see the design doc's Design Lock, item 9).
                currentWeekContext.record(stimulus: decision.finalStimulus)

                let block = WorkoutBlock(type: blockTemplate.type)
                context.insert(block)
                session.addBlock(block)
                block.trainingStressProfile = FunctionalFitnessStressProfileMapper.map(stimulus: decision.finalStimulus)

                let prescription = FunctionalFitnessPrescription(
                    stimulus: decision.finalStimulus, intendedStimulus: decision.intendedStimulus, format: ffTemplate.format
                )
                context.insert(prescription)
                block.attachFunctionalFitnessPrescription(prescription)

                var resolvedModalities: Set<FunctionalModality> = []
                var resolvedLoadingRoles: [LoadingClassification] = []

                // Stage TE.1 fail-fast guard: checked once, immediately
                // before this block's own candidate-resolution loop —
                // never entered with an unknown environment silently
                // treated as "anything goes."
                if !ffTemplate.orderedMovementSlots.isEmpty, environment == nil {
                    throw FunctionalFitnessMaterializationError.trainingEnvironmentRequired
                }

                for slotTemplate in ffTemplate.orderedMovementSlots {
                    guard let exerciseSlot = slotTemplate.exerciseSlot else { continue }

                    // Stage TE.1 (§K/§L): a narrowed main-lift/competition
                    // slot (`allowedExercises` non-empty) is precisely
                    // attributable — the allow-list branch short-circuits
                    // every other dimension, so if none of its explicitly
                    // listed exercises are environment-compatible, that IS
                    // the whole reason this slot is unsatisfiable. Checked
                    // before the general search below so this precise,
                    // typed cause is reported instead of the vaguer
                    // general "no candidate resolved" outcome. A slot with
                    // no `allowedExercises` restriction can fail for many
                    // reasons (target/movementFunction mismatch too) —
                    // misattributing every such failure to environment
                    // would be inventing a cause this code cannot actually
                    // prove, so that general case is left to the existing,
                    // already-correct Stage E stimulus validation below.
                    if !exerciseSlot.allowedExercises.isEmpty,
                       !exerciseSlot.allowedExercises.contains(where: {
                           TrainingEnvironmentCompatibilityRule.evaluate(required: $0.requiredEquipment, environment: environment) == .compatible
                       }) {
                        let missing = Set(exerciseSlot.allowedExercises.flatMap(\.requiredEquipment)).subtracting(Set(environment?.availableEquipment ?? []))
                        throw FunctionalFitnessMaterializationError.environmentIncompatible(slot: exerciseSlot.name, missingEquipment: Array(missing))
                    }

                    // Stage D: GOING FORWARD override wins, matching every
                    // other materializer's identical precedent; otherwise
                    // the first candidate satisfying the slot's typed
                    // constraints — deterministic, never a name-parsed or
                    // random pick (§9/§29).
                    let resolvedExercise = SubstituteExerciseUseCase.resolvedExercise(for: exerciseSlot, in: instance)
                        ?? candidateExercises.first { SubstitutionValidator.isValid(candidate: $0, for: exerciseSlot, environment: environment) }

                    // Stage FF.P1: a real, non-nil structural target,
                    // resolved AFTER Stage D above has already picked the
                    // real Exercise (the one real exception — Assault Bike
                    // — depends on it). The generator itself never sets
                    // `slotTemplate.reps`/`.distanceMeters` for real
                    // generated content, so a nil template value here
                    // reliably means "not authored" — an explicit
                    // hand-authored/seed/benchmark value always wins and
                    // is never overwritten by this generated default.
                    let generatedTarget = FunctionalFitnessMovementTargetRule.resolve(
                        format: ffTemplate.format, modality: exerciseSlot.allowedModalities.first,
                        movementFunctions: exerciseSlot.allowedMovementFunctions, exercise: resolvedExercise
                    )

                    let movement = FunctionalFitnessMovement(
                        exercise: resolvedExercise,
                        reps: slotTemplate.reps ?? generatedTarget.reps,
                        calories: slotTemplate.calories,
                        distanceMeters: slotTemplate.distanceMeters ?? generatedTarget.distanceMeters,
                        loadKilograms: slotTemplate.loadKilograms,
                        minuteSlot: slotTemplate.minuteSlot
                    )
                    context.insert(movement)
                    // Stage FF.P1: a real, pre-existing gap this stage
                    // closes as necessary infrastructure — without this,
                    // `SubstituteFunctionalFitnessMovementUseCase` (and the
                    // real readiness-adaptation flow that calls it) could
                    // never validate or apply a same-session substitution
                    // against any real generated Functional Fitness
                    // movement at all, since it requires this field.
                    // Mirrors `StrengthMaterializer`'s identical, already-
                    // established `prescription.sourceExerciseSlot = slot`
                    // pattern exactly — no new mechanism, no change to
                    // `SubstitutionValidator`/eligibility/readiness policy.
                    movement.sourceExerciseSlot = exerciseSlot
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
                    resolvedLoadingRoles: resolvedLoadingRoles, against: decision.finalStimulus
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

        // Functional Fitness's strength block always uses a genuine fixed
        // rep prescription (`FunctionalFitnessProgramGenerator`'s only
        // rep-goal construction) — never an RIR/effort target.
        let fixedReps: Int? = {
            guard case .fixedReps(let n) = prescriptionTemplate.repGoalSchedule.first?.prescription else { return nil }
            return n
        }()
        var setCount = 0
        if case .fixed(let setsByWeek) = prescriptionTemplate.setCountRule {
            setCount = setsByWeek.first ?? 0
        }
        for _ in 0..<setCount {
            let setPrescription = SetPrescription(repRangeLow: fixedReps, repRangeHigh: fixedReps, targetWeight: nil)
            context.insert(setPrescription)
            prescription.addSetPrescription(setPrescription)
        }
    }
}
