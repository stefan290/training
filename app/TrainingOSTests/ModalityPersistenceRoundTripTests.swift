import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 3C §28: create -> save -> fresh ModelContext -> fetch ->
/// semantic equality / expected relationships, for every new persisted
/// type introduced in this pass. Complements `ModalityArchitectureProofTests`
/// (which never saves) — this file exists specifically to catch anything
/// that only breaks after a real save/refetch cycle, the same discipline
/// `PersistenceRoundTripTests.swift` already applies to the Stage 1-2 graph.
@MainActor
final class ModalityPersistenceRoundTripTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func freshContext() -> ModelContext {
        ModelContext(container)
    }

    func testSteadyStatePrescriptionSurvivesRoundTrip() throws {
        let block = WorkoutBlock(type: .steadyState)
        context.insert(block)
        let prescriptionID = UUID()
        let prescription = SteadyStatePrescription(
            id: prescriptionID,
            activityType: .cycling,
            durationSeconds: 2700,
            distanceMeters: 22000,
            primaryIntensity: .heartRateZone(.two),
            secondaryIntensity: .cadence(BoundedRange(85...95))
        )
        context.insert(prescription)
        block.attachSteadyStatePrescription(prescription)
        try context.save()

        let reloaded = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<SteadyStatePrescription>(predicate: #Predicate { $0.id == prescriptionID })).first
        )
        XCTAssertEqual(reloaded.activityType, .cycling)
        XCTAssertEqual(reloaded.durationSeconds, 2700)
        XCTAssertEqual(reloaded.primaryIntensity, .heartRateZone(.two))
        XCTAssertEqual(reloaded.secondaryIntensity, .cadence(BoundedRange(85...95)))
        XCTAssertNotNil(reloaded.workoutBlock)
        XCTAssertEqual(reloaded.workoutBlock?.id, block.id)
    }

    func testIntervalPrescriptionAndResultWithRepsSurviveRoundTrip() throws {
        let block = WorkoutBlock(type: .intervals)
        context.insert(block)

        let prescription = IntervalPrescription(
            activityType: .rowing,
            intervalCount: 4,
            workDurationSeconds: 240,
            workIntensity: .strokeRate(BoundedRange(28...32)),
            recoveryDurationSeconds: 180,
            recoveryIntensity: .heartRatePercent(BoundedRange(0.70...0.70))
        )
        context.insert(prescription)
        block.attachIntervalPrescription(prescription)

        let resultID = UUID()
        let result = IntervalResult(id: resultID, sessionDurationSeconds: 1680, averageHeartRate: 165)
        context.insert(result)
        block.attachIntervalResult(result)
        for index in 0..<4 {
            let rep = IntervalRepResult(actualWorkDurationSeconds: 240, averagePower: 220 + index, wasCompletedAsPrescribed: true)
            context.insert(rep)
            result.addRepResult(rep)
        }
        try context.save()

        let reloadedResult = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<IntervalResult>(predicate: #Predicate { $0.id == resultID })).first
        )
        XCTAssertEqual(reloadedResult.orderedRepResults.count, 4)
        XCTAssertEqual(reloadedResult.orderedRepResults.map(\.sortIndex), [0, 1, 2, 3])
        XCTAssertEqual(reloadedResult.orderedRepResults.map(\.averagePower), [220, 221, 222, 223])
        // Individual intervals remain inspectable, not collapsed into one
        // session-average value — Stage 3B/3C §11's explicit requirement.
    }

    func testFunctionalFitnessPrescriptionAndScaledResultSurviveRoundTrip() throws {
        let toesToBar = Exercise(canonicalName: "Toes-to-Bar", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "core")
        let kneeRaise = Exercise(canonicalName: "Knee Raises", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "core")
        context.insert(toesToBar)
        context.insert(kneeRaise)

        let block = WorkoutBlock(type: .functionalFitness)
        context.insert(block)

        let prescription = FunctionalFitnessPrescription(
            stimulus: Stimulus(
                targetDurationDomain: .medium, intensity: .high, loading: .bodyweightOnly,
                movementFunctions: [.gymnasticsPull], movementModalityMix: [ModalityCount(modality: .gymnastics, count: 1)],
                skillDemand: .high, systemicDemand: .moderate, scoreType: .roundsAndReps
            ),
            format: .amrap(capSeconds: 720)
        )
        context.insert(prescription)
        block.attachFunctionalFitnessPrescription(prescription)
        let movement = FunctionalFitnessMovement(exercise: toesToBar, reps: 12)
        context.insert(movement)
        prescription.addMovement(movement)

        let resultID = UUID()
        let result = FunctionalFitnessResult(
            id: resultID, scoreType: .roundsAndReps, scoreValue: .roundsAndReps(rounds: 7, partialReps: 14),
            scoreDirection: .higherIsBetter, resultContext: .scaled
        )
        context.insert(result)
        block.attachFunctionalFitnessResult(result)
        let performed = FunctionalFitnessPerformedMovement(
            prescribedMovement: movement,
            performedExercise: kneeRaise,
            performedReps: 12
        )
        context.insert(performed)
        result.addPerformedMovement(performed)
        try context.save()

        let reloadedResult = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<FunctionalFitnessResult>(predicate: #Predicate { $0.id == resultID })).first
        )
        XCTAssertEqual(reloadedResult.resultContext, .scaled)
        XCTAssertEqual(reloadedResult.scoreValue, .roundsAndReps(rounds: 7, partialReps: 14))
        let reloadedPerformed = try XCTUnwrap(reloadedResult.orderedPerformedMovements.first)
        XCTAssertEqual(reloadedPerformed.prescribedMovement?.exercise?.canonicalName, "Toes-to-Bar")
        XCTAssertEqual(reloadedPerformed.performedExercise?.canonicalName, "Knee Raises")
        // The original prescription was never mutated to represent the
        // scale — it still reads "Toes-to-Bar," with the performed variant
        // recorded alongside it. Stage 3C §13.
    }

    func testBenchmarkDefinitionAndPerformanceProfileSurviveRoundTrip() throws {
        let benchmark = BenchmarkDefinition(
            canonicalID: "benchmark.fran",
            name: "Fran",
            stimulus: Stimulus(
                targetDurationDomain: .short, intensity: .high, loading: .moderate,
                movementFunctions: [.hingeLoaded, .gymnasticsPull],
                movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1), ModalityCount(modality: .gymnastics, count: 1)],
                skillDemand: .moderate, systemicDemand: .high, scoreType: .time
            ),
            format: .forTime(capSeconds: nil),
            scoreType: .time,
            scoreDirection: .lowerIsBetter
        )
        context.insert(benchmark)

        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        let benchmarkProfileID = UUID()
        let benchmarkProfile = BenchmarkPerformanceProfile(id: benchmarkProfileID)
        context.insert(benchmarkProfile)
        performanceProfile.addBenchmarkProfile(benchmarkProfile)
        benchmarkProfile.benchmark = benchmark

        let result = FunctionalFitnessResult(
            scoreType: .time, scoreValue: .time(seconds: 245), scoreDirection: .lowerIsBetter, resultContext: .rx
        )
        context.insert(result)
        result.benchmark = benchmark
        benchmarkProfile.addResult(result)
        try context.save()

        let reloadedProfile = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<BenchmarkPerformanceProfile>(predicate: #Predicate { $0.id == benchmarkProfileID })).first
        )
        XCTAssertEqual(reloadedProfile.benchmark?.canonicalID, "benchmark.fran")
        XCTAssertEqual(reloadedProfile.results.count, 1)
        XCTAssertEqual(reloadedProfile.results.first?.scoreValue, .time(seconds: 245))
    }

    func testActivityPerformanceProfileDistinguishesContext() throws {
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)

        let generalRunning = ActivityPerformanceProfile(activityType: .running)
        context.insert(generalRunning)
        performanceProfile.addActivityProfile(generalRunning)

        let fiveKRunning = ActivityPerformanceProfile(activityType: .running, performanceContext: "5K")
        context.insert(fiveKRunning)
        performanceProfile.addActivityProfile(fiveKRunning)

        let profileID = performanceProfile.id
        try context.save()

        let reloadedProfile = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<PerformanceProfile>(predicate: #Predicate { $0.id == profileID })).first
        )
        let general = try XCTUnwrap(reloadedProfile.activityProfile(for: .running))
        let fiveK = try XCTUnwrap(reloadedProfile.activityProfile(for: .running, context: "5K"))
        XCTAssertNotEqual(general.id, fiveK.id)
        XCTAssertNil(general.performanceContext)
        XCTAssertEqual(fiveK.performanceContext, "5K")
        // Stage 3C §21: "5K" is never the same identity as generic Running.
    }

    func testWorkoutBlockTrainingStressProfileSurvivesRoundTrip() throws {
        let blockID = UUID()
        let block = WorkoutBlock(
            id: blockID,
            type: .steadyState,
            trainingStressProfile: TrainingStressProfile(
                overallIntensity: .moderate,
                systemicDemand: .high,
                lowerBodyLoad: .high,
                upperBodyLoad: .none,
                impactLoading: .low,
                metabolicDemand: .high,
                durationClassification: .long,
                modality: .running,
                recoveryDemand: .moderate
            )
        )
        context.insert(block)
        try context.save()

        let reloaded = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<WorkoutBlock>(predicate: #Predicate { $0.id == blockID })).first
        )
        let profile = try XCTUnwrap(reloaded.trainingStressProfile)
        XCTAssertEqual(profile.overallIntensity, .moderate)
        XCTAssertEqual(profile.systemicDemand, .high)
        XCTAssertEqual(profile.lowerBodyLoad, .high)
        XCTAssertEqual(profile.upperBodyLoad, .none)
        XCTAssertEqual(profile.impactLoading, .low)
        XCTAssertEqual(profile.metabolicDemand, .high)
        XCTAssertEqual(profile.durationClassification, .long)
        XCTAssertEqual(profile.modality, .running)
        XCTAssertEqual(profile.recoveryDemand, .moderate)
        // No existing test exercised this before the first Xcode
        // verification pass of Stage 3C; added specifically because
        // IntensityTarget's ClosedRange round-trip crash (see
        // BoundedRange's doc comment) showed a plain-looking Codable
        // value type stored on an @Model can still break SwiftData at
        // save time — TrainingStressProfile only holds simple enums, so
        // this confirms it doesn't share that failure mode.
    }
}
