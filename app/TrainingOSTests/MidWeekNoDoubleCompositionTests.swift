import XCTest
import SwiftData
@testable import TrainingOS

/// R0 (Mid-Week Start / No-Double Production Bug), LOCKED CONTRACT ROUND:
/// proves the real dogfood case through the REAL production path —
/// `LongTermPlanner.buildCustomMix` (the athlete's explicit 3H+2FF
/// selection) -> `AcceptStrategicPlanUseCase` (which now applies
/// `LongTermPlanner.resolvedInitialPlanStartDate` for any brand-new,
/// non-superseding plan) -> `StartPhaseUseCase.start` (Functional Fitness
/// materializes immediately; Hypertrophy, being `.rmBased`, is deferred
/// pending source RM calibration) -> `CalibrationTestSupport
/// .completeAnyPendingCalibrationAndMaterialize` (the real "set your
/// starting weights" step) -> persisted `Session`s. Never a hand-built
/// scheduler-only fixture.
///
/// LOCKED PRODUCT CONTRACT (replaces two earlier, REJECTED models — see
/// `AcceptStrategicPlanUseCase.accept`'s own doc comment for the full
/// architectural reasoning): a brand-new plan's first source-backed
/// tactical week may only ever be a genuine full calendar week
/// (Monday-Sunday). If accepted on Monday, the program starts immediately.
/// If accepted Tuesday-Sunday, ZERO source-backed Sessions exist before
/// the following Monday — not carried forward, not dropped-and-doubled,
/// not fabricated as bootstrap content repeating real Week-0 material.
/// The following Monday begins a genuinely fresh, independent nominal
/// week (the athlete's full selected composition, exactly).
@MainActor
final class MidWeekNoDoubleCompositionTests: XCTestCase {
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

    private struct Candidates {
        let strength: [Exercise]
        let functionalFitness: [Exercise]
    }

    /// Mirrors `TacticalPlacementBoundaryTests.makeCandidates()` — REAL
    /// candidate exercises are required for Hypertrophy's `ExerciseSlot`s
    /// to actually resolve to concrete `Exercise`s; without them,
    /// `RequiredSourceCalibrationsUseCase.stillRequired` never finds a
    /// resolved exercise to require calibration for at all, and the
    /// deferred-materialization path this bug lives in is never exercised.
    private func makeCandidates() -> Candidates {
        func exercise(
            _ name: String, _ targets: [MuscleGroup] = [], _ movementFunctions: [MovementFunction] = [], _ functionalModality: FunctionalModality? = nil
        ) -> Exercise {
            let ex = Exercise(canonicalName: name, modality: .hypertrophy, equipment: "barbell", movementPattern: "test", primaryTargets: targets, movementFunctions: movementFunctions, functionalModality: functionalModality)
            context.insert(ex)
            return ex
        }
        let strength = [
            exercise("R0 Boundary Primary Shoulders", [.shoulders]),
            exercise("R0 Boundary Primary Quads", [.quadriceps]),
            exercise("R0 Boundary Primary Back", [.back]),
            exercise("R0 Boundary Paired Accessory", [.chest, .triceps]),
        ]
        let ff = [
            exercise("R0 Boundary FF Squat Lift", [], [.squatLoaded], .weightlifting),
            exercise("R0 Boundary FF Pull-up", [], [.gymnasticsPull], .gymnastics),
            exercise("R0 Boundary FF Bike", [], [.monostructural], .metabolicConditioning),
        ]
        return Candidates(strength: strength, functionalFitness: ff)
    }

    private func availability() -> UserAvailability {
        UserAvailability(trainingDaysPerWeek: 5, allowsDoubleSessions: false, maxSessionsPerDay: 1)
    }

    /// The real production path for the athlete's exact dogfood scenario:
    /// Build Muscle, 5 training days, no doubles, explicit 3H+2FF, plan
    /// accepted on `asOf`.
    @discardableResult
    private func startThreeHypertrophyTwoFunctionalFitness(asOf: Date, candidates: Candidates) throws -> (goal: Goal, phase: TrainingPhase, mix: TrainingMix) {
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .muscleGain, preferences: GoalPreferences(availableTrainingDaysPerWeek: 5, allowsDoubleSessions: false), createdAt: asOf)
        context.insert(goal)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        // The real production entry point (`AcceptStrategicPlanUseCase
        // .accept`, called with its default `alignFirstPhaseToFullCalendarWeek:
        // true`) — exactly what `StrategicPlanSelectionViewModel.acceptAndStart`
        // itself calls, never a special test-only path.
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: asOf)
        let phase = try XCTUnwrap(plan.orderedPhases.first)

        guard case .success(let mix) = LongTermPlanner.buildCustomMix(
            selections: [(style: .hypertrophy, frequency: 3), (style: .functionalFitness, frequency: 2)], capacity: 5
        ) else {
            XCTFail("3H+2FF must be a real, constructible composition")
            throw StartPhaseError.mixHasNoComponents
        }

        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let materializationContext = TacticalMaterializationContext(
            equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
            strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness,
            trainingEnvironment: environment
        )
        _ = try StartPhaseUseCase.start(
            phase: phase, mix: mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext, context: context
        )
        // The real "set your starting weights" step — completes Hypertrophy's
        // deferred calibration and invokes the SEPARATE, later
        // `materializeOnceCalibrationComplete` scheduling call this bug lives in.
        try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: phase, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext, asOf: asOf, context: context
        )
        return (goal, phase, mix)
    }

    private func normalizedDay(_ date: Date) -> Date { Calendar.current.startOfDay(for: date) }

    private func allSessions(mix: TrainingMix) -> [Session] {
        mix.orderedComponents.compactMap(\.programInstance).flatMap(\.sessions)
    }

    // MARK: A — the real dogfood case: Friday acceptance

    func testFridayAcceptance_ZeroSessionsBeforeMonday_FreshFullCadenceMondayOnward() throws {
        let friday = date(2026, 1, 2) // confirmed Friday
        let candidates = makeCandidates()
        let (goal, phase, mix) = try startThreeHypertrophyTwoFunctionalFitness(asOf: friday, candidates: candidates)

        // The phase's own real, persisted start truthfully anchors to
        // the resolved Monday — never lies that the tactical program
        // began Friday when it did not.
        let expectedMonday = date(2026, 1, 5)
        XCTAssertEqual(normalizedDay(phase.startDate), normalizedDay(expectedMonday), "a brand-new plan's phase must truthfully anchor to the resolved Monday, not the real acceptance day")

        let sessions = allSessions(mix: mix)
        XCTAssertEqual(sessions.count, 5, "exactly 3 Hypertrophy + 2 Functional Fitness sessions — never fabricated, never dropped")

        // ZERO sessions Friday/Saturday/Sunday.
        let saturday = normalizedDay(date(2026, 1, 3))
        let sunday = normalizedDay(date(2026, 1, 4))
        let fridayNormalized = normalizedDay(friday)
        for session in sessions {
            let day = normalizedDay(session.day?.date ?? .distantPast)
            XCTAssertNotEqual(day, fridayNormalized, "zero planned sessions must exist on the real acceptance Friday")
            XCTAssertNotEqual(day, saturday, "zero planned sessions must exist on the partial-start Saturday")
            XCTAssertNotEqual(day, sunday, "zero planned sessions must exist on the partial-start Sunday")
        }

        // No day anywhere exceeds capacity — the hard no-double invariant.
        let byDay = Dictionary(grouping: sessions) { normalizedDay($0.day?.date ?? .distantPast) }
        XCTAssertEqual(byDay.values.filter { $0.count > 1 }.count, 0, "no calendar day may ever hold more than 1 planned Session for a no-doubles athlete")

        // Following Monday->Sunday: exactly 5 sessions, 5 distinct days,
        // all within that one real calendar week.
        let monday = normalizedDay(expectedMonday)
        let followingSunday = normalizedDay(date(2026, 1, 11))
        let inFollowingWeek = sessions.filter { let d = normalizedDay($0.day?.date ?? .distantPast); return d >= monday && d <= followingSunday }
        XCTAssertEqual(inFollowingWeek.count, 5, "the following Monday->Sunday must contain exactly 5 planned Sessions — a genuinely fresh, independent full nominal week")
        XCTAssertEqual(Set(inFollowingWeek.map { normalizedDay($0.day?.date ?? .distantPast) }).count, 5, "5 distinct calendar days")

        // Zero false missed sessions / zero fabricated debt: every one of
        // the 5 real sessions is still `.scheduled`.
        for session in sessions {
            XCTAssertEqual(session.status, .scheduled, "\(session.name) must not be marked missed/non-adherent purely due to the partial-start-week rule")
        }

        // Composition authority preserved exactly.
        let hypertrophyCount = sessions.filter { $0.programInstance?.programDefinition?.name.contains("Hypertrophy") == true }.count
        let ffCount = sessions.count - hypertrophyCount
        XCTAssertEqual(hypertrophyCount, 3)
        XCTAssertEqual(ffCount, 2)

        // Source session order coherent: each component's own sessions
        // still land on strictly increasing, never-repeated calendar days.
        for instance in mix.orderedComponents.compactMap(\.programInstance) {
            let dates = instance.sessions.compactMap { $0.day?.date }.sorted()
            XCTAssertEqual(Set(dates).count, dates.count, "\(instance.programDefinition?.name ?? "?")'s own sessions must never share a calendar day")
        }

        XCTAssertEqual(goal.primaryType, .muscleGain, "the goal itself is never mutated by the partial-start-week rule")
    }

    // MARK: no-double survives the deferred-calibration second pass, isolated from the boundary rule

    func testNoDoubleContractPreservedAcrossTheDeferredCalibrationPass() throws {
        let monday = date(2026, 1, 5) // accept ON Monday — normal immediate start, isolates the no-double proof from the boundary rule
        let candidates = makeCandidates()
        let (_, _, mix) = try startThreeHypertrophyTwoFunctionalFitness(asOf: monday, candidates: candidates)

        let sessions = allSessions(mix: mix)
        XCTAssertEqual(sessions.count, 5)
        let byDay = Dictionary(grouping: sessions) { normalizedDay($0.day?.date ?? .distantPast) }
        XCTAssertEqual(byDay.values.filter { $0.count > 1 }.count, 0, "no-double contract: no two Sessions may share a calendar day for a no-doubles athlete, even across the FF-immediate + Hypertrophy-deferred two-pass materialization")
        XCTAssertEqual(Set(byDay.keys).count, 5, "5 distinct calendar days for 5 real sessions")
    }

    // MARK: B — Wednesday acceptance: zero sessions before Monday even though 5 real days (Wed-Sun) exist

    func testWednesdayAcceptance_DoesNotSqueezeSessionsIntoTheAvailablePartialWeek() throws {
        let wednesday = date(2026, 1, 7) // confirmed Wednesday
        let candidates = makeCandidates()
        let (_, phase, mix) = try startThreeHypertrophyTwoFunctionalFitness(asOf: wednesday, candidates: candidates)

        let expectedMonday = date(2026, 1, 12)
        XCTAssertEqual(normalizedDay(phase.startDate), normalizedDay(expectedMonday), "even with 5 real available days (Wed-Sun) exactly matching the mix's total, the locked contract begins the program the following Monday — never squeezed into the partial week")

        let sessions = allSessions(mix: mix)
        XCTAssertEqual(sessions.count, 5)
        let monday = normalizedDay(expectedMonday)
        for session in sessions {
            let day = normalizedDay(session.day?.date ?? .distantPast)
            XCTAssertGreaterThanOrEqual(day, monday, "zero sessions before the following Monday, even though Wed-Sun had room")
        }
        XCTAssertEqual(Set(sessions.map { normalizedDay($0.day?.date ?? .distantPast) }).count, 5, "the following full week supplies exactly 5 distinct real days")
        let byDay = Dictionary(grouping: sessions) { normalizedDay($0.day?.date ?? .distantPast) }
        XCTAssertEqual(byDay.values.filter { $0.count > 1 }.count, 0)
    }

    // MARK: C — Sunday acceptance: zero sessions before Monday

    func testSundayAcceptance_ZeroSessionsBeforeMonday() throws {
        let sunday = date(2026, 1, 4) // confirmed Sunday
        let candidates = makeCandidates()
        let (_, phase, mix) = try startThreeHypertrophyTwoFunctionalFitness(asOf: sunday, candidates: candidates)

        let expectedMonday = date(2026, 1, 5)
        XCTAssertEqual(normalizedDay(phase.startDate), normalizedDay(expectedMonday))

        let sessions = allSessions(mix: mix)
        XCTAssertEqual(sessions.count, 5)
        let sundayNormalized = normalizedDay(sunday)
        XCTAssertFalse(sessions.contains { normalizedDay($0.day?.date ?? .distantPast) == sundayNormalized }, "zero sessions on the real acceptance Sunday")
        let monday = normalizedDay(expectedMonday)
        XCTAssertTrue(sessions.allSatisfy { normalizedDay($0.day?.date ?? .distantPast) >= monday }, "every session lands on or after the following Monday")
    }

    // MARK: D — Monday acceptance: normal immediate start unchanged

    func testMondayAcceptance_NormalImmediateStartUnchanged() throws {
        let monday = date(2026, 1, 5) // confirmed Monday
        let candidates = makeCandidates()
        let (_, phase, mix) = try startThreeHypertrophyTwoFunctionalFitness(asOf: monday, candidates: candidates)

        XCTAssertEqual(normalizedDay(phase.startDate), normalizedDay(monday), "a Monday acceptance starts immediately — no shift applied")

        let sessions = allSessions(mix: mix)
        XCTAssertEqual(sessions.count, 5)
        let byDay = Dictionary(grouping: sessions) { normalizedDay($0.day?.date ?? .distantPast) }
        XCTAssertEqual(byDay.values.filter { $0.count > 1 }.count, 0, "a full-week Monday start must never double-book either")
        XCTAssertEqual(Set(byDay.keys).count, 5, "5 distinct calendar days for 5 real sessions")
        XCTAssertTrue(byDay.keys.allSatisfy { $0 >= normalizedDay(monday) }, "every session lands on or after the real Monday acceptance day")
    }
}
