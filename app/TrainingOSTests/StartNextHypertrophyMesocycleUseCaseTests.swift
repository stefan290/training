import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 10R.2B, corrected by Stage 10R.7A
/// (`STAGE10R7_STRATEGIC_PHASE_LIFECYCLE_DESIGN.md`, D-10R7-1/D-10R7-3):
/// proves the real, user-initiated Mesocycle 1 -> Mesocycle 2 transition —
/// fresh calibration required (never satisfied by Mesocycle 1's own),
/// exercise carry-forward (only when source-approved, with the athlete
/// free to change it before Mesocycle 2 starts), idempotency, and
/// persistence. **Also proves the Stage 10R.7A correction itself**: a
/// mesocycle succession never creates a new `TrainingPhase` — the whole
/// M1->M2->M3 sequence runs inside the SAME strategic phase, and the
/// SAME `TrainingMixComponent`'s `.programInstance` pointer is simply
/// reassigned to each new mesocycle's `ProgramInstance` in turn.
///
/// **Fixture boundary, stated plainly (mirrors `HypertrophyV2EndToEndTests`'s
/// own documented precedent):** `LongTermPlanner`'s goal/mix candidate
/// ranking is a separately, already-tested concern — this fixture attaches
/// a directly-generated 3-Day Full Body `ProgramDefinition` to a hand-built
/// `TrainingPhase`/`TrainingMix`/`TrainingMixComponent` rather than routing
/// through `StartPhaseUseCase.start()`'s own `LongTermPlanner.proposeProgram`
/// selection (which cannot be pinned to a specific configuration
/// deterministically). Every OTHER step is the real, unmodified
/// production path: `ResolveProgramInstanceExerciseSlotsUseCase`,
/// `RequiredSourceCalibrationsUseCase`, `RecordSourceRMCalibrationUseCase`,
/// `StartPhaseUseCase.materializeOnceCalibrationComplete`, and
/// `StartNextHypertrophyMesocycleUseCase` itself. "Mesocycle 1 complete" is
/// represented as a real, materialized Week-1 `ProgramInstance` state
/// (calibrated and materialized through the real gating flow) — not as
/// 4 real weeks + deload logged through every set, which would be an
/// excessively large fixture to prove something
/// `StartNextHypertrophyMesocycleUseCase` doesn't itself depend on (it only
/// reads the previous instance's own definition/config/exercise
/// resolution state, never whether every week was logged).
@MainActor
final class StartNextHypertrophyMesocycleUseCaseTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()
    let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)
    let startDate = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
        // Stage TE.1: `PhaseDetailViewModel`/`AdvanceTacticalWeekUseCase`
        // resolve `TrainingEnvironment` from the store's own `User`
        // (single-profile app, same "first User" convention already used
        // throughout this codebase) — a real, fully-equipped default so
        // every pre-existing test in this file keeps its exact prior
        // behavior.
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

    private func freshContext() -> ModelContext { ModelContext(container) }

    private func availability() -> UserAvailability {
        UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1)
    }

    private struct Fixture {
        var plan: TrainingPlan
        var phase: TrainingPhase
        var instance: ProgramInstance
        var mix: TrainingMix
        var component: TrainingMixComponent
        var catalog: ExerciseCatalog
    }

    /// Builds a real Mesocycle 1 (Basic Hypertrophy) phase/instance
    /// through the real calibration-gated production path, entering every
    /// required RM as `100`, ending with a real materialized Week 1.
    @discardableResult
    private func makeCalibratedMesocycle1() throws -> Fixture {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .muscleGain)
        context.insert(goal)
        let plan = TrainingPlan(status: .active)
        context.insert(plan)
        goal.addPlan(plan)

        let phase = TrainingPhase(type: .muscleGain, startDate: startDate, priorityRule: .strength, status: .active)
        context.insert(phase)
        plan.addPhase(phase)

        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 3, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: context
        )
        let instance = ProgramInstance(ownerUserID: ownerUserID, startDate: startDate, status: .active, priority: .primary)
        context.insert(instance)
        instance.programDefinition = definition
        phase.addProgramInstance(instance)

        let mix = TrainingMix(kind: .selected, name: "3-Day Full Body Hypertrophy")
        context.insert(mix)
        phase.addTrainingMix(mix)
        let component = TrainingMixComponent(label: "Hypertrophy", programmingSystem: .hypertrophy, priority: .primary, frequency: SessionFrequency(target: 3))
        context.insert(component)
        mix.addComponent(component)
        component.programInstance = instance

        try ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: try context.fetch(FetchDescriptor<Exercise>()), environment: TrainingEnvironmentTestSupport.full(context: context))

        let required = RequiredSourceCalibrationsUseCase.stillRequired(for: definition, instance: instance)
        XCTAssertFalse(required.isEmpty, "precondition: a fresh instance genuinely requires calibration")
        for requirement in required {
            RecordSourceRMCalibrationUseCase.record(exercise: requirement.exercise, rmType: requirement.rmType, kilograms: 100, for: instance, modelContext: context)
        }
        try context.save()
        XCTAssertTrue(RequiredSourceCalibrationsUseCase.stillRequired(for: definition, instance: instance).isEmpty)

        _ = try StartPhaseUseCase.materializeOnceCalibrationComplete(
            component: component, instance: instance, phase: phase, mix: mix, asOf: startDate,
            ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)), context: context
        )
        XCTAssertFalse(instance.sessions.isEmpty, "precondition: Mesocycle 1 Week 1 really materialized")

        return Fixture(plan: plan, phase: phase, instance: instance, mix: mix, component: component, catalog: catalog)
    }

    /// Stage 10R.3B: real Mesocycle 1 -> Mesocycle 2 -> a real, calibrated,
    /// materialized Mesocycle 2 — the fixture the M2 -> M3 transition
    /// tests below build on, exactly mirroring `makeCalibratedMesocycle1`'s
    /// own discipline one mesocycle later.
    @discardableResult
    private func makeCalibratedMesocycle2() throws -> Fixture {
        let mesocycle1 = try makeCalibratedMesocycle1()
        let transition = try StartNextHypertrophyMesocycleUseCase.start(
            previousPhase: mesocycle1.phase, previousInstance: mesocycle1.instance, asOf: startDate,
            ownerUserID: ownerUserID, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )
        XCTAssertTrue(transition.awaitingCalibration, "precondition: Mesocycle 2 requires fresh calibration")
        for requirement in RequiredSourceCalibrationsUseCase.stillRequired(for: try XCTUnwrap(transition.instance.programDefinition), instance: transition.instance) {
            RecordSourceRMCalibrationUseCase.record(exercise: requirement.exercise, rmType: requirement.rmType, kilograms: 90, for: transition.instance, modelContext: context)
        }
        try context.save()
        XCTAssertTrue(RequiredSourceCalibrationsUseCase.stillRequired(for: try XCTUnwrap(transition.instance.programDefinition), instance: transition.instance).isEmpty)

        _ = try StartPhaseUseCase.materializeOnceCalibrationComplete(
            component: try XCTUnwrap(transition.instance.trainingMixComponents.first),
            instance: transition.instance, phase: transition.phase, mix: try XCTUnwrap(transition.instance.trainingMixComponents.first?.trainingMix),
            asOf: startDate, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )
        XCTAssertFalse(transition.instance.sessions.isEmpty, "precondition: Mesocycle 2 Week 1 really materialized")

        let component = try XCTUnwrap(transition.instance.trainingMixComponents.first)
        let mix = try XCTUnwrap(component.trainingMix)
        return Fixture(plan: mesocycle1.plan, phase: transition.phase, instance: transition.instance, mix: mix, component: component, catalog: mesocycle1.catalog)
    }

    /// Stage 10R.4A: `PhaseDetailViewModel.canStartNextHypertrophyMesocycle`
    /// now requires the outgoing instance to be tactically EXHAUSTED
    /// (`STAGE10R4_TACTICAL_ROLLFORWARD_DESIGN.md` §5/§16 — the
    /// previously-existing gate, gated only on `!sessions.isEmpty`, let
    /// the action appear after only Week 1 materialized). Walks
    /// `instance` from wherever it currently is to real exhaustion using
    /// only skips (Locked Decision 3 — terminal, zero fabricated
    /// performance data) + the real, safe `AdvanceTacticalWeekUseCase`.
    private func rollDate(afterWeekIndex weekIndex: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: (weekIndex + 1) * 7, to: startDate) ?? startDate
    }

    @discardableResult
    private func skipToExhaustion(phase: TrainingPhase, instance: ProgramInstance) throws -> Int {
        var rolls = 0
        while !TacticalWeekCompletion.isInstanceExhausted(for: instance) {
            guard let weekIndex = TacticalWeekCompletion.currentMaterializedWeekIndex(for: instance) else { break }
            for session in ProgramWeekGrouping.realSessions(in: instance, forWeek: weekIndex) {
                try ChangeSessionStatusUseCase.skip(session, modelContext: context)
            }
            let outcome = try AdvanceTacticalWeekUseCase.advance(
                phase: phase, asOf: rollDate(afterWeekIndex: weekIndex), ownerUserID: ownerUserID, performanceProfile: nil,
                availability: availability(),
                materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
                context: context
            )
            guard outcome == .advanced else { break }
            rolls += 1
        }
        return rolls
    }

    // MARK: 21/22 — fresh calibration required; Mesocycle 1's does not satisfy Mesocycle 2

    func testTransitionRequiresFreshCalibrationNeverSatisfiedByMesocycleOnes() throws {
        let fixture = try makeCalibratedMesocycle1()

        let result = try StartNextHypertrophyMesocycleUseCase.start(
            previousPhase: fixture.phase, previousInstance: fixture.instance, asOf: startDate,
            ownerUserID: ownerUserID, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )

        XCTAssertTrue(result.awaitingCalibration, "Mesocycle 2 requires fresh RM — never satisfied by Mesocycle 1's own calibration rows")
        XCTAssertTrue(result.instance.sessions.isEmpty, "materialization must be deferred until fresh calibration is entered")
        let nextDefinition = try XCTUnwrap(result.instance.programDefinition)
        let stillRequired = RequiredSourceCalibrationsUseCase.stillRequired(for: nextDefinition, instance: result.instance)
        XCTAssertFalse(stillRequired.isEmpty)
    }

    // MARK: 23/24/25 — exercise carry-forward, only when source-approved; incompatible does not carry; user may change it

    func testExerciseCarriesForwardOnlyWhenSourceApproved() throws {
        let fixture = try makeCalibratedMesocycle1()
        let pushDay = try XCTUnwrap(fixture.instance.programDefinition?.orderedTemplateSessions.first { $0.name == "Push Emphasis" })
        let horizontalPushSlot = try XCTUnwrap(pushDay.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).first { $0.exerciseSlot?.name == "Horizontal Push" }?.exerciseSlot)
        let originalExercise = try XCTUnwrap(SubstituteExerciseUseCase.resolvedExercise(for: horizontalPushSlot, in: fixture.instance))
        XCTAssertEqual(originalExercise.canonicalName, "Barbell Bench Press", "precondition: the deterministic Mesocycle 1 default")

        let result = try StartNextHypertrophyMesocycleUseCase.start(
            previousPhase: fixture.phase, previousInstance: fixture.instance, asOf: startDate,
            ownerUserID: ownerUserID, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )

        let nextDefinition = try XCTUnwrap(result.instance.programDefinition)
        let nextPushDay = try XCTUnwrap(nextDefinition.orderedTemplateSessions.first { $0.name == "Push Emphasis" })
        let nextHorizontalPushSlot = try XCTUnwrap(nextPushDay.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).first { $0.exerciseSlot?.name == "Horizontal Push" }?.exerciseSlot)
        XCTAssertEqual(nextHorizontalPushSlot.resolvedExercise?.canonicalName, "Barbell Bench Press", "the athlete's actual Mesocycle 1 exercise carries forward as the visible default")

        // The 3 new superset-partner slots have no Mesocycle-1 equivalent
        // at all — they must still resolve (via the ordinary deterministic
        // fallback), never left blank.
        for slot in nextPushDay.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates) where slot.exerciseSlot?.name == "Incline Push or Front Delts" {
            XCTAssertNotNil(slot.exerciseSlot?.resolvedExercise, "even a brand-new superset-partner slot resolves to something, never left unresolved")
        }
    }

    // MARK: 25 — the athlete may still change a carried-forward selection

    func testCarriedForwardSelectionCanStillBeChangedByTheAthlete() throws {
        let fixture = try makeCalibratedMesocycle1()
        let result = try StartNextHypertrophyMesocycleUseCase.start(
            previousPhase: fixture.phase, previousInstance: fixture.instance, asOf: startDate,
            ownerUserID: ownerUserID, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )
        let nextDefinition = try XCTUnwrap(result.instance.programDefinition)
        let nextPushDay = try XCTUnwrap(nextDefinition.orderedTemplateSessions.first { $0.name == "Push Emphasis" })
        let horizontalPushSlot = try XCTUnwrap(nextPushDay.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).first { $0.exerciseSlot?.name == "Horizontal Push" }?.exerciseSlot)
        XCTAssertEqual(horizontalPushSlot.resolvedExercise?.canonicalName, "Barbell Bench Press", "precondition: carried forward as the visible default")

        // The athlete changes their mind before Mesocycle 2 starts — the
        // ordinary, already-existing GOING FORWARD substitution mechanism
        // (Stage 4C), unmodified by carry-forward, still wins.
        try SubstituteExerciseUseCase.substituteGoingForward(
            instance: result.instance, slot: horizontalPushSlot, with: fixture.catalog.inclineDumbbellPress,  environment: TrainingEnvironmentTestSupport.full(context: context), context: context
        )
        XCTAssertEqual(
            SubstituteExerciseUseCase.resolvedExercise(for: horizontalPushSlot, in: result.instance)?.canonicalName,
            "Incline Dumbbell Press", "the athlete's own change wins over the carried-forward default"
        )
    }

    /// Every carry-forward mapping is same-category-to-same-category (see
    /// `StartNextHypertrophyMesocycleUseCase`'s own table doc comment), so a
    /// genuinely incompatible carry-forward cannot occur through the
    /// normal, validated `SubstituteExerciseUseCase` path in this
    /// specific configuration — categories' `allowedTargets`/
    /// `allowedMovementFunctions` are identical across mesocycles. This
    /// test proves the safety net exists regardless: a directly-forced,
    /// intentionally-invalid override (bypassing `SubstituteExerciseUseCase`'s
    /// own validation on purpose, simulating "somehow an incompatible
    /// override exists") must still never carry forward — proving
    /// `StartNextHypertrophyMesocycleUseCase`'s carry-forward runs its OWN
    /// independent compatibility check rather than blindly trusting
    /// whatever a previous instance's override says.
    func testIncompatiblePreviousSelectionDoesNotCarryForward() throws {
        let fixture = try makeCalibratedMesocycle1()
        let pushDay = try XCTUnwrap(fixture.instance.programDefinition?.orderedTemplateSessions.first { $0.name == "Push Emphasis" })
        let horizontalPushSlot = try XCTUnwrap(pushDay.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).first { $0.exerciseSlot?.name == "Horizontal Push" }?.exerciseSlot)

        let incompatible = Exercise(canonicalName: "Test Incompatible Exercise", modality: .strength, equipment: "none", movementPattern: "isolation", primaryTargets: [.calves])
        context.insert(incompatible)
        let override = SlotSelectionOverride(selectedExercise: incompatible)
        override.templateSlot = horizontalPushSlot
        context.insert(override)
        fixture.instance.addSlotSelectionOverride(override)

        let result = try StartNextHypertrophyMesocycleUseCase.start(
            previousPhase: fixture.phase, previousInstance: fixture.instance, asOf: startDate,
            ownerUserID: ownerUserID, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )

        let nextDefinition = try XCTUnwrap(result.instance.programDefinition)
        let nextPushDay = try XCTUnwrap(nextDefinition.orderedTemplateSessions.first { $0.name == "Push Emphasis" })
        let nextHorizontalPushSlot = try XCTUnwrap(nextPushDay.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).first { $0.exerciseSlot?.name == "Horizontal Push" }?.exerciseSlot)
        XCTAssertNotEqual(nextHorizontalPushSlot.resolvedExercise?.canonicalName, "Test Incompatible Exercise", "an incompatible carried selection must never be used")
        XCTAssertEqual(nextHorizontalPushSlot.resolvedExercise?.canonicalName, "Barbell Bench Press", "falls through to the same deterministic resolution a fresh instance already uses")
    }

    // MARK: 26 — transition is user-initiated (no automatic trigger exists)

    func testTransitionIsNeverAutomaticOnlyExplicitCallTriggersIt() throws {
        let fixture = try makeCalibratedMesocycle1()
        // Merely having a real, materialized Mesocycle 1 instance must
        // never, by itself, create a second ProgramInstance — only an
        // explicit `StartNextHypertrophyMesocycleUseCase.start` call does.
        XCTAssertEqual(fixture.plan.orderedPhases.count, 1, "a mesocycle succession never creates a new strategic phase")
        XCTAssertEqual(fixture.phase.programInstances.count, 1, "no automatic second ProgramInstance appears on its own")
    }

    /// The Simulator sandbox this project develops in has no UI-tap
    /// automation available — this test is the closest honest substitute
    /// for "tap the button in `PhaseDetailView`": it drives the exact
    /// `PhaseDetailViewModel` the real button calls, proving the ViewModel
    /// layer (not just the underlying use case, already proven above) is
    /// wired correctly — the action appears only when appropriate, is
    /// correctly labeled, performs the real transition, and correctly
    /// hides itself afterward (the same idempotency signal the UI relies
    /// on to never offer a repeat tap).
    func testPhaseDetailViewModelOffersAndPerformsTheRealTransition() throws {
        let fixture = try makeCalibratedMesocycle1()
        try skipToExhaustion(phase: fixture.phase, instance: fixture.instance)
        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: fixture.phase, modelContext: context)

        XCTAssertTrue(viewModel.canStartNextHypertrophyMesocycle, "a real, TACTICALLY EXHAUSTED Hypertrophy phase with a next mesocycle must offer the action")
        XCTAssertEqual(viewModel.nextHypertrophyMesocycleTypeLabel, "Metabolite Focus")

        XCTAssertTrue(viewModel.startNextHypertrophyMesocycle(modelContext: context), "the real transition must succeed")
        XCTAssertEqual(fixture.plan.orderedPhases.count, 1, "Stage 10R.7A: a mesocycle succession never creates a new strategic phase")
        XCTAssertEqual(fixture.phase.programInstances.count, 2, "the real StartNextHypertrophyMesocycleUseCase actually ran — a second ProgramInstance now exists under the SAME phase")

        viewModel.load(phase: fixture.phase, modelContext: context)
        XCTAssertFalse(viewModel.canStartNextHypertrophyMesocycle, "hidden after a successful transition — the UI's own idempotency signal")
    }

    /// Stage 10R.3B: the same honest substitute as
    /// `testPhaseDetailViewModelOffersAndPerformsTheRealTransition`
    /// (this file's own top-level note on the sandbox's lack of UI-tap
    /// automation applies identically here), one mesocycle later — proves
    /// the ViewModel correctly offers "Start Resensitization" (not a
    /// stale "Start Metabolite Focus" label) once a real, calibrated
    /// Mesocycle 2 exists, and that tapping it performs the real M2 -> M3
    /// transition.
    func testPhaseDetailViewModelOffersAndPerformsTheRealMesocycleTwoToThreeTransition() throws {
        let fixture = try makeCalibratedMesocycle2()
        try skipToExhaustion(phase: fixture.phase, instance: fixture.instance)
        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: fixture.phase, modelContext: context)

        XCTAssertTrue(viewModel.canStartNextHypertrophyMesocycle, "a real, TACTICALLY EXHAUSTED Mesocycle 2 with a next mesocycle must offer the action")
        XCTAssertEqual(viewModel.nextHypertrophyMesocycleTypeLabel, "Resensitization")

        XCTAssertTrue(viewModel.startNextHypertrophyMesocycle(modelContext: context), "the real transition must succeed")
        XCTAssertEqual(fixture.plan.orderedPhases.count, 1, "Stage 10R.7A: a mesocycle succession never creates a new strategic phase")
        XCTAssertEqual(fixture.phase.programInstances.count, 3, "the real StartNextHypertrophyMesocycleUseCase actually ran — a third ProgramInstance now exists under the SAME phase")

        viewModel.load(phase: fixture.phase, modelContext: context)
        XCTAssertFalse(viewModel.canStartNextHypertrophyMesocycle, "hidden after a successful transition — Mesocycle 3 has no successor")
        XCTAssertNil(viewModel.nextHypertrophyMesocycleTypeLabel)
    }

    // MARK: 27/28 — idempotent; only one Mesocycle-2 ProgramInstance created

    func testTransitionIsIdempotentOnlyOneMesocycleTwoInstanceEverCreated() throws {
        let fixture = try makeCalibratedMesocycle1()
        let materializationContext = TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context))

        let first = try StartNextHypertrophyMesocycleUseCase.start(
            previousPhase: fixture.phase, previousInstance: fixture.instance, asOf: startDate,
            ownerUserID: ownerUserID, availability: availability(), materializationContext: materializationContext, context: context
        )
        let second = try StartNextHypertrophyMesocycleUseCase.start(
            previousPhase: fixture.phase, previousInstance: fixture.instance, asOf: startDate,
            ownerUserID: ownerUserID, availability: availability(), materializationContext: materializationContext, context: context
        )

        XCTAssertEqual(first.instance.id, second.instance.id, "a repeated call returns the same instance, never a duplicate")
        XCTAssertEqual(fixture.plan.orderedPhases.count, 1, "Stage 10R.7A: never a new strategic phase, regardless of how many times start() is called")
        let metaboliteFocusInstances = fixture.phase.programInstances.filter { $0.programDefinition?.hypertrophyConfiguration?.phaseType == .metaboliteFocus }
        XCTAssertEqual(metaboliteFocusInstances.count, 1, "exactly one Mesocycle 2 ProgramInstance, regardless of how many times start() is called")
        XCTAssertEqual(fixture.component.programInstance?.id, first.instance.id, "the SAME component's current pointer, never a new component")
    }

    // MARK: 29 — persistence survives terminate/relaunch

    func testTransitionPersistsAcrossRelaunch() throws {
        let fixture = try makeCalibratedMesocycle1()
        let planID = fixture.plan.id

        let result = try StartNextHypertrophyMesocycleUseCase.start(
            previousPhase: fixture.phase, previousInstance: fixture.instance, asOf: startDate,
            ownerUserID: ownerUserID, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )
        for requirement in RequiredSourceCalibrationsUseCase.stillRequired(for: try XCTUnwrap(result.instance.programDefinition), instance: result.instance) {
            RecordSourceRMCalibrationUseCase.record(exercise: requirement.exercise, rmType: requirement.rmType, kilograms: 120, for: result.instance, modelContext: context)
        }
        try context.save()

        let reloadedPlan = try XCTUnwrap(freshContext().fetch(FetchDescriptor<TrainingPlan>(predicate: #Predicate { $0.id == planID })).first)
        XCTAssertEqual(reloadedPlan.orderedPhases.count, 1, "Stage 10R.7A: still just the one strategic phase after relaunch")
        let reloadedPhase = try XCTUnwrap(reloadedPlan.orderedPhases.first)
        XCTAssertEqual(reloadedPhase.programInstances.count, 2, "both Mesocycle 1 and Mesocycle 2 ProgramInstances survive relaunch, under the same phase")
        let reloadedMesocycle2 = try XCTUnwrap(reloadedPhase.programInstances.first { $0.programDefinition?.hypertrophyConfiguration?.phaseType == .metaboliteFocus })
        XCTAssertFalse(reloadedMesocycle2.sourceRMCalibrations.isEmpty, "the entered Mesocycle 2 calibration survives relaunch")
        XCTAssertEqual(reloadedPhase.primaryInstance?.id, reloadedMesocycle2.id, "the phase's CURRENT primary instance is the successor mesocycle, not the original")
    }

    // MARK: Real production integration — Mesocycle 1 -> Mesocycle 2, full lifecycle

    /// See this file's own top-level doc comment for the exact fixture
    /// boundary this test operates within.
    func testRealProductionLifecycleFromMesocycleOneThroughCalibratedMesocycleTwo() throws {
        let fixture = try makeCalibratedMesocycle1()

        let transition = try StartNextHypertrophyMesocycleUseCase.start(
            previousPhase: fixture.phase, previousInstance: fixture.instance, asOf: startDate,
            ownerUserID: ownerUserID, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )
        XCTAssertTrue(transition.awaitingCalibration)
        let nextDefinition = try XCTUnwrap(transition.instance.programDefinition)
        XCTAssertEqual(nextDefinition.hypertrophyConfiguration?.phaseType, .metaboliteFocus)

        let required = RequiredSourceCalibrationsUseCase.stillRequired(for: nextDefinition, instance: transition.instance)
        XCTAssertFalse(required.isEmpty)
        for requirement in required {
            RecordSourceRMCalibrationUseCase.record(exercise: requirement.exercise, rmType: requirement.rmType, kilograms: 90, for: transition.instance, modelContext: context)
        }
        try context.save()

        _ = try StartPhaseUseCase.materializeOnceCalibrationComplete(
            component: try XCTUnwrap(transition.instance.trainingMixComponents.first),
            instance: transition.instance, phase: transition.phase, mix: try XCTUnwrap(transition.instance.trainingMixComponents.first?.trainingMix),
            asOf: startDate, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )

        XCTAssertFalse(transition.instance.sessions.isEmpty, "Mesocycle 2 Week 1 really materialized")
        let day1 = try XCTUnwrap(transition.instance.sessions.first { $0.name == "Push Emphasis" })
        let prescriptions = day1.orderedBlocks.flatMap(\.orderedPrescriptions)
        XCTAssertEqual(prescriptions.count, 9, "the real recovered Mesocycle 2 Day 1 (9 slots, including the superset partner)")
    }

    // MARK: Stage 10R.3B — Mesocycle 2 -> Mesocycle 3 transition

    func testMesocycle2ToMesocycle3TransitionRequiresFreshCalibrationNeverSatisfiedByEarlierMesocycles() throws {
        let fixture = try makeCalibratedMesocycle2()

        let result = try StartNextHypertrophyMesocycleUseCase.start(
            previousPhase: fixture.phase, previousInstance: fixture.instance, asOf: startDate,
            ownerUserID: ownerUserID, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )

        XCTAssertTrue(result.awaitingCalibration, "Mesocycle 3 requires fresh RM — never satisfied by Mesocycle 1 or 2's own calibration rows")
        XCTAssertTrue(result.instance.sessions.isEmpty, "materialization must be deferred until fresh calibration is entered")
        let nextDefinition = try XCTUnwrap(result.instance.programDefinition)
        XCTAssertEqual(nextDefinition.hypertrophyConfiguration?.phaseType, .resensitization)
        XCTAssertFalse(RequiredSourceCalibrationsUseCase.stillRequired(for: nextDefinition, instance: result.instance).isEmpty)
    }

    /// Stage 10R.3B: provenance is now phase-aware — proves the Mesocycle
    /// 3 instance's generated `ProgramDefinition` cites the real
    /// Mesocycle 3 sheet, not the Mesocycle 2 sheet this use case
    /// previously hardcoded regardless of which phase was being started.
    func testMesocycle3ProvenanceCitesItsOwnSheetNotMesocycleTwos() throws {
        let fixture = try makeCalibratedMesocycle2()
        let result = try StartNextHypertrophyMesocycleUseCase.start(
            previousPhase: fixture.phase, previousInstance: fixture.instance, asOf: startDate,
            ownerUserID: ownerUserID, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )
        let nextDefinition = try XCTUnwrap(result.instance.programDefinition)
        guard case .sourced(let file, let sheet, _) = nextDefinition.provenance else {
            return XCTFail("expected .sourced provenance")
        }
        XCTAssertEqual(file, "3 day full body_Novice.xlsx")
        XCTAssertEqual(sheet, "Mesocycle 3 Resensitization", "must never cite Mesocycle 2's sheet for a Mesocycle 3 instance")
    }

    func testMesocycle2ToMesocycle3CarryForwardUsesTheDedicatedMappingAndNeverTheM1ToM2Table() throws {
        let fixture = try makeCalibratedMesocycle2()
        let pushDay = try XCTUnwrap(fixture.instance.programDefinition?.orderedTemplateSessions.first { $0.name == "Push Emphasis" })
        let horizontalPushSlot = try XCTUnwrap(pushDay.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).first { $0.exerciseSlot?.name == "Horizontal Push" }?.exerciseSlot)
        let originalExercise = try XCTUnwrap(SubstituteExerciseUseCase.resolvedExercise(for: horizontalPushSlot, in: fixture.instance))
        XCTAssertEqual(originalExercise.canonicalName, "Barbell Bench Press", "precondition: the deterministic Mesocycle 2 default")

        let result = try StartNextHypertrophyMesocycleUseCase.start(
            previousPhase: fixture.phase, previousInstance: fixture.instance, asOf: startDate,
            ownerUserID: ownerUserID, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )

        let nextDefinition = try XCTUnwrap(result.instance.programDefinition)
        XCTAssertEqual(nextDefinition.orderedTemplateSessions.flatMap { $0.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates) }.count, 22, "Mesocycle 3's real 22-slot structure")

        let nextPushDay = try XCTUnwrap(nextDefinition.orderedTemplateSessions.first { $0.name == "Push Emphasis" })
        let nextHorizontalPushSlot = try XCTUnwrap(nextPushDay.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).first { $0.exerciseSlot?.name == "Horizontal Push" }?.exerciseSlot)
        XCTAssertEqual(nextHorizontalPushSlot.resolvedExercise?.canonicalName, "Barbell Bench Press", "the athlete's actual Mesocycle 2 exercise carries forward via the dedicated M2->M3 table")
    }

    /// Proves the M2-only rows (the 3 superset partners, "Chest Isolation
    /// or Triceps," and the 2nd Legs-day Quads occurrence) never create a
    /// phantom Mesocycle 3 slot or leak a leftover selection — they simply
    /// have no mapping entry, and Mesocycle 3 genuinely has fewer/different
    /// slots than Mesocycle 2.
    func testDroppedAndMesocycleTwoOnlyRowsDoNotLeakIntoMesocycleThree() throws {
        let fixture = try makeCalibratedMesocycle2()
        let result = try StartNextHypertrophyMesocycleUseCase.start(
            previousPhase: fixture.phase, previousInstance: fixture.instance, asOf: startDate,
            ownerUserID: ownerUserID, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )
        let nextDefinition = try XCTUnwrap(result.instance.programDefinition)
        XCTAssertFalse(
            nextDefinition.orderedTemplateSessions.contains { session in
                session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).contains { $0.exerciseSlot?.name == "Chest Isolation or Triceps" }
            },
            "the dropped Mesocycle-2-only category must never reappear in Mesocycle 3"
        )
        let nextLegsDay = try XCTUnwrap(nextDefinition.orderedTemplateSessions.first { $0.name == "Legs Emphasis" })
        let quadsSlots = nextLegsDay.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).filter { $0.exerciseSlot?.name == "Quads" }
        XCTAssertEqual(quadsSlots.count, 1, "Mesocycle 3's Legs day has exactly 1 Quads slot, never Mesocycle 2's 2")
        XCTAssertNotNil(quadsSlots.first?.exerciseSlot?.resolvedExercise, "even the sole Quads slot still resolves to something, never left unresolved")
    }

    func testMesocycle2ToMesocycle3TransitionIsIdempotent() throws {
        let fixture = try makeCalibratedMesocycle2()
        let materializationContext = TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context))

        let first = try StartNextHypertrophyMesocycleUseCase.start(
            previousPhase: fixture.phase, previousInstance: fixture.instance, asOf: startDate,
            ownerUserID: ownerUserID, availability: availability(), materializationContext: materializationContext, context: context
        )
        let second = try StartNextHypertrophyMesocycleUseCase.start(
            previousPhase: fixture.phase, previousInstance: fixture.instance, asOf: startDate,
            ownerUserID: ownerUserID, availability: availability(), materializationContext: materializationContext, context: context
        )

        XCTAssertEqual(first.instance.id, second.instance.id, "a repeated call returns the same instance, never a duplicate")
        XCTAssertEqual(fixture.plan.orderedPhases.count, 1, "Stage 10R.7A: never a new strategic phase, regardless of how many times start() is called")
        let resensitizationInstances = fixture.phase.programInstances.filter { $0.programDefinition?.hypertrophyConfiguration?.phaseType == .resensitization }
        XCTAssertEqual(resensitizationInstances.count, 1, "exactly one Mesocycle 3 ProgramInstance, regardless of how many times start() is called")
    }

    func testMesocycle3TransitionPersistsAcrossRelaunch() throws {
        let fixture = try makeCalibratedMesocycle2()
        let planID = fixture.plan.id

        let result = try StartNextHypertrophyMesocycleUseCase.start(
            previousPhase: fixture.phase, previousInstance: fixture.instance, asOf: startDate,
            ownerUserID: ownerUserID, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )
        for requirement in RequiredSourceCalibrationsUseCase.stillRequired(for: try XCTUnwrap(result.instance.programDefinition), instance: result.instance) {
            RecordSourceRMCalibrationUseCase.record(exercise: requirement.exercise, rmType: requirement.rmType, kilograms: 80, for: result.instance, modelContext: context)
        }
        try context.save()

        let reloadedPlan = try XCTUnwrap(freshContext().fetch(FetchDescriptor<TrainingPlan>(predicate: #Predicate { $0.id == planID })).first)
        XCTAssertEqual(reloadedPlan.orderedPhases.count, 1, "Stage 10R.7A: still just the one strategic phase after relaunch")
        let reloadedPhase = try XCTUnwrap(reloadedPlan.orderedPhases.first)
        XCTAssertEqual(reloadedPhase.programInstances.count, 3, "all 3 mesocycle ProgramInstances survive relaunch, under the same phase")
        let reloadedMesocycle3 = try XCTUnwrap(reloadedPhase.programInstances.first { $0.programDefinition?.hypertrophyConfiguration?.phaseType == .resensitization })
        XCTAssertFalse(reloadedMesocycle3.sourceRMCalibrations.isEmpty, "the entered Mesocycle 3 calibration survives relaunch")
        XCTAssertEqual(reloadedMesocycle3.programDefinition?.lengthWeeks, 3, "Mesocycle 3's own 3-week length survives relaunch")
        XCTAssertEqual(reloadedPhase.primaryInstance?.id, reloadedMesocycle3.id, "the phase's CURRENT primary instance is Mesocycle 3, not an earlier one")
    }

    /// The real production path: a calibrated Mesocycle 1 -> Mesocycle 2
    /// -> Mesocycle 3, exercising the full 3-phase lifecycle end to end
    /// (the "explain the boundary" fixture discipline this file's own
    /// top-level doc comment already establishes: real materialized
    /// Week-1 state per phase, not every set of every week logged).
    func testRealProductionLifecycleFromMesocycleOneThroughCalibratedMesocycleThree() throws {
        let fixture = try makeCalibratedMesocycle2()

        let transition = try StartNextHypertrophyMesocycleUseCase.start(
            previousPhase: fixture.phase, previousInstance: fixture.instance, asOf: startDate,
            ownerUserID: ownerUserID, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )
        XCTAssertTrue(transition.awaitingCalibration)
        let nextDefinition = try XCTUnwrap(transition.instance.programDefinition)
        XCTAssertEqual(nextDefinition.hypertrophyConfiguration?.phaseType, .resensitization)
        XCTAssertEqual(nextDefinition.lengthWeeks, 3)

        let required = RequiredSourceCalibrationsUseCase.stillRequired(for: nextDefinition, instance: transition.instance)
        XCTAssertFalse(required.isEmpty)
        for requirement in required {
            RecordSourceRMCalibrationUseCase.record(exercise: requirement.exercise, rmType: requirement.rmType, kilograms: 85, for: transition.instance, modelContext: context)
        }
        try context.save()

        _ = try StartPhaseUseCase.materializeOnceCalibrationComplete(
            component: try XCTUnwrap(transition.instance.trainingMixComponents.first),
            instance: transition.instance, phase: transition.phase, mix: try XCTUnwrap(transition.instance.trainingMixComponents.first?.trainingMix),
            asOf: startDate, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)),
            context: context
        )

        XCTAssertFalse(transition.instance.sessions.isEmpty, "Mesocycle 3 Week 1 really materialized")
        let day1 = try XCTUnwrap(transition.instance.sessions.first { $0.name == "Push Emphasis" })
        let prescriptions = day1.orderedBlocks.flatMap(\.orderedPrescriptions)
        XCTAssertEqual(prescriptions.count, 7, "the real recovered Mesocycle 3 Day 1 (7 slots, no superset partner, no Chest Isolation or Triceps)")
        XCTAssertEqual(fixture.plan.orderedPhases.count, 1, "Stage 10R.7A: the full 3-mesocycle lifecycle runs inside one strategic phase")
        XCTAssertEqual(fixture.phase.programInstances.count, 3, "all 3 mesocycles of the real lifecycle now exist under that one phase")
    }
}
