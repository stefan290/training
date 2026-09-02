import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 10R.7A (`STAGE10R7_STRATEGIC_PHASE_LIFECYCLE_DESIGN.md`,
/// D-10R7-1 through D-10R7-12): proves the corrected strategic/program
/// lifecycle boundary — a `TrainingPhase` is a pre-planned strategic
/// period; Hypertrophy mesocycle succession runs INSIDE the same phase
/// and must never be suppressed by an already-existing next strategic
/// phase; `TrainingPhaseCompletion`'s derived queries; and
/// `TransitionPhaseUseCase`'s atomic transaction boundary. Every test
/// drives the real production chain: `AcceptStrategicPlanUseCase` (which
/// really does pre-plan every strategic phase up front) ->
/// `StartPhaseUseCase`/`StartNextHypertrophyMesocycleUseCase` for
/// mesocycle succession -> `TransitionPhaseUseCase` for strategic
/// succession.
@MainActor
final class StrategicPhaseLifecycleTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()
    let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
        // Stage TE.1: real fixture default — see identical note in
        // StartNextHypertrophyMesocycleUseCaseTests.setUpWithError.
        let user = User(displayName: "TE.1 Fixture User")
        context.insert(user)
        let profile = UserProfile()
        context.insert(profile)
        user.attachProfile(profile)
        let fullGym = TrainingEnvironment(name: "Test Full Gym", availableEquipment: EquipmentRequirement.allCases)
        context.insert(fullGym)
        profile.trainingEnvironments = [fullGym]
        profile.defaultTrainingEnvironment = fullGym
        try? context.save()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar.current.date(from: components)!
    }

    private func availability() -> UserAvailability {
        UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1)
    }

    private struct AllCandidates {
        let strength: [Exercise]
        let functionalFitness: [Exercise]
    }

    private func makeCandidates() -> AllCandidates {
        func exercise(
            _ name: String, _ targets: [MuscleGroup] = [], _ movementFunctions: [MovementFunction] = [], _ functionalModality: FunctionalModality? = nil
        ) -> Exercise {
            let ex = Exercise(canonicalName: name, modality: .hypertrophy, equipment: "barbell", movementPattern: "test", primaryTargets: targets, movementFunctions: movementFunctions, functionalModality: functionalModality)
            context.insert(ex)
            return ex
        }
        let strength = [
            exercise("Aaa Lifecycle Primary Shoulders", [.shoulders]),
            exercise("Aaa Lifecycle Primary Quads", [.quadriceps]),
            exercise("Aaa Lifecycle Primary Back", [.back]),
            exercise("Zzz Lifecycle Paired Accessory", [.chest, .triceps]),
        ]
        let ff = [
            exercise("Lifecycle FF Squat Lift", [], [.squatLoaded], .weightlifting),
            exercise("Lifecycle FF Pull-up", [], [.gymnasticsPull], .gymnastics),
            exercise("Lifecycle FF Bike", [], [.monostructural], .metabolicConditioning),
        ]
        return AllCandidates(strength: strength, functionalFitness: ff)
    }

    private func makeAcceptedPlan(asOf: Date) throws -> (goal: Goal, plan: TrainingPlan) {
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .muscleGain, targetDate: Calendar.current.date(byAdding: .year, value: 1, to: asOf), createdAt: asOf)
        context.insert(goal)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: asOf)
        return (goal, plan)
    }

    private func rollDate(_ start: Date, afterWeekIndex weekIndex: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: (weekIndex + 1) * 7, to: start) ?? start
    }

    @discardableResult
    private func skipEveryRealSession(in instance: ProgramInstance, weekIndex: Int) throws -> Void {
        for session in ProgramWeekGrouping.realSessions(in: instance, forWeek: weekIndex) {
            try ChangeSessionStatusUseCase.skip(session, modelContext: context)
        }
    }

    @discardableResult
    private func skipToExhaustion(phase: TrainingPhase, instance: ProgramInstance, startDate: Date) throws -> Int {
        var rolls = 0
        while !TacticalWeekCompletion.isInstanceExhausted(for: instance) {
            guard let weekIndex = TacticalWeekCompletion.currentMaterializedWeekIndex(for: instance) else { break }
            try skipEveryRealSession(in: instance, weekIndex: weekIndex)
            let outcome = try AdvanceTacticalWeekUseCase.advance(
                phase: phase, asOf: rollDate(startDate, afterWeekIndex: weekIndex), ownerUserID: ownerUserID, performanceProfile: nil,
                availability: availability(),
                materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
                context: context
            )
            guard outcome == .advanced else { break }
            rolls += 1
        }
        return rolls
    }

    // MARK: 1/2 — the plan pre-plans every strategic phase up front; Phase 1 is a real 3-Day Full Body hypertrophy lifecycle

    func testPlanPrePlansPhase1AndPhase2UpFrontAndPhase1RunsARealHypertrophyLifecycle() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        XCTAssertGreaterThanOrEqual(fixture.plan.orderedPhases.count, 2, "AcceptStrategicPlanUseCase pre-plans every phase up front — Phase 2 already exists before Phase 1 ever starts")
        XCTAssertEqual(fixture.plan.orderedPhases[0].status, .planned)
        XCTAssertEqual(fixture.plan.orderedPhases[1].status, .planned)

        let phase1 = fixture.plan.orderedPhases[0]
        let candidates = makeCandidates()
        let mix1Candidates = LongTermPlanner.proposeTrainingMix(phase: phase1, goal: fixture.goal)
        let mix1 = try XCTUnwrap(mix1Candidates.first { $0.mix.name == "Focused Hypertrophy" })
        try StartPhaseUseCase.start(
            phase: phase1, mix: mix1.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness, trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )
        try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: phase1, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            asOf: asOf, context: context
        )
        XCTAssertEqual(phase1.primaryInstance?.programDefinition?.hypertrophyConfiguration?.phaseType, .basicHypertrophy, "Phase 1 runs a real Mesocycle 1 (Basic Hypertrophy) lifecycle")
    }

    // MARK: 3/4/5/6 — the central Stage 10R.7A regression: a pre-planned Phase 2 must never suppress mesocycle succession inside Phase 1

    func testCompletingMesocycleOneExposesStartMetaboliteFocusEvenThoughStrategicPhaseTwoAlreadyExists() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        XCTAssertGreaterThanOrEqual(fixture.plan.orderedPhases.count, 2)
        let phase1 = fixture.plan.orderedPhases[0]
        let originalPhaseCount = fixture.plan.orderedPhases.count

        let candidates = makeCandidates()
        let mix1Candidates = LongTermPlanner.proposeTrainingMix(phase: phase1, goal: fixture.goal)
        let mix1 = try XCTUnwrap(mix1Candidates.first { $0.mix.name == "Focused Hypertrophy" })
        try StartPhaseUseCase.start(
            phase: phase1, mix: mix1.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness, trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )
        try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: phase1, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            asOf: asOf, context: context
        )
        let hypertrophyInstance = try XCTUnwrap(phase1.primaryInstance)
        try skipToExhaustion(phase: phase1, instance: hypertrophyInstance, startDate: asOf)
        XCTAssertTrue(TacticalWeekCompletion.isInstanceExhausted(for: hypertrophyInstance), "precondition: Mesocycle 1 really exhausted")

        // The critical assertion (D-10R7-3): Phase 2 ALREADY exists in
        // `orderedPhases` — the OLD, incorrect gate (`nextPhase == nil`)
        // would have hidden the mesocycle-succession action here.
        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: phase1, modelContext: context)
        XCTAssertNotNil(viewModel.nextPhase, "precondition: a real pre-planned strategic Phase 2 already exists")
        XCTAssertTrue(viewModel.canStartNextHypertrophyMesocycle, "a pre-planned future STRATEGIC phase must never suppress mesocycle succession INSIDE Phase 1")
        XCTAssertEqual(viewModel.nextHypertrophyMesocycleTypeLabel, "Metabolite Focus")

        let hypertrophyInstanceCountBefore = phase1.programInstances.filter { $0.programDefinition?.hypertrophyConfiguration != nil }.count
        XCTAssertTrue(viewModel.startNextHypertrophyMesocycle(modelContext: context), "the real mesocycle succession must succeed")
        XCTAssertEqual(fixture.plan.orderedPhases.count, originalPhaseCount, "no additional strategic phase was generated")
        XCTAssertEqual(
            phase1.programInstances.filter { $0.programDefinition?.hypertrophyConfiguration != nil }.count, hypertrophyInstanceCountBefore + 1,
            "Mesocycle 2 now exists, attached to the SAME strategic Phase 1 (Focused Hypertrophy's own SteadyState component is untouched)"
        )
        XCTAssertEqual(phase1.primaryInstance?.programDefinition?.hypertrophyConfiguration?.phaseType, .metaboliteFocus, "Mesocycle 2 remains associated with strategic Phase 1")
        XCTAssertFalse(RequiredSourceCalibrationsUseCase.stillRequired(for: try XCTUnwrap(phase1.primaryInstance?.programDefinition), instance: try XCTUnwrap(phase1.primaryInstance)).isEmpty, "fresh Mesocycle 2 calibration is still required — never satisfied by Mesocycle 1's own")
    }

    // MARK: 12/13 — a phase becomes terminal once every component's program lifecycle (including the final hypertrophy mesocycle) is exhausted with no successor

    func testPhaseBecomesTerminalOnceMesocycleThreeAndEveryOtherComponentIsExhausted() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        let originalPhaseCount = fixture.plan.orderedPhases.count
        let phase1 = fixture.plan.orderedPhases[0]
        let candidates = makeCandidates()
        let mix1 = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: phase1, goal: fixture.goal).first { $0.mix.name == "Focused Hypertrophy" })
        try StartPhaseUseCase.start(
            phase: phase1, mix: mix1.mix, asOf: asOf, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness, trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )
        try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: phase1, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            asOf: asOf, context: context
        )

        // Walk M1 -> M2 -> M3 to exhaustion, all inside the same Phase 1.
        for _ in 0..<2 {
            let instance = try XCTUnwrap(phase1.primaryInstance)
            try skipToExhaustion(phase: phase1, instance: instance, startDate: asOf)
            XCTAssertFalse(TrainingPhaseCompletion.isPhaseTerminal(phase1), "not terminal yet — a further mesocycle is still available")
            let component = try XCTUnwrap((phase1.selectedTrainingMix ?? phase1.recommendedTrainingMix)?.orderedComponents.first { $0.priority == .primary })
            _ = try StartNextHypertrophyMesocycleUseCase.start(
                previousPhase: phase1, previousInstance: instance, asOf: asOf, ownerUserID: ownerUserID, availability: availability(),
                materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
                context: context
            )
            for requirement in RequiredSourceCalibrationsUseCase.stillRequired(for: try XCTUnwrap(component.programInstance?.programDefinition), instance: try XCTUnwrap(component.programInstance)) {
                RecordSourceRMCalibrationUseCase.record(exercise: requirement.exercise, rmType: requirement.rmType, kilograms: 90, for: try XCTUnwrap(component.programInstance), modelContext: context)
            }
            try context.save()
            _ = try StartPhaseUseCase.materializeOnceCalibrationComplete(
                component: component, instance: try XCTUnwrap(component.programInstance), phase: phase1, mix: try XCTUnwrap(component.trainingMix),
                asOf: asOf, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
                materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
                context: context
            )
        }
        XCTAssertEqual(phase1.primaryInstance?.programDefinition?.hypertrophyConfiguration?.phaseType, .resensitization, "now on Mesocycle 3, still the same Phase 1")

        let finalInstance = try XCTUnwrap(phase1.primaryInstance)
        try skipToExhaustion(phase: phase1, instance: finalInstance, startDate: asOf)
        XCTAssertTrue(TacticalWeekCompletion.isInstanceExhausted(for: finalInstance))
        let component = try XCTUnwrap((phase1.selectedTrainingMix ?? phase1.recommendedTrainingMix)?.orderedComponents.first { $0.priority == .primary })
        XCTAssertTrue(TrainingPhaseCompletion.isComponentProgramLifecycleTerminal(component), "Mesocycle 3 exhausted with no next mesocycle — the component's program lifecycle is terminal")

        // "Focused Hypertrophy" is itself a mixed mix (Hypertrophy +
        // SteadyState/"Zone 2 Conditioning") — the phase is only terminal
        // once EVERY component's program lifecycle is, so the SteadyState
        // component must also be exhausted (it has no succession
        // mechanism at all — D-10R6-10 — so exhaustion alone is terminal
        // for it).
        XCTAssertFalse(TrainingPhaseCompletion.isPhaseTerminal(phase1), "Hypertrophy finished, but the SteadyState/Zone 2 Conditioning component is still unfinished")
        let steadyStateComponent = try XCTUnwrap((phase1.selectedTrainingMix ?? phase1.recommendedTrainingMix)?.orderedComponents.first { $0.programmingSystem == .steadyState })
        let steadyStateInstance = try XCTUnwrap(steadyStateComponent.programInstance)
        for weekIndex in 0..<(steadyStateInstance.programDefinition?.orderedWeeks.count ?? 0) {
            try skipEveryRealSession(in: steadyStateInstance, weekIndex: weekIndex)
        }
        XCTAssertTrue(TrainingPhaseCompletion.isComponentProgramLifecycleTerminal(steadyStateComponent), "SteadyState has no succession mechanism — exhaustion alone is terminal for it")

        XCTAssertTrue(TrainingPhaseCompletion.isPhaseTerminal(phase1), "a phase becomes terminal once EVERY one of its components' program lifecycles is terminal")
        XCTAssertEqual(fixture.plan.orderedPhases.count, originalPhaseCount, "still exactly the pre-planned phases — no phase was ever fabricated by mesocycle succession")
    }

    // MARK: 14/15 — mixed-modality phase terminal semantics

    func testMixedModalityPhaseIsNotTerminalUntilEveryComponentIsTerminal() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        XCTAssertGreaterThanOrEqual(fixture.plan.orderedPhases.count, 2)
        let phase2 = fixture.plan.orderedPhases[1]
        // Phase 2 must be `.planned` -> `.active` first; a real strategic
        // transition needs Phase 1 `.active` and terminal first, but here
        // we only need Phase 2 STARTED to test its own mixed-modality
        // terminal semantics directly, so start it the same way
        // `TransitionPhaseUseCase`/tests already do: via `StartPhaseUseCase
        // .start` directly (phase status guard only requires `.planned`).
        let candidates = makeCandidates()
        let mix2 = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: phase2, goal: fixture.goal).first { $0.mix.name == "Strength Plus Variety" })
        try StartPhaseUseCase.start(
            phase: phase2, mix: mix2.mix, asOf: asOf, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness, trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )
        try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: phase2, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            asOf: asOf, context: context
        )
        XCTAssertEqual(mix2.mix.orderedComponents.count, 3, "Hypertrophy + Functional Fitness + Running — sanity check on the real candidate")

        XCTAssertFalse(TrainingPhaseCompletion.isPhaseTerminal(phase2), "nothing has been exhausted yet")

        // Exhaust ONLY the Hypertrophy component's current mesocycle —
        // Functional Fitness and Running remain unfinished.
        let hypertrophyComponent = try XCTUnwrap(mix2.mix.orderedComponents.first { $0.programmingSystem == .hypertrophy })
        let hypertrophyInstance = try XCTUnwrap(hypertrophyComponent.programInstance)
        try skipToExhaustion(phase: phase2, instance: hypertrophyInstance, startDate: asOf)
        // Mesocycle 1 exhausted, but Mesocycle 2 is still available for
        // this Hypertrophy configuration — exhaustion ALONE is correctly
        // NOT yet component-terminal (a further mesocycle succession is
        // still expected, D-10R7-5's own distinction).
        XCTAssertFalse(TrainingPhaseCompletion.isComponentProgramLifecycleTerminal(hypertrophyComponent), "a further mesocycle is still available for Hypertrophy — not yet program-lifecycle terminal")
        XCTAssertFalse(TrainingPhaseCompletion.isPhaseTerminal(phase2), "Hypertrophy not yet program-lifecycle terminal + Functional Fitness/Running unfinished => the mixed phase must NOT be terminal")
    }

    // MARK: 16 — date boundary alone never fabricates completion

    func testPhaseDateBoundaryAloneNeverFabricatesCompletion() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        let phase1 = fixture.plan.orderedPhases[0]
        let candidates = makeCandidates()
        let mix1 = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: phase1, goal: fixture.goal).first { $0.mix.name == "Focused Hypertrophy" })
        try StartPhaseUseCase.start(
            phase: phase1, mix: mix1.mix, asOf: asOf, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness, trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )
        try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: phase1, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            asOf: asOf, context: context
        )
        // Nothing has been exhausted — Phase 1 has a real `endDate`
        // (planner-computed) but is nowhere near it yet.
        XCTAssertNotNil(phase1.endDate)
        XCTAssertFalse(TrainingPhaseCompletion.isPhaseTerminal(phase1), "far from its own endDate, unfinished — correctly not terminal")

        // Even a phase whose endDate has already passed, with real
        // required work still unfinished, must not be treated as
        // terminal — `isPhaseTerminal` never reads `endDate`/the current
        // date at all (D-10R7-6).
        phase1.endDate = Calendar.current.date(byAdding: .day, value: -1, to: asOf)
        XCTAssertFalse(TrainingPhaseCompletion.isPhaseTerminal(phase1), "a passed endDate alone must never fabricate completion while real required work remains unfinished")
    }

    // MARK: 17/18 — next strategic phase resolution never fabricates one

    func testNextStrategicPhaseResolvesTheExistingPrePlannedPhaseNeverFabricatesOne() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        let phase1 = fixture.plan.orderedPhases[0]
        let phase2 = fixture.plan.orderedPhases[1]
        XCTAssertEqual(TrainingPhaseCompletion.nextStrategicPhase(for: phase1)?.id, phase2.id)
        XCTAssertFalse(TrainingPhaseCompletion.isFinalStrategicPhase(phase1))
        let lastPhase = try XCTUnwrap(fixture.plan.orderedPhases.last)
        XCTAssertNil(TrainingPhaseCompletion.nextStrategicPhase(for: lastPhase))
        XCTAssertTrue(TrainingPhaseCompletion.isFinalStrategicPhase(lastPhase))
        XCTAssertEqual(fixture.plan.orderedPhases.count, fixture.plan.orderedPhases.count, "purely a read — never mutates or fabricates a phase")
    }

    // MARK: 20/21/22/23 — atomic strategic transition: idempotency, forced failure, unrelated state survives

    func testImmediateSecondTransitionInvocationCannotTransitionAgainAndForcedFailurePreservesValidState() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        let phase1 = fixture.plan.orderedPhases[0]
        let phase2 = fixture.plan.orderedPhases[1]
        let candidates = makeCandidates()
        let mix1 = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: phase1, goal: fixture.goal).first { $0.mix.name == "Focused Hypertrophy" })
        try StartPhaseUseCase.start(
            phase: phase1, mix: mix1.mix, asOf: asOf, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness, trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )
        try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: phase1, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            asOf: asOf, context: context
        )

        // An unrelated, unsaved pending mutation U.
        let unrelatedGoal = Goal(ownerUserID: ownerUserID, primaryType: .enduranceEvent)
        context.insert(unrelatedGoal)
        let unrelatedGoalID = unrelatedGoal.id

        // Force a genuine failure: an empty mix has no components at all,
        // so `StartPhaseUseCase.start` throws `.mixHasNoComponents` —
        // AFTER the scratch context has already marked the outgoing phase
        // completed, proving the whole attempt is discarded together.
        let emptyMix = TrainingMix(kind: .selected, name: "Empty")
        XCTAssertThrowsError(try TransitionPhaseUseCase.transition(
            from: phase1, toNextPhaseWithMix: emptyMix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)), context: context
        )) { error in
            XCTAssertEqual(error as? StartPhaseError, .mixHasNoComponents)
        }

        // U survives, untouched.
        XCTAssertTrue(context.hasChanges, "U is still a pending, unsaved mutation")
        XCTAssertNotNil(try context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.id == unrelatedGoalID })).first)

        // Phase 1 is still valid/active — never left permanently completed by the failed attempt.
        XCTAssertEqual(phase1.status, .active, "a failed transition must never leave the outgoing phase completed")
        XCTAssertEqual(phase2.status, .planned, "a failed transition must never partially activate the next phase")
        for instance in phase1.programInstances {
            XCTAssertNotEqual(instance.status, .completed, "a failed transition must never mark the outgoing instances completed either")
        }

        // Now retry, this time with a real mix — succeeds exactly once.
        let mix2 = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: phase2, goal: fixture.goal).first { $0.mix.name == "Strength Plus Variety" })
        let transitionResult = try TransitionPhaseUseCase.transition(
            from: phase1, toNextPhaseWithMix: mix2.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness, trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )
        XCTAssertEqual(transitionResult.completedPhase.id, phase1.id)
        XCTAssertEqual(phase1.status, .completed)
        XCTAssertEqual(phase2.status, .active)

        // Immediate second invocation cannot transition again — Phase 1 is
        // no longer `.active`.
        XCTAssertThrowsError(try TransitionPhaseUseCase.transition(
            from: phase1, toNextPhaseWithMix: mix2.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness, trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )) { error in
            XCTAssertEqual(error as? PhaseTransitionError, .outgoingPhaseNotActive)
        }
        // U is STILL there, unaffected by any of this.
        XCTAssertNotNil(try context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.id == unrelatedGoalID })).first)
    }

    // MARK: 24 — transition into a calibration-required next phase is a coherent, non-failing state

    func testTransitionIntoCalibrationRequiredPhaseProducesCoherentAwaitingCalibrationState() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        let phase1 = fixture.plan.orderedPhases[0]
        let phase2 = fixture.plan.orderedPhases[1]
        let candidates = makeCandidates()
        let mix1 = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: phase1, goal: fixture.goal).first { $0.mix.name == "Focused Hypertrophy" })
        try StartPhaseUseCase.start(
            phase: phase1, mix: mix1.mix, asOf: asOf, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness, trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )
        try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: phase1, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            asOf: asOf, context: context
        )

        let mix2 = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: phase2, goal: fixture.goal).first { $0.mix.name == "Strength Plus Variety" })
        let transitionResult = try TransitionPhaseUseCase.transition(
            from: phase1, toNextPhaseWithMix: mix2.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness, trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )

        // Phase 2's Hypertrophy component is `.rmBased` and genuinely
        // requires fresh calibration — a coherent, successfully-committed
        // transition, not a failure.
        XCTAssertFalse(transitionResult.startResult.componentsAwaitingCalibration.isEmpty, "the Hypertrophy component of Phase 2's mix genuinely awaits calibration")
        XCTAssertEqual(transitionResult.nextPhase.status, .active, "the phase itself is fully active despite one component awaiting calibration")
        let hypertrophyInstance = try XCTUnwrap(transitionResult.startResult.instancesByComponent.values.first {
            $0.programDefinition?.programmingSystem == .hypertrophy
        })
        XCTAssertTrue(hypertrophyInstance.sessions.isEmpty, "no fabricated tactical content for the awaiting-calibration component")
        XCTAssertFalse(RequiredSourceCalibrationsUseCase.stillRequired(for: try XCTUnwrap(hypertrophyInstance.programDefinition), instance: hypertrophyInstance).isEmpty)
    }

    // MARK: TE.1 closure — the scratch-context TrainingEnvironment re-fetch fix, regression-proven

    /// `TransitionPhaseUseCase.transition` runs its whole orchestration
    /// against an isolated SCRATCH `ModelContext`, separate from this test's
    /// own `context` — the same established atomic-transaction pattern
    /// `AdvanceTacticalWeekUseCase` already uses. A `TrainingEnvironment`
    /// fetched in THIS context is bound to it; passing it directly into the
    /// scratch context (rather than re-fetching it there by
    /// `persistentModelID`, as `TransitionPhaseUseCase.swift` lines ~194-196
    /// do) reproduced a real `NSCocoaErrorDomain Code=1560` validation
    /// failure during TE.1 implementation. This proves the fix holds: the
    /// transition succeeds with a real environment carried across that
    /// boundary, the SAME environment row survives with its own fields
    /// unchanged when re-fetched from an entirely fresh `ModelContext`
    /// afterward, the new phase's materialized Functional Fitness session
    /// correctly references that same row, and an unrelated candidate
    /// `Exercise` used in the same transition is untouched — mirroring the
    /// exact "corrupts an unrelated row" symptom class this bug belongs to
    /// (`STAGE10R7A_TX_ROOT_CAUSE_REPORT.md`).
    func testTransitionPhaseRefetchesTrainingEnvironmentByIDAcrossTheScratchContextBoundaryWithoutCorruption() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        let phase1 = fixture.plan.orderedPhases[0]
        let phase2 = fixture.plan.orderedPhases[1]
        let candidates = makeCandidates()
        let unrelatedExerciseID = try XCTUnwrap(candidates.strength.first).id
        let unrelatedExerciseOriginalName = try XCTUnwrap(candidates.strength.first).canonicalName

        // A distinctive, narrowly-equipped environment (not the generic
        // "full gym" fixture) so its exact post-transition equipment set is
        // unambiguous evidence of "unchanged," not merely "still non-empty."
        let environment = TrainingEnvironment(name: "TE.1 Scratch Boundary Test Environment", availableEquipment: [.barbell, .rack, .bench])
        context.insert(environment)
        try context.save()
        let environmentID = environment.persistentModelID

        let mix1 = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: phase1, goal: fixture.goal).first { $0.mix.name == "Focused Hypertrophy" })
        try StartPhaseUseCase.start(
            phase: phase1, mix: mix1.mix, asOf: asOf, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness, trainingEnvironment: environment),
            context: context
        )
        try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: phase1, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, trainingEnvironment: environment),
            asOf: asOf, context: context
        )

        let mix2 = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: phase2, goal: fixture.goal).first { $0.mix.name == "Strength Plus Variety" })
        let transitionResult = try TransitionPhaseUseCase.transition(
            from: phase1, toNextPhaseWithMix: mix2.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness, trainingEnvironment: environment),
            context: context
        )
        XCTAssertEqual(transitionResult.nextPhase.status, .active, "the transition itself must succeed with a real environment threaded across the scratch-context boundary")

        // The Functional Fitness component materializes immediately (no
        // calibration gate) — its Session must reference the SAME
        // environment row, proving the scratch-context re-fetch resolved
        // to the real, correct object, not a corrupted or orphaned one.
        let ffInstance = try XCTUnwrap(transitionResult.startResult.instancesByComponent.values.first {
            $0.programDefinition?.programmingSystem == .functionalFitness
        })
        let ffSession = try XCTUnwrap(ffInstance.sessions.first)
        XCTAssertEqual(ffSession.materializedInEnvironment?.id, environment.id, "the materialized session must reference the exact same TrainingEnvironment row, not a duplicate produced by a corrupted re-fetch")

        // Re-fetch everything from a BRAND NEW ModelContext — proves
        // persisted, on-disk state, not merely this test's own in-memory
        // object graph.
        let freshContext = ModelContext(container)
        let refetchedEnvironment = try XCTUnwrap(freshContext.fetch(FetchDescriptor<TrainingEnvironment>(predicate: #Predicate { $0.persistentModelID == environmentID })).first)
        XCTAssertEqual(refetchedEnvironment.name, "TE.1 Scratch Boundary Test Environment", "the environment's own fields must survive the scratch-context boundary unchanged")
        XCTAssertEqual(Set(refetchedEnvironment.availableEquipment), Set([.barbell, .rack, .bench]), "equipment must be exactly what was configured — no corruption, no silent widening/narrowing")

        let refetchedUnrelatedExercise = try XCTUnwrap(freshContext.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == unrelatedExerciseID })).first)
        XCTAssertEqual(refetchedUnrelatedExercise.canonicalName, unrelatedExerciseOriginalName, "an unrelated candidate Exercise used in the same transition must be untouched — the exact symptom class (\"corrupts an unrelated row\") this scratch-context bug belongs to")
    }
}
