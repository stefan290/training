import XCTest
import SwiftData
@testable import TrainingOS

/// Running R2.7/Testing J: scheduled threshold-recalibration enforcement.
/// HowTo.txt line 13: "There are scheduled Threshold Pace Adjustment
/// reminders within the plan... Don't adjust any other time." Mirrors
/// `SourceRMCalibrationTests`' persistence discipline.
@MainActor
final class RunningThresholdRecalibrationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var instance: ProgramInstance!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
        instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        try context.save()
    }

    func testInitialCalibrationIsAlwaysAllowedEvenWithoutAScheduledCheckpoint() throws {
        let recorded = RecordRunningThresholdCalibrationUseCase.record(
            thresholdPaceSecondsPerKilometer: 300, for: instance, isScheduledCheckpoint: false, modelContext: context
        )
        XCTAssertNotNil(recorded)
        XCTAssertEqual(recorded?.reasonCode, .initialCalibration)
        try context.save()
        XCTAssertEqual(instance.runningThresholdCalibrations.count, 1)
    }

    func testSecondCalibrationIsRejectedWhenNotAtAScheduledCheckpoint() throws {
        RecordRunningThresholdCalibrationUseCase.record(thresholdPaceSecondsPerKilometer: 300, for: instance, isScheduledCheckpoint: false, modelContext: context)
        try context.save()

        let secondAttempt = RecordRunningThresholdCalibrationUseCase.record(
            thresholdPaceSecondsPerKilometer: 290, for: instance, isScheduledCheckpoint: false, modelContext: context
        )
        XCTAssertNil(secondAttempt, "workout performance/athlete whim must never silently rewrite threshold outside a scheduled checkpoint")
        XCTAssertEqual(instance.runningThresholdCalibrations.count, 1)
        XCTAssertEqual(RecordRunningThresholdCalibrationUseCase.currentThreshold(for: instance)?.thresholdPaceSecondsPerKilometer, 300)
    }

    func testSecondCalibrationIsAllowedAtAnExplicitlyFlaggedScheduledCheckpoint() throws {
        RecordRunningThresholdCalibrationUseCase.record(thresholdPaceSecondsPerKilometer: 300, for: instance, isScheduledCheckpoint: false, modelContext: context)
        try context.save()

        let secondAttempt = RecordRunningThresholdCalibrationUseCase.record(
            thresholdPaceSecondsPerKilometer: 290, for: instance, isScheduledCheckpoint: true, modelContext: context
        )
        XCTAssertNotNil(secondAttempt)
        XCTAssertEqual(secondAttempt?.reasonCode, .recordedAtScheduledCheckpoint)
        try context.save()
        XCTAssertEqual(instance.runningThresholdCalibrations.count, 2)
        XCTAssertEqual(RecordRunningThresholdCalibrationUseCase.currentThreshold(for: instance)?.thresholdPaceSecondsPerKilometer, 290)
    }

    func testNoAlgorithmForComputingTheNewThresholdIsInvented() {
        // The use case's only numeric input is the literal value the
        // caller supplies — there is no code path anywhere in this type
        // that derives a threshold from performance data itself
        // (CLAUDE.md rule 10; R2.7's own explicit instruction not to
        // invent the missing calculation).
        let recorded = RecordRunningThresholdCalibrationUseCase.record(
            thresholdPaceSecondsPerKilometer: 312.5, for: instance, isScheduledCheckpoint: false, modelContext: context
        )
        XCTAssertEqual(recorded?.thresholdPaceSecondsPerKilometer, 312.5)
    }

    func testGateReasonCodesAreExplainableWithoutHiddenState() {
        XCTAssertEqual(RunningThresholdRecalibrationGate.evaluate(isInitialCalibration: true, isScheduledCheckpoint: false).reasonCode, .initialCalibration)
        XCTAssertEqual(RunningThresholdRecalibrationGate.evaluate(isInitialCalibration: false, isScheduledCheckpoint: true).reasonCode, .recordedAtScheduledCheckpoint)
        let rejected = RunningThresholdRecalibrationGate.evaluate(isInitialCalibration: false, isScheduledCheckpoint: false)
        XCTAssertFalse(rejected.allowed)
        XCTAssertEqual(rejected.reasonCode, .rejectedNotAtScheduledCheckpoint)
    }
}
