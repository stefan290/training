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
        startDate: Date, ownerUserID: UUID, performanceProfile: PerformanceProfile?, userProfile: UserProfile? = nil,
        materializationContext: TacticalMaterializationContext, context: ModelContext
    ) throws -> [Session] {
        switch system {
        case .hypertrophy, .powerlifting:
            let result = StrengthMaterializer.materializeWeek(
                definition: definition, instance: instance, weekIndex: 0, isDeload: false,
                startDate: startDate, ownerUserID: ownerUserID, equipmentProfile: materializationContext.equipmentProfile,
                slotContext: { slot in
                    strengthSlotContext(
                        slot: slot, instance: instance, weekIndex: 0, isDeload: false,
                        performanceProfile: performanceProfile, userProfile: userProfile, context: context
                    )
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
        performanceProfile: PerformanceProfile?, availability: UserAvailability, userProfile: UserProfile? = nil,
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

            // Stage 10B.6 fix: this previously hardcoded `isDeload: false`
            // regardless of `weekIndex`, making the already-generated 5th
            // `TrainingWeek` (already marked `isDeload: true` by every
            // generator) structurally unreachable in production — see
            // `STAGE10B6_HYPERTROPHY_PRESCRIPTION_REDESIGN.md` §12. Reads
            // the real, already-persisted flag instead of assuming.
            let weeks = definition.orderedWeeks
            let isDeload = weeks.indices.contains(weekIndex) ? weeks[weekIndex].isDeload : false

            let sessions: [Session]
            switch system {
            case .hypertrophy, .powerlifting:
                let result = StrengthMaterializer.materializeWeek(
                    definition: definition, instance: instance, weekIndex: weekIndex, isDeload: isDeload,
                    startDate: weekStartDate, ownerUserID: ownerUserID, equipmentProfile: materializationContext.equipmentProfile,
                    slotContext: { slot in
                        strengthSlotContext(
                            slot: slot, instance: instance, weekIndex: weekIndex, isDeload: isDeload,
                            performanceProfile: performanceProfile, userProfile: userProfile, context: context
                        )
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
        slot: ExerciseSlot, instance: ProgramInstance, weekIndex: Int, isDeload: Bool,
        performanceProfile: PerformanceProfile?, userProfile: UserProfile?, context: ModelContext
    ) -> StrengthMaterializer.SlotContext {
        guard let exercise = SubstituteExerciseUseCase.resolvedExercise(for: slot, in: instance) else { return .init() }

        // Stage 10B.6: Hypertrophy V2 slots resolve entirely through
        // their own engine, identically at every week including week 0 —
        // no e1RM, no phase-specific week-1 RM factor (D-10B6-7/D-10B6-9:
        // e1RM is dropped as a dependency for this rule family, kept
        // unchanged for Family A/B/C's own `weekIndex == 0` branch below).
        if let template = slot.prescriptionTemplate, let rules = template.rules, rules.loadRule == .doubleProgression {
            // TRAININGOS_DESIGNED fallback (2.5 kg), matching
            // `CompleteSessionUseCase.progressionPreview`'s exact existing
            // convention — never blocks materialization on a missing
            // per-user equipment setting.
            let increment = userProfile?.equipmentIncrements[exercise.equipment] ?? 2.5
            let weightResolution = HypertrophyV2ProgressionEngine.resolveWeight(
                exercise: exercise, performanceProfile: performanceProfile, equipmentIncrement: increment
            )
            guard let role = template.slotRole else {
                return StrengthMaterializer.SlotContext(
                    doubleProgressionWeightKg: weightResolution.weightKg,
                    doubleProgressionReasonCode: weightResolution.reasonCode
                )
            }
            let repGoal = HypertrophyV2ProgressionEngine.resolveRepGoal(rules: rules, weekIndex: weekIndex, isDeload: isDeload)
            let setCount = HypertrophyV2ProgressionEngine.resolveSetCount(
                role: role, rules: rules, isDeload: isDeload,
                previousWeekSetCount: AutoregulationRatingResolver.previousWeekSetCount(for: template, in: instance),
                autoregulationRating: AutoregulationRatingResolver.rating(for: template, in: instance)
            )
            return StrengthMaterializer.SlotContext(
                doubleProgressionWeightKg: weightResolution.weightKg,
                doubleProgressionReasonCode: weightResolution.reasonCode,
                doubleProgressionRepGoal: repGoal,
                doubleProgressionSetCount: setCount
            )
        }

        if weekIndex == 0 {
            // Stage 10R.1C: for `.rmBased` slots, the source workbooks
            // require a literal, physically-tested RM (10RM/8RM/5RM,
            // per the slot's own `RMType`) — never derived from
            // `PerformanceProfile`/`SubstitutionAwareRecommendation`'s
            // "estimated 1RM" mechanism, which is both a different basis
            // and a different scope (permanent-per-exercise vs. fresh-
            // per-mesocycle). See
            // `STAGE10R1C_SOURCE_RM_CALIBRATION_DESIGN.md`. Non-`.rmBased`
            // loadRules (`.linkedToPairedSlot`/`.none`) need no
            // `rmKilograms` at week 0 at all — `rmKilograms` simply stays
            // `nil` for them, exactly as `StrengthProgressionEngine
            // .resolveWeight` already expects.
            guard let loadRule = slot.prescriptionTemplate?.rules?.loadRule, case .rmBased(let payload) = loadRule else {
                return .init()
            }
            let calibration = instance.sourceRMCalibration(for: exercise, rmType: payload.rmType)
            return StrengthMaterializer.SlotContext(rmKilograms: calibration?.kilograms)
        }

        guard let template = slot.prescriptionTemplate else { return .init() }
        return StrengthMaterializer.SlotContext(
            weekOneResolvedWeightKg: AutoregulationRatingResolver.weekZeroResolvedWeight(for: template, in: instance),
            previousWeekSetCount: AutoregulationRatingResolver.previousWeekSetCount(for: template, in: instance),
            autoregulationRating: AutoregulationRatingResolver.rating(for: template, in: instance)
        )
    }
}
