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
        XCTAssertTrue(template.orderedMovementSlots.isEmpty, "Stage FF.M1: Stage C (movement-slot composition) moved to materialization time — a freshly generated dynamically-composed template has no pre-baked slots")
        XCTAssertEqual(definition.programmingSystem, .functionalFitness)
    }

    // §46.2: EMOM rotation.
    func testEMOMRotation() throws {
        let stimulus = makeStimulus(duration: .medium, mix: [ModalityCount(modality: .metabolicConditioning, count: 3)], scoreType: .completedIntervals)
        let definition = generate(format: .emom(intervalSeconds: 60, totalSeconds: 720), stimulus: stimulus)
        let template = try ffTemplate(in: definition)
        XCTAssertEqual(template.format, .emom(intervalSeconds: 60, totalSeconds: 720))
        XCTAssertTrue(template.orderedMovementSlots.isEmpty, "Stage FF.M1: Stage C moved to materialization time — no pre-baked slots at generation")
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
        XCTAssertTrue(template.orderedMovementSlots.isEmpty, "Stage FF.M1: Stage C moved to materialization time — no pre-baked slots at generation")
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
        XCTAssertTrue(template.orderedMovementSlots.isEmpty, "Stage FF.M1: Stage C moved to materialization time — no pre-baked slots at generation")
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

    // Distinct training forms use the real generator and persisted recipe.
    private func styledConfiguration(_ style: FunctionalTrainingStyle?, conditioning: Bool? = nil) -> FunctionalFitnessProgramConfiguration {
        FunctionalFitnessProgramConfiguration(
            daysPerWeek: 3, lengthWeeks: 4, targetStimulus: makeStimulus(),
            format: .amrap(capSeconds: 720), sessionRole: .functionalFitness,
            varianceConstraints: VarianceConstraints(), requiresRecentExposureToProgress: false,
            includeStrengthBlock: false,
            weeklyPlan: FunctionalFitnessAuthoredProgramLibrary.weeklyPlan(forSessionsPerWeek: 3),
            trainingStyle: style, functionalStrengthIncludesConditioning: conditioning
        )
    }

    func testFunctionalStrengthWithoutConditioningHasRealResistanceContentEverySession() throws {
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: styledConfiguration(.functionalStrength, conditioning: false), provenance: .constructed(reason: "test"), context: context)
        XCTAssertEqual(definition.orderedTemplateSessions.count, 12)
        for session in definition.orderedTemplateSessions {
            XCTAssertEqual(session.role, .strength)
            XCTAssertFalse(session.orderedBlockTemplates.contains { $0.type == .functionalFitness })
            let block = try XCTUnwrap(session.orderedBlockTemplates.first { $0.type == .hypertrophy })
            XCTAssertFalse(block.orderedPrescriptionTemplates.isEmpty)
        }
    }

    func testFunctionalStrengthWithConditioningKeepsResistanceBeforeConditioning() throws {
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: styledConfiguration(.functionalStrength, conditioning: true), provenance: .constructed(reason: "test"), context: context)
        for session in definition.orderedTemplateSessions {
            XCTAssertEqual(session.role, .mixed)
            XCTAssertEqual(session.orderedBlockTemplates.map(\.type), [.hypertrophy, .functionalFitness])
        }
    }

    func testCrossFitKeepsWODWhenGoalBiasedIntentHadOmittedConditioning() throws {
        var configuration = styledConfiguration(.crossFit)
        configuration.weeklyPlan = configuration.weeklyPlan?.map { intent in
            var result = intent
            result.includeConditioningBlock = false
            return result
        }
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        XCTAssertTrue(definition.name.contains("CrossFit"))
        for session in definition.orderedTemplateSessions {
            XCTAssertNotNil(session.orderedBlockTemplates.first { $0.type == .functionalFitness }?.functionalFitnessPrescriptionTemplate)
        }
    }

    func testStyledRecurringInputIsNormalizedToExactWeekIntents() throws {
        var configuration = styledConfiguration(.functionalStrength, conditioning: false)
        configuration.weeklyPlan = nil
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        XCTAssertEqual(definition.functionalFitnessConfiguration?.weeklyPlan?.count, 12)
        XCTAssertEqual(definition.orderedTemplateSessions.filter { $0.activeFromWeek == 3 }.count, 3)
        XCTAssertFalse(definition.orderedTemplateSessions.flatMap(\.orderedBlockTemplates).contains { $0.type == .functionalFitness })
    }

    func testStyledRecipeAndBlocksSurviveFreshModelContext() throws {
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: styledConfiguration(.functionalStrength, conditioning: false), provenance: .constructed(reason: "test"), context: context)
        let id = definition.id
        try context.save()
        let fresh = ModelContext(container)
        let reloaded = try XCTUnwrap(fresh.fetch(FetchDescriptor<ProgramDefinition>()).first { $0.id == id })
        XCTAssertEqual(reloaded.functionalFitnessConfiguration?.trainingStyle, .functionalStrength)
        XCTAssertEqual(reloaded.functionalFitnessConfiguration?.functionalStrengthIncludesConditioning, false)
        XCTAssertTrue(reloaded.functionalFitnessConfiguration?.weeklyPlan?.allSatisfy { $0.includeStrengthBlock && !$0.includeConditioningBlock } == true)
        XCTAssertEqual(reloaded.orderedTemplateSessions.count, 12)
        XCTAssertFalse(reloaded.orderedTemplateSessions.flatMap(\.orderedBlockTemplates).contains { $0.type == .functionalFitness })
    }

    func testLegacyRecipeDecodesWithoutNewFieldsAndPreservesItsIntents() throws {
        let original = styledConfiguration(nil)
        let data = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "trainingStyle")
        object.removeValue(forKey: "functionalStrengthIncludesConditioning")
        let legacy = try JSONDecoder().decode(FunctionalFitnessProgramConfiguration.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.trainingStyle)
        XCTAssertNil(legacy.functionalStrengthIncludesConditioning)
        for intent in try XCTUnwrap(legacy.weeklyPlan) {
            XCTAssertEqual(legacy.resolvedIntent(intent), intent)
        }
    }

    func testCustomMixStoresTwoIndependentFunctionalFormsAndConditioningChoice() throws {
        let result = LongTermPlanner.buildCustomMix(selections: [(.functionalStrength, 2), (.crossFit, 2)], capacity: 4, phaseType: .muscleGain, functionalStrengthIncludesConditioning: false)
        let mix = try result.get()
        XCTAssertEqual(mix.orderedComponents.map(\.functionalTrainingStyle), [.functionalStrength, .crossFit])
        XCTAssertEqual(mix.orderedComponents.map(\.label), ["Functional Strength", "CrossFit"])
        XCTAssertEqual(mix.orderedComponents[0].functionalStrengthIncludesConditioning, false)
        XCTAssertNil(mix.orderedComponents[1].functionalStrengthIncludesConditioning)
        context.insert(mix)
        try context.save()
        let fresh = ModelContext(container)
        let restored = try XCTUnwrap(fresh.fetch(FetchDescriptor<TrainingMix>()).first { $0.id == mix.id })
        XCTAssertEqual(restored.orderedComponents.map(\.functionalTrainingStyle), [.functionalStrength, .crossFit])
        XCTAssertEqual(restored.orderedComponents[0].functionalStrengthIncludesConditioning, false)
    }

    func testFunctionalStrengthOptOutDoesNotClaimConditioningCapability() throws {
        let optedOut = LongTermPlanner.buildCustomMix(selections: [(.functionalStrength, 3)], capacity: 3, phaseType: .enduranceEvent, functionalStrengthIncludesConditioning: false)
        if case .success = optedOut { XCTFail("Strength without conditioning cannot carry a conditioning-only assignment") }
        let optedIn = LongTermPlanner.buildCustomMix(selections: [(.functionalStrength, 3)], capacity: 3, phaseType: .enduranceEvent, functionalStrengthIncludesConditioning: true)
        XCTAssertNoThrow(try optedIn.get())
        let crossFit = LongTermPlanner.buildCustomMix(selections: [(.crossFit, 3)], capacity: 3, phaseType: .enduranceEvent)
        XCTAssertNoThrow(try crossFit.get())
    }

    func testCombinedFunctionalFrequencyCannotBypassExistingFiveDayCapability() {
        let result = LongTermPlanner.buildCustomMix(selections: [(.functionalStrength, 3), (.crossFit, 3)], capacity: 6)
        if case .success = result { XCTFail("Two component identities must not bypass the existing unsupported six-day rule") }
    }

    func testNewStylePreferencesRemainDistinctAndLegacyPreferencesDecode() throws {
        XCTAssertNotEqual(TrainingStyle.functionalStrength.modalityPreferences, TrainingStyle.crossFit.modalityPreferences)
        XCTAssertFalse(TrainingStyle.selectableCases.contains(.functionalFitness))
        XCTAssertTrue(TrainingStyle.selectableCases.contains(.functionalStrength))
        XCTAssertTrue(TrainingStyle.selectableCases.contains(.crossFit))
        let legacy = try JSONDecoder().decode(ModalityPreference.self, from: Data(#"{"system":"functionalFitness"}"#.utf8))
        XCTAssertNil(legacy.functionalTrainingStyle)
        XCTAssertEqual(legacy, ModalityPreference(system: .functionalFitness))
    }


    func testPlannerResolvesBothFormsAndAllocatesHeavyStrengthOnceAcrossMix() throws {
        let mix = try LongTermPlanner.buildCustomMix(selections: [(.functionalStrength, 2), (.crossFit, 2)], capacity: 4, phaseType: .strength).get()
        let phase = TrainingPhase(type: .strength, startDate: Date(timeIntervalSince1970: 1_767_571_200), priorityRule: .strength)
        context.insert(phase)
        phase.addTrainingMix(mix)
        var recipes: [FunctionalFitnessProgramConfiguration] = []
        for component in mix.orderedComponents {
            let proposal = LongTermPlanner.proposeProgram(component: component, profile: nil, availability: UserAvailability(trainingDaysPerWeek: 4, allowsDoubleSessions: false, maxSessionsPerDay: 1), context: context)
            XCTAssertTrue(proposal.gaps.isEmpty)
            let definition = try XCTUnwrap(proposal.candidates.first?.programDefinition)
            let recipe = try XCTUnwrap(definition.functionalFitnessConfiguration)
            XCTAssertEqual(recipe.trainingStyle, component.functionalTrainingStyle)
            recipes.append(recipe)
        }
        for week in 0..<4 {
            let assignments = recipes.flatMap { $0.weeklyPlan ?? [] }.filter { $0.relativeWeek == week && $0.genericStrengthAssignment != nil }
            XCTAssertEqual(assignments.count, GenericStrengthRequirementCalculator.remainingRequirement(sourceContribution: 0))
        }
    }

}
