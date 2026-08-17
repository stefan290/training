import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 6C acceptance tests (Part AB): Week reads the real scheduled/
/// materialized `Day`/`Session` graph — never a second, UI-only dataset,
/// never fabricates a Session beyond what's actually materialized, and
/// never mutates anything just because the user is browsing.
@MainActor
final class WeekViewModelTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func makeDay(offsetFromToday: Int) -> Day {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: offsetFromToday, to: calendar.startOfDay(for: Date()))!
        let day = Day(ownerUserID: ownerUserID, date: date)
        context.insert(day)
        return day
    }

    private func addSession(to day: Day, name: String, status: SessionStatus = .scheduled) -> Session {
        let session = Session(name: name, modality: .strength, status: status)
        context.insert(session)
        day.addSession(session)
        return session
    }

    // MARK: Q/R — current week contents, multiple Sessions per day

    func testCurrentWeekContainsEveryScheduledSessionInThatWeek() throws {
        let today = makeDay(offsetFromToday: 0)
        addSession(to: today, name: "Lower A")

        let viewModel = WeekViewModel()
        viewModel.load(modelContext: context)

        let allSessionNames = viewModel.days.flatMap { $0.sessions.map(\.name) }
        XCTAssertTrue(allSessionNames.contains("Lower A"))
    }

    func testDaysWithMultipleSessionsExposeEachSessionIndependently() throws {
        let today = makeDay(offsetFromToday: 0)
        addSession(to: today, name: "Lower A")
        addSession(to: today, name: "Evening Zone 2")

        let viewModel = WeekViewModel()
        viewModel.load(modelContext: context)

        let todayEntry = try XCTUnwrap(viewModel.days.first { Calendar.current.isDateInToday($0.date) })
        XCTAssertEqual(todayEntry.sessions.count, 2)
        XCTAssertEqual(Set(todayEntry.sessions.map(\.name)), ["Lower A", "Evening Zone 2"])
    }

    // MARK: S — zero-Session days render as Rest without a fake Session

    func testDaysWithZeroSessionsHaveAnEmptySessionsArrayNeverAFabricatedOne() throws {
        // Deliberately no Day/Session created for "today" at all.
        let viewModel = WeekViewModel()
        viewModel.load(modelContext: context)

        XCTAssertEqual(viewModel.days.count, 7)
        XCTAssertTrue(viewModel.days.allSatisfy { $0.sessions.isEmpty })
    }

    // MARK: T — status mapping from canonical domain state

    func testWeekStatusLabelMapsFromCanonicalSessionStatus() {
        XCTAssertEqual(SessionPresentation.weekStatusLabel(for: .completed, isToday: false), "Completed")
        XCTAssertEqual(SessionPresentation.weekStatusLabel(for: .inProgress, isToday: false), "In Progress")
        XCTAssertEqual(SessionPresentation.weekStatusLabel(for: .missed, isToday: false), "Missed")
        XCTAssertEqual(SessionPresentation.weekStatusLabel(for: .scheduled, isToday: true), "Ready", "today's own scheduled Session is still 'Ready,' never 'Upcoming'")
        XCTAssertEqual(SessionPresentation.weekStatusLabel(for: .scheduled, isToday: false), "Upcoming")
    }

    // MARK: U/V — inspecting a future Session never mutates it or creates results

    func testInspectingAFutureSessionNeverMutatesItsStatusOrTimestamps() throws {
        let futureDay = makeDay(offsetFromToday: 3)
        let session = addSession(to: futureDay, name: "Upper A")
        let statusBefore = session.status
        let startedAtBefore = session.startedAt
        let completedAtBefore = session.completedAt

        // The exact read surface `SessionPreviewContent` exercises —
        // nothing here calls a use case or mutates anything.
        _ = session.orderedBlocks.map { BlockPresentation.compactDetail(for: $0) }

        XCTAssertEqual(session.status, statusBefore)
        XCTAssertEqual(session.startedAt, startedAtBefore)
        XCTAssertEqual(session.completedAt, completedAtBefore)
    }

    func testInspectingAFutureSessionCreatesNoResults() throws {
        let futureDay = makeDay(offsetFromToday: 3)
        let session = addSession(to: futureDay, name: "Upper A")
        let block = WorkoutBlock(type: .strength)
        context.insert(block)
        session.addBlock(block)
        let movement = ExercisePrescription(exercise: Exercise(canonicalName: "Overhead Press", modality: .strength, equipment: "barbell", movementPattern: "press"))
        context.insert(movement)
        block.addPrescription(movement)

        _ = session.orderedBlocks.map { BlockPresentation.compactDetail(for: $0) }

        let resultCount = try context.fetchCount(FetchDescriptor<SetResult>())
        XCTAssertEqual(resultCount, 0)
    }

    // MARK: W/X/Y/Z — future detail exposes the real prescription per modality

    func testFutureStrengthSessionDetailExposesAllExercisePrescriptionsInCanonicalOrder() throws {
        let futureDay = makeDay(offsetFromToday: 2)
        let session = addSession(to: futureDay, name: "Upper A")
        let block = WorkoutBlock(type: .strength)
        context.insert(block)
        session.addBlock(block)
        for name in ["Bench Press", "Row", "Overhead Press"] {
            let movement = ExercisePrescription(exercise: Exercise(canonicalName: name, modality: .strength, equipment: "barbell", movementPattern: "press"))
            context.insert(movement)
            block.addPrescription(movement)
        }

        XCTAssertEqual(block.orderedPrescriptions.compactMap { $0.exercise?.canonicalName }, ["Bench Press", "Row", "Overhead Press"])
    }

    func testFutureSteadyStateSessionDetailExposesItsRealPrescription() throws {
        let futureDay = makeDay(offsetFromToday: 2)
        let session = addSession(to: futureDay, name: "Zone 2 Bike")
        let block = WorkoutBlock(type: .steadyState)
        context.insert(block)
        session.addBlock(block)
        let prescription = SteadyStatePrescription(activityType: .cycling, durationSeconds: 2400)
        context.insert(prescription)
        block.attachSteadyStatePrescription(prescription)

        guard case .steadyState(let resolved) = block.blockPrescription else {
            return XCTFail("expected a steadyState prescription")
        }
        XCTAssertEqual(resolved.activityType, .cycling)
        XCTAssertEqual(resolved.durationSeconds, 2400)
    }

    func testFutureIntervalSessionDetailExposesItsRealIntervalStructure() throws {
        let futureDay = makeDay(offsetFromToday: 2)
        let session = addSession(to: futureDay, name: "Track Intervals")
        let block = WorkoutBlock(type: .intervals)
        context.insert(block)
        session.addBlock(block)
        let prescription = IntervalPrescription(activityType: .running, intervalCount: 6, workDurationSeconds: 180, recoveryDurationSeconds: 90)
        context.insert(prescription)
        block.attachIntervalPrescription(prescription)

        guard case .intervals(let resolved) = block.blockPrescription else {
            return XCTFail("expected an intervals prescription")
        }
        XCTAssertEqual(resolved.intervalCount, 6)
        XCTAssertEqual(resolved.workDurationSeconds, 180)
        XCTAssertEqual(resolved.recoveryDurationSeconds, 90)
    }

    func testFutureFunctionalFitnessSessionDetailExposesItsRealWorkoutPrescription() throws {
        let futureDay = makeDay(offsetFromToday: 2)
        let session = addSession(to: futureDay, name: "Metcon")
        let block = WorkoutBlock(type: .functionalFitness)
        context.insert(block)
        session.addBlock(block)
        let stimulus = Stimulus(
            targetDurationDomain: .short, intensity: .high, loading: .moderate,
            movementFunctions: [.squatLoaded], movementModalityMix: [], skillDemand: .moderate,
            systemicDemand: .high, scoreType: .roundsAndReps
        )
        let prescription = FunctionalFitnessPrescription(stimulus: stimulus, format: .amrap(capSeconds: 720))
        context.insert(prescription)
        block.attachFunctionalFitnessPrescription(prescription)

        guard case .functionalFitness(let resolved) = block.blockPrescription else {
            return XCTFail("expected a functionalFitness prescription")
        }
        if case .amrap(let cap) = resolved.format {
            XCTAssertEqual(cap, 720)
        } else {
            XCTFail("expected AMRAP format")
        }
    }

    // MARK: AA/AB — tactical window boundary, never fabricated, never triggers materialization

    func testNavigatingOutsideTheTacticalWindowDoesNotFabricateSessions() throws {
        let sessionCountBefore = try context.fetchCount(FetchDescriptor<Session>())
        let dayCountBefore = try context.fetchCount(FetchDescriptor<Day>())

        let viewModel = WeekViewModel()
        for _ in 0..<52 { viewModel.goToNextWeek(modelContext: context) } // roughly a year out — nothing materialized there

        XCTAssertTrue(viewModel.weekHasNoMaterializedData)
        XCTAssertTrue(viewModel.days.allSatisfy { $0.sessions.isEmpty })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Session>()), sessionCountBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Day>()), dayCountBefore)
    }

    func testNavigatingForwardRepeatedlyNeverTriggersMaterialization() throws {
        let dayCountBefore = try context.fetchCount(FetchDescriptor<Day>())
        let viewModel = WeekViewModel()
        for _ in 0..<10 {
            viewModel.goToNextWeek(modelContext: context)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Day>()), dayCountBefore)
    }

    // MARK: AC — multiple Sessions on one day remain separate

    func testMultipleSessionsOnOneDayRemainIndependentlyMutable() throws {
        let today = makeDay(offsetFromToday: 0)
        let morning = addSession(to: today, name: "Lower A")
        let evening = addSession(to: today, name: "Evening Zone 2")

        try StartSessionUseCase.start(morning, asOf: Date(), modelContext: context)

        XCTAssertEqual(morning.status, .inProgress)
        XCTAssertEqual(evening.status, .scheduled, "starting one Session on a shared day never affects its sibling")
    }

    // MARK: AD — Week derives its data from the live store, never a cached/parallel copy

    func testWeekReflectsLiveStoreStateRatherThanACachedCopy() throws {
        let today = makeDay(offsetFromToday: 0)
        let session = addSession(to: today, name: "Lower A")

        let viewModel = WeekViewModel()
        viewModel.load(modelContext: context)
        XCTAssertEqual(viewModel.days.first { Calendar.current.isDateInToday($0.date) }?.sessions.first?.status, .scheduled)

        try StartSessionUseCase.start(session, asOf: Date(), modelContext: context)
        viewModel.load(modelContext: context)

        XCTAssertEqual(viewModel.days.first { Calendar.current.isDateInToday($0.date) }?.sessions.first?.status, .inProgress)
    }
}
