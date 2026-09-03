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
/// **Stage FF.M1: Stage C (movement-slot composition) also moved here**,
/// for `isDynamicallyComposed == true` templates — the CONFIGURED →
/// INTENDED → FINAL → movement-composition contradiction (slots frozen at
/// generation time, before any real week's FINAL stimulus exists) is
/// closed by deferring Stage C to this same materialization call, reading
/// that week's real FINAL stimulus context via `FunctionalFitnessMovementComposer`.
/// `isDynamicallyComposed == false` (no real content today) keeps the
/// original, generation-time-slots path entirely unchanged.
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

        // Stage FF.M1: prescription-only history (never performance/score/
        // adherence/completion) — the immediately preceding tactical
        // week's REAL materialized movement functions/Exercises, read
        // directly from `instance`'s already-persisted rows regardless of
        // whether that week was ever completed. Never merged with
        // same-week exposure — kept as a wholly separate, secondary input
        // (`FunctionalFitnessMovementComposer`'s own contract).
        let priorWeekRange = priorWeekDateRange(weekStartDate: weekStartDate)
        let priorWeekMovements = priorWeekFunctionalFitnessMovements(instance: instance, dateRange: priorWeekRange)
        let priorWeekFunctionExposure = functionExposureCounts(from: priorWeekMovements)
        let priorWeekExerciseExposure = exerciseExposureCounts(from: priorWeekMovements)
        var movementComposer = FunctionalFitnessMovementComposer(priorWeekExposure: priorWeekFunctionExposure)
        // Stage FF.M1 closure: SAME-WEEK, across-session Exercise exposure
        // per MovementFunction — distinct from `usedExerciseIDsThisSession`
        // (resets every session) and from `priorWeekExerciseExposure`
        // (previous tactical week only). Without this, a MovementFunction
        // programmed in two different sessions the same week had nothing
        // preferring a different Exercise the second time before falling
        // to prior-week history. Threaded across the whole week, mutated
        // once per resolved Exercise, never merged with either of the
        // other two horizons.
        var thisWeekExerciseExposure: [MovementFunction: [UUID: Int]] = [:]

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

                let block = WorkoutBlock(type: blockTemplate.type)
                context.insert(block)
                session.addBlock(block)

                if ffTemplate.isDynamicallyComposed {
                    try materializeDynamicBlock(
                        ffTemplate: ffTemplate, decision: decision, block: block, session: session,
                        instance: instance, candidateExercises: candidateExercises, environment: environment,
                        movementComposer: &movementComposer, priorWeekExerciseExposure: priorWeekExerciseExposure,
                        thisWeekExerciseExposure: &thisWeekExerciseExposure,
                        currentWeekContext: &currentWeekContext, context: context
                    )
                } else {
                    try materializeAuthoredBlock(
                        ffTemplate: ffTemplate, decision: decision, block: block, instance: instance,
                        candidateExercises: candidateExercises, environment: environment,
                        currentWeekContext: &currentWeekContext, context: context
                    )
                }
            }
        }

        return sessions
    }

    // MARK: - Stage FF.M1: dynamically-composed FF (materialization-time Stage C)

    private static func materializeDynamicBlock(
        ffTemplate: FunctionalFitnessPrescriptionTemplate,
        decision: FunctionalFitnessProgrammingDecision,
        block: WorkoutBlock,
        session: Session,
        instance: ProgramInstance,
        candidateExercises: [Exercise],
        environment: TrainingEnvironment?,
        movementComposer: inout FunctionalFitnessMovementComposer,
        priorWeekExerciseExposure: [MovementFunction: [UUID: Int]],
        thisWeekExerciseExposure: inout [MovementFunction: [UUID: Int]],
        currentWeekContext: inout CurrentWeekFunctionalFitnessProgrammingContext,
        context: ModelContext
    ) throws {
        // Stage TE.1 fail-fast guard: unknown environment is never
        // treated as "anything goes," checked before any composition or
        // candidate-resolution runs.
        guard let environment else {
            throw FunctionalFitnessMaterializationError.trainingEnvironmentRequired
        }

        let eligibility = eligibleFunctions(candidateExercises: candidateExercises, environment: environment)
        let composedFunctions = movementComposer.composeSession(
            eligibleFunctions: eligibility.functions, monostructuralEligible: eligibility.monostructuralEligible
        )

        guard !composedFunctions.isEmpty else {
            // Stage FF.M1 minimum-coherent-session floor: zero classes had
            // any eligible candidate this session — an explicit typed
            // incompatibility, never an empty Session or a fabricated
            // cross-class substitute.
            let missing = Set(candidateExercises.flatMap(\.requiredEquipment)).subtracting(Set(environment.availableEquipment))
            throw FunctionalFitnessMaterializationError.environmentIncompatible(slot: "Functional Fitness Session", missingEquipment: Array(missing))
        }

        // Stage FF.M1 Correction L: FINAL stimulus.movementFunctions must
        // represent ACTUAL PRESCRIBED FUNCTIONS — overwritten from what
        // Stage C really composed this materialization, never left as the
        // old frozen CONFIGURED value.
        var finalStimulus = decision.finalStimulus
        finalStimulus.movementFunctions = composedFunctions
        currentWeekContext.record(stimulus: finalStimulus)
        block.trainingStressProfile = FunctionalFitnessStressProfileMapper.map(stimulus: finalStimulus)

        let prescription = FunctionalFitnessPrescription(stimulus: finalStimulus, intendedStimulus: decision.intendedStimulus, format: ffTemplate.format)
        context.insert(prescription)
        block.attachFunctionalFitnessPrescription(prescription)

        var resolvedModalities: Set<FunctionalModality> = []
        var usedExerciseIDsThisSession: Set<UUID> = []

        for function in composedFunctions {
            let modality = modality(for: function)
            let slot = ExerciseSlot(
                name: "\(modality.rawValue) - \(function.rawValue)",
                allowedMovementFunctions: [function],
                allowedModalities: [modality]
            )
            context.insert(slot)
            let slotTemplate = FunctionalFitnessMovementSlotTemplate()
            context.insert(slotTemplate)
            slotTemplate.attachExerciseSlot(slot)
            // Attached to the owning template (not just constructed
            // standalone) so `SubstituteFunctionalFitnessMovementUseCase`'s
            // existing `slot.owningFunctionalFitnessSlot?
            // .functionalFitnessPrescriptionTemplate?.format` lookup keeps
            // working unchanged — and so every week's real composed
            // content remains a truthful, cascading-deleted audit trail,
            // never read back as "this week's slots" via
            // `orderedMovementSlots` (that accumulates across every week
            // materialized so far; this dynamic path never reads it back).
            ffTemplate.addMovementSlot(slotTemplate)

            // Stage FF.M1 Decision B (Exercise selection): semantic
            // eligibility + TE.1 (unchanged `SubstitutionValidator.isValid`)
            // → same-session distinctness → GOING FORWARD preference for
            // this exact semantic role (stronger than automatic rotation —
            // it may legitimately repeat across every session that
            // programs this function this week) → THIS-WEEK,
            // across-session least-used preference → prior-week tie-break
            // → canonicalName stable tie-break. A multi-function Exercise
            // (Wall Ball/Thruster/Dumbbell Snatch) may fill only ONE role
            // per session, enforced by `usedExerciseIDsThisSession`.
            let eligible = candidateExercises.filter {
                SubstitutionValidator.isValid(candidate: $0, for: slot, environment: environment)
                    && !usedExerciseIDsThisSession.contains($0.id)
            }
            // Stage FF.M1 closure: a GOING FORWARD preference only wins
            // when it's already a member of `eligible` — i.e. it still
            // satisfies semantic eligibility, TE.1, and same-session
            // distinctness. Never deleted when temporarily unusable (an
            // environment/session that blocks it this time doesn't
            // invalidate it for a future week where it's valid again);
            // simply not consulted this time, falling through to the
            // normal rotation below.
            let preferredExercise = instance.functionalFitnessMovementFunctionOverride(for: function)?.selectedExercise
            let thisWeekExposureForFunction = thisWeekExerciseExposure[function] ?? [:]
            let priorExposureForFunction = priorWeekExerciseExposure[function] ?? [:]
            let resolvedExercise = preferredExercise.flatMap { preferred in eligible.first { $0.id == preferred.id } } ?? eligible.min { a, b in
                let thisWeekA = thisWeekExposureForFunction[a.id] ?? 0
                let thisWeekB = thisWeekExposureForFunction[b.id] ?? 0
                if thisWeekA != thisWeekB { return thisWeekA < thisWeekB }
                let priorA = priorExposureForFunction[a.id] ?? 0
                let priorB = priorExposureForFunction[b.id] ?? 0
                if priorA != priorB { return priorA < priorB }
                return a.canonicalName < b.canonicalName
            }
            if let resolvedExercise {
                usedExerciseIDsThisSession.insert(resolvedExercise.id)
                thisWeekExerciseExposure[function, default: [:]][resolvedExercise.id, default: 0] += 1
            }

            let generatedTarget = FunctionalFitnessMovementTargetRule.resolve(
                format: ffTemplate.format, modality: modality, movementFunctions: [function], exercise: resolvedExercise
            )

            let movement = FunctionalFitnessMovement(
                exercise: resolvedExercise, reps: generatedTarget.reps, calories: nil,
                distanceMeters: generatedTarget.distanceMeters, loadKilograms: nil, minuteSlot: nil
            )
            context.insert(movement)
            movement.sourceExerciseSlot = slot
            prescription.addMovement(movement)

            if let resolvedModality = resolvedExercise?.functionalModality { resolvedModalities.insert(resolvedModality) }
        }

        let validation = FunctionalFitnessStimulusValidator.validate(
            format: ffTemplate.format, resolvedModalities: resolvedModalities, resolvedLoadingRoles: [],
            resolvedMovementFunctions: Set(composedFunctions), against: finalStimulus
        )
        guard validation.passes else {
            throw FunctionalFitnessMaterializationError.stimulusValidationFailed(validation)
        }
    }

    /// Stage FF.M1's accepted movement space, and only that space, maps
    /// to its modality here — the 9 deferred `MovementFunction` cases
    /// (`locomotion`/`carry`/`jumping`/`trunk`/`verticalPullLoaded`/
    /// `horizontalPullLoaded`/`verticalPushLoaded`/`kneeFlexionLoaded`/
    /// `other`) are never produced by `FunctionalFitnessMovementComposer`,
    /// so they never reach this lookup.
    private static func modality(for function: MovementFunction) -> FunctionalModality {
        switch function {
        case .squatLoaded, .hingeLoaded, .pressLoaded: return .weightlifting
        case .gymnasticsPull, .gymnasticsPush: return .gymnastics
        case .monostructural: return .metabolicConditioning
        default: return .metabolicConditioning // unreachable — composer never produces a deferred function
        }
    }

    /// TE.1 hard eligibility, computed once per block (candidateExercises/
    /// environment don't change within one `materializeWeek` call) —
    /// FF.M1's composition engine never performs its own equipment
    /// reasoning, it only consumes this already-gated set (the locked
    /// TE.1/composition boundary).
    private static func eligibleFunctions(candidateExercises: [Exercise], environment: TrainingEnvironment) -> (functions: Set<MovementFunction>, monostructuralEligible: Bool) {
        let loadedAndGymnastics: [MovementFunction] = [.squatLoaded, .hingeLoaded, .pressLoaded, .gymnasticsPull, .gymnasticsPush]
        var eligible: Set<MovementFunction> = []
        for function in loadedAndGymnastics {
            let requiredModality = modality(for: function)
            let hasCandidate = candidateExercises.contains {
                $0.functionalModality == requiredModality
                    && $0.movementFunctions.contains(function)
                    && TrainingEnvironmentCompatibilityRule.evaluate(required: $0.requiredEquipment, environment: environment) == .compatible
            }
            if hasCandidate { eligible.insert(function) }
        }
        let monostructuralEligible = candidateExercises.contains {
            $0.functionalModality == .metabolicConditioning
                && $0.movementFunctions.contains(.monostructural)
                && TrainingEnvironmentCompatibilityRule.evaluate(required: $0.requiredEquipment, environment: environment) == .compatible
        }
        return (eligible, monostructuralEligible)
    }

    /// Stage FF.M1 prescription-history horizon: current week (tracked in
    /// `FunctionalFitnessMovementComposer`/`usedExerciseIDsThisSession`
    /// above) + the immediately preceding tactical week only — never
    /// merged, never gated on completion (`FunctionalFitnessExposureHistoryBuilder`
    /// is a DIFFERENT, completion-gated mechanism feeding `VarianceConstraints`,
    /// which FF.M1 does not activate).
    private static func priorWeekDateRange(weekStartDate: Date) -> Range<Date> {
        let priorWeekStart = Calendar.current.date(byAdding: .day, value: -7, to: weekStartDate) ?? weekStartDate
        return priorWeekStart..<weekStartDate
    }

    private static func priorWeekFunctionalFitnessMovements(instance: ProgramInstance, dateRange: Range<Date>) -> [(function: MovementFunction, exercise: Exercise)] {
        instance.sessions
            .filter { session in
                guard let date = session.day?.date else { return false }
                return dateRange.contains(date)
            }
            .flatMap(\.orderedBlocks)
            .compactMap(\.functionalFitnessPrescription)
            .flatMap(\.orderedMovements)
            .compactMap { movement -> (MovementFunction, Exercise)? in
                guard let exercise = movement.exercise,
                      let function = movement.sourceExerciseSlot?.allowedMovementFunctions.first
                else { return nil }
                return (function, exercise)
            }
    }

    private static func functionExposureCounts(from movements: [(function: MovementFunction, exercise: Exercise)]) -> [MovementFunction: Int] {
        movements.reduce(into: [:]) { counts, entry in counts[entry.function, default: 0] += 1 }
    }

    private static func exerciseExposureCounts(from movements: [(function: MovementFunction, exercise: Exercise)]) -> [MovementFunction: [UUID: Int]] {
        movements.reduce(into: [:]) { counts, entry in
            counts[entry.function, default: [:]][entry.exercise.id, default: 0] += 1
        }
    }

    // MARK: - Pre-FF.M1 authored path (unchanged behavior)

    private static func materializeAuthoredBlock(
        ffTemplate: FunctionalFitnessPrescriptionTemplate,
        decision: FunctionalFitnessProgrammingDecision,
        block: WorkoutBlock,
        instance: ProgramInstance,
        candidateExercises: [Exercise],
        environment: TrainingEnvironment?,
        currentWeekContext: inout CurrentWeekFunctionalFitnessProgrammingContext,
        context: ModelContext
    ) throws {
        // Same-week FF complementarity coordinates against what a
        // sibling session is ACTUALLY programmed to do after CP.2
        // adaptation, not its pre-adaptation intent — FINAL, not
        // INTENDED (verified against CP.2's own same-week pairing
        // contract; see the design doc's Design Lock, item 9).
        currentWeekContext.record(stimulus: decision.finalStimulus)

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
