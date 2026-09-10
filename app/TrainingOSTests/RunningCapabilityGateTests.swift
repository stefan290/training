import XCTest
import SwiftData
@testable import TrainingOS

/// Running R3 CAPABILITY GATE tests: proves TrainingOS never silently
/// approximates an unsupported running configuration to the nearest
/// supported one, and never generates for anything but exactly
/// 5K + 2 days/week today.
@MainActor
final class RunningCapabilityGateTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    func testFiveKTwoDaysPerWeekIsSupported() {
        XCTAssertTrue(ProgramCapabilityRegistry.isRunningConfigurationSupported(distance: .fiveK, daysPerWeek: 2))
    }

    func testFiveKThreeDaysPerWeekIsUnsupported() {
        XCTAssertFalse(ProgramCapabilityRegistry.isRunningConfigurationSupported(distance: .fiveK, daysPerWeek: 3))
    }

    func testFiveKOneDayPerWeekIsUnsupported() {
        XCTAssertFalse(ProgramCapabilityRegistry.isRunningConfigurationSupported(distance: .fiveK, daysPerWeek: 1))
    }

    func testFiveKFourFiveAndSixDaysPerWeekAreAllUnsupported() {
        for days in [4, 5, 6] {
            XCTAssertFalse(ProgramCapabilityRegistry.isRunningConfigurationSupported(distance: .fiveK, daysPerWeek: days))
        }
    }

    // MARK: The generator itself must refuse, not approximate

    func testGeneratorSucceedsForTheOneSupportedConfiguration() throws {
        let definition = try RunningProgramGenerator.generate(
            configuration: RunningProgramConfiguration(distance: .fiveK, daysPerWeek: 2),
            provenance: .constructed(reason: "test"), context: context
        )
        XCTAssertEqual(definition.orderedTemplateSessions.count, 25)
    }

    func testGeneratorThrowsExplicitlyForThreeDaysPerWeekNeverSilentlyProducingTheTwoDayProgram() {
        XCTAssertThrowsError(
            try RunningProgramGenerator.generate(
                configuration: RunningProgramConfiguration(distance: .fiveK, daysPerWeek: 3),
                provenance: .constructed(reason: "test"), context: context
            )
        ) { error in
            XCTAssertEqual(error as? RunningGenerationError, .unsupportedConfiguration(distance: .fiveK, daysPerWeek: 3))
        }
    }

    func testGeneratorThrowsExplicitlyForOneDayPerWeek() {
        XCTAssertThrowsError(
            try RunningProgramGenerator.generate(
                configuration: RunningProgramConfiguration(distance: .fiveK, daysPerWeek: 1),
                provenance: .constructed(reason: "test"), context: context
            )
        )
    }

    /// "10K + 2 runs/week" — `RunningDistance` is deliberately single-case
    /// (`.fiveK` only) this V1, so a 10K request cannot even be
    /// constructed as a `RunningDistance` value today; this test proves
    /// that absence structurally (a hypothetical additional case would
    /// still correctly fail `isRunningConfigurationSupported`, since
    /// `RunningBuiltInLibrary.all` only ever contains a `.fiveK` entry).
    func testNoDistanceOtherThanFiveKExistsToRequestAtAll() {
        XCTAssertEqual(RunningDistance.allCases, [.fiveK])
        XCTAssertEqual(RunningBuiltInLibrary.all.map(\.configuration.distance), [.fiveK])
    }

    func testExactlyOneCuratedRunningConfigurationExistsAndItIsFiveKTwoDay() {
        XCTAssertEqual(RunningBuiltInLibrary.all.count, 1)
        XCTAssertEqual(RunningBuiltInLibrary.all[0].configuration, RunningProgramConfiguration(distance: .fiveK, daysPerWeek: 2))
    }
}
