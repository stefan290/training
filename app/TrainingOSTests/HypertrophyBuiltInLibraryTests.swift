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
            let definition = try HypertrophyProgramGenerator.generate(
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
    ///
    /// **Stage 10R.3A update:** 3-Day Full Body's day-focus-driven path
    /// now has real recovered source content for all 3 mesocycles
    /// (Mesocycle 3 "Resensitization" landed in Stage 10R.3A), so this
    /// configuration now builds a full 3-phase journey exactly like the
    /// other 5 — the Stage 10R.2A-era `XCTAssertThrowsError` branch this
    /// test used to have (proving the honest `phaseNotYetRecovered` throw
    /// while Mesocycle 3 was unrecovered) is removed; a single assertion
    /// path now covers all 6 configurations.
    func testEveryBuiltInConfigurationBuildsAFullThreePhaseJourney() throws {
        for config in HypertrophyBuiltInLibrary.all {
            let plan = TrainingPlan(status: .active)
            context.insert(plan)

            let results = try HypertrophyProgramJourney.build(
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
            // Stage 10B.6: the 3-Day Full Body reference configuration now
            // runs through the day-focus-driven Hypertrophy V2 path
            // (`.doubleProgression` load, no %RM factor at all) — the
            // Heavy Quads/Glutes exception is a `.rmBased`-only mechanism
            // and cannot apply there; covered instead by
            // `HypertrophyDayFocusGenerationTests.testHeavyExceptionNeverFiresUnderStage10BsActualFullBodyReferenceConfig()`.
            guard !(config.dayCount == 3 && config.split == .fullBody) else { continue }
            let definition = try HypertrophyProgramGenerator.generate(
                configuration: HypertrophyProgramConfiguration(dayCount: config.dayCount, split: config.split, phaseType: .basicHypertrophy),
                provenance: .constructed(reason: "test"),
                context: context
            )
            let firstSession = try XCTUnwrap(definition.orderedTemplateSessions.first)
            let block = try XCTUnwrap(firstSession.orderedBlockTemplates.first)
            let primary = try XCTUnwrap(block.orderedPrescriptionTemplates.first { $0.exerciseSlot?.name != "Chest Isolation or Triceps" })
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
