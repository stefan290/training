import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 7 (Tactical Planning Orchestration), Slice 4 acceptance fix:
/// proves `SeedAnnualPlanJourney`'s dates are correctly anchored relative
/// to "now" — the active phase's tactical window genuinely contains
/// today, Today/Week have real materialized Sessions to show, and the
/// app's "seed once" bootstrap guard behaves correctly — rather than the
/// prior bug (an independently-chosen transition offset that silently
/// drifted out of sync with the planner's own real 12-week phase
/// duration, leaving the "active" phase's Sessions dated weeks in the
/// future).
@MainActor
final class AnnualPlanSeedDateTests: XCTestCase {
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
        let catalog = ExerciseCatalog.makeAndInsert(context: context)
        return try SeedAnnualPlanJourney.seed(user: user, performanceProfile: profile, catalog: catalog, context: context)
    }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    // MARK: A — clean acceptance bootstrap creates the rich TrainingPlan

    func testCleanBootstrapCreatesTheRichTrainingPlan() throws {
        let journey = try makeJourney()
        XCTAssertGreaterThanOrEqual(journey.plan.orderedPhases.count, 4)
        XCTAssertGreaterThanOrEqual(journey.upcomingPhases.count, 2)
        XCTAssertNotNil(journey.activePhase.recommendedTrainingMix)
        XCTAssertNotNil(journey.activePhase.selectedTrainingMix)
        XCTAssertNotEqual(journey.activePhase.recommendedTrainingMix?.id, journey.activePhase.selectedTrainingMix?.id)
    }

    // MARK: B — exactly one phase is Active for the reference date

    func testExactlyOnePhaseIsActiveForTheReferenceDate() throws {
        let journey = try makeJourney()
        let activePhases = journey.plan.orderedPhases.filter { $0.status == .active }
        XCTAssertEqual(activePhases.count, 1)
        XCTAssertEqual(activePhases.first?.id, journey.activePhase.id)

        // The active phase's own dates genuinely contain today — not a
        // phase whose window already ended, or one that hasn't started.
        XCTAssertLessThanOrEqual(journey.activePhase.startDate, today)
        if let endDate = journey.activePhase.endDate {
            XCTAssertGreaterThan(endDate, today)
        }
    }

    // MARK: C — completed/upcoming phases correctly positioned around it

    func testCompletedAndUpcomingPhasesAreCorrectlyPositioned() throws {
        let journey = try makeJourney()
        let completedEnd = try XCTUnwrap(journey.completedPhase.endDate)
        XCTAssertLessThanOrEqual(completedEnd, today, "the completed phase must genuinely have ended by today, not merely been marked complete")
        XCTAssertEqual(completedEnd, journey.activePhase.startDate, "the active phase must pick up exactly where the completed one left off — no gap, no overlap")

        for upcoming in journey.upcomingPhases {
            XCTAssertGreaterThan(upcoming.startDate, today, "an upcoming phase must genuinely start after today")
            XCTAssertEqual(upcoming.status, .planned)
        }
    }

    // MARK: D/E — active phase gets real ProgramInstances, first tactical window materializes

    func testActivePhaseComponentsHaveRealMaterializedFirstWindows() throws {
        let journey = try makeJourney()
        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: journey.activePhase, modelContext: context)

        XCTAssertFalse(viewModel.activeComponents.isEmpty)
        for component in viewModel.activeComponents {
            let instance = try XCTUnwrap(component.programInstance)
            XCTAssertFalse(ProgramWeekGrouping.realSessions(in: instance, forWeek: 0).isEmpty, "\(component.label) must have a real materialized week 0")
        }
    }

    // MARK: F — current week contains Sessions

    func testCurrentTacticalWindowContainsSessions() throws {
        let journey = try makeJourney()
        let instance = try XCTUnwrap(journey.activePhase.primaryInstance)
        let weekSessions = ProgramWeekGrouping.realSessions(in: instance, forWeek: 0)
        XCTAssertFalse(weekSessions.isEmpty)
        for session in weekSessions {
            let date = try XCTUnwrap(session.day?.date)
            XCTAssertGreaterThanOrEqual(date, journey.activePhase.startDate)
            XCTAssertLessThan(date, Calendar.current.date(byAdding: .day, value: 7, to: journey.activePhase.startDate)!)
        }
    }

    // MARK: G — reference "today" contains at least one real Session

    func testTodayContainsAtLeastOneRealMaterializedSession() throws {
        let journey = try makeJourney()
        let allSessions = journey.activePhase.programInstances.flatMap(\.sessions)
        let todaysSessions = allSessions.filter { session in
            guard let date = session.day?.date else { return false }
            return Calendar.current.isDate(date, inSameDayAs: today)
        }
        XCTAssertFalse(todaysSessions.isEmpty, "the acceptance fixture must genuinely place at least one real Session on today's date")
    }

    // MARK: H — relaunch does not duplicate the entire acceptance graph

    func testUserExistsAfterSeedingSoARelaunchGuardWouldSkipReseeding() throws {
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<User>()), 0, "precondition: nothing seeded yet")
        _ = try makeJourney()
        // This is exactly the predicate `TrainingOSApp.init` checks
        // (`existingUserCount == 0`) before ever calling the seed
        // functions — proving it would now correctly evaluate to "skip."
        XCTAssertGreaterThan(try context.fetchCount(FetchDescriptor<User>()), 0)
    }

    // MARK: I — existing non-empty data is not destructively replaced

    func testASecondSeedInvocationNeverDeletesTheFirstRunsData() throws {
        let firstJourney = try makeJourney()
        let firstPlanID = firstJourney.plan.id
        let firstSessionIDs = Set(firstJourney.activePhase.programInstances.flatMap(\.sessions).map(\.id))

        // Even in the worst case where a caller mistakenly re-seeds
        // (the real guard in `TrainingOSApp` prevents this from ever
        // happening in production), the first run's own data must never
        // be deleted or mutated — `SeedAnnualPlanJourney` only ever adds
        // new rows via `context.insert`, never deletes/overwrites
        // anything belonging to a prior run.
        let secondUser = User(displayName: "Second Test User")
        context.insert(secondUser)
        let secondProfile = PerformanceProfile()
        context.insert(secondProfile)
        secondUser.attachPerformanceProfile(secondProfile)
        let secondCatalog = ExerciseCatalog.makeAndInsert(context: context)
        _ = try SeedAnnualPlanJourney.seed(user: secondUser, performanceProfile: secondProfile, catalog: secondCatalog, context: context)

        let survivingPlans = try context.fetch(FetchDescriptor<TrainingPlan>())
        XCTAssertTrue(survivingPlans.contains { $0.id == firstPlanID }, "the first run's own TrainingPlan must still exist")
        let survivingSessionIDs = Set(try context.fetch(FetchDescriptor<Session>()).map(\.id))
        XCTAssertTrue(firstSessionIDs.isSubset(of: survivingSessionIDs), "none of the first run's Sessions may be deleted by a later seed call")
    }

    // MARK: J — Today filtering returns the correct Sessions for the supplied date

    func testTodayViewModelFiltersCorrectlyForTheSuppliedReferenceDate() throws {
        let journey = try makeJourney()
        let viewModel = TodayViewModel()

        viewModel.load(modelContext: context, referenceDate: today)
        XCTAssertFalse(viewModel.sessions.isEmpty, "with the real reference date, Today must show the real materialized Sessions")

        let farFuture = Calendar.current.date(byAdding: .day, value: 400, to: today)!
        viewModel.load(modelContext: context, referenceDate: farFuture)
        XCTAssertTrue(viewModel.sessions.isEmpty, "a date with no materialized Day must correctly show nothing — never a stale carry-over from the previous load")
        _ = journey
    }

    // MARK: Regression — orphaned naive Days (real `AcceptScheduleProposalUseCase` behavior) must never hide a real Session

    /// A mixed-modality phase's 3 components each materialize a naive
    /// day-0 Session, but `maxSessionsPerDay: 1` forces the scheduler to
    /// spread most of them onto other days — leaving 2 empty, orphaned
    /// `Day` rows behind on today's own date alongside the 1 real `Day`
    /// that actually kept its Session. `TodayViewModel` must aggregate
    /// every matching `Day`, never just whichever one a `.first(where:)`
    /// happens to find.
    func testTodayAggregatesSessionsAcrossMultipleDayRowsSharingTheSameDate() throws {
        let journey = try makeJourney()
        let allDaysForToday = try context.fetch(FetchDescriptor<Day>()).filter {
            Calendar.current.isDate($0.date, inSameDayAs: today)
        }
        XCTAssertGreaterThan(allDaysForToday.count, 1, "sanity check: this scenario only reproduces the bug when multiple Day rows genuinely share today's date")
        XCTAssertEqual(allDaysForToday.filter { $0.orderedSessions.isEmpty }.count, allDaysForToday.count - 1, "exactly the orphaned naive Days should be empty")

        let viewModel = TodayViewModel()
        viewModel.load(modelContext: context, referenceDate: today)
        XCTAssertFalse(viewModel.sessions.isEmpty)
        _ = journey
    }
}
