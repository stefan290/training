import Foundation
import SwiftData

/// `TACTICAL_PLANNING_HANDOFF.md` §1-2 — materializes the first tactical
/// window at phase start, and rolls it forward one real week at a time as
/// each prior week's actual results/feedback become available. Never a
/// new progression mechanism: every per-system call here is the exact
/// existing materializer/engine call, just resolved with real inputs
/// (`SubstitutionAwareRecommendation` for a starting RM,
/// `AutoregulationRatingResolver` for autoregulation feedback,
/// `ProgramWeekGrouping` for "which week is next") instead of test
/// fixtures.
enum RollTacticalWindowUseCase {
    struct Result {
        /// Keyed by `TrainingMixComponent.id` — only components that
        /// actually rolled forward this call (Steady State never appears
        /// here — see the type's own doc comment).
        var newSessionsByComponent: [UUID: [Session]]
        var scheduleProposal: ScheduleProposal
    }

    // MARK: - First window (called by StartPhaseUseCase)

    /// Materializes only what can honestly be materialized right now.
    /// Hypertrophy/Powerlifting/Interval/Functional Fitness need live
    /// per-week feedback to progress past week 0 — never fabricated ahead
    /// — so only week 0 is materialized here. Steady State has no such
    /// dependency and materializes its whole natural block in one call,
    /// per `SteadyStateMaterializer`'s own documented architecture.
    @discardableResult
    static func materializeFirstWindow(
        system: ProgrammingSystemKind, definition: ProgramDefinition, instance: ProgramInstance,
        startDate: Date, ownerUserID: UUID, performanceProfile: PerformanceProfile?,
        materializationContext: TacticalMaterializationContext, context: ModelContext
    ) throws -> [Session] {
        switch system {
        case .hypertrophy, .powerlifting:
            let result = StrengthMaterializer.materializeWeek(
                definition: definition, instance: instance, weekIndex: 0, isDeload: false,
                startDate: startDate, ownerUserID: ownerUserID, equipmentProfile: materializationContext.equipmentProfile,
                slotContext: { slot in
                    strengthSlotContext(slot: slot, instance: instance, weekIndex: 0, performanceProfile: performanceProfile, context: context)
                },
                context: context
            )
            return result.sessions
        case .steadyState:
            return SteadyStateMaterializer.materializeAllWeeks(
                definition: definition, instance: instance, startDate: startDate, ownerUserID: ownerUserID, context: context
            )
        case .interval:
            return try IntervalMaterializer.materializeWeek(
                definition: definition, instance: instance, weekIndex: 0, startDate: startDate, ownerUserID: ownerUserID,
                weekContext: { _ in .init() }, context: context
            )
        case .functionalFitness:
            return try FunctionalFitnessMaterializer.materializeWeek(
                definition: definition, instance: instance, weekIndex: 0, startDate: startDate, ownerUserID: ownerUserID,
                candidateExercises: materializationContext.functionalFitnessCandidateExercises,
                exposureHistory: materializationContext.functionalFitnessExposureHistory, context: context
            )
        }
    }

    // MARK: - Rolling forward (real prior results feed the next week)

    /// Rolls every not-yet-exhausted component of `mix` forward by
    /// exactly the next real week — never a batch of several weeks at
    /// once, and never a week whose inputs don't yet exist.
    ///
    /// **Known, disclosed limitation:** Steady State already materialized
    /// its whole natural block up front (`materializeFirstWindow`) and is
    /// skipped here — it has nothing left to roll within the *same*
    /// `ProgramInstance`. Extending a Steady State component beyond its
    /// own generated `ProgramDefinition.lengthWeeks` would mean
    /// generating a new `ProgramInstance`, which is a phase-transition-
    /// shaped event (a new `start` call), not a same-phase roll — not
    /// built this pass, flagged rather than silently assumed.
    @discardableResult
    static func rollForward(
        mix: TrainingMix, asOf: Date, ownerUserID: UUID,
        performanceProfile: PerformanceProfile?, availability: UserAvailability,
        materializationContext: TacticalMaterializationContext, context: ModelContext
    ) throws -> Result? {
        var inputs: [ScheduledProgramInput] = []
        var newSessionsByComponent: [UUID: [Session]] = [:]

        for component in mix.orderedComponents {
            guard let instance = component.programInstance, let definition = instance.programDefinition else { continue }
            guard let system = component.programmingSystem, system != .steadyState else { continue }

            let weekIndex = ProgramWeekGrouping.nextWeekIndex(for: instance)
            // `StrengthMaterializer.materializeWeek` treats `startDate` as
            // THIS week's own start (no internal week-offset math), so it
            // needs the pre-shifted value. `IntervalMaterializer`/
            // `FunctionalFitnessMaterializer.materializeWeek` instead derive
            // their own week start internally as `startDate + weekIndex*7`
            // (matching `materializeFirstWindow`'s weekIndex-0 call, where
            // `startDate` is the instance's own start date) — passing an
            // already-shifted date here would double-apply the week offset,
            // dating every rolled-forward week one week later than intended.
            let weekStartDate = Calendar.current.date(byAdding: .day, value: weekIndex * 7, to: instance.startDate) ?? instance.startDate

            let sessions: [Session]
            switch system {
            case .hypertrophy, .powerlifting:
                let result = StrengthMaterializer.materializeWeek(
                    definition: definition, instance: instance, weekIndex: weekIndex, isDeload: false,
                    startDate: weekStartDate, ownerUserID: ownerUserID, equipmentProfile: materializationContext.equipmentProfile,
                    slotContext: { slot in
                        strengthSlotContext(slot: slot, instance: instance, weekIndex: weekIndex, performanceProfile: performanceProfile, context: context)
                    },
                    context: context
                )
                sessions = result.sessions
            case .interval:
                sessions = try IntervalMaterializer.materializeWeek(
                    definition: definition, instance: instance, weekIndex: weekIndex, startDate: instance.startDate, ownerUserID: ownerUserID,
                    weekContext: { _ in .init() }, context: context
                )
            case .functionalFitness:
                sessions = try FunctionalFitnessMaterializer.materializeWeek(
                    definition: definition, instance: instance, weekIndex: weekIndex, startDate: instance.startDate, ownerUserID: ownerUserID,
                    candidateExercises: materializationContext.functionalFitnessCandidateExercises,
                    exposureHistory: materializationContext.functionalFitnessExposureHistory, context: context
                )
            case .steadyState:
                continue
            }

            guard !sessions.isEmpty else { continue }
            newSessionsByComponent[component.id] = sessions
            inputs.append(ScheduledProgramInput(component: component, sessions: sessions))
        }

        guard !inputs.isEmpty else { return nil }

        let constraints = SchedulingConstraints(availability: availability, window: SchedulingWindow(startDate: asOf, numberOfDays: 7))
        let scheduled = SchedulingPipeline.propose(mix: mix, inputs: inputs, constraints: constraints)
        try AcceptScheduleProposalUseCase.accept(scheduled.proposal, ownerUserID: ownerUserID, context: context)

        return Result(newSessionsByComponent: newSessionsByComponent, scheduleProposal: scheduled.proposal)
    }

    // MARK: - Strength slot-context resolution

    /// Week 0: resolves a starting RM from real `PerformanceProfile`
    /// history via the existing recommendation hierarchy (own history /
    /// related-exercise estimate / calibration required) — never a
    /// fabricated number. Week N>0: resolves the real autoregulation
    /// inputs from the actually-materialized graph — never re-derives or
    /// clones a prior week's values.
    private static func strengthSlotContext(
        slot: ExerciseSlot, instance: ProgramInstance, weekIndex: Int, performanceProfile: PerformanceProfile?, context: ModelContext
    ) -> StrengthMaterializer.SlotContext {
        guard let exercise = SubstituteExerciseUseCase.resolvedExercise(for: slot, in: instance) else { return .init() }

        if weekIndex == 0 {
            let selectedProfile = performanceProfile?.profile(for: exercise)
            let candidates = slot.allowedExercises.filter { $0.id != exercise.id }
            let curated = (try? context.fetch(FetchDescriptor<ExerciseRelationship>())) ?? []
            let output = SubstitutionAwareRecommendation.resolve(SubstitutionAwareRecommendation.Input(
                selectedExercise: exercise, selectedExerciseProfile: selectedProfile,
                candidatesForEstimate: candidates, curatedRelationships: curated,
                relatedProfileLookup: { performanceProfile?.profile(for: $0) }
            ))
            return StrengthMaterializer.SlotContext(rmKilograms: output.referenceOneRepMax)
        }

        guard let template = slot.prescriptionTemplate else { return .init() }
        return StrengthMaterializer.SlotContext(
            weekOneResolvedWeightKg: AutoregulationRatingResolver.weekZeroResolvedWeight(for: template, in: instance),
            previousWeekSetCount: AutoregulationRatingResolver.previousWeekSetCount(for: template, in: instance),
            autoregulationRating: AutoregulationRatingResolver.rating(for: template, in: instance)
        )
    }
}
