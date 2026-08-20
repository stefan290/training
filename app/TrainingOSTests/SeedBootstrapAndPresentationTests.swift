import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 7 (Tactical Planning Orchestration), Slice 4 acceptance fix:
/// proves the app's own bootstrap (`SeedDataProvider.seedPrerequisites` +
/// `SeedAnnualPlanJourney.seed` — the exact sequence `TrainingOSApp.init`
/// now uses) produces ONE coherent training universe for Today/Week,
/// never `seedAll`'s own 8 hand-built demo scenarios mixed in alongside
/// it. Also covers the "Anytime" scheduled-time presentation fix and the
/// TrainingMixComponent → ProgrammingSystem → ProgramDefinition layering.
@MainActor
final class SeedBootstrapAndPresentationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    /// Exactly what `TrainingOSApp.init` calls on first launch.
    private func makeAppBootstrap() throws -> SeedAnnualPlanJourney.Result {
        let prerequisites = SeedDataProvider.seedPrerequisites(in: context)
        return try SeedAnnualPlanJourney.seed(
            user: prerequisites.user, performanceProfile: prerequisites.performanceProfile,
            catalog: prerequisites.catalog, context: context
        )
    }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    // MARK: A — the app bootstrap never receives seedAll's own legacy scenario Sessions

    func testAppBootstrapNeverIncludesSeedAllsLegacyScenarios() throws {
        _ = try makeAppBootstrap()
        // `seedAll` was never called at all in this path — its own named
        // scenarios ("Lower A", "Evening Zone 2", etc.) cannot exist.
        let allSessionNames = Set(try context.fetch(FetchDescriptor<Session>()).map(\.name))
        for legacyName in ["Lower A", "Evening Zone 2", "Upcoming Zone 2"] {
            XCTAssertFalse(allSessionNames.contains(legacyName), "\(legacyName) is seedAll's own legacy scenario name — it must never appear in the app's real bootstrap")
        }
        // Exactly one Goal, one User — no second, competing training universe.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Goal>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<User>()), 1)
    }

    // MARK: B — every Today Session belongs to the accepted active plan/tactical graph

    func testEveryTodaySessionBelongsToTheAcceptedActivePlan() throws {
        let journey = try makeAppBootstrap()
        let viewModel = TodayViewModel()
        viewModel.load(modelContext: context, referenceDate: today)

        XCTAssertFalse(viewModel.sessions.isEmpty)
        for session in viewModel.sessions {
            let phase = session.programInstance?.phase
            XCTAssertEqual(phase?.id, journey.activePhase.id, "\(session.name) must trace back to the accepted plan's own active phase, never an unrelated seed scenario")
        }
    }

    // MARK: C — Today and Week agree on Session identity/date

    func testTodayAndWeekAgreeOnSessionIdentity() throws {
        _ = try makeAppBootstrap()
        let todayViewModel = TodayViewModel()
        todayViewModel.load(modelContext: context, referenceDate: today)

        let weekViewModel = WeekViewModel()
        weekViewModel.load(modelContext: context, referenceDate: today)
        let weekToday = try XCTUnwrap(weekViewModel.days.first { Calendar.current.isDate($0.date, inSameDayAs: today) })

        XCTAssertEqual(Set(todayViewModel.sessions.map(\.id)), Set(weekToday.sessions.map(\.id)), "Today and Week must show the exact same Sessions for the same date — no hidden extra Sessions visible to only one surface")
    }

    // MARK: D — unknown/default time is never presented as an intentional 00:00 appointment

    func testUnknownScheduledTimeIsPresentedAsAnytimeNeverAnInventedClockTime() throws {
        let midnight = Calendar.current.startOfDay(for: Date())
        XCTAssertEqual(SessionPresentation.scheduledTimeLabel(midnight), "Anytime")

        let realTime = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!
        XCTAssertNotEqual(SessionPresentation.scheduledTimeLabel(realTime), "Anytime", "a genuinely meaningful time must still render normally")
    }

    // MARK: J — a date-only/Anytime Session is never classified as "late" merely because midnight has passed

    func testAnytimeSessionIsNeverPastDueRegardlessOfTimeOfDay() {
        let midnight = Calendar.current.startOfDay(for: Date())
        let laterSameDay = Calendar.current.date(byAdding: .hour, value: 20, to: midnight)! // 20:00 — long after midnight
        XCTAssertFalse(SessionPresentation.isPastDueUnstarted(status: .scheduled, scheduledTime: midnight, asOf: laterSameDay), "an Anytime Session must remain startable all day, never flagged late just because the clock passed midnight")
    }

    // MARK: K — a genuinely time-specific Session CAN still become late

    func testGenuinelyTimeSpecificSessionBecomesLateAfterItsRealScheduledTime() {
        let sevenAM = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!
        let eightAM = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
        let sixAM = Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: Date())!

        XCTAssertTrue(SessionPresentation.isPastDueUnstarted(status: .scheduled, scheduledTime: sevenAM, asOf: eightAM), "a real 07:00 appointment must be late once 08:00 arrives")
        XCTAssertFalse(SessionPresentation.isPastDueUnstarted(status: .scheduled, scheduledTime: sevenAM, asOf: sixAM), "not yet late before its own real time")
        XCTAssertFalse(SessionPresentation.isPastDueUnstarted(status: .completed, scheduledTime: sevenAM, asOf: eightAM), "an already-completed Session is never shown as past-due-unstarted")
    }

    func testRealSchedulerNeverProducesANonMidnightScheduledTime() throws {
        // Documents the confirmed architecture fact driving the fix above:
        // the real scheduling pipeline has no time-of-day concept
        // anywhere, so every production-scheduled Session's own
        // scheduledTime is exactly midnight — never a fabricated "real"
        // time this test could be fooled by.
        let journey = try makeAppBootstrap()
        let sessions = journey.activePhase.programInstances.flatMap(\.sessions)
        XCTAssertFalse(sessions.isEmpty)
        for session in sessions {
            guard let scheduledTime = session.scheduledTime else { continue }
            XCTAssertEqual(scheduledTime, Calendar.current.startOfDay(for: scheduledTime), "a real, scheduler-produced Session's own scheduledTime is always exactly midnight today — confirms the presentation fix is addressing a real, reproducible case, not a hypothetical one")
        }
    }

    // MARK: G — TrainingMixComponent -> ProgrammingSystem -> ProgramDefinition mapping is semantically valid

    func testComponentLabelProgrammingSystemAndProgramDefinitionAreConsistentLayers() throws {
        let journey = try makeAppBootstrap()
        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: journey.activePhase, modelContext: context)

        let strengthComponent = try XCTUnwrap(viewModel.activeComponents.first { $0.label == "Strength" })
        // By design (`LongTermPlanner.muscleGainVariedMix`, `ADHERENCE_AWARE_PLANNING.md`
        // §5d's own worked example): "Strength" is the broad, user-facing
        // modality label; `.hypertrophy` is the real, resolved programming
        // system driving it — never a capability-registry mismatch.
        XCTAssertEqual(strengthComponent.programmingSystem, .hypertrophy)
        let instance = try XCTUnwrap(strengthComponent.programInstance)
        let definition = try XCTUnwrap(instance.programDefinition)
        XCTAssertEqual(definition.programmingSystem, .hypertrophy, "the component's own programmingSystem and its real materialized ProgramDefinition's system must always agree")
    }

    // MARK: H — user-facing modality/system/program labels come from the correct layer

    func testProgrammingSystemLabelIsDistinctFromTheComponentsOwnLabel() throws {
        let journey = try makeAppBootstrap()
        let strengthComponent = try XCTUnwrap(journey.activePhase.selectedTrainingMix?.orderedComponents.first { $0.label == "Strength" })
        let systemLabel = PlanPresentation.programmingSystemLabel(strengthComponent.programmingSystem)
        XCTAssertEqual(systemLabel, "Hypertrophy")
        XCTAssertNotEqual(systemLabel, strengthComponent.label, "the modality label and the resolved programming system are two distinct, independently meaningful values — never accidentally the same string")
        for system in ProgrammingSystemKind.allCases {
            XCTAssertFalse(PlanPresentation.programmingSystemLabel(system).isEmpty)
        }
    }
}
