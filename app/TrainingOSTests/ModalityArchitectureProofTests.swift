import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 3C §27: proves the production domain types — unchanged
/// `ExercisePrescription`/`SetResult` plus the new typed
/// `BlockPrescription`/`BlockResult` siblings — can represent all 14
/// required scenarios. These are architecture *representation* tests, not
/// programming-engine tests: each one constructs the minimum graph needed
/// to prove the shape holds, then asserts `WorkoutBlock.blockPrescription`/
/// `.blockResult` synthesize the expected case.
@MainActor
final class ModalityArchitectureProofTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func makeExercise(_ name: String, _ modality: TrainingModality = .functionalFitness) -> Exercise {
        let exercise = Exercise(canonicalName: name, modality: modality, equipment: "mixed", movementPattern: "mixed")
        context.insert(exercise)
        return exercise
    }

    private func makeDay() -> Day {
        let day = Day(ownerUserID: UUID(), date: Date())
        context.insert(day)
        return day
    }

    // MARK: 1. Bench Press 3x8-12 @ 2 RIR

    func testBenchPress3x8to12At2RIR() throws {
        let exercise = makeExercise("Barbell Bench Press", .hypertrophy)
        let session = Session(name: "Push", modality: .hypertrophy)
        context.insert(session)
        let block = WorkoutBlock(type: .hypertrophy)
        context.insert(block)
        session.addBlock(block)

        let movement = ExercisePrescription(exercise: exercise)
        context.insert(movement)
        block.addPrescription(movement)

        var results: [SetResult] = []
        for index in 0..<3 {
            let setPrescription = SetPrescription(repRangeLow: 8, repRangeHigh: 12, targetWeight: 60, targetRir: 2)
            context.insert(setPrescription)
            movement.addSetPrescription(setPrescription)

            let result = SetResult(setIndex: index, weight: 60, reps: 10, targetRir: 2, actualRir: 2)
            context.insert(result)
            setPrescription.addResult(result)
            movement.addLoggedSetResult(result)
            results.append(result)
        }

        guard case .exercise(let prescriptions) = try XCTUnwrap(block.blockPrescription) else {
            return XCTFail("expected .exercise")
        }
        XCTAssertEqual(prescriptions.first?.orderedSetPrescriptions.count, 3)

        guard case .strength(let strengthResult) = try XCTUnwrap(block.blockResult) else {
            return XCTFail("expected .strength")
        }
        XCTAssertEqual(strengthResult.setResults.count, 3)
    }

    // MARK: 2. Zone 2 Bike 45 min

    func testZone2Bike45Min() throws {
        let session = Session(name: "Zone 2 Bike", modality: .conditioning, role: .aerobicBase)
        context.insert(session)
        let block = WorkoutBlock(type: .steadyState)
        context.insert(block)
        session.addBlock(block)

        let prescription = SteadyStatePrescription(
            activityType: .cycling,
            durationSeconds: 2700,
            primaryIntensity: .heartRateZone(.two)
        )
        context.insert(prescription)
        block.attachSteadyStatePrescription(prescription)

        let result = SteadyStateResult(
            actualDurationSeconds: 2700,
            actualDistanceMeters: 22000,
            averageHeartRate: 138
        )
        context.insert(result)
        block.attachSteadyStateResult(result)

        guard case .steadyState(let steadyPrescription) = try XCTUnwrap(block.blockPrescription) else {
            return XCTFail("expected .steadyState")
        }
        XCTAssertEqual(steadyPrescription.activityType, .cycling)
        XCTAssertEqual(steadyPrescription.durationSeconds, 2700)

        guard case .steadyState(let steadyResult) = try XCTUnwrap(block.blockResult) else {
            return XCTFail("expected .steadyState")
        }
        XCTAssertEqual(steadyResult.averageHeartRate, 138)
        // No strength concept required — sets/reps/RIR/load never referenced.
    }

    // MARK: 3. Alternating Run/Walk

    func testAlternatingRunWalk() throws {
        let session = Session(name: "Run/Walk Week 1", modality: .conditioning, role: .easy)
        context.insert(session)
        let warmUp = WorkoutBlock(type: .warmup)
        context.insert(warmUp)
        session.addBlock(warmUp)

        let mainBlock = WorkoutBlock(type: .intervals)
        context.insert(mainBlock)
        session.addBlock(mainBlock)

        let intervalPrescription = IntervalPrescription(
            activityType: .running,
            intervalCount: 8,
            workDurationSeconds: 60,
            workIntensity: .rpe(BoundedRange(3...5)),
            recoveryDurationSeconds: 90,
            recoveryIntensity: .rpe(BoundedRange(1...2)) // walking effort
        )
        context.insert(intervalPrescription)
        mainBlock.attachIntervalPrescription(intervalPrescription)

        let coolDown = WorkoutBlock(type: .cooldown)
        context.insert(coolDown)
        session.addBlock(coolDown)

        XCTAssertEqual(session.orderedBlocks.map(\.type), [.warmup, .intervals, .cooldown])
        guard case .intervals(let prescription) = try XCTUnwrap(mainBlock.blockPrescription) else {
            return XCTFail("expected .intervals")
        }
        XCTAssertEqual(prescription.intervalCount, 8)
        XCTAssertEqual(prescription.recoveryDurationSeconds, 90)
    }

    // MARK: 4. 5x1km intervals

    func test5x1kmIntervals() throws {
        let block = WorkoutBlock(type: .intervals)
        context.insert(block)

        let prescription = IntervalPrescription(
            activityType: .running,
            intervalCount: 5,
            workDistanceMeters: 1000,
            workIntensity: .pace(BoundedRange(Pace(secondsPerKilometer: 270)...Pace(secondsPerKilometer: 280))),
            recoveryDurationSeconds: 120,
            recoveryIntensity: .rpe(BoundedRange(1...2))
        )
        context.insert(prescription)
        block.attachIntervalPrescription(prescription)

        guard case .intervals(let result) = try XCTUnwrap(block.blockPrescription) else {
            return XCTFail("expected .intervals")
        }
        XCTAssertEqual(result.workDistanceMeters, 1000)
        XCTAssertNil(result.workDurationSeconds)
    }

    // MARK: 5-7. 4x4 VO2 running / cycling / rowing — same abstraction, different modality + unit

    private func makeVO2FourByFour(activityType: ActivityType, workTarget: IntensityTarget) -> WorkoutBlock {
        let block = WorkoutBlock(type: .intervals)
        context.insert(block)
        let prescription = IntervalPrescription(
            activityType: activityType,
            intervalCount: 4,
            workDurationSeconds: 240,
            workIntensity: workTarget,
            recoveryDurationSeconds: 180,
            recoveryIntensity: .heartRatePercent(BoundedRange(0.70...0.70))
        )
        context.insert(prescription)
        block.attachIntervalPrescription(prescription)
        return block
    }

    func test4x4VO2Running() throws {
        let block = makeVO2FourByFour(activityType: .running, workTarget: .heartRatePercent(BoundedRange(0.90...0.95)))
        guard case .intervals(let prescription) = try XCTUnwrap(block.blockPrescription) else {
            return XCTFail("expected .intervals")
        }
        XCTAssertEqual(prescription.activityType, .running)
        XCTAssertEqual(prescription.intervalCount, 4)
        XCTAssertEqual(prescription.workDurationSeconds, 240)
    }

    func test4x4VO2Cycling() throws {
        let block = makeVO2FourByFour(activityType: .cycling, workTarget: .powerZone(.four))
        guard case .intervals(let prescription) = try XCTUnwrap(block.blockPrescription) else {
            return XCTFail("expected .intervals")
        }
        XCTAssertEqual(prescription.activityType, .cycling)
        XCTAssertEqual(prescription.workIntensity, .powerZone(.four))
    }

    func test4x4VO2Rowing() throws {
        let block = makeVO2FourByFour(activityType: .rowing, workTarget: .strokeRate(BoundedRange(28...32)))
        guard case .intervals(let prescription) = try XCTUnwrap(block.blockPrescription) else {
            return XCTFail("expected .intervals")
        }
        XCTAssertEqual(prescription.activityType, .rowing)
        XCTAssertEqual(prescription.workIntensity, .strokeRate(BoundedRange(28...32)))
        // Same IntervalPrescription type as running/cycling above — only
        // `activityType` and the IntensityTarget case differ, proving the
        // modality-independent abstraction from ENDURANCE_PROGRAMMING_MODEL.md §4.
    }

    // MARK: 8. AMRAP

    func testAMRAP() throws {
        let dbThruster = makeExercise("DB Thruster")
        let toesToBar = makeExercise("Toes-to-Bar")
        let bike = makeExercise("Bike", .conditioning)

        let block = WorkoutBlock(type: .functionalFitness)
        context.insert(block)

        let prescription = FunctionalFitnessPrescription(
            stimulus: Stimulus(
                targetDurationDomain: .medium, intensity: .high, loading: .moderate,
                movementFunctions: [.hingeLoaded, .gymnasticsPull, .monostructural],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .moderate, systemicDemand: .high, scoreType: .roundsAndReps
            ),
            format: .amrap(capSeconds: 720)
        )
        context.insert(prescription)
        block.attachFunctionalFitnessPrescription(prescription)

        for (exercise, reps) in [(dbThruster, 10), (toesToBar, 12)] {
            let movement = FunctionalFitnessMovement(exercise: exercise, reps: reps)
            context.insert(movement)
            prescription.addMovement(movement)
        }
        let bikeMovement = FunctionalFitnessMovement(exercise: bike, calories: 15)
        context.insert(bikeMovement)
        prescription.addMovement(bikeMovement)

        let result = FunctionalFitnessResult(
            scoreType: .roundsAndReps,
            scoreValue: .roundsAndReps(rounds: 7, partialReps: 14),
            scoreDirection: .higherIsBetter
        )
        context.insert(result)
        block.attachFunctionalFitnessResult(result)

        guard case .functionalFitness(let storedPrescription) = try XCTUnwrap(block.blockPrescription) else {
            return XCTFail("expected .functionalFitness")
        }
        XCTAssertEqual(storedPrescription.orderedMovements.count, 3)
        if case .amrap(let cap) = storedPrescription.format {
            XCTAssertEqual(cap, 720)
        } else {
            XCTFail("expected .amrap format")
        }

        guard case .functionalFitness(let storedResult) = try XCTUnwrap(block.blockResult) else {
            return XCTFail("expected .functionalFitness")
        }
        XCTAssertEqual(storedResult.scoreValue, .roundsAndReps(rounds: 7, partialReps: 14))
        XCTAssertEqual(storedResult.scoreDirection, .higherIsBetter)
    }

    // MARK: 9. EMOM

    func testEMOM() throws {
        let row = makeExercise("Row", .conditioning)
        let burpee = makeExercise("Burpee")
        let wallBall = makeExercise("Wall Ball")

        let block = WorkoutBlock(type: .functionalFitness)
        context.insert(block)

        let prescription = FunctionalFitnessPrescription(
            stimulus: Stimulus(
                targetDurationDomain: .medium, intensity: .moderate, loading: .bodyweightOnly,
                movementFunctions: [.monostructural, .gymnasticsPush, .hingeLoaded],
                movementModalityMix: [
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .weightlifting, count: 1),
                ],
                skillDemand: .low, systemicDemand: .moderate, scoreType: .completedIntervals
            ),
            format: .emom(intervalSeconds: 60, totalSeconds: 720)
        )
        context.insert(prescription)
        block.attachFunctionalFitnessPrescription(prescription)

        for (exercise, calories, reps, slot) in [(row, 12, nil, 1), (burpee, nil, 10, 2), (wallBall, nil, 12, 3)] as [(Exercise, Int?, Int?, Int)] {
            let movement = FunctionalFitnessMovement(exercise: exercise, reps: reps, calories: calories, minuteSlot: slot)
            context.insert(movement)
            prescription.addMovement(movement)
        }

        let result = FunctionalFitnessResult(
            scoreType: .completedIntervals,
            scoreValue: .completedIntervals(12),
            scoreDirection: .higherIsBetter
        )
        context.insert(result)
        block.attachFunctionalFitnessResult(result)

        guard case .functionalFitness(let storedPrescription) = try XCTUnwrap(block.blockPrescription) else {
            return XCTFail("expected .functionalFitness")
        }
        XCTAssertEqual(storedPrescription.orderedMovements.map(\.minuteSlot), [1, 2, 3])
        if case .emom(let intervalSeconds, let totalSeconds) = storedPrescription.format {
            XCTAssertEqual(intervalSeconds, 60)
            XCTAssertEqual(totalSeconds, 720)
        } else {
            XCTFail("expected .emom format")
        }
    }

    // MARK: 10. For Time benchmark

    func testForTimeBenchmark() throws {
        let thruster = makeExercise("Thruster")
        let pullUp = makeExercise("Pull-up")

        let benchmark = BenchmarkDefinition(
            canonicalID: "benchmark.fran",
            name: "Fran",
            stimulus: Stimulus(
                targetDurationDomain: .short, intensity: .high, loading: .moderate,
                movementFunctions: [.hingeLoaded, .gymnasticsPull],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                ],
                skillDemand: .moderate, systemicDemand: .high, scoreType: .time
            ),
            format: .forTime(capSeconds: nil),
            scoreType: .time,
            scoreDirection: .lowerIsBetter
        )
        context.insert(benchmark)

        let block = WorkoutBlock(type: .functionalFitness)
        context.insert(block)
        let prescription = FunctionalFitnessPrescription(stimulus: benchmark.stimulus, format: benchmark.format)
        context.insert(prescription)
        block.attachFunctionalFitnessPrescription(prescription)
        for exercise in [thruster, pullUp] {
            let movement = FunctionalFitnessMovement(exercise: exercise)
            context.insert(movement)
            prescription.addMovement(movement)
        }

        let result = FunctionalFitnessResult(
            scoreType: .time,
            scoreValue: .time(seconds: 245),
            scoreDirection: .lowerIsBetter,
            resultContext: .rx
        )
        context.insert(result)
        block.attachFunctionalFitnessResult(result)
        // Referencing the benchmark is the one thing that distinguishes
        // this from an ordinary generated workout — everything else about
        // the prescription/result shape is identical.
        result.benchmark = benchmark

        guard case .functionalFitness(let storedResult) = try XCTUnwrap(block.blockResult) else {
            return XCTFail("expected .functionalFitness")
        }
        XCTAssertEqual(storedResult.scoreValue, .time(seconds: 245))
        XCTAssertEqual(storedResult.benchmark?.canonicalID, "benchmark.fran")
    }

    // MARK: 11. Strength + Metcon in one Session

    func testStrengthPlusMetconOneSession() throws {
        let backSquat = makeExercise("Back Squat", .strength)
        let wallBall = makeExercise("Wall Ball")

        let session = Session(name: "Strength + Metcon", modality: .hybrid, role: .mixed)
        context.insert(session)

        let strengthBlock = WorkoutBlock(type: .strength)
        context.insert(strengthBlock)
        session.addBlock(strengthBlock)
        let squatMovement = ExercisePrescription(exercise: backSquat)
        context.insert(squatMovement)
        strengthBlock.addPrescription(squatMovement)
        for _ in 0..<5 {
            let setPrescription = SetPrescription(repRangeLow: 5, repRangeHigh: 5, targetWeight: 100, targetRir: 2)
            context.insert(setPrescription)
            squatMovement.addSetPrescription(setPrescription)
        }

        let metconBlock = WorkoutBlock(type: .functionalFitness)
        context.insert(metconBlock)
        session.addBlock(metconBlock)
        let metconPrescription = FunctionalFitnessPrescription(
            stimulus: Stimulus(
                targetDurationDomain: .medium, intensity: .high, loading: .light,
                movementFunctions: [.squatLoaded, .monostructural],
                movementModalityMix: [ModalityCount(modality: .metabolicConditioning, count: 1)],
                skillDemand: .low, systemicDemand: .moderate, scoreType: .roundsAndReps
            ),
            format: .amrap(capSeconds: 720)
        )
        context.insert(metconPrescription)
        metconBlock.attachFunctionalFitnessPrescription(metconPrescription)
        let wallBallMovement = FunctionalFitnessMovement(exercise: wallBall, reps: 15)
        context.insert(wallBallMovement)
        metconPrescription.addMovement(wallBallMovement)

        // The requirement: one Session, ordered heterogeneous blocks, no
        // special Session subclass and no Session-level branch on modality.
        XCTAssertEqual(session.orderedBlocks.map(\.type), [.strength, .functionalFitness])
        guard case .exercise = try XCTUnwrap(strengthBlock.blockPrescription) else {
            return XCTFail("expected block 1 to be .exercise")
        }
        guard case .functionalFitness = try XCTUnwrap(metconBlock.blockPrescription) else {
            return XCTFail("expected block 2 to be .functionalFitness")
        }
    }

    // MARK: 12. Two Sessions on one Day

    func testTwoSessionsOneDay() throws {
        let day = makeDay()
        let morning = Session(name: "Lower A", modality: .strength)
        context.insert(morning)
        day.addSession(morning)

        let evening = Session(name: "Evening Zone 2", modality: .conditioning, role: .aerobicBase)
        context.insert(evening)
        day.addSession(evening)

        XCTAssertEqual(day.orderedSessions.map(\.name), ["Lower A", "Evening Zone 2"])
        XCTAssertEqual(day.orderedSessions.map(\.sortIndex), [0, 1])
    }

    // MARK: 13. Hypertrophy primary + Aerobic secondary phase

    func testHypertrophyPrimaryPlusAerobicSecondaryPhase() throws {
        let phase = TrainingPhase(type: .muscleGain, startDate: Date(), priorityRule: .strength)
        context.insert(phase)

        let hypertrophyInstance = ProgramInstance(ownerUserID: UUID(), priority: .primary)
        context.insert(hypertrophyInstance)
        phase.addProgramInstance(hypertrophyInstance)

        let aerobicInstance = ProgramInstance(ownerUserID: UUID(), priority: .secondary)
        context.insert(aerobicInstance)
        phase.addProgramInstance(aerobicInstance)

        XCTAssertEqual(phase.primaryInstance?.id, hypertrophyInstance.id)
        XCTAssertEqual(phase.secondaryInstances.map(\.id), [aerobicInstance.id])
        // TrainingPhase performs no scheduling logic itself — it only
        // exposes priority; a future ConcurrentScheduler decides placement.
    }

    // MARK: 14. Running primary + Strength secondary phase

    func testRunningPrimaryPlusStrengthSecondaryPhase() throws {
        let phase = TrainingPhase(type: .enduranceEvent, startDate: Date(), priorityRule: .endurance)
        context.insert(phase)

        let runningInstance = ProgramInstance(ownerUserID: UUID(), priority: .primary)
        context.insert(runningInstance)
        phase.addProgramInstance(runningInstance)

        let strengthInstance = ProgramInstance(ownerUserID: UUID(), priority: .secondary)
        context.insert(strengthInstance)
        phase.addProgramInstance(strengthInstance)

        XCTAssertEqual(phase.primaryInstance?.id, runningInstance.id)
        XCTAssertEqual(phase.secondaryInstances.map(\.id), [strengthInstance.id])
        // Proves the same TrainingPhase/ProgramInstance shape works
        // whichever system is primary — nothing here special-cases
        // strength as the default primary.
    }
}
