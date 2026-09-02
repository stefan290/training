import Foundation
import SwiftData

/// Thrown when a performance-gated interval template
/// (`requiresSuccessfulCompletionToProgress == true`) is asked to
/// materialize a week beyond the first without the previous week's
/// actual `IntervalSessionOutcome` — Stage 4D §15/§33's explicit rule:
/// "do not generate progression solely from calendar week if the
/// methodology requires successful completion... do not invent future
/// outcomes." Thrown rather than silently falling back to calendar
/// progression, so violating this precondition is a loud programmer
/// error, not a quiet behavioral surprise.
enum IntervalMaterializationError: Error, Equatable {
    case previousOutcomeRequired
    /// Stage TE.1: no `TrainingEnvironment` was supplied at all — thrown
    /// before any activity-resolution happens.
    case trainingEnvironmentRequired
    /// Stage TE.1: a real, configured environment exists, but the
    /// resolved `ActivityType`'s own requirement isn't satisfied by it.
    case environmentIncompatible(activityType: ActivityType, missingEquipment: [EquipmentRequirement])
}

/// Turns an interval `ProgramDefinition`'s template graph into real,
/// dated execution rows — the interval sibling of
/// `StrengthMaterializer`/`SteadyStateMaterializer`.
///
/// **Scope, stated plainly:** materializes one week at a time, always —
/// unlike `SteadyStateMaterializer` (which can resolve every week
/// immediately because none of its dimensions ever depend on a live
/// result), an interval template *may* set
/// `requiresSuccessfulCompletionToProgress`, and this materializer has no
/// way to know in advance whether a given template will. Callers whose
/// rules never set that flag may still call this once per week in a
/// simple loop with `previousOutcome: nil` throughout — the result is
/// identical to materializing every week up front, just expressed as
/// repeated calls instead of a single one.
enum IntervalMaterializer {
    /// Per-block runtime context the caller must supply for week
    /// `weekIndex > 0` — everything the template graph itself cannot
    /// know. `nil` fields are valid at week 0 (nothing preceding it yet)
    /// or when the template's rules never progress that dimension.
    struct WeekContext {
        var previousActualIntervalCount: Int?
        var previousActualWorkDurationSeconds: Int?
        var previousActualWorkDistanceMeters: Double?
        var previousActualZone: HeartRateZone?
        var previousActualRecoveryDurationSeconds: Int?
        var previousOutcome: IntervalSessionOutcome?

        init(
            previousActualIntervalCount: Int? = nil,
            previousActualWorkDurationSeconds: Int? = nil,
            previousActualWorkDistanceMeters: Double? = nil,
            previousActualZone: HeartRateZone? = nil,
            previousActualRecoveryDurationSeconds: Int? = nil,
            previousOutcome: IntervalSessionOutcome? = nil
        ) {
            self.previousActualIntervalCount = previousActualIntervalCount
            self.previousActualWorkDurationSeconds = previousActualWorkDurationSeconds
            self.previousActualWorkDistanceMeters = previousActualWorkDistanceMeters
            self.previousActualZone = previousActualZone
            self.previousActualRecoveryDurationSeconds = previousActualRecoveryDurationSeconds
            self.previousOutcome = previousOutcome
        }
    }

    @discardableResult
    static func materializeWeek(
        definition: ProgramDefinition,
        instance: ProgramInstance,
        weekIndex: Int,
        startDate: Date,
        ownerUserID: UUID,
        weekContext: (WorkoutBlockTemplate) -> WeekContext,
        /// Stage TE.1: read fresh from `TacticalMaterializationContext
        /// .trainingEnvironment` at each real call. `nil` is a valid,
        /// honest "not yet configured" state — never treated as
        /// "anything goes" (see the fail-fast guard below).
        environment: TrainingEnvironment?,
        context: ModelContext
    ) throws -> [Session] {
        var sessions: [Session] = []
        let weekStartDate = Calendar.current.date(byAdding: .day, value: weekIndex * 7, to: startDate) ?? startDate
        let orderedTemplateSessions = definition.orderedTemplateSessions.filter { $0.activeFromWeek <= weekIndex }

        // Stage TE.1 fail-fast guard: checked once, before any activity
        // resolution — never silently treated as "anything goes."
        if !orderedTemplateSessions.isEmpty, environment == nil {
            throw IntervalMaterializationError.trainingEnvironmentRequired
        }

        for (dayIndex, templateSession) in orderedTemplateSessions.enumerated() {
            let date = Calendar.current.date(byAdding: .day, value: dayIndex, to: weekStartDate) ?? weekStartDate
            let day = Day(ownerUserID: ownerUserID, date: date)
            context.insert(day)

            let session = Session(name: templateSession.name, modality: .conditioning, status: .scheduled, role: templateSession.role)
            session.materializedInEnvironment = environment
            context.insert(session)
            day.addSession(session)
            instance.addSession(session)
            sessions.append(session)

            for blockTemplate in templateSession.orderedBlockTemplates {
                let block = WorkoutBlock(type: blockTemplate.type)
                context.insert(block)
                session.addBlock(block)

                if let steadyStateTemplate = blockTemplate.steadyStatePrescriptionTemplate,
                   let ssRules = steadyStateTemplate.progressionRules {
                    // Warm-up/cool-down blocks — plain, unprogressed
                    // steady-state structure (Stage 4D §7).
                    let activityType = SubstituteActivityUseCase.resolvedActivityType(
                        for: blockTemplate, defaultActivityType: steadyStateTemplate.preferredActivityType, in: instance
                    )
                    try checkEnvironmentCompatibility(activityType: activityType, environment: environment)
                    let durationResult = SteadyStateProgressionEngine.resolveDuration(rules: ssRules, weekIndex: weekIndex, isRecoveryWeek: false)
                    let prescription = SteadyStatePrescription(
                        activityType: activityType, durationSeconds: durationResult.durationSeconds,
                        primaryIntensity: steadyStateTemplate.primaryIntensity
                    )
                    context.insert(prescription)
                    block.attachSteadyStatePrescription(prescription)

                    // Stage CP.1: this embedded warm-up/cool-down block is
                    // a real SteadyStatePrescription, mapped exactly like
                    // SteadyStateMaterializer's own blocks.
                    block.trainingStressProfile = SteadyStateTrainingStressMapper.map(
                        activityType: activityType, durationSeconds: durationResult.durationSeconds,
                        primaryIntensity: steadyStateTemplate.primaryIntensity
                    )
                    continue
                }

                guard let intervalTemplate = blockTemplate.intervalPrescriptionTemplate,
                      let rules = intervalTemplate.progressionRules else { continue }

                let ctx = weekContext(blockTemplate)
                if rules.requiresSuccessfulCompletionToProgress, weekIndex > 0, ctx.previousOutcome == nil {
                    throw IntervalMaterializationError.previousOutcomeRequired
                }

                let countResult = IntervalProgressionEngine.resolveIntervalCount(
                    rules: rules, weekIndex: weekIndex, previousActualCount: ctx.previousActualIntervalCount, previousOutcome: ctx.previousOutcome
                )
                let durationResult = IntervalProgressionEngine.resolveWorkDuration(
                    rules: rules, weekIndex: weekIndex, previousActualDurationSeconds: ctx.previousActualWorkDurationSeconds, previousOutcome: ctx.previousOutcome
                )
                let distanceResult = IntervalProgressionEngine.resolveWorkDistance(
                    rules: rules, weekIndex: weekIndex, previousActualDistanceMeters: ctx.previousActualWorkDistanceMeters, previousOutcome: ctx.previousOutcome
                )
                let intensityResult = IntervalProgressionEngine.resolveIntensity(
                    rules: rules, weekIndex: weekIndex, previousActualZone: ctx.previousActualZone, previousOutcome: ctx.previousOutcome
                )
                let recoveryResult = IntervalProgressionEngine.resolveRecoveryDuration(
                    rules: rules, weekIndex: weekIndex, previousActualRecoverySeconds: ctx.previousActualRecoveryDurationSeconds, previousOutcome: ctx.previousOutcome
                )

                let activityType = SubstituteActivityUseCase.resolvedActivityType(
                    for: blockTemplate, defaultActivityType: intervalTemplate.preferredActivityType, in: instance
                )
                try checkEnvironmentCompatibility(activityType: activityType, environment: environment)

                let prescription = IntervalPrescription(
                    activityType: activityType,
                    intervalCount: countResult.count,
                    workDurationSeconds: durationResult.durationSeconds,
                    workDistanceMeters: distanceResult.distanceMeters,
                    workIntensity: intensityResult.intensity ?? intervalTemplate.workIntensity,
                    recoveryDurationSeconds: recoveryResult.recoveryDurationSeconds,
                    recoveryIntensity: intervalTemplate.recoveryIntensity
                )
                prescription.sourceWorkoutBlockTemplate = blockTemplate
                context.insert(prescription)
                block.attachIntervalPrescription(prescription)

                // Stage CP.1: observes exactly this resolved prescription
                // — never influences IntervalProgressionEngine's own output.
                block.trainingStressProfile = IntervalTrainingStressMapper.map(
                    activityType: activityType, intervalCount: countResult.count,
                    workDurationSeconds: durationResult.durationSeconds, recoveryDurationSeconds: recoveryResult.recoveryDurationSeconds,
                    workIntensity: intensityResult.intensity ?? intervalTemplate.workIntensity
                )
            }
        }

        return sessions
    }

    /// Stage TE.1: the narrowest correct seam — checked immediately
    /// after `resolvedActivityType`, before constructing the real
    /// prescription, at both of this materializer's real call sites
    /// (composed, not merged into `SubstituteActivityUseCase.isValid`, a
    /// different question).
    private static func checkEnvironmentCompatibility(activityType: ActivityType, environment: TrainingEnvironment?) throws {
        switch TrainingEnvironmentCompatibilityRule.evaluate(required: activityType.requiredEquipment, environment: environment) {
        case .compatible:
            return
        case .incompatible(let missing):
            throw IntervalMaterializationError.environmentIncompatible(activityType: activityType, missingEquipment: Array(missing))
        case .environmentUnknown:
            throw IntervalMaterializationError.trainingEnvironmentRequired
        }
    }
}
