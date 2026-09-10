import Foundation
import SwiftData

/// Running R3: thrown only for the same environment-compatibility reasons
/// `SteadyStateMaterializationError`/`IntervalMaterializationError` already
/// throw — Running's own `ActivityType.running.requiredEquipment` is `[]`
/// (R2), so `.environmentIncompatible` can never actually fire for this
/// program in practice; the check is still performed, for the same
/// fail-fast discipline every other materializer applies, rather than
/// silently skipped because "it happens to always pass."
enum RunningMaterializationError: Error, Equatable {
    case trainingEnvironmentRequired
    case environmentIncompatible(activityType: ActivityType, missingEquipment: [EquipmentRequirement])
}

/// Turns the Running V1 `ProgramDefinition`'s template graph into real,
/// dated execution rows — the Running sibling of `SteadyStateMaterializer`/
/// `IntervalMaterializer`, but with one deliberate, load-bearing
/// difference from both:
///
/// **`TemplateSession.activeFromWeek` is read with EXACT equality here,
/// never the generic `activeFromWeek <= weekIndex` "recurring from this
/// week onward" filter every other materializer/preflight in this
/// codebase uses** (`SteadyStateMaterializer`, `IntervalMaterializer`,
/// `FunctionalFitnessMaterializer`, `TacticalAdvancementPreflight`).
/// Those systems have ONE recurring weekly structure whose numbers
/// progress by a rule; Running's recovered structure is the opposite —
/// R1 found the actual block/repeat SHAPE changes every single relative
/// week (warm-up block count 1→7, repeat-group count 0→3), so each of
/// this definition's 25 `TemplateSession`s is a literal, one-off week
/// (`RunningProgramGenerator` sets `activeFromWeek` to exactly the
/// 0-indexed relative week each session belongs to, never a "joins the
/// rotation and stays" marker). No new schema field was added for this —
/// reusing `activeFromWeek` with a *locally different* filter semantic,
/// scoped entirely to this file, is safe because no other materializer is
/// ever invoked against a `.running` `ProgramDefinition` (`RollTacticalWindowUseCase`
/// dispatches `.running` to this type alone, exactly as it dispatches
/// `.steadyState` to `SteadyStateMaterializer` alone), and
/// `TacticalAdvancementPreflight` explicitly excludes `.running` from its
/// own `activeFromWeek <=` computation for the same reason it already
/// excludes `.steadyState`.
///
/// **Materializes every week in one call**, exactly like
/// `SteadyStateMaterializer` and for the identical reason: nothing in
/// this program depends on a live per-week result or rating — every
/// number is already the literal, source-recovered value for its own
/// specific week, not a rule resolved from week-zero data.
enum RunningProgramMaterializer {
    @discardableResult
    static func materializeAllWeeks(
        definition: ProgramDefinition,
        instance: ProgramInstance,
        startDate: Date,
        ownerUserID: UUID,
        environment: TrainingEnvironment?,
        context: ModelContext
    ) throws -> [Session] {
        var sessions: [Session] = []
        let orderedWeeks = definition.orderedWeeks
        let orderedTemplateSessions = definition.orderedTemplateSessions

        if !orderedTemplateSessions.isEmpty, environment == nil {
            throw RunningMaterializationError.trainingEnvironmentRequired
        }

        for (weekIndex, _) in orderedWeeks.enumerated() {
            let weekStartDate = Calendar.current.date(byAdding: .day, value: weekIndex * 7, to: startDate) ?? startDate
            // EXACT equality — see this type's own doc comment. Every
            // other materializer in this codebase uses `<=` here; that
            // would be wrong for Running (it would re-include every prior
            // week's sessions in every subsequent week).
            let thisWeeksSessions = orderedTemplateSessions.filter { $0.activeFromWeek == weekIndex }

            for (dayIndex, templateSession) in thisWeeksSessions.enumerated() {
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

                    if let steadyTemplate = blockTemplate.steadyStatePrescriptionTemplate,
                       let rules = steadyTemplate.progressionRules {
                        let activityType = SubstituteActivityUseCase.resolvedActivityType(
                            for: blockTemplate, defaultActivityType: steadyTemplate.preferredActivityType, in: instance
                        )
                        try checkEnvironmentCompatibility(activityType: activityType, environment: environment)

                        // `weekIndex: 0` always — this template's own
                        // `weekOneDistanceMeters`/`primaryIntensity` ARE
                        // this exact week's literal source value; there is
                        // no progression to resolve (see this type's own
                        // doc comment).
                        let distanceResult = SteadyStateProgressionEngine.resolveDistance(rules: rules, weekIndex: 0, isRecoveryWeek: false)
                        let intensityResult = SteadyStateProgressionEngine.resolveIntensity(
                            rules: rules, weekIndex: 0, isRecoveryWeek: false, staticPrimaryIntensity: steadyTemplate.primaryIntensity
                        )

                        let prescription = SteadyStatePrescription(
                            activityType: activityType,
                            distanceMeters: distanceResult.distanceMeters,
                            primaryIntensity: intensityResult.intensity,
                            sourceLabel: steadyTemplate.sourceLabel,
                            executionNotes: steadyTemplate.executionNotes
                        )
                        prescription.sourceWorkoutBlockTemplate = blockTemplate
                        context.insert(prescription)
                        block.attachSteadyStatePrescription(prescription)

                        block.trainingStressProfile = SteadyStateTrainingStressMapper.map(
                            activityType: activityType, durationSeconds: nil, primaryIntensity: intensityResult.intensity
                        )
                        continue
                    }

                    guard let intervalTemplate = blockTemplate.intervalPrescriptionTemplate,
                          let rules = intervalTemplate.progressionRules else { continue }

                    let activityType = SubstituteActivityUseCase.resolvedActivityType(
                        for: blockTemplate, defaultActivityType: intervalTemplate.preferredActivityType, in: instance
                    )
                    try checkEnvironmentCompatibility(activityType: activityType, environment: environment)

                    // Same "week 0, no progression" reasoning as above —
                    // `rules.priority` is always empty for this program, so
                    // every resolver call below is a pure pass-through of
                    // the literal week-one value regardless of the
                    // `weekIndex` passed.
                    let countResult = IntervalProgressionEngine.resolveIntervalCount(rules: rules, weekIndex: 0, previousActualCount: nil, previousOutcome: nil)
                    let distanceResult = IntervalProgressionEngine.resolveWorkDistance(rules: rules, weekIndex: 0, previousActualDistanceMeters: nil, previousOutcome: nil)
                    let recoveryDistanceResult = IntervalProgressionEngine.resolveRecoveryDistance(rules: rules)

                    let prescription = IntervalPrescription(
                        activityType: activityType,
                        intervalCount: countResult.count,
                        workDistanceMeters: distanceResult.distanceMeters,
                        workIntensity: intervalTemplate.workIntensity,
                        recoveryDistanceMeters: recoveryDistanceResult.distanceMeters,
                        recoveryIntensity: intervalTemplate.recoveryIntensity,
                        sourceLabel: intervalTemplate.sourceLabel,
                        executionNotes: intervalTemplate.executionNotes
                    )
                    prescription.sourceWorkoutBlockTemplate = blockTemplate
                    context.insert(prescription)
                    block.attachIntervalPrescription(prescription)

                    block.trainingStressProfile = IntervalTrainingStressMapper.map(
                        activityType: activityType, intervalCount: countResult.count,
                        workDurationSeconds: nil, recoveryDurationSeconds: nil,
                        workIntensity: intervalTemplate.workIntensity
                    )
                }
            }
        }

        return sessions
    }

    private static func checkEnvironmentCompatibility(activityType: ActivityType, environment: TrainingEnvironment?) throws {
        switch TrainingEnvironmentCompatibilityRule.evaluate(required: activityType.requiredEquipment, environment: environment) {
        case .compatible:
            return
        case .incompatible(let missing):
            throw RunningMaterializationError.environmentIncompatible(activityType: activityType, missingEquipment: Array(missing))
        case .environmentUnknown:
            throw RunningMaterializationError.trainingEnvironmentRequired
        }
    }
}
