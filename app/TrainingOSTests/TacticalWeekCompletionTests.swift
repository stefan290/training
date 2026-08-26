import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 10R.4A: proves the pure, derived tactical-lifecycle queries
/// (`TacticalWeekCompletion`) — week-terminal, next-source-week,
/// instance-exhaustion, and the mixed-modality advancement gate — never
/// a persisted status (Locked Decision 4). Every fixture here builds
/// real `Session`/`Day` objects with real `SessionStatus` values; no
/// query under test ever writes anything.
@MainActor
final class TacticalWeekCompletionTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    // MARK: Fixture helpers

    private func makeInstance(startDate: Date = Date(timeIntervalSince1970: 1_700_000_000), definition: ProgramDefinition? = nil) -> ProgramInstance {
        let instance = ProgramInstance(ownerUserID: ownerUserID, startDate: startDate, status: .active)
        context.insert(instance)
        instance.programDefinition = definition
        return instance
    }

    /// One real materialized `Session` in `instance`'s `weekIndex`'th
    /// 7-day window (mirrors `ProgramWeekGrouping.realSessions`'s own
    /// `daysSinceStart / 7 == weekIndex` bucketing), with the given
    /// status — never a fabricated `SetResult`/rating (Locked Decision 3
    /// — these fixtures never populate either, proving the query itself
    /// works from `Session.status` alone).
    @discardableResult
    private func addSession(to instance: ProgramInstance, weekIndex: Int, dayOffsetWithinWeek: Int = 0, status: SessionStatus) -> Session {
        let date = Calendar.current.date(byAdding: .day, value: weekIndex * 7 + dayOffsetWithinWeek, to: instance.startDate) ?? instance.startDate
        let day = Day(ownerUserID: ownerUserID, date: date)
        context.insert(day)
        let session = Session(name: "Session", modality: .strength, status: status)
        context.insert(session)
        day.addSession(session)
        instance.addSession(session)
        return session
    }

    private func makeThreeDayFullBodyDefinition(phaseType: HypertrophyPhaseType) throws -> ProgramDefinition {
        try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 3, split: .fullBody, phaseType: phaseType),
            provenance: .constructed(reason: "test fixture"), context: context
        )
    }

    // MARK: isWeekTerminal

    func testEmptyWeekIsNotTerminal() {
        let instance = makeInstance()
        XCTAssertFalse(TacticalWeekCompletion.isWeekTerminal(for: instance, weekIndex: 0))
    }

    func testAllCompletedIsTerminal() {
        let instance = makeInstance()
        addSession(to: instance, weekIndex: 0, dayOffsetWithinWeek: 0, status: .completed)
        addSession(to: instance, weekIndex: 0, dayOffsetWithinWeek: 2, status: .completed)
        addSession(to: instance, weekIndex: 0, dayOffsetWithinWeek: 4, status: .completed)
        XCTAssertTrue(TacticalWeekCompletion.isWeekTerminal(for: instance, weekIndex: 0))
    }

    /// Missed/skipped/abandoned test 1: completed + skipped + completed -> terminal.
    func testCompletedSkippedCompletedIsTerminal() {
        let instance = makeInstance()
        addSession(to: instance, weekIndex: 0, dayOffsetWithinWeek: 0, status: .completed)
        addSession(to: instance, weekIndex: 0, dayOffsetWithinWeek: 2, status: .skipped)
        addSession(to: instance, weekIndex: 0, dayOffsetWithinWeek: 4, status: .completed)
        XCTAssertTrue(TacticalWeekCompletion.isWeekTerminal(for: instance, weekIndex: 0))
    }

    /// Missed/skipped/abandoned test 2: completed + missed + completed -> terminal.
    func testCompletedMissedCompletedIsTerminal() {
        let instance = makeInstance()
        addSession(to: instance, weekIndex: 0, dayOffsetWithinWeek: 0, status: .completed)
        addSession(to: instance, weekIndex: 0, dayOffsetWithinWeek: 2, status: .missed)
        addSession(to: instance, weekIndex: 0, dayOffsetWithinWeek: 4, status: .completed)
        XCTAssertTrue(TacticalWeekCompletion.isWeekTerminal(for: instance, weekIndex: 0))
    }

    /// Missed/skipped/abandoned test 3: all other terminal + one abandoned -> terminal.
    func testAllOtherTerminalPlusOneAbandonedIsTerminal() {
        let instance = makeInstance()
        addSession(to: instance, weekIndex: 0, dayOffsetWithinWeek: 0, status: .completed)
        addSession(to: instance, weekIndex: 0, dayOffsetWithinWeek: 2, status: .skipped)
        addSession(to: instance, weekIndex: 0, dayOffsetWithinWeek: 4, status: .abandoned)
        XCTAssertTrue(TacticalWeekCompletion.isWeekTerminal(for: instance, weekIndex: 0))
    }

    /// Missed/skipped/abandoned test 4: one scheduled remains -> NOT terminal.
    func testOneScheduledRemainingIsNotTerminal() {
        let instance = makeInstance()
        addSession(to: instance, weekIndex: 0, dayOffsetWithinWeek: 0, status: .completed)
        addSession(to: instance, weekIndex: 0, dayOffsetWithinWeek: 2, status: .completed)
        addSession(to: instance, weekIndex: 0, dayOffsetWithinWeek: 4, status: .scheduled)
        XCTAssertFalse(TacticalWeekCompletion.isWeekTerminal(for: instance, weekIndex: 0))
    }

    /// Missed/skipped/abandoned test 5: one inProgress remains -> NOT terminal.
    func testOneInProgressRemainingIsNotTerminal() {
        let instance = makeInstance()
        addSession(to: instance, weekIndex: 0, dayOffsetWithinWeek: 0, status: .completed)
        addSession(to: instance, weekIndex: 0, dayOffsetWithinWeek: 2, status: .inProgress)
        XCTAssertFalse(TacticalWeekCompletion.isWeekTerminal(for: instance, weekIndex: 0))
    }

    /// Missed/skipped/abandoned test 6/7: skipped/missed/abandoned Sessions
    /// never receive fabricated SetResults or ratings — proven directly:
    /// these fixtures construct them with zero blocks/prescriptions at
    /// all, and `TacticalWeekCompletion` never reads or writes
    /// `SetResult`/`autoregulationRating` anywhere in its own
    /// implementation (it only reads `Session.status`).
    func testTerminalSessionsCarryNoFabricatedPerformanceData() {
        let instance = makeInstance()
        let skipped = addSession(to: instance, weekIndex: 0, dayOffsetWithinWeek: 0, status: .skipped)
        let missed = addSession(to: instance, weekIndex: 0, dayOffsetWithinWeek: 2, status: .missed)
        let abandoned = addSession(to: instance, weekIndex: 0, dayOffsetWithinWeek: 4, status: .abandoned)
        XCTAssertTrue(TacticalWeekCompletion.isWeekTerminal(for: instance, weekIndex: 0))
        for session in [skipped, missed, abandoned] {
            XCTAssertTrue(session.blocks.isEmpty, "no fabricated WorkoutBlock/ExercisePrescription/SetResult for a terminal-but-unperformed session")
        }
    }

    // MARK: hasNextSourceWeek / isInstanceExhausted / canAdvanceTacticalWeek — real M1 (5-week) and M3 (3-week) definitions

    func testHasNextSourceWeekForFiveWeekMesocycle() throws {
        let definition = try makeThreeDayFullBodyDefinition(phaseType: .basicHypertrophy)
        let instance = makeInstance(definition: definition)
        XCTAssertTrue(TacticalWeekCompletion.hasNextSourceWeek(for: instance, afterWeekIndex: 0))
        XCTAssertTrue(TacticalWeekCompletion.hasNextSourceWeek(for: instance, afterWeekIndex: 3))
        XCTAssertFalse(TacticalWeekCompletion.hasNextSourceWeek(for: instance, afterWeekIndex: 4), "week index 4 (deload) is the final M1 week — no week 6")
    }

    func testHasNextSourceWeekForThreeWeekMesocycle() throws {
        let definition = try makeThreeDayFullBodyDefinition(phaseType: .resensitization)
        let instance = makeInstance(definition: definition)
        XCTAssertTrue(TacticalWeekCompletion.hasNextSourceWeek(for: instance, afterWeekIndex: 0))
        XCTAssertFalse(TacticalWeekCompletion.hasNextSourceWeek(for: instance, afterWeekIndex: 2), "week index 2 (deload) is the final M3 week — no week 4; proves not hardcoded to 5 weeks")
    }

    func testInstanceExhaustedOnlyAtRealFinalTerminalWeek() throws {
        let definition = try makeThreeDayFullBodyDefinition(phaseType: .resensitization)
        let instance = makeInstance(definition: definition)
        addSession(to: instance, weekIndex: 0, status: .completed)
        XCTAssertFalse(TacticalWeekCompletion.isInstanceExhausted(for: instance), "week 0 terminal but weeks remain")
        XCTAssertTrue(TacticalWeekCompletion.canAdvanceTacticalWeek(for: instance))

        addSession(to: instance, weekIndex: 1, status: .completed)
        XCTAssertFalse(TacticalWeekCompletion.isInstanceExhausted(for: instance), "week 1 terminal but the deload week remains")
        XCTAssertTrue(TacticalWeekCompletion.canAdvanceTacticalWeek(for: instance))

        addSession(to: instance, weekIndex: 2, status: .completed)
        XCTAssertTrue(TacticalWeekCompletion.isInstanceExhausted(for: instance), "the deload week (index 2, M3's final week) is now terminal")
        XCTAssertFalse(TacticalWeekCompletion.canAdvanceTacticalWeek(for: instance))
    }

    func testCurrentMaterializedWeekIndexNilBeforeAnyMaterialization() {
        let instance = makeInstance()
        XCTAssertNil(TacticalWeekCompletion.currentMaterializedWeekIndex(for: instance))
    }

    // MARK: Mixed-modality gate

    private func makeComponent(instance: ProgramInstance?, system: ProgrammingSystemKind?) -> TrainingMixComponent {
        let component = TrainingMixComponent(label: "Component", programmingSystem: system, priority: .primary, frequency: SessionFrequency(target: 3))
        context.insert(component)
        component.programInstance = instance
        return component
    }

    func testMixGateWithheldWhenOneComponentNotTerminal() throws {
        let hypertrophyDefinition = try makeThreeDayFullBodyDefinition(phaseType: .basicHypertrophy)
        let hypertrophyInstance = makeInstance(definition: hypertrophyDefinition)
        addSession(to: hypertrophyInstance, weekIndex: 0, status: .completed)

        let secondDefinition = try makeThreeDayFullBodyDefinition(phaseType: .basicHypertrophy)
        let secondInstance = makeInstance(definition: secondDefinition)
        addSession(to: secondInstance, weekIndex: 0, status: .scheduled)

        let mix = TrainingMix(kind: .selected, name: "Mixed")
        context.insert(mix)
        mix.addComponent(makeComponent(instance: hypertrophyInstance, system: .hypertrophy))
        mix.addComponent(makeComponent(instance: secondInstance, system: .hypertrophy))

        XCTAssertFalse(TacticalWeekCompletion.canAdvanceTacticalWeek(for: mix), "one component's current week is not terminal — the whole mix must not be advanceable")
    }

    func testMixGateAvailableWhenEveryComponentTerminal() throws {
        let firstDefinition = try makeThreeDayFullBodyDefinition(phaseType: .basicHypertrophy)
        let firstInstance = makeInstance(definition: firstDefinition)
        addSession(to: firstInstance, weekIndex: 0, status: .completed)

        let secondDefinition = try makeThreeDayFullBodyDefinition(phaseType: .basicHypertrophy)
        let secondInstance = makeInstance(definition: secondDefinition)
        addSession(to: secondInstance, weekIndex: 0, status: .skipped)

        let mix = TrainingMix(kind: .selected, name: "Mixed")
        context.insert(mix)
        mix.addComponent(makeComponent(instance: firstInstance, system: .hypertrophy))
        mix.addComponent(makeComponent(instance: secondInstance, system: .hypertrophy))

        XCTAssertTrue(TacticalWeekCompletion.canAdvanceTacticalWeek(for: mix))
    }

    /// One component already tactically exhausted must not permanently
    /// block a sibling that still has more weeks — see
    /// `TacticalWeekCompletion.canAdvanceTacticalWeek(for: TrainingMix)`'s
    /// own doc comment.
    func testExhaustedComponentDoesNotBlockAStillProgressingSibling() throws {
        let exhaustedDefinition = try makeThreeDayFullBodyDefinition(phaseType: .resensitization)
        let exhaustedInstance = makeInstance(definition: exhaustedDefinition)
        addSession(to: exhaustedInstance, weekIndex: 0, status: .completed)
        addSession(to: exhaustedInstance, weekIndex: 1, status: .completed)
        addSession(to: exhaustedInstance, weekIndex: 2, status: .completed) // M3's final (deload) week — now exhausted
        XCTAssertTrue(TacticalWeekCompletion.isInstanceExhausted(for: exhaustedInstance), "precondition")

        let progressingDefinition = try makeThreeDayFullBodyDefinition(phaseType: .basicHypertrophy)
        let progressingInstance = makeInstance(definition: progressingDefinition)
        addSession(to: progressingInstance, weekIndex: 0, status: .completed)

        let mix = TrainingMix(kind: .selected, name: "Mixed")
        context.insert(mix)
        mix.addComponent(makeComponent(instance: exhaustedInstance, system: .hypertrophy))
        mix.addComponent(makeComponent(instance: progressingInstance, system: .hypertrophy))

        XCTAssertTrue(TacticalWeekCompletion.canAdvanceTacticalWeek(for: mix), "the exhausted component must not block the still-progressing one")
    }

    func testMixGateFalseWhenEveryComponentExhausted() throws {
        let definition = try makeThreeDayFullBodyDefinition(phaseType: .resensitization)
        let instance = makeInstance(definition: definition)
        addSession(to: instance, weekIndex: 0, status: .completed)
        addSession(to: instance, weekIndex: 1, status: .completed)
        addSession(to: instance, weekIndex: 2, status: .completed)

        let mix = TrainingMix(kind: .selected, name: "Mixed")
        context.insert(mix)
        mix.addComponent(makeComponent(instance: instance, system: .hypertrophy))

        XCTAssertFalse(TacticalWeekCompletion.canAdvanceTacticalWeek(for: mix), "nothing left to advance — must not falsely report available")
    }

    func testSteadyStateComponentNeverGatesOrBlocksTheMix() throws {
        let hypertrophyDefinition = try makeThreeDayFullBodyDefinition(phaseType: .basicHypertrophy)
        let hypertrophyInstance = makeInstance(definition: hypertrophyDefinition)
        addSession(to: hypertrophyInstance, weekIndex: 0, status: .completed)

        // A Steady State component with a materialized-but-unfinished
        // session must never block the mix — rollForward itself always
        // skips `.steadyState` (it materialized its whole block up front).
        let steadyStateInstance = makeInstance()
        addSession(to: steadyStateInstance, weekIndex: 0, status: .scheduled)

        let mix = TrainingMix(kind: .selected, name: "Mixed")
        context.insert(mix)
        mix.addComponent(makeComponent(instance: hypertrophyInstance, system: .hypertrophy))
        mix.addComponent(makeComponent(instance: steadyStateInstance, system: .steadyState))

        XCTAssertTrue(TacticalWeekCompletion.canAdvanceTacticalWeek(for: mix))
    }
}
