import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 4C: create -> save -> fresh ModelContext -> fetch -> semantic
/// equality, for every new persisted type this stage introduces
/// (`SteadyStatePrescriptionTemplate`, `ExerciseRelationship`,
/// `SlotSelectionOverride`, `ActivitySelectionOverride`,
/// `Exercise.primaryTargets`). Written before trusting any of them in
/// generator/materializer/substitution logic, per the standing discipline
/// established by Stage 4A's own Bug 2/3 discoveries — a Codable type is
/// never assumed persistence-safe by analogy alone.
@MainActor
final class SteadyStatePersistenceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func freshContext() -> ModelContext {
        ModelContext(container)
    }

    // MARK: - SteadyStatePrescriptionTemplate

    func testSteadyStatePrescriptionTemplateWithDurationProgressionSurvivesRoundTrip() throws {
        let templateID = UUID()
        let rules = SteadyStateProgressionRules(
            progressionDimension: .duration,
            weekOneDurationSeconds: 2700,
            laterWeekDurationSeconds: [3000, 3300, 3600],
            recoveryWeekDurationFraction: 0.7
        )
        let template = SteadyStatePrescriptionTemplate(
            id: templateID,
            preferredActivityType: .cycling,
            allowedActivityTypes: [.cycling, .rowing, .skiErg],
            primaryIntensity: .heartRateZone(.two),
            progressionRules: rules
        )
        context.insert(template)
        try context.save()

        let fetchContext = freshContext()
        let descriptor = FetchDescriptor<SteadyStatePrescriptionTemplate>(predicate: #Predicate { $0.id == templateID })
        let fetched = try XCTUnwrap(try fetchContext.fetch(descriptor).first)

        XCTAssertEqual(fetched.preferredActivityType, .cycling)
        XCTAssertEqual(fetched.allowedActivityTypes, [.cycling, .rowing, .skiErg])
        XCTAssertEqual(fetched.primaryIntensity, .heartRateZone(.two))
        XCTAssertEqual(fetched.progressionRules, rules)
    }

    /// The critical Bug-3-style regression check: two sibling rows holding
    /// *different* `SteadyStateProgressionDimension`/`IntensityZoneProgression`
    /// shapes must each decode correctly, not silently collapse the second
    /// row's values to `nil` — exactly the diagnostic
    /// `TemplateGraphPersistenceTests` already ran for `StrengthProgressionRules`,
    /// repeated here for the new steady-state rule storage rather than
    /// assumed safe by analogy.
    func testTwoSiblingRowsWithDifferentProgressionDimensionsBothSurviveRoundTrip() throws {
        let durationID = UUID()
        let intensityID = UUID()

        let durationTemplate = SteadyStatePrescriptionTemplate(
            id: durationID,
            preferredActivityType: .running,
            progressionRules: SteadyStateProgressionRules(progressionDimension: .duration, weekOneDurationSeconds: 1800, laterWeekDurationSeconds: [2100])
        )
        context.insert(durationTemplate)

        let intensityTemplate = SteadyStatePrescriptionTemplate(
            id: intensityID,
            preferredActivityType: .running,
            progressionRules: SteadyStateProgressionRules(
                progressionDimension: .intensityZone,
                intensityZoneProgression: IntensityZoneProgression(startZone: .two, stepPerWeek: 1, maxZone: .four)
            )
        )
        context.insert(intensityTemplate)
        try context.save()

        let fetchContext = freshContext()
        let durationDescriptor = FetchDescriptor<SteadyStatePrescriptionTemplate>(predicate: #Predicate { $0.id == durationID })
        let intensityDescriptor = FetchDescriptor<SteadyStatePrescriptionTemplate>(predicate: #Predicate { $0.id == intensityID })

        let fetchedDuration = try XCTUnwrap(try fetchContext.fetch(durationDescriptor).first)
        let fetchedIntensity = try XCTUnwrap(try fetchContext.fetch(intensityDescriptor).first)

        XCTAssertEqual(fetchedDuration.progressionRules?.progressionDimension, .duration)
        XCTAssertEqual(fetchedDuration.progressionRules?.weekOneDurationSeconds, 1800)
        XCTAssertNil(fetchedDuration.progressionRules?.intensityZoneProgression)

        XCTAssertEqual(fetchedIntensity.progressionRules?.progressionDimension, .intensityZone)
        XCTAssertEqual(fetchedIntensity.progressionRules?.intensityZoneProgression, IntensityZoneProgression(startZone: .two, stepPerWeek: 1, maxZone: .four))
        XCTAssertNil(fetchedIntensity.progressionRules?.weekOneDurationSeconds)
    }

    func testWorkoutBlockTemplateSteadyStateRelationshipSurvivesRoundTrip() throws {
        let sessionID = UUID()
        let session = TemplateSession(id: sessionID, name: "Day 1", role: .aerobicBase)
        context.insert(session)
        let block = WorkoutBlockTemplate(type: .steadyState)
        context.insert(block)
        session.addBlockTemplate(block)
        let template = SteadyStatePrescriptionTemplate(preferredActivityType: .rowing, progressionRules: SteadyStateProgressionRules(progressionDimension: .none, weekOneDurationSeconds: 2700))
        context.insert(template)
        block.attachSteadyStatePrescriptionTemplate(template)
        try context.save()

        let fetchContext = freshContext()
        let descriptor = FetchDescriptor<TemplateSession>(predicate: #Predicate { $0.id == sessionID })
        let fetchedSession = try XCTUnwrap(try fetchContext.fetch(descriptor).first)
        let fetchedBlock = try XCTUnwrap(fetchedSession.orderedBlockTemplates.first)
        XCTAssertEqual(fetchedBlock.steadyStatePrescriptionTemplate?.preferredActivityType, .rowing)
    }

    // MARK: - Exercise.primaryTargets

    func testExercisePrimaryTargetsSurvivesRoundTrip() throws {
        let exerciseID = UUID()
        let exercise = Exercise(
            id: exerciseID, canonicalName: "Test Bench Press Variant", modality: .hypertrophy,
            equipment: "barbell", movementPattern: "horizontalPush", primaryTargets: [.chest, .triceps]
        )
        context.insert(exercise)
        try context.save()

        let fetchContext = freshContext()
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == exerciseID })
        let fetched = try XCTUnwrap(try fetchContext.fetch(descriptor).first)
        XCTAssertEqual(Set(fetched.primaryTargets), Set([.chest, .triceps]))
    }

    // MARK: - ExerciseRelationship

    func testExerciseRelationshipSurvivesRoundTrip() throws {
        let barbell = Exercise(canonicalName: "Barbell Bench Press Rel Test", modality: .hypertrophy, equipment: "barbell", movementPattern: "horizontalPush")
        let dumbbell = Exercise(canonicalName: "Dumbbell Bench Press Rel Test", modality: .hypertrophy, equipment: "dumbbell", movementPattern: "horizontalPush")
        context.insert(barbell)
        context.insert(dumbbell)
        let relationshipID = UUID()
        let relationship = ExerciseRelationship(id: relationshipID, fromExercise: barbell, toExercise: dumbbell, type: .directSubstitute)
        context.insert(relationship)
        try context.save()

        let fetchContext = freshContext()
        let descriptor = FetchDescriptor<ExerciseRelationship>(predicate: #Predicate { $0.id == relationshipID })
        let fetched = try XCTUnwrap(try fetchContext.fetch(descriptor).first)
        XCTAssertEqual(fetched.type, .directSubstitute)
        XCTAssertEqual(fetched.fromExercise?.canonicalName, "Barbell Bench Press Rel Test")
        XCTAssertEqual(fetched.toExercise?.canonicalName, "Dumbbell Bench Press Rel Test")
    }

    // MARK: - SlotSelectionOverride

    func testSlotSelectionOverrideSurvivesRoundTripAndRelationships() throws {
        let slot = ExerciseSlot(name: "Horizontal Push Persistence Test", allowedTargets: [.chest])
        context.insert(slot)
        let exercise = Exercise(canonicalName: "Dumbbell Bench Press Slot Test", modality: .hypertrophy, equipment: "dumbbell", movementPattern: "horizontalPush")
        context.insert(exercise)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)

        let overrideID = UUID()
        let override = SlotSelectionOverride(id: overrideID, selectedExercise: exercise, reason: .userPreference)
        override.templateSlot = slot
        context.insert(override)
        instance.addSlotSelectionOverride(override)
        try context.save()

        let fetchContext = freshContext()
        let descriptor = FetchDescriptor<SlotSelectionOverride>(predicate: #Predicate { $0.id == overrideID })
        let fetched = try XCTUnwrap(try fetchContext.fetch(descriptor).first)
        XCTAssertEqual(fetched.selectedExercise?.canonicalName, "Dumbbell Bench Press Slot Test")
        XCTAssertEqual(fetched.reason, .userPreference)
        XCTAssertEqual(fetched.templateSlot?.name, "Horizontal Push Persistence Test")
        XCTAssertEqual(fetched.programInstance?.id, instance.id)
    }

    /// Deleting the `ExerciseSlot` (as happens when its `ProgramDefinition`
    /// cascades away) must nullify `templateSlot` cleanly rather than
    /// crash — the same established `referencedAsPairedSlotBy`-style
    /// guard, proven directly for this new relationship.
    func testDeletingExerciseSlotNullifiesRatherThanCrashingSlotSelectionOverride() throws {
        let slot = ExerciseSlot(name: "Nullify Test Slot", allowedTargets: [.chest])
        context.insert(slot)
        let exercise = Exercise(canonicalName: "Nullify Test Exercise", modality: .hypertrophy, equipment: "dumbbell", movementPattern: "horizontalPush")
        context.insert(exercise)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        let override = SlotSelectionOverride(selectedExercise: exercise)
        override.templateSlot = slot
        context.insert(override)
        instance.addSlotSelectionOverride(override)
        try context.save()

        context.delete(slot)
        XCTAssertNoThrow(try context.save())

        XCTAssertNil(override.templateSlot)
        XCTAssertNotNil(override.programInstance, "the override itself must survive — only the dangling template reference nullifies")
    }

    // MARK: - ActivitySelectionOverride

    func testActivitySelectionOverrideSurvivesRoundTrip() throws {
        let template = SteadyStatePrescriptionTemplate(preferredActivityType: .cycling, allowedActivityTypes: [.cycling, .rowing])
        context.insert(template)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)

        let overrideID = UUID()
        let override = ActivitySelectionOverride(id: overrideID, selectedActivityType: .rowing, reason: .equipmentUnavailable)
        override.templateSteadyState = template
        context.insert(override)
        instance.addActivitySelectionOverride(override)
        try context.save()

        let fetchContext = freshContext()
        let descriptor = FetchDescriptor<ActivitySelectionOverride>(predicate: #Predicate { $0.id == overrideID })
        let fetched = try XCTUnwrap(try fetchContext.fetch(descriptor).first)
        XCTAssertEqual(fetched.selectedActivityType, .rowing)
        XCTAssertEqual(fetched.reason, .equipmentUnavailable)
        XCTAssertEqual(fetched.templateSteadyState?.preferredActivityType, .cycling)
    }

    /// Deleting the `ProgramInstance` cascades its overrides away — pure
    /// instance-state, not performance history, so nothing here should
    /// survive (contrast with `Session`'s `.nullify`, which does need to
    /// survive).
    func testDeletingProgramInstanceCascadesItsSlotSelectionOverrides() throws {
        let slot = ExerciseSlot(name: "Cascade Test Slot", allowedTargets: [.chest])
        context.insert(slot)
        let exercise = Exercise(canonicalName: "Cascade Test Exercise", modality: .hypertrophy, equipment: "dumbbell", movementPattern: "horizontalPush")
        context.insert(exercise)
        let instanceID = UUID()
        let instance = ProgramInstance(id: instanceID, ownerUserID: UUID())
        context.insert(instance)
        let overrideID = UUID()
        let override = SlotSelectionOverride(id: overrideID, selectedExercise: exercise)
        override.templateSlot = slot
        context.insert(override)
        instance.addSlotSelectionOverride(override)
        try context.save()

        context.delete(instance)
        try context.save()

        let fetchContext = freshContext()
        let overrideDescriptor = FetchDescriptor<SlotSelectionOverride>(predicate: #Predicate { $0.id == overrideID })
        XCTAssertTrue(try fetchContext.fetch(overrideDescriptor).isEmpty, "the override is pure instance state and must not outlive its ProgramInstance")
    }
}
