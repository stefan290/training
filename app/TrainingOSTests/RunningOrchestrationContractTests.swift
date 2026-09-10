import XCTest
@testable import TrainingOS

/// Running R2.10/Testing S: orchestration-facing metadata tests. Proves
/// the contract is built entirely from already-existing fields
/// (`TrainingStressProfile`, `SessionRole`) — no new persisted scheduling
/// decision is introduced, and no source recommendation is silently
/// promoted to a mandatory constraint without citation.
final class RunningOrchestrationContractTests: XCTestCase {
    func testQualityRolesClassifyAsQuality() {
        for role: SessionRole in [.tempo, .threshold, .interval] {
            XCTAssertEqual(RunningOrchestrationContract.qualityClassification(for: role), .quality, "\(role) must classify as quality")
        }
    }

    func testEasyRolesClassifyAsEasy() {
        for role: SessionRole in [.easy, .recovery, .aerobicBase, .long] {
            XCTAssertEqual(RunningOrchestrationContract.qualityClassification(for: role), .easy, "\(role) must classify as easy")
        }
    }

    func testRolesWithNoHonestRunningQualityDistinctionReturnNil() {
        for role: SessionRole in [.strength, .hypertrophy, .functionalFitness, .skill, .mixed] {
            XCTAssertNil(RunningOrchestrationContract.qualityClassification(for: role), "\(role) has no honestly derivable running quality/easy distinction")
        }
    }

    func testMetadataReusesRecoveryDemandFromTrainingStressProfileRatherThanANewField() {
        let profile = TrainingStressProfile(
            overallIntensity: .high, systemicDemand: .high, lowerBodyLoad: .high, upperBodyLoad: .none,
            impactLoading: .high, metabolicDemand: .high, durationClassification: .medium, modality: .running,
            recoveryDemand: .high
        )
        let metadata = RunningOrchestrationContract.metadata(
            activityType: .running, sessionRole: .interval, trainingStressProfile: profile, isPlannedReductionWeek: false
        )
        XCTAssertEqual(metadata.recoverySensitivity, .high)
        XCTAssertEqual(metadata.qualityClassification, .quality)
        XCTAssertEqual(metadata.isPlannedReductionWeek, false)
    }

    func testMetadataHandlesAbsentTrainingStressProfileAndUnknownReductionStatusHonestly() {
        let metadata = RunningOrchestrationContract.metadata(
            activityType: .running, sessionRole: .easy, trainingStressProfile: nil, isPlannedReductionWeek: nil
        )
        XCTAssertNil(metadata.recoverySensitivity)
        XCTAssertNil(metadata.isPlannedReductionWeek)
        XCTAssertEqual(metadata.qualityClassification, .easy)
    }

    // MARK: Mandatory vs. advisory classification is documented and citable

    func testNoCrossDomainRuleIsClassifiedMandatoryGivenSourceHedgeLanguageAndExplicitOverridePaths() {
        let allRules = [
            RunningOrchestrationContract.liftingSequencedAfterRunning,
            RunningOrchestrationContract.liftingBeforeRunningRequiresPaceReduction,
            RunningOrchestrationContract.enduranceProgramsNotStackable,
            RunningOrchestrationContract.liftingFrequencyModificationLimits,
        ]
        for rule in allRules {
            XCTAssertEqual(rule.strength, .advisory, "\(rule.citation) has an explicit override path in source and must not be mandatory")
            XCTAssertFalse(rule.citation.isEmpty)
        }
    }
}
