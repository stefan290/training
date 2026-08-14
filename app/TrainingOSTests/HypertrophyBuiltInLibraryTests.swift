import XCTest
import SwiftData
@testable import TrainingOS

/// Proves the 6 curated V1 Hypertrophy configurations (`V1_PROGRAM_LIBRARY.md`)
/// each instantiate correctly through the *same* generator — configurations,
/// not separate engines.
@MainActor
final class HypertrophyBuiltInLibraryTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    func testLibraryContainsExactlyTheSixDocumentedConfigurations() {
        XCTAssertEqual(HypertrophyBuiltInLibrary.all.count, 6)
        XCTAssertEqual(HypertrophyBuiltInLibrary.all.map(\.name), [
            "3-Day Full Body Hypertrophy",
            "4-Day Full Body Hypertrophy",
            "5-Day Full Body Hypertrophy",
            "5-Day Upper/Arms Focus",
            "4-Day Lower/Leg Focus",
            "6-Day High-Frequency Hypertrophy"
        ])
    }

    func testEveryBuiltInConfigurationInstantiatesViaTheSameGenerator() throws {
        for config in HypertrophyBuiltInLibrary.all {
            let definition = HypertrophyProgramGenerator.generate(
                configuration: HypertrophyProgramConfiguration(dayCount: config.dayCount, split: config.split, phaseType: .basicHypertrophy),
                provenance: .constructed(reason: "V1 built-in: \(config.name)"),
                context: context
            )
            XCTAssertEqual(definition.orderedTemplateSessions.count, config.dayCount, "\(config.name) should produce \(config.dayCount) sessions")
            XCTAssertEqual(definition.hypertrophyConfiguration?.split, config.split, "\(config.name) should use split \(config.split)")
            XCTAssertEqual(definition.programmingSystem, .hypertrophy)
        }
    }

    /// Each of the 6 configs ships as a full 3-phase journey
    /// (`V1_PROGRAM_LIBRARY.md`'s own statement), same `{dayCount,split}`
    /// throughout.
    func testEveryBuiltInConfigurationBuildsAFullThreePhaseJourney() throws {
        for config in HypertrophyBuiltInLibrary.all {
            let plan = TrainingPlan(status: .active)
            context.insert(plan)

            let results = HypertrophyProgramJourney.build(
                dayCount: config.dayCount, split: config.split, plan: plan, ownerUserID: UUID(),
                firstPhaseStartDate: Date(timeIntervalSince1970: 0), context: context
            )
            XCTAssertEqual(results.count, 3, "\(config.name) should build all 3 journey phases")
            for result in results {
                XCTAssertEqual(result.definition.hypertrophyConfiguration?.dayCount, config.dayCount)
                XCTAssertEqual(result.definition.hypertrophyConfiguration?.split, config.split)
            }
        }
    }

    /// The confirmed Heavy exception should surface only for the
    /// Lower/Leg Focus configuration, not any full-body/arms config.
    func testOnlyLegFocusConfigurationAppliesTheHeavyException() throws {
        for config in HypertrophyBuiltInLibrary.all {
            let definition = HypertrophyProgramGenerator.generate(
                configuration: HypertrophyProgramConfiguration(dayCount: config.dayCount, split: config.split, phaseType: .basicHypertrophy),
                provenance: .constructed(reason: "test"),
                context: context
            )
            let firstSession = try XCTUnwrap(definition.orderedTemplateSessions.first)
            let block = try XCTUnwrap(firstSession.orderedBlockTemplates.first)
            let primary = try XCTUnwrap(block.orderedPrescriptionTemplates.first { $0.pairedSlot == nil })
            guard case .rmBased(let payload) = try XCTUnwrap(primary.rules?.loadRule) else {
                return XCTFail("expected .rmBased")
            }
            if config.split == .legs {
                XCTAssertEqual(payload.weekOneFactor, 1.0, accuracy: 0.0001, "\(config.name) should apply the Heavy exception")
            } else {
                XCTAssertEqual(payload.weekOneFactor, 0.85, accuracy: 0.0001, "\(config.name) should use the standard Basic Hypertrophy factor")
            }
        }
    }
}
