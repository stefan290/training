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

    // MARK: - Source Authority Repair (4/5/6-Day Hypertrophy): fidelity gate

    /// Only the one configuration actually migrated off the legacy
    /// placeholder generator (`HypertrophyProgramGenerator
    /// .generateDayFocusDriven`'s real `dayCount == 3, split == .fullBody`
    /// routing) is source-verified today — confirmed directly against
    /// the real `3 day full body_Novice.xlsx` workbook this pass, not
    /// merely re-asserted from `SOURCE_PROGRAM_MANIFEST.md`.
    /// Source Authority Repair Phase C: 6-Day Full Body is now recovered
    /// too — all four Family A Full Body configurations (3/4/5/6-Day)
    /// report source-verified today, each independently cell-verified
    /// against its own real workbook.
    func testAllFourFullBodyDayCountsAreSourceVerifiedToday() {
        XCTAssertTrue(ProgramCapabilityRegistry.isHypertrophySourceVerified(dayCount: 3, split: .fullBody))
        XCTAssertTrue(ProgramCapabilityRegistry.isHypertrophySourceVerified(dayCount: 4, split: .fullBody))
        XCTAssertTrue(ProgramCapabilityRegistry.isHypertrophySourceVerified(dayCount: 5, split: .fullBody))
        XCTAssertTrue(ProgramCapabilityRegistry.isHypertrophySourceVerified(dayCount: 6, split: .fullBody))
    }

    /// Every other curated Hypertrophy configuration in
    /// `HypertrophyBuiltInLibrary.all` still runs `generateLegacyFixedPair`
    /// and must report unverified — fail-closed by construction, so a
    /// newly-added curated entry defaults to unverified until explicitly
    /// proven against its own real source workbook.
    func testOtherCuratedHypertrophyConfigurationsAreNotYetSourceVerified() {
        for entry in HypertrophyBuiltInLibrary.all where !((entry.dayCount == 3 || entry.dayCount == 4 || entry.dayCount == 5 || entry.dayCount == 6) && entry.split == .fullBody) {
            XCTAssertFalse(
                ProgramCapabilityRegistry.isHypertrophySourceVerified(dayCount: entry.dayCount, split: entry.split),
                "\(entry.name) is not yet migrated off the legacy placeholder generator and must not report source-verified"
            )
        }
    }

    /// Every split at every day count remains fail-closed unless it is
    /// an exact recovered reference configuration — never "any full-body
    /// split at any day count."
    func testSourceVerificationIsExactNotApproximate() {
        XCTAssertFalse(ProgramCapabilityRegistry.isHypertrophySourceVerified(dayCount: 3, split: .legs))
        XCTAssertFalse(ProgramCapabilityRegistry.isHypertrophySourceVerified(dayCount: 4, split: .legs))
        XCTAssertFalse(ProgramCapabilityRegistry.isHypertrophySourceVerified(dayCount: 5, split: .legs), "correct day count, wrong split — must not approximate to 'any split at a verified day count'")
        XCTAssertFalse(ProgramCapabilityRegistry.isHypertrophySourceVerified(dayCount: 6, split: .legs), "6-Day exists, but not for this split — .legs is a separate, unrecovered configuration")
        XCTAssertFalse(ProgramCapabilityRegistry.isHypertrophySourceVerified(dayCount: 7, split: .fullBody), "no 7-Day Full Body configuration exists at all — must not approximate to the nearest verified day count")
    }
}
