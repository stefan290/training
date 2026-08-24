import XCTest
import SwiftData
@testable import TrainingOS

/// Proves the approved Hypertrophy sequencing (Basic Hypertrophy ->
/// Metabolite Focus -> Resensitization) via `TrainingPlan.orderedPhases`
/// — no new "ProgramJourney" entity — and that each phase is independent
/// (its own `ProgramDefinition`, its own `ProgramInstance`, nothing
/// shared or cross-referenced between phases beyond ordering).
@MainActor
final class HypertrophyProgramJourneyTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func freshContext() -> ModelContext {
        ModelContext(container)
    }

    func testBuildsThreePhasesInApprovedOrder() throws {
        let ownerUserID = UUID()
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .muscleGain)
        context.insert(goal)
        let plan = TrainingPlan(status: .active)
        context.insert(plan)
        goal.addPlan(plan)

        let results = try HypertrophyProgramJourney.build(
            dayCount: 4, split: .fullBody, plan: plan, ownerUserID: ownerUserID,
            firstPhaseStartDate: Date(timeIntervalSince1970: 0), context: context
        )

        XCTAssertEqual(results.map(\.phaseType), [.basicHypertrophy, .metaboliteFocus, .resensitization])
        XCTAssertEqual(plan.orderedPhases.count, 3)
        XCTAssertEqual(plan.orderedPhases.map(\.type), [.muscleGain, .muscleGain, .muscleGain])
    }

    /// Each phase is a fully independent `ProgramDefinition`/
    /// `ProgramInstance` — same `dayCount`/`split` throughout, but no
    /// shared object between phases beyond the common `TrainingPlan`.
    func testEachPhaseHasItsOwnIndependentDefinitionAndInstance() throws {
        let ownerUserID = UUID()
        let plan = TrainingPlan(status: .active)
        context.insert(plan)

        let results = try HypertrophyProgramJourney.build(
            dayCount: 3, split: .legs, plan: plan, ownerUserID: ownerUserID,
            firstPhaseStartDate: Date(timeIntervalSince1970: 0), context: context
        )

        let definitionIDs = Set(results.map(\.definition.id))
        let instanceIDs = Set(results.map(\.instance.id))
        XCTAssertEqual(definitionIDs.count, 3, "each phase must get its own ProgramDefinition, not a shared one")
        XCTAssertEqual(instanceIDs.count, 3, "each phase must get its own ProgramInstance, not a shared one")

        for result in results {
            XCTAssertEqual(result.definition.hypertrophyConfiguration?.dayCount, 3)
            XCTAssertEqual(result.definition.hypertrophyConfiguration?.split, .legs)
            XCTAssertEqual(result.definition.hypertrophyConfiguration?.phaseType, result.phaseType)
            XCTAssertEqual(result.instance.programDefinition?.id, result.definition.id)
        }
    }

    /// Stage 3 decision A1: each phase remains independently startable —
    /// materializing (starting) one phase must not require any other
    /// phase to exist or have been materialized.
    func testEachPhaseIsIndependentlyStartable() throws {
        let ownerUserID = UUID()
        let plan = TrainingPlan(status: .active)
        context.insert(plan)

        let results = try HypertrophyProgramJourney.build(
            dayCount: 3, split: .fullBody, plan: plan, ownerUserID: ownerUserID,
            firstPhaseStartDate: Date(timeIntervalSince1970: 0), context: context
        )

        // Start only the *second* phase (Metabolite Focus) — proves it
        // doesn't depend on the first phase ever having been started.
        let metaboliteFocus = try XCTUnwrap(results.first { $0.phaseType == .metaboliteFocus })
        let materialized = StrengthMaterializer.materializeWeek(
            definition: metaboliteFocus.definition, instance: metaboliteFocus.instance,
            weekIndex: 0, isDeload: false, startDate: Date(timeIntervalSince1970: 0),
            ownerUserID: ownerUserID, equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )
        XCTAssertEqual(materialized.sessions.count, 3)

        // The other two phases remain unmaterialized (no Sessions), which
        // is a valid, unrelated state, not a dependency violation.
        let basicHypertrophy = try XCTUnwrap(results.first { $0.phaseType == .basicHypertrophy })
        XCTAssertTrue(basicHypertrophy.instance.sessions.isEmpty)
    }

    func testJourneySurvivesRoundTrip() throws {
        let ownerUserID = UUID()
        let plan = TrainingPlan(status: .active)
        context.insert(plan)
        let planID = plan.id

        try HypertrophyProgramJourney.build(
            dayCount: 4, split: .backChest, plan: plan, ownerUserID: ownerUserID,
            firstPhaseStartDate: Date(timeIntervalSince1970: 0), context: context
        )
        try context.save()

        let reloadedPlan = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<TrainingPlan>(predicate: #Predicate { $0.id == planID })).first
        )
        XCTAssertEqual(reloadedPlan.orderedPhases.count, 3)
        for phase in reloadedPlan.orderedPhases {
            XCTAssertEqual(phase.primaryInstance?.programDefinition?.hypertrophyConfiguration?.split, .backChest)
        }
    }
}
