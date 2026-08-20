import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 7 (Tactical Planning Orchestration), Slice 4 acceptance fix
/// (round 7): proves the new `LongTermPlanner.PlanningContext` mechanism
/// — a phase's previous/next sibling derived purely from `TrainingPlan
/// .orderedPhases`, never a new persisted relationship — resolves
/// correctly and deterministically, that Maintenance/Recovery/Transition
/// no longer share one indistinguishable code path, that the existing
/// selected-over-recommended precedence is honored and never mutated by
/// merely previewing, and that `preferredActivityType`'s real wiring fix
/// lets program resolution honor a stated activity preference instead of
/// silently defaulting to running. Every phase here comes from the real
/// `LongTermPlanner.proposeStrategicPlan`/`AcceptStrategicPlanUseCase`
/// pipeline, never a hand-built fixture.
///
/// A later round added the actual TRAININGOS-DESIGNED reduced-dose
/// policy itself (`LongTermPlanner.maintenanceComponentDecisions`) — its
/// own dedicated tests live in the "Reduced-dose policy" section below.
@MainActor
final class MaintenancePlanningContextTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar.current.date(from: components)!
    }

    /// A long enough horizon that the real planner's own cadence rule
    /// (Maintenance after 2 consecutive Muscle Gain phases) fires at
    /// least once — matches `LongTermPlannerStrategicPlanTests`'s own
    /// proven fixture shape.
    private func makePlanWithMaintenance() throws -> (goal: Goal, plan: TrainingPlan) {
        let goal = Goal(ownerUserID: UUID(), primaryType: .muscleGain, targetDate: date(2028, 8, 14), createdAt: date(2026, 8, 14))
        context.insert(goal)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: date(2026, 8, 14))
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: date(2026, 8, 14))
        XCTAssertTrue(plan.orderedPhases.contains { $0.type == .maintenance })
        return (goal, plan)
    }

    // MARK: H — the contextual mechanism inspects previous/next without persisting a new relationship

    func testPlanningContextResolvesPreviousAndNextPurelyFromOrderedPhases() throws {
        let (_, plan) = try makePlanWithMaintenance()
        let maintenanceIndex = try XCTUnwrap(plan.orderedPhases.firstIndex { $0.type == .maintenance })
        let maintenancePhase = plan.orderedPhases[maintenanceIndex]

        let planningContext = LongTermPlanner.planningContext(for: maintenancePhase)

        XCTAssertEqual(planningContext.previousPhase?.id, plan.orderedPhases[maintenanceIndex - 1].id, "previous phase must be the plan's own immediate predecessor")
        if plan.orderedPhases.indices.contains(maintenanceIndex + 1) {
            XCTAssertEqual(planningContext.nextPhase?.id, plan.orderedPhases[maintenanceIndex + 1].id)
        }
        XCTAssertEqual(planningContext.previousPhase?.type, .muscleGain, "the planner's own cadence rule guarantees Maintenance follows Muscle Gain in this fixture")

        // No new persisted relationship: TrainingPhase's own schema is
        // untouched by resolving context — this is pure computation over
        // the already-existing TrainingPlan.orderedPhases relationship.
        XCTAssertTrue(try context.fetchCount(FetchDescriptor<TrainingPhase>()) == plan.orderedPhases.count)
    }

    func testFirstPhaseInAPlanHasNoPreviousPhase() throws {
        let (_, plan) = try makePlanWithMaintenance()
        let firstPhase = try XCTUnwrap(plan.orderedPhases.first)
        let planningContext = LongTermPlanner.planningContext(for: firstPhase)
        XCTAssertNil(planningContext.previousPhase)
    }

    // MARK: B/I — the preceding phase's selected mix is the strongest signal, and is never mutated by previewing

    func testPreviousTrainingMixPrefersTheSelectedMixOverTheRecommendation() throws {
        let (_, plan) = try makePlanWithMaintenance()
        let maintenancePhase = try XCTUnwrap(plan.orderedPhases.first { $0.type == .maintenance })
        let priorMuscleGainPhase = try XCTUnwrap(LongTermPlanner.planningContext(for: maintenancePhase).previousPhase)

        let recommended = TrainingMix(kind: .recommended, name: "Recommended Placeholder")
        context.insert(recommended)
        priorMuscleGainPhase.addTrainingMix(recommended)
        let selected = TrainingMix(kind: .selected, name: "What The User Actually Trained")
        context.insert(selected)
        priorMuscleGainPhase.addTrainingMix(selected)

        let resolved = LongTermPlanner.planningContext(for: maintenancePhase).previousTrainingMix
        XCTAssertEqual(resolved?.id, selected.id, "a .selected mix must always win over a .recommended one when resolving planning context, mirroring TrainingMix's own existing precedence rule")

        // Merely resolving context must never mutate the source phase.
        XCTAssertEqual(priorMuscleGainPhase.trainingMixes.count, 2)
        XCTAssertEqual(priorMuscleGainPhase.selectedTrainingMix?.id, selected.id)
    }

    // MARK: C — falls back to the recommendation when no selected mix exists

    func testPreviousTrainingMixFallsBackToTheRecommendationWhenNoneIsSelected() throws {
        let (_, plan) = try makePlanWithMaintenance()
        let maintenancePhase = try XCTUnwrap(plan.orderedPhases.first { $0.type == .maintenance })
        let priorMuscleGainPhase = try XCTUnwrap(LongTermPlanner.planningContext(for: maintenancePhase).previousPhase)

        let recommended = TrainingMix(kind: .recommended, name: "Only Recommendation On Record")
        context.insert(recommended)
        priorMuscleGainPhase.addTrainingMix(recommended)

        let resolved = LongTermPlanner.planningContext(for: maintenancePhase).previousTrainingMix
        XCTAssertEqual(resolved?.id, recommended.id, "with no selected mix, context must deterministically fall back to the recommendation rather than resolving to nil")
    }

    // MARK: D — deterministic for identical inputs

    func testMaintenanceRecommendationIsDeterministicAcrossRepeatedCalls() throws {
        let (goal, plan) = try makePlanWithMaintenance()
        let maintenancePhase = try XCTUnwrap(plan.orderedPhases.first { $0.type == .maintenance })

        let firstRun = LongTermPlanner.proposeTrainingMix(phase: maintenancePhase, goal: goal)
        let secondRun = LongTermPlanner.proposeTrainingMix(phase: maintenancePhase, goal: goal)

        XCTAssertEqual(firstRun.map(\.mix.name), secondRun.map(\.mix.name))
        XCTAssertEqual(
            firstRun.map { $0.mix.orderedComponents.map(\.label) },
            secondRun.map { $0.mix.orderedComponents.map(\.label) }
        )
    }

    // MARK: E — Maintenance recommendation never materializes tactical state

    func testResolvingMaintenanceContextAndRecommendationCreatesNoTacticalState() throws {
        let (goal, plan) = try makePlanWithMaintenance()
        let maintenancePhase = try XCTUnwrap(plan.orderedPhases.first { $0.type == .maintenance })
        let sessionCountBefore = try context.fetchCount(FetchDescriptor<Session>())
        let instanceCountBefore = try context.fetchCount(FetchDescriptor<ProgramInstance>())

        _ = LongTermPlanner.planningContext(for: maintenancePhase)
        _ = LongTermPlanner.proposeTrainingMix(phase: maintenancePhase, goal: goal)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Session>()), sessionCountBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramInstance>()), instanceCountBefore)
        XCTAssertTrue(maintenancePhase.programInstances.isEmpty)
        XCTAssertEqual(maintenancePhase.status, .planned)
    }

    // MARK: F — viewing an upcoming Maintenance phase remains read-only end-to-end

    func testViewingAnUpcomingMaintenancePhaseThroughTheRealViewModelRemainsReadOnly() throws {
        let (_, plan) = try makePlanWithMaintenance()
        let maintenancePhase = try XCTUnwrap(plan.orderedPhases.first { $0.type == .maintenance })
        let sessionCountBefore = try context.fetchCount(FetchDescriptor<Session>())
        let mixCountBefore = try context.fetchCount(FetchDescriptor<TrainingMix>())

        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: maintenancePhase, modelContext: context)
        viewModel.load(phase: maintenancePhase, modelContext: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Session>()), sessionCountBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainingMix>()), mixCountBefore)
        XCTAssertNotNil(viewModel.upcomingPreviewMix, "the real Maintenance phase must still expose a preview even though nothing was persisted")
    }

    // MARK: G — Maintenance, Recovery and Transition no longer share one indistinguishable policy path

    func testMaintenanceRecoveryAndTransitionKeepDistinctMixIdentitiesAndCodePaths() throws {
        let (goal, plan) = try makePlanWithMaintenance()
        let maintenancePhase = try XCTUnwrap(plan.orderedPhases.first { $0.type == .maintenance })

        // Hand-built Recovery/Transition phases (never persisted as part
        // of a real plan here — only used to exercise candidateMixTemplates'
        // now-separate switch arms directly, which is exactly what this
        // test needs to prove).
        let recoveryPhase = TrainingPhase(type: .recovery, startDate: date(2026, 8, 14), priorityRule: .mixedModal)
        let transitionPhase = TrainingPhase(type: .transition, startDate: date(2026, 8, 14), priorityRule: .mixedModal)

        let maintenanceMix = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: maintenancePhase, goal: goal).first?.mix)
        let recoveryMix = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: recoveryPhase, goal: goal).first?.mix)
        let transitionMix = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: transitionPhase, goal: goal).first?.mix)

        XCTAssertEqual(maintenanceMix.name, "Maintenance")
        XCTAssertEqual(recoveryMix.name, "Recovery")
        XCTAssertEqual(transitionMix.name, "Transition")
        XCTAssertNotEqual(maintenanceMix.name, recoveryMix.name)
        XCTAssertNotEqual(maintenanceMix.name, transitionMix.name)

        // Recovery/Transition must never consult planning context — giving
        // the preceding phase a real selected mix must not change
        // Recovery's own output, proving it stays on the plain generic
        // path (`lowerDemandGenericMix`) rather than routing through
        // Maintenance's own `maintenanceMix` seam.
        let priorMuscleGainPhase = try XCTUnwrap(LongTermPlanner.planningContext(for: maintenancePhase).previousPhase)
        let selected = TrainingMix(kind: .selected, name: "Heavy Strength Focus")
        context.insert(selected)
        priorMuscleGainPhase.addTrainingMix(selected)
        let recoveryMixAfter = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: recoveryPhase, goal: goal).first?.mix)
        XCTAssertEqual(recoveryMixAfter.orderedComponents.map(\.label), recoveryMix.orderedComponents.map(\.label), "Recovery's recommendation must be unaffected by preceding-phase context, unlike Maintenance's")
    }

    // MARK: J — program resolution uses the resulting components' own stated preference, not a hardcoded Running default

    func testPreferredActivityTypeResolvesFromGoalPreferencesInsteadOfDefaultingToRunning() throws {
        let cyclingGoal = Goal(
            ownerUserID: UUID(), primaryType: .maintenance,
            preferences: GoalPreferences(preferredModalities: [ModalityPreference(system: .steadyState, activityType: .cycling)]),
            createdAt: date(2026, 8, 14)
        )
        context.insert(cyclingGoal)
        let component = TrainingMixComponent(label: "General Conditioning", programmingSystem: .steadyState, priority: .primary, frequency: SessionFrequency(target: 2))
        context.insert(component)
        let scratchContext = ModelContext(PersistenceController.makeInMemoryContainer())

        let candidate = LongTermPlanner.previewProgramCandidate(component: component, goal: cyclingGoal, context: scratchContext)

        XCTAssertEqual(candidate?.programDefinition.name.contains("Cycling"), true, "a stated Steady State activity preference must be honored instead of silently defaulting to Running")
        XCTAssertFalse(candidate?.programDefinition.name.contains("Running") ?? true)
    }

    func testPreferredActivityTypeStillDefaultsToRunningWithNoStatedPreference() throws {
        let goalWithNoPreference = Goal(ownerUserID: UUID(), primaryType: .maintenance, createdAt: date(2026, 8, 14))
        context.insert(goalWithNoPreference)
        let component = TrainingMixComponent(label: "General Conditioning", programmingSystem: .steadyState, priority: .primary, frequency: SessionFrequency(target: 2))
        context.insert(component)
        let scratchContext = ModelContext(PersistenceController.makeInMemoryContainer())

        let candidate = LongTermPlanner.previewProgramCandidate(component: component, goal: goalWithNoPreference, context: scratchContext)

        XCTAssertEqual(candidate?.programDefinition.name.contains("Running"), true, "the pre-existing, still-correct default behavior must be unchanged when no preference is stated")
    }

    // MARK: - Reduced-dose policy

    /// Replaces whatever mix the plan's own real prior Muscle Gain phase
    /// was given with a hand-shaped `.selected` one — the transform under
    /// test only ever reads `component.priority`/`programmingSystem`/
    /// `frequency`, so this is the real production input shape, just
    /// controlled precisely enough to exercise one worked example at a
    /// time.
    @discardableResult
    private func setPreviousPhaseSelectedMix(_ plan: TrainingPlan, components: [(label: String, system: ProgrammingSystemKind, priority: GoalPriority, target: Int, minimum: Int?)]) throws -> TrainingMix {
        let maintenancePhase = try XCTUnwrap(plan.orderedPhases.first { $0.type == .maintenance })
        let previousPhase = try XCTUnwrap(LongTermPlanner.planningContext(for: maintenancePhase).previousPhase)
        // `selectedTrainingMix` reads `trainingMixes.first { .selected }` —
        // clear any mix a prior call in the SAME test already attached,
        // so re-calling this helper for a new sub-case doesn't silently
        // keep resolving to the first one ever added.
        previousPhase.trainingMixes.removeAll()
        let mix = TrainingMix(kind: .selected, name: "Prior Selected Mix")
        context.insert(mix)
        for spec in components {
            mix.addComponent(TrainingMixComponent(
                label: spec.label, programmingSystem: spec.system, priority: spec.priority,
                frequency: SessionFrequency(target: spec.target, minimum: spec.minimum)
            ))
        }
        previousPhase.addTrainingMix(mix)
        return mix
    }

    private func maintenanceComponents(_ goal: Goal, _ plan: TrainingPlan) throws -> [TrainingMixComponent] {
        let maintenancePhase = try XCTUnwrap(plan.orderedPhases.first { $0.type == .maintenance })
        let mix = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: maintenancePhase, goal: goal).first?.mix)
        return mix.orderedComponents
    }

    // A: 5x Hypertrophy (primary) + 2x Conditioning (supporting) -> preserves Hypertrophy at 2x, reduces (never drops to zero) Conditioning, never collapses to Conditioning-only.
    func testFocusedHypertrophyMaintenancePreservesHypertrophyAndReducesConditioning() throws {
        let (goal, plan) = try makePlanWithMaintenance()
        try setPreviousPhaseSelectedMix(plan, components: [
            ("Hypertrophy", .hypertrophy, .primary, 5, nil),
            ("Zone 2 Conditioning", .steadyState, .supporting, 2, nil),
        ])

        let components = try maintenanceComponents(goal, plan)
        let hypertrophy = try XCTUnwrap(components.first { $0.programmingSystem == .hypertrophy })
        XCTAssertEqual(hypertrophy.frequency.target, 2)
        XCTAssertTrue(components.contains { $0.programmingSystem == .steadyState }, "Conditioning must still be present, just reduced — Maintenance must never collapse to Conditioning-only")
        let conditioning = try XCTUnwrap(components.first { $0.programmingSystem == .steadyState })
        XCTAssertEqual(conditioning.frequency.target, 1)
        XCTAssertTrue(components.contains { $0.programmingSystem == .hypertrophy }, "must never collapse to a single non-resistance modality")
    }

    // B/C/D/E: resistance-training frequency floor never goes below 1, and 2/week is the floor for anything that was previously meaningful (>=3).
    func testResistanceFrequencyFloorAcrossPreviousTargets() throws {
        let (goal, plan) = try makePlanWithMaintenance()

        try setPreviousPhaseSelectedMix(plan, components: [("Strength", .hypertrophy, .primary, 3, nil)])
        XCTAssertEqual(try maintenanceComponents(goal, plan).first?.frequency.target, 2, "B: 3/week reduces to the 2/week maintenance floor")

        try setPreviousPhaseSelectedMix(plan, components: [("Strength", .hypertrophy, .primary, 2, nil)])
        XCTAssertEqual(try maintenanceComponents(goal, plan).first?.frequency.target, 2, "C: 2/week is already at the floor and stays at 2")

        try setPreviousPhaseSelectedMix(plan, components: [("Strength", .hypertrophy, .primary, 1, nil)])
        let oneXResult = try maintenanceComponents(goal, plan)
        XCTAssertEqual(oneXResult.first?.frequency.target, 1, "D: 1/week is preserved, never reduced further")
        XCTAssertNotEqual(oneXResult.first?.frequency.target, 0)

        // E, generalized: no previous target, however high, ever reduces a preserved resistance component to zero.
        for previousTarget in 1...7 {
            try setPreviousPhaseSelectedMix(plan, components: [("Strength", .powerlifting, .secondary, previousTarget, nil)])
            let result = try maintenanceComponents(goal, plan)
            XCTAssertFalse(result.isEmpty, "a Primary/Secondary resistance component must never be omitted entirely")
            XCTAssertGreaterThanOrEqual(result.first?.frequency.target ?? 0, 1, "previous target \(previousTarget) must never reduce to zero")
        }
    }

    // F/G: Primary/Secondary non-resistance reduction.
    func testNonResistancePrimarySecondaryFrequencyReduction() throws {
        let (goal, plan) = try makePlanWithMaintenance()

        try setPreviousPhaseSelectedMix(plan, components: [("Conditioning", .steadyState, .primary, 4, nil)])
        XCTAssertEqual(try maintenanceComponents(goal, plan).first?.frequency.target, 2, "F: 4/week non-resistance reduces to 2/week")

        try setPreviousPhaseSelectedMix(plan, components: [("Conditioning", .steadyState, .primary, 3, nil)])
        XCTAssertEqual(try maintenanceComponents(goal, plan).first?.frequency.target, 1, "G: 3/week non-resistance reduces to 1/week")
    }

    // H: the worked 3 Strength + 2 FF + 1 Running example — Supporting is reduced/removed before any Primary component is touched, and Strength (Primary) is preserved throughout.
    func testStrengthPlusVarietyMaintenancePreservesStrengthAndTrimsSupportingFirst() throws {
        let (goal, plan) = try makePlanWithMaintenance()
        try setPreviousPhaseSelectedMix(plan, components: [
            ("Strength", .hypertrophy, .primary, 3, nil),
            ("Functional Fitness", .functionalFitness, .supporting, 2, nil),
            ("Running", .steadyState, .supporting, 1, nil),
        ])

        let components = try maintenanceComponents(goal, plan)
        let strength = try XCTUnwrap(components.first { $0.programmingSystem == .hypertrophy })
        XCTAssertEqual(strength.frequency.target, 2, "Strength (Primary) is preserved and reduced to the resistance floor")

        let functionalFitness = components.first { $0.programmingSystem == .functionalFitness }
        XCTAssertEqual(functionalFitness?.frequency.target, 1, "Functional Fitness (Supporting, previously 2/week) is reduced, not removed")

        let running = components.first { $0.programmingSystem == .steadyState }
        XCTAssertNil(running, "Running (Supporting, previously only 1/week, with another Supporting component already occupying the reduced-demand budget) is trimmed before ever touching Strength")

        XCTAssertEqual(components.map(\.frequency.target).reduce(0, +), 3, "2x Strength + 1x Functional Fitness")
    }

    // I: total weekly target is lower than the preceding mix in the normal multi-component case.
    func testMaintenanceTotalWeeklyTargetIsLowerThanThePrecedingMix() throws {
        let (goal, plan) = try makePlanWithMaintenance()
        let previousComponents: [(label: String, system: ProgrammingSystemKind, priority: GoalPriority, target: Int, minimum: Int?)] = [
            ("Strength", .hypertrophy, .primary, 3, nil),
            ("Functional Fitness", .functionalFitness, .supporting, 2, nil),
            ("Running", .steadyState, .supporting, 1, nil),
        ]
        try setPreviousPhaseSelectedMix(plan, components: previousComponents)
        let previousTotal = previousComponents.reduce(0) { $0 + $1.target }

        let maintenanceTotal = try maintenanceComponents(goal, plan).map(\.frequency.target).reduce(0, +)

        XCTAssertLessThan(maintenanceTotal, previousTotal, "Maintenance must contain fewer total weekly sessions than the preceding accumulation phase in the normal multi-component case")
    }

    // J: selected-over-recommended precedence still holds through the full proposeTrainingMix pipeline with the real transform active.
    func testMaintenanceUsesThePrecedingSelectedMixOverItsRecommendationEndToEnd() throws {
        let (goal, plan) = try makePlanWithMaintenance()
        let maintenancePhase = try XCTUnwrap(plan.orderedPhases.first { $0.type == .maintenance })
        let previousPhase = try XCTUnwrap(LongTermPlanner.planningContext(for: maintenancePhase).previousPhase)

        let recommended = TrainingMix(kind: .recommended, name: "Recommended")
        context.insert(recommended)
        recommended.addComponent(TrainingMixComponent(label: "Hypertrophy", programmingSystem: .hypertrophy, priority: .primary, frequency: SessionFrequency(target: 5)))
        previousPhase.addTrainingMix(recommended)

        let selected = TrainingMix(kind: .selected, name: "Selected")
        context.insert(selected)
        selected.addComponent(TrainingMixComponent(label: "Powerlifting", programmingSystem: .powerlifting, priority: .primary, frequency: SessionFrequency(target: 4)))
        previousPhase.addTrainingMix(selected)

        let components = try maintenanceComponents(goal, plan)
        XCTAssertTrue(components.contains { $0.programmingSystem == .powerlifting }, "must derive from the SELECTED mix (Powerlifting), never the merely-recommended one (Hypertrophy)")
        XCTAssertFalse(components.contains { $0.programmingSystem == .hypertrophy })
    }

    // K: previewing a Maintenance phase with the real reduced-dose transform active still creates no tactical state.
    func testMaintenanceReducedDoseTransformNeverMaterializesTacticalState() throws {
        let (goal, plan) = try makePlanWithMaintenance()
        try setPreviousPhaseSelectedMix(plan, components: [
            ("Strength", .hypertrophy, .primary, 3, nil),
            ("Running", .steadyState, .supporting, 1, nil),
        ])
        let maintenancePhase = try XCTUnwrap(plan.orderedPhases.first { $0.type == .maintenance })
        let sessionCountBefore = try context.fetchCount(FetchDescriptor<Session>())
        let instanceCountBefore = try context.fetchCount(FetchDescriptor<ProgramInstance>())

        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: maintenancePhase, modelContext: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Session>()), sessionCountBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramInstance>()), instanceCountBefore)
        XCTAssertTrue(maintenancePhase.programInstances.isEmpty)
        XCTAssertNotNil(viewModel.upcomingPreviewMix)
    }

    // L: deterministic for identical inputs, with a real (non-fallback) previous mix.
    func testMaintenanceReducedDoseTransformIsDeterministic() throws {
        let (goal, plan) = try makePlanWithMaintenance()
        try setPreviousPhaseSelectedMix(plan, components: [
            ("Strength", .hypertrophy, .primary, 5, nil),
            ("Functional Fitness", .functionalFitness, .supporting, 2, nil),
            ("Running", .steadyState, .supporting, 1, nil),
        ])

        let firstRun = try maintenanceComponents(goal, plan).map { ($0.label, $0.frequency.target) }
        let secondRun = try maintenanceComponents(goal, plan).map { ($0.label, $0.frequency.target) }

        XCTAssertEqual(firstRun.map(\.0), secondRun.map(\.0))
        XCTAssertEqual(firstRun.map(\.1), secondRun.map(\.1))
    }

    // M: Recovery and Transition remain unaffected by the Maintenance transform even when the preceding phase has a rich selected mix.
    func testRecoveryAndTransitionRemainUnaffectedByTheMaintenanceReducedDoseTransform() throws {
        let (goal, plan) = try makePlanWithMaintenance()
        try setPreviousPhaseSelectedMix(plan, components: [
            ("Strength", .hypertrophy, .primary, 5, nil),
            ("Conditioning", .steadyState, .supporting, 2, nil),
        ])

        let recoveryPhase = TrainingPhase(type: .recovery, startDate: date(2026, 8, 14), priorityRule: .mixedModal)
        let transitionPhase = TrainingPhase(type: .transition, startDate: date(2026, 8, 14), priorityRule: .mixedModal)

        let recoveryMix = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: recoveryPhase, goal: goal).first?.mix)
        let transitionMix = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: transitionPhase, goal: goal).first?.mix)

        XCTAssertEqual(recoveryMix.orderedComponents.map(\.label), ["General Conditioning"])
        XCTAssertEqual(recoveryMix.orderedComponents.first?.frequency.target, 2)
        XCTAssertEqual(transitionMix.orderedComponents.map(\.label), ["General Conditioning"])
        XCTAssertEqual(transitionMix.orderedComponents.first?.frequency.target, 2)
        XCTAssertFalse(recoveryMix.orderedComponents.contains { $0.programmingSystem == .hypertrophy }, "Recovery must never pick up Maintenance's own preserved-hypertrophy behavior")
    }

    // N: an existing minimum floor on a preceding component is respected, never violated.
    func testMaintenanceTransformNeverProducesATargetBelowAnExistingMinimum() throws {
        let (goal, plan) = try makePlanWithMaintenance()
        // A Supporting component whose own minimum (3) is deliberately
        // higher than anything the reduction formula alone would
        // propose (1) — the floor must win.
        try setPreviousPhaseSelectedMix(plan, components: [
            ("Strength", .hypertrophy, .primary, 3, nil),
            ("Required Conditioning", .steadyState, .supporting, 3, 3),
        ])

        let components = try maintenanceComponents(goal, plan)
        let conditioning = try XCTUnwrap(components.first { $0.label == "Required Conditioning" })
        XCTAssertGreaterThanOrEqual(conditioning.frequency.target, conditioning.frequency.minimum ?? 0, "target must never fall below an existing minimum")
        XCTAssertEqual(conditioning.frequency.target, 3, "the existing minimum (3) overrides the formula's own proposal (1) rather than silently violating it")
    }

    // MARK: - Real seeded fixture end-to-end (Slice 4 acceptance)

    private func makeSeedJourney() throws -> SeedAnnualPlanJourney.Result {
        let user = User(displayName: "Test User")
        context.insert(user)
        let profile = PerformanceProfile()
        context.insert(profile)
        user.attachPerformanceProfile(profile)
        let catalog = ExerciseCatalog.makeAndInsert(context: context)
        return try SeedAnnualPlanJourney.seed(user: user, performanceProfile: profile, catalog: catalog, context: context)
    }

    /// The real acceptance fixture's own Maintenance phase sits
    /// immediately after the ACTIVE phase ("Strength Plus Variety": 3x
    /// Strength + 2x Functional Fitness + 1x Running, `.selected`) — NOT
    /// after the two-phases-back completed phase ("Focused Hypertrophy").
    /// `planningContext`'s previous phase is always the plan's own
    /// immediate predecessor, so this is what the seeded Maintenance
    /// preview must derive from. Documents the real, verified end-to-end
    /// outcome rather than assuming which prior mix applies.
    func testSeededUpcomingMaintenancePreviewDerivesFromTheImmediatelyPrecedingActivePhase() throws {
        let journey = try makeSeedJourney()
        let maintenancePhase = try XCTUnwrap(journey.upcomingPhases.first)
        XCTAssertEqual(maintenancePhase.type, .maintenance)
        XCTAssertEqual(maintenancePhase.status, .planned, "still genuinely upcoming — nothing materialized")

        let planningContext = LongTermPlanner.planningContext(for: maintenancePhase)
        XCTAssertEqual(planningContext.previousPhase?.id, journey.activePhase.id, "Maintenance's immediate predecessor in this fixture is the ACTIVE phase, not the completed one two phases back")
        XCTAssertEqual(planningContext.previousTrainingMix?.id, journey.activePhase.selectedTrainingMix?.id)
        XCTAssertEqual(planningContext.previousTrainingMix?.name, "Strength Plus Variety")

        let components = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: maintenancePhase, goal: journey.goal).first?.mix).orderedComponents
        let strength = try XCTUnwrap(components.first { $0.programmingSystem == .hypertrophy })
        XCTAssertEqual(strength.frequency.target, 2, "Strength (Primary, previously 3x) preserved at the resistance floor")
        let functionalFitness = try XCTUnwrap(components.first { $0.programmingSystem == .functionalFitness })
        XCTAssertEqual(functionalFitness.frequency.target, 1, "Functional Fitness (Supporting, previously 2x) reduced, not removed")
        XCTAssertNil(components.first { $0.programmingSystem == .steadyState }, "Running (Supporting, previously 1x, with Functional Fitness already occupying the reduced-Supporting slot) is trimmed")
        XCTAssertNotEqual(components.map(\.label).sorted(), ["General Conditioning"], "must never be the old generic single-conditioning fallback")

        // Also verified through the real, production ViewModel — the
        // exact path the Simulator UI itself uses.
        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: maintenancePhase, modelContext: context)
        let previewLabels = Set(viewModel.upcomingComponentPreviews.map(\.component.label))
        XCTAssertEqual(previewLabels, ["Strength", "Functional Fitness"])
    }
}
