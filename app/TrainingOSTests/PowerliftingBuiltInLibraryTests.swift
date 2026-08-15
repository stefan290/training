import XCTest
import SwiftData
@testable import TrainingOS

/// Proves the 2 curated V1 Powerlifting configurations
/// (`V1_PROGRAM_LIBRARY.md` #7-8) each instantiate correctly through the
/// *same* generator — configurations, not separate engines — mirroring
/// `HypertrophyBuiltInLibraryTests`'s discipline.
@MainActor
final class PowerliftingBuiltInLibraryTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    func testLibraryContainsExactlyTheTwoDocumentedConfigurations() {
        XCTAssertEqual(PowerliftingBuiltInLibrary.all.count, 2)
        XCTAssertEqual(PowerliftingBuiltInLibrary.all.map(\.name), [
            "4-Day Powerlifting Strength",
            "5-Day Powerlifting Hypertrophy"
        ])
        XCTAssertEqual(PowerliftingBuiltInLibrary.all.map(\.configuration.family), [.b, .c])
    }

    func testEveryBuiltInConfigurationInstantiatesViaTheSameGenerator() throws {
        for config in PowerliftingBuiltInLibrary.all {
            let definition = PowerliftingProgramGenerator.generate(
                configuration: config.configuration,
                provenance: .constructed(reason: "V1 built-in: \(config.name)"),
                context: context
            )
            XCTAssertEqual(definition.orderedTemplateSessions.count, config.configuration.dayCount, "\(config.name) should produce \(config.configuration.dayCount) sessions")
            XCTAssertEqual(definition.powerliftingConfiguration?.family, config.configuration.family, "\(config.name) should use family \(config.configuration.family)")
            XCTAssertEqual(definition.programmingSystem, .powerlifting)
            XCTAssertEqual(definition.lengthWeeks, 5)
            XCTAssertEqual(definition.orderedWeeks.count, 5)
            XCTAssertEqual(definition.orderedWeeks.last?.isDeload, true)
        }
    }

    /// The two built-ins are genuinely different day structures, not the
    /// same generator output relabeled — Family B's Monday/Tuesday/
    /// Thursday/Friday vs. Family C's Monday-through-Friday.
    func testTheTwoBuiltInsProduceDistinctDayStructures() {
        let strength = PowerliftingProgramGenerator.generate(
            configuration: PowerliftingBuiltInLibrary.all[0].configuration,
            provenance: .constructed(reason: "test"), context: context
        )
        let hypertrophyBlock = PowerliftingProgramGenerator.generate(
            configuration: PowerliftingBuiltInLibrary.all[1].configuration,
            provenance: .constructed(reason: "test"), context: context
        )
        XCTAssertEqual(strength.orderedTemplateSessions.map(\.name), ["Monday", "Tuesday", "Thursday", "Friday"])
        XCTAssertEqual(hypertrophyBlock.orderedTemplateSessions.map(\.name), ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"])
    }
}
