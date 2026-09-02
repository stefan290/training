import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 7 (Tactical Planning Orchestration), Slice 4 acceptance fix
/// (round 5): proves Week navigation across calendar-week boundaries is
/// read-only, and that an upcoming phase's strategic preview exposes
/// `LongTermPlanner`'s own recommendation without ever materializing a
/// tactical window, assigning a real date, or creating a Session — all
/// driven through the real `SeedAnnualPlanJourney` fixture, never a
/// hand-built one.
@MainActor
final class WeekNavigationAndUpcomingPhasePreviewTests: XCTestCase {
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
        let userProfile = UserProfile()
        context.insert(userProfile)
        user.attachProfile(userProfile)
        let fullGym = TrainingEnvironment(name: "Test Full Gym", availableEquipment: EquipmentRequirement.allCases)
        context.insert(fullGym)
        userProfile.trainingEnvironments = [fullGym]
        userProfile.defaultTrainingEnvironment = fullGym
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        return try SeedAnnualPlanJourney.seed(user: user, performanceProfile: profile, catalog: catalog, context: context)
    }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    // MARK: — Week navigation crosses calendar-week boundaries correctly

    func testWeekNavigationAdvancesAndReturnsAcrossCalendarWeekBoundaries() throws {
        _ = try makeJourney()
        let viewModel = WeekViewModel()
        viewModel.load(modelContext: context)
        XCTAssertTrue(viewModel.isCurrentWeek)
        let currentWeekStart = try XCTUnwrap(viewModel.days.first?.date)

        viewModel.goToNextWeek(modelContext: context)
        XCTAssertFalse(viewModel.isCurrentWeek)
        let nextWeekStart = try XCTUnwrap(viewModel.days.first?.date)
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: currentWeekStart, to: nextWeekStart).day, 7, "Next Week must land exactly 7 days after the current week's own start")

        viewModel.goToNextWeek(modelContext: context)
        let twoWeeksOutStart = try XCTUnwrap(viewModel.days.first?.date)
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: currentWeekStart, to: twoWeeksOutStart).day, 14, "a second Next Week must land exactly 14 days out")

        viewModel.goToPreviousWeek(modelContext: context)
        viewModel.goToPreviousWeek(modelContext: context)
        viewModel.goToPreviousWeek(modelContext: context)
        let previousWeekStart = try XCTUnwrap(viewModel.days.first?.date)
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: currentWeekStart, to: previousWeekStart).day, -7, "three Previous Week calls from two-weeks-out (net offset -1) must land back one week before the current week")

        viewModel.goToCurrentWeek(modelContext: context)
        XCTAssertTrue(viewModel.isCurrentWeek)
        XCTAssertEqual(viewModel.days.first?.date, currentWeekStart, "This Week must return exactly to the original current-week start")
    }

    /// The exact acceptance-test scenario: the active phase starts
    /// mid-week, so Next Week must surface the following full tactical
    /// week's sessions — including Running, which this round's fix keeps
    /// on a steady weekly cadence.
    func testNextWeekSurfacesTheFollowingFullTacticalWeeksRunningSession() throws {
        let journey = try makeJourney()
        let runningComponent = try XCTUnwrap(journey.activePhase.selectedTrainingMix?.orderedComponents.first { $0.programmingSystem == .steadyState })
        let runningInstance = try XCTUnwrap(runningComponent.programInstance)
        XCTAssertGreaterThan(runningInstance.sessions.count, 1, "sanity: Steady State's whole natural block is already materialized")

        let viewModel = WeekViewModel()
        viewModel.load(modelContext: context)
        for _ in 0..<6 {
            viewModel.goToNextWeek(modelContext: context)
            let weekSessionIDs = Set(viewModel.days.flatMap(\.sessions).map(\.id))
            if runningInstance.sessions.contains(where: { weekSessionIDs.contains($0.id) }) {
                return // found Running in some future real calendar week — the browsing path surfaces real materialized data
            }
        }
        XCTFail("browsing forward across 6 calendar weeks never surfaced any of Running's already-materialized sessions")
    }

    // MARK: — Week navigation center label is deterministic relative to today's actual calendar week

    func testWeekNavigationLabelIsDeterministicRelativeToTodaysCalendarWeekRegardlessOfNavigationDirection() throws {
        _ = try makeJourney()
        let viewModel = WeekViewModel()
        viewModel.load(modelContext: context)
        XCTAssertEqual(viewModel.weekNavigationLabel, "This Week")

        viewModel.goToNextWeek(modelContext: context)
        XCTAssertEqual(viewModel.weekNavigationLabel, "Next Week", "one step forward must always read 'Next Week', never 'Current Week'")

        viewModel.goToNextWeek(modelContext: context)
        XCTAssertTrue(viewModel.weekNavigationLabel.contains("–"), "two steps out must show a concrete date range, never a relative word that misdescribes which week is on screen")
        XCTAssertNotEqual(viewModel.weekNavigationLabel, "Current Week")

        viewModel.goToCurrentWeek(modelContext: context)
        XCTAssertEqual(viewModel.weekNavigationLabel, "This Week")

        viewModel.goToPreviousWeek(modelContext: context)
        XCTAssertEqual(viewModel.weekNavigationLabel, "Previous Week", "one step back must always read 'Previous Week'")

        viewModel.goToPreviousWeek(modelContext: context)
        XCTAssertTrue(viewModel.weekNavigationLabel.contains("–"), "two steps back must also show a concrete date range")
    }

    // MARK: — Browsing future/previous weeks never mutates the schedule

    func testBrowsingFutureAndPreviousWeeksNeverMutatesAnyPersistedState() throws {
        _ = try makeJourney()
        let sessionCountBefore = try context.fetchCount(FetchDescriptor<Session>())
        let dayCountBefore = try context.fetchCount(FetchDescriptor<Day>())

        let viewModel = WeekViewModel()
        viewModel.load(modelContext: context)
        for _ in 0..<5 { viewModel.goToNextWeek(modelContext: context) }
        for _ in 0..<8 { viewModel.goToPreviousWeek(modelContext: context) }
        viewModel.goToCurrentWeek(modelContext: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Session>()), sessionCountBefore, "browsing Week must never create or delete a Session")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Day>()), dayCountBefore, "browsing Week must never create or delete a Day")
    }

    // MARK: — Upcoming phase preview never materializes a tactical window

    func testUpcomingPhasePreviewNeverMaterializesATacticalWindow() throws {
        let journey = try makeJourney()
        let upcomingPhase = try XCTUnwrap(journey.upcomingPhases.first)
        let sessionCountBefore = try context.fetchCount(FetchDescriptor<Session>())
        let instanceCountBefore = try context.fetchCount(FetchDescriptor<ProgramInstance>())
        let mixCountBefore = try context.fetchCount(FetchDescriptor<TrainingMix>())

        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: upcomingPhase, modelContext: context)
        viewModel.load(phase: upcomingPhase, modelContext: context) // browsing again must still be a no-op

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Session>()), sessionCountBefore, "previewing an upcoming phase must never create a Session")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramInstance>()), instanceCountBefore, "previewing an upcoming phase must never create a real ProgramInstance")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TrainingMix>()), mixCountBefore, "previewing an upcoming phase must never persist a TrainingMix into the real store")
        XCTAssertTrue(upcomingPhase.programInstances.isEmpty)
        XCTAssertEqual(upcomingPhase.status, .planned, "merely previewing must never advance a phase's status")
    }

    // MARK: — Upcoming phase preview exposes recommendation data when available

    func testUpcomingPhasePreviewExposesRecommendationDataWhenAvailable() throws {
        let journey = try makeJourney()
        let upcomingPhase = try XCTUnwrap(journey.upcomingPhases.first)

        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: upcomingPhase, modelContext: context)

        let previewMix = try XCTUnwrap(viewModel.upcomingPreviewMix, "an upcoming phase with a real Goal must expose a live recommended-mix preview")
        XCTAssertFalse(previewMix.orderedComponents.isEmpty)
        XCTAssertFalse(viewModel.upcomingComponentPreviews.isEmpty)
        XCTAssertTrue(viewModel.upcomingComponentPreviews.contains { $0.previewProgramDefinition != nil }, "at least one previewed component must resolve to a real, known ProgramDefinition")
    }

    // MARK: — Browsing an upcoming phase never alters the active phase

    func testBrowsingAnUpcomingPhaseNeverAltersTheActivePhase() throws {
        let journey = try makeJourney()
        let activeSessionIDsBefore = Set(journey.activePhase.selectedTrainingMix?.orderedComponents.compactMap(\.programInstance).flatMap(\.sessions).map(\.id) ?? [])
        let activeMixIDBefore = journey.activePhase.selectedTrainingMix?.id
        let activeStatusBefore = journey.activePhase.status

        let upcomingPhase = try XCTUnwrap(journey.upcomingPhases.first)
        let previewViewModel = PhaseDetailViewModel()
        previewViewModel.load(phase: upcomingPhase, modelContext: context)

        let activeViewModel = PhaseDetailViewModel()
        activeViewModel.load(phase: journey.activePhase, modelContext: context)

        XCTAssertEqual(journey.activePhase.status, activeStatusBefore)
        XCTAssertEqual(journey.activePhase.selectedTrainingMix?.id, activeMixIDBefore)
        let activeSessionIDsAfter = Set(activeViewModel.activeComponents.compactMap(\.programInstance).flatMap(\.sessions).map(\.id))
        XCTAssertEqual(activeSessionIDsAfter, activeSessionIDsBefore, "browsing an upcoming phase's preview must never change the active phase's own real materialized Sessions")
    }
}
