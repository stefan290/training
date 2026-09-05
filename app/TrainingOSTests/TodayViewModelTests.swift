import XCTest
import SwiftData
@testable import TrainingOS

/// V1 R2 (Today reconciliation) checkpoint: proves `TodayViewModel`'s real
/// state-selection behavior for every required Today state — never a
/// hardcoded-string/pixel assertion, always the real `sessions`/
/// `upcomingPlanStart`/`currentPhaseType` the View actually renders from.
@MainActor
final class TodayViewModelTests: XCTestCase {
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
    private func makeSession(
        on referenceDate: Date, name: String, status: SessionStatus = .scheduled,
        scheduledTime: Date? = nil, blockCount: Int = 1
    ) -> Session {
        let day = Day(ownerUserID: ownerUserID, date: Calendar.current.startOfDay(for: referenceDate))
        context.insert(day)
        let session = Session(scheduledTime: scheduledTime, name: name, modality: .hypertrophy, status: status)
        context.insert(session)
        day.addSession(session)
        for _ in 0..<blockCount {
            let block = WorkoutBlock(type: .strength)
            context.insert(block)
            session.addBlock(block)
        }
        return session
    }

    // MARK: A — one session today

    func testOneSessionToday() throws {
        let today = Date()
        makeSession(on: today, name: "Lower A")
        let viewModel = TodayViewModel()
        viewModel.load(modelContext: context, referenceDate: today)

        XCTAssertEqual(viewModel.sessions.count, 1)
        XCTAssertEqual(viewModel.sessions.first?.name, "Lower A")
        XCTAssertNil(viewModel.upcomingPlanStart, "a real session today must never also present the upcoming-start state")
    }

    // MARK: B — multiple real sessions today

    func testMultipleSessionsToday() throws {
        let today = Date()
        makeSession(on: today, name: "Lower A")
        makeSession(on: today, name: "Zone 2 Bike")
        let viewModel = TodayViewModel()
        viewModel.load(modelContext: context, referenceDate: today)

        XCTAssertEqual(viewModel.sessions.count, 2, "legitimate multiple Sessions must never be merged into one")
        XCTAssertEqual(Set(viewModel.sessions.map(\.name)), ["Lower A", "Zone 2 Bike"])
    }

    // MARK: C — completed today

    func testCompletedSessionToday() throws {
        let today = Date()
        let session = makeSession(on: today, name: "Lower A", status: .completed)
        let viewModel = TodayViewModel()
        viewModel.load(modelContext: context, referenceDate: today)

        XCTAssertEqual(viewModel.sessions.count, 1)
        XCTAssertEqual(viewModel.sessions.first?.status, .completed)
        XCTAssertEqual(session.status, .completed, "completion status itself is untouched by loading")
    }

    // MARK: D — genuine rest day (within an already-started phase)

    func testRestDayWithinAnAlreadyStartedPhase() throws {
        let today = Date()
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .muscleGain, createdAt: today)
        context.insert(goal)
        let plan = TrainingPlan(status: .active, createdAt: today)
        context.insert(plan)
        goal.addPlan(plan)
        let phase = TrainingPhase(
            type: .muscleGain, startDate: Calendar.current.date(byAdding: .day, value: -7, to: today)!,
            priorityRule: .strength, status: .active
        )
        context.insert(phase)
        plan.addPhase(phase)
        try context.save()

        let viewModel = TodayViewModel()
        viewModel.load(modelContext: context, referenceDate: today)

        XCTAssertTrue(viewModel.sessions.isEmpty)
        XCTAssertNil(viewModel.upcomingPlanStart, "an already-started phase's own rest day must never be presented as an upcoming plan start")
        XCTAssertEqual(viewModel.currentPhaseType, .muscleGain)
    }

    // MARK: E — R0 upcoming-plan-start state (Friday acceptance, Monday start), through the real production path

    func testUpcomingPlanStartAfterFridayAcceptance() throws {
        let friday = date(2026, 1, 2) // confirmed Friday
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .muscleGain, preferences: GoalPreferences(availableTrainingDaysPerWeek: 5, allowsDoubleSessions: false), createdAt: friday)
        context.insert(goal)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: friday)
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: friday)
        let phase = try XCTUnwrap(plan.orderedPhases.first)

        guard case .success(let mix) = LongTermPlanner.buildCustomMix(
            selections: [(style: .hypertrophy, frequency: 3), (style: .functionalFitness, frequency: 2)], capacity: 5
        ) else { return XCTFail("3H+2FF must be constructible") }

        let environment = TrainingEnvironmentTestSupport.full(context: context)
        // Real candidate exercises are required for Hypertrophy/Functional
        // Fitness slots to actually resolve — mirrors
        // `MidWeekNoDoubleCompositionTests.makeCandidates()`'s own
        // established idiom; an empty array never exercises the real
        // materialization path at all.
        let strengthExercise = Exercise(canonicalName: "Test Back Squat", modality: .hypertrophy, equipment: "barbell", movementPattern: "squat", primaryTargets: [.quadriceps])
        context.insert(strengthExercise)
        let ffExercise = Exercise(canonicalName: "Test FF Movement", modality: .hypertrophy, equipment: "barbell", movementPattern: "test", movementFunctions: [.squatLoaded], functionalModality: .weightlifting)
        context.insert(ffExercise)
        _ = try StartPhaseUseCase.start(
            phase: phase, mix: mix, asOf: friday, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: UserAvailability(trainingDaysPerWeek: 5, allowsDoubleSessions: false, maxSessionsPerDay: 1),
            materializationContext: TacticalMaterializationContext(
                equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
                strengthCandidateExercises: [strengthExercise], functionalFitnessCandidateExercises: [ffExercise], trainingEnvironment: environment
            ),
            context: context
        )

        let viewModel = TodayViewModel()
        viewModel.load(modelContext: context, referenceDate: friday)

        XCTAssertTrue(viewModel.sessions.isEmpty, "R0: zero source-backed Sessions exist before the resolved Monday")
        let upcoming = try XCTUnwrap(viewModel.upcomingPlanStart, "Today must present the R0 upcoming-start state, never look broken/empty with no explanation")
        XCTAssertEqual(Calendar.current.startOfDay(for: upcoming.startDate), Calendar.current.startOfDay(for: date(2026, 1, 5)), "the presented start date must be the real, truthful resolved Monday — never the Friday acceptance day")
        XCTAssertEqual(upcoming.phaseType, phase.type)
    }

    // MARK: F — late/earlier-today session

    func testLateSessionIsFlaggedPastDueButNeverAutoMarkedMissed() throws {
        let now = Date()
        let earlierToday = Calendar.current.date(byAdding: .hour, value: -3, to: now)!
        makeSession(on: now, name: "Lower A", scheduledTime: earlierToday)
        let viewModel = TodayViewModel()
        viewModel.load(modelContext: context, referenceDate: now)

        let session = try XCTUnwrap(viewModel.sessions.first)
        XCTAssertTrue(SessionPresentation.isPastDueUnstarted(status: session.status, scheduledTime: session.scheduledTime, asOf: now))
        XCTAssertEqual(session.status, .scheduled, "a past-due session must never be silently auto-marked missed merely by loading Today")
    }

    func testMarkMissedOnlyWritesWhenExplicitlyCalled() throws {
        let now = Date()
        let earlierToday = Calendar.current.date(byAdding: .hour, value: -3, to: now)!
        let session = makeSession(on: now, name: "Lower A", scheduledTime: earlierToday)
        let viewModel = TodayViewModel()
        viewModel.load(modelContext: context, referenceDate: now)

        viewModel.markMissed(session, modelContext: context)
        XCTAssertEqual(session.status, .missed)
    }

    // MARK: G — readiness-adapted state

    // Readiness adaptation is presented entirely through `ReadinessGateFlow`
    // (a full-screen cover triggered from `TodayView`'s own "Start" action),
    // not through any state `TodayViewModel` itself owns or computes —
    // confirmed by reading both files: `TodayViewModel` has no readiness-
    // related property, and `TodayView` presents `ReadinessGateFlow` keyed
    // only on `readinessGateSession` (View-local `@State`), unmodified by
    // this checkpoint. There is therefore no ViewModel-level state to
    // assert here without either fabricating one or duplicating
    // `ReadinessGateFlow`'s/`ReadinessAdaptationProposalView`'s own existing,
    // real test coverage — this checkpoint preserves that flow exactly as
    // it already worked, per its own "do not change readiness logic"
    // instruction.
}
