import XCTest
@testable import TrainingOS

/// Stage 5B: proves the planner distinguishes "conceptually appropriate"
/// from "currently executable" — `PROGRAM_RECOMMENDATION_MODEL.md` §5.
final class ProgramCapabilityRegistryTests: XCTestCase {
    func testAllFiveProgrammingSystemsAreAvailable() {
        let available = ProgramCapabilityRegistry.availableProgrammingSystems()
        XCTAssertEqual(available, Set(ProgrammingSystemKind.allCases))
    }

    func testOnlyHypertrophyAndPowerliftingHaveCuratedConfigurations() {
        for system in ProgrammingSystemKind.allCases {
            let capability = ProgramCapabilityRegistry.capability(for: system)
            switch system {
            case .hypertrophy:
                XCTAssertTrue(capability.hasCuratedConfigurations)
                XCTAssertEqual(capability.curatedConfigurationCount, 6)
            case .powerlifting:
                XCTAssertTrue(capability.hasCuratedConfigurations)
                XCTAssertEqual(capability.curatedConfigurationCount, 2)
            case .steadyState, .interval, .functionalFitness:
                XCTAssertFalse(capability.hasCuratedConfigurations)
                XCTAssertEqual(capability.curatedConfigurationCount, 0)
            }
            // Every system still has a real, tested generator today —
            // the curation gap is never an executability gap.
            XCTAssertTrue(capability.hasGenerator)
        }
    }

    func testWellFormedParametersAreInstantiableAcrossAllFiveSystems() {
        let wellFormed: [GeneratorParameters] = [
            .hypertrophy(HypertrophyProgramConfiguration(dayCount: 5, split: .fullBody, phaseType: .basicHypertrophy)),
            .powerlifting(PowerliftingProgramConfiguration(family: .b, dayCount: 4)),
            .steadyState(SteadyStateProgramConfiguration(
                activityType: .running, allowedActivityTypes: [.running], daysPerWeek: 2,
                lengthWeeks: 4, progressionDimension: .duration
            )),
        ]
        for parameters in wellFormed {
            XCTAssertTrue(ProgramCapabilityRegistry.canInstantiate(parameters), "\(parameters.system) should be instantiable")
        }
    }

    /// §42 test 25 — `ProgramCapabilityRegistry` rejects a nonexistent
    /// configuration (structurally invalid parameters), never silently
    /// accepting it.
    func testStructurallyInvalidParametersAreRejected() {
        let invalidHypertrophy = GeneratorParameters.hypertrophy(
            HypertrophyProgramConfiguration(dayCount: 0, split: .fullBody, phaseType: .basicHypertrophy)
        )
        XCTAssertFalse(ProgramCapabilityRegistry.canInstantiate(invalidHypertrophy))

        let invalidSteadyState = GeneratorParameters.steadyState(
            SteadyStateProgramConfiguration(
                activityType: .running, allowedActivityTypes: [.running], daysPerWeek: 0,
                lengthWeeks: 4, progressionDimension: .duration
            )
        )
        XCTAssertFalse(ProgramCapabilityRegistry.canInstantiate(invalidSteadyState))
    }
}
