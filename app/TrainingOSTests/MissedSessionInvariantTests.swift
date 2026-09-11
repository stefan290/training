import XCTest
import SwiftData
@testable import TrainingOS

/// Concurrent Programming V1: CHARACTERIZATION of current, unmodified
/// production behavior when a Session inside a concurrent (multi-
/// component) week is missed — written BEFORE any missed-session code
/// change, per this checkpoint's own discipline (empirical proof before
/// any fix). Exercises the real `RollTacticalWindowUseCase`/
/// `ProgramWeekGrouping` pipeline directly (the same harness pattern as
/// `CrossModalityFunctionalFitnessProgrammingTests`), never a mock
/// scheduler.
///
/// FINDING (confirmed by reading `ProgramWeekGrouping.nextWeekIndex` and
/// `RollTacticalWindowUseCase.rollForward`/`materializeFirstWindow`
/// directly): neither reads `Session.status` anywhere. "Which week is
/// next" is determined purely by whether real, already-materialized
/// Sessions exist for a given 7-day bucket — never by whether those
/// Sessions were completed, missed, skipped, or abandoned. This means the
/// V1 product rule the directive asks for ("a missed session must not
/// silently rewrite the athlete's plan") is ALREADY the current, real
/// behavior for every concurrent component (Hypertrophy, Powerlifting,
/// Functional Fitness, Running) — nothing here needed a code change; these
/// tests LOCK today's real, correct behavior in place, per the directive's
/// own instruction ("if current behavior already matches this, lock it
/// with tests").
@MainActor
final class MissedSessionInvariantTests: XCTestCase {
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

    private func exercise(_ name: String, targets: [MuscleGroup]) -> Exercise {
        Exercise(canonicalName: name, modality: .hypertrophy, equipment: "barbell", movementPattern: "test", primaryTargets: targets)
    }

    private func resolveAllSlots(in definition: ProgramDefinition, to exercise: Exercise) {
        for templateSession in definition.orderedTemplateSessions {
            for blockTemplate in templateSession.orderedBlockTemplates {
                for template in blockTemplate.orderedPrescriptionTemplates {
                    template.exerciseSlot?.resolvedExercise = exercise
                }
            }
        }
    }

    private func heavySquatMaterializableStimulus() -> Stimulus {
        Stimulus(
            targetDurationDomain: .medium, intensity: .high, loading: .heavy,
            movementFunctions: [.squatLoaded], movementModalityMix: [],
            skillDemand: .moderate, systemicDemand: .high, scoreType: .load
        )
    }

    private func makeHypertrophyComponent(label: String, priority: GoalPriority, startDate: Date) throws -> TrainingMixComponent {
        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 1, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: context
        )
        resolveAllSlots(in: definition, to: exercise("Back Squat", targets: [.quadriceps, .glutes]))
        let instance = ProgramInstance(ownerUserID: ownerUserID, startDate: startDate)
        context.insert(instance)
        instance.programDefinition = definition
        let component = TrainingMixComponent(
            label: label, programmingSystem: .hypertrophy, priority: priority,
            adaptationObjectives: [.muscleGain], frequency: SessionFrequency(target: 1)
        )
        context.insert(component)
        component.programInstance = instance
        return component
    }

    private func makeFunctionalFitnessComponent(label: String, priority: GoalPriority, startDate: Date) -> TrainingMixComponent {
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 2, targetStimulus: heavySquatMaterializableStimulus(), format: .maxLoad,
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false, isDynamicallyComposed: false
        )
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID, startDate: startDate)
        context.insert(instance)
        instance.programDefinition = definition
        let component = TrainingMixComponent(
            label: label, programmingSystem: .functionalFitness, priority: priority,
            adaptationObjectives: [.workCapacity, .aerobicCapacity, .power], frequency: SessionFrequency(target: 1)
        )
        context.insert(component)
        component.programInstance = instance
        return component
    }

    private func makeRunningComponent(label: String, priority: GoalPriority, startDate: Date) throws -> TrainingMixComponent {
        let configuration = RunningBuiltInLibrary.all[0].configuration
        let definition = try RunningProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test fixture"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID, startDate: startDate)
        context.insert(instance)
        instance.programDefinition = definition
        let component = TrainingMixComponent(
            label: label, programmingSystem: .running, priority: priority,
            frequency: SessionFrequency(target: configuration.daysPerWeek)
        )
        context.insert(component)
        component.programInstance = instance
        // Running materializes its whole 13-relative-week block up front,
        // exactly like production's `RollTacticalWindowUseCase
        // .materializeFirstWindow` — real path, not a bespoke fixture.
        try RollTacticalWindowUseCase.materializeFirstWindow(
            system: .running, definition: definition, instance: instance, startDate: startDate,
            ownerUserID: ownerUserID, performanceProfile: nil,
            materializationContext: materializationContext(), context: context
        )
        return component
    }

    private func materializationContext() -> TacticalMaterializationContext {
        TacticalMaterializationContext(
            equipmentProfile: equipment, strengthCandidateExercises: [], functionalFitnessCandidateExercises: [],
            trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)
        )
    }

    private func availability() -> UserAvailability {
        UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1)
    }

    // MARK: - Question 1-2: is a missed session moved? are later sessions moved?

    /// Marks a Hypertrophy week-0 session `.missed`, then rolls forward.
    /// The missed session's own status and date must remain exactly as
    /// they were — `rollForward` never revisits an already-materialized
    /// Session.
    func testMissedHypertrophySessionIsNeverMovedOrReinterpretedByRollForward() throws {
        let asOf = date(2026, 1, 5)
        let strength = try makeHypertrophyComponent(label: "Strength", priority: .primary, startDate: asOf)
        let ff = makeFunctionalFitnessComponent(label: "Functional Fitness", priority: .supporting, startDate: asOf)
        let mix = TrainingMix(kind: .selected, name: "Missed Session Fixture")
        context.insert(mix)
        mix.addComponent(strength)
        mix.addComponent(ff)

        // Materialize + schedule week 0 first (mirrors `StartPhaseUseCase`'s
        // real first-window call), so there is a real, already-placed
        // Session to mark missed.
        let week0Strength = try RollTacticalWindowUseCase.materializeFirstWindow(
            system: .hypertrophy, definition: strength.programInstance!.programDefinition!, instance: strength.programInstance!,
            startDate: asOf, ownerUserID: ownerUserID, performanceProfile: nil, materializationContext: materializationContext(), context: context
        )
        let week0FF = try RollTacticalWindowUseCase.materializeFirstWindow(
            system: .functionalFitness, definition: ff.programInstance!.programDefinition!, instance: ff.programInstance!,
            startDate: asOf, ownerUserID: ownerUserID, performanceProfile: nil, materializationContext: materializationContext(), context: context
        )
        let week0Proposal = SchedulingPipeline.propose(
            mix: mix,
            inputs: [ScheduledProgramInput(component: strength, sessions: week0Strength), ScheduledProgramInput(component: ff, sessions: week0FF)],
            constraints: SchedulingConstraints(availability: availability(), window: SchedulingWindow(startDate: asOf, numberOfDays: 7))
        )
        try AcceptScheduleProposalUseCase.accept(week0Proposal.proposal, ownerUserID: ownerUserID, context: context)

        let missedSession = try XCTUnwrap(week0Strength.first)
        missedSession.status = .missed
        let originalDate = missedSession.day?.date
        let originalDayID = missedSession.day?.id
        let originalFrequency = strength.frequency.target

        let rollForwardDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: asOf))
        let result = try XCTUnwrap(RollTacticalWindowUseCase.rollForward(
            mix: mix, asOf: rollForwardDate, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext(), context: context
        ))

        // Q1/Q2: the missed session itself is untouched — never moved,
        // never re-dated, status never silently reset back to `.scheduled`.
        XCTAssertEqual(missedSession.status, .missed, "a missed session's status must never be silently reset by a later roll-forward")
        XCTAssertEqual(missedSession.day?.date, originalDate, "a missed session must never be moved to a different calendar day")
        XCTAssertEqual(missedSession.day?.id, originalDayID)

        // Q3/Q4: the remaining concurrent week is not "recomputed" around
        // the miss, and frequency is never silently changed.
        XCTAssertEqual(strength.frequency.target, originalFrequency, "component frequency must never change because of a missed session")

        // Q5: the next tactical window (week 1) still materializes
        // normally — a miss does not block or alter subsequent progression.
        let week1Strength = try XCTUnwrap(result.newSessionsByComponent[strength.id])
        XCTAssertEqual(week1Strength.count, week0Strength.count, "week 1 materializes with the same real cadence regardless of week 0's completion status")

        // Q7: source-backed session order/content for week 1 is exactly
        // what an uninterrupted week would have produced — never altered
        // by the sibling miss.
        XCTAssertEqual(week1Strength.first?.name, week0Strength.first?.name, "a missed prior week never changes subsequent source-backed session identity/order")
    }

    /// Q6: does a missed session create a NEW cross-component recovery
    /// conflict? `rollForward`'s Stage CP.2 producer/consumer pass only
    /// ever reads `SessionStressComposer.compose` of the sessions it JUST
    /// materialized THIS call (never a completed/missed/skipped session
    /// from a prior week) — so a missed Hypertrophy session cannot, even
    /// in principle, alter the FF sibling's same-week eligibility check.
    func testMissedHypertrophySessionNeverAltersSiblingFunctionalFitnessEligibility() throws {
        let asOf = date(2026, 1, 5)
        let strength = try makeHypertrophyComponent(label: "Strength", priority: .primary, startDate: asOf)
        let ff = makeFunctionalFitnessComponent(label: "Functional Fitness", priority: .supporting, startDate: asOf)
        let mix = TrainingMix(kind: .selected, name: "Missed Session Sibling Fixture")
        context.insert(mix)
        mix.addComponent(strength)
        mix.addComponent(ff)

        let week0Strength = try RollTacticalWindowUseCase.materializeFirstWindow(
            system: .hypertrophy, definition: strength.programInstance!.programDefinition!, instance: strength.programInstance!,
            startDate: asOf, ownerUserID: ownerUserID, performanceProfile: nil, materializationContext: materializationContext(), context: context
        )
        week0Strength.first?.status = .missed

        let rollForwardDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: asOf))
        let result = try XCTUnwrap(RollTacticalWindowUseCase.rollForward(
            mix: mix, asOf: rollForwardDate, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext(), context: context
        ))

        // The FF sibling's week-1 stimulus is identical to the baseline
        // "moderate early-week strength stress leaves FF eligible" case
        // proven in `CrossModalityFunctionalFitnessProgrammingTests` —
        // week 0's `.missed` status (on a DIFFERENT week's session) plays
        // no role at all in this computation.
        let ffSession = try XCTUnwrap(result.newSessionsByComponent[ff.id]?.first)
        let ffStimulus = try XCTUnwrap(ffSession.orderedBlocks.first { $0.type == .functionalFitness }?.functionalFitnessPrescription?.stimulus)
        XCTAssertEqual(ffStimulus, heavySquatMaterializableStimulus(), "a sibling's missed status from a prior week must never influence this week's cross-component stress reasoning")
    }

    /// A missed FUNCTIONAL FITNESS session: same invariant, opposite
    /// component. Also confirms `adaptationObjectives`/component identity
    /// survive completely untouched.
    func testMissedFunctionalFitnessSessionIsNeverMovedOrReinterpretedByRollForward() throws {
        let asOf = date(2026, 1, 5)
        let strength = try makeHypertrophyComponent(label: "Strength", priority: .primary, startDate: asOf)
        let ff = makeFunctionalFitnessComponent(label: "Functional Fitness", priority: .supporting, startDate: asOf)
        let mix = TrainingMix(kind: .selected, name: "Missed FF Fixture")
        context.insert(mix)
        mix.addComponent(strength)
        mix.addComponent(ff)

        let week0FF = try RollTacticalWindowUseCase.materializeFirstWindow(
            system: .functionalFitness, definition: ff.programInstance!.programDefinition!, instance: ff.programInstance!,
            startDate: asOf, ownerUserID: ownerUserID, performanceProfile: nil, materializationContext: materializationContext(), context: context
        )
        let missedFF = try XCTUnwrap(week0FF.first)
        missedFF.status = .missed
        let originalDate = missedFF.day?.date
        let originalObjectives = ff.adaptationObjectives

        let rollForwardDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: asOf))
        let result = try XCTUnwrap(RollTacticalWindowUseCase.rollForward(
            mix: mix, asOf: rollForwardDate, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext(), context: context
        ))

        XCTAssertEqual(missedFF.status, .missed)
        XCTAssertEqual(missedFF.day?.date, originalDate)
        XCTAssertEqual(ff.adaptationObjectives, originalObjectives, "a missed session must never mutate the component's own adaptation objectives")
        XCTAssertNotNil(result.newSessionsByComponent[ff.id], "FF still progresses to its next real week regardless of the prior week's miss")
    }

    /// A missed hard RUNNING session. Running never appears in
    /// `rollForward`'s per-call materialization at all (it materializes
    /// its whole 13-relative-week block up front in `materializeFirstWindow`
    /// and is unconditionally `continue`d in `rollForward`'s switch) — so a
    /// missed Running session cannot possibly be moved, regenerated, or
    /// have its frequency altered by ANY later `rollForward` call for its
    /// concurrent siblings. This test proves that directly against the
    /// real, closed Running 5K/2-Day V1 generator/materializer.
    func testMissedHardRunningSessionIsUntouchedByASiblingsRollForward() throws {
        let asOf = date(2026, 1, 5)
        let running = try makeRunningComponent(label: "Running", priority: .supporting, startDate: asOf)
        let strength = try makeHypertrophyComponent(label: "Strength", priority: .primary, startDate: asOf)
        let mix = TrainingMix(kind: .selected, name: "Missed Running Fixture")
        context.insert(mix)
        mix.addComponent(strength)
        mix.addComponent(running)

        let runningSessions = running.programInstance!.sessions.sorted { ($0.day?.date ?? .distantPast) < ($1.day?.date ?? .distantPast) }
        let hardRunningSession = try XCTUnwrap(runningSessions.first { session in
            guard let role = session.role else { return false }
            return RunningOrchestrationContract.qualityClassification(for: role) == .quality
        }, "the real Running V1 source must contain at least one quality/hard session across its 13 weeks")
        hardRunningSession.status = .missed
        let originalDate = hardRunningSession.day?.date
        let originalFrequency = running.frequency.target
        let originalSessionCount = running.programInstance!.sessions.count

        let week0Strength = try RollTacticalWindowUseCase.materializeFirstWindow(
            system: .hypertrophy, definition: strength.programInstance!.programDefinition!, instance: strength.programInstance!,
            startDate: asOf, ownerUserID: ownerUserID, performanceProfile: nil, materializationContext: materializationContext(), context: context
        )
        _ = week0Strength

        let rollForwardDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: asOf))
        let result = try RollTacticalWindowUseCase.rollForward(
            mix: mix, asOf: rollForwardDate, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext(), context: context
        )

        XCTAssertEqual(hardRunningSession.status, .missed, "a missed hard Running session's status must survive a sibling's roll-forward completely untouched")
        XCTAssertEqual(hardRunningSession.day?.date, originalDate, "a missed Running session must never be moved to another day")
        XCTAssertEqual(running.frequency.target, originalFrequency, "Running's own exact frequency (2) must never change because of a missed session")
        XCTAssertEqual(running.programInstance!.sessions.count, originalSessionCount, "rollForward never re-materializes or duplicates Running's already-complete 13-week block")
        // Running never appears in `newSessionsByComponent` from a
        // sibling's rollForward call — confirms it was correctly skipped,
        // not silently re-touched.
        XCTAssertNil(result?.newSessionsByComponent[running.id], "Running must never be re-materialized by a sibling component's rollForward call")
    }
}
