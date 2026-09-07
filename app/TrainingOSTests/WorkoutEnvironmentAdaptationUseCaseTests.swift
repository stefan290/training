import XCTest
import SwiftData
@testable import TrainingOS

/// V1 R5 (Training Environment product reconciliation), Part 1: proves
/// "use Home Gym for THIS workout" is genuinely safe, using the real
/// production primitives (`SubstituteExerciseUseCase.substituteThisSessionOnly`,
/// `SubstitutionCandidateRanking`, `TrainingEnvironmentCompatibilityRule`)
/// this checkpoint's own architecture trace found already exist and
/// already compose correctly — `WorkoutEnvironmentAdaptationUseCase` is
/// pure orchestration over them, never a new mechanism.
@MainActor
final class WorkoutEnvironmentAdaptationUseCaseTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    /// Mirrors `SubstitutionTests.buildSingleSlotStrengthProgram` — a
    /// real, single-slot strength program materialized into one real
    /// Session, so this checkpoint's own adaptation orchestration is
    /// proven against the exact same real production shape the pre-
    /// existing substitution architecture already proves safe.
    private func buildMaterializedStrengthSession(candidates: [Exercise]) -> (instance: ProgramInstance, slot: ExerciseSlot, session: Session, prescription: ExercisePrescription) {
        let definition = ProgramDefinition(name: "R5 Adaptation Test Program", lengthWeeks: 4, programmingSystem: .hypertrophy, generatorVersion: 1, provenance: .constructed(reason: "test"))
        context.insert(definition)
        for _ in 0..<4 {
            let week = TrainingWeek(isDeload: false)
            context.insert(week)
            definition.addWeek(week)
        }
        let templateSession = TemplateSession(name: "Push Day", role: .hypertrophy)
        context.insert(templateSession)
        definition.addTemplateSession(templateSession)
        let block = WorkoutBlockTemplate(type: .hypertrophy)
        context.insert(block)
        templateSession.addBlockTemplate(block)
        let template = PrescriptionTemplate(rules: StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.85, laterWeekMultipliers: [1.05, 1.075, 1.1])),
            setCountRule: .fixed(setsByWeek: [3, 3, 3, 3]), repGoalSchedule: [RepGoal.rir(10)]
        ))
        context.insert(template)
        block.addPrescriptionTemplate(template)
        let slot = ExerciseSlot(name: "Horizontal Push", allowedTargets: [.chest, .triceps])
        context.insert(slot)
        template.attachExerciseSlot(slot)

        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition
        try? ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: candidates, environment: TrainingEnvironment.fullGym())

        let sessions = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: instance.ownerUserID,
            equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
            slotContext: { _ in StrengthMaterializer.SlotContext(rmKilograms: 100) }, context: context
        ).sessions
        let session = sessions[0]
        let prescription = session.orderedBlocks[0].orderedPrescriptions[0]
        return (instance, slot, session, prescription)
    }

    // MARK: G(i) — already-compatible prescription is left unchanged

    func testCompatibleExerciseIsNeverTouchedByAnAdaptation() throws {
        let barbell = Exercise(canonicalName: "R5 Barbell Bench Press", modality: .hypertrophy, equipment: "barbell", movementPattern: "horizontalPush", primaryTargets: [.chest, .triceps], requiredEquipment: [.barbell, .bench])
        context.insert(barbell)
        let fixture = buildMaterializedStrengthSession(candidates: [barbell])
        XCTAssertEqual(fixture.prescription.exercise?.id, barbell.id)

        let fullGym = TrainingEnvironment.fullGym()
        let adaptations = WorkoutEnvironmentAdaptationUseCase.preview(
            session: fixture.session, targetEnvironment: fullGym, candidateExercises: [barbell],
            curatedRelationships: [], profileLookup: { _ in nil }
        )
        XCTAssertTrue(adaptations.isEmpty, "a prescription already compatible with the target environment must never be listed as needing adaptation")
    }

    // MARK: G(ii) — incompatible prescription is substituted with a real, eligible replacement

    func testIncompatibleExerciseIsSubstitutedWithARealEligibleReplacement() throws {
        let barbell = Exercise(canonicalName: "R5 Barbell Bench Press", modality: .hypertrophy, equipment: "barbell", movementPattern: "horizontalPush", primaryTargets: [.chest, .triceps], requiredEquipment: [.barbell, .bench])
        let dumbbell = Exercise(canonicalName: "R5 Dumbbell Bench Press", modality: .hypertrophy, equipment: "dumbbell", movementPattern: "horizontalPush", primaryTargets: [.chest, .triceps], requiredEquipment: [.dumbbells, .bench])
        context.insert(barbell)
        context.insert(dumbbell)
        let fixture = buildMaterializedStrengthSession(candidates: [barbell, dumbbell])
        XCTAssertEqual(fixture.prescription.exercise?.id, barbell.id)

        // A real Home Gym with no barbell — genuinely incompatible.
        let homeGym = TrainingEnvironment(name: "Home Gym", availableEquipment: [.dumbbells, .bench])
        context.insert(homeGym)

        let adaptations = WorkoutEnvironmentAdaptationUseCase.preview(
            session: fixture.session, targetEnvironment: homeGym, candidateExercises: [barbell, dumbbell],
            curatedRelationships: [], profileLookup: { _ in nil }
        )
        XCTAssertEqual(adaptations.count, 1)
        XCTAssertEqual(adaptations.first?.originalExercise.id, barbell.id)
        XCTAssertEqual(adaptations.first?.replacementExercise?.id, dumbbell.id)

        try WorkoutEnvironmentAdaptationUseCase.apply(adaptations, environment: homeGym)
        XCTAssertEqual(fixture.prescription.exercise?.id, dumbbell.id, "the prescription must now hold the real, environment-compatible substitute")
        XCTAssertTrue(fixture.prescription.substitutionUsed)
        XCTAssertEqual(fixture.prescription.substitutionReason, .equipmentUnavailable)
    }

    // MARK: no real substitute available — honestly disclosed, never forced

    func testNoRealSubstituteAvailableIsHonestlyDisclosedNeverForced() throws {
        let barbell = Exercise(canonicalName: "R5 Barbell Bench Press Only", modality: .hypertrophy, equipment: "barbell", movementPattern: "horizontalPush", primaryTargets: [.chest, .triceps], requiredEquipment: [.barbell, .bench])
        context.insert(barbell)
        let fixture = buildMaterializedStrengthSession(candidates: [barbell])

        let bodyweightOnly = TrainingEnvironment(name: "Travel", availableEquipment: [.bodyweight])
        context.insert(bodyweightOnly)

        let adaptations = WorkoutEnvironmentAdaptationUseCase.preview(
            session: fixture.session, targetEnvironment: bodyweightOnly, candidateExercises: [barbell],
            curatedRelationships: [], profileLookup: { _ in nil }
        )
        XCTAssertEqual(adaptations.count, 1)
        XCTAssertNil(adaptations.first?.replacementExercise, "no real, eligible candidate exists in this environment — must be disclosed, never fabricated")

        try WorkoutEnvironmentAdaptationUseCase.apply(adaptations, environment: bodyweightOnly)
        XCTAssertEqual(fixture.prescription.exercise?.id, barbell.id, "a prescription with no real replacement must be left exactly as it was, never silently forced")
    }

    // MARK: H — progression evidence remains exercise-specific after a this-session-only adaptation

    func testAdaptedExerciseResultDoesNotIncorrectlyProgressTheOriginalExercise() throws {
        let barbell = Exercise(canonicalName: "R5 Progression Barbell Bench", modality: .hypertrophy, equipment: "barbell", movementPattern: "horizontalPush", primaryTargets: [.chest, .triceps], requiredEquipment: [.barbell, .bench])
        let dumbbell = Exercise(canonicalName: "R5 Progression Dumbbell Bench", modality: .hypertrophy, equipment: "dumbbell", movementPattern: "horizontalPush", primaryTargets: [.chest, .triceps], requiredEquipment: [.dumbbells, .bench])
        context.insert(barbell)
        context.insert(dumbbell)
        let fixture = buildMaterializedStrengthSession(candidates: [barbell, dumbbell])
        let homeGym = TrainingEnvironment(name: "Home Gym", availableEquipment: [.dumbbells, .bench])
        context.insert(homeGym)

        let adaptations = WorkoutEnvironmentAdaptationUseCase.preview(
            session: fixture.session, targetEnvironment: homeGym, candidateExercises: [barbell, dumbbell],
            curatedRelationships: [], profileLookup: { _ in nil }
        )
        try WorkoutEnvironmentAdaptationUseCase.apply(adaptations, environment: homeGym)
        XCTAssertEqual(fixture.prescription.exercise?.id, dumbbell.id)

        // Log a real result the exact way live execution does — reading
        // the prescription's CURRENT exercise, never the original slot
        // default (this is the real, existing, unmodified contract this
        // checkpoint's own architecture trace confirmed).
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        let (result, _) = RecordSetResultUseCase.recordSet(
            setIndex: 0, weight: 40, reps: 8, targetRir: 2, actualRir: 2, prBand: "8-12",
            scoringDirection: .higherIsBetter, context: .rx, setPrescription: nil,
            exercisePrescription: fixture.prescription, exercise: try XCTUnwrap(fixture.prescription.exercise),
            performanceProfile: performanceProfile, completedAt: Date(), modelContext: context
        )
        XCTAssertEqual(result.weight, 40)

        let dumbbellProfile = performanceProfile.exerciseProfiles.first { $0.exercise?.id == dumbbell.id }
        let barbellProfile = performanceProfile.exerciseProfiles.first { $0.exercise?.id == barbell.id }
        XCTAssertNotNil(dumbbellProfile, "the logged result must become real evidence for the substitute exercise")
        XCTAssertNil(barbellProfile, "the original (unperformed) exercise must never gain evidence it was never actually given")
        XCTAssertEqual(dumbbellProfile?.setResults.count, 1)
    }

    // MARK: I — a this-session-only adaptation never becomes a persistent substitution preference

    func testThisSessionOnlyAdaptationNeverCreatesAGoingForwardPreference() throws {
        let barbell = Exercise(canonicalName: "R5 NoPref Barbell Bench", modality: .hypertrophy, equipment: "barbell", movementPattern: "horizontalPush", primaryTargets: [.chest, .triceps], requiredEquipment: [.barbell, .bench])
        let dumbbell = Exercise(canonicalName: "R5 NoPref Dumbbell Bench", modality: .hypertrophy, equipment: "dumbbell", movementPattern: "horizontalPush", primaryTargets: [.chest, .triceps], requiredEquipment: [.dumbbells, .bench])
        context.insert(barbell)
        context.insert(dumbbell)
        let fixture = buildMaterializedStrengthSession(candidates: [barbell, dumbbell])
        let homeGym = TrainingEnvironment(name: "Home Gym", availableEquipment: [.dumbbells, .bench])
        context.insert(homeGym)

        let adaptations = WorkoutEnvironmentAdaptationUseCase.preview(
            session: fixture.session, targetEnvironment: homeGym, candidateExercises: [barbell, dumbbell],
            curatedRelationships: [], profileLookup: { _ in nil }
        )
        try WorkoutEnvironmentAdaptationUseCase.apply(adaptations, environment: homeGym)

        XCTAssertNil(fixture.instance.slotSelectionOverride(for: fixture.slot), "a this-session-only environment adaptation must never write a SlotSelectionOverride")

        // A future materialized week returns to the template's own
        // default — proving the adaptation never mutated the
        // ProgramInstance/ProgramDefinition/future materialization.
        let week1Sessions = StrengthMaterializer.materializeWeek(
            definition: try XCTUnwrap(fixture.instance.programDefinition), instance: fixture.instance, weekIndex: 1, isDeload: false,
            startDate: Date(timeIntervalSince1970: 7 * 86400), ownerUserID: fixture.instance.ownerUserID,
            equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
            slotContext: { _ in StrengthMaterializer.SlotContext(rmKilograms: 100) }, context: context
        ).sessions
        let week1Prescription = try XCTUnwrap(week1Sessions.first?.orderedBlocks.first?.orderedPrescriptions.first)
        XCTAssertEqual(week1Prescription.exercise?.id, barbell.id, "future materialization must return to the template default, never inherit today's workout-only adaptation")
    }

    // MARK: source slot intent preserved — a candidate outside the slot's own constraints is never chosen

    func testAdaptationNeverPicksAnExerciseOutsideTheSlotsOwnSemanticConstraints() throws {
        let barbell = Exercise(canonicalName: "R5 SlotIntent Barbell Bench", modality: .hypertrophy, equipment: "barbell", movementPattern: "horizontalPush", primaryTargets: [.chest, .triceps], requiredEquipment: [.barbell, .bench])
        // A real exercise that fits the new environment but targets an
        // unrelated muscle group — must never be picked merely because
        // it's environment-compatible.
        let unrelated = Exercise(canonicalName: "R5 SlotIntent Dumbbell Row", modality: .hypertrophy, equipment: "dumbbell", movementPattern: "row", primaryTargets: [.back], requiredEquipment: [.dumbbells])
        context.insert(barbell)
        context.insert(unrelated)
        let fixture = buildMaterializedStrengthSession(candidates: [barbell])
        let homeGym = TrainingEnvironment(name: "Home Gym", availableEquipment: [.dumbbells, .bench])
        context.insert(homeGym)

        let adaptations = WorkoutEnvironmentAdaptationUseCase.preview(
            session: fixture.session, targetEnvironment: homeGym, candidateExercises: [barbell, unrelated],
            curatedRelationships: [], profileLookup: { _ in nil }
        )
        XCTAssertEqual(adaptations.first?.replacementExercise, nil, "an exercise that doesn't satisfy the slot's own allowedTargets must never be chosen merely for being environment-compatible")
    }
}
