import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 6D Part 4/8 (Test G): Plan's hierarchical navigation
/// (Goal -> Phase -> Program -> Week -> Session) reads the real
/// materialized graph and never fabricates a future prescription or
/// mutates anything just from being viewed.
@MainActor
final class PlanHierarchyTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()
    let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func makeInstance(definition: ProgramDefinition, startDate: Date) -> ProgramInstance {
        let instance = ProgramInstance(ownerUserID: ownerUserID, startDate: startDate)
        instance.programDefinition = definition
        context.insert(instance)
        return instance
    }

    // MARK: Week grouping

    func testRealSessionsAreBucketedIntoTheCorrectWeek() throws {
        let definition = HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 3, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: context
        )
        let startDate = Date(timeIntervalSince1970: 0)
        let instance = makeInstance(definition: definition, startDate: startDate)

        // Week 0: materialize at startDate (days 0, 1, 2).
        StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: startDate, ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )
        // Week 1: materialize starting 7 days later (days 7, 8, 9).
        let weekTwoStart = Calendar.current.date(byAdding: .day, value: 7, to: startDate)!
        StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 1, isDeload: false,
            startDate: weekTwoStart, ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100, weekOneResolvedWeightKg: 85) }, context: context
        )

        XCTAssertEqual(ProgramWeekGrouping.realSessions(in: instance, forWeek: 0).count, 3)
        XCTAssertEqual(ProgramWeekGrouping.realSessions(in: instance, forWeek: 1).count, 3)
        XCTAssertEqual(ProgramWeekGrouping.realSessions(in: instance, forWeek: 2).count, 0, "no Session exists yet for week 2 — never fabricated")
    }

    func testWeekGroupingNeverFabricatesASessionForAnUnmaterializedWeek() throws {
        let definition = HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 3, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: context
        )
        let instance = makeInstance(definition: definition, startDate: Date(timeIntervalSince1970: 0))
        // Deliberately never materialized at all.

        for week in 0..<definition.lengthWeeks {
            XCTAssertTrue(ProgramWeekGrouping.realSessions(in: instance, forWeek: week).isEmpty)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Session>()), 0)
    }

    // MARK: Template-only preview never mutates/creates anything

    func testTemplateOnlySessionPreviewNeverCreatesASessionOrMutatesTheDefinition() throws {
        let definition = HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 3, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: context
        )
        let sessionCountBefore = try context.fetchCount(FetchDescriptor<Session>())
        let generatorVersionBefore = definition.generatorVersion

        // The exact read surface `TemplateSessionPreviewView` exercises.
        for templateSession in definition.orderedTemplateSessions {
            for blockTemplate in templateSession.orderedBlockTemplates {
                _ = blockTemplate.orderedPrescriptionTemplates.map { $0.exerciseSlot?.name }
                _ = blockTemplate.orderedPrescriptionTemplates.map { $0.rules?.repGoalSchedule.first }
            }
        }

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Session>()), sessionCountBefore)
        XCTAssertEqual(definition.generatorVersion, generatorVersionBefore)
    }

    /// A template-only week never shows a load — load depends on a
    /// tested RM (a runtime input this view never has), so the deterministic
    /// rep-goal schedule is the only numeric detail ever surfaced for it.
    func testTemplateOnlyPreviewExposesRepGoalButNeverAAFabricatedLoad() throws {
        let definition = HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 1, split: .legs, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: context
        )
        let templateSession = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let blockTemplate = try XCTUnwrap(templateSession.orderedBlockTemplates.first)
        let primaryTemplate = try XCTUnwrap(blockTemplate.orderedPrescriptionTemplates.first { $0.rules?.setCountRule.isAutoregulated == true })

        XCTAssertNotNil(primaryTemplate.rules?.repGoalSchedule.first?.reps, "rep goal is deterministic from the template alone")
        // PrescriptionTemplate itself has no resolved-weight concept at
        // all — load only ever exists on a materialized SetPrescription.
    }

    // MARK: Goal -> Phase -> Program navigation reads real data, fabricates nothing

    func testPlanViewModelShowsOnlyRealPhasesNeverFabricatingFutureOnes() throws {
        let user = User(displayName: "Test")
        context.insert(user)
        let goal = Goal(ownerUserID: user.id, primaryType: .muscleGain, status: .active)
        context.insert(goal)
        user.addGoal(goal)
        let plan = TrainingPlan(status: .active)
        context.insert(plan)
        goal.addPlan(plan)

        let activePhase = TrainingPhase(type: .strength, startDate: Date(), priorityRule: .strength, status: .active)
        context.insert(activePhase)
        plan.addPhase(activePhase)

        let viewModel = PlanViewModel()
        viewModel.load(modelContext: context)

        XCTAssertEqual(viewModel.phases.count, 1, "only the one real Phase that actually exists — nothing fabricated")
        XCTAssertEqual(viewModel.phases.first?.type, .strength)
    }
}

private extension SetCountRule {
    var isAutoregulated: Bool {
        if case .autoregulated = self { return true }
        return false
    }
}
