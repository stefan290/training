import XCTest
import SwiftData
@testable import TrainingOS

/// Stage TE.1: proves the Training Environment Foundation — the tri-state
/// compatibility rule, the fail-fast "unknown environment" guard (never
/// silently treated as compatible), real materialization success/failure
/// under a restrictive environment across every real workout type
/// (Exercise-based and ActivityType-based), the main-lift/allow-list
/// conflict case, and the model's default/migration invariants.
@MainActor
final class TrainingEnvironmentTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    // MARK: - A. Model round-trip / default invariant

    func testNewUserProfileHasNoDefaultEnvironment() {
        let profile = UserProfile()
        XCTAssertNil(profile.defaultTrainingEnvironment, "an unconfigured profile must never silently have a default environment")
        XCTAssertTrue(profile.trainingEnvironments.isEmpty)
    }

    func testDeletingTheDefaultEnvironmentClearsThePointerRatherThanFallingBackSilently() throws {
        let profile = UserProfile()
        context.insert(profile)
        let home = TrainingEnvironment(name: "Home", availableEquipment: [.dumbbells])
        let gym = TrainingEnvironment(name: "Gym", availableEquipment: EquipmentRequirement.allCases)
        context.insert(home)
        context.insert(gym)
        profile.trainingEnvironments = [home, gym]
        profile.defaultTrainingEnvironment = home
        try context.save()

        context.delete(home)
        try context.save()

        XCTAssertNil(profile.defaultTrainingEnvironment, "deleting the default must clear the pointer, never silently promote gym to default")
        XCTAssertEqual(profile.trainingEnvironments.map(\.name), ["Gym"])
    }

    func testDeletingUserProfileCascadesToItsOwnTrainingEnvironments() throws {
        let user = User(displayName: "TE.1 Cascade Test")
        let profile = UserProfile()
        context.insert(user)
        context.insert(profile)
        user.attachProfile(profile)
        let home = TrainingEnvironment(name: "Home", availableEquipment: [.dumbbells])
        context.insert(home)
        profile.trainingEnvironments = [home]
        try context.save()

        context.delete(profile)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<TrainingEnvironment>())
        XCTAssertTrue(remaining.isEmpty, "TrainingEnvironment is owned by UserProfile (.cascade) — it must not survive the profile's deletion")
    }

    func testSessionMaterializedInEnvironmentIsReferenceOnlyAndNullifiesOnDelete() throws {
        let environment = TrainingEnvironment(name: "Gym", availableEquipment: EquipmentRequirement.allCases)
        context.insert(environment)
        let day = Day(ownerUserID: UUID(), date: Date())
        context.insert(day)
        let session = Session(name: "Test Session", modality: .conditioning)
        session.materializedInEnvironment = environment
        context.insert(session)
        day.addSession(session)

        // TE.1 closure: the delete/nullify path must leave every OTHER
        // real fact about this Session alone too — not just its own name.
        // A resolved Exercise (strength/hypertrophy family) and an
        // ActivityType-bearing prescription (endurance family) together
        // cover both of this app's two exercise-identity shapes
        // (CLAUDE.md rule 6 canonical Exercise vs. rule 19's endurance
        // `ActivityType`).
        let resolvedExercise = Exercise(canonicalName: "TE.1 Delete Regression Squat", modality: .hypertrophy, equipment: "barbell", movementPattern: "squat")
        context.insert(resolvedExercise)
        let strengthBlock = WorkoutBlock(type: .strength)
        context.insert(strengthBlock)
        session.addBlock(strengthBlock)
        let prescription = ExercisePrescription(exercise: resolvedExercise)
        context.insert(prescription)
        strengthBlock.addPrescription(prescription)

        let enduranceBlock = WorkoutBlock(type: .steadyState)
        context.insert(enduranceBlock)
        session.addBlock(enduranceBlock)
        let steadyStatePrescription = SteadyStatePrescription(activityType: .rowing, durationSeconds: 1800)
        context.insert(steadyStatePrescription)
        enduranceBlock.attachSteadyStatePrescription(steadyStatePrescription)

        try context.save()

        context.delete(environment)
        try context.save()

        XCTAssertNil(session.materializedInEnvironment, "deleting the environment must nullify the reference, never delete or reinterpret the Session")
        XCTAssertEqual(session.name, "Test Session", "the Session itself — genuine historical truth — is completely unaffected")
        XCTAssertNotNil(session.orderedBlocks.first { $0.id == strengthBlock.id }, "no block is removed by an environment deletion")
        XCTAssertEqual(prescription.exercise?.id, resolvedExercise.id, "a resolved Exercise reference must survive an unrelated environment's deletion untouched")
        XCTAssertEqual(enduranceBlock.steadyStatePrescription?.activityType, .rowing, "ActivityType/prescription data must survive an unrelated environment's deletion untouched")
        XCTAssertEqual(enduranceBlock.steadyStatePrescription?.durationSeconds, 1800)
    }

    // MARK: - B. Pure rule tests

    func testEmptyRequiredIsAlwaysCompatibleOnceARealEnvironmentExists() {
        let austere = TrainingEnvironment(name: "Nothing", availableEquipment: [])
        XCTAssertEqual(TrainingEnvironmentCompatibilityRule.evaluate(required: [], environment: austere), .compatible)
    }

    func testAustereEnvironmentIsIncompatibleWithAnyRealRequirement() {
        let austere = TrainingEnvironment(name: "Nothing", availableEquipment: [])
        XCTAssertEqual(TrainingEnvironmentCompatibilityRule.evaluate(required: [.barbell], environment: austere), .incompatible(missing: [.barbell]))
    }

    func testNilEnvironmentIsAlwaysUnknownNeverCompatibleEvenForAnEmptyRequirement() {
        XCTAssertEqual(TrainingEnvironmentCompatibilityRule.evaluate(required: [], environment: nil), .environmentUnknown,
                        "nil must never be treated as compatible, even vacuously — this is the locked Round-2 amendment's core invariant")
        XCTAssertEqual(TrainingEnvironmentCompatibilityRule.evaluate(required: [.barbell], environment: nil), .environmentUnknown)
    }

    func testPartialOverlapReportsExactlyTheMissingSubset() {
        let environment = TrainingEnvironment(name: "Partial", availableEquipment: [.barbell])
        XCTAssertEqual(
            TrainingEnvironmentCompatibilityRule.evaluate(required: [.barbell, .rack, .bench], environment: environment),
            .incompatible(missing: [.rack, .bench])
        )
    }

    func testDuplicateRequirementsAreAbsorbedByTheUnderlyingSet() {
        let environment = TrainingEnvironment(name: "Barbell Only", availableEquipment: [.barbell])
        XCTAssertEqual(TrainingEnvironmentCompatibilityRule.evaluate(required: [.barbell, .barbell, .barbell], environment: environment), .compatible)
    }

    func testEveryRealEquipmentRequirementCaseIsHandledExhaustively() {
        // A future EquipmentRequirement case fails closed automatically —
        // this proves every CURRENT case round-trips through the rule
        // without special-casing.
        let full = TrainingEnvironment(name: "Full", availableEquipment: EquipmentRequirement.allCases)
        for equipment in EquipmentRequirement.allCases {
            XCTAssertEqual(TrainingEnvironmentCompatibilityRule.evaluate(required: [equipment], environment: full), .compatible, "\(equipment) must be satisfied by a full environment")
        }
    }

    // MARK: - C. Catalog metadata-coverage / correctness

    func testEveryRealCatalogExerciseHasAnExplicitRequiredEquipmentValue() throws {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        // A representative cross-section, one per real functional
        // modality/family, each checked against its real, expected
        // equipment — proving the catalog fix (Easy Run/Track Interval
        // Run) landed and existing values are still correct.
        XCTAssertEqual(catalog.easyRun.requiredEquipment, [], "Easy Run must be confirmed empty, not merely omitted")
        XCTAssertEqual(catalog.wallBall.requiredEquipment, [.medicineBall])
        XCTAssertEqual(catalog.pullUp.requiredEquipment, [.pullUpBar])
        XCTAssertEqual(catalog.backSquat.requiredEquipment, [.barbell, .rack])
        XCTAssertEqual(catalog.bike.requiredEquipment, [.bike])
        XCTAssertEqual(catalog.row.requiredEquipment, [.rower])
    }

    // MARK: - G. FF materialization with a real restrictive environment

    /// Hand-built (not generator-produced) — a single real
    /// `gymnasticsPull` movement slot, matching §N's own worked example
    /// exactly (real production candidates for this slot are precisely
    /// {Pull-up, Toes-to-Bar}), so these tests are deterministic and
    /// independent of `FunctionalFitnessProgramGenerator`'s own slot
    /// composition for a given format/stimulus.
    private func makeFFDefinition() -> (ProgramDefinition, ProgramInstance) {
        let definition = ProgramDefinition(name: "TE.1 FF Test", lengthWeeks: 1, programmingSystem: .functionalFitness, generatorVersion: 1, provenance: .constructed(reason: "test"))
        context.insert(definition)
        let week = TrainingWeek(isDeload: false)
        context.insert(week)
        definition.addWeek(week)
        let templateSession = TemplateSession(name: "Metcon Day", role: .functionalFitness)
        context.insert(templateSession)
        definition.addTemplateSession(templateSession)
        let block = WorkoutBlockTemplate(type: .functionalFitness)
        context.insert(block)
        templateSession.addBlockTemplate(block)
        let ffTemplate = FunctionalFitnessPrescriptionTemplate(stimulus: heavySquatMaterializableStimulus(), format: .maxLoad)
        context.insert(ffTemplate)
        block.attachFunctionalFitnessPrescriptionTemplate(ffTemplate)
        let movementSlot = FunctionalFitnessMovementSlotTemplate()
        context.insert(movementSlot)
        ffTemplate.addMovementSlot(movementSlot)
        let exerciseSlot = ExerciseSlot(name: "Gymnastics Pull", allowedMovementFunctions: [.gymnasticsPull], allowedModalities: [.gymnastics])
        context.insert(exerciseSlot)
        movementSlot.attachExerciseSlot(exerciseSlot)

        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition
        return (definition, instance)
    }

    private func heavySquatMaterializableStimulus() -> Stimulus {
        Stimulus(
            targetDurationDomain: .medium, intensity: .high, loading: .heavy,
            movementFunctions: [.gymnasticsPull], movementModalityMix: [ModalityCount(modality: .gymnastics, count: 1)],
            skillDemand: .moderate, systemicDemand: .high, scoreType: .load
        )
    }

    func testFFMaterializationThrowsTrainingEnvironmentRequiredWhenEnvironmentIsNilAndSlotsExist() throws {
        let (definition, instance) = makeFFDefinition()
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        XCTAssertThrowsError(try FunctionalFitnessMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0), ownerUserID: instance.ownerUserID,
            candidateExercises: [catalog.backSquat, catalog.wallBall, catalog.pullUp, catalog.toesToBar, catalog.row, catalog.bike],
            exposureHistory: [], environment: nil, context: context
        )) { error in
            XCTAssertEqual(error as? FunctionalFitnessMaterializationError, .trainingEnvironmentRequired)
        }
    }

    func testFFMaterializationSucceedsWhenARealEnvironmentSatisfiesEveryMovementSlot() throws {
        let (definition, instance) = makeFFDefinition()
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let fullGym = TrainingEnvironment(name: "Full Gym", availableEquipment: EquipmentRequirement.allCases)
        context.insert(fullGym)
        let sessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0), ownerUserID: instance.ownerUserID,
            candidateExercises: [catalog.backSquat, catalog.wallBall, catalog.pullUp, catalog.toesToBar, catalog.row, catalog.bike],
            exposureHistory: [], environment: fullGym, context: context
        )
        XCTAssertFalse(sessions.isEmpty)
        XCTAssertEqual(sessions.first?.materializedInEnvironment?.id, fullGym.id, "diagnostic reference metadata must record the environment actually used")
    }

    func testFFGymnasticsPullSlotThrowsEnvironmentIncompatibleWhenNoRealCandidateHasAPullUpBar() throws {
        // Real, production candidates for the gymnasticsPull slot are
        // exactly {Pull-up, Toes-to-Bar}, both requiring `.pullUpBar`
        // (§N's own worked example) — an environment lacking it must
        // empty the whole pool for this slot.
        let (definition, instance) = makeFFDefinition()
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let noBar = TrainingEnvironment(name: "No Pull-up Bar", availableEquipment: [.barbell, .rack, .medicineBall, .bike, .rower])
        context.insert(noBar)
        XCTAssertThrowsError(try FunctionalFitnessMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0), ownerUserID: instance.ownerUserID,
            candidateExercises: [catalog.backSquat, catalog.wallBall, catalog.pullUp, catalog.toesToBar, catalog.row, catalog.bike],
            exposureHistory: [], environment: noBar, context: context
        )) { error in
            guard case .stimulusValidationFailed = error as? FunctionalFitnessMaterializationError else {
                return XCTFail("expected the general 'no candidate resolved for this dimension-constrained slot' path (Stage E), got \(error)")
            }
        }
    }

    // MARK: - K/L. Main-lift (allowedExercises) narrowed-slot conflict

    func testNarrowedAllowedExercisesSlotProducesATypedEnvironmentConflictNeverASilentSubstitution() throws {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let definition = ProgramDefinition(name: "TE.1 Main Lift Test", lengthWeeks: 1, programmingSystem: .hypertrophy, generatorVersion: 1, provenance: .constructed(reason: "test"))
        context.insert(definition)
        let week = TrainingWeek(isDeload: false)
        context.insert(week)
        definition.addWeek(week)
        let templateSession = TemplateSession(name: "Squat Day", role: .strength)
        context.insert(templateSession)
        definition.addTemplateSession(templateSession)
        let block = WorkoutBlockTemplate(type: .strength)
        context.insert(block)
        templateSession.addBlockTemplate(block)
        let slot = ExerciseSlot(name: "Competition Squat", allowedExercises: [catalog.backSquat])
        context.insert(slot)
        let prescriptionTemplate = PrescriptionTemplate()
        context.insert(prescriptionTemplate)
        block.addPrescriptionTemplate(prescriptionTemplate)
        prescriptionTemplate.attachExerciseSlot(slot)

        // Back Squat requires [.barbell, .rack] — an environment with a
        // barbell but no rack cannot satisfy this narrowed slot, and
        // there is no other allowed exercise to fall back to.
        let noRack = TrainingEnvironment(name: "No Rack", availableEquipment: [.barbell])
        context.insert(noRack)

        XCTAssertThrowsError(try ResolveProgramInstanceExerciseSlotsUseCase.resolve(
            definition: definition, candidateExercises: [catalog.backSquat], environment: noRack
        )) { error in
            guard case .environmentIncompatible(let slotName, let missing) = error as? ExerciseSlotResolutionError else {
                return XCTFail("expected a typed environmentIncompatible conflict, got \(error)")
            }
            XCTAssertEqual(slotName, "Competition Squat")
            XCTAssertEqual(Set(missing), [.rack])
        }
        XCTAssertNil(slot.resolvedExercise, "must never silently substitute an unrelated exercise into a narrowed main-lift slot")
    }

    // MARK: - M. Unknown-environment fail-fast, ActivityType-based

    func testSteadyStateMaterializerThrowsTrainingEnvironmentRequiredBeforeAnyResolution() throws {
        let configuration = SteadyStateProgramConfiguration(activityType: .cycling, allowedActivityTypes: [.cycling], daysPerWeek: 1, lengthWeeks: 1, progressionDimension: .none)
        let definition = SteadyStateProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        XCTAssertThrowsError(try SteadyStateMaterializer.materializeAllWeeks(
            definition: definition, instance: instance, startDate: Date(timeIntervalSince1970: 0), ownerUserID: instance.ownerUserID,
            environment: nil, context: context
        )) { error in
            XCTAssertEqual(error as? SteadyStateMaterializationError, .trainingEnvironmentRequired)
        }
        XCTAssertTrue(instance.sessions.isEmpty, "no partial materialization on a fail-fast throw")
    }

    func testCyclingRequiresABikeAndThrowsEnvironmentIncompatibleWithoutOne() throws {
        let configuration = SteadyStateProgramConfiguration(activityType: .cycling, allowedActivityTypes: [.cycling], daysPerWeek: 1, lengthWeeks: 1, progressionDimension: .none)
        let definition = SteadyStateProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        let noBike = TrainingEnvironment(name: "No Bike", availableEquipment: [.rower])
        context.insert(noBike)
        XCTAssertThrowsError(try SteadyStateMaterializer.materializeAllWeeks(
            definition: definition, instance: instance, startDate: Date(timeIntervalSince1970: 0), ownerUserID: instance.ownerUserID,
            environment: noBike, context: context
        )) { error in
            guard case .environmentIncompatible(let activityType, let missing) = error as? SteadyStateMaterializationError else {
                return XCTFail("expected environmentIncompatible, got \(error)")
            }
            XCTAssertEqual(activityType, .cycling)
            XCTAssertEqual(missing, [.bike])
        }
    }

    func testRunningNeverRequiresAnyModeledEquipmentEvenInAnAustereEnvironment() throws {
        let configuration = SteadyStateProgramConfiguration(activityType: .running, allowedActivityTypes: [.running], daysPerWeek: 1, lengthWeeks: 1, progressionDimension: .none)
        let definition = SteadyStateProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        let austere = TrainingEnvironment(name: "Nothing", availableEquipment: [])
        context.insert(austere)
        let sessions = try SteadyStateMaterializer.materializeAllWeeks(
            definition: definition, instance: instance, startDate: Date(timeIntervalSince1970: 0), ownerUserID: instance.ownerUserID,
            environment: austere, context: context
        )
        XCTAssertFalse(sessions.isEmpty, "running must never be blocked by any modeled equipment gap")
    }

    // MARK: - P2. Every real ActivityType's exact derived requirement, table-driven

    func testEveryActivityTypesRequiredEquipmentMatchesTheLockedMapping() {
        let expected: [ActivityType: [EquipmentRequirement]] = [
            .running: [],
            .cycling: [.bike],
            .rowing: [.rower],
            .skiErg: [.skiErg],
            .other: [],
        ]
        for activityType in ActivityType.allCases {
            XCTAssertEqual(activityType.requiredEquipment, expected[activityType], "\(activityType) must match the locked TE.1 mapping exactly")
        }
    }

    // MARK: - H. Substitution engine environment-awareness (Exercise-based)

    func testSubstitutionValidatorRejectsAnEnvironmentIncompatibleCandidateEvenWhenEveryOtherDimensionMatches() {
        let squatSlot = ExerciseSlot(name: "Squat Pattern", allowedMovementFunctions: [.squatLoaded])
        let backSquat = Exercise(canonicalName: "TE.1 Back Squat", modality: .strength, equipment: "barbell", movementPattern: "squat", movementFunctions: [.squatLoaded], requiredEquipment: [.barbell, .rack])
        let noRack = TrainingEnvironment(name: "No Rack", availableEquipment: [.barbell])
        let full = TrainingEnvironment(name: "Full", availableEquipment: EquipmentRequirement.allCases)
        XCTAssertTrue(SubstitutionValidator.isValid(candidate: backSquat, for: squatSlot, environment: full))
        XCTAssertFalse(SubstitutionValidator.isValid(candidate: backSquat, for: squatSlot, environment: noRack))
        XCTAssertFalse(SubstitutionValidator.isValid(candidate: backSquat, for: squatSlot, environment: nil), "unknown environment must never be treated as compatible")
    }

    func testSubstituteExerciseGoingForwardRejectsAnEnvironmentIncompatibleCandidate() throws {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let slot = ExerciseSlot(name: "Squat Pattern", allowedMovementFunctions: [.squatLoaded])
        context.insert(slot)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        let noRack = TrainingEnvironment(name: "No Rack", availableEquipment: [.barbell])
        context.insert(noRack)

        XCTAssertThrowsError(try SubstituteExerciseUseCase.substituteGoingForward(
            instance: instance, slot: slot, with: catalog.backSquat, environment: noRack, context: context
        )) { error in
            XCTAssertEqual(error as? SubstitutionError, .invalidForSlot)
        }
    }

    // MARK: - Absurdity checks

    func testAFutureEquipmentRequirementCaseWouldFailClosedNotOpen() {
        // Simulated by an environment that has everything CURRENTLY
        // known but is asked about a requirement set that (by
        // construction) it cannot satisfy — proving the subtraction-based
        // rule has no implicit "unlisted means fine" branch.
        let full = TrainingEnvironment(name: "Full", availableEquipment: EquipmentRequirement.allCases)
        let missingEverything = TrainingEnvironment(name: "Empty", availableEquipment: [])
        XCTAssertEqual(TrainingEnvironmentCompatibilityRule.evaluate(required: EquipmentRequirement.allCases, environment: full), .compatible)
        if case .incompatible(let missing) = TrainingEnvironmentCompatibilityRule.evaluate(required: EquipmentRequirement.allCases, environment: missingEverything) {
            XCTAssertEqual(missing.count, EquipmentRequirement.allCases.count)
        } else {
            XCTFail("an empty environment must be incompatible with every real requirement, never silently compatible")
        }
    }
}
