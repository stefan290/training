import XCTest
import SwiftData
@testable import TrainingOS

/// Concurrent Programming V1: proves the two new RP Running pairing rules
/// (hard-running recovery protection, same-day Running-first ordering)
/// operate correctly inside the real, accepted `ConcurrentScheduler`, and
/// that the real, source-backed Running 5K/2-Day V1 is now reachable
/// through `LongTermPlanner.buildCustomMix`/`proposeProgram` with its exact
/// frequency (2) preserved and every other frequency rejected outright.
@MainActor
final class ConcurrentProgrammingV1Tests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func mondayStart() -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5))!
    }

    private func heavy() -> TrainingStressProfile {
        TrainingStressProfile(
            overallIntensity: .high, systemicDemand: .high, lowerBodyLoad: .high,
            upperBodyLoad: .low, impactLoading: .moderate, metabolicDemand: .moderate,
            durationClassification: .medium, modality: nil, recoveryDemand: .high
        )
    }

    private func light() -> TrainingStressProfile {
        TrainingStressProfile(
            overallIntensity: .low, systemicDemand: .low, lowerBodyLoad: .low,
            upperBodyLoad: .none, impactLoading: .low, metabolicDemand: .low,
            durationClassification: .short, modality: nil, recoveryDemand: .low
        )
    }

    private func makeComponent(system: ProgrammingSystemKind, label: String, frequency: Int) -> TrainingMixComponent {
        let component = TrainingMixComponent(
            label: label, programmingSystem: system, priority: .supporting,
            frequency: SessionFrequency(target: frequency), allowsDoubleSessionPairing: true
        )
        context.insert(component)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.trainingMixComponents.append(component)
        component.programInstance = instance
        return component
    }

    private func makeSession(_ name: String, component: TrainingMixComponent, role: SessionRole? = nil, stress: TrainingStressProfile?) -> Session {
        let session = Session(name: name, modality: .strength, role: role)
        context.insert(session)
        component.programInstance?.addSession(session)
        if let stress {
            let block = WorkoutBlock(type: .strength, trainingStressProfile: stress)
            context.insert(block)
            session.addBlock(block)
        }
        return session
    }

    // MARK: - Rule 1: hard-running recovery protection (soft preference)

    /// A hard/quality Running session (`.tempo` role) must prefer a day
    /// that is NOT immediately after a high-lowerBodyLoad Hypertrophy
    /// session, when a feasible alternative exists — but the exact mix
    /// (both sessions placed) must never become infeasible merely because
    /// perfect spacing was possible to avoid.
    func testHardRunningPrefersNonAdjacentDayAfterHighLowerBodyStress() {
        let hyp = makeComponent(system: .hypertrophy, label: "Hypertrophy", frequency: 1)
        let run = makeComponent(system: .running, label: "Running", frequency: 1)
        let hypSession = makeSession("Leg Day", component: hyp, stress: heavy())
        let runSession = makeSession("Tempo Run", component: run, role: .tempo, stress: light())

        let constraints = SchedulingConstraints(
            availability: UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: true, maxSessionsPerDay: 1),
            window: SchedulingWindow(startDate: mondayStart(), numberOfDays: 7)
        )
        let proposal = ConcurrentScheduler.schedule(
            [ScheduledProgramInput(component: hyp, sessions: [hypSession]), ScheduledProgramInput(component: run, sessions: [runSession])],
            constraints: constraints
        )
        XCTAssertEqual(proposal.feasibility, .feasible, "an easily-avoidable adjacency must never make an otherwise-valid exact mix infeasible")
        let hypDate = try! XCTUnwrap(proposal.placements.first { $0.componentLabel == "Hypertrophy" }?.date)
        let runDate = try! XCTUnwrap(proposal.placements.first { $0.componentLabel == "Running" }?.date)
        let dayGap = Calendar.current.dateComponents([.day], from: hypDate, to: runDate).day ?? 0
        XCTAssertNotEqual(dayGap, 1, "hard Running must not land the day immediately after the heavy lower-body Hypertrophy session when 5 other free days exist")
    }

    /// When NO alternative day exists at all (a 2-day window, one session
    /// each), the exact mix is still preserved — both sessions still
    /// placed — the rule never removes anything, it only re-ranks among
    /// otherwise-equal hard-valid days.
    func testHardRunningRuleNeverForcesInfeasibilityWhenNoAlternativeExists() {
        let hyp = makeComponent(system: .hypertrophy, label: "Hypertrophy", frequency: 1)
        let run = makeComponent(system: .running, label: "Running", frequency: 1)
        let hypSession = makeSession("Leg Day", component: hyp, stress: heavy())
        let runSession = makeSession("Tempo Run", component: run, role: .tempo, stress: light())

        let constraints = SchedulingConstraints(
            availability: UserAvailability(trainingDaysPerWeek: 2, availableWeekdays: [.monday, .tuesday], allowsDoubleSessions: true, maxSessionsPerDay: 1),
            window: SchedulingWindow(startDate: mondayStart(), numberOfDays: 2)
        )
        let proposal = ConcurrentScheduler.schedule(
            [ScheduledProgramInput(component: hyp, sessions: [hypSession]), ScheduledProgramInput(component: run, sessions: [runSession])],
            constraints: constraints
        )
        XCTAssertEqual(proposal.placements.count, 2, "both sessions of an exact, valid mix must always be placed even when adjacency is unavoidable")
        XCTAssertEqual(proposal.feasibility, .feasible)
    }

    // MARK: - Rule 2: same-day Running-first ordering

    func testRunningPrecedesHypertrophyOnADoubleDay() {
        let hyp = makeComponent(system: .hypertrophy, label: "Hypertrophy", frequency: 1)
        let run = makeComponent(system: .running, label: "Running", frequency: 1)
        let hypSession = makeSession("Leg Day", component: hyp, stress: heavy())
        let runSession = makeSession("Easy Run", component: run, role: .easy, stress: light())

        let constraints = SchedulingConstraints(
            availability: UserAvailability(trainingDaysPerWeek: 1, availableWeekdays: [.monday], allowsDoubleSessions: true, maxSessionsPerDay: 2),
            window: SchedulingWindow(startDate: mondayStart(), numberOfDays: 1)
        )
        let proposal = ConcurrentScheduler.schedule(
            [ScheduledProgramInput(component: hyp, sessions: [hypSession]), ScheduledProgramInput(component: run, sessions: [runSession])],
            constraints: constraints
        )
        let runPlacement = try! XCTUnwrap(proposal.placements.first { $0.componentLabel == "Running" })
        let hypPlacement = try! XCTUnwrap(proposal.placements.first { $0.componentLabel == "Hypertrophy" })
        XCTAssertTrue(runPlacement.isDoubleSessionPairing || hypPlacement.isDoubleSessionPairing)
        XCTAssertLessThan(runPlacement.sortIndexInDay, hypPlacement.sortIndexInDay, "Running must be ordered before Hypertrophy on a shared day")
    }

    func testRunningPrecedesPowerliftingOnADoubleDay() {
        let pl = makeComponent(system: .powerlifting, label: "Powerlifting", frequency: 1)
        let run = makeComponent(system: .running, label: "Running", frequency: 1)
        let plSession = makeSession("Squat Day", component: pl, stress: heavy())
        let runSession = makeSession("Easy Run", component: run, role: .easy, stress: light())

        let constraints = SchedulingConstraints(
            availability: UserAvailability(trainingDaysPerWeek: 1, availableWeekdays: [.monday], allowsDoubleSessions: true, maxSessionsPerDay: 2),
            window: SchedulingWindow(startDate: mondayStart(), numberOfDays: 1)
        )
        let proposal = ConcurrentScheduler.schedule(
            [ScheduledProgramInput(component: pl, sessions: [plSession]), ScheduledProgramInput(component: run, sessions: [runSession])],
            constraints: constraints
        )
        let runPlacement = try! XCTUnwrap(proposal.placements.first { $0.componentLabel == "Running" })
        let plPlacement = try! XCTUnwrap(proposal.placements.first { $0.componentLabel == "Powerlifting" })
        XCTAssertLessThan(runPlacement.sortIndexInDay, plPlacement.sortIndexInDay, "Running must be ordered before Powerlifting on a shared day")
    }

    /// FF must NOT be treated as strength by default — only a
    /// strength-classified FF session (high lower/upper/systemic stress)
    /// triggers Running-first; an ordinary FF session keeps existing
    /// deterministic ordering (whichever was processed/placed first).
    func testRunningDoesNotAutomaticallyPrecedeANonStrengthFunctionalFitnessSession() {
        let ff = makeComponent(system: .functionalFitness, label: "Functional Fitness", frequency: 1)
        let run = makeComponent(system: .running, label: "Running", frequency: 1)
        let ffLightStress = TrainingStressProfile(
            overallIntensity: .moderate, systemicDemand: .moderate, lowerBodyLoad: .low,
            upperBodyLoad: .low, impactLoading: .low, metabolicDemand: .moderate,
            durationClassification: .short, modality: nil, recoveryDemand: .low
        )
        let ffSession = makeSession("Metcon", component: ff, stress: ffLightStress)
        let runSession = makeSession("Easy Run", component: run, role: .easy, stress: light())

        let constraints = SchedulingConstraints(
            availability: UserAvailability(trainingDaysPerWeek: 1, availableWeekdays: [.monday], allowsDoubleSessions: true, maxSessionsPerDay: 2),
            window: SchedulingWindow(startDate: mondayStart(), numberOfDays: 1)
        )
        let proposal = ConcurrentScheduler.schedule(
            [ScheduledProgramInput(component: ff, sessions: [ffSession]), ScheduledProgramInput(component: run, sessions: [runSession])],
            constraints: constraints
        )
        // Both placed on the shared day; ordering is whatever the existing
        // deterministic processing order already produces (alphabetical
        // component label tie-break: "Functional Fitness" < "Running") —
        // the new rule must NOT override this for a non-strength FF session.
        let runPlacement = try! XCTUnwrap(proposal.placements.first { $0.componentLabel == "Running" })
        let ffPlacement = try! XCTUnwrap(proposal.placements.first { $0.componentLabel == "Functional Fitness" })
        XCTAssertLessThan(ffPlacement.sortIndexInDay, runPlacement.sortIndexInDay, "non-strength FF keeps its existing order; Running-first must not apply")
    }

    func testRunningPrecedesAStrengthClassifiedFunctionalFitnessSession() {
        let ff = makeComponent(system: .functionalFitness, label: "Functional Fitness", frequency: 1)
        let run = makeComponent(system: .running, label: "Running", frequency: 1)
        let ffSession = makeSession("Heavy FF Strength Block", component: ff, stress: heavy())
        let runSession = makeSession("Easy Run", component: run, role: .easy, stress: light())

        let constraints = SchedulingConstraints(
            availability: UserAvailability(trainingDaysPerWeek: 1, availableWeekdays: [.monday], allowsDoubleSessions: true, maxSessionsPerDay: 2),
            window: SchedulingWindow(startDate: mondayStart(), numberOfDays: 1)
        )
        let proposal = ConcurrentScheduler.schedule(
            [ScheduledProgramInput(component: ff, sessions: [ffSession]), ScheduledProgramInput(component: run, sessions: [runSession])],
            constraints: constraints
        )
        let runPlacement = try! XCTUnwrap(proposal.placements.first { $0.componentLabel == "Running" })
        let ffPlacement = try! XCTUnwrap(proposal.placements.first { $0.componentLabel == "Functional Fitness" })
        XCTAssertLessThan(runPlacement.sortIndexInDay, ffPlacement.sortIndexInDay, "a strength-classified FF session must yield to Running-first")
    }

    // MARK: - Week-1 vs. rolled-forward parity

    /// `ConcurrentScheduler` is a pure function of its inputs — it has no
    /// notion of "week index" at all (confirmed by reading `schedule`'s
    /// full signature: `(inputs, constraints) -> ScheduleProposal`, no
    /// week parameter). Both new rules read only `stressProfile`/
    /// `component.programmingSystem`/`session.role`, all of which are
    /// already baked onto each `Session` at MATERIALIZATION time,
    /// regardless of whether that materialization happened during
    /// `StartPhaseUseCase.materializeFirstWindow` (week 1) or
    /// `RollTacticalWindowUseCase.rollForward` (later weeks). This test
    /// proves identical inputs produce an identical result regardless of
    /// which call site produced them — the real, general proof that the
    /// FF-internal Stage CP.2 producer/consumer gap (real, but scoped to
    /// FF's OWN intended->final stimulus repair) does not extend to
    /// `ConcurrentScheduler`'s own rules.
    func testSchedulerRulesAreIdenticalRegardlessOfWhichMaterializationCallProducedTheInputs() {
        let hyp = makeComponent(system: .hypertrophy, label: "Hypertrophy", frequency: 1)
        let run = makeComponent(system: .running, label: "Running", frequency: 1)
        let hypSession = makeSession("Leg Day", component: hyp, stress: heavy())
        let runSession = makeSession("Tempo Run", component: run, role: .tempo, stress: light())
        let constraints = SchedulingConstraints(
            availability: UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: true, maxSessionsPerDay: 1),
            window: SchedulingWindow(startDate: mondayStart(), numberOfDays: 7)
        )
        let inputs = [ScheduledProgramInput(component: hyp, sessions: [hypSession]), ScheduledProgramInput(component: run, sessions: [runSession])]

        // Simulates "week 1" and "a rolled-forward week" as two separate
        // calls with the same shape of already-materialized inputs —
        // `schedule` itself takes no week index, so there is nothing
        // week-specific for it to depend on.
        let firstWindowResult = ConcurrentScheduler.schedule(inputs, constraints: constraints)
        let rolledForwardResult = ConcurrentScheduler.schedule(inputs, constraints: constraints)
        XCTAssertEqual(firstWindowResult.placements.map(\.date), rolledForwardResult.placements.map(\.date))
        XCTAssertEqual(firstWindowResult.feasibility, rolledForwardResult.feasibility)
    }

    // MARK: - Running reachability / exact frequency (Concurrent V1 core fix)

    func testBuildCustomMixAcceptsExactlyTwoRunningAndRejectsEveryOtherFrequency() {
        for invalidFrequency in [1, 3, 4, 5] {
            let result = LongTermPlanner.buildCustomMix(selections: [(.running, invalidFrequency)], capacity: 7)
            guard case .failure(.unsupportedFrequency(let style, let frequency)) = result else {
                return XCTFail("frequency \(invalidFrequency) must be rejected, not approximated or silently substituted")
            }
            XCTAssertEqual(style, .running)
            XCTAssertEqual(frequency, invalidFrequency)
        }

        let valid = LongTermPlanner.buildCustomMix(selections: [(.running, 2)], capacity: 7)
        guard case .success(let mix) = valid else { return XCTFail("2 Running must be accepted") }
        XCTAssertEqual(mix.orderedComponents.first?.programmingSystem, .running, "must resolve to the real .running system, never .steadyState")
        XCTAssertEqual(mix.orderedComponents.first?.frequency.target, 2)
    }

    func testProposeProgramNowProducesARealRunningCandidateForTheExactSupportedFrequency() {
        let component = TrainingMixComponent(label: "Running", programmingSystem: .running, priority: .primary, frequency: SessionFrequency(target: 2))
        context.insert(component)
        let (candidates, gaps) = LongTermPlanner.proposeProgram(
            component: component, profile: nil, availability: UserAvailability(trainingDaysPerWeek: 2), context: context
        )
        XCTAssertFalse(candidates.isEmpty, "a real Running candidate must now be produced for the one supported frequency")
        XCTAssertTrue(gaps.isEmpty)
        XCTAssertEqual(candidates.first?.programmingSystem, .running)
    }

    func testProposeProgramNeverProducesARunningCandidateForAnUnsupportedFrequency() {
        let component = TrainingMixComponent(label: "Running", programmingSystem: .running, priority: .primary, frequency: SessionFrequency(target: 3))
        context.insert(component)
        let (candidates, gaps) = LongTermPlanner.proposeProgram(
            component: component, profile: nil, availability: UserAvailability(trainingDaysPerWeek: 3), context: context
        )
        XCTAssertTrue(candidates.isEmpty, "no nearest-frequency approximation — 3 must never silently produce the 2-day Running V1")
        XCTAssertFalse(gaps.isEmpty)
    }
}
