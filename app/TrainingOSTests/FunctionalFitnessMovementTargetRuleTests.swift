import XCTest
import SwiftData
@testable import TrainingOS

/// Stage FF.P1: Structural Movement Targets. Proves, against real
/// production types and (where practical) the real production pipeline:
/// `FunctionalFitnessMovementTargetRule` is the single deterministic
/// source of truth for reps/distance, reused identically by
/// `FunctionalFitnessMaterializer` (initial resolution) and
/// `SubstituteFunctionalFitnessMovementUseCase` (recomputation after a
/// valid substitution); authored template targets are never overwritten;
/// targets are orthogonal to Stage CP.2's loading adaptation; and the
/// Row/SkiErg/Run <-> Assault Bike substitution edge case is handled
/// truthfully.
@MainActor
final class FunctionalFitnessMovementTargetRuleTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()
    let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func exercise(_ name: String, targets: [MuscleGroup]) -> Exercise {
        Exercise(canonicalName: name, modality: .hypertrophy, equipment: "barbell", movementPattern: "test", primaryTargets: targets)
    }

    private func resolveAllSlots(in definition: ProgramDefinition, to exercise: Exercise) {
        for templateSession in definition.orderedTemplateSessions {
            for blockTemplate in templateSession.orderedBlockTemplates {
                for template in blockTemplate.orderedPrescriptionTemplates {
                    template.exerciseSlot?.resolvedExercise = exercise
                }
            }
        }
    }

    /// The exact real fixed Stage-A/B stimulus+format every real FF mix
    /// routes through (`LongTermPlanner.functionalFitnessParameterCandidates`)
    /// — reused directly rather than driving the full mix-proposal
    /// pipeline, matching this whole test suite's established precedent
    /// (CP.1/CP.2/CP.2R's own tests do the same).
    private func realProductionStimulus() -> Stimulus {
        Stimulus(
            targetDurationDomain: .medium, intensity: .moderate, loading: .moderate,
            movementFunctions: [.squatLoaded, .gymnasticsPull, .monostructural],
            movementModalityMix: [
                ModalityCount(modality: .weightlifting, count: 1),
                ModalityCount(modality: .gymnastics, count: 1),
                ModalityCount(modality: .metabolicConditioning, count: 1),
            ],
            skillDemand: .moderate, systemicDemand: .moderate, scoreType: .time
        )
    }

    private func realProductionFormat() -> WorkoutFormat { .roundsForTime(rounds: 5, capSeconds: nil) }

    private func rowErg() -> Exercise {
        Exercise(
            canonicalName: "Row Erg", modality: .functionalFitness, equipment: "rower", movementPattern: "locomotion",
            movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning
        )
    }

    private func skiErg() -> Exercise {
        Exercise(
            canonicalName: "SkiErg", modality: .functionalFitness, equipment: "skiErg", movementPattern: "locomotion",
            movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning
        )
    }

    private func easyRun() -> Exercise {
        Exercise(
            canonicalName: "Easy Run (Zone 2)", modality: .functionalFitness, equipment: "none", movementPattern: "locomotion",
            movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning
        )
    }

    private func assaultBike() -> Exercise {
        Exercise(
            canonicalName: "Assault Bike", modality: .functionalFitness, equipment: "bike", movementPattern: "locomotion",
            movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning
        )
    }

    private func pullUp() -> Exercise {
        Exercise(
            canonicalName: "Pull-up", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "verticalPull",
            movementFunctions: [.gymnasticsPull, .verticalPullLoaded], functionalModality: .gymnastics
        )
    }

    private func toesToBar() -> Exercise {
        Exercise(
            canonicalName: "Toes-to-Bar", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "coreFlexion",
            movementFunctions: [.gymnasticsPull, .trunk], functionalModality: .gymnastics
        )
    }

    private func backSquat() -> Exercise {
        Exercise(
            canonicalName: "Back Squat", modality: .functionalFitness, equipment: "barbell", movementPattern: "squat",
            movementFunctions: [.squatLoaded], functionalModality: .weightlifting
        )
    }

    private func wallBall() -> Exercise {
        Exercise(
            canonicalName: "Wall Ball", modality: .functionalFitness, equipment: "medicineBall", movementPattern: "squatToPress",
            movementFunctions: [.squatLoaded, .pressLoaded], functionalModality: .weightlifting
        )
    }

    private func thruster() -> Exercise {
        Exercise(
            canonicalName: "Thruster", modality: .functionalFitness, equipment: "barbell", movementPattern: "squatToPress",
            movementFunctions: [.squatLoaded, .pressLoaded], functionalModality: .weightlifting
        )
    }

    // MARK: A/B — target-type classification + deterministic values

    func testSquatLoadedWeightliftingRoundsForTimeGetsTwelveReps() {
        let target = FunctionalFitnessMovementTargetRule.resolve(
            format: realProductionFormat(), modality: .weightlifting, movementFunctions: [.squatLoaded], exercise: backSquat()
        )
        XCTAssertEqual(target.reps, 12)
        XCTAssertNil(target.distanceMeters)
    }

    func testGymnasticsPullGymnasticsRoundsForTimeGetsEightReps() {
        let target = FunctionalFitnessMovementTargetRule.resolve(
            format: realProductionFormat(), modality: .gymnastics, movementFunctions: [.gymnasticsPull], exercise: pullUp()
        )
        XCTAssertEqual(target.reps, 8)
        XCTAssertNil(target.distanceMeters)
    }

    // MARK: C — total-dose sanity

    func testTotalDoseAtFiveRealProductionRoundsMatchesTheLockedTotals() {
        let squat = FunctionalFitnessMovementTargetRule.resolve(format: realProductionFormat(), modality: .weightlifting, movementFunctions: [.squatLoaded], exercise: backSquat())
        let pull = FunctionalFitnessMovementTargetRule.resolve(format: realProductionFormat(), modality: .gymnastics, movementFunctions: [.gymnasticsPull], exercise: pullUp())
        let mono = FunctionalFitnessMovementTargetRule.resolve(format: realProductionFormat(), modality: .metabolicConditioning, movementFunctions: [.monostructural], exercise: rowErg())
        XCTAssertEqual((squat.reps ?? 0) * 5, 60)
        XCTAssertEqual((pull.reps ?? 0) * 5, 40)
        XCTAssertEqual((mono.distanceMeters ?? 0) * 5, 1000)
    }

    // MARK: D/E/G/H/I — real materialization, per movement category

    func testRealMuscleGainVariedMixShapedFFSessionProducesConcreteTargetsOnAllThreeMovements() throws {
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 1, targetStimulus: realProductionStimulus(), format: realProductionFormat(),
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false
        )
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition

        let candidates = [wallBall(), pullUp(), rowErg()]
        for candidate in candidates { context.insert(candidate) }

        let sessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
            candidateExercises: candidates, exposureHistory: [], componentAdaptationObjectives: [.workCapacity, .aerobicCapacity, .power], context: context
        )
        let movements = try XCTUnwrap(sessions.first?.orderedBlocks.first { $0.type == .functionalFitness }?.functionalFitnessPrescription?.orderedMovements)
        XCTAssertEqual(movements.count, 3)
        let squatMovement = try XCTUnwrap(movements.first { $0.exercise?.canonicalName == "Wall Ball" })
        XCTAssertEqual(squatMovement.reps, 12, "loaded movement gets reps while loadKilograms stays nil")
        XCTAssertNil(squatMovement.loadKilograms)
        let pullMovement = try XCTUnwrap(movements.first { $0.exercise?.canonicalName == "Pull-up" })
        XCTAssertEqual(pullMovement.reps, 8, "bodyweight movement gets the correct .gymnasticsPull reps value")
        let rowMovement = try XCTUnwrap(movements.first { $0.exercise?.canonicalName == "Row Erg" })
        XCTAssertEqual(rowMovement.distanceMeters, 200)
    }

    func testRealFunctionalFitnessFocusedMixShapedFFSessionProducesTheIdenticalConcreteTargets() throws {
        // Per the Prescription Depth audit's own §5 finding, both real
        // mixes route through byte-identical Stage A/B/C output — this
        // proves the identical result for the FF-primary shape too, not
        // a divergent one.
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 1, targetStimulus: realProductionStimulus(), format: realProductionFormat(),
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false
        )
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition

        let candidates = [backSquat(), toesToBar(), skiErg()]
        for candidate in candidates { context.insert(candidate) }

        let sessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
            candidateExercises: candidates, exposureHistory: [],
            componentAdaptationObjectives: [.workCapacity, .aerobicCapacity, .anaerobicCapacity, .power, .skillAcquisition], context: context
        )
        let movements = try XCTUnwrap(sessions.first?.orderedBlocks.first { $0.type == .functionalFitness }?.functionalFitnessPrescription?.orderedMovements)
        XCTAssertEqual(movements.first { $0.exercise?.canonicalName == "Back Squat" }?.reps, 12)
        XCTAssertEqual(movements.first { $0.exercise?.canonicalName == "Toes-to-Bar" }?.reps, 8)
        XCTAssertEqual(movements.first { $0.exercise?.canonicalName == "SkiErg" }?.distanceMeters, 200)
    }

    func testDistanceNativeMonostructuralCandidatesAllReceiveTwoHundredMetersUniformly() {
        for candidate in [rowErg(), skiErg(), easyRun()] {
            let target = FunctionalFitnessMovementTargetRule.resolve(
                format: realProductionFormat(), modality: .metabolicConditioning, movementFunctions: [.monostructural], exercise: candidate
            )
            XCTAssertEqual(target.distanceMeters, 200, "\(candidate.canonicalName) should receive the uniform 200m target")
            XCTAssertNil(target.reps)
        }
    }

    func testAssaultBikeReceivesNoTarget() {
        let target = FunctionalFitnessMovementTargetRule.resolve(
            format: realProductionFormat(), modality: .metabolicConditioning, movementFunctions: [.monostructural], exercise: assaultBike()
        )
        XCTAssertNil(target.reps)
        XCTAssertNil(target.distanceMeters)
    }

    // MARK: J/K — unsupported cases degrade truthfully

    func testUnsupportedMovementFunctionReceivesNoGeneratedTarget() {
        let target = FunctionalFitnessMovementTargetRule.resolve(
            format: realProductionFormat(), modality: .weightlifting, movementFunctions: [.hingeLoaded],
            exercise: exercise("Deadlift", targets: [.hamstrings])
        )
        XCTAssertNil(target.reps)
        XCTAssertNil(target.distanceMeters)
    }

    func testUnsupportedWorkoutFormatReceivesNoGeneratedTarget() {
        let target = FunctionalFitnessMovementTargetRule.resolve(
            format: .amrap(capSeconds: 600), modality: .weightlifting, movementFunctions: [.squatLoaded], exercise: backSquat()
        )
        XCTAssertNil(target.reps)
        XCTAssertNil(target.distanceMeters)
    }

    // MARK: Authored precedence — never overwritten

    func testExplicitAuthoredTemplateTargetIsPreservedNotOverwritten() throws {
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 1, targetStimulus: realProductionStimulus(), format: realProductionFormat(),
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false
        )
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition

        // Simulate hand-authored/benchmark content: explicitly author the
        // squat slot's own template with a real, non-default rep count
        // BEFORE materialization.
        let squatSlot = try XCTUnwrap(
            definition.orderedTemplateSessions.first?.orderedBlockTemplates.first?
                .functionalFitnessPrescriptionTemplate?.movementSlots.first { $0.exerciseSlot?.allowedModalities.first == .weightlifting }
        )
        squatSlot.reps = 21

        let candidates = [backSquat(), pullUp(), rowErg()]
        for candidate in candidates { context.insert(candidate) }
        let sessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
            candidateExercises: candidates, exposureHistory: [], componentAdaptationObjectives: [.workCapacity], context: context
        )
        let movements = try XCTUnwrap(sessions.first?.orderedBlocks.first { $0.type == .functionalFitness }?.functionalFitnessPrescription?.orderedMovements)
        XCTAssertEqual(movements.first { $0.exercise?.canonicalName == "Back Squat" }?.reps, 21, "the explicit authored template value must never be overwritten by FF.P1's generated default (12)")
    }

    // MARK: F — CP.2R orthogonality: targets unaffected by CP.2's loading repair

    func testTargetsAreByteIdenticalBeforeAndAfterCP2sLoadingRepairFires() throws {
        let hypDefinition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 1, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: context
        )
        resolveAllSlots(in: hypDefinition, to: exercise("Back Squat", targets: [.quadriceps, .glutes]))
        let strengthInstance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(strengthInstance)
        strengthInstance.programDefinition = hypDefinition

        let peakWeekResult = StrengthMaterializer.materializeWeek(
            definition: hypDefinition, instance: strengthInstance, weekIndex: 3, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 140, weekOneResolvedWeightKg: 140 * 0.85) }, context: context
        )
        let strengthSession = try XCTUnwrap(peakWeekResult.sessions.first)
        let strengthProfile = try XCTUnwrap(SessionStressComposer.compose(strengthSession))
        XCTAssertEqual(strengthProfile.lowerBodyLoad, .high, "the real peak week (RIR 1)")

        // A real, non-empty FF triplet using .roundsForTime (not
        // CP.2R's own .maxLoad fixture) so FF.P1 targets are actually
        // assigned, with a heavy squatLoaded slot that CP.2's repair
        // will actually adjust.
        let heavyStimulus = Stimulus(
            targetDurationDomain: .medium, intensity: .high, loading: .heavy,
            movementFunctions: [.squatLoaded, .gymnasticsPull, .monostructural],
            movementModalityMix: [
                ModalityCount(modality: .weightlifting, count: 1),
                ModalityCount(modality: .gymnastics, count: 1),
                ModalityCount(modality: .metabolicConditioning, count: 1),
            ],
            skillDemand: .moderate, systemicDemand: .high, scoreType: .time
        )
        let ffConfiguration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 1, targetStimulus: heavyStimulus, format: realProductionFormat(),
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false
        )
        let ffDefinition = FunctionalFitnessProgramGenerator.generate(configuration: ffConfiguration, provenance: .constructed(reason: "test"), context: context)
        let ffInstance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(ffInstance)
        ffInstance.programDefinition = ffDefinition

        let candidates = [wallBall(), pullUp(), rowErg()]
        for candidate in candidates { context.insert(candidate) }

        let ffSessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: ffDefinition, instance: ffInstance, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
            candidateExercises: candidates, exposureHistory: [],
            protectedSiblingStressProfilesThisWeek: [strengthProfile],
            componentAdaptationObjectives: [.workCapacity, .aerobicCapacity, .power], context: context
        )
        let prescription = try XCTUnwrap(ffSessions.first?.orderedBlocks.first { $0.type == .functionalFitness }?.functionalFitnessPrescription)
        XCTAssertEqual(prescription.intendedStimulus?.loading, .heavy)
        XCTAssertEqual(prescription.stimulus.loading, .moderate, "CP.2's real repair fired")

        let movements = prescription.orderedMovements
        XCTAssertEqual(movements.first { $0.exercise?.canonicalName == "Wall Ball" }?.reps, 12, "the target is byte-identical regardless of CP.2's loading repair")
        XCTAssertEqual(movements.first { $0.exercise?.canonicalName == "Pull-up" }?.reps, 8)
        XCTAssertEqual(movements.first { $0.exercise?.canonicalName == "Row Erg" }?.distanceMeters, 200)
    }

    // MARK: Substitution — recomputation, precedence, and the Assault Bike edge case

    private func makeMovementWithSlot(
        modality: FunctionalModality, movementFunctions: [MovementFunction], exercise: Exercise,
        templateReps: Int? = nil, templateDistance: Double? = nil, movementReps: Int? = nil, movementDistance: Double? = nil
    ) -> FunctionalFitnessMovement {
        let slot = ExerciseSlot(name: "test slot", allowedMovementFunctions: movementFunctions, allowedModalities: [modality])
        context.insert(slot)
        let template = FunctionalFitnessMovementSlotTemplate(reps: templateReps, distanceMeters: templateDistance)
        context.insert(template)
        template.attachExerciseSlot(slot)
        let prescriptionTemplate = FunctionalFitnessPrescriptionTemplate(stimulus: realProductionStimulus(), format: realProductionFormat())
        context.insert(prescriptionTemplate)
        prescriptionTemplate.addMovementSlot(template)

        let movement = FunctionalFitnessMovement(exercise: exercise, reps: movementReps, distanceMeters: movementDistance)
        context.insert(movement)
        movement.sourceExerciseSlot = slot
        return movement
    }

    func testRowErgTwoHundredMetersSubstitutedToAssaultBikeClearsDistanceMeters() throws {
        let movement = makeMovementWithSlot(
            modality: .metabolicConditioning, movementFunctions: [.monostructural], exercise: rowErg(), movementDistance: 200
        )
        context.insert(assaultBike())
        try SubstituteFunctionalFitnessMovementUseCase.substituteThisSessionOnly(movement: movement, with: assaultBike())
        XCTAssertNil(movement.distanceMeters, "Assault Bike must never keep a stale distance target")
    }

    func testAssaultBikeWithNoTargetSubstitutedToRowErgReceivesTwoHundredMeters() throws {
        let movement = makeMovementWithSlot(
            modality: .metabolicConditioning, movementFunctions: [.monostructural], exercise: assaultBike(), movementDistance: nil
        )
        context.insert(rowErg())
        try SubstituteFunctionalFitnessMovementUseCase.substituteThisSessionOnly(movement: movement, with: rowErg())
        XCTAssertEqual(movement.distanceMeters, 200)
    }

    func testPullUpEightRepsSubstitutedToToesToBarStaysEightReps() throws {
        let movement = makeMovementWithSlot(
            modality: .gymnastics, movementFunctions: [.gymnasticsPull], exercise: pullUp(), movementReps: 8
        )
        context.insert(toesToBar())
        try SubstituteFunctionalFitnessMovementUseCase.substituteThisSessionOnly(movement: movement, with: toesToBar())
        XCTAssertEqual(movement.reps, 8)
    }

    func testCompatibleSquatLoadedSubstitutionRetainsTwelveReps() throws {
        let movement = makeMovementWithSlot(
            modality: .weightlifting, movementFunctions: [.squatLoaded], exercise: backSquat(), movementReps: 12
        )
        context.insert(wallBall())
        try SubstituteFunctionalFitnessMovementUseCase.substituteThisSessionOnly(movement: movement, with: wallBall())
        XCTAssertEqual(movement.reps, 12)
        context.insert(thruster())
        try SubstituteFunctionalFitnessMovementUseCase.substituteThisSessionOnly(movement: movement, with: thruster())
        XCTAssertEqual(movement.reps, 12)
    }

    func testSubstitutionNeverInventsCalories() throws {
        let movement = makeMovementWithSlot(
            modality: .metabolicConditioning, movementFunctions: [.monostructural], exercise: rowErg(), movementDistance: 200
        )
        XCTAssertNil(movement.calories)
        context.insert(assaultBike())
        try SubstituteFunctionalFitnessMovementUseCase.substituteThisSessionOnly(movement: movement, with: assaultBike())
        XCTAssertNil(movement.calories, "FF.P1 never populates calories, including through substitution recomputation")
    }

    func testSubstitutionNeverInventsNumericLoad() throws {
        let movement = makeMovementWithSlot(
            modality: .weightlifting, movementFunctions: [.squatLoaded], exercise: backSquat(), movementReps: 12
        )
        XCTAssertNil(movement.loadKilograms)
        context.insert(wallBall())
        try SubstituteFunctionalFitnessMovementUseCase.substituteThisSessionOnly(movement: movement, with: wallBall())
        XCTAssertNil(movement.loadKilograms, "numeric load remains genuinely unspecified, never invented as self-scaled")
    }

    func testExplicitAuthoredTargetSurvivesASubstitutionUnchanged() throws {
        // The TEMPLATE itself carries an explicit, non-nil reps value —
        // the reliable signal (per FF.P1's own locked precedence) that
        // this is authored, not FF.P1-generated, and must never be
        // recomputed even across a substitution.
        let movement = makeMovementWithSlot(
            modality: .metabolicConditioning, movementFunctions: [.monostructural], exercise: rowErg(),
            templateDistance: 500, movementDistance: 500
        )
        context.insert(assaultBike())
        try SubstituteFunctionalFitnessMovementUseCase.substituteThisSessionOnly(movement: movement, with: assaultBike())
        XCTAssertEqual(movement.distanceMeters, 500, "an explicitly authored target must survive a substitution unchanged, never recomputed to nil")
    }

    func testReadinessDrivenSubstitutionUsesTheSameRecomputationPath() throws {
        // ReadinessAdaptationDecisionUseCase's real .exerciseSubstituted
        // case calls the exact same SubstituteFunctionalFitnessMovementUseCase
        // .substituteThisSessionOnly this test exercises directly above —
        // confirmed by direct read (ReadinessAdaptationDecisionUseCase.swift),
        // so there is no separate recomputation path to test independently.
        let movement = makeMovementWithSlot(
            modality: .metabolicConditioning, movementFunctions: [.monostructural], exercise: rowErg(), movementDistance: 200
        )
        context.insert(assaultBike())
        try SubstituteFunctionalFitnessMovementUseCase.substituteThisSessionOnly(movement: movement, with: assaultBike(), reason: .readinessAdaptation)
        XCTAssertNil(movement.distanceMeters)
        XCTAssertTrue(movement.substitutionUsed)
    }

    // MARK: Live UI — shared formatting

    func testLiveExecutionHeaderFormattingRendersConcreteTargets() {
        let squat = FunctionalFitnessMovement(exercise: backSquat(), reps: 12)
        let pull = FunctionalFitnessMovement(exercise: pullUp(), reps: 8)
        let row = FunctionalFitnessMovement(exercise: rowErg(), distanceMeters: 200)
        XCTAssertEqual(BlockPresentation.prescribedMovementLine(squat), "Back Squat \u{b7} 12 reps")
        XCTAssertEqual(BlockPresentation.prescribedMovementLine(pull), "Pull-up \u{b7} 8 reps")
        XCTAssertEqual(BlockPresentation.prescribedMovementLine(row), "Row Erg \u{b7} 200 m")
    }

    func testAssaultBikeHeaderFormattingContainsNoInventedTarget() {
        let bike = FunctionalFitnessMovement(exercise: assaultBike())
        XCTAssertEqual(BlockPresentation.prescribedMovementLine(bike), "Assault Bike", "no fabricated target for the one real, deliberately-untargeted candidate")
    }
}
