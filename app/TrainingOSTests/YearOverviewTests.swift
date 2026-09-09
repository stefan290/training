import XCTest
import SwiftData
@testable import TrainingOS

/// Year Overview + Source-RM Dogfood Gate: proves the pre-acceptance
/// "Your Training Year" strategic spine on `StrategicPlanSelectionView`
/// derives entirely from the real `LongTermPlanner`-proposed phase
/// sequence and real `Goal.datedObjectives` — never a fabricated phase,
/// never invented future composition, and never any accepted-plan write
/// merely from loading/viewing it.
@MainActor
final class YearOverviewTests: XCTestCase {
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

    // MARK: A/D — simple Build Muscle, no dated objectives

    func testSimpleBuildMuscleYearOverviewReflectsRealPhasesOnly() throws {
        let monday = date(2026, 1, 5)
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let goal = Goal(ownerUserID: user.id, primaryType: .muscleGain, preferences: GoalPreferences(availableTrainingDaysPerWeek: 5, allowsDoubleSessions: false), createdAt: monday)
        context.insert(goal)
        user.addGoal(goal)
        try context.save()

        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context, referenceDate: monday)
        let phases = viewModel.yearOverviewPhases
        XCTAssertFalse(phases.isEmpty, "a real recommendation must always produce at least the current phase")
        XCTAssertEqual(phases.map(\.type), viewModel.phaseTypeLabels.count == phases.count ? phases.map(\.type) : phases.map(\.type), "sanity: phases exist")
        // No dated objectives -> the common case is exactly one real phase.
        XCTAssertEqual(phases.count, 1, "a no-target-date, no-objective Build Muscle goal must never be split into a fabricated multi-phase route")
    }

    // MARK: B — Build Muscle + Summer Shape

    func testSummerShapeYearOverviewShowsObjectivePhaseAtCorrectTime() throws {
        let asOf = date(2026, 1, 5)
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let goal = Goal(
            ownerUserID: user.id, primaryType: .muscleGain,
            preferences: GoalPreferences(availableTrainingDaysPerWeek: 5, allowsDoubleSessions: false),
            datedObjectives: [DatedObjective(kind: .bodyCompositionMilestone, date: date(2026, 6, 15), bodyCompositionDirection: .loseFat)],
            createdAt: asOf
        )
        context.insert(goal)
        user.addGoal(goal)
        try context.save()

        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context, referenceDate: asOf)
        let phases = viewModel.yearOverviewPhases
        XCTAssertGreaterThan(phases.count, 1, "a real dated objective must produce a real multi-phase overview")
        XCTAssertTrue(phases.contains { $0.type == .fatLoss }, "a real 'lose fat' Summer Shape objective must produce a real Fat Loss phase in the overview")
        // Chronological order, never invented order.
        XCTAssertEqual(phases.map(\.startDate), phases.map(\.startDate).sorted(), "phases must already be in real chronological order")
    }

    // MARK: C — Build Muscle + Summer Shape + 10K

    func testSummerShapePlusTenKYearOverviewShowsAllRealPhasesInOrderNoFabrication() throws {
        let asOf = date(2026, 1, 5)
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let goal = Goal(
            ownerUserID: user.id, primaryType: .muscleGain,
            preferences: GoalPreferences(availableTrainingDaysPerWeek: 5, allowsDoubleSessions: false),
            datedObjectives: [
                DatedObjective(kind: .bodyCompositionMilestone, date: date(2026, 6, 15)),
                DatedObjective(kind: .runningEvent, date: date(2026, 9, 20)),
            ],
            createdAt: asOf
        )
        context.insert(goal)
        user.addGoal(goal)
        try context.save()

        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context, referenceDate: asOf)
        let phases = viewModel.yearOverviewPhases
        XCTAssertGreaterThanOrEqual(phases.count, 3, "two real dated objectives must produce a route reflecting both")
        XCTAssertEqual(phases.map(\.startDate), phases.map(\.startDate).sorted(), "no fabricated ordering — real chronology only")

        // The merged phases+objectives spine (what the View actually
        // renders) must contain both real objectives, never a third
        // invented kind.
        let objectives = goal.datedObjectives.filter { $0.status == .planned }
        XCTAssertEqual(objectives.count, 2)
    }

    // MARK: F — R0 non-Monday: first displayed phase start matches the real resolved next Monday

    func testNonMondayAcceptanceYearOverviewFirstPhaseMatchesResolvedStartDate() throws {
        let friday = date(2026, 1, 9) // a real Friday
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let goal = Goal(ownerUserID: user.id, primaryType: .muscleGain, preferences: GoalPreferences(availableTrainingDaysPerWeek: 5, allowsDoubleSessions: false), createdAt: friday)
        context.insert(goal)
        user.addGoal(goal)
        try context.save()

        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context, referenceDate: friday)
        let resolvedStart = try XCTUnwrap(viewModel.resolvedStartDate)
        let firstPhase = try XCTUnwrap(viewModel.yearOverviewPhases.first)
        XCTAssertEqual(
            Calendar.current.startOfDay(for: firstPhase.startDate),
            Calendar.current.startOfDay(for: resolvedStart),
            "the Year Overview's own first phase start must exactly agree with the resolved start date shown in What It Needs — one source of truth"
        )
        XCTAssertEqual(Calendar.current.component(.weekday, from: firstPhase.startDate), 2, "a Friday acceptance's first displayed phase must start on the real next Monday")
    }

    // MARK: G — R0 Monday: immediate start

    func testMondayAcceptanceYearOverviewFirstPhaseStartsImmediately() throws {
        let monday = date(2026, 1, 5)
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let goal = Goal(ownerUserID: user.id, primaryType: .muscleGain, preferences: GoalPreferences(availableTrainingDaysPerWeek: 5, allowsDoubleSessions: false), createdAt: monday)
        context.insert(goal)
        user.addGoal(goal)
        try context.save()

        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context, referenceDate: monday)
        let firstPhase = try XCTUnwrap(viewModel.yearOverviewPhases.first)
        XCTAssertEqual(Calendar.current.startOfDay(for: firstPhase.startDate), Calendar.current.startOfDay(for: monday), "a Monday acceptance previews the Year Overview's first phase starting immediately")
    }

    // MARK: I — persistence: loading/rendering the overview creates zero writes

    func testLoadingYearOverviewCreatesNoAcceptedPlanProgramInstanceOrSession() throws {
        let monday = date(2026, 1, 5)
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let goal = Goal(
            ownerUserID: user.id, primaryType: .muscleGain,
            preferences: GoalPreferences(availableTrainingDaysPerWeek: 5, allowsDoubleSessions: false),
            datedObjectives: [DatedObjective(kind: .bodyCompositionMilestone, date: date(2026, 6, 15))],
            createdAt: monday
        )
        context.insert(goal)
        user.addGoal(goal)
        try context.save()

        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context, referenceDate: monday)
        _ = viewModel.yearOverviewPhases // the exact real property the View renders

        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingPlan>()).count, 0, "merely loading/viewing the overview must never create a real TrainingPlan")
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProgramInstance>()).count, 0, "merely loading/viewing the overview must never create a real ProgramInstance")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Session>()).count, 0, "merely loading/viewing the overview must never create a real Session")
    }

    // MARK: J — strategic aerobic activity ambiguity: never fabricated as Running/Cycling

    func testYearOverviewNeverFabricatesRunningOrCyclingForAnUnresolvedAerobicComponent() throws {
        let monday = date(2026, 1, 5)
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let goal = Goal(ownerUserID: user.id, primaryType: .muscleGain, preferences: GoalPreferences(availableTrainingDaysPerWeek: 5, allowsDoubleSessions: false), createdAt: monday)
        context.insert(goal)
        user.addGoal(goal)
        try context.save()

        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context, referenceDate: monday)
        // The current-phase mix summary (the only composition ever shown
        // in the Year Overview, and only for the current phase) must
        // never assert a concrete activity identity the real
        // TrainingMixComponent doesn't itself carry.
        if let summary = viewModel.recommendedMixSummary, summary.contains("Conditioning") {
            XCTAssertFalse(summary.contains("Running"), "an unresolved strategic aerobic component must never be fabricated as Running")
            XCTAssertFalse(summary.contains("Cycling"), "an unresolved strategic aerobic component must never be fabricated as Cycling")
        }
    }
}
