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
            XCTAssertEqual(block.orderedPrescriptionTemplates.count, 4)
            XCTAssertEqual(Set(block.orderedPrescriptionTemplates.compactMap { $0.exerciseSlot?.allowedMovementFunctions.first }).count, 4)
        }
    }

    func testFunctionalStrengthWithConditioningKeepsResistanceBeforeConditioning() throws {
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: styledConfiguration(.functionalStrength, conditioning: true), provenance: .constructed(reason: "test"), context: context)
        for session in definition.orderedTemplateSessions {
            XCTAssertEqual(session.role, .mixed)
            XCTAssertEqual(session.orderedBlockTemplates.map(\.type), [.hypertrophy, .functionalFitness])
            let resistance = try XCTUnwrap(session.orderedBlockTemplates.first)
            XCTAssertEqual(resistance.orderedPrescriptionTemplates.count, 3)
            XCTAssertEqual(session.orderedBlockTemplates.last?.functionalFitnessPrescriptionTemplate?.format, .amrap(capSeconds: 720))
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


    func testTimeBudgetAccountsForWorkRestWarmupAndTransitions() {
        let strength = FunctionalStrengthSessionBudget(resistanceSeconds: FunctionalStrengthSessionBudget.resistanceEstimate(setCounts: [4, 4, 4, 4]), conditioningSeconds: 0)
        XCTAssertEqual(strength.estimatedTotalSeconds, 49 * 60)
        XCTAssertTrue(strength.meetsTimeTarget)
        let combined = FunctionalStrengthSessionBudget(resistanceSeconds: FunctionalStrengthSessionBudget.resistanceEstimate(setCounts: [4, 4, 4]), conditioningSeconds: 12 * 60)
        XCTAssertEqual(combined.estimatedTotalSeconds, 50 * 60)
        XCTAssertTrue(combined.meetsTimeTarget)
        XCTAssertLessThan(combined.resistanceSeconds, strength.resistanceSeconds)
    }

    func testTimeBudgetDisclosesIncompleteContentInsteadOfInventingDuration() {
        let empty = FunctionalStrengthSessionBudget(resistanceSeconds: FunctionalStrengthSessionBudget.resistanceEstimate(setCounts: [0, 0]), conditioningSeconds: 0)
        XCTAssertEqual(empty.estimatedTotalSeconds, WarmupPolicy.targetDurationSeconds)
        XCTAssertFalse(empty.meetsTimeTarget)
        let excessive = FunctionalStrengthSessionBudget(resistanceSeconds: FunctionalStrengthSessionBudget.resistanceEstimate(setCounts: [10, 10, 10, 10]), conditioningSeconds: 0)
        XCTAssertFalse(excessive.meetsTimeTarget)
    }

    func testCompleteFunctionalStrengthMaterializesFourExercisesAndTimeBudgetAcrossAllWeeks() throws {
        let candidates = [
            Exercise(canonicalName: "Test Squat", modality: .hypertrophy, equipment: "barbell", movementPattern: "squat", primaryTargets: [.quadriceps, .glutes], movementFunctions: [.squatLoaded]),
            Exercise(canonicalName: "Test Hinge", modality: .hypertrophy, equipment: "barbell", movementPattern: "hinge", primaryTargets: [.hamstrings, .glutes, .back], movementFunctions: [.hingeLoaded]),
            Exercise(canonicalName: "Test Press", modality: .hypertrophy, equipment: "barbell", movementPattern: "press", primaryTargets: [.shoulders, .chest, .triceps], movementFunctions: [.pressLoaded]),
            Exercise(canonicalName: "Test Pull", modality: .hypertrophy, equipment: "barbell", movementPattern: "pull", primaryTargets: [.back, .biceps], movementFunctions: [.horizontalPullLoaded])
        ]
        candidates.forEach { context.insert($0) }
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: styledConfiguration(.functionalStrength, conditioning: false), provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition
        try ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: candidates, environment: environment)
        var created: [Session] = []
        for week in 0..<4 {
            let sessions = try FunctionalFitnessMaterializer.materializeWeek(definition: definition, instance: instance, weekIndex: week, startDate: Date(timeIntervalSince1970: 1_767_571_200), ownerUserID: instance.ownerUserID, candidateExercises: candidates, exposureHistory: [], environment: environment, context: context)
            XCTAssertEqual(sessions.count, 3)
            for session in sessions {
                let prescriptions = session.orderedBlocks.flatMap(\.orderedPrescriptions)
                XCTAssertEqual(prescriptions.count, 4)
                XCTAssertEqual(Set(prescriptions.compactMap { $0.exercise?.id }).count, 4)
                XCTAssertTrue(prescriptions.allSatisfy { $0.orderedSetPrescriptions.count == 4 })
                XCTAssertTrue(prescriptions.flatMap(\.orderedSetPrescriptions).allSatisfy { $0.restAfterSetSeconds == 120 && $0.repRangeLow == 8 && $0.repRangeHigh == 12 && $0.targetRir == 3 })
                let budget = try XCTUnwrap(session.functionalStrengthBudget)
                XCTAssertEqual(budget.estimatedTotalSeconds, 49 * 60)
                XCTAssertTrue(budget.meetsTimeTarget)
            }
            created += sessions
        }
        try context.save()
        let fresh = ModelContext(container)
        let reloaded = try fresh.fetch(FetchDescriptor<Session>()).filter { $0.programInstance?.id == instance.id }
        XCTAssertEqual(reloaded.count, created.count)
        XCTAssertTrue(reloaded.allSatisfy { $0.functionalStrengthBudget?.estimatedTotalSeconds == 49 * 60 })
        XCTAssertTrue(reloaded.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).flatMap(\.orderedSetPrescriptions).allSatisfy { $0.restAfterSetSeconds == 120 })
    }


    func testFunctionalStrengthConditioningFitsSameBudgetWithProductionCatalog() throws {
        _ = ExerciseCatalog.resolveOrInsert(context: context)
        let candidates = try context.fetch(FetchDescriptor<Exercise>())
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: styledConfiguration(.functionalStrength, conditioning: true), provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition
        try ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: candidates, environment: environment)
        for week in 0..<4 {
            let sessions = try FunctionalFitnessMaterializer.materializeWeek(definition: definition, instance: instance, weekIndex: week, startDate: Date(timeIntervalSince1970: 1_767_571_200), ownerUserID: instance.ownerUserID, candidateExercises: candidates, exposureHistory: [], environment: environment, context: context)
            XCTAssertEqual(sessions.count, 3)
            for session in sessions {
                let resistance = session.orderedBlocks.flatMap(\.orderedPrescriptions)
                XCTAssertEqual(resistance.count, 3)
                XCTAssertTrue(resistance.allSatisfy { $0.orderedSetPrescriptions.count == 4 })
                XCTAssertEqual(session.orderedBlocks.last?.functionalFitnessPrescription?.format, .amrap(capSeconds: 720))
                let budget = try XCTUnwrap(session.functionalStrengthBudget)
                XCTAssertEqual(budget.estimatedTotalSeconds, 50 * 60)
                XCTAssertTrue(budget.meetsTimeTarget)
            }
        }
    }

}
