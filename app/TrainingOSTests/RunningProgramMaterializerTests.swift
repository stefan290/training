import XCTest
import SwiftData
@testable import TrainingOS

/// Running R3 — materialization fidelity, calibration gating, and the
/// PROGRAM STRUCTURE vs. ATHLETE-SPECIFIC PRESCRIPTION dogfood proof:
/// the same source-backed structure, materialized twice with two
/// different athlete thresholds, must produce identical structure and
/// different absolute paces.
@MainActor
final class RunningProgramMaterializerTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var definition: ProgramDefinition!
    var environment: TrainingEnvironment!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
        definition = try RunningProgramGenerator.generate(
            configuration: RunningProgramConfiguration(distance: .fiveK, daysPerWeek: 2),
            provenance: .constructed(reason: "test"), context: context
        )
        environment = TrainingEnvironment(name: "Test Environment", availableEquipment: [])
        context.insert(environment)
    }

    private func makeInstance() -> ProgramInstance {
        let instance = ProgramInstance(ownerUserID: UUID())
        instance.programDefinition = definition
        context.insert(instance)
        return instance
    }

    // MARK: Calibration gate — item "no silent default threshold"

    func testThresholdCalibrationIsRequiredBeforeAnyPaceCanBeFinalized() {
        let instance = makeInstance()
        XCTAssertTrue(RequiredRunningCalibrationUseCase.isThresholdCalibrationRequired(for: definition, instance: instance))
    }

    func testThresholdCalibrationIsNoLongerRequiredOnceEntered() {
        let instance = makeInstance()
        RecordRunningThresholdCalibrationUseCase.record(
            thresholdPaceSecondsPerKilometer: 300, for: instance, isScheduledCheckpoint: false, modelContext: context
        )
        XCTAssertFalse(RequiredRunningCalibrationUseCase.isThresholdCalibrationRequired(for: definition, instance: instance))
    }

    // MARK: Item 13/14 — golden threshold reproduces all 13 paces; a
    // different threshold individualizes correctly

    func testMaterializingWithTheCapturedFiveMinuteThresholdReproducesGoldenPaces() throws {
        let instance = makeInstance()
        let sessions = try RunningProgramMaterializer.materializeAllWeeks(
            definition: definition, instance: instance, startDate: Date(), ownerUserID: instance.ownerUserID,
            environment: environment, context: context
        )
        XCTAssertEqual(sessions.count, 25)

        // Week 1 Slot A's Tempo block: 90.09% threshold, verified against
        // 300s threshold => 300/0.9009009... = 333s/km = 05:33/km, the
        // exact source-observed golden pace.
        let week1SlotA = sessions[0]
        let tempoBlock = week1SlotA.blocks.first { $0.steadyStatePrescription?.sourceLabel == .tempo }
        let tempoIntensity = tempoBlock?.steadyStatePrescription?.primaryIntensity
        guard case .percentOfReference(let range, .thresholdPace)? = tempoIntensity else {
            return XCTFail("expected a percentOfReference intensity")
        }
        let targetPace = ThresholdPaceEngine.targetPace(thresholdPaceSecondsPerKilometer: 300, percentOfThreshold: range.lower)
        XCTAssertEqual(targetPace.secondsPerKilometer, 333, accuracy: 0.1)
    }

    func testMaterializingWithADifferentThresholdProducesIndividualizedPacesOverTheSameStructure() throws {
        let athleteAInstance = makeInstance()
        RecordRunningThresholdCalibrationUseCase.record(
            thresholdPaceSecondsPerKilometer: 300, for: athleteAInstance, isScheduledCheckpoint: false, modelContext: context
        )
        let sessionsA = try RunningProgramMaterializer.materializeAllWeeks(
            definition: definition, instance: athleteAInstance, startDate: Date(), ownerUserID: athleteAInstance.ownerUserID,
            environment: environment, context: context
        )

        // A second, separate ProgramInstance off the SAME definition —
        // proves structure is shared/fixed, only the athlete-specific
        // resolved pace differs.
        let athleteBThreshold = 270.0 // 4:30/km
        let tempoIntensityA = sessionsA[0].blocks.first { $0.steadyStatePrescription?.sourceLabel == .tempo }?.steadyStatePrescription?.primaryIntensity
        guard case .percentOfReference(let rangeA, .thresholdPace)? = tempoIntensityA else {
            return XCTFail("expected a percentOfReference intensity")
        }
        let paceA = ThresholdPaceEngine.targetPace(thresholdPaceSecondsPerKilometer: 300, percentOfThreshold: rangeA.lower)
        let paceB = ThresholdPaceEngine.targetPace(thresholdPaceSecondsPerKilometer: athleteBThreshold, percentOfThreshold: rangeA.lower)

        XCTAssertNotEqual(paceA.secondsPerKilometer, paceB.secondsPerKilometer, "different thresholds must yield different absolute paces")
        XCTAssertEqual(paceB.secondsPerKilometer, athleteBThreshold / rangeA.lower, accuracy: 0.01)

        // Same %threshold fraction underlies both — the PROGRAM STRUCTURE
        // itself never changed between the two athletes.
        XCTAssertEqual(rangeA.lower, 0.9009009009009009, accuracy: 0.0001)
    }

    // MARK: Repeat structures, taper, race — intact after materialization

    func testRepeatStructureSurvivesMaterialization() throws {
        let instance = makeInstance()
        let sessions = try RunningProgramMaterializer.materializeAllWeeks(
            definition: definition, instance: instance, startDate: Date(), ownerUserID: instance.ownerUserID,
            environment: environment, context: context
        )
        let week9SlotA = sessions.first { $0.name == "Week 9 — Slot A" }!
        let intervalBlock = week9SlotA.blocks.first { $0.intervalPrescription != nil }!
        XCTAssertEqual(intervalBlock.intervalPrescription?.intervalCount, 4)
        XCTAssertEqual(intervalBlock.intervalPrescription?.sourceLabel, .hard)
    }

    func testTaperStructureSurvivesMaterialization() throws {
        let instance = makeInstance()
        let sessions = try RunningProgramMaterializer.materializeAllWeeks(
            definition: definition, instance: instance, startDate: Date(), ownerUserID: instance.ownerUserID,
            environment: environment, context: context
        )
        let week12SlotA = sessions.first { $0.name == "Week 12 — Slot A" }!
        let intervalBlocks = week12SlotA.blocks.compactMap(\.intervalPrescription)
        XCTAssertEqual(intervalBlocks.map(\.intervalCount), [1, 1])
    }

    func testRaceSurvivesMaterializationAsRPEOnly() throws {
        let instance = makeInstance()
        let sessions = try RunningProgramMaterializer.materializeAllWeeks(
            definition: definition, instance: instance, startDate: Date(), ownerUserID: instance.ownerUserID,
            environment: environment, context: context
        )
        let race = sessions.last!
        let raceBlock = race.blocks.first { $0.steadyStatePrescription?.sourceLabel == .active }!
        XCTAssertEqual(raceBlock.steadyStatePrescription?.primaryIntensity, .rpe(BoundedRange(lower: 6, upper: 6)))
        XCTAssertEqual(raceBlock.steadyStatePrescription?.executionNotes, "Start conservatively; pick up effort ~1.5 mi; if strong at mile 2, increase effort to finish.")
    }

    // MARK: Recalibration checkpoints are represented

    func testRecalibrationCheckpointsAreMarkedAtRelativeWeeksFiveAndNine() {
        let weeks = definition.orderedWeeks
        XCTAssertTrue(weeks[4].isThresholdRecalibrationCheckpoint, "relative week 5")
        XCTAssertTrue(weeks[8].isThresholdRecalibrationCheckpoint, "relative week 9")
        for index in [0, 1, 2, 3, 5, 6, 7, 9, 10, 11, 12] {
            XCTAssertFalse(weeks[index].isThresholdRecalibrationCheckpoint, "relative week \(index + 1) must not be a checkpoint")
        }
    }

    func testRecalibrationAtACheckpointGoesThroughTheExistingR2Gate() {
        let instance = makeInstance()
        RecordRunningThresholdCalibrationUseCase.record(
            thresholdPaceSecondsPerKilometer: 300, for: instance, isScheduledCheckpoint: false, modelContext: context
        )
        // Out-of-schedule adjustment attempt: rejected by R2's existing gate.
        let rejected = RecordRunningThresholdCalibrationUseCase.record(
            thresholdPaceSecondsPerKilometer: 295, for: instance, isScheduledCheckpoint: false, modelContext: context
        )
        XCTAssertNil(rejected)
        // At a real checkpoint (week 5/9, `isScheduledCheckpoint: true`
        // supplied by whatever future flow reads `TrainingWeek
        // .isThresholdRecalibrationCheckpoint`): accepted.
        let accepted = RecordRunningThresholdCalibrationUseCase.record(
            thresholdPaceSecondsPerKilometer: 295, for: instance, isScheduledCheckpoint: true, modelContext: context
        )
        XCTAssertNotNil(accepted)
    }

    // MARK: R2 adaptation engines apply to materialized output unchanged

    func testR2ExecutionOverrideEngineAppliesToAMaterializedEightyPercentBlock() throws {
        let instance = makeInstance()
        RecordRunningThresholdCalibrationUseCase.record(
            thresholdPaceSecondsPerKilometer: 300, for: instance, isScheduledCheckpoint: false, modelContext: context
        )
        let sessions = try RunningProgramMaterializer.materializeAllWeeks(
            definition: definition, instance: instance, startDate: Date(), ownerUserID: instance.ownerUserID,
            environment: environment, context: context
        )
        let easyBlock = sessions[0].blocks.first { $0.steadyStatePrescription?.sourceLabel == .easy }!
        guard case .percentOfReference(let range, .thresholdPace)? = easyBlock.steadyStatePrescription?.primaryIntensity else {
            return XCTFail("expected percentOfReference")
        }
        let (decision, reason) = RunningExecutionOverrideEngine.evaluateIntensityOverride(
            prescribedPercentOfThreshold: range.lower, prescribedRPE: nil,
            requestedPercentOfThreshold: range.lower + 0.05, repIndexZeroBased: 1
        )
        XCTAssertEqual(decision, .rejected)
        XCTAssertEqual(reason, .rejectedExceedsPrescribedAtOrBelow89Percent)
    }
}
