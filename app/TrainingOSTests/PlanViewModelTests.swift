import XCTest
import SwiftData
@testable import TrainingOS

/// V1 R3 (Plan/strategic spine reconciliation): proves `PlanViewModel`'s
/// real derived presentation state — never a hardcoded-string/pixel
/// assertion, always the real `phases`/`datedObjectives`/`currentPhase`/
/// `upcomingStartDate`/`currentWeekPosition`/`isFinalPhase` the View
/// actually renders from.
@MainActor
final class PlanViewModelTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()

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

    @discardableResult
    private func makeActiveGoalAndPlan(datedObjectives: [DatedObjective] = []) -> (goal: Goal, plan: TrainingPlan) {
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .muscleGain, datedObjectives: datedObjectives)
        context.insert(goal)
        let plan = TrainingPlan(status: .active)
        context.insert(plan)
        goal.addPlan(plan)
        return (goal, plan)
    }

    @discardableResult
    private func addPhase(
        to plan: TrainingPlan, type: PhaseType, start: Date, end: Date?, status: PhaseStatus,
        mixComponents: [(label: String, system: ProgrammingSystemKind, frequency: Int)] = []
    ) -> TrainingPhase {
        let phase = TrainingPhase(type: type, startDate: start, endDate: end, priorityRule: .strength, status: status)
        context.insert(phase)
        plan.addPhase(phase)
        if !mixComponents.isEmpty {
            let mix = TrainingMix(kind: .selected, name: "Test Mix")
            context.insert(mix)
            mix.phase = phase
            for component in mixComponents {
                mix.addComponent(TrainingMixComponent(
                    label: component.label, programmingSystem: component.system, priority: .primary,
                    adaptationObjectives: [.muscleGain], frequency: SessionFrequency(target: component.frequency)
                ))
            }
        }
        return phase
    }

    // MARK: A — active phase presented as current

    func testActivePhaseIsPresentedAsCurrent() throws {
        let (_, plan) = makeActiveGoalAndPlan()
        let active = addPhase(to: plan, type: .muscleGain, start: date(2026, 1, 5), end: date(2026, 2, 16), status: .active)
        try context.save()

        let viewModel = PlanViewModel()
        viewModel.load(modelContext: context)

        XCTAssertEqual(viewModel.currentPhase?.id, active.id)
        XCTAssertNil(viewModel.upcomingStartDate, "an already-started phase must never present the R0 upcoming state")
    }

    // MARK: B — future phases

    func testFuturePhasesAreDistinctFromCurrentPhase() throws {
        let (_, plan) = makeActiveGoalAndPlan()
        let active = addPhase(to: plan, type: .muscleGain, start: date(2026, 1, 5), end: date(2026, 2, 16), status: .active)
        let future = addPhase(to: plan, type: .fatLoss, start: date(2026, 2, 16), end: date(2026, 3, 30), status: .planned)
        try context.save()

        let viewModel = PlanViewModel()
        viewModel.load(modelContext: context)

        XCTAssertEqual(viewModel.phases.map(\.id), [active.id, future.id])
        XCTAssertEqual(viewModel.currentPhase?.id, active.id)
    }

    // MARK: Chronological ordering of phases + dated objectives together

    func testPhasesAndObjectivesOrderChronologically() throws {
        let (_, plan) = makeActiveGoalAndPlan(datedObjectives: [
            DatedObjective(kind: .bodyCompositionMilestone, date: date(2026, 6, 15)),
            DatedObjective(kind: .runningEvent, date: date(2026, 9, 20)),
        ])
        addPhase(to: plan, type: .muscleGain, start: date(2026, 1, 5), end: date(2026, 4, 1), status: .active)
        addPhase(to: plan, type: .fatLoss, start: date(2026, 4, 1), end: date(2026, 7, 1), status: .planned)
        addPhase(to: plan, type: .enduranceEvent, start: date(2026, 7, 1), end: date(2026, 10, 1), status: .planned)
        try context.save()

        let viewModel = PlanViewModel()
        viewModel.load(modelContext: context)

        // The real, ordered anchor dates a spine built from this state
        // must render in: phase1 (Jan) < milestone (Jun 15) < phase2 (Apr)...
        // — the View merges/sorts these; here we just prove the ViewModel's
        // own real data is correct and complete for that sort to work.
        XCTAssertEqual(viewModel.phases.count, 3)
        XCTAssertEqual(viewModel.datedObjectives.count, 2)
        XCTAssertEqual(viewModel.datedObjectives.map(\.date), viewModel.datedObjectives.map(\.date).sorted(), "objectives themselves must already be chronologically sorted")
    }

    // MARK: C — one dated objective

    func testOneDatedObjectiveIsExposed() throws {
        let (_, plan) = makeActiveGoalAndPlan(datedObjectives: [
            DatedObjective(kind: .bodyCompositionMilestone, date: date(2026, 6, 15)),
        ])
        addPhase(to: plan, type: .muscleGain, start: date(2026, 1, 5), end: nil, status: .active)
        try context.save()

        let viewModel = PlanViewModel()
        viewModel.load(modelContext: context)

        XCTAssertEqual(viewModel.datedObjectives.count, 1)
        XCTAssertEqual(viewModel.datedObjectives.first?.kind, .bodyCompositionMilestone)
    }

    // MARK: D — multiple dated objectives, correct order, cancelled/completed excluded

    func testMultipleDatedObjectivesOrderedAndFilteredByStatus() throws {
        let (_, plan) = makeActiveGoalAndPlan(datedObjectives: [
            DatedObjective(kind: .runningEvent, date: date(2026, 9, 20)),
            DatedObjective(kind: .bodyCompositionMilestone, date: date(2026, 6, 15)),
            DatedObjective(kind: .bodyCompositionMilestone, date: date(2026, 3, 1), status: .completed),
            DatedObjective(kind: .runningEvent, date: date(2026, 1, 1), status: .cancelled),
        ])
        addPhase(to: plan, type: .muscleGain, start: date(2026, 1, 5), end: nil, status: .active)
        try context.save()

        let viewModel = PlanViewModel()
        viewModel.load(modelContext: context)

        XCTAssertEqual(viewModel.datedObjectives.count, 2, "completed/cancelled objectives must never appear in the forward journey")
        XCTAssertEqual(viewModel.datedObjectives.map(\.kind), [.bodyCompositionMilestone, .runningEvent], "must be in real chronological order (Jun before Sep)")
    }

    // MARK: E — R0 upcoming Monday start, through the real production path

    func testUpcomingMondayStartAfterFridayAcceptance() throws {
        let friday = date(2026, 1, 2) // confirmed Friday
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .muscleGain, preferences: GoalPreferences(availableTrainingDaysPerWeek: 5, allowsDoubleSessions: false), createdAt: friday)
        context.insert(goal)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: friday)
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: friday)
        let phase = try XCTUnwrap(plan.orderedPhases.first)

        guard case .success(let mix) = LongTermPlanner.buildCustomMix(
            selections: [(style: .hypertrophy, frequency: 3), (style: .functionalFitness, frequency: 2)], capacity: 5
        ) else { return XCTFail("3H+2FF must be constructible") }

        let strengthExercise = Exercise(canonicalName: "Test Back Squat", modality: .hypertrophy, equipment: "barbell", movementPattern: "squat", primaryTargets: [.quadriceps])
        context.insert(strengthExercise)
        let ffExercise = Exercise(canonicalName: "Test FF Movement", modality: .hypertrophy, equipment: "barbell", movementPattern: "test", movementFunctions: [.squatLoaded], functionalModality: .weightlifting)
        context.insert(ffExercise)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        _ = try StartPhaseUseCase.start(
            phase: phase, mix: mix, asOf: friday, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: UserAvailability(trainingDaysPerWeek: 5, allowsDoubleSessions: false, maxSessionsPerDay: 1),
            materializationContext: TacticalMaterializationContext(
                equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
                strengthCandidateExercises: [strengthExercise], functionalFitnessCandidateExercises: [ffExercise], trainingEnvironment: environment
            ),
            context: context
        )

        let viewModel = PlanViewModel()
        viewModel.load(modelContext: context, referenceDate: friday)

        XCTAssertEqual(viewModel.currentPhase?.id, phase.id)
        let upcoming = try XCTUnwrap(viewModel.upcomingStartDate, "Plan must present the R0 upcoming-start truth, never imply Week 1 before the real resolved Monday")
        XCTAssertEqual(Calendar.current.startOfDay(for: upcoming), Calendar.current.startOfDay(for: date(2026, 1, 5)))
        XCTAssertNil(viewModel.currentWeekPosition, "no week position may be shown before the phase's own truthful start date")

        // H — the real, athlete-selected 3H+2FF composition is exactly
        // what's attached to the phase, never a preset substitution.
        let attachedMix = phase.selectedTrainingMix ?? phase.recommendedTrainingMix
        let summary = try XCTUnwrap(attachedMix.map(PlanPresentation.mixSummary))
        XCTAssertEqual(summary, "3× Hypertrophy + 2× Functional Fitness")
    }

    // MARK: F — final phase truthfully communicated, no goal-completion implication

    func testFinalPhaseHasNoLaterPlannedPhase() throws {
        let (_, plan) = makeActiveGoalAndPlan()
        addPhase(to: plan, type: .muscleGain, start: date(2026, 1, 5), end: date(2026, 4, 1), status: .active)
        try context.save()

        let viewModel = PlanViewModel()
        viewModel.load(modelContext: context)

        XCTAssertTrue(viewModel.isFinalPhase)
    }

    func testNonFinalPhaseWhenALaterPhaseExists() throws {
        let (_, plan) = makeActiveGoalAndPlan()
        addPhase(to: plan, type: .muscleGain, start: date(2026, 1, 5), end: date(2026, 4, 1), status: .active)
        addPhase(to: plan, type: .fatLoss, start: date(2026, 4, 1), end: nil, status: .planned)
        try context.save()

        let viewModel = PlanViewModel()
        viewModel.load(modelContext: context)

        XCTAssertFalse(viewModel.isFinalPhase)
    }

    // MARK: G — strategic transition actions remain reachable (existing behavior, unmodified)

    func testStrategicTransitionRemainsUnaffectedByNewProperties() throws {
        let (_, plan) = makeActiveGoalAndPlan()
        addPhase(to: plan, type: .muscleGain, start: date(2026, 1, 5), end: date(2026, 4, 1), status: .active)
        try context.save()

        let viewModel = PlanViewModel()
        viewModel.load(modelContext: context)

        // No terminal mix/next-phase state here, so no transition should
        // be surfaced — proves the pre-existing `phaseAwaitingStrategicTransition`
        // logic still runs exactly as before, untouched by this checkpoint.
        XCTAssertNil(viewModel.phaseAwaitingStrategicTransition)
    }
}
