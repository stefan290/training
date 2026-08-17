import Foundation
import SwiftData

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
        context: ModelContext
    ) -> [Session] {
        var sessions: [Session] = []
        let orderedWeeks = definition.orderedWeeks
        let orderedTemplateSessions = definition.orderedTemplateSessions

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
                }
            }
        }

        return sessions
    }
}
