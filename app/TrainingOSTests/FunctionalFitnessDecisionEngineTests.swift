import XCTest
@testable import TrainingOS

/// Stage 4E §50: proves `FunctionalFitnessDecisionEngine`'s planned-
/// variance logic with controlled recent-history fixtures — deterministic
/// configured behavior, never a claim of scientifically precise
/// programming superiority.
@MainActor
final class FunctionalFitnessDecisionEngineTests: XCTestCase {
    private let engine = FunctionalFitnessDecisionEngine()

    private func record(
        duration: DurationDomain = .medium, loading: LoadingClassification = .moderate,
        mix: [ModalityCount] = [ModalityCount(modality: .weightlifting, count: 1), ModalityCount(modality: .gymnastics, count: 1)],
        functions: [MovementFunction] = [.squatLoaded, .gymnasticsPull],
        skill: SkillDemand = .moderate, highIntensity: Bool = true
    ) -> VarianceExposureRecord {
        VarianceExposureRecord(date: Date(timeIntervalSince1970: 0), durationDomain: duration, loading: loading, movementModalityMix: mix, movementFunctionsUsed: functions, skillDemand: skill, wasHighIntensity: highIntensity)
    }

    private func stimulus(
        duration: DurationDomain = .medium, loading: LoadingClassification = .moderate,
        mix: [ModalityCount] = [ModalityCount(modality: .weightlifting, count: 1), ModalityCount(modality: .gymnastics, count: 1)],
        functions: [MovementFunction] = [.squatLoaded, .gymnasticsPull]
    ) -> Stimulus {
        Stimulus(targetDurationDomain: duration, intensity: .high, loading: loading, movementFunctions: functions, movementModalityMix: mix, skillDemand: .moderate, systemicDemand: .high, scoreType: .time)
    }

    // §50.31: identify missing duration exposure.
    func testIdentifiesMissingDurationExposureAndRotatesDomain() {
        let recentAllShort = Array(repeating: record(duration: .short), count: 3)
        let input = ProgrammingDecisionInput(
            exposureHistory: recentAllShort,
            stimulusRequirements: stimulus(duration: .short),
            varianceConstraints: VarianceConstraints(avoidRepeatingDurationDomainWithinSessions: 3)
        )
        let output = engine.decide(input)
        XCTAssertEqual(output.nextStimulus.targetDurationDomain, .medium, "3 consecutive short sessions should rotate to medium")
        XCTAssertEqual(output.reasonCode, .functionalDurationBalance)
    }

    // §50.32: identify missing modality exposure.
    func testIdentifiesMissingModalityExposureAndAddsUnderExposedModality() {
        // Target already covers weightlifting + gymnastics; only
        // metabolicConditioning is missing from all recent exposure —
        // unambiguous least-exposed candidate (no tie).
        let recentAllSameMix = Array(repeating: record(mix: [ModalityCount(modality: .weightlifting, count: 1), ModalityCount(modality: .gymnastics, count: 1)]), count: 2)
        let input = ProgrammingDecisionInput(
            exposureHistory: recentAllSameMix,
            stimulusRequirements: stimulus(mix: [ModalityCount(modality: .weightlifting, count: 1), ModalityCount(modality: .gymnastics, count: 1)]),
            varianceConstraints: VarianceConstraints(avoidRepeatingModalityMixWithinSessions: 2)
        )
        let output = engine.decide(input)
        XCTAssertTrue(output.nextStimulus.movementModalityMix.contains { $0.modality == .metabolicConditioning }, "the never-exposed modality should be added")
        XCTAssertEqual(output.reasonCode, .functionalModalityBalance)
    }

    // §50.33: identify repeated movement-pattern overuse.
    func testIdentifiesRepeatedMovementPatternOveruseAndAddsUnderExposedPattern() {
        let recentAllSameFunctions = Array(repeating: record(functions: [.squatLoaded, .hingeLoaded]), count: 2)
        let input = ProgrammingDecisionInput(
            exposureHistory: recentAllSameFunctions,
            stimulusRequirements: stimulus(functions: [.squatLoaded, .hingeLoaded]),
            varianceConstraints: VarianceConstraints(avoidRepeatingMovementFunctionWithinSessions: 2)
        )
        let output = engine.decide(input)
        XCTAssertFalse(output.nextStimulus.movementFunctions.isEmpty)
        XCTAssertTrue(output.nextStimulus.movementFunctions.contains { ![.squatLoaded, .hingeLoaded].contains($0) }, "an under-exposed pattern should be added")
        XCTAssertEqual(output.reasonCode, .functionalMovementBalance)
    }

    // §50.34: selects a valid contrasting stimulus when configuration
    // requests balance — the duration dimension is checked first (fixed
    // priority order), so a violation there wins over a simultaneous
    // modality violation.
    func testSelectsContrastingStimulusInFixedPriorityOrderWhenMultipleDimensionsAreViolated() {
        let recentAllShortAndSameMix = Array(repeating: record(duration: .short, mix: [ModalityCount(modality: .weightlifting, count: 1)]), count: 2)
        let input = ProgrammingDecisionInput(
            exposureHistory: recentAllShortAndSameMix,
            stimulusRequirements: stimulus(duration: .short, mix: [ModalityCount(modality: .weightlifting, count: 1)]),
            varianceConstraints: VarianceConstraints(avoidRepeatingModalityMixWithinSessions: 2, avoidRepeatingDurationDomainWithinSessions: 2)
        )
        let output = engine.decide(input)
        XCTAssertEqual(output.reasonCode, .functionalDurationBalance, "duration is checked before modality in this engine's fixed priority order")
        XCTAssertEqual(output.nextStimulus.targetDurationDomain, .medium)
    }

    // No violation configured or triggered -> stimulus passes through unchanged.
    func testNoViolationLeavesStimulusUnchanged() {
        let input = ProgrammingDecisionInput(exposureHistory: [], stimulusRequirements: stimulus(), varianceConstraints: VarianceConstraints())
        let output = engine.decide(input)
        XCTAssertEqual(output.nextStimulus, stimulus())
        XCTAssertEqual(output.reasonCode, .stimulusAsConfigured)
    }

    /// Not enough history yet to judge a repeat (fewer records than the
    /// configured window) must never falsely trigger a balance adjustment.
    func testInsufficientHistoryNeverFalselyTriggersABalanceAdjustment() {
        let onlyOneRecord = [record(duration: .short)]
        let input = ProgrammingDecisionInput(
            exposureHistory: onlyOneRecord, stimulusRequirements: stimulus(duration: .short),
            varianceConstraints: VarianceConstraints(avoidRepeatingDurationDomainWithinSessions: 3)
        )
        let output = engine.decide(input)
        XCTAssertEqual(output.reasonCode, .stimulusAsConfigured)
        XCTAssertEqual(output.nextStimulus.targetDurationDomain, .short)
    }

    // §50.35: identical input history produces identical output.
    func testIdenticalInputProducesIdenticalOutput() {
        let input = ProgrammingDecisionInput(
            exposureHistory: Array(repeating: record(duration: .short), count: 3),
            stimulusRequirements: stimulus(duration: .short),
            varianceConstraints: VarianceConstraints(avoidRepeatingDurationDomainWithinSessions: 3)
        )
        let first = engine.decide(input)
        let second = engine.decide(input)
        XCTAssertEqual(first.nextStimulus, second.nextStimulus)
        XCTAssertEqual(first.reasonCode, second.reasonCode)
    }

    // MARK: - §27/§50.36: exposure derives from actual completed results only

    func testSkippedSessionDoesNotCountAsCompletedExposure() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)

        // A completed session with a real result contributes.
        let completedDay = Day(ownerUserID: instance.ownerUserID, date: Date(timeIntervalSince1970: 0))
        context.insert(completedDay)
        let completedSession = Session(name: "Completed", modality: .functionalFitness, status: .completed)
        context.insert(completedSession)
        completedDay.addSession(completedSession)
        instance.addSession(completedSession)
        let completedBlock = WorkoutBlock(type: .functionalFitness)
        context.insert(completedBlock)
        completedSession.addBlock(completedBlock)
        let prescription = FunctionalFitnessPrescription(stimulus: stimulus(), format: .amrap(capSeconds: 720))
        context.insert(prescription)
        completedBlock.attachFunctionalFitnessPrescription(prescription)
        let result = FunctionalFitnessResult(scoreType: .roundsAndReps, scoreValue: .roundsAndReps(rounds: 5, partialReps: 3), scoreDirection: .higherIsBetter)
        context.insert(result)
        completedBlock.attachFunctionalFitnessResult(result)

        // A skipped session with only a prescription (never attempted) must not contribute.
        let skippedDay = Day(ownerUserID: instance.ownerUserID, date: Date(timeIntervalSince1970: 86400))
        context.insert(skippedDay)
        let skippedSession = Session(name: "Skipped", modality: .functionalFitness, status: .skipped)
        context.insert(skippedSession)
        skippedDay.addSession(skippedSession)
        instance.addSession(skippedSession)
        let skippedBlock = WorkoutBlock(type: .functionalFitness)
        context.insert(skippedBlock)
        skippedSession.addBlock(skippedBlock)
        let skippedPrescription = FunctionalFitnessPrescription(stimulus: stimulus(), format: .amrap(capSeconds: 720))
        context.insert(skippedPrescription)
        skippedBlock.attachFunctionalFitnessPrescription(skippedPrescription)
        // No result attached — never attempted.

        let exposure = FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn: instance)
        XCTAssertEqual(exposure.count, 1, "only the completed session with a real result should contribute exposure")
    }
}
