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
        /// Stage CP.2 addition: this component's own real
        /// `AdaptationObjective`s, threaded through to Functional
        /// Fitness's same-week complementarity check. No cross-modality
        /// `protectedSiblingStressProfilesThisWeek` signal exists at
        /// first-window time — `StartPhaseUseCase` materializes every
        /// component in one single-pass loop, not the two-pass producer/
        /// consumer split `RollTacticalWindowUseCase.rollForward` uses;
        /// restructuring that loop is out of Stage CP.2's authorized
        /// scope. Cross-modality discouragement is therefore only live
        /// from the first ROLLED-forward week onward — a disclosed,
        /// deliberate limitation, not a silent gap.
        componentAdaptationObjectives: [AdaptationObjective] = [],
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
            return try SteadyStateMaterializer.materializeAllWeeks(
                definition: definition, instance: instance, startDate: startDate, ownerUserID: ownerUserID,
                environment: materializationContext.trainingEnvironment, context: context
            )
        case .running:
            // Running R3: materializes its whole 13-relative-week block in
            // one call, exactly like Steady State and for the identical
            // reason — nothing in this program depends on a live per-week
            // result (`RunningProgramMaterializer`'s own doc comment).
            return try RunningProgramMaterializer.materializeAllWeeks(
                definition: definition, instance: instance, startDate: startDate, ownerUserID: ownerUserID,
                environment: materializationContext.trainingEnvironment, context: context
            )
        case .interval:
            return try IntervalMaterializer.materializeWeek(
                definition: definition, instance: instance, weekIndex: 0, startDate: startDate, ownerUserID: ownerUserID,
                weekContext: IntervalWeekContextBuilder.build(instance: instance, weekIndex: 0),
                environment: materializationContext.trainingEnvironment, context: context
            )
        case .functionalFitness:
            return try FunctionalFitnessMaterializer.materializeWeek(
                definition: definition, instance: instance, weekIndex: 0, startDate: startDate, ownerUserID: ownerUserID,
                candidateExercises: materializationContext.functionalFitnessCandidateExercises,
                exposureHistory: FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn: instance),
                componentAdaptationObjectives: componentAdaptationObjectives,
                environment: materializationContext.trainingEnvironment,
                // FUNCTIONAL FITNESS PROGRAMMING AUTHORITY V2, Section 8:
                // the one real production wiring of per-athlete movement
                // capability into selection. `nil` (no row exists for
                // this exercise) reads as `.unknown` — Section 28's
                // migration-safety requirement — never inferred
                // `.workoutReady`.
                movementCapabilityLookup: { exercise in performanceProfile?.movementCapability(for: exercise)?.proficiency ?? .unknown },
                performanceProfile: performanceProfile, userProfile: userProfile,
                context: context
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
        // Dogfood Round 2 (Finding 2): every real `Day` this call could
        // land a placement on — whether created earlier by
        // `StartPhaseUseCase`/a materializer (always midnight-normalized,
        // via `phase.startDate`/`instance.startDate` arithmetic) or by
        // `AcceptScheduleProposalUseCase.findOrCreateDay`'s own exact-
        // equality lookup below — must share the SAME calendar-day
        // identity convention. `asOf` here is real callers' raw
        // `Date()` (`PhaseDetailViewModel.advanceTacticalWeek`), never
        // normalized upstream; used un-normalized, it seeds
        // `SchedulingWindow.startDate` with a real time-of-day, so
        // `window.date(forDayOffset: 0)` would never exactly equal an
        // already-existing midnight `Day.date` for that same real
        // calendar day — `findOrCreateDay` would then silently create a
        // SECOND `Day` row for one real date, which every UI grouping
        // that uses `Calendar.isDate(_:inSameDayAs:)` then renders as two
        // separate sessions that day, even though nothing here ever
        // decided to schedule a double. Normalizing once, here, at the
        // single real call boundary this checkpoint's trace found,
        // closes it — never touches `ConcurrentScheduler`'s own
        // occupancy/hard-constraint logic, which was already correct.
        let asOf = Calendar.current.startOfDay(for: asOf)
        var inputs: [ScheduledProgramInput] = []
        var newSessionsByComponent: [UUID: [Session]] = [:]

        // Stage CP.2: Pass 1 — every component whose `ProgrammingSystem`
        // has no constraint-CONSUMING stage today (`.hypertrophy`,
        // `.powerlifting`, `.interval`; `.steadyState` never rolls here at
        // all, unchanged). Producer/consumer role is keyed purely on
        // `programmingSystem`, never `GoalPriority` — `GoalPriority`
        // stays "how protected," never "materializes first"
        // (`TRAINING_MIX_CONCURRENT_PROGRAMMING_DESIGN.md`'s CP.2 §1/§2).
        var protectedSiblingStressProfilesThisWeek: [TrainingStressProfile] = []

        for component in mix.orderedComponents {
            guard let instance = component.programInstance, let definition = instance.programDefinition else { continue }
            guard let system = component.programmingSystem else { continue }
            guard system == .hypertrophy || system == .powerlifting || system == .interval else { continue }

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
            //
            // Stage 10R.4B defense-in-depth bounds guard
            // (`STAGE10R4_TACTICAL_ROLLFORWARD_DESIGN.md` §3/§17): the
            // real caller-side gate (`AdvanceTacticalWeekUseCase`/
            // `TacticalWeekCompletion.canAdvanceTacticalWeek`) already
            // never invokes `rollForward` once a component is exhausted
            // — this guard exists only so a bug or a future caller that
            // skips that gate fails safely (this component is simply
            // skipped, `continue`) rather than fabricating a bogus week
            // past the definition's own final, source-defined week. Never
            // reached for any in-range call — behavior for every existing
            // valid `weekIndex` is unchanged.
            let weeks = definition.orderedWeeks
            guard weeks.indices.contains(weekIndex) else { continue }
            let isDeload = weeks[weekIndex].isDeload

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
                    weekContext: IntervalWeekContextBuilder.build(instance: instance, weekIndex: weekIndex),
                    environment: materializationContext.trainingEnvironment, context: context
                )
            case .steadyState, .functionalFitness, .running:
                // Running R3: already fully materialized upfront in
                // `materializeFirstWindow`, exactly like Steady State —
                // nothing left to roll within the same `ProgramInstance`.
                continue
            }

            guard !sessions.isEmpty else { continue }
            newSessionsByComponent[component.id] = sessions
            inputs.append(ScheduledProgramInput(component: component, sessions: sessions))

            // Stage CP.2: visible to Pass 2's Functional Fitness
            // component(s) ONLY when `.primary` — `GoalPriority` is what
            // makes a dimension "protected," not what determines
            // materialization order; every component reaching this line
            // already materialized first purely because it's a producer,
            // regardless of its own priority.
            if component.priority == .primary {
                protectedSiblingStressProfilesThisWeek.append(contentsOf: sessions.compactMap(SessionStressComposer.compose))
            }
        }

        // Stage CP.2: Pass 2 — Functional Fitness, the one real
        // constraint-CONSUMING `ProgrammingSystem` today. Reads Pass 1's
        // real, already-materialized sibling stress; never blocked on any
        // `GoalPriority` ordering of its own.
        for component in mix.orderedComponents {
            guard component.programmingSystem == .functionalFitness else { continue }
            guard let instance = component.programInstance, let definition = instance.programDefinition else { continue }

            let weekIndex = ProgramWeekGrouping.nextWeekIndex(for: instance)
            let weeks = definition.orderedWeeks
            guard weeks.indices.contains(weekIndex) else { continue }

            let sessions = try FunctionalFitnessMaterializer.materializeWeek(
                definition: definition, instance: instance, weekIndex: weekIndex, startDate: instance.startDate, ownerUserID: ownerUserID,
                candidateExercises: materializationContext.functionalFitnessCandidateExercises,
                exposureHistory: FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn: instance),
                protectedSiblingStressProfilesThisWeek: protectedSiblingStressProfilesThisWeek,
                componentAdaptationObjectives: component.adaptationObjectives,
                environment: materializationContext.trainingEnvironment,
                movementCapabilityLookup: { exercise in performanceProfile?.movementCapability(for: exercise)?.proficiency ?? .unknown },
                performanceProfile: performanceProfile, userProfile: userProfile,
                context: context
            )

            guard !sessions.isEmpty else { continue }
            newSessionsByComponent[component.id] = sessions
            inputs.append(ScheduledProgramInput(component: component, sessions: sessions))
        }

        guard !inputs.isEmpty else { return nil }

        // MUSCLE + 5FF FINAL CLOSURE, Section 17/18 (project-owner
        // decision): the real fix, after two reverted attempts anchored
        // on `asOf` in one form or another — see
        // `causal-analysis/tactical-window-anchor.md` for the full trace
        // of both, including exactly which real test each one broke.
        // Neither attempt is used. `asOf` is "when the user is doing this
        // action" (Section 18) — it must never redefine which real
        // calendar dates belong to the program week, so it is never used
        // to ANCHOR the window at all. The window instead derives
        // directly from the REAL naive dates the materializers above
        // already stamped onto each just-materialized Session's `Day`
        // (`instance.startDate + weekIndex*7`, computed independently per
        // component exactly as `StartPhaseUseCase`'s own scheduling call
        // already anchors to `phase.startDate` rather than `asOf` — the
        // same "anchor to the real template boundary, never the action
        // moment" precedent, applied here too) — always correct by
        // construction, never a re-derived guess.
        //
        // This also directly resolves Attempt 1's real failure (a Strength
        // component rolling week 0 for the first time alongside an FF
        // component already on week 1, in the SAME call — two components
        // genuinely at different weekIndex advancement is real, valid,
        // already-tested production behavior, not an edge case to
        // special-case away): rather than forcing one single canonical
        // week onto every component, the window WIDENS to cover the full
        // span from the earliest to the latest component's own real
        // target week. `ConcurrentScheduler.originWeekFloorOffset`
        // already exists, already handles a window spanning multiple real
        // weeks (built for Steady State's own multi-week-per-call
        // materialization), and already floors each session to its own
        // intended relative week within a wider window via its naive
        // `Day.date` — this reuses that existing, already-tested
        // mechanism rather than inventing a new one.
        let allNaiveDates = inputs.flatMap(\.sessions).compactMap { $0.day?.date }
        let calendar = Calendar.current
        let windowStartDate: Date
        let windowNumberOfDays: Int
        if let earliest = allNaiveDates.min(), let latest = allNaiveDates.max() {
            windowStartDate = calendar.startOfDay(for: earliest)
            let spanDays = calendar.dateComponents([.day], from: windowStartDate, to: calendar.startOfDay(for: latest)).day ?? 0
            // +7 guarantees the LATEST session's own real week is fully
            // covered even when that session isn't the first day of its
            // week (e.g. a Sunday session near the end of a 7-day span).
            windowNumberOfDays = spanDays + 7
        } else {
            // Defensive fallback only — every real materializer always
            // assigns a `Day` to a Session it produces, so this should
            // never be reached in practice. `asOf` here is strictly a
            // last resort, never the primary anchor.
            windowStartDate = asOf
            windowNumberOfDays = 7
        }

        // Stage CP.2 (Correction 1 — no post-scheduler regeneration): this
        // remains the ONLY `SchedulingPipeline.propose` call in a
        // successful `rollForward` attempt, exactly as before CP.2. If
        // `ConcurrentScheduler` still can't avoid a real day-adjacency
        // conflict, the existing typed `.interferenceConflict`
        // `ScheduleIssue` behavior is retained completely unchanged —
        // Concurrent Programming does not react to it. Post-scheduler
        // reprogramming/negotiation is a DEFERRED FUTURE CAPABILITY, not
        // built here (see `TRAINING_MIX_CONCURRENT_PROGRAMMING_DESIGN.md`'s
        // CP.2 Corrections Before Implementation section).
        let constraints = SchedulingConstraints(availability: availability, window: SchedulingWindow(startDate: windowStartDate, numberOfDays: windowNumberOfDays))
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
