import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 4E: create -> save -> fresh ModelContext -> fetch -> semantic
/// equality, for every new persisted type this stage introduces
/// (`FunctionalFitnessPrescriptionTemplate`, `FunctionalFitnessMovementSlotTemplate`,
/// `Exercise.movementFunctions`/`.functionalModality`,
/// `ExerciseSlot.allowedMovementFunctions`/`.allowedModalities`). Written
/// before trusting any of them in generator/materializer/decision-engine
/// logic, per the standing discipline.
@MainActor
final class FunctionalFitnessPersistenceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func freshContext() -> ModelContext {
        ModelContext(container)
    }

    private func makeStimulus(duration: DurationDomain = .short) -> Stimulus {
        Stimulus(
            targetDurationDomain: duration, intensity: .high, loading: .moderate,
            movementFunctions: [.squatLoaded, .gymnasticsPull],
            movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1), ModalityCount(modality: .gymnastics, count: 1)],
            skillDemand: .moderate, systemicDemand: .high, scoreType: .time
        )
    }

    // MARK: - FunctionalFitnessPrescriptionTemplate

    func testFunctionalFitnessPrescriptionTemplateSurvivesRoundTrip() throws {
        let templateID = UUID()
        let stimulus = makeStimulus()
        let format = WorkoutFormat.forTime(capSeconds: 600)
        let template = FunctionalFitnessPrescriptionTemplate(
            id: templateID, stimulus: stimulus, format: format,
            requiresRecentExposureToProgress: true,
            varianceConstraints: VarianceConstraints(avoidRepeatingModalityMixWithinSessions: 2, avoidRepeatingDurationDomainWithinSessions: 3)
        )
        context.insert(template)
        try context.save()

        let fetchContext = freshContext()
        let descriptor = FetchDescriptor<FunctionalFitnessPrescriptionTemplate>(predicate: #Predicate { $0.id == templateID })
        let fetched = try XCTUnwrap(try fetchContext.fetch(descriptor).first)

        XCTAssertEqual(fetched.stimulus, stimulus)
        XCTAssertEqual(fetched.format, format)
        XCTAssertTrue(fetched.requiresRecentExposureToProgress)
        XCTAssertEqual(fetched.varianceConstraints?.avoidRepeatingModalityMixWithinSessions, 2)
        XCTAssertEqual(fetched.varianceConstraints?.avoidRepeatingDurationDomainWithinSessions, 3)
    }

    /// The critical Bug-3-style regression check, repeated for the new
    /// direct `Stimulus`/`WorkoutFormat` storage and the new movement-slot
    /// relationship: two sibling rows with heterogeneous formats/stimuli
    /// must each decode correctly.
    func testTwoSiblingRowsWithDifferentFormatsAndStimuliBothSurviveRoundTrip() throws {
        let amrapID = UUID()
        let ladderID = UUID()

        let amrapTemplate = FunctionalFitnessPrescriptionTemplate(
            id: amrapID, stimulus: makeStimulus(duration: .medium), format: .amrap(capSeconds: 720)
        )
        context.insert(amrapTemplate)

        let ladderTemplate = FunctionalFitnessPrescriptionTemplate(
            id: ladderID, stimulus: makeStimulus(duration: .short), format: .ladder(direction: .descending, capSeconds: 600)
        )
        context.insert(ladderTemplate)
        try context.save()

        let fetchContext = freshContext()
        let amrapDescriptor = FetchDescriptor<FunctionalFitnessPrescriptionTemplate>(predicate: #Predicate { $0.id == amrapID })
        let ladderDescriptor = FetchDescriptor<FunctionalFitnessPrescriptionTemplate>(predicate: #Predicate { $0.id == ladderID })

        let fetchedAmrap = try XCTUnwrap(try fetchContext.fetch(amrapDescriptor).first)
        let fetchedLadder = try XCTUnwrap(try fetchContext.fetch(ladderDescriptor).first)

        XCTAssertEqual(fetchedAmrap.format, .amrap(capSeconds: 720))
        XCTAssertEqual(fetchedAmrap.stimulus.targetDurationDomain, .medium)
        XCTAssertEqual(fetchedLadder.format, .ladder(direction: .descending, capSeconds: 600))
        XCTAssertEqual(fetchedLadder.stimulus.targetDurationDomain, .short)
    }

    func testWorkoutBlockTemplateFunctionalFitnessRelationshipAndMovementSlotsSurviveRoundTrip() throws {
        let blockID = UUID()
        let block = WorkoutBlockTemplate(id: blockID, type: .functionalFitness)
        context.insert(block)
        let template = FunctionalFitnessPrescriptionTemplate(stimulus: makeStimulus(), format: .forTime(capSeconds: 600))
        context.insert(template)
        block.attachFunctionalFitnessPrescriptionTemplate(template)

        let slotTemplate = FunctionalFitnessMovementSlotTemplate(reps: 21, loadingRole: .moderate, repScheme: [21, 15, 9])
        context.insert(slotTemplate)
        let exerciseSlot = ExerciseSlot(name: "Squat/Press slot", allowedMovementFunctions: [.squatLoaded], allowedModalities: [.weightlifting])
        context.insert(exerciseSlot)
        slotTemplate.attachExerciseSlot(exerciseSlot)
        template.addMovementSlot(slotTemplate)
        try context.save()

        let fetchContext = freshContext()
        let descriptor = FetchDescriptor<WorkoutBlockTemplate>(predicate: #Predicate { $0.id == blockID })
        let fetchedBlock = try XCTUnwrap(try fetchContext.fetch(descriptor).first)
        let fetchedTemplate = try XCTUnwrap(fetchedBlock.functionalFitnessPrescriptionTemplate)
        let fetchedSlotTemplate = try XCTUnwrap(fetchedTemplate.orderedMovementSlots.first)

        XCTAssertEqual(fetchedSlotTemplate.reps, 21)
        XCTAssertEqual(fetchedSlotTemplate.repScheme, [21, 15, 9])
        XCTAssertEqual(fetchedSlotTemplate.loadingRole, .moderate)
        XCTAssertEqual(fetchedSlotTemplate.exerciseSlot?.allowedMovementFunctions, [.squatLoaded])
        XCTAssertEqual(fetchedSlotTemplate.exerciseSlot?.allowedModalities, [.weightlifting])
    }

    /// Deleting the `WorkoutBlockTemplate` (as happens when its
    /// `ProgramDefinition` cascades away) must cascade-delete the
    /// `FunctionalFitnessPrescriptionTemplate` and its movement slots —
    /// same established pattern as the steady-state/interval siblings.
    func testDeletingWorkoutBlockTemplateCascadesItsFunctionalFitnessPrescriptionTemplate() throws {
        let block = WorkoutBlockTemplate(type: .functionalFitness)
        context.insert(block)
        let templateID = UUID()
        let template = FunctionalFitnessPrescriptionTemplate(id: templateID, stimulus: makeStimulus(), format: .amrap(capSeconds: 720))
        context.insert(template)
        block.attachFunctionalFitnessPrescriptionTemplate(template)
        try context.save()

        context.delete(block)
        try context.save()

        let fetchContext = freshContext()
        let descriptor = FetchDescriptor<FunctionalFitnessPrescriptionTemplate>(predicate: #Predicate { $0.id == templateID })
        XCTAssertTrue(try fetchContext.fetch(descriptor).isEmpty)
    }

    // MARK: - Exercise movement taxonomy

    func testExerciseMovementFunctionsAndFunctionalModalitySurviveRoundTrip() throws {
        let exerciseID = UUID()
        let exercise = Exercise(
            id: exerciseID, canonicalName: "Test Thruster", modality: .functionalFitness, equipment: "barbell", movementPattern: "squatToPress",
            movementFunctions: [.squatLoaded, .pressLoaded], functionalModality: .weightlifting
        )
        context.insert(exercise)
        try context.save()

        let fetchContext = freshContext()
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == exerciseID })
        let fetched = try XCTUnwrap(try fetchContext.fetch(descriptor).first)
        XCTAssertEqual(Set(fetched.movementFunctions), Set([.squatLoaded, .pressLoaded]))
        XCTAssertEqual(fetched.functionalModality, .weightlifting)
    }

    /// Two sibling `Exercise` rows with heterogeneous `functionalModality`
    /// values — the same diagnostic shape that caught Stage 4A's Bug 3,
    /// re-run for this new field.
    func testTwoSiblingExerciseRowsWithDifferentFunctionalModalitiesBothSurviveRoundTrip() throws {
        let gymnasticsID = UUID()
        let weightliftingID = UUID()
        context.insert(Exercise(id: gymnasticsID, canonicalName: "Test Toes-to-Bar", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "core", functionalModality: .gymnastics))
        context.insert(Exercise(id: weightliftingID, canonicalName: "Test Deadlift", modality: .functionalFitness, equipment: "barbell", movementPattern: "hinge", functionalModality: .weightlifting))
        try context.save()

        let fetchContext = freshContext()
        let gymnasticsDescriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == gymnasticsID })
        let weightliftingDescriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == weightliftingID })
        XCTAssertEqual(try fetchContext.fetch(gymnasticsDescriptor).first?.functionalModality, .gymnastics)
        XCTAssertEqual(try fetchContext.fetch(weightliftingDescriptor).first?.functionalModality, .weightlifting)
    }
}
