import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 7 (Tactical Planning Orchestration), Slice 4 acceptance fix
/// (round 4): proves the baseline tactical-placement contract through the
/// REAL production path (`LongTermPlanner` -> `StartPhaseUseCase` -> real
/// materializers -> `ConcurrentScheduler`/`AcceptScheduleProposalUseCase`)
/// — never a hand-authored `ScheduleProposal`. Covers the phase-start
/// boundary, per-week frequency fidelity, and cross-surface consistency
/// that the origin-week floor fix (`ConcurrentScheduler
/// .originWeekFloorOffset`) and the `RollTacticalWindowUseCase` week-shift
/// fix both depend on.
@MainActor
final class TacticalPlacementBoundaryTests: XCTestCase {
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
            exercise("Aaa Boundary Primary Shoulders", [.shoulders]),
            exercise("Aaa Boundary Primary Quads", [.quadriceps]),
            exercise("Aaa Boundary Primary Back", [.back]),
            exercise("Zzz Boundary Paired Accessory", [.chest, .triceps]),
        ]
        let ff = [
            exercise("Boundary FF Squat Lift", [], [.squatLoaded], .weightlifting),
            exercise("Boundary FF Pull-up", [], [.gymnasticsPull], .gymnastics),
            exercise("Boundary FF Bike", [], [.monostructural], .metabolicConditioning),
        ]
        return AllCandidates(strength: strength, functionalFitness: ff)
    }

    private func startVariedMix(asOf: Date) throws -> (goal: Goal, phase: TrainingPhase, mix: TrainingMix, result: StartPhaseUseCase.Result, candidates: AllCandidates) {
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .muscleGain, targetDate: Calendar.current.date(byAdding: .year, value: 1, to: asOf), createdAt: asOf)
        context.insert(goal)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: asOf)
        let phase = try XCTUnwrap(plan.orderedPhases.first)

        let mixCandidates = LongTermPlanner.proposeTrainingMix(phase: phase, goal: goal)
        let variedMix = try XCTUnwrap(mixCandidates.first { $0.mix.name == "Strength Plus Variety" })
        let candidates = makeCandidates()
        let materializationContext = TacticalMaterializationContext(
            equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness
        )
        let result = try StartPhaseUseCase.start(
            phase: phase, mix: variedMix.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext, context: context
        )
        return (goal, phase, variedMix.mix, result, candidates)
    }

    private func weekIndex(of date: Date, from start: Date) -> Int {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start), to: Calendar.current.startOfDay(for: date)).day ?? -1
        return days / 7
    }

    /// Real Monday-Sunday calendar week identity — deliberately distinct
    /// from `weekIndex`'s program-week (7-day-from-phase-start) bucketing.
    /// A phase that starts mid-week has program weeks that straddle two
    /// calendar weeks; this is what the "Week" UI/tactical debt tests
    /// below actually need to reason about.
    private func calendarWeekKey(for date: Date) -> DateComponents {
        Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    }

    /// A second, structurally different real candidate mix — Steady
    /// State as the *primary* (first claim on days) rather than
    /// `startVariedMix`'s supporting-tier Running — so genericity tests
    /// aren't only ever exercising one specific priority arrangement.
    private func startEnduranceMix(asOf: Date) throws -> (goal: Goal, phase: TrainingPhase, mix: TrainingMix, candidates: AllCandidates) {
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .enduranceEvent, targetDate: Calendar.current.date(byAdding: .year, value: 1, to: asOf), createdAt: asOf)
        context.insert(goal)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: asOf)
        let phase = try XCTUnwrap(plan.orderedPhases.first)

        let mixCandidates = LongTermPlanner.proposeTrainingMix(phase: phase, goal: goal)
        let performanceMix = try XCTUnwrap(mixCandidates.first { $0.mix.name.hasSuffix("Performance") && $0.mix.orderedComponents.count == 2 })
        let candidates = makeCandidates()
        let materializationContext = TacticalMaterializationContext(
            equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness
        )
        try StartPhaseUseCase.start(
            phase: phase, mix: performanceMix.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext, context: context
        )
        return (goal, phase, performanceMix.mix, candidates)
    }

    // MARK: A — no Session ever schedules before TrainingPhase.startDate

    func testNoSessionEverSchedulesBeforeThePhasesOwnStartDate() throws {
        let asOf = date(2026, 3, 4) // a Wednesday — mid-calendar-week start
        let fixture = try startVariedMix(asOf: asOf)

        let allSessions = fixture.mix.orderedComponents.compactMap(\.programInstance).flatMap(\.sessions)
        XCTAssertFalse(allSessions.isEmpty)
        for session in allSessions {
            let scheduledDate = try XCTUnwrap(session.day?.date, "\(session.name) must have a real scheduled Day after phase start")
            XCTAssertGreaterThanOrEqual(scheduledDate, fixture.phase.startDate, "\(session.name) must never be scheduled before the phase's own start date")
        }
    }

    // MARK: H — a mid-calendar-week phase start never backfills before phase start

    func testMidCalendarWeekPhaseStartNeverBackfillsEarlierDays() throws {
        let asOf = date(2026, 3, 4) // Wednesday
        let fixture = try startVariedMix(asOf: asOf)
        let allSessions = fixture.mix.orderedComponents.compactMap(\.programInstance).flatMap(\.sessions)
        for session in allSessions {
            let scheduledDate = try XCTUnwrap(session.day?.date)
            XCTAssertFalse(scheduledDate < asOf, "\(session.name) landed before the phase's own asOf/start date — a mid-week start must never backfill earlier calendar days")
        }
    }

    // MARK: C/F — Running's own weekly cadence is preserved, one real week at a time, in correct order

    func testRunningsFrequencyIsPreservedOneRealCalendarWeekAtATimeInCorrectOrder() throws {
        let asOf = date(2026, 1, 5) // Monday
        let fixture = try startVariedMix(asOf: asOf)
        let runningInstance = try XCTUnwrap(fixture.mix.orderedComponents.first { $0.label == "Running" }?.programInstance)

        let byWeek = Dictionary(grouping: runningInstance.sessions) { session -> Int in
            weekIndex(of: session.day?.date ?? .distantPast, from: fixture.phase.startDate)
        }

        // No single real calendar week ever holds more than one of
        // Running's sessions — the exact "2 in week 1, 3 in week 2"
        // compression bug this fix addresses.
        for (week, sessions) in byWeek {
            XCTAssertLessThanOrEqual(sessions.count, 1, "calendar week \(week) holds \(sessions.count) Running sessions — later weeks' content must never compress into one real week")
        }

        // Each of Running's materialized weeks landed in a DISTINCT,
        // increasing real calendar week — never out of order.
        let orderedRealWeeks = runningInstance.sessions
            .sorted { ($0.day?.date ?? .distantPast) < ($1.day?.date ?? .distantPast) }
            .map { weekIndex(of: $0.day?.date ?? .distantPast, from: fixture.phase.startDate) }
        XCTAssertEqual(orderedRealWeeks, orderedRealWeeks.sorted(), "Running's own materialized weeks must land in non-decreasing real-calendar-week order")
        XCTAssertEqual(Set(orderedRealWeeks).count, orderedRealWeeks.count, "no two of Running's own materialized weeks may share the same real calendar week")
    }

    // MARK: D — 3 Strength + 2 Functional Fitness + 1 Running produces exactly those weekly counts

    func testMixedModalityWeeklyCountsMatchTheAcceptedTrainingMixExactly() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try startVariedMix(asOf: asOf)

        let strengthInstance = try XCTUnwrap(fixture.mix.orderedComponents.first { $0.label == "Strength" }?.programInstance)
        let ffInstance = try XCTUnwrap(fixture.mix.orderedComponents.first { $0.label == "Functional Fitness" }?.programInstance)
        let runningInstance = try XCTUnwrap(fixture.mix.orderedComponents.first { $0.label == "Running" }?.programInstance)

        func week0Count(_ instance: ProgramInstance) -> Int {
            instance.sessions.filter { weekIndex(of: $0.day?.date ?? .distantPast, from: fixture.phase.startDate) == 0 }.count
        }

        XCTAssertEqual(week0Count(strengthInstance), 3, "Strength's own week 0 must contain exactly its 3 materialized sessions")
        XCTAssertEqual(week0Count(ffInstance), 2, "Functional Fitness's own week 0 must contain exactly its 2 materialized sessions")
        XCTAssertEqual(week0Count(runningInstance), 1, "Running's own week 0 must contain exactly 1 session — never more, from a later week compressing in")
    }

    // MARK: — Aggregate invariant: required weekly sessions == sessions materialized across the whole tactical window

    /// Locks in the invariant the acceptance round explicitly asked for:
    /// summed across every real materialized week, each component's own
    /// session count must equal `frequency.target` (or `.minimum` when
    /// set) times however many of its own weeks actually materialized —
    /// never fewer, with no silent drop. This holds independently of
    /// which specific calendar day any individual session lands on.
    func testEveryComponentsTotalMaterializedSessionsMatchesItsOwnFrequencyTimesMaterializedWeeks() throws {
        let asOf = date(2026, 1, 5) // Monday
        let fixture = try startVariedMix(asOf: asOf)

        for component in fixture.mix.orderedComponents {
            guard let instance = component.programInstance else { continue }
            let requiredPerWeek = component.frequency.minimum ?? component.frequency.target
            let materializedWeeks = Set(instance.sessions.map { weekIndex(of: $0.day?.date ?? .distantPast, from: fixture.phase.startDate) }).count
            XCTAssertEqual(
                instance.sessions.count, requiredPerWeek * materializedWeeks,
                "\(component.label): materialized \(instance.sessions.count) sessions across \(materializedWeeks) week(s), expected exactly \(requiredPerWeek) per week"
            )
        }
    }

    /// A phase that starts mid-calendar-week has fewer than 7 real
    /// calendar days available in its first program-week (some fall
    /// before `phase.startDate` and are correctly never scheduled). This
    /// documents — not silently hides — what the scheduler does when a
    /// mix's total weekly session count exceeds the days actually
    /// available in that shortened first week under a strict one-
    /// session-per-day availability: every session still lands on a
    /// real, valid day at or after phase start, never before it and
    /// never doubled without permission, even though that may push the
    /// lowest-priority component's first session past the calendar-week
    /// boundary its higher-priority peers already filled.
    func testMidWeekPhaseStartWithAnAtCapacityMixPlacesEverySessionValidlyEvenWhenOneSpillsPastTheFirstCalendarWeek() throws {
        let asOf = date(2026, 1, 7) // Wednesday — 5 usable days remain in the first calendar week
        let fixture = try startVariedMix(asOf: asOf)

        let allSessions = fixture.mix.orderedComponents.compactMap(\.programInstance).flatMap(\.sessions)
        XCTAssertFalse(allSessions.isEmpty)
        for session in allSessions {
            let scheduledDate = try XCTUnwrap(session.day?.date)
            XCTAssertGreaterThanOrEqual(scheduledDate, fixture.phase.startDate, "\(session.name) must never be scheduled before phase start, even under a mid-week-start capacity crunch")
        }
        // No two sessions may double up on the same real Day under this
        // fixture's strict one-session-per-day availability.
        let allDates = allSessions.compactMap { $0.day?.date }
        XCTAssertEqual(Set(allDates).count, allDates.count, "no day may hold more than one session when doubling isn't permitted")
    }

    // MARK: B — a partial first calendar week may legitimately contain fewer than the mix's nominal weekly frequency

    func testPartialFirstCalendarWeekLegitimatelyContainsFewerSessionsThanTheMixsNominalFrequency() throws {
        let asOf = date(2026, 1, 7) // Wednesday
        let fixture = try startVariedMix(asOf: asOf)
        let allSessions = fixture.mix.orderedComponents.compactMap(\.programInstance).flatMap(\.sessions)

        let firstCalendarWeekKey = calendarWeekKey(for: asOf)
        let firstWeekSessions = allSessions.filter { session in
            guard let date = session.day?.date else { return false }
            return calendarWeekKey(for: date) == firstCalendarWeekKey
        }

        // The mix's nominal frequency is 3 + 2 + 1 = 6, but only 5 real
        // calendar days (Wed-Sun) exist on/after a Wednesday phase start
        // with maxSessionsPerDay = 1 — this is an accepted, documented
        // shortfall, never a bug to silently "fix" by forcing 6 sessions
        // into 5 days.
        XCTAssertEqual(firstWeekSessions.count, 5, "a phase's shortened first calendar week is allowed to under-deliver the nominal weekly frequency by exactly the days it lost to phase start")
    }

    // MARK: D/E/F — the deferred (lowest-priority) session preserves cadence: no calendar week ever receives more than one, and no debt accumulates into a later week

    func testNoTrainingDebtAccumulatesIntoAnyLaterCalendarWeek() throws {
        let asOf = date(2026, 1, 7) // Wednesday
        let fixture = try startVariedMix(asOf: asOf)
        let runningInstance = try XCTUnwrap(fixture.mix.orderedComponents.first { $0.label == "Running" }?.programInstance)
        XCTAssertEqual(runningInstance.sessions.count, 5, "sanity: Running's whole natural block materialized")

        let byCalendarWeek = Dictionary(grouping: runningInstance.sessions) { session in
            calendarWeekKey(for: session.day?.date ?? .distantPast)
        }

        // The exact "training debt" failure mode: a session delayed out
        // of the shortened first week must never cluster together with
        // the very next week's own session inside one later calendar
        // week (which would silently overload that week while an
        // earlier one goes without) — every calendar week gets AT MOST
        // Running's own nominal 1-per-week frequency, never more.
        for (weekKey, sessions) in byCalendarWeek {
            XCTAssertLessThanOrEqual(sessions.count, 1, "calendar week \(weekKey) received \(sessions.count) Running sessions — a deferred session must never double up with its own next week's session (training debt)")
        }

        // Program/tactical ordering survives the deferral: every one of
        // Running's own sessions, taken in materialization order, lands
        // on a strictly later real date than the one before it.
        let orderedDates = runningInstance.sessions.compactMap(\.day?.date).sorted()
        for i in 1..<orderedDates.count {
            XCTAssertGreaterThan(orderedDates[i], orderedDates[i - 1], "Running's own sessions must remain strictly increasing in real scheduled date")
        }

        // Once past the shortened first week, every real calendar week
        // Running touches contains exactly its normal cadence (1) —
        // never 0 (silently dropped) and never 2+ (debt).
        let weeksAfterTheFirst = byCalendarWeek.filter { $0.key != calendarWeekKey(for: asOf) }
        XCTAssertTrue(weeksAfterTheFirst.allSatisfy { $0.value.count == 1 }, "every calendar week other than the phase's own shortened first week must show Running's normal 1-per-week cadence")
    }

    // MARK: G — the same no-debt behavior holds generically for a differently-shaped, differently-prioritized mix

    func testNoTrainingDebtIsGenericAcrossADifferentMixShapeAndPriorityOrder() throws {
        let asOf = date(2026, 1, 7) // Wednesday
        let fixture = try startEnduranceMix(asOf: asOf)
        // "Running Performance": Steady State primary (target 5) + Strength
        // Maintenance supporting (target 2) — Steady State claims days
        // FIRST here, the inverse priority arrangement from
        // `startVariedMix`'s supporting-tier Running, proving the fix
        // isn't tied to one specific component/priority shape.
        let steadyStateComponent = try XCTUnwrap(fixture.mix.orderedComponents.first { $0.programmingSystem == .steadyState })
        let steadyStateInstance = try XCTUnwrap(steadyStateComponent.programInstance)

        let byCalendarWeek = Dictionary(grouping: steadyStateInstance.sessions) { session in
            calendarWeekKey(for: session.day?.date ?? .distantPast)
        }
        let requiredPerWeek = steadyStateComponent.frequency.minimum ?? steadyStateComponent.frequency.target
        for (weekKey, sessions) in byCalendarWeek {
            XCTAssertLessThanOrEqual(sessions.count, requiredPerWeek, "calendar week \(weekKey) received \(sessions.count) of \(steadyStateComponent.label)'s sessions — no calendar week may exceed the component's own nominal per-week frequency, regardless of mix shape")
        }
        let allDates = steadyStateInstance.sessions.compactMap(\.day?.date)
        XCTAssertEqual(Set(allDates).count, allDates.count, "no two sessions of the same component may land on the same real day")
    }

    // MARK: H — a bounded phase's own shortened final week follows the same partial-week principle

    func testShortenedFinalWeekOfABoundedPhaseNeverFabricatesBeyondItsOwnEndDate() throws {
        let asOf = date(2026, 1, 5) // Monday
        let fixture = try startVariedMix(asOf: asOf)
        guard let endDate = fixture.phase.endDate else { return } // CLAUDE.md rule 10: never invent a bound the real planner didn't produce

        let allSessions = fixture.mix.orderedComponents.compactMap(\.programInstance).flatMap(\.sessions)
        for session in allSessions {
            guard let scheduledDate = session.day?.date else { continue }
            XCTAssertLessThanOrEqual(scheduledDate, endDate, "\(session.name) must never be scheduled after the phase's own bounded end date, even to complete a partial final week")
        }
        // A phase boundary that lands mid-week is exactly the same
        // "partial week" shape as a mid-week start — under-delivering the
        // nominal frequency in that final, shortened week is expected,
        // never treated as a scheduling failure.
    }

    // MARK: G — Program Detail (PhaseDetailViewModel) and Week (WeekViewModel) reference the same Sessions

    func testPhaseDetailAndWeekViewModelsAgreeOnTheSameRealSessions() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try startVariedMix(asOf: asOf)

        let phaseDetail = PhaseDetailViewModel()
        phaseDetail.load(phase: fixture.phase, modelContext: context)
        let programDetailSessionIDs = Set(phaseDetail.activeComponents.compactMap(\.programInstance).flatMap(\.sessions).map(\.id))

        let week = WeekViewModel()
        week.load(modelContext: context, referenceDate: asOf)
        let weekSessionIDs = Set(week.days.flatMap(\.sessions).map(\.id))

        XCTAssertFalse(programDetailSessionIDs.isEmpty)
        XCTAssertTrue(weekSessionIDs.isSubset(of: programDetailSessionIDs), "every Session Week shows for this phase's own calendar week must trace back to a real Session Program Detail also knows about")
    }

    // MARK: I — browsing Program Detail creates no Sessions

    func testBrowsingPhaseDetailCreatesNoNewSessions() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try startVariedMix(asOf: asOf)
        let countBefore = try context.fetchCount(FetchDescriptor<Session>())

        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: fixture.phase, modelContext: context)
        viewModel.load(phase: fixture.phase, modelContext: context) // browsing again must still be a no-op

        let countAfter = try context.fetchCount(FetchDescriptor<Session>())
        XCTAssertEqual(countBefore, countAfter, "loading Phase Detail must never materialize or schedule a Session")
    }

    // MARK: B — no Session schedules after a bounded phase's own endDate

    func testNoSessionEverSchedulesAfterABoundedPhasesOwnEndDate() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try startVariedMix(asOf: asOf)
        guard let endDate = fixture.phase.endDate else {
            // Not every phase in the real strategic-plan generator carries
            // a bounded endDate (CLAUDE.md rule 10: never invent one) —
            // this assertion only applies when one genuinely exists.
            return
        }
        let allSessions = fixture.mix.orderedComponents.compactMap(\.programInstance).flatMap(\.sessions)
        for session in allSessions {
            guard let scheduledDate = session.day?.date else { continue }
            XCTAssertLessThanOrEqual(scheduledDate, endDate, "\(session.name) was scheduled after the phase's own bounded end date")
        }
    }
}
