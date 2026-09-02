import Foundation
import SwiftData

/// Stage TE.1: the SteadyState sibling of `IntervalMaterializationError` —
/// this materializer had no error type of its own before TE.1 because it
/// was never `throws` (every dimension it resolves is a deterministic
/// function of `weekIndex` alone). Environment compatibility is the
/// first real reason it can now fail.
enum SteadyStateMaterializationError: Error, Equatable {
    /// No `TrainingEnvironment` was supplied at all — thrown before any
    /// activity-resolution happens.
    case trainingEnvironmentRequired
    /// A real, configured environment exists, but the resolved
    /// `ActivityType`'s own requirement isn't satisfied by it.
    case environmentIncompatible(activityType: ActivityType, missingEquipment: [EquipmentRequirement])
}

/// Turns a steady-state `ProgramDefinition`'s template graph into real,
/// dated execution rows — the steady-state sibling of
/// `StrengthMaterializer`.
///
/// **Scope, stated plainly, and deliberately broader than
/// `StrengthMaterializer`'s:** every dimension `SteadyStateProgressionEngine`
/// resolves (duration/distance/intensity-zone/recovery) is a deterministic
/// function of `weekIndex` alone — none of them need a live per-week
/// rating or the previous week's actual outcome the way strength's
/// autoregulation does. There is therefore no partial-materialization
/// limitation here: this materializes every week of a `ProgramDefinition`
/// in one call. This is a genuine architectural difference from strength,
/// not an oversight — see `STAGE4_IMPLEMENTATION_REPORT.md`'s Stage 4C
/// section.
enum SteadyStateMaterializer {
    @discardableResult
    static func materializeAllWeeks(
        definition: ProgramDefinition,
        instance: ProgramInstance,
        startDate: Date,
        ownerUserID: UUID,
        /// Stage TE.1: read fresh from `TacticalMaterializationContext
        /// .trainingEnvironment` at each real call. `nil` is a valid,
        /// honest "not yet configured" state — never treated as
        /// "anything goes" (see the fail-fast guard below).
        environment: TrainingEnvironment?,
        context: ModelContext
    ) throws -> [Session] {
        var sessions: [Session] = []
        let orderedWeeks = definition.orderedWeeks
        let orderedTemplateSessions = definition.orderedTemplateSessions

        // Stage TE.1 fail-fast guard: checked once, before any activity
        // resolution — never silently treated as "anything goes."
        if !orderedTemplateSessions.isEmpty, environment == nil {
            throw SteadyStateMaterializationError.trainingEnvironmentRequired
        }

        for (weekIndex, week) in orderedWeeks.enumerated() {
            let weekStartDate = Calendar.current.date(byAdding: .day, value: weekIndex * 7, to: startDate) ?? startDate
            // Frequency progression (Stage 4C §7-8): a `TemplateSession`
            // only participates in a given week once `weekIndex` reaches
            // its `activeFromWeek` — modeled here, at the Session level,
            // never inside `SteadyStateProgressionEngine`'s per-block
            // resolution.
            let activeTemplateSessions = orderedTemplateSessions.filter { $0.activeFromWeek <= weekIndex }

            for (dayIndex, templateSession) in activeTemplateSessions.enumerated() {
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
                    guard let steadyStateTemplate = blockTemplate.steadyStatePrescriptionTemplate,
                          let rules = steadyStateTemplate.progressionRules else { continue }

                    let block = WorkoutBlock(type: blockTemplate.type)
                    context.insert(block)
                    session.addBlock(block)

                    let durationResult = SteadyStateProgressionEngine.resolveDuration(rules: rules, weekIndex: weekIndex, isRecoveryWeek: week.isDeload)
                    let distanceResult = SteadyStateProgressionEngine.resolveDistance(rules: rules, weekIndex: weekIndex, isRecoveryWeek: week.isDeload)
                    let intensityResult = SteadyStateProgressionEngine.resolveIntensity(
                        rules: rules, weekIndex: weekIndex, isRecoveryWeek: week.isDeload,
                        staticPrimaryIntensity: steadyStateTemplate.primaryIntensity
                    )

                    // GOING FORWARD activity substitution hook — mirrors
                    // `StrengthMaterializer`'s `SubstituteExerciseUseCase.resolvedExercise`
                    // call exactly.
                    let activityType = SubstituteActivityUseCase.resolvedActivityType(
                        for: blockTemplate, defaultActivityType: steadyStateTemplate.preferredActivityType, in: instance
                    )
                    // Stage TE.1: the narrowest correct seam — checked
                    // immediately after resolution, before constructing
                    // the real prescription (composed, not merged into
                    // `SubstituteActivityUseCase.isValid`, a different
                    // question).
                    switch TrainingEnvironmentCompatibilityRule.evaluate(required: activityType.requiredEquipment, environment: environment) {
                    case .compatible:
                        break
                    case .incompatible(let missing):
                        throw SteadyStateMaterializationError.environmentIncompatible(activityType: activityType, missingEquipment: Array(missing))
                    case .environmentUnknown:
                        throw SteadyStateMaterializationError.trainingEnvironmentRequired
                    }

                    let prescription = SteadyStatePrescription(
                        activityType: activityType,
                        durationSeconds: durationResult.durationSeconds,
                        distanceMeters: distanceResult.distanceMeters,
                        primaryIntensity: intensityResult.intensity,
                        secondaryIntensity: steadyStateTemplate.secondaryIntensity
                    )
                    prescription.sourceWorkoutBlockTemplate = blockTemplate
                    context.insert(prescription)
                    block.attachSteadyStatePrescription(prescription)

                    // Stage CP.1: observes exactly this resolved
                    // prescription — never influences SteadyStateProgressionEngine's
                    // own output.
                    block.trainingStressProfile = SteadyStateTrainingStressMapper.map(
                        activityType: activityType, durationSeconds: durationResult.durationSeconds,
                        primaryIntensity: intensityResult.intensity
                    )
                }
            }
        }

        return sessions
    }
}
