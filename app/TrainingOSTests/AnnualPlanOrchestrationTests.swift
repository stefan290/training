import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 7 (Tactical Planning Orchestration), Slice 4: Annual Plan /
/// Current Phase presentation — every test drives the real
/// `SeedAnnualPlanJourney` fixture (itself built entirely through
/// `AcceptStrategicPlanUseCase`/`StartPhaseUseCase`/`TransitionPhaseUseCase`,
/// never hand-constructed rows) through the real `PlanViewModel`/
/// `PhaseDetailViewModel`, never a UI-only fake.
@MainActor
final class AnnualPlanOrchestrationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func makeJourney() throws -> SeedAnnualPlanJourney.Result {
        let user = User(displayName: "Test User")
        context.insert(user)
        let profile = PerformanceProfile()
        context.insert(profile)
        user.attachPerformanceProfile(profile)
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        return try SeedAnnualPlanJourney.seed(user: user, performanceProfile: profile, catalog: catalog, context: context)
    }

    // MARK: A — phases order correctly

    func testAnnualPlanOrdersPhasesCorrectly() throws {
        let journey = try makeJourney()
        let viewModel = PlanViewModel()
        viewModel.load(modelContext: context)

        XCTAssertEqual(viewModel.phases.map(\.id), journey.plan.orderedPhases.map(\.id))
        XCTAssertEqual(viewModel.phases[0].id, journey.completedPhase.id)
        XCTAssertEqual(viewModel.phases[1].id, journey.activePhase.id)
        XCTAssertEqual(viewModel.phases[2].id, journey.upcomingPhases[0].id)
    }

    // MARK: B — Completed/Active/Upcoming maps from real phase state

    func testStatusLabelsMapFromRealPhaseState() throws {
        let journey = try makeJourney()
        XCTAssertEqual(journey.completedPhase.status, .completed)
        XCTAssertEqual(journey.activePhase.status, .active)
        XCTAssertEqual(journey.upcomingPhases[0].status, .planned)

        XCTAssertEqual(PlanPresentation.annualPlanStatusLabel(journey.completedPhase.status), "Completed")
        XCTAssertEqual(PlanPresentation.annualPlanStatusLabel(journey.activePhase.status), "Active")
        XCTAssertEqual(PlanPresentation.annualPlanStatusLabel(journey.upcomingPhases[0].status), "Upcoming")
    }

    // MARK: C — active phase identifiable without UI heuristics

    func testActivePhaseIsIdentifiableWithoutUIHeuristics() throws {
        let journey = try makeJourney()
        // The ONLY signal is `status` — never array position, never a
        // string comparison on a display label.
        let activeByStatus = journey.plan.orderedPhases.filter { $0.status == .active }
        XCTAssertEqual(activeByStatus.count, 1)
        XCTAssertEqual(activeByStatus.first?.id, journey.activePhase.id)
    }

    // MARK: D — Current Phase shows every accepted component

    func testCurrentPhaseShowsEveryAcceptedComponent() throws {
        let journey = try makeJourney()
        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: journey.activePhase, modelContext: context)

        XCTAssertEqual(viewModel.activeComponents.count, 3, "Strength + Functional Fitness + Running — none silently dropped")
        XCTAssertEqual(Set(viewModel.activeComponents.compactMap(\.programmingSystem)), [.hypertrophy, .functionalFitness, .steadyState])
    }

    // MARK: E — recommended vs selected remains distinguishable

    func testRecommendedVsSelectedRemainsDistinguishable() throws {
        let journey = try makeJourney()
        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: journey.activePhase, modelContext: context)

        let recommended = try XCTUnwrap(viewModel.recommendedMix)
        let selected = try XCTUnwrap(viewModel.selectedMix)
        XCTAssertNotEqual(recommended.id, selected.id)
        XCTAssertEqual(recommended.kind, .recommended)
        XCTAssertEqual(selected.kind, .selected)
        XCTAssertNotEqual(PlanPresentation.mixSummary(recommended), PlanPresentation.mixSummary(selected))
        XCTAssertFalse(PlanPresentation.mixSummary(selected).isEmpty)
        // The selected (goal-compatible) plan is never framed as an error
        // — nothing in the presentation layer marks it invalid/rejected.
        XCTAssertTrue(selected.orderedComponents.allSatisfy { $0.programInstance != nil })
    }

    // MARK: F — multiple ProgramInstances presented independently

    func testMultipleProgramInstancesArePresentedIndependently() throws {
        let journey = try makeJourney()
        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: journey.activePhase, modelContext: context)

        let instanceIDs = viewModel.activeComponents.compactMap { $0.programInstance?.id }
        XCTAssertEqual(instanceIDs.count, 3)
        XCTAssertEqual(Set(instanceIDs).count, 3, "each component's own instance must be independently resolvable, never sharing one")
    }

    // MARK: G — mixed modality never collapsed into one program

    func testMixedModalityIsNotCollapsedIntoOneProgram() throws {
        let journey = try makeJourney()
        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: journey.activePhase, modelContext: context)

        let definitionIDs = viewModel.activeComponents.compactMap { $0.programInstance?.programDefinition?.id }
        XCTAssertEqual(Set(definitionIDs).count, 3, "each component must keep its own ProgramDefinition, never merged into one")
        let systems = viewModel.activeComponents.compactMap { $0.programInstance?.programDefinition?.programmingSystem }
        XCTAssertEqual(Set(systems).count, 3)
    }

    // MARK: H — future phase inspection causes no materialization

    func testFuturePhaseInspectionCausesNoMaterialization() throws {
        let journey = try makeJourney()
        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: journey.upcomingPhases[0], modelContext: context)

        XCTAssertTrue(journey.upcomingPhases[0].programInstances.isEmpty)
        XCTAssertNil(viewModel.selectedMix)
        XCTAssertNil(viewModel.recommendedMix)
        XCTAssertTrue(viewModel.activeComponents.isEmpty)
        XCTAssertEqual(journey.upcomingPhases[0].status, .planned, "merely loading detail must never advance a phase's status")
    }

    // MARK: I — opening Annual Plan causes no writes

    func testOpeningAnnualPlanCausesNoWrites() throws {
        let journey = try makeJourney()
        let sessionCountBefore = try context.fetchCount(FetchDescriptor<Session>())
        let instanceCountBefore = try context.fetchCount(FetchDescriptor<ProgramInstance>())
        let decisionCountBefore = try context.fetchCount(FetchDescriptor<PlannerDecision>())
        let mixCountBefore = try context.fetchCount(FetchDescriptor<TrainingMix>())

        let viewModel = PlanViewModel()
        viewModel.load(modelContext: context)
        _ = viewModel.phases.map { PlanPresentation.annualPlanStatusLabel($0.status) }

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Session>()), sessionCountBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramInstance>()), instanceCountBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlannerDecision>()), decisionCountBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainingMix>()), mixCountBefore)
        _ = journey
    }

    // MARK: J — opening Current Phase causes no writes

    func testOpeningCurrentPhaseCausesNoWrites() throws {
        let journey = try makeJourney()
        let sessionCountBefore = try context.fetchCount(FetchDescriptor<Session>())
        let instanceCountBefore = try context.fetchCount(FetchDescriptor<ProgramInstance>())
        let mixCountBefore = try context.fetchCount(FetchDescriptor<TrainingMix>())

        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: journey.activePhase, modelContext: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Session>()), sessionCountBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramInstance>()), instanceCountBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainingMix>()), mixCountBefore)
    }

    // MARK: K — completed phase detail never mutates history

    func testCompletedPhaseDetailDoesNotMutateHistory() throws {
        let journey = try makeJourney()
        let instance = try XCTUnwrap(journey.completedPhase.primaryInstance)
        let setResultCountBefore = try context.fetchCount(FetchDescriptor<SetResult>())
        let sessionIDsBefore = Set(instance.sessions.map(\.id))

        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: journey.completedPhase, modelContext: context)
        _ = viewModel.activeComponents

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetResult>()), setResultCountBefore)
        XCTAssertEqual(Set(instance.sessions.map(\.id)), sessionIDsBefore)
        XCTAssertEqual(journey.completedPhase.status, .completed, "viewing history must never revert or advance status")
        XCTAssertEqual(instance.status, .completed)
    }

    // MARK: L — upcoming phase detail never creates Sessions

    func testUpcomingPhaseDetailDoesNotCreateSessions() throws {
        let journey = try makeJourney()
        let sessionCountBefore = try context.fetchCount(FetchDescriptor<Session>())

        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: journey.upcomingPhases[0], modelContext: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Session>()), sessionCountBefore)
    }

    // MARK: M — program navigation uses the real ProgramInstance

    func testProgramNavigationUsesTheRealProgramInstance() throws {
        let journey = try makeJourney()
        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: journey.activePhase, modelContext: context)

        XCTAssertFalse(viewModel.activeComponents.isEmpty)
        for component in viewModel.activeComponents {
            let instance = try XCTUnwrap(component.programInstance, "\(component.label) must resolve to a real ProgramInstance for navigation")
            let definition = try XCTUnwrap(instance.programDefinition)
            XCTAssertEqual(definition.programmingSystem, component.programmingSystem)
            // The existing Program/Week/Session preview architecture takes
            // exactly these two — proving no second parallel program-detail
            // system is needed.
            _ = ProgramDetailView(instance: instance, definition: definition)
        }
    }

    // MARK: N — no raw enum casing where a presentation mapping exists

    func testUserFacingLabelsNeverExposeRawEnumCasing() {
        for status in PhaseStatus.allCases {
            let label = PlanPresentation.annualPlanStatusLabel(status)
            XCTAssertFalse(label.isEmpty)
            XCTAssertNotEqual(label, status.rawValue)
        }
        for system in ProgrammingSystemKind.allCases {
            XCTAssertNotEqual(PlanPresentation.programmingSystemLabel(system), system.rawValue)
        }
        for type in PhaseType.allCases {
            XCTAssertNotEqual(PlanPresentation.phaseTypeLabel(type), type.rawValue)
        }
        for priority in GoalPriority.allCases {
            XCTAssertNotEqual(PlanPresentation.priorityLabel(priority), priority.rawValue)
        }
    }

    // MARK: O — a transition updates the presentation model with no special UI mutation

    func testTransitioningPhaseUpdatesThePresentationModelWithNoSpecialUIMutation() throws {
        let journey = try makeJourney()

        // The presentation layer is never told about the transition
        // directly — it only ever re-reads the domain model.
        let viewModel = PlanViewModel()
        viewModel.load(modelContext: context)

        XCTAssertEqual(viewModel.phases.first { $0.status == .active }?.id, journey.activePhase.id)
        XCTAssertEqual(viewModel.phases.first { $0.status == .completed }?.id, journey.completedPhase.id)
        XCTAssertEqual(viewModel.phases.first { $0.status == .planned }?.id, journey.upcomingPhases[0].id)

        let phaseDetailViewModel = PhaseDetailViewModel()
        phaseDetailViewModel.load(phase: journey.activePhase, modelContext: context)
        XCTAssertEqual(phaseDetailViewModel.selectedMix?.kind, .selected)
    }
}
