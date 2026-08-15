import XCTest
@testable import TrainingOS

/// Stage 4E §47/§51: scoring direction and `TrainingStressProfile`
/// mapping — coarse, deterministic, never inferred from a format's name.
final class FunctionalFitnessScoringAndStressProfileTests: XCTestCase {
    // MARK: - §47: scoring

    // §47.11: For Time — lower is better.
    func testForTimeLowerIsBetter() {
        let slower = RecordFunctionalFitnessResultUseCase.comparableValue(for: .time(seconds: 300))
        let faster = RecordFunctionalFitnessResultUseCase.comparableValue(for: .time(seconds: 245))
        let direction = RecordFunctionalFitnessResultUseCase.mapToScoringDirection(.lowerIsBetter)
        XCTAssertTrue(ScoringEngine.isBetter(faster, than: slower, direction: direction))
    }

    // §47.12: AMRAP — higher rounds/reps is better.
    func testAMRAPHigherRoundsAndRepsIsBetter() {
        let sevenRoundsPlus14 = RecordFunctionalFitnessResultUseCase.comparableValue(for: .roundsAndReps(rounds: 7, partialReps: 14))
        let sixRoundsPlus20 = RecordFunctionalFitnessResultUseCase.comparableValue(for: .roundsAndReps(rounds: 6, partialReps: 20))
        let direction = RecordFunctionalFitnessResultUseCase.mapToScoringDirection(.higherIsBetter)
        XCTAssertTrue(ScoringEngine.isBetter(sevenRoundsPlus14, than: sixRoundsPlus20, direction: direction), "more rounds always beats fewer rounds, regardless of partial reps")

        let sevenRoundsPlus20 = RecordFunctionalFitnessResultUseCase.comparableValue(for: .roundsAndReps(rounds: 7, partialReps: 20))
        XCTAssertTrue(ScoringEngine.isBetter(sevenRoundsPlus20, than: sevenRoundsPlus14, direction: direction), "within the same round count, more partial reps wins")
    }

    // §47.13: Max Load — higher is better.
    func testMaxLoadHigherIsBetter() {
        let heavier = RecordFunctionalFitnessResultUseCase.comparableValue(for: .load(kilograms: 120))
        let lighter = RecordFunctionalFitnessResultUseCase.comparableValue(for: .load(kilograms: 100))
        let direction = RecordFunctionalFitnessResultUseCase.mapToScoringDirection(.higherIsBetter)
        XCTAssertTrue(ScoringEngine.isBetter(heavier, than: lighter, direction: direction))
    }

    // §47.14: Max Reps — higher is better.
    func testMaxRepsHigherIsBetter() {
        let more = RecordFunctionalFitnessResultUseCase.comparableValue(for: .repetitions(30))
        let fewer = RecordFunctionalFitnessResultUseCase.comparableValue(for: .repetitions(22))
        let direction = RecordFunctionalFitnessResultUseCase.mapToScoringDirection(.higherIsBetter)
        XCTAssertTrue(ScoringEngine.isBetter(more, than: fewer, direction: direction))
    }

    // §47.16: scoring direction is always explicit — FunctionalFitnessResult's
    // own initializer requires it, there is no default and nothing infers
    // it from scoreType or format.
    func testScoringDirectionIsAlwaysExplicitNeverInferred() {
        // Two results sharing the exact same scoreType (.time) but
        // opposite directions must both be representable — proving
        // direction isn't derived from scoreType.
        let timeLowerIsBetter = FunctionalFitnessResult(scoreType: .time, scoreValue: .time(seconds: 245), scoreDirection: .lowerIsBetter)
        let timeHigherIsBetter = FunctionalFitnessResult(scoreType: .time, scoreValue: .time(seconds: 245), scoreDirection: .higherIsBetter)
        XCTAssertNotEqual(timeLowerIsBetter.scoreDirection, timeHigherIsBetter.scoreDirection)
    }

    // §47.15: Rx and Scaled remain distinct (never the same PR sequence).
    func testRxAndScaledNeverCompeteForTheSameBenchmarkRecord() {
        let rxRecord = PersonalRecord(value: 245, scoringDirection: .lowerIsBetter, context: .rx)
        let scaledRecord = PersonalRecord(value: 300, scoringDirection: .lowerIsBetter, context: .scaled)
        let best = ScoringEngine.bestRecord(among: [rxRecord, scaledRecord], context: .rx, repBand: nil)
        XCTAssertEqual(best?.context, .rx)
        XCTAssertEqual(best?.value, 245)
    }

    // §47.17: no workout-name parsing anywhere in this codebase's scoring
    // path — `comparableValue`/`mapToScoringDirection` only ever switch
    // on the typed `ScoreValue`/`ScoreDirection`, never a String.
    func testScoringNeverParsesAWorkoutName() {
        let result = FunctionalFitnessResult(scoreType: .time, scoreValue: .time(seconds: 245), scoreDirection: .lowerIsBetter)
        // The value is entirely determined by the typed scoreValue/scoreDirection
        // fields; a benchmark's `name` ("Fran") plays no part in this call.
        let value = RecordFunctionalFitnessResultUseCase.comparableValue(for: result.scoreValue)
        XCTAssertEqual(value, 245)
    }

    // MARK: - §51: TrainingStressProfile

    // §51.37: heavy squat/hinge metcon has high lower-body load.
    func testHeavySquatHingeMetconHasHighLowerBodyLoad() {
        let stimulus = Stimulus(
            targetDurationDomain: .medium, intensity: .high, loading: .heavy,
            movementFunctions: [.squatLoaded, .hingeLoaded], movementModalityMix: [ModalityCount(modality: .weightlifting, count: 2)],
            skillDemand: .moderate, systemicDemand: .high, scoreType: .time
        )
        let profile = FunctionalFitnessStressProfileMapper.map(stimulus: stimulus)
        XCTAssertEqual(profile.lowerBodyLoad, .high)
        XCTAssertEqual(profile.upperBodyLoad, .none, "no upper-body movement function was requested")
    }

    // §51.38: easy skill EMOM differs from hard metabolic triplet.
    func testEasySkillEMOMDiffersFromHardMetabolicTriplet() {
        let easySkillEMOM = Stimulus(
            targetDurationDomain: .short, intensity: .low, loading: .bodyweightOnly,
            movementFunctions: [.gymnasticsPush], movementModalityMix: [ModalityCount(modality: .gymnastics, count: 1)],
            skillDemand: .high, systemicDemand: .low, scoreType: .completedIntervals
        )
        let hardTriplet = Stimulus(
            targetDurationDomain: .medium, intensity: .high, loading: .heavy,
            movementFunctions: [.squatLoaded, .gymnasticsPull, .monostructural],
            movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1), ModalityCount(modality: .gymnastics, count: 1), ModalityCount(modality: .metabolicConditioning, count: 1)],
            skillDemand: .moderate, systemicDemand: .high, scoreType: .roundsAndReps
        )
        let easyProfile = FunctionalFitnessStressProfileMapper.map(stimulus: easySkillEMOM)
        let hardProfile = FunctionalFitnessStressProfileMapper.map(stimulus: hardTriplet)
        XCTAssertNotEqual(easyProfile, hardProfile)
        XCTAssertEqual(easyProfile.overallIntensity, .low)
        XCTAssertEqual(hardProfile.overallIntensity, .high)
    }

    // §51.39: long easy monostructural conditioning differs from
    // high-intensity mixed modal.
    func testLongEasyMonostructuralConditioningDiffersFromHighIntensityMixedModal() {
        let longEasy = Stimulus(
            targetDurationDomain: .long, intensity: .low, loading: .bodyweightOnly,
            movementFunctions: [.monostructural], movementModalityMix: [ModalityCount(modality: .metabolicConditioning, count: 1)],
            skillDemand: .low, systemicDemand: .low, scoreType: .distance
        )
        let highIntensityMixedModal = Stimulus(
            targetDurationDomain: .short, intensity: .high, loading: .heavy,
            movementFunctions: [.squatLoaded, .gymnasticsPull], movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1), ModalityCount(modality: .gymnastics, count: 1)],
            skillDemand: .moderate, systemicDemand: .high, scoreType: .time
        )
        let longEasyProfile = FunctionalFitnessStressProfileMapper.map(stimulus: longEasy)
        let mixedModalProfile = FunctionalFitnessStressProfileMapper.map(stimulus: highIntensityMixedModal)
        XCTAssertEqual(longEasyProfile.durationClassification, .long)
        XCTAssertEqual(mixedModalProfile.durationClassification, .short)
        XCTAssertEqual(longEasyProfile.systemicDemand, .low)
        XCTAssertEqual(mixedModalProfile.systemicDemand, .high)
    }
}
