import XCTest
import SwiftData
@testable import TrainingOS

/// Proves `PowerliftingProgramGenerator`'s structural output for both
/// families — day count/names, per-slot RM type, the Triples protocol,
/// the confirmed Week-4 asymmetry (Family B) / freeze (Family C)
/// parameters, and the Friday backoff's structural `pairedSlot` reference
/// — and that the generated graph survives a real save/refetch cycle.
/// See the generator's own doc comment for what this intentionally does
/// not claim (a complete, realistic per-day exercise selection, or a
/// source-confirmed Family C rep-goal schedule/deload set count for
/// either family).
@MainActor
final class PowerliftingProgramGeneratorTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func freshContext() -> ModelContext {
        ModelContext(container)
    }

    private func generate(family: PowerliftingFamily, dayCount: Int) -> ProgramDefinition {
        PowerliftingProgramGenerator.generate(
            configuration: PowerliftingProgramConfiguration(family: family, dayCount: dayCount),
            provenance: .constructed(reason: "test fixture"),
            context: context
        )
    }

    // MARK: - Family B structure

    func testFamilyBProducesFourNamedDays() throws {
        let definition = generate(family: .b, dayCount: 4)
        XCTAssertEqual(definition.orderedTemplateSessions.map(\.name), ["Monday", "Tuesday", "Thursday", "Friday"])
        XCTAssertEqual(definition.programmingSystem, .powerlifting)
        XCTAssertEqual(definition.powerliftingConfiguration, PowerliftingProgramConfiguration(family: .b, dayCount: 4))
    }

    func testFamilyBUsesMixed5And8RMBasisPerSlot() throws {
        let definition = generate(family: .b, dayCount: 4)

        func rmType(forSession name: String) throws -> RMType {
            let session = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == name })
            let block = try XCTUnwrap(session.orderedBlockTemplates.first)
            let template = try XCTUnwrap(block.orderedPrescriptionTemplates.first)
            guard case .rmBased(let payload) = try XCTUnwrap(template.rules?.loadRule) else {
                XCTFail("expected .rmBased for \(name)")
                return .rm10
            }
            return payload.rmType
        }

        XCTAssertEqual(try rmType(forSession: "Monday"), .rm5, "Bench is a 5RM slot (FAMILY_B_RM_BASIS)")
        XCTAssertEqual(try rmType(forSession: "Tuesday"), .rm5, "Squat is a 5RM slot")
        XCTAssertEqual(try rmType(forSession: "Thursday"), .rm5, "Deadlift is a 5RM slot")
        XCTAssertEqual(try rmType(forSession: "Friday"), .rm8, "the accessory row is an 8RM slot")
    }

    func testFamilyBTriplesSessionsUseTheLighterFactorAndFlatRepGoal() throws {
        let definition = generate(family: .b, dayCount: 4)
        for dayName in ["Monday", "Thursday"] {
            let session = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == dayName })
            let block = try XCTUnwrap(session.orderedBlockTemplates.first)
            let template = try XCTUnwrap(block.orderedPrescriptionTemplates.first)
            guard case .rmBased(let payload) = try XCTUnwrap(template.rules?.loadRule) else {
                return XCTFail("expected .rmBased")
            }
            XCTAssertEqual(payload.weekOneFactor, 0.7, accuracy: 0.0001, "\(dayName) is a Triples session")
            XCTAssertEqual(template.rules?.repGoalSchedule, Array(repeating: RepGoal.fixedReps(3), count: 4), "\(dayName)'s rep goal never changes")
        }

        let tuesday = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == "Tuesday" })
        let tuesdayBlock = try XCTUnwrap(tuesday.orderedBlockTemplates.first)
        let tuesdayTemplate = try XCTUnwrap(tuesdayBlock.orderedPrescriptionTemplates.first)
        guard case .rmBased(let tuesdayPayload) = try XCTUnwrap(tuesdayTemplate.rules?.loadRule) else {
            return XCTFail("expected .rmBased")
        }
        XCTAssertEqual(tuesdayPayload.weekOneFactor, 0.95, accuracy: 0.0001, "Tuesday is an ordinary, not Triples, session")
    }

    func testFamilyBWeekFourAsymmetryDiffersMondayTuesdayVsThursdayFriday() throws {
        let definition = generate(family: .b, dayCount: 4)

        for dayName in ["Monday", "Tuesday"] {
            let session = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == dayName })
            let block = try XCTUnwrap(session.orderedBlockTemplates.first)
            let template = try XCTUnwrap(block.orderedPrescriptionTemplates.first)
            guard case .autoregulated(let config) = try XCTUnwrap(template.rules?.setCountRule) else {
                return XCTFail("expected .autoregulated")
            }
            XCTAssertTrue(config.applyRatingOnFinalWeek, "\(dayName) keeps applying the rating in Week 4")
        }

        let thursday = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == "Thursday" })
        let thursdayBlock = try XCTUnwrap(thursday.orderedBlockTemplates.first)
        let thursdayTemplate = try XCTUnwrap(thursdayBlock.orderedPrescriptionTemplates.first)
        guard case .autoregulated(let thursdayConfig) = try XCTUnwrap(thursdayTemplate.rules?.setCountRule) else {
            return XCTFail("expected .autoregulated")
        }
        XCTAssertFalse(thursdayConfig.applyRatingOnFinalWeek, "Thursday's Week-4 set count is a flat copy of Week 3")
        XCTAssertNil(thursdayConfig.freezeAfterWeek, "Family B uses the asymmetry shape, not Family C's freeze")
    }

    func testFamilyBFridayAccessoryUsesFixedNeverAutoregulatedSchedule() throws {
        let definition = generate(family: .b, dayCount: 4)
        let friday = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == "Friday" })
        let block = try XCTUnwrap(friday.orderedBlockTemplates.first)
        let template = try XCTUnwrap(block.orderedPrescriptionTemplates.first)
        XCTAssertEqual(template.rules?.setCountRule, .fixed(setsByWeek: [2, 2, 3, 3]))
    }

    func testFamilyBDeloadUsesTheDocumentedDaySplitFactors() throws {
        let definition = generate(family: .b, dayCount: 4)
        let monday = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == "Monday" })
        let mondayBlock = try XCTUnwrap(monday.orderedBlockTemplates.first)
        let mondayTemplate = try XCTUnwrap(mondayBlock.orderedPrescriptionTemplates.first)
        XCTAssertEqual(mondayTemplate.rules?.deloadWeightPositionOverride, DeloadPositionOverride(boundaryDayIndex: 2, fullPositionFactor: 0.7, halfPositionFactor: 0.5))
        XCTAssertEqual(mondayTemplate.rules?.deloadRepPositionOverride, DeloadPositionOverride(boundaryDayIndex: 2, fullPositionFactor: 2.0 / 3.0, halfPositionFactor: 0.5))
    }

    // MARK: - Family C structure

    func testFamilyCProducesFiveNamedDays() throws {
        let definition = generate(family: .c, dayCount: 5)
        XCTAssertEqual(definition.orderedTemplateSessions.map(\.name), ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"])
        XCTAssertEqual(definition.powerliftingConfiguration, PowerliftingProgramConfiguration(family: .c, dayCount: 5))
    }

    func testFamilyCUsesUniform10RMBasis() throws {
        let definition = generate(family: .c, dayCount: 5)
        for session in definition.orderedTemplateSessions {
            for template in try XCTUnwrap(session.orderedBlockTemplates.first).orderedPrescriptionTemplates {
                if case .rmBased(let payload) = template.rules?.loadRule {
                    XCTAssertEqual(payload.rmType, .rm10, "\(session.name) should be 10RM-based")
                }
            }
        }
    }

    func testFamilyCFreezesThursdayAndFridayButNotMondayThroughWednesday() throws {
        let definition = generate(family: .c, dayCount: 5)

        for dayName in ["Monday", "Tuesday", "Wednesday"] {
            let session = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == dayName })
            let block = try XCTUnwrap(session.orderedBlockTemplates.first)
            let template = try XCTUnwrap(block.orderedPrescriptionTemplates.first)
            guard case .autoregulated(let config) = try XCTUnwrap(template.rules?.setCountRule) else {
                return XCTFail("expected .autoregulated")
            }
            XCTAssertNil(config.freezeAfterWeek, "\(dayName) keeps incrementing through Week 4")
        }

        let thursday = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == "Thursday" })
        let thursdayBlock = try XCTUnwrap(thursday.orderedBlockTemplates.first)
        let thursdayTemplate = try XCTUnwrap(thursdayBlock.orderedPrescriptionTemplates.first)
        guard case .autoregulated(let thursdayConfig) = try XCTUnwrap(thursdayTemplate.rules?.setCountRule) else {
            return XCTFail("expected .autoregulated")
        }
        XCTAssertEqual(thursdayConfig.freezeAfterWeek, 2, "Thursday freezes after Week 3 (0-based index 2)")
        XCTAssertTrue(thursdayConfig.applyRatingOnFinalWeek, "Family C uses the freeze shape, not Family B's asymmetry")
    }

    func testFamilyCFridayHasPrimaryAndBackoffStructurallyPairedToMonday() throws {
        let definition = generate(family: .c, dayCount: 5)
        let monday = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == "Monday" })
        let mondayTemplate = try XCTUnwrap(try XCTUnwrap(monday.orderedBlockTemplates.first).orderedPrescriptionTemplates.first)

        let friday = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == "Friday" })
        let fridayBlock = try XCTUnwrap(friday.orderedBlockTemplates.first)
        XCTAssertEqual(fridayBlock.orderedPrescriptionTemplates.count, 2, "Friday has a primary exercise plus the backoff")

        let backoff = try XCTUnwrap(fridayBlock.orderedPrescriptionTemplates.first { $0.pairedSlot != nil })
        XCTAssertEqual(backoff.pairedSlot?.id, mondayTemplate.id, "the backoff is structurally paired to Monday's slot (decision A5's shape)")
        XCTAssertEqual(backoff.rules?.loadRule, .linkedToPairedSlot(fractionOfSourceResult: 0.85 / 0.95))
        XCTAssertEqual(backoff.rules?.deloadRepFraction, 1.0, "the backoff's deload reps are the sole exception: unchanged from Week 1")

        let primary = try XCTUnwrap(fridayBlock.orderedPrescriptionTemplates.first { $0.pairedSlot == nil })
        XCTAssertEqual(primary.rules?.deloadRepFraction, 0.5, "every other Family C row deloads reps to half of Week 1")
    }

    func testFamilyCDeloadWeightIsUnchangedMondayTuesdayHalvedWednesdayOnward() throws {
        let definition = generate(family: .c, dayCount: 5)
        for dayName in ["Monday", "Tuesday"] {
            let session = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == dayName })
            let template = try XCTUnwrap(try XCTUnwrap(session.orderedBlockTemplates.first).orderedPrescriptionTemplates.first)
            XCTAssertEqual(template.rules?.deloadWeightPositionOverride?.fullPositionFactor, 1.0, "\(dayName) is unchanged during deload")
        }
        for dayName in ["Wednesday", "Thursday", "Friday"] {
            let session = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == dayName })
            let template = try XCTUnwrap(try XCTUnwrap(session.orderedBlockTemplates.first).orderedPrescriptionTemplates.first)
            XCTAssertEqual(template.rules?.deloadWeightPositionOverride?.boundaryDayIndex, 2)
            XCTAssertEqual(template.rules?.deloadWeightPositionOverride?.halfPositionFactor, 0.5)
        }
    }

    // MARK: - Round trip

    func testFamilyBGraphSurvivesRoundTrip() throws {
        let definition = generate(family: .b, dayCount: 4)
        let definitionID = definition.id
        try context.save()

        let reloaded = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<ProgramDefinition>(predicate: #Predicate { $0.id == definitionID })).first
        )
        XCTAssertEqual(reloaded.powerliftingConfiguration, PowerliftingProgramConfiguration(family: .b, dayCount: 4))
        XCTAssertEqual(reloaded.orderedTemplateSessions.count, 4)
    }

    func testFamilyCGraphSurvivesRoundTripIncludingPairedSlot() throws {
        let definition = generate(family: .c, dayCount: 5)
        let definitionID = definition.id
        try context.save()

        let reloaded = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<ProgramDefinition>(predicate: #Predicate { $0.id == definitionID })).first
        )
        let monday = try XCTUnwrap(reloaded.orderedTemplateSessions.first { $0.name == "Monday" })
        let mondayTemplate = try XCTUnwrap(try XCTUnwrap(monday.orderedBlockTemplates.first).orderedPrescriptionTemplates.first)
        let friday = try XCTUnwrap(reloaded.orderedTemplateSessions.first { $0.name == "Friday" })
        let fridayBlock = try XCTUnwrap(friday.orderedBlockTemplates.first)
        let backoff = try XCTUnwrap(fridayBlock.orderedPrescriptionTemplates.first { $0.pairedSlot != nil })
        XCTAssertEqual(backoff.pairedSlot?.id, mondayTemplate.id)
    }
}
