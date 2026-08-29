import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 10R.1C: the concrete test matrix requested alongside the
/// approved design — proves the calibration domain model, the
/// required-calibration query, and the `StartPhaseUseCase` gate, all
/// generically across every `.rmBased` family (never Hypertrophy-only).
@MainActor
final class SourceRMCalibrationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()
    let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func makeInstance(definition: ProgramDefinition, ownerUserID: UUID? = nil) -> ProgramInstance {
        let instance = ProgramInstance(ownerUserID: ownerUserID ?? self.ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        return instance
    }

    private func hypertrophyDefinition() throws -> ProgramDefinition {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 3, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: context
        )
        _ = catalog
        return definition
    }

    /// A deterministic, genuinely-required exercise — NOT
    /// `context.fetch(FetchDescriptor<Exercise>()).first`, which returns
    /// an unspecified, unsorted first match across the WHOLE catalog and
    /// is not guaranteed to be one any `.rmBased` slot actually resolved
    /// to (a real flake this pass found: such an exercise may never
    /// appear in `RequiredSourceCalibrationsUseCase.stillRequired` at
    /// all, making an "is this still required" assertion pass or fail by
    /// accident of fetch order).
    private func firstResolvedExercise(in definition: ProgramDefinition) throws -> Exercise {
        try XCTUnwrap(definition.orderedTemplateSessions.first?.orderedBlockTemplates.first?.orderedPrescriptionTemplates.first?.exerciseSlot?.resolvedExercise)
    }

    // MARK: A — literal 10RM reaches the engine unconverted

    func testEnteredTenRepMaxReachesTheEngineLiterallyBeforeRounding() throws {
        let definition = try hypertrophyDefinition()
        let instance = makeInstance(definition: definition)
        let session = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let template = try XCTUnwrap(session.orderedBlockTemplates.first?.orderedPrescriptionTemplates.first { $0.exerciseSlot?.name == "Horizontal Push" })
        let exercise = try XCTUnwrap(template.exerciseSlot?.resolvedExercise)

        RecordSourceRMCalibrationUseCase.record(exercise: exercise, rmType: .rm10, kilograms: 80, for: instance, modelContext: context)
        XCTAssertEqual(instance.sourceRMCalibration(for: exercise, rmType: .rm10)?.kilograms, 80, "the literal entered value, never converted")

        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: instance.sourceRMCalibration(for: exercise, rmType: .rm10)?.kilograms) },
            context: context
        )
        let prescription = try XCTUnwrap(result.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).first { $0.sourcePrescriptionTemplate?.id == template.id })
        XCTAssertEqual(prescription.orderedSetPrescriptions.first?.targetWeight ?? -1, equipment.resolve(IdealLoad(kilograms: 80 * 0.85)), accuracy: 0.0001, "80 * 0.85 (Family A's source week-one factor), rounded through the equipment increment — never a converted/estimated figure")
    }

    // MARK: B — independent exercise calibration

    func testDifferentExercisesCalibrateIndependently() throws {
        let definition = try hypertrophyDefinition()
        let instance = makeInstance(definition: definition)
        let bench = try XCTUnwrap(definition.orderedTemplateSessions.first?.orderedBlockTemplates.first?.orderedPrescriptionTemplates.first { $0.exerciseSlot?.name == "Horizontal Push" }?.exerciseSlot?.resolvedExercise)
        let row = try XCTUnwrap(definition.orderedTemplateSessions.first?.orderedBlockTemplates.first?.orderedPrescriptionTemplates.first { $0.exerciseSlot?.name == "Horizontal Pull" }?.exerciseSlot?.resolvedExercise)

        RecordSourceRMCalibrationUseCase.record(exercise: bench, rmType: .rm10, kilograms: 80, for: instance, modelContext: context)
        RecordSourceRMCalibrationUseCase.record(exercise: row, rmType: .rm10, kilograms: 60, for: instance, modelContext: context)

        XCTAssertEqual(instance.sourceRMCalibration(for: bench, rmType: .rm10)?.kilograms, 80)
        XCTAssertEqual(instance.sourceRMCalibration(for: row, rmType: .rm10)?.kilograms, 60)
    }

    // MARK: C — RMType separation (never cross-satisfy)

    func testSameExerciseDifferentRMTypesNeverCrossSatisfy() throws {
        let definition = try hypertrophyDefinition()
        let instance = makeInstance(definition: definition)
        let catalog = try firstResolvedExercise(in: definition)

        RecordSourceRMCalibrationUseCase.record(exercise: catalog, rmType: .rm5, kilograms: 100, for: instance, modelContext: context)
        XCTAssertNil(instance.sourceRMCalibration(for: catalog, rmType: .rm8), "an rm5 entry must never satisfy an rm8 requirement for the identical exercise")
        XCTAssertNil(instance.sourceRMCalibration(for: catalog, rmType: .rm10))

        RecordSourceRMCalibrationUseCase.record(exercise: catalog, rmType: .rm8, kilograms: 90, for: instance, modelContext: context)
        XCTAssertEqual(instance.sourceRMCalibration(for: catalog, rmType: .rm5)?.kilograms, 100, "adding rm8 must not disturb the existing, distinct rm5 entry")
        XCTAssertEqual(instance.sourceRMCalibration(for: catalog, rmType: .rm8)?.kilograms, 90)
    }

    // MARK: D — ProgramInstance separation

    func testOneInstancesCalibrationNeverSatisfiesAnother() throws {
        let definition = try hypertrophyDefinition()
        let instanceA = makeInstance(definition: definition)
        let instanceB = makeInstance(definition: definition)
        let exercise = try firstResolvedExercise(in: definition)

        RecordSourceRMCalibrationUseCase.record(exercise: exercise, rmType: .rm10, kilograms: 80, for: instanceA, modelContext: context)
        XCTAssertNotNil(instanceA.sourceRMCalibration(for: exercise, rmType: .rm10))
        XCTAssertNil(instanceB.sourceRMCalibration(for: exercise, rmType: .rm10), "a different ProgramInstance must never inherit another instance's calibration")
    }

    // MARK: E — no mesocycle carry-over

    func testANewInstanceNeverAutomaticallyCarriesOverThePriorInstancesCalibration() throws {
        let definition = try hypertrophyDefinition()
        let firstInstance = makeInstance(definition: definition)
        let exercise = try firstResolvedExercise(in: definition)
        RecordSourceRMCalibrationUseCase.record(exercise: exercise, rmType: .rm10, kilograms: 80, for: firstInstance, modelContext: context)

        let secondInstance = makeInstance(definition: definition)
        let stillRequired = RequiredSourceCalibrationsUseCase.stillRequired(for: definition, instance: secondInstance)
        XCTAssertTrue(stillRequired.contains { $0.exercise.id == exercise.id && $0.rmType == .rm10 }, "the new mesocycle/instance must require fresh calibration, never silently inherit the previous one")
    }

    // MARK: F — previous value is reference-only, never satisfies current

    func testPreviousValueIsReadableAsReferenceButNeverSatisfiesTheCurrentInstance() throws {
        let definition = try hypertrophyDefinition()
        let firstInstance = makeInstance(definition: definition)
        let exercise = try firstResolvedExercise(in: definition)
        RecordSourceRMCalibrationUseCase.record(exercise: exercise, rmType: .rm10, kilograms: 80, for: firstInstance, modelContext: context)

        let secondInstance = makeInstance(definition: definition)
        let previous = PreviousSourceRMCalibrationUseCase.mostRecentPriorValue(
            for: exercise, rmType: .rm10, excluding: secondInstance, ownerUserID: ownerUserID, modelContext: context
        )
        XCTAssertEqual(previous?.kilograms, 80, "the prior instance's value must be readable as reference")
        XCTAssertNil(secondInstance.sourceRMCalibration(for: exercise, rmType: .rm10), "reference visibility must never itself satisfy the current instance's requirement")
    }

    // MARK: G/H/Q — real StartPhaseUseCase gating

    private func makeAcceptedPlan(asOf: Date) throws -> (goal: Goal, phase: TrainingPhase) {
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .muscleGain, targetDate: Calendar.current.date(byAdding: .year, value: 1, to: asOf), createdAt: asOf)
        context.insert(goal)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: asOf)
        let phase = try XCTUnwrap(plan.orderedPhases.first)
        return (goal, phase)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar.current.date(from: components)!
    }

    private func availability() -> UserAvailability {
        UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1)
    }

    func testMissingCalibrationDefersRatherThanFabricatingAndCalibrationCompletionMaterializesExactlyOnce() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let mixCandidates = LongTermPlanner.proposeTrainingMix(phase: fixture.phase, goal: fixture.goal)
        let recommended = try XCTUnwrap(mixCandidates.first { $0.roles.contains(.recommended) })
        let materializationContext = TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: [
            catalog.backSquat, catalog.benchPress, catalog.inclineDumbbellPress, catalog.romanianDeadlift, catalog.legPress,
        ])

        // G — missing calibration defers, never fabricates.
        let startResult = try StartPhaseUseCase.start(
            phase: fixture.phase, mix: recommended.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(), materializationContext: materializationContext, context: context
        )
        let instance = try XCTUnwrap(fixture.phase.primaryInstance)
        XCTAssertTrue(instance.sessions.isEmpty)
        XCTAssertFalse(startResult.componentsAwaitingCalibration.isEmpty)

        // H — completing calibration materializes exactly once.
        try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: fixture.phase, performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext, asOf: asOf, context: context
        )
        XCTAssertFalse(instance.sessions.isEmpty, "materialization must succeed exactly once calibration is complete")
        let sessionCountAfterFirstMaterialization = instance.sessions.count

        // Re-verifying with calibration already satisfied must not
        // duplicate materialization (defensive re-check inside
        // `materializeOnceCalibrationComplete` throws instead).
        guard let component = instance.trainingMixComponents.first, let mix = component.trainingMix else {
            return XCTFail("expected a wired component/mix")
        }
        XCTAssertThrowsError(try StartPhaseUseCase.materializeOnceCalibrationComplete(
            component: component, instance: instance, phase: fixture.phase, mix: mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(), materializationContext: materializationContext, context: context
        ))
        XCTAssertEqual(instance.sessions.count, sessionCountAfterFirstMaterialization, "a defensive re-call must never re-materialize or duplicate sessions")
    }

    // MARK: Q — non-.rmBased programs are never gated

    func testNonRMBasedProgramsAreNeverGated() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let mixCandidates = LongTermPlanner.proposeTrainingMix(phase: fixture.phase, goal: fixture.goal)
        // Any accepted mix's non-strength component (Steady State/Functional
        // Fitness) must materialize immediately regardless of Strength's
        // own calibration state — the gate is `.rmBased`-scoped, never
        // system-wide.
        let recommended = try XCTUnwrap(mixCandidates.first { $0.roles.contains(.recommended) })
        let materializationContext = TacticalMaterializationContext(
            equipmentProfile: equipment, strengthCandidateExercises: [catalog.backSquat, catalog.benchPress],
            functionalFitnessCandidateExercises: [catalog.wallBall, catalog.pullUp, catalog.bike]
        )
        try StartPhaseUseCase.start(
            phase: fixture.phase, mix: recommended.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(), materializationContext: materializationContext, context: context
        )
        let nonStrengthInstances = fixture.phase.programInstances.filter { $0.programDefinition?.programmingSystem != .hypertrophy && $0.programDefinition?.programmingSystem != .powerlifting }
        for instance in nonStrengthInstances {
            XCTAssertFalse(instance.sessions.isEmpty, "\(instance.programDefinition?.programmingSystem?.rawValue ?? "?") must materialize immediately — it is never `.rmBased` and therefore never gated")
        }
    }

    // MARK: I/J — exercise change / substitution never transfers calibration

    func testChangingTheResolvedExerciseDuringSetupUpdatesTheRequirementRatherThanKeepingTheOldOne() throws {
        let definition = try hypertrophyDefinition()
        let instance = makeInstance(definition: definition)
        let slot = try XCTUnwrap(definition.orderedTemplateSessions.first?.orderedBlockTemplates.first?.orderedPrescriptionTemplates.first { $0.exerciseSlot?.name == "Quads" }?.exerciseSlot)
        let originalExercise = try XCTUnwrap(slot.resolvedExercise)
        RecordSourceRMCalibrationUseCase.record(exercise: originalExercise, rmType: .rm10, kilograms: 100, for: instance, modelContext: context)
        XCTAssertTrue(RequiredSourceCalibrationsUseCase.stillRequired(for: definition, instance: instance).filter { $0.exercise.id == originalExercise.id }.isEmpty, "sanity: the original exercise is satisfied")

        // Changing the setup-time selection to a different, uncalibrated exercise.
        let replacement = Exercise(canonicalName: "Zzz Test Leg Press Replacement", modality: .hypertrophy, equipment: "machine", movementPattern: "squat", primaryTargets: [.quadriceps], movementFunctions: [.squatLoaded])
        context.insert(replacement)
        try SubstituteExerciseUseCase.substituteGoingForward(instance: instance, slot: slot, with: replacement, context: context)

        let stillRequired = RequiredSourceCalibrationsUseCase.stillRequired(for: definition, instance: instance)
        XCTAssertTrue(stillRequired.contains { $0.exercise.id == replacement.id && $0.rmType == .rm10 }, "the replacement exercise must now require its own calibration")
        XCTAssertNotNil(instance.sourceRMCalibration(for: originalExercise, rmType: .rm10), "the original exercise's calibration is untouched, simply no longer relevant to this slot")
        XCTAssertNil(instance.sourceRMCalibration(for: replacement, rmType: .rm10), "the replacement must never inherit the original's RM")
    }

    // MARK: K — ordinary SetResult never creates calibration

    func testLoggingAnOrdinarySetResultNeverCreatesASourceRMCalibration() throws {
        let definition = try hypertrophyDefinition()
        let instance = makeInstance(definition: definition)
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        let template = try XCTUnwrap(definition.orderedTemplateSessions.first?.orderedBlockTemplates.first?.orderedPrescriptionTemplates.first)
        let exercise = try XCTUnwrap(template.exerciseSlot?.resolvedExercise)
        let prescription = ExercisePrescription(exercise: exercise)
        context.insert(prescription)
        let setPrescription = SetPrescription(repRangeLow: 3, repRangeHigh: 3, targetWeight: 60, targetRir: 0)
        context.insert(setPrescription)
        prescription.addSetPrescription(setPrescription)

        RecordSetResultUseCase.recordSet(
            setIndex: 0, weight: 60, reps: 8, targetRir: 0, actualRir: 0, prBand: nil, scoringDirection: .higherIsBetter,
            context: .rx, setPrescription: setPrescription, exercisePrescription: prescription, exercise: exercise,
            performanceProfile: performanceProfile, completedAt: Date(), modelContext: context
        )

        XCTAssertNil(instance.sourceRMCalibration(for: exercise, rmType: .rm10), "logging an ordinary set must never fabricate a SourceRMCalibration")
        XCTAssertTrue((try context.fetch(FetchDescriptor<SourceRMCalibration>())).isEmpty, "no SourceRMCalibration must exist anywhere as a side effect of logging")
    }

    // MARK: L — estimatedOneRepMax never satisfies source calibration

    func testEstimatedOneRepMaxNeverSatisfiesSourceCalibration() throws {
        let definition = try hypertrophyDefinition()
        let instance = makeInstance(definition: definition)
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        let template = try XCTUnwrap(definition.orderedTemplateSessions.first?.orderedBlockTemplates.first?.orderedPrescriptionTemplates.first)
        let exercise = try XCTUnwrap(template.exerciseSlot?.resolvedExercise)

        let profile = ExercisePerformanceProfile(estimatedOneRepMax: 999, confidence: 1.0)
        profile.exercise = exercise
        context.insert(profile)
        performanceProfile.addExerciseProfile(profile)

        let stillRequired = RequiredSourceCalibrationsUseCase.stillRequired(for: definition, instance: instance)
        XCTAssertTrue(stillRequired.contains { $0.exercise.id == exercise.id }, "a populated estimatedOneRepMax must never satisfy the source calibration requirement")

        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: instance.sourceRMCalibration(for: exercise, rmType: .rm10)?.kilograms) },
            context: context
        )
        let prescription = try XCTUnwrap(result.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).first { $0.sourcePrescriptionTemplate?.id == template.id })
        XCTAssertNil(prescription.orderedSetPrescriptions.first?.targetWeight, "the estimated 1RM (999) must never leak into the resolved source load")
        XCTAssertEqual(prescription.appliedLoadReasonCode, .calibrationRequired)
    }

    // MARK: M — Family B mixed rm5/rm8 requirements stay distinct

    func testFamilyBMixedRM5RM8RequirementsRemainDistinct() throws {
        let entry = try XCTUnwrap(PowerliftingBuiltInLibrary.all.first { $0.name.contains("Strength") })
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let definition = PowerliftingProgramGenerator.generate(configuration: entry.configuration, provenance: .constructed(reason: "test"), context: context)
        ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: [
            catalog.backSquat, catalog.benchPress, catalog.romanianDeadlift, catalog.deadlift, catalog.barbellRow, catalog.dumbbellLateralRaise,
        ])
        let instance = makeInstance(definition: definition)

        let required = RequiredSourceCalibrationsUseCase.stillRequired(for: definition, instance: instance)
        let rmTypesPresent = Set(required.map(\.rmType))
        XCTAssertTrue(rmTypesPresent.contains(.rm5), "Family B's Legs/Push/Deadlift slots require rm5")
        XCTAssertTrue(rmTypesPresent.contains(.rm8), "Family B's Hamstring/Upper-Pull/Shoulder slots require rm8")

        // Calibrating one basis must never satisfy the other, even for
        // the same resolved exercise (if any slot happens to share one).
        if let sharedExercise = required.first(where: { req in required.contains { $0.exercise.id == req.exercise.id && $0.rmType != req.rmType } })?.exercise {
            RecordSourceRMCalibrationUseCase.record(exercise: sharedExercise, rmType: .rm5, kilograms: 100, for: instance, modelContext: context)
            XCTAssertNil(instance.sourceRMCalibration(for: sharedExercise, rmType: .rm8))
        }
    }

    // MARK: N — Family C rm10 uses the identical generic mechanism

    func testFamilyCUniformRM10UsesTheSameGenericMechanism() throws {
        let entry = try XCTUnwrap(PowerliftingBuiltInLibrary.all.first { $0.name.contains("Hypertrophy") })
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let definition = PowerliftingProgramGenerator.generate(configuration: entry.configuration, provenance: .constructed(reason: "test"), context: context)
        ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: [
            catalog.backSquat, catalog.benchPress, catalog.romanianDeadlift, catalog.deadlift, catalog.barbellRow, catalog.dumbbellLateralRaise,
        ])
        let instance = makeInstance(definition: definition)

        let required = RequiredSourceCalibrationsUseCase.stillRequired(for: definition, instance: instance)
        XCTAssertFalse(required.isEmpty)
        XCTAssertTrue(required.allSatisfy { $0.rmType == .rm10 }, "Family C is a uniform 10RM basis")

        for requirement in required {
            RecordSourceRMCalibrationUseCase.record(exercise: requirement.exercise, rmType: requirement.rmType, kilograms: 100, for: instance, modelContext: context)
        }
        XCTAssertTrue(RequiredSourceCalibrationsUseCase.stillRequired(for: definition, instance: instance).isEmpty, "completing every listed requirement must fully satisfy the query")
    }
}
