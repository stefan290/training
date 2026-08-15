import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 4E §46: proves the production domain can generate/represent all
/// 10 required shapes through the same generic `WorkoutBlockTemplate`/
/// `FunctionalFitnessPrescriptionTemplate` architecture — no format-
/// specific Session subclasses, ever.
@MainActor
final class FunctionalFitnessProgramGeneratorTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func makeStimulus(
        duration: DurationDomain = .medium, intensity: IntensityClassification = .high, loading: LoadingClassification = .moderate,
        functions: [MovementFunction] = [.squatLoaded, .gymnasticsPull, .monostructural],
        mix: [ModalityCount] = [ModalityCount(modality: .weightlifting, count: 1), ModalityCount(modality: .gymnastics, count: 1), ModalityCount(modality: .metabolicConditioning, count: 1)],
        scoreType: ScoreType = .roundsAndReps
    ) -> Stimulus {
        Stimulus(
            targetDurationDomain: duration, intensity: intensity, loading: loading,
            movementFunctions: functions, movementModalityMix: mix,
            skillDemand: .moderate, systemicDemand: .high, scoreType: scoreType
        )
    }

    private func generate(format: WorkoutFormat, stimulus: Stimulus, includeStrength: Bool = false) -> ProgramDefinition {
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 2, targetStimulus: stimulus, format: format,
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: includeStrength
        )
        return FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
    }

    private func ffTemplate(in definition: ProgramDefinition) throws -> FunctionalFitnessPrescriptionTemplate {
        let block = try XCTUnwrap(definition.orderedTemplateSessions.first?.orderedBlockTemplates.first { $0.type == .functionalFitness })
        return try XCTUnwrap(block.functionalFitnessPrescriptionTemplate)
    }

    // §46.1: 12-minute AMRAP triplet.
    func test12MinuteAMRAPTriplet() throws {
        let stimulus = makeStimulus(duration: .medium, scoreType: .roundsAndReps)
        let definition = generate(format: .amrap(capSeconds: 720), stimulus: stimulus)
        let template = try ffTemplate(in: definition)
        XCTAssertEqual(template.format, .amrap(capSeconds: 720))
        XCTAssertEqual(template.orderedMovementSlots.count, 3, "a triplet has 3 movement slots, one per modality-mix entry")
        XCTAssertEqual(definition.programmingSystem, .functionalFitness)
    }

    // §46.2: EMOM rotation.
    func testEMOMRotation() throws {
        let stimulus = makeStimulus(duration: .medium, mix: [ModalityCount(modality: .metabolicConditioning, count: 3)], scoreType: .completedIntervals)
        let definition = generate(format: .emom(intervalSeconds: 60, totalSeconds: 720), stimulus: stimulus)
        let template = try ffTemplate(in: definition)
        XCTAssertEqual(template.format, .emom(intervalSeconds: 60, totalSeconds: 720))
        XCTAssertEqual(template.orderedMovementSlots.count, 3, "a 3-station EMOM rotation has 3 movement slots")
    }

    // §46.3: 21-15-9 For Time (a named benchmark shape).
    func test21_15_9ForTime() throws {
        let stimulus = makeStimulus(duration: .short, mix: [ModalityCount(modality: .weightlifting, count: 1), ModalityCount(modality: .gymnastics, count: 1)], scoreType: .time)
        let definition = generate(format: .forTime(capSeconds: 600), stimulus: stimulus)
        let template = try ffTemplate(in: definition)
        XCTAssertEqual(template.format, .forTime(capSeconds: 600))
        let slot = FunctionalFitnessMovementSlotTemplate(repScheme: [21, 15, 9])
        XCTAssertEqual(slot.repScheme, [21, 15, 9], "the explicit rep-scheme sequence, never a parsed '21-15-9' string")
    }

    // §46.4: 5-round For Time.
    func test5RoundForTime() throws {
        let stimulus = makeStimulus(duration: .medium, scoreType: .time)
        let definition = generate(format: .roundsForTime(rounds: 5, capSeconds: 1200), stimulus: stimulus)
        let template = try ffTemplate(in: definition)
        XCTAssertEqual(template.format, .roundsForTime(rounds: 5, capSeconds: 1200))
    }

    // §46.5: Chipper — one ordered pass, no forced "round" abstraction.
    func testChipper() throws {
        let stimulus = makeStimulus(
            duration: .long,
            mix: [ModalityCount(modality: .metabolicConditioning, count: 1), ModalityCount(modality: .gymnastics, count: 2), ModalityCount(modality: .weightlifting, count: 2)],
            scoreType: .time
        )
        let definition = generate(format: .chipper(capSeconds: 1800), stimulus: stimulus)
        let template = try ffTemplate(in: definition)
        XCTAssertEqual(template.format, .chipper(capSeconds: 1800))
        XCTAssertEqual(template.orderedMovementSlots.count, 5, "a 5-movement chipper has 5 slots, no round grouping")
    }

    // §46.6: Ascending ladder.
    func testAscendingLadder() throws {
        let stimulus = makeStimulus(duration: .medium, scoreType: .time)
        let definition = generate(format: .ladder(direction: .ascending, capSeconds: 900), stimulus: stimulus)
        let template = try ffTemplate(in: definition)
        XCTAssertEqual(template.format, .ladder(direction: .ascending, capSeconds: 900))
        let slot = FunctionalFitnessMovementSlotTemplate(repScheme: [1, 2, 3, 4, 5])
        XCTAssertEqual(slot.repScheme, [1, 2, 3, 4, 5])
    }

    // §46.7: Max Load.
    func testMaxLoad() throws {
        let stimulus = makeStimulus(duration: .short, loading: .heavy, mix: [ModalityCount(modality: .weightlifting, count: 1)], scoreType: .load)
        let definition = generate(format: .maxLoad, stimulus: stimulus)
        let template = try ffTemplate(in: definition)
        XCTAssertEqual(template.format, .maxLoad)
        XCTAssertEqual(FunctionalFitnessStimulusValidator.defaultScoreType(for: .maxLoad), .load)
    }

    // §46.8: Max Reps.
    func testMaxReps() throws {
        let stimulus = makeStimulus(duration: .short, mix: [ModalityCount(modality: .gymnastics, count: 1)], scoreType: .repetitions)
        let definition = generate(format: .maxReps(capSeconds: 120), stimulus: stimulus)
        let template = try ffTemplate(in: definition)
        XCTAssertEqual(template.format, .maxReps(capSeconds: 120))
        XCTAssertEqual(FunctionalFitnessStimulusValidator.defaultScoreType(for: .maxReps(capSeconds: 120)), .repetitions)
    }

    // §46.9: single-modality conditioning workout.
    func testSingleModalityConditioningWorkout() throws {
        let stimulus = makeStimulus(duration: .long, loading: .bodyweightOnly, functions: [.monostructural], mix: [ModalityCount(modality: .metabolicConditioning, count: 1)], scoreType: .distance)
        let definition = generate(format: .forTime(capSeconds: nil), stimulus: stimulus)
        let template = try ffTemplate(in: definition)
        XCTAssertEqual(template.orderedMovementSlots.count, 1, "single-modality means exactly one movement slot")
    }

    // §46.10/§20: Strength + Metcon Session — proves composition through
    // the existing generic architecture, no "CrossFitSession."
    func testStrengthPlusMetconSessionComposition() throws {
        let stimulus = makeStimulus()
        let definition = generate(format: .amrap(capSeconds: 480), stimulus: stimulus, includeStrength: true)
        let session = try XCTUnwrap(definition.orderedTemplateSessions.first)
        XCTAssertEqual(session.orderedBlockTemplates.map(\.type), [.strength, .functionalFitness], "one Session, ordered heterogeneous blocks")
    }

    // MARK: - §6: format and stimulus are independent

    func testSameFormatWithDifferentStimuliAreNotConflated() {
        let lightTriplet = makeStimulus(intensity: .low, loading: .light, scoreType: .roundsAndReps)
        let heavySingles = makeStimulus(intensity: .high, loading: .heavy, mix: [ModalityCount(modality: .weightlifting, count: 1)], scoreType: .roundsAndReps)

        let definitionA = generate(format: .amrap(capSeconds: 720), stimulus: lightTriplet)
        let definitionB = generate(format: .amrap(capSeconds: 720), stimulus: heavySingles)

        XCTAssertEqual(try! ffTemplate(in: definitionA).format, try! ffTemplate(in: definitionB).format, "both are the same format...")
        XCTAssertNotEqual(try! ffTemplate(in: definitionA).stimulus, try! ffTemplate(in: definitionB).stimulus, "...but must never be treated as 'the same kind of workout' just because the format matches")
    }
}
