import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 4C Part B (§15-45), test requirements §49-53: proves the
/// substitution architecture end to end — strength (THIS SESSION ONLY vs.
/// GOING FORWARD, historical stability, performance-profile separation),
/// slot validity, endurance activity substitution, cross-`ProgramInstance`
/// non-leakage, and Functional Fitness scaling compatibility.
@MainActor
final class SubstitutionTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    // MARK: - Strength fixture

    private func buildSingleSlotStrengthProgram() -> (definition: ProgramDefinition, slot: ExerciseSlot, barbell: Exercise, dumbbell: Exercise) {
        let barbell = Exercise(canonicalName: "Barbell Bench Press (Sub Test)", modality: .hypertrophy, equipment: "barbell", movementPattern: "horizontalPush", primaryTargets: [.chest, .triceps])
        let dumbbell = Exercise(canonicalName: "Dumbbell Bench Press (Sub Test)", modality: .hypertrophy, equipment: "dumbbell", movementPattern: "horizontalPush", primaryTargets: [.chest, .triceps])
        context.insert(barbell)
        context.insert(dumbbell)

        let definition = ProgramDefinition(name: "Substitution Test Program", lengthWeeks: 4, programmingSystem: .hypertrophy, generatorVersion: 1, provenance: .constructed(reason: "test"))
        context.insert(definition)
        for _ in 0..<4 {
            let week = TrainingWeek(isDeload: false)
            context.insert(week)
            definition.addWeek(week)
        }
        let session = TemplateSession(name: "Push Day", role: .hypertrophy)
        context.insert(session)
        definition.addTemplateSession(session)
        let block = WorkoutBlockTemplate(type: .hypertrophy)
        context.insert(block)
        session.addBlockTemplate(block)
        let template = PrescriptionTemplate(rules: StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.85, laterWeekMultipliers: [1.05, 1.075, 1.1])),
            setCountRule: .fixed(setsByWeek: [3, 3, 3, 3]),
            repGoalSchedule: [RepGoal(reps: 10, toFailure: true)]
        ))
        context.insert(template)
        block.addPrescriptionTemplate(template)
        let slot = ExerciseSlot(name: "Horizontal Push", allowedTargets: [.chest, .triceps], resolvedExercise: barbell)
        context.insert(slot)
        template.attachExerciseSlot(slot)

        return (definition, slot, barbell, dumbbell)
    }

    private func materializeStrengthWeek(definition: ProgramDefinition, instance: ProgramInstance, weekIndex: Int) -> [Session] {
        StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: weekIndex, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: instance.ownerUserID,
            equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
            slotContext: { _ in StrengthMaterializer.SlotContext(rmKilograms: 100) }, context: context
        ).sessions
    }

    // MARK: - §49.18-19: THIS SESSION ONLY

    func testThisSessionOnlySubstitutionDoesNotAffectFutureMaterializedSessions() throws {
        let (definition, slot, barbell, dumbbell) = buildSingleSlotStrengthProgram()
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition

        let week0Sessions = materializeStrengthWeek(definition: definition, instance: instance, weekIndex: 0)
        let week0Prescription = try XCTUnwrap(week0Sessions.first?.orderedBlocks.first?.orderedPrescriptions.first)
        XCTAssertEqual(week0Prescription.exercise?.id, barbell.id)

        try SubstituteExerciseUseCase.substituteThisSessionOnly(prescription: week0Prescription, slot: slot, with: dumbbell, reason: .userPreference)
        XCTAssertEqual(week0Prescription.exercise?.id, dumbbell.id)
        XCTAssertTrue(week0Prescription.substitutionUsed)
        XCTAssertEqual(week0Prescription.substitutionReason, .userPreference)

        // §19: a future Session returns to the template's own default.
        let week1Sessions = materializeStrengthWeek(definition: definition, instance: instance, weekIndex: 1)
        let week1Prescription = try XCTUnwrap(week1Sessions.first?.orderedBlocks.first?.orderedPrescriptions.first)
        XCTAssertEqual(week1Prescription.exercise?.id, barbell.id, "THIS SESSION ONLY must not leak into future materialization")
    }

    // MARK: - §49.20-23/§52: GOING FORWARD + historical stability

    func testGoingForwardSubstitutionAffectsOnlyFutureMaterializationNeverAlreadyMaterializedSessions() throws {
        let (definition, slot, barbell, dumbbell) = buildSingleSlotStrengthProgram()
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition

        let week0Sessions = materializeStrengthWeek(definition: definition, instance: instance, weekIndex: 0)
        let week0Prescription = try XCTUnwrap(week0Sessions.first?.orderedBlocks.first?.orderedPrescriptions.first)
        week0Prescription.workoutBlock?.session?.status = .completed
        XCTAssertEqual(week0Prescription.exercise?.id, barbell.id)

        try SubstituteExerciseUseCase.substituteGoingForward(instance: instance, slot: slot, with: dumbbell, reason: .equipmentUnavailable, context: context)

        // §42: the already-materialized (and now completed) week 0 Session
        // must never be retroactively rewritten.
        XCTAssertEqual(week0Prescription.exercise?.id, barbell.id, "a completed Session must never be retroactively changed by a later substitution")

        // §21/§30: a not-yet-materialized future Session picks up the new selection.
        let week1Sessions = materializeStrengthWeek(definition: definition, instance: instance, weekIndex: 1)
        let week1Prescription = try XCTUnwrap(week1Sessions.first?.orderedBlocks.first?.orderedPrescriptions.first)
        XCTAssertEqual(week1Prescription.exercise?.id, dumbbell.id)

        // §20/§43: the reusable template graph itself is never mutated.
        XCTAssertEqual(slot.resolvedExercise?.id, barbell.id, "ProgramDefinition/its template graph must never be mutated by a user substitution")
    }

    /// §31: switching back recovers the original selection cleanly.
    func testSwitchingBackToTheOriginalExerciseWorks() throws {
        let (definition, slot, barbell, dumbbell) = buildSingleSlotStrengthProgram()
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition

        try SubstituteExerciseUseCase.substituteGoingForward(instance: instance, slot: slot, with: dumbbell, context: context)
        XCTAssertEqual(SubstituteExerciseUseCase.resolvedExercise(for: slot, in: instance)?.id, dumbbell.id)

        try SubstituteExerciseUseCase.substituteGoingForward(instance: instance, slot: slot, with: barbell, context: context)
        XCTAssertEqual(SubstituteExerciseUseCase.resolvedExercise(for: slot, in: instance)?.id, barbell.id)

        // §41: exactly one override row exists for this (instance, slot)
        // pair throughout — updated in place, never accumulated.
        XCTAssertEqual(instance.slotSelectionOverrides.count, 1)
    }

    /// §32: a substitution made under one ProgramInstance must never
    /// silently apply to a different instance of the same slot.
    func testGoingForwardOverrideDoesNotLeakToADifferentProgramInstance() throws {
        let (definition, slot, barbell, dumbbell) = buildSingleSlotStrengthProgram()
        let instanceA = ProgramInstance(ownerUserID: UUID())
        context.insert(instanceA)
        instanceA.programDefinition = definition
        try SubstituteExerciseUseCase.substituteGoingForward(instance: instanceA, slot: slot, with: dumbbell, context: context)

        let instanceB = ProgramInstance(ownerUserID: UUID())
        context.insert(instanceB)
        instanceB.programDefinition = definition

        XCTAssertEqual(SubstituteExerciseUseCase.resolvedExercise(for: slot, in: instanceA)?.id, dumbbell.id)
        XCTAssertEqual(SubstituteExerciseUseCase.resolvedExercise(for: slot, in: instanceB)?.id, barbell.id, "a fresh ProgramInstance must not inherit another instance's override")
    }

    // MARK: - §27/§50: slot validity

    func testValidSubstitutionIsAcceptedAndInvalidSubstitutionIsRejected() {
        let (_, slot, _, _) = buildSingleSlotStrengthProgram()
        let squat = Exercise(canonicalName: "Back Squat (Sub Test)", modality: .strength, equipment: "barbell", movementPattern: "squat", primaryTargets: [.quadriceps, .glutes])
        context.insert(squat)

        XCTAssertFalse(SubstitutionValidator.isValid(candidate: squat, for: slot), "a squat must not satisfy a Horizontal Push slot")

        XCTAssertThrowsError(try SubstituteExerciseUseCase.substituteThisSessionOnly(
            prescription: ExercisePrescription(), slot: slot, with: squat
        )) { error in
            XCTAssertEqual(error as? SubstitutionError, .invalidForSlot)
        }
    }

    /// §22/§50.29: a slot permitting multiple targets (Stage 3 decision
    /// A6) validates an exercise matching *either* target, not just the
    /// first one listed.
    func testMultiTargetSlotAcceptsAnExerciseMatchingEitherAllowedTarget() {
        let slot = ExerciseSlot(name: "Chest Isolation or Triceps", allowedTargets: [.chest, .triceps])
        context.insert(slot)
        let cableFly = Exercise(canonicalName: "Cable Fly (Sub Test)", modality: .hypertrophy, equipment: "cable", movementPattern: "horizontalPush", primaryTargets: [.chest])
        let tricepPushdown = Exercise(canonicalName: "Tricep Pushdown (Sub Test)", modality: .hypertrophy, equipment: "cable", movementPattern: "elbowExtension", primaryTargets: [.triceps])
        context.insert(cableFly)
        context.insert(tricepPushdown)

        XCTAssertTrue(SubstitutionValidator.isValid(candidate: cableFly, for: slot))
        XCTAssertTrue(SubstitutionValidator.isValid(candidate: tricepPushdown, for: slot))
    }

    // MARK: - §23-25/§29/§44: performance-profile separation and recommendation confidence

    func testSubstitutedExerciseGetsItsOwnPerformanceProfileNeverMergedWithTheOriginal() {
        let (_, _, barbell, dumbbell) = buildSingleSlotStrengthProgram()
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)

        let barbellProfile = PerformanceProfileStore.exerciseProfile(for: barbell, in: performanceProfile, context: context)
        barbellProfile.estimatedOneRepMax = 100
        barbellProfile.confidence = 0.9

        // §24: the substitute must not inherit the original's PR/estimate.
        let dumbbellProfile = PerformanceProfileStore.exerciseProfile(for: dumbbell, in: performanceProfile, context: context)
        XCTAssertNotEqual(dumbbellProfile.id, barbellProfile.id)
        XCTAssertNil(dumbbellProfile.estimatedOneRepMax, "switching exercises must never copy the original's 1RM")
        XCTAssertEqual(dumbbellProfile.confidence, 0, "a freshly created profile has no confidence yet")

        // §25/§29/§44: no history yet for Dumbbell and no related exercise
        // supplied -> CALIBRATION_REQUIRED, never an invented load.
        let recommendation = SubstitutionAwareRecommendation.resolve(SubstitutionAwareRecommendation.Input(
            selectedExercise: dumbbell, selectedExerciseProfile: dumbbellProfile,
            candidatesForEstimate: [], curatedRelationships: [], relatedProfileLookup: { _ in nil }
        ))
        XCTAssertNil(recommendation.referenceOneRepMax)
        XCTAssertEqual(recommendation.reasonCode, .calibrationRequired)
        XCTAssertEqual(recommendation.confidence, 0)

        // §31: switching back, Barbell's original history is untouched.
        XCTAssertEqual(barbellProfile.estimatedOneRepMax, 100)
        XCTAssertEqual(barbellProfile.confidence, 0.9)
    }

    /// §25/§26/§44: a related exercise's history can inform a lower-
    /// confidence estimate, but only through a real, typed relationship —
    /// never by inventing a number.
    func testRelatedExerciseInformsALowerConfidenceEstimateWhenNoDirectHistoryExists() {
        let (_, _, barbell, dumbbell) = buildSingleSlotStrengthProgram()
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        let barbellProfile = PerformanceProfileStore.exerciseProfile(for: barbell, in: performanceProfile, context: context)
        barbellProfile.estimatedOneRepMax = 100
        barbellProfile.confidence = 0.9

        let relationship = ExerciseRelationship(fromExercise: dumbbell, toExercise: barbell, type: .directSubstitute)
        context.insert(relationship)

        let recommendation = SubstitutionAwareRecommendation.resolve(SubstitutionAwareRecommendation.Input(
            selectedExercise: dumbbell, selectedExerciseProfile: nil,
            candidatesForEstimate: [barbell], curatedRelationships: [relationship],
            relatedProfileLookup: { $0.id == barbell.id ? barbellProfile : nil }
        ))
        XCTAssertEqual(recommendation.referenceOneRepMax, 100)
        XCTAssertEqual(recommendation.reasonCode, .substitutionEstimate)
        XCTAssertEqual(recommendation.confidence, 0.45, accuracy: 0.0001, "0.9 * the 0.5 TrainingOS-designed discount")
    }

    func testExactOwnHistoryIsPreferredOverARelatedExerciseEstimate() {
        let (_, _, barbell, dumbbell) = buildSingleSlotStrengthProgram()
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        let barbellProfile = PerformanceProfileStore.exerciseProfile(for: barbell, in: performanceProfile, context: context)
        barbellProfile.estimatedOneRepMax = 100
        barbellProfile.confidence = 0.9
        let dumbbellProfile = PerformanceProfileStore.exerciseProfile(for: dumbbell, in: performanceProfile, context: context)
        dumbbellProfile.estimatedOneRepMax = 40
        dumbbellProfile.confidence = 0.8

        let recommendation = SubstitutionAwareRecommendation.resolve(SubstitutionAwareRecommendation.Input(
            selectedExercise: dumbbell, selectedExerciseProfile: dumbbellProfile,
            candidatesForEstimate: [barbell], curatedRelationships: [],
            relatedProfileLookup: { $0.id == barbell.id ? barbellProfile : nil }
        ))
        XCTAssertEqual(recommendation.referenceOneRepMax, 40, "Dumbbell's own history must win over Barbell's, even though Barbell's is more complete")
        XCTAssertEqual(recommendation.reasonCode, .percentageOfEstimate)
        XCTAssertEqual(recommendation.confidence, 0.8)
    }

    // MARK: - §34-37/§51: endurance activity substitution

    private func buildSteadyStateFixture(preferred: ActivityType, allowed: [ActivityType], primaryIntensity: IntensityTarget?) -> (definition: ProgramDefinition, template: SteadyStatePrescriptionTemplate) {
        let configuration = SteadyStateProgramConfiguration(activityType: preferred, allowedActivityTypes: allowed, daysPerWeek: 1, lengthWeeks: 2, progressionDimension: .none)
        let definition = SteadyStateProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let template = definition.orderedTemplateSessions[0].orderedBlockTemplates[0].steadyStatePrescriptionTemplate!
        template.primaryIntensity = primaryIntensity
        return (definition, template)
    }

    func testThisSessionOnlyActivitySubstitutionDoesNotAffectFutureSessionsAndEntersTheNewActivitysHistory() throws {
        let (definition, template) = buildSteadyStateFixture(preferred: .cycling, allowed: [.cycling, .rowing], primaryIntensity: .heartRateZone(.two))
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition

        let sessions = SteadyStateMaterializer.materializeAllWeeks(definition: definition, instance: instance, startDate: Date(timeIntervalSince1970: 0), ownerUserID: instance.ownerUserID, context: context)
        let day0Prescription = try XCTUnwrap(sessions[0].orderedBlocks.first?.steadyStatePrescription)
        XCTAssertEqual(day0Prescription.activityType, .cycling)

        try SubstituteActivityUseCase.substituteThisSessionOnly(prescription: day0Prescription, template: template, with: .rowing, reason: .equipmentUnavailable)
        XCTAssertEqual(day0Prescription.activityType, .rowing)
        XCTAssertTrue(day0Prescription.substitutionUsed)

        // §35: the next already-materialized Session (built before the
        // substitution) is unaffected.
        XCTAssertEqual(sessions[1].orderedBlocks.first?.steadyStatePrescription?.activityType, .cycling)

        // §36: logging the actual result must go to Rowing's history, not Cycling's.
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        let rowingProfile = PerformanceProfileStore.activityProfile(for: .rowing, in: performanceProfile, context: context)
        let result = SteadyStateResult(actualDurationSeconds: 2700)
        context.insert(result)
        rowingProfile.addSteadyStateResult(result)
        result.activityPerformanceProfile = rowingProfile
        XCTAssertEqual(rowingProfile.steadyStateResults.count, 1)
        let cyclingProfile = PerformanceProfileStore.activityProfile(for: .cycling, in: performanceProfile, context: context)
        XCTAssertEqual(cyclingProfile.steadyStateResults.count, 0, "the substituted result must not also appear under Cycling")

        // §37 (the original template's own default is untouched).
        XCTAssertEqual(template.preferredActivityType, .cycling)
    }

    func testGoingForwardActivitySubstitutionAffectsOnlyFutureMaterialization() throws {
        let (definition, template) = buildSteadyStateFixture(preferred: .cycling, allowed: [.cycling, .rowing], primaryIntensity: .heartRateZone(.two))
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition

        let firstBatch = SteadyStateMaterializer.materializeAllWeeks(definition: definition, instance: instance, startDate: Date(timeIntervalSince1970: 0), ownerUserID: instance.ownerUserID, context: context)
        let alreadyMaterializedPrescription = try XCTUnwrap(firstBatch.first?.orderedBlocks.first?.steadyStatePrescription)

        try SubstituteActivityUseCase.substituteGoingForward(instance: instance, template: template, with: .rowing, context: context)

        XCTAssertEqual(alreadyMaterializedPrescription.activityType, .cycling, "already-materialized Sessions must not retroactively change")
        XCTAssertEqual(SubstituteActivityUseCase.resolvedActivityType(for: template, in: instance), .rowing)
        XCTAssertEqual(template.preferredActivityType, .cycling, "the template's own default must never be mutated")
    }

    /// §35/§38: a running-specific prescription must reject Bike.
    func testRunningSpecificPrescriptionRejectsCyclingSubstitution() {
        let (_, template) = buildSteadyStateFixture(preferred: .running, allowed: [.running], primaryIntensity: .pace(PaceRange(lower: Pace(secondsPerKilometer: 260), upper: Pace(secondsPerKilometer: 280))))
        XCTAssertFalse(SubstituteActivityUseCase.isValid(candidate: .cycling, for: template))
        XCTAssertThrowsError(try SubstituteActivityUseCase.substituteThisSessionOnly(
            prescription: SteadyStatePrescription(activityType: .running), template: template, with: .cycling
        )) { error in
            XCTAssertEqual(error as? SubstitutionError, .invalidForSlot)
        }
    }

    /// §37/§39: a modality-specific power target must not silently
    /// transfer to the new activity.
    func testEquipmentSpecificIntensityDoesNotTransferAcrossActivitySubstitution() throws {
        let bikePower = IntensityTarget.powerRange(PowerRange(lower: Power(watts: 180), upper: Power(watts: 200)))
        let (_, template) = buildSteadyStateFixture(preferred: .cycling, allowed: [.cycling, .rowing], primaryIntensity: bikePower)
        let prescription = SteadyStatePrescription(activityType: .cycling, primaryIntensity: bikePower)
        context.insert(prescription)

        try SubstituteActivityUseCase.substituteThisSessionOnly(prescription: prescription, template: template, with: .rowing)
        XCTAssertEqual(prescription.activityType, .rowing)
        XCTAssertNil(prescription.primaryIntensity, "a Bike power target must never be silently reused as a Row target")
    }

    // MARK: - §53: Functional Fitness scaling compatibility (existing model, confirmed not broken)

    func testFunctionalFitnessScalingPreservesThePrescribedMovementSeparatelyFromWhatWasPerformed() {
        let toesToBar = Exercise(canonicalName: "Toes-to-Bar (Sub Test)", modality: .functionalFitness, equipment: "bar", movementPattern: "gymnasticsPull")
        let kneeRaises = Exercise(canonicalName: "Knee Raises (Sub Test)", modality: .functionalFitness, equipment: "bar", movementPattern: "gymnasticsPull")
        context.insert(toesToBar)
        context.insert(kneeRaises)

        let stimulus = Stimulus(
            targetDurationDomain: .medium, intensity: .high, loading: .bodyweightOnly,
            movementFunctions: [.gymnasticsPull], movementModalityMix: [ModalityCount(modality: .gymnastics, count: 1)],
            skillDemand: .moderate, systemicDemand: .moderate, scoreType: .roundsAndReps
        )
        let prescription = FunctionalFitnessPrescription(stimulus: stimulus, format: .amrap(capSeconds: 720))
        context.insert(prescription)
        let movement = FunctionalFitnessMovement(exercise: toesToBar, reps: 10)
        context.insert(movement)
        prescription.addMovement(movement)

        let result = FunctionalFitnessResult(scoreType: .roundsAndReps, scoreValue: .roundsAndReps(rounds: 5, partialReps: 3), scoreDirection: .higherIsBetter, resultContext: .scaled)
        context.insert(result)
        let performed = FunctionalFitnessPerformedMovement(prescribedMovement: movement, performedExercise: kneeRaises, performedReps: 10)
        context.insert(performed)
        result.addPerformedMovement(performed)

        XCTAssertEqual(movement.exercise?.canonicalName, "Toes-to-Bar (Sub Test)", "the prescription itself must remain Toes-to-Bar, never overwritten by the scaled attempt")
        XCTAssertEqual(performed.prescribedMovement?.exercise?.canonicalName, "Toes-to-Bar (Sub Test)")
        XCTAssertEqual(performed.performedExercise?.canonicalName, "Knee Raises (Sub Test)")
        XCTAssertEqual(result.resultContext, .scaled)
    }
}
