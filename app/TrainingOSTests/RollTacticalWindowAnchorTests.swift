import XCTest
import SwiftData
@testable import TrainingOS

/// MUSCLE + 5FF FINAL CLOSURE, Section 17/18 (project-owner decision):
/// proves the real fix in `RollTacticalWindowUseCase.rollForward` —
/// the scheduling window anchors to the REAL naive dates the
/// materializers already stamped onto each just-materialized Session
/// (`instance.startDate + weekIndex*7`), never to `asOf` (Section 18:
/// "when the user is doing this action") in any form. Table-driven
/// across every weekday Section 18 names (Monday/Tuesday/Wednesday/
/// Friday/Sunday) `asOf` could land on, all rolling forward to the exact
/// same real target week regardless — see `causal-analysis/
/// tactical-window-anchor.md` for the two prior fix attempts this
/// checkpoint's approach replaces (each anchored to `asOf` in some form,
/// each breaking a different real test).
@MainActor
final class RollTacticalWindowAnchorTests: XCTestCase {
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

    private func makeHypertrophyComponent(startDate: Date) throws -> TrainingMixComponent {
        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 2, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: context
        )
        resolveAllSlots(in: definition, to: exercise("Back Squat", targets: [.quadriceps, .glutes]))
        let instance = ProgramInstance(ownerUserID: ownerUserID, startDate: startDate)
        context.insert(instance)
        instance.programDefinition = definition
        let component = TrainingMixComponent(
            label: "Strength", programmingSystem: .hypertrophy, priority: .primary,
            adaptationObjectives: [.muscleGain], frequency: SessionFrequency(target: 2)
        )
        context.insert(component)
        component.programInstance = instance
        return component
    }

    private func makeFunctionalFitnessComponent(startDate: Date) -> TrainingMixComponent {
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 4, targetStimulus: heavySquatMaterializableStimulus(), format: .maxLoad,
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false, isDynamicallyComposed: false
        )
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID, startDate: startDate)
        context.insert(instance)
        instance.programDefinition = definition
        let component = TrainingMixComponent(
            label: "Functional Fitness", programmingSystem: .functionalFitness, priority: .supporting,
            adaptationObjectives: [.workCapacity, .aerobicCapacity, .power], frequency: SessionFrequency(target: 1)
        )
        context.insert(component)
        component.programInstance = instance
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

    /// Builds a real 2-component mix (Hypertrophy + Functional Fitness,
    /// the exact same real production shape `MissedSessionInvariantTests`
    /// already exercises), materializes and schedules week 0, then rolls
    /// forward to week 1 with `asOf` set to `weekdayOffsetFromMonday` days
    /// after week 1's own real Monday — proving the roll succeeds and
    /// every newly-materialized session lands within week 1's own real
    /// 7-day span (`instance.startDate + 7` through `+13`), regardless of
    /// which day of that week `asOf` happens to be.
    private func assertRollForwardLandsInCorrectWeek(weekdayOffsetFromMonday: Int, line: UInt = #line) throws {
        let monday = date(2026, 1, 5)
        let strength = try makeHypertrophyComponent(startDate: monday)
        let ff = makeFunctionalFitnessComponent(startDate: monday)
        let mix = TrainingMix(kind: .selected, name: "Tactical Window Anchor Fixture")
        context.insert(mix)
        mix.addComponent(strength)
        mix.addComponent(ff)

        let week0Strength = try RollTacticalWindowUseCase.materializeFirstWindow(
            system: .hypertrophy, definition: strength.programInstance!.programDefinition!, instance: strength.programInstance!,
            startDate: monday, ownerUserID: ownerUserID, performanceProfile: nil, materializationContext: materializationContext(), context: context
        )
        let week0FF = try RollTacticalWindowUseCase.materializeFirstWindow(
            system: .functionalFitness, definition: ff.programInstance!.programDefinition!, instance: ff.programInstance!,
            startDate: monday, ownerUserID: ownerUserID, performanceProfile: nil, materializationContext: materializationContext(), context: context
        )
        let week0Proposal = SchedulingPipeline.propose(
            mix: mix,
            inputs: [ScheduledProgramInput(component: strength, sessions: week0Strength), ScheduledProgramInput(component: ff, sessions: week0FF)],
            constraints: SchedulingConstraints(availability: availability(), window: SchedulingWindow(startDate: monday, numberOfDays: 7))
        )
        try AcceptScheduleProposalUseCase.accept(week0Proposal.proposal, ownerUserID: ownerUserID, context: context)

        // Week 1's own real, canonical calendar span — completely
        // independent of whichever weekday `asOf` below happens to be.
        let week1Monday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: monday))
        let week1Sunday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 13, to: monday))

        let asOf = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: weekdayOffsetFromMonday, to: week1Monday))
        let result = try XCTUnwrap(
            RollTacticalWindowUseCase.rollForward(
                mix: mix, asOf: asOf, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
                materializationContext: materializationContext(), context: context
            ),
            "roll-forward must succeed regardless of which weekday `asOf` falls on within the real target week",
            file: #filePath, line: line
        )

        XCTAssertEqual(result.scheduleProposal.feasibility, .feasible, line: line)
        let allNewSessions = result.newSessionsByComponent.values.flatMap { $0 }
        XCTAssertFalse(allNewSessions.isEmpty, "week 1 must materialize real sessions", line: line)
        for session in allNewSessions {
            let placedDate = try XCTUnwrap(session.day?.date, "every newly materialized session must have a real placed date", file: #filePath, line: line)
            XCTAssertTrue(
                placedDate >= Calendar.current.startOfDay(for: week1Monday) && placedDate <= Calendar.current.startOfDay(for: week1Sunday),
                "session placed on \(placedDate) must fall within week 1's own real span (\(week1Monday) - \(week1Sunday)), regardless of asOf's own weekday (\(asOf))",
                line: line
            )
        }
    }

    func testRollForwardLandsInCorrectWeek_AsOfMonday() throws {
        try assertRollForwardLandsInCorrectWeek(weekdayOffsetFromMonday: 0)
    }

    func testRollForwardLandsInCorrectWeek_AsOfTuesday() throws {
        try assertRollForwardLandsInCorrectWeek(weekdayOffsetFromMonday: 1)
    }

    func testRollForwardLandsInCorrectWeek_AsOfWednesday() throws {
        try assertRollForwardLandsInCorrectWeek(weekdayOffsetFromMonday: 2)
    }

    func testRollForwardLandsInCorrectWeek_AsOfFriday() throws {
        try assertRollForwardLandsInCorrectWeek(weekdayOffsetFromMonday: 4)
    }

    func testRollForwardLandsInCorrectWeek_AsOfSunday() throws {
        try assertRollForwardLandsInCorrectWeek(weekdayOffsetFromMonday: 6)
    }

    /// Section 21, item 17: "past dates inside canonical target week use
    /// truthful missed/past semantics rather than making whole week
    /// infeasible." `asOf` set to Wednesday of week 1 means Monday/
    /// Tuesday of that same real target week are chronologically BEFORE
    /// `asOf` — proves two things directly: (a) the roll still succeeds
    /// for the WHOLE week, never partial/infeasible merely because part
    /// of it is chronologically behind `asOf` (Section 17's own "must
    /// not schedule a past session as future... but must not make the
    /// whole week infeasible either"), and (b) nothing auto-invents a
    /// `.missed`/any other non-`.scheduled` status for those earlier
    /// days merely from being chronologically behind `asOf` — status is
    /// exactly what every OTHER real session's real, unrelated business
    /// logic decides (an explicit, separate act), never a side effect of
    /// scheduling itself (mirrors `MissedSessionInvariantTests`'s own
    /// established finding: neither `ConcurrentScheduler` nor
    /// `rollForward` ever reads `Session.status` or "now").
    func testRollForwardNeverAutoMarksChronologicallyEarlierSessionsWithinTheTargetWeekAsMissed() throws {
        let monday = date(2026, 1, 5)
        let strength = try makeHypertrophyComponent(startDate: monday)
        let ff = makeFunctionalFitnessComponent(startDate: monday)
        let mix = TrainingMix(kind: .selected, name: "Past-Within-Week Fixture")
        context.insert(mix)
        mix.addComponent(strength)
        mix.addComponent(ff)

        let week0Strength = try RollTacticalWindowUseCase.materializeFirstWindow(
            system: .hypertrophy, definition: strength.programInstance!.programDefinition!, instance: strength.programInstance!,
            startDate: monday, ownerUserID: ownerUserID, performanceProfile: nil, materializationContext: materializationContext(), context: context
        )
        let week0FF = try RollTacticalWindowUseCase.materializeFirstWindow(
            system: .functionalFitness, definition: ff.programInstance!.programDefinition!, instance: ff.programInstance!,
            startDate: monday, ownerUserID: ownerUserID, performanceProfile: nil, materializationContext: materializationContext(), context: context
        )
        let week0Proposal = SchedulingPipeline.propose(
            mix: mix,
            inputs: [ScheduledProgramInput(component: strength, sessions: week0Strength), ScheduledProgramInput(component: ff, sessions: week0FF)],
            constraints: SchedulingConstraints(availability: availability(), window: SchedulingWindow(startDate: monday, numberOfDays: 7))
        )
        try AcceptScheduleProposalUseCase.accept(week0Proposal.proposal, ownerUserID: ownerUserID, context: context)

        let week1Monday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: monday))
        let wednesday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 2, to: week1Monday))
        let result = try XCTUnwrap(RollTacticalWindowUseCase.rollForward(
            mix: mix, asOf: wednesday, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext(), context: context
        ))

        XCTAssertEqual(result.scheduleProposal.feasibility, .feasible, "the whole target week must materialize successfully even though `asOf` (Wednesday) falls chronologically after some of that same week's own real days")
        let allNewSessions = result.newSessionsByComponent.values.flatMap { $0 }
        XCTAssertFalse(allNewSessions.isEmpty)
        for session in allNewSessions {
            XCTAssertEqual(session.status, .scheduled, "a session dated chronologically before `asOf` within its own real target week must never be auto-marked missed/past — only an explicit, separate act (e.g. ChangeSessionStatusUseCase) may ever change status, exactly as MissedSessionInvariantTests already establishes")
        }
    }
}
