import XCTest
import SwiftData
@testable import TrainingOS

/// Running R2 — Dogfood / Proof. An isolated domain-level harness
/// exercising every required scenario end-to-end against a real
/// `ModelContainer`/`ModelContext`, at an athlete threshold of 5:00/km —
/// not UI dogfooding, per the checkpoint's own instruction.
@MainActor
final class RunningFoundationDogfoodTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var instance: ProgramInstance!
    let thresholdSecondsPerKm = 300.0 // 5:00/km

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
        instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        RecordRunningThresholdCalibrationUseCase.record(
            thresholdPaceSecondsPerKilometer: thresholdSecondsPerKm, for: instance, isScheduledCheckpoint: false, modelContext: context
        )
        try context.save()
    }

    func testDogfoodProof_ThresholdPaceCalculations() {
        let eightyPercent = ThresholdPaceEngine.targetPace(thresholdPaceSecondsPerKilometer: thresholdSecondsPerKm, percentOfThreshold: 0.80)
        XCTAssertEqual(eightyPercent.secondsPerKilometer, 375, accuracy: 0.0001) // 6:15/km
        let (m1, s1) = ThresholdPaceEngine.displayMinutesAndSeconds(for: eightyPercent)
        XCTAssertEqual(m1, 6); XCTAssertEqual(s1, 15, accuracy: 0.0001)

        let oneHundredPercent = ThresholdPaceEngine.targetPace(thresholdPaceSecondsPerKilometer: thresholdSecondsPerKm, percentOfThreshold: 1.00)
        XCTAssertEqual(oneHundredPercent.secondsPerKilometer, 300, accuracy: 0.0001) // 5:00/km

        // 110%, per the source's own observed 04:33/km value, actually
        // sits at derived %threshold 1.0989 (not a flat 1.10) — the
        // dogfood proof reproduces the SOURCE-OBSERVED figure exactly,
        // and separately shows a literal 110% for comparison.
        let observedFourThirtyThree = ThresholdPaceEngine.targetPace(thresholdPaceSecondsPerKilometer: thresholdSecondsPerKm, percentOfThreshold: 1.098901098901099)
        XCTAssertEqual(observedFourThirtyThree.secondsPerKilometer, 273, accuracy: 0.01)
        let (m2, s2) = ThresholdPaceEngine.displayMinutesAndSeconds(for: observedFourThirtyThree)
        XCTAssertEqual(m2, 4); XCTAssertEqual(s2, 33, accuracy: 0.5)

        let literalOneHundredTen = ThresholdPaceEngine.targetPace(thresholdPaceSecondsPerKilometer: thresholdSecondsPerKm, percentOfThreshold: 1.10)
        XCTAssertEqual(literalOneHundredTen.secondsPerKilometer, 272.7, accuracy: 0.1)
    }

    func testDogfoodProof_ValidEightyPercentPrescriptionAndRejectedOverrideAttempt() throws {
        let session = Session(name: "Dogfood — Slot A", modality: .conditioning)
        context.insert(session)
        let block = WorkoutBlock(type: .steadyState)
        session.addBlock(block)
        let prescription = SteadyStatePrescription(
            activityType: .running, distanceMeters: 3000,
            primaryIntensity: .percentOfReference(BoundedRange(lower: 0.80, upper: 0.80), metric: .thresholdPace),
            sourceLabel: .active
        )
        block.attachSteadyStatePrescription(prescription)
        try context.save()

        // Valid 80% prescription: persists and reads back cleanly.
        XCTAssertEqual(block.steadyStatePrescription?.primaryIntensity, .percentOfReference(BoundedRange(lower: 0.80, upper: 0.80), metric: .thresholdPace))

        // Rejected attempt to execute that 80% block at 85%.
        let (decision, reason) = RunningExecutionOverrideEngine.evaluateIntensityOverride(
            prescribedPercentOfThreshold: 0.80, prescribedRPE: nil, requestedPercentOfThreshold: 0.85, repIndexZeroBased: 1
        )
        XCTAssertEqual(decision, .rejected)
        XCTAssertEqual(reason, .rejectedExceedsPrescribedAtOrBelow89Percent)
    }

    func testDogfoodProof_RepeatGroupPrescription() throws {
        let session = Session(name: "Dogfood — Repeat Group", modality: .conditioning)
        context.insert(session)
        let block = WorkoutBlock(type: .intervals)
        session.addBlock(block)
        block.attachIntervalPrescription(IntervalPrescription(
            activityType: .running, intervalCount: 4, workDistanceMeters: 400,
            workIntensity: .percentOfReference(BoundedRange(lower: 1.0, upper: 1.0), metric: .thresholdPace),
            recoveryDistanceMeters: 400,
            recoveryIntensity: .percentOfReference(BoundedRange(lower: 0.75, upper: 0.75), metric: .thresholdPace),
            sourceLabel: .hard
        ))
        try context.save()
        XCTAssertEqual(block.intervalPrescription?.intervalCount, 4)
        XCTAssertEqual(block.intervalPrescription?.sourceLabel, .hard)
    }

    func testDogfoodProof_RPEOnlyPrescription() throws {
        let session = Session(name: "Dogfood — Race", modality: .conditioning)
        context.insert(session)
        let block = WorkoutBlock(type: .steadyState)
        session.addBlock(block)
        block.attachSteadyStatePrescription(SteadyStatePrescription(
            activityType: .running, distanceMeters: 5000,
            primaryIntensity: .rpe(BoundedRange(lower: 6, upper: 6)),
            sourceLabel: .active,
            executionNotes: "Start conservatively; pick up effort ~1.5 mi; if strong at mile 2, increase effort to finish."
        ))
        try context.save()
        XCTAssertEqual(block.steadyStatePrescription?.primaryIntensity, .rpe(BoundedRange(lower: 6, upper: 6)))
    }

    func testDogfoodProof_MissedSessionAndIllnessWeekDecisions() {
        let (missedDecision, missedReason) = RunningReEntryEngine.singleMissedWorkout(wouldCompromiseNextSession: false)
        XCTAssertEqual(missedDecision, .moveOneDayLater)
        XCTAssertEqual(missedReason, .singleWorkoutMovedOneDayLater)

        let (illnessDecision, illnessReason) = RunningReEntryEngine.wholeWeekMissed(cause: .illness, previousWeekWasDeload: false)
        XCTAssertEqual(illnessDecision, .repeatPreviousWeek)
        XCTAssertEqual(illnessReason, .wholeWeekIllnessRepeatPreviousWeek)
    }

    func testDogfoodProof_ScheduledRecalibrationBehavior() throws {
        // Athlete already has an initial 5:00/km calibration from setUp.
        // An out-of-schedule adjustment attempt is rejected...
        let rejected = RecordRunningThresholdCalibrationUseCase.record(
            thresholdPaceSecondsPerKilometer: 290, for: instance, isScheduledCheckpoint: false, modelContext: context
        )
        XCTAssertNil(rejected)
        XCTAssertEqual(RecordRunningThresholdCalibrationUseCase.currentThreshold(for: instance)?.thresholdPaceSecondsPerKilometer, thresholdSecondsPerKm)

        // ...while the same adjustment at a flagged scheduled checkpoint succeeds.
        let accepted = RecordRunningThresholdCalibrationUseCase.record(
            thresholdPaceSecondsPerKilometer: 290, for: instance, isScheduledCheckpoint: true, modelContext: context
        )
        try context.save()
        XCTAssertNotNil(accepted)
        XCTAssertEqual(RecordRunningThresholdCalibrationUseCase.currentThreshold(for: instance)?.thresholdPaceSecondsPerKilometer, 290)
    }
}
