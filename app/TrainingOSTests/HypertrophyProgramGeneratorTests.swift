import XCTest
import SwiftData
@testable import TrainingOS

/// Proves `HypertrophyProgramGenerator`'s parameterization — day count,
/// split, phase-specific load factors, the confirmed Heavy exception, and
/// that `linkedResultReference`/autoregulation's paired-slot reference is
/// wired correctly — and that the generated graph survives a real
/// save/refetch cycle. See the generator's own doc comment for what this
/// intentionally does *not* claim (a complete, realistic per-day exercise
/// selection).
@MainActor
final class HypertrophyProgramGeneratorTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func freshContext() -> ModelContext {
        ModelContext(container)
    }

    private func generate(dayCount: Int, split: HypertrophySplit, phaseType: HypertrophyPhaseType) -> ProgramDefinition {
        HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: dayCount, split: split, phaseType: phaseType),
            provenance: .constructed(reason: "test fixture"),
            context: context
        )
    }

    func testDayCountParameterizationProducesThatManyTemplateSessions() throws {
        for dayCount in [3, 4, 5, 6] {
            let definition = generate(dayCount: dayCount, split: .fullBody, phaseType: .basicHypertrophy)
            XCTAssertEqual(definition.orderedTemplateSessions.count, dayCount, "dayCount \(dayCount) should produce \(dayCount) TemplateSessions")
        }
    }

    func testFiveWeeksAlwaysGeneratedWithLastAsDeload() throws {
        let definition = generate(dayCount: 4, split: .fullBody, phaseType: .basicHypertrophy)
        XCTAssertEqual(definition.lengthWeeks, 5)
        XCTAssertEqual(definition.orderedWeeks.count, 5)
        XCTAssertEqual(definition.orderedWeeks.dropLast().map(\.isDeload), [false, false, false, false])
        XCTAssertTrue(definition.orderedWeeks.last?.isDeload ?? false)
    }

    func testEachSessionHasOnePrimaryAndOnePairedPrescriptionTemplate() throws {
        let definition = generate(dayCount: 3, split: .fullBody, phaseType: .basicHypertrophy)
        for session in definition.orderedTemplateSessions {
            let block = try XCTUnwrap(session.orderedBlockTemplates.first)
            XCTAssertEqual(block.type, .hypertrophy)
            XCTAssertEqual(block.orderedPrescriptionTemplates.count, 2)
        }
    }

    func testBasicHypertrophyUsesWeekOneFactorOf0Point85() throws {
        let definition = generate(dayCount: 3, split: .fullBody, phaseType: .basicHypertrophy)
        let primary = try primaryTemplate(in: definition)
        guard case .rmBased(let payload) = try XCTUnwrap(primary.rules?.loadRule) else {
            return XCTFail("expected .rmBased")
        }
        XCTAssertEqual(payload.weekOneFactor, 0.85, accuracy: 0.0001)
        XCTAssertEqual(payload.laterWeekMultipliers, [1.05, 1.075, 1.1])
    }

    func testResensitizationUsesFullRMAsWeekOneFactor() throws {
        let definition = generate(dayCount: 3, split: .fullBody, phaseType: .resensitization)
        let primary = try primaryTemplate(in: definition)
        guard case .rmBased(let payload) = try XCTUnwrap(primary.rules?.loadRule) else {
            return XCTFail("expected .rmBased")
        }
        XCTAssertEqual(payload.weekOneFactor, 1.0, accuracy: 0.0001)
    }

    /// Metabolite Focus: primary at 0.75, paired slot independently at
    /// 0.6 (both `rmBased`, per its own documented "×0.75 primary / ×0.6
    /// superset partner" — distinct from every other phase, which links
    /// the paired slot to the primary's result instead).
    func testMetaboliteFocusUsesDistinctPrimaryAndPairedFactors() throws {
        let definition = generate(dayCount: 3, split: .fullBody, phaseType: .metaboliteFocus)
        let session = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let block = try XCTUnwrap(session.orderedBlockTemplates.first)
        let primary = try XCTUnwrap(block.orderedPrescriptionTemplates.first { $0.exerciseSlot?.name != "Chest Isolation or Triceps" })
        let paired = try XCTUnwrap(block.orderedPrescriptionTemplates.first { $0.exerciseSlot?.name == "Chest Isolation or Triceps" })

        guard case .rmBased(let primaryPayload) = try XCTUnwrap(primary.rules?.loadRule) else {
            return XCTFail("expected primary .rmBased")
        }
        XCTAssertEqual(primaryPayload.weekOneFactor, 0.75, accuracy: 0.0001)

        guard case .rmBased(let pairedPayload) = try XCTUnwrap(paired.rules?.loadRule) else {
            return XCTFail("expected paired .rmBased for Metabolite Focus specifically")
        }
        XCTAssertEqual(pairedPayload.weekOneFactor, 0.6, accuracy: 0.0001)
    }

    /// Every non-Metabolite-Focus phase pairs the accessory via
    /// `linkedResultReference` (Stage 4 §8) instead of an independent RM
    /// test.
    func testBasicHypertrophyPairsAccessoryViaLinkedResultReference() throws {
        let definition = generate(dayCount: 3, split: .fullBody, phaseType: .basicHypertrophy)
        let session = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let block = try XCTUnwrap(session.orderedBlockTemplates.first)
        let paired = try XCTUnwrap(block.orderedPrescriptionTemplates.first { $0.exerciseSlot?.name == "Chest Isolation or Triceps" })
        XCTAssertEqual(paired.rules?.loadRule, .linkedToPairedSlot(fractionOfSourceResult: 0.6))
        XCTAssertNotNil(paired.pairedSlot, "linkedResultReference's pairing must be the structural, authoring-time PrescriptionTemplate reference (decision A5), not resolved dynamically.")
    }

    /// `pairedSlot` is legitimately set on *both* rows in the same pair,
    /// for two different rules: `paired.pairedSlot` is its own
    /// `linkedToPairedSlot` load source (asserted above), while
    /// `primary.pairedSlot` is separately its own `autoregulated` set
    /// count's rating source (`AutoregulationRatingResolver.rating`'s
    /// contract) — the field is reused per-row for whichever rule that
    /// row itself owns, never both purposes on the same row at once here.
    func testPrimarysPairedSlotIsItsOwnAutoregulationRatingSourceNotJustPairedsLoadLink() throws {
        let definition = generate(dayCount: 3, split: .fullBody, phaseType: .basicHypertrophy)
        let session = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let block = try XCTUnwrap(session.orderedBlockTemplates.first)
        let primary = try XCTUnwrap(block.orderedPrescriptionTemplates.first { $0.exerciseSlot?.name != "Chest Isolation or Triceps" })
        let paired = try XCTUnwrap(block.orderedPrescriptionTemplates.first { $0.exerciseSlot?.name == "Chest Isolation or Triceps" })

        XCTAssertEqual(primary.rules?.setCountRule, .autoregulated(AutoregulatedSetCount(baselineSets: 3)))
        XCTAssertEqual(primary.pairedSlot?.id, paired.id, "primary's own rating source must be the paired accessory")
        XCTAssertEqual(paired.pairedSlot?.id, primary.id, "paired's own load-link source must still be the primary — unaffected by primary also having its own pairedSlot")
    }

    /// The confirmed Family-A-Mesocycle-2 superset-partner deload case
    /// (decision A2) — the paired slot omits during deload, the primary
    /// does not.
    func testPairedSlotOmitsDuringDeloadPrimaryDoesNot() throws {
        let definition = generate(dayCount: 3, split: .fullBody, phaseType: .basicHypertrophy)
        let primary = try primaryTemplate(in: definition)
        let session = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let block = try XCTUnwrap(session.orderedBlockTemplates.first)
        let paired = try XCTUnwrap(block.orderedPrescriptionTemplates.first { $0.exerciseSlot?.name == "Chest Isolation or Triceps" })

        XCTAssertEqual(primary.rules?.deloadWeightAction, .standard)
        XCTAssertEqual(paired.rules?.deloadWeightAction, .omit)
        XCTAssertEqual(paired.rules?.deloadRepAction, .omit)
    }

    /// `FAMILY_A_LEGS_HEAVY_EXCEPTION`: only the `.legs` split's
    /// representative Heavy day uses the full (1.0) baseline; every other
    /// split uses the phase's normal factor.
    func testLegsSplitAppliesHeavyExceptionOnlyToLegsSplit() throws {
        let legsDefinition = generate(dayCount: 4, split: .legs, phaseType: .basicHypertrophy)
        let legsPrimary = try primaryTemplate(in: legsDefinition)
        guard case .rmBased(let legsPayload) = try XCTUnwrap(legsPrimary.rules?.loadRule) else {
            return XCTFail("expected .rmBased")
        }
        XCTAssertEqual(legsPayload.weekOneFactor, 1.0, accuracy: 0.0001, "Heavy Quads/Glutes exception should override Basic Hypertrophy's usual 0.85")
        XCTAssertEqual(legsPrimary.exerciseSlot?.name, "Heavy Quads/Glutes")

        let fullBodyDefinition = generate(dayCount: 4, split: .fullBody, phaseType: .basicHypertrophy)
        let fullBodyPrimary = try primaryTemplate(in: fullBodyDefinition)
        guard case .rmBased(let fullBodyPayload) = try XCTUnwrap(fullBodyPrimary.rules?.loadRule) else {
            return XCTFail("expected .rmBased")
        }
        XCTAssertEqual(fullBodyPayload.weekOneFactor, 0.85, accuracy: 0.0001, "Full body split must not receive the legs-only Heavy exception")
    }

    func testGeneratedGraphSurvivesRoundTrip() throws {
        let definition = generate(dayCount: 4, split: .armsShoulders, phaseType: .basicHypertrophy)
        let definitionID = definition.id
        try context.save()

        let reloaded = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<ProgramDefinition>(predicate: #Predicate { $0.id == definitionID })).first
        )
        XCTAssertEqual(reloaded.hypertrophyConfiguration, HypertrophyProgramConfiguration(dayCount: 4, split: .armsShoulders, phaseType: .basicHypertrophy))
        XCTAssertEqual(reloaded.orderedTemplateSessions.count, 4)
        XCTAssertEqual(reloaded.orderedWeeks.count, 5)
        let primary = try primaryTemplate(in: reloaded)
        XCTAssertEqual(primary.exerciseSlot?.name, "Overhead Press")
    }

    private func primaryTemplate(in definition: ProgramDefinition) throws -> PrescriptionTemplate {
        let session = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let block = try XCTUnwrap(session.orderedBlockTemplates.first)
        return try XCTUnwrap(block.orderedPrescriptionTemplates.first { $0.exerciseSlot?.name != "Chest Isolation or Triceps" })
    }
}
