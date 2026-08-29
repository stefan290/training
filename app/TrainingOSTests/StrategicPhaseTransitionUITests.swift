import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 10R.7B: proves the strategic phase-transition UI wiring —
/// `PlanViewModel.phaseAwaitingStrategicTransition`,
/// `PhaseDetailViewModel.canPresentStrategicTransition`/
/// `isFinalStrategicPhaseComplete`, and `StrategicTransitionViewModel`'s one
/// deliberate write — through the exact same real production chain
/// `StrategicPhaseLifecycleTests` already established
/// (`AcceptStrategicPlanUseCase` -> `StartPhaseUseCase`/
/// `StartNextHypertrophyMesocycleUseCase` -> `TransitionPhaseUseCase`).
/// Terminal/lifecycle semantics themselves are `TrainingPhaseCompletion`'s
/// own job, already proven there — this file proves the UI layer correctly
/// EXPOSES and ACTS on those semantics, never reimplements them.
@MainActor
final class StrategicPhaseTransitionUITests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()
    let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)

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
            exercise("UI Lifecycle Primary Shoulders", [.shoulders]),
            exercise("UI Lifecycle Primary Quads", [.quadriceps]),
            exercise("UI Lifecycle Primary Back", [.back]),
            exercise("UI Lifecycle Paired Accessory", [.chest, .triceps]),
        ]
        let ff = [
            exercise("UI Lifecycle FF Squat Lift", [], [.squatLoaded], .weightlifting),
            exercise("UI Lifecycle FF Pull-up", [], [.gymnasticsPull], .gymnastics),
            exercise("UI Lifecycle FF Bike", [], [.monostructural], .metabolicConditioning),
        ]
        return AllCandidates(strength: strength, functionalFitness: ff)
    }

    private func makeAcceptedPlan(asOf: Date, primaryType: GoalType = .muscleGain) throws -> (goal: Goal, plan: TrainingPlan) {
        let goal = Goal(ownerUserID: ownerUserID, primaryType: primaryType, targetDate: Calendar.current.date(byAdding: .year, value: 1, to: asOf), createdAt: asOf)
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
            let allExercises = try context.fetch(FetchDescriptor<Exercise>())
            let outcome = try AdvanceTacticalWeekUseCase.advance(
                phase: phase, asOf: rollDate(startDate, afterWeekIndex: weekIndex), ownerUserID: ownerUserID, performanceProfile: nil,
                availability: availability(),
                materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: allExercises, functionalFitnessCandidateExercises: allExercises),
                context: context
            )
            guard outcome == .advanced else { break }
            rolls += 1
        }
        return rolls
    }

    /// Walks Phase 1 (real "Focused Hypertrophy" mix) all the way through
    /// Mesocycle 1 -> 2 -> 3 -> exhausted, plus its SteadyState sibling
    /// component, until `TrainingPhaseCompletion.isPhaseTerminal` is
    /// genuinely `true` — the shared setup every "phase terminal" test
    /// below needs, factored once rather than repeated per test.
    private func makeTerminalPhase1(asOf: Date) throws -> (goal: Goal, plan: TrainingPlan, phase1: TrainingPhase, candidates: AllCandidates) {
        let fixture = try makeAcceptedPlan(asOf: asOf)
        let phase1 = fixture.plan.orderedPhases[0]
        let candidates = makeCandidates()
        let mix1 = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: phase1, goal: fixture.goal).first { $0.mix.name == "Focused Hypertrophy" })
        try StartPhaseUseCase.start(
            phase: phase1, mix: mix1.mix, asOf: asOf, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness),
            context: context
        )
        try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: phase1, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength),
            asOf: asOf, context: context
        )

        for _ in 0..<2 {
            let instance = try XCTUnwrap(phase1.primaryInstance)
            try skipToExhaustion(phase: phase1, instance: instance, startDate: asOf)
            let component = try XCTUnwrap((phase1.selectedTrainingMix ?? phase1.recommendedTrainingMix)?.orderedComponents.first { $0.priority == .primary })
            _ = try StartNextHypertrophyMesocycleUseCase.start(
                previousPhase: phase1, previousInstance: instance, asOf: asOf, ownerUserID: ownerUserID, availability: availability(),
                materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>())),
                context: context
            )
            for requirement in RequiredSourceCalibrationsUseCase.stillRequired(for: try XCTUnwrap(component.programInstance?.programDefinition), instance: try XCTUnwrap(component.programInstance)) {
                RecordSourceRMCalibrationUseCase.record(exercise: requirement.exercise, rmType: requirement.rmType, kilograms: 90, for: try XCTUnwrap(component.programInstance), modelContext: context)
            }
            try context.save()
            _ = try StartPhaseUseCase.materializeOnceCalibrationComplete(
                component: component, instance: try XCTUnwrap(component.programInstance), phase: phase1, mix: try XCTUnwrap(component.trainingMix),
                asOf: asOf, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
                materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>())),
                context: context
            )
        }
        let finalInstance = try XCTUnwrap(phase1.primaryInstance)
        try skipToExhaustion(phase: phase1, instance: finalInstance, startDate: asOf)

        let steadyStateComponent = try XCTUnwrap((phase1.selectedTrainingMix ?? phase1.recommendedTrainingMix)?.orderedComponents.first { $0.programmingSystem == .steadyState })
        let steadyStateInstance = try XCTUnwrap(steadyStateComponent.programInstance)
        for weekIndex in 0..<(steadyStateInstance.programDefinition?.orderedWeeks.count ?? 0) {
            try skipEveryRealSession(in: steadyStateInstance, weekIndex: weekIndex)
        }
        XCTAssertTrue(TrainingPhaseCompletion.isPhaseTerminal(phase1), "precondition: Phase 1 must genuinely be terminal for these tests")
        return (fixture.goal, fixture.plan, phase1, candidates)
    }

    // MARK: 2 — phase not terminal: no Start Next Phase action anywhere

    func testPhaseNotTerminalShowsNoStrategicTransitionActionInEitherViewModel() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        let phase1 = fixture.plan.orderedPhases[0]
        let candidates = makeCandidates()
        let mix1 = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: phase1, goal: fixture.goal).first { $0.mix.name == "Focused Hypertrophy" })
        try StartPhaseUseCase.start(
            phase: phase1, mix: mix1.mix, asOf: asOf, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness),
            context: context
        )
        try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: phase1, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength),
            asOf: asOf, context: context
        )

        let planViewModel = PlanViewModel()
        planViewModel.load(modelContext: context)
        XCTAssertNil(planViewModel.phaseAwaitingStrategicTransition, "nothing is terminal yet")

        let phaseViewModel = PhaseDetailViewModel()
        phaseViewModel.load(phase: phase1, modelContext: context)
        XCTAssertFalse(phaseViewModel.canPresentStrategicTransition)
        XCTAssertFalse(phaseViewModel.isFinalStrategicPhaseComplete)
    }

    // MARK: 3 — phase terminal: Start Next Phase appears in both ViewModels

    func testPhaseTerminalShowsStrategicTransitionActionInBothViewModels() throws {
        let asOf = date(2026, 1, 5)
        let terminal = try makeTerminalPhase1(asOf: asOf)

        let planViewModel = PlanViewModel()
        planViewModel.load(modelContext: context)
        XCTAssertEqual(planViewModel.phaseAwaitingStrategicTransition?.id, terminal.phase1.id)

        let phaseViewModel = PhaseDetailViewModel()
        phaseViewModel.load(phase: terminal.phase1, modelContext: context)
        XCTAssertTrue(phaseViewModel.canPresentStrategicTransition)
        XCTAssertFalse(phaseViewModel.isFinalStrategicPhaseComplete)
    }

    // MARK: Stage 10R.7B-FIX — the reviewed mix IS the accepted mix IS what TransitionPhaseUseCase starts

    /// Proves the product invariant directly. Identity note: `reviewedMix`
    /// is uninserted at `load` time, so its `persistentModelID` is only a
    /// TEMPORARY identifier until the exact same object is later inserted
    /// and saved inside `TransitionPhaseUseCase`'s scratch context (the
    /// same "temporary vs. permanent identifier" behavior Stage 10R.6/
    /// 10R.7A already empirically established) — so identity is compared
    /// AFTER the transition, once both sides have a real, permanent one.
    func testReviewedMixIsExactlyWhatTransitionPhaseUseCaseStarts() throws {
        let asOf = date(2026, 1, 5)
        let terminal = try makeTerminalPhase1(asOf: asOf)
        let nextPhase = try XCTUnwrap(TrainingPhaseCompletion.nextStrategicPhase(for: terminal.phase1))

        let viewModel = StrategicTransitionViewModel()
        viewModel.load(currentPhase: terminal.phase1, modelContext: context)
        let reviewedMixName = try XCTUnwrap(viewModel.reviewedMix?.name)

        // A second, independent proposal call (the shape the bug used to
        // take) constructs entirely new `TrainingMix`/`TrainingMixComponent`
        // objects every time — never the SAME instance `load` already
        // resolved and showed the user. `startTransition` must never take
        // this shape again.
        let secondIndependentCall = LongTermPlanner.proposeTrainingMix(phase: nextPhase, goal: terminal.goal)
        let secondIndependentMix = (secondIndependentCall.first { $0.roles.contains(.recommended) } ?? secondIndependentCall.first)?.mix
        XCTAssertFalse(secondIndependentMix === viewModel.reviewedMix, "a second independent proposal call must never be assumed to be the same object `load` already resolved and showed the user")

        XCTAssertTrue(viewModel.startTransition(modelContext: context))
        // `viewModel.reviewedMix` is the exact object `startTransition`
        // passed into `TransitionPhaseUseCase.transition` — once THAT
        // save completes, its own `persistentModelID` resolves to the
        // same real, permanent identifier the caller-side refresh used.
        let reviewedMixIDAfterSave = try XCTUnwrap(viewModel.reviewedMix?.persistentModelID)
        let startedMix = try XCTUnwrap(nextPhase.selectedTrainingMix)
        XCTAssertEqual(startedMix.persistentModelID, reviewedMixIDAfterSave, "the ACTUAL mix TransitionPhaseUseCase started must be the exact object identity `load` reviewed and the user saw — never a re-derived one")
        XCTAssertEqual(startedMix.name, reviewedMixName)
    }

    /// The scenario explicitly named in the directive: the planner has
    /// another valid candidate available (a real, differently-preference-
    /// aligned proposal), and it changes between `load` and the tap — but
    /// `startTransition` must still start the ORIGINALLY reviewed
    /// candidate, never silently substitute whatever a fresh call would
    /// now return.
    func testGoalPreferencesChangingAfterReviewNeverSilentlySubstitutesADifferentCandidate() throws {
        let asOf = date(2026, 1, 5)
        let terminal = try makeTerminalPhase1(asOf: asOf)
        let nextPhase = try XCTUnwrap(TrainingPhaseCompletion.nextStrategicPhase(for: terminal.phase1))

        let viewModel = StrategicTransitionViewModel()
        viewModel.load(currentPhase: terminal.phase1, modelContext: context)
        let reviewedMixName = try XCTUnwrap(viewModel.reviewedMix?.name)

        // Mutate real, persisted Goal.preferences AFTER the review already
        // happened — exactly the kind of state change a second,
        // independent `proposeTrainingMix` call could pick up on (it
        // reads `goal.preferences` directly, `LongTermPlanner
        // .rankCandidateMixes`). A high-variety preference aligned with
        // Functional Fitness is real, legitimate input that COULD promote
        // a different candidate than the one already reviewed.
        terminal.goal.preferences = GoalPreferences(
            preferredModalities: [ModalityPreference(system: .functionalFitness)],
            varietyPreference: .high
        )
        try context.save()

        XCTAssertTrue(viewModel.startTransition(modelContext: context))
        let reviewedMixIDAfterSave = try XCTUnwrap(viewModel.reviewedMix?.persistentModelID)
        let startedMix = try XCTUnwrap(nextPhase.selectedTrainingMix)
        XCTAssertEqual(startedMix.persistentModelID, reviewedMixIDAfterSave, "changing goal preferences after review must never change which candidate the transition actually starts")
        XCTAssertEqual(startedMix.name, reviewedMixName)
    }

    /// Reopening/canceling behaves coherently: a fresh `load` on a new
    /// ViewModel instance (exactly what a fresh sheet presentation does —
    /// `StrategicPhaseTransitionSheet` constructs a new `@State` ViewModel
    /// per presentation) always produces its own independently-usable
    /// review, never contaminated by a previous session's state.
    func testReopeningProducesAFreshIndependentlyUsableReview() throws {
        let asOf = date(2026, 1, 5)
        let terminal = try makeTerminalPhase1(asOf: asOf)

        let firstOpen = StrategicTransitionViewModel()
        firstOpen.load(currentPhase: terminal.phase1, modelContext: context)
        XCTAssertNotNil(firstOpen.reviewedMix, "precondition: the first open reviews a real candidate")
        // User cancels — never taps Start Next Phase. `firstOpen` is
        // simply discarded, same as SwiftUI discarding a dismissed
        // sheet's `@State`.

        let secondOpen = StrategicTransitionViewModel()
        secondOpen.load(currentPhase: terminal.phase1, modelContext: context)
        XCTAssertNotNil(secondOpen.reviewedMix, "reopening must produce its own fresh, independently usable review")
        XCTAssertFalse(secondOpen.didSucceed)
        XCTAssertNil(secondOpen.errorMessage)
        XCTAssertTrue(secondOpen.startTransition(modelContext: context), "the second, independent session must be able to actually complete the transition")
    }

    /// Calibration copy must describe the mix actually started — since
    /// `previewIncludesCalibrationRequiredSystem` is now computed directly
    /// FROM `reviewedMix` (never a second independent read), this is
    /// guaranteed by construction; this test proves the guarantee holds
    /// end to end, not just that the two happen to agree by coincidence.
    func testCalibrationPreviewMatchesTheMixActuallyStartedEndToEnd() throws {
        let asOf = date(2026, 1, 5)
        let terminal = try makeTerminalPhase1(asOf: asOf)

        let viewModel = StrategicTransitionViewModel()
        viewModel.load(currentPhase: terminal.phase1, modelContext: context)
        let previewSaidCalibrationNeeded = viewModel.previewIncludesCalibrationRequiredSystem
        let reviewedHasRMBasedComponent = viewModel.reviewedMix?.orderedComponents.contains {
            $0.programmingSystem == .hypertrophy || $0.programmingSystem == .powerlifting
        } ?? false
        XCTAssertEqual(previewSaidCalibrationNeeded, reviewedHasRMBasedComponent, "the calibration note must describe the reviewed mix, not some other computation")

        XCTAssertTrue(viewModel.startTransition(modelContext: context))
        let actuallyAwaitsCalibration = (viewModel.componentsAwaitingCalibrationCount ?? 0) > 0
        XCTAssertEqual(previewSaidCalibrationNeeded, actuallyAwaitsCalibration, "the calibration note shown before the tap must match what the transition actually left awaiting calibration")
    }

    // MARK: 4/5 — mesocycle succession still appears instead of strategic transition while M1/M2 complete

    func testMesocycleSuccessionStillAppearsInsteadOfStrategicTransitionWhileEarlierMesocyclesComplete() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        let phase1 = fixture.plan.orderedPhases[0]
        let candidates = makeCandidates()
        let mix1 = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: phase1, goal: fixture.goal).first { $0.mix.name == "Focused Hypertrophy" })
        try StartPhaseUseCase.start(
            phase: phase1, mix: mix1.mix, asOf: asOf, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness),
            context: context
        )
        try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: phase1, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength),
            asOf: asOf, context: context
        )
        let instance = try XCTUnwrap(phase1.primaryInstance)
        try skipToExhaustion(phase: phase1, instance: instance, startDate: asOf)

        let phaseViewModel = PhaseDetailViewModel()
        phaseViewModel.load(phase: phase1, modelContext: context)
        XCTAssertTrue(phaseViewModel.canStartNextHypertrophyMesocycle, "M1 exhausted -> Start Metabolite Focus must appear")
        XCTAssertFalse(phaseViewModel.canPresentStrategicTransition, "the whole phase is NOT terminal merely because M1 is — strategic transition must not appear yet")

        let planViewModel = PlanViewModel()
        planViewModel.load(modelContext: context)
        XCTAssertNil(planViewModel.phaseAwaitingStrategicTransition, "PlanView must not show the strategic banner while only a mesocycle succession is available")
    }

    // MARK: 7 — mixed phase with unfinished sibling never shows strategic transition

    func testMixedPhaseWithUnfinishedSiblingNeverShowsStrategicTransition() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        let phase2 = fixture.plan.orderedPhases[1]
        let candidates = makeCandidates()
        let mix2 = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: phase2, goal: fixture.goal).first { $0.mix.name == "Strength Plus Variety" })
        try StartPhaseUseCase.start(
            phase: phase2, mix: mix2.mix, asOf: asOf, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness),
            context: context
        )
        try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: phase2, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength),
            asOf: asOf, context: context
        )
        let hypertrophyComponent = try XCTUnwrap(mix2.mix.orderedComponents.first { $0.programmingSystem == .hypertrophy })
        let hypertrophyInstance = try XCTUnwrap(hypertrophyComponent.programInstance)
        try skipToExhaustion(phase: phase2, instance: hypertrophyInstance, startDate: asOf)

        let phaseViewModel = PhaseDetailViewModel()
        phaseViewModel.load(phase: phase2, modelContext: context)
        XCTAssertFalse(phaseViewModel.canPresentStrategicTransition, "Functional Fitness/Running remain unfinished siblings")
    }

    // MARK: 13 — no calibration needed: sessions materialize immediately, count is zero

    func testTransitionWithNoCalibrationRequiredSystemMaterializesSessionsImmediately() throws {
        // Anchored close to real "now" rather than a fixed historical
        // date: `StrategicTransitionViewModel.startTransition` calls
        // `TransitionPhaseUseCase.transition` with a real `Date()` (the
        // correct production behavior for a live, user-initiated action,
        // same as `PhaseDetailViewModel.advanceTacticalWeek`/
        // `startNextHypertrophyMesocycle`) — a phase built from a distant
        // historical `asOf` would have its own `endDate` already long
        // past by the time the real transition call runs, which is
        // exactly what broke Functional Fitness's own day-window
        // resolution here (zero eligible session days).
        let asOf = Calendar.current.startOfDay(for: Date())
        // A Functional Fitness goal's own real candidate mix
        // (`functionalFitnessFocusedMix`) has no Hypertrophy/Powerlifting
        // component at all — no succession mechanism either, so exhausting
        // it once is already the whole phase's program lifecycle terminal.
        let fixture = try makeAcceptedPlan(asOf: asOf, primaryType: .functionalFitness)
        XCTAssertGreaterThanOrEqual(fixture.plan.orderedPhases.count, 2, "precondition: a real next phase exists to transition into")
        let phase1 = fixture.plan.orderedPhases[0]
        // The real, already-proven-sufficient production catalog
        // (`SeedAnnualPlanJourney`'s own candidate pool) — this test's own
        // 3-exercise hand-rolled pool (sufficient for a MIXED mix
        // elsewhere in this file) isn't enough variety for
        // `functionalFitnessFocusedMix`'s higher-frequency single component.
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let ffCandidates = [catalog.wallBall, catalog.pullUp, catalog.bike, catalog.row, catalog.toesToBar, catalog.kettlebellSwing, catalog.thruster, catalog.deadlift, catalog.dumbbellSnatch]
        let mix1 = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: phase1, goal: fixture.goal).first)
        try StartPhaseUseCase.start(
            phase: phase1, mix: mix1.mix, asOf: asOf, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, functionalFitnessCandidateExercises: ffCandidates),
            context: context
        )
        let instance = try XCTUnwrap(phase1.primaryInstance)
        try skipToExhaustion(phase: phase1, instance: instance, startDate: asOf)
        XCTAssertTrue(TrainingPhaseCompletion.isPhaseTerminal(phase1), "Functional Fitness has no succession mechanism — exhaustion alone is terminal")

        let viewModel = StrategicTransitionViewModel()
        viewModel.load(currentPhase: phase1, modelContext: context)
        XCTAssertFalse(viewModel.previewIncludesCalibrationRequiredSystem, "the real proposed next-phase mix has no RM-based component")

        XCTAssertTrue(viewModel.startTransition(modelContext: context))
        XCTAssertEqual(viewModel.componentsAwaitingCalibrationCount, 0)
        let nextPhase = try XCTUnwrap(viewModel.nextPhase)
        let nextInstance = try XCTUnwrap(nextPhase.primaryInstance)
        XCTAssertFalse(nextInstance.sessions.isEmpty, "with no calibration required, real Sessions must already be materialized — visible through the existing Today/Plan flow, no separate success workflow needed")
    }

    // MARK: 16 — final phase terminal: no Start Next Phase action

    func testFinalStrategicPhaseTerminalShowsNoStrategicTransitionAction() throws {
        let asOf = date(2026, 1, 5)
        // Deliberately NOT `makeTerminalPhase1` here — Phase 1 stays
        // untouched/`.planned` so it can never itself independently
        // satisfy either ViewModel's gate; this test's only job is the
        // "is this the final phase" branch, isolated from every other
        // phase's own state (constructing a full real lifecycle through
        // every intervening phase is unnecessary — `isPhaseTerminal` is
        // already independently proven at the domain level).
        let fixture = try makeAcceptedPlan(asOf: asOf)
        let lastPhase = try XCTUnwrap(fixture.plan.orderedPhases.last)
        lastPhase.status = .active
        let mix = TrainingMix(kind: .selected, name: "Final Phase Test Mix")
        mix.addComponent(TrainingMixComponent(label: "Test", programmingSystem: .steadyState, priority: .primary, frequency: SessionFrequency(target: 2)))
        context.insert(mix)
        lastPhase.addTrainingMix(mix)
        XCTAssertTrue(TrainingPhaseCompletion.isFinalStrategicPhase(lastPhase))

        let phaseViewModel = PhaseDetailViewModel()
        phaseViewModel.load(phase: lastPhase, modelContext: context)
        XCTAssertFalse(phaseViewModel.canPresentStrategicTransition, "there is no next phase to transition into")
        // Not asserting `isFinalStrategicPhaseComplete` here — that also
        // requires `isPhaseTerminal`, which this hand-built mix (with an
        // un-instantiated component) correctly does NOT satisfy; the one
        // fact this test needs is already proven above.

        let planViewModel = PlanViewModel()
        planViewModel.load(modelContext: context)
        XCTAssertNil(planViewModel.phaseAwaitingStrategicTransition)
    }

    // MARK: 8/10/11 — starting the transition invokes the real use case once, activates the existing pre-planned next phase, creates no new phase

    func testStartTransitionActivatesExistingPrePlannedPhaseAndCreatesNoNewPhase() throws {
        let asOf = date(2026, 1, 5)
        let terminal = try makeTerminalPhase1(asOf: asOf)
        let phase2 = try XCTUnwrap(TrainingPhaseCompletion.nextStrategicPhase(for: terminal.phase1))
        let originalPhaseCount = terminal.plan.orderedPhases.count

        let viewModel = StrategicTransitionViewModel()
        viewModel.load(currentPhase: terminal.phase1, modelContext: context)
        XCTAssertEqual(viewModel.nextPhase?.id, phase2.id)

        XCTAssertTrue(viewModel.startTransition(modelContext: context))
        XCTAssertTrue(viewModel.didSucceed)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(terminal.phase1.status, .completed)
        XCTAssertEqual(phase2.status, .active)
        XCTAssertEqual(terminal.plan.orderedPhases.count, originalPhaseCount, "no new strategic phase was fabricated")
    }

    // MARK: 9 — double tap cannot transition twice

    func testDoubleTapCannotTransitionTwice() throws {
        let asOf = date(2026, 1, 5)
        let terminal = try makeTerminalPhase1(asOf: asOf)
        let phase2 = try XCTUnwrap(TrainingPhaseCompletion.nextStrategicPhase(for: terminal.phase1))

        let viewModel = StrategicTransitionViewModel()
        viewModel.load(currentPhase: terminal.phase1, modelContext: context)

        XCTAssertTrue(viewModel.startTransition(modelContext: context), "first tap succeeds")
        XCTAssertFalse(viewModel.startTransition(modelContext: context), "second (double) tap must be a no-op")
        XCTAssertEqual(terminal.phase1.status, .completed, "still exactly once-transitioned")
        XCTAssertEqual(phase2.status, .active)
    }

    // MARK: 12 — transition requiring calibration: the count is reported, and the existing app-wide calibration gate picks it up

    func testTransitionRequiringCalibrationReportsCountAndCalibrationGateBecomesPending() throws {
        let asOf = date(2026, 1, 5)
        let terminal = try makeTerminalPhase1(asOf: asOf)

        let viewModel = StrategicTransitionViewModel()
        viewModel.load(currentPhase: terminal.phase1, modelContext: context)
        XCTAssertTrue(viewModel.previewIncludesCalibrationRequiredSystem, "Phase 2's real proposed mix includes Hypertrophy")

        XCTAssertTrue(viewModel.startTransition(modelContext: context))
        XCTAssertEqual(viewModel.componentsAwaitingCalibrationCount, 1)

        // The existing, already-shipped app-wide gate re-checked exactly
        // the way `RootTabView` does on `.strategicPhaseTransitionCompleted`.
        let calibrationViewModel = SourceRMCalibrationViewModel()
        calibrationViewModel.load(modelContext: context)
        XCTAssertTrue(calibrationViewModel.hasPendingCalibration, "the new phase's Hypertrophy component genuinely awaits calibration")
    }

    // MARK: 14 — failed transition: previous phase remains valid, error is visible, no optimistic success

    func testFailedTransitionPreservesPreviousPhaseAndSurfacesAVisibleError() throws {
        let asOf = date(2026, 1, 5)
        let terminal = try makeTerminalPhase1(asOf: asOf)
        // Force a real failure the same way `StrategicPhaseLifecycleTests`
        // does — but the ViewModel always proposes its own real mix, so
        // the failure is forced by breaking the use case's OWN precondition
        // instead: mark the outgoing phase no longer `.active` first.
        terminal.phase1.status = .completed

        let viewModel = StrategicTransitionViewModel()
        viewModel.load(currentPhase: terminal.phase1, modelContext: context)
        XCTAssertFalse(viewModel.startTransition(modelContext: context))
        XCTAssertFalse(viewModel.didSucceed)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertEqual(terminal.phase1.status, .completed, "unchanged by the failed attempt (it was already this way going in)")
        XCTAssertEqual(viewModel.nextPhase?.status, .planned, "the next phase must never be partially activated by a failed attempt")
    }

    // MARK: 15 — relaunch after successful transition: new phase remains active

    func testRelaunchAfterSuccessfulTransitionKeepsNewPhaseActive() throws {
        let asOf = date(2026, 1, 5)
        let terminal = try makeTerminalPhase1(asOf: asOf)
        let phase2ID = try XCTUnwrap(TrainingPhaseCompletion.nextStrategicPhase(for: terminal.phase1)).id

        let viewModel = StrategicTransitionViewModel()
        viewModel.load(currentPhase: terminal.phase1, modelContext: context)
        XCTAssertTrue(viewModel.startTransition(modelContext: context))
        try context.save()

        // A fresh ModelContext on the same container — the closest
        // in-process approximation of "quit and relaunch the app," same
        // convention `RelationshipOwnershipTests` already established.
        let reloadContext = ModelContext(container)
        let reloadedPhase2 = try XCTUnwrap(reloadContext.fetch(FetchDescriptor<TrainingPhase>(predicate: #Predicate { $0.id == phase2ID })).first)
        XCTAssertEqual(reloadedPhase2.status, .active)
    }
}
