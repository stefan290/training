import XCTest
import SwiftData
@testable import TrainingOS

/// Dogfood Round 2 Continuation (Finding J): the approved composable
/// measurement-dimension domain model — `Exercise.measuredDimensions`
/// (capability) -> `SetPrescription`'s populated target fields (this
/// prescription's actual targets) -> execution input dimensions ->
/// `SetResult`'s populated actual fields. Farmer's Carry is the concrete
/// proof: distance-based (3 x 40 m), never a fabricated rep count.
@MainActor
final class DogfoodRound2ContinuationFindingJTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    /// A genuinely fresh `ModelContext` on the SAME container — forces a
    /// real re-fetch from the persisted store rather than returning an
    /// already-in-memory object, exactly `TemplateGraphPersistenceTests`'
    /// own round-trip methodology (the file that originally diagnosed this
    /// codebase's real heterogeneous-enum-decode failure this design
    /// deliberately avoids).
    private func freshContext() -> ModelContext {
        ModelContext(container)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar.current.date(from: components)!
    }

    @discardableResult
    private func makeOnboardedAthlete(trainingDays: Int = 5, allowsDoubles: Bool = false) throws -> (user: User, goal: Goal) {
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        user.profile?.trainingEnvironments = [environment]
        user.profile?.defaultTrainingEnvironment = environment
        let goal = Goal(
            ownerUserID: user.id, primaryType: .muscleGain,
            preferences: GoalPreferences(availableTrainingDaysPerWeek: trainingDays, allowsDoubleSessions: allowsDoubles)
        )
        context.insert(goal)
        user.addGoal(goal)
        try context.save()
        return (user, goal)
    }

    private func completeAnyCalibration(goal: Goal, trainingDays: Int, allowsDoubles: Bool = false, asOf: Date) throws {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let environment = goal.user?.profile?.defaultTrainingEnvironment
        guard let phase = goal.plans.first?.orderedPhases.first else { return }
        try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: phase, performanceProfile: goal.user?.performanceProfile,
            availability: UserAvailability(trainingDaysPerWeek: trainingDays, allowsDoubleSessions: allowsDoubles, maxSessionsPerDay: allowsDoubles ? 2 : 1),
            materializationContext: TacticalMaterializationContext(
                equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
                strengthCandidateExercises: exercises, functionalFitnessCandidateExercises: exercises,
                trainingEnvironment: environment
            ),
            asOf: asOf,
            context: context
        )
    }

    /// Builds the real acceptance scenario (Muscle Gain, 4 Hypertrophy +
    /// 1 Functional Fitness/week, Full Gym, 5 days, doubles off) through
    /// the real production path and returns the materialized FF session's
    /// strength (Functional Bodybuilding main-body) block.
    private func makeMuscleGainFFStrengthBlock() throws -> WorkoutBlock {
        let monday = date(2026, 1, 5)
        let (_, goal) = try makeOnboardedAthlete(trainingDays: 5)
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context, referenceDate: monday)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.hypertrophy, 4), (.functionalFitness, 1)]))
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))
        try completeAnyCalibration(goal: goal, trainingDays: 5, asOf: monday)

        let phase = try XCTUnwrap(goal.plans.first?.orderedPhases.first)
        let ffComponent = try XCTUnwrap((phase.selectedTrainingMix ?? phase.recommendedTrainingMix)?.orderedComponents.first { $0.programmingSystem == .functionalFitness })
        let ffSession = try XCTUnwrap(ffComponent.programInstance?.sessions.first)
        return try XCTUnwrap(ffSession.orderedBlocks.first { ($0.type == .strength || $0.type == .hypertrophy) })
    }

    /// MUSCLE + 5FF FINAL CLOSURE, Section 5 (project-owner decision):
    /// Carry/Trunk roles only exist for the `.lowerFatigueComplementary`
    /// family now (no longer unconditional on every FF session) —
    /// `makeMuscleGainFFStrengthBlock`'s "4 Hypertrophy + 1 FF" scenario
    /// resolves that lone FF session to `mixedResistanceWorkCapacity`,
    /// which no longer carries either. This helper reaches the one real
    /// scenario that does: Build Muscle + 5x Functional Fitness alone,
    /// whose 5th (last) session is `.lowerFatigueComplementary` — the
    /// exact same real acceptance scenario
    /// `testFixtureD_MuscleFiveFFAlone` exercises.
    private func makeMuscleGainFFLowerFatigueStrengthBlock() throws -> WorkoutBlock {
        let monday = date(2026, 1, 5)
        let (_, goal) = try makeOnboardedAthlete(trainingDays: 5)
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context, referenceDate: monday)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.functionalFitness, 5)]))
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))
        try completeAnyCalibration(goal: goal, trainingDays: 5, asOf: monday)

        let phase = try XCTUnwrap(goal.plans.first?.orderedPhases.first)
        let ffComponent = try XCTUnwrap((phase.selectedTrainingMix ?? phase.recommendedTrainingMix)?.orderedComponents.first { $0.programmingSystem == .functionalFitness })
        let sessions = try XCTUnwrap(ffComponent.programInstance?.sessions.sorted { ($0.day?.date ?? .distantPast) < ($1.day?.date ?? .distantPast) })
        let lastSession = try XCTUnwrap(sessions.last, "expected the real 5th session (lowerFatigueComplementary)")
        return try XCTUnwrap(lastSession.orderedBlocks.first { ($0.type == .strength || $0.type == .hypertrophy) })
    }

    // MARK: 1. Back Squat remains rep + load based (regression)

    func testLoadedPatternRoleRemainsRepAndLoadBased() throws {
        let strengthBlock = try makeMuscleGainFFStrengthBlock()
        // MUSCLE + 5FF FINAL CLOSURE, Section 5 (project-owner decision):
        // this scenario's main body is now the 2-role primary+
        // complementary loaded-pattern pair, both RIR-driven
        // (`HypertrophyProgramGenerator.repGoalSchedule`, real `.rir`-only
        // prescriptions with no `repRangeLow`/`repRangeHigh` at all — see
        // `causal-analysis/conditioning-test-authority-migration.md`).
        // The real, load-bearing identifying signal for a loaded-pattern
        // role is `appliedLoadReasonCode != nil` (RM-based), not a rep
        // range — the previous `repRangeLow != nil` search actually
        // matched the OLD Trunk accessory role's `.fixedReps(15)` by
        // coincidence, never a genuine loaded pattern.
        let loadedRole = try XCTUnwrap(strengthBlock.orderedPrescriptions.first {
            $0.appliedLoadReasonCode != nil
        })
        let setPrescription = try XCTUnwrap(loadedRole.orderedSetPrescriptions.first)
        XCTAssertNotNil(setPrescription.targetRir, "a loaded-pattern role must remain effort/RIR-based")
        XCTAssertNil(setPrescription.targetDistanceMeters, "a rep-based role must never also carry a distance target")
        XCTAssertNil(setPrescription.targetDurationSeconds)
    }

    // MARK: 2. Farmer's Carry materializes as 3 x 40 m, never 3 x 12 reps

    func testFarmersCarryMaterializesAsThreeSetsOfFortyMetersNeverReps() throws {
        let strengthBlock = try makeMuscleGainFFLowerFatigueStrengthBlock()
        let carryRole = try XCTUnwrap(strengthBlock.orderedPrescriptions.first { $0.exercise?.canonicalName == "Farmer's Carry" })
        let sets = carryRole.orderedSetPrescriptions
        XCTAssertEqual(sets.count, 3, "Farmer's Carry must materialize exactly 3 sets")
        for set in sets {
            XCTAssertEqual(set.targetDistanceMeters, 40, "Farmer's Carry must target 40 real meters, never an invented distance")
            XCTAssertNil(set.repRangeLow, "Farmer's Carry must never carry a rep target")
            XCTAssertNil(set.repRangeHigh)
        }
        // Confirms the real catalog capability signal reached this role.
        let exercise = try XCTUnwrap(carryRole.exercise)
        XCTAssertEqual(exercise.measuredDimensions, [.load, .distance])
    }

    // MARK: 3. Farmer's Carry can record actual load + actual distance with reps == nil

    func testFarmersCarryLogsActualLoadAndDistanceWithNilReps() throws {
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let exercise = try XCTUnwrap(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.canonicalName == "Farmer's Carry" })).first)
        let prescription = ExercisePrescription(exercise: exercise)
        context.insert(prescription)
        let setPrescription = SetPrescription(targetDistanceMeters: 40)
        context.insert(setPrescription)
        prescription.addSetPrescription(setPrescription)
        try context.save()

        let outcome = try LogSetUseCase.logSet(
            setIndex: 0, weight: 32, reps: nil, targetRir: nil, actualRir: nil, prBand: nil,
            scoringDirection: .higherIsBetter, context: .rx, setPrescription: setPrescription,
            exercisePrescription: prescription, exercise: exercise, performanceProfile: try XCTUnwrap(user.performanceProfile),
            completedAt: date(2026, 1, 5), modelContext: context, distanceMeters: 38
        )
        XCTAssertEqual(outcome.result.weight, 32)
        XCTAssertNil(outcome.result.reps, "must never fabricate a rep count for a distance-based result")
        XCTAssertEqual(outcome.result.distanceMeters, 38)
    }

    // MARK: 4/5. Rep-based and distance-based SetResult persist and read correctly

    func testRepBasedSetResultPersistsAndReadsUnchanged() throws {
        let result = SetResult(setIndex: 0, weight: 100, reps: 5, actualRir: 2)
        context.insert(result)
        try context.save()
        let resultID = result.id

        let reloaded = try XCTUnwrap(freshContext().fetch(FetchDescriptor<SetResult>(predicate: #Predicate { $0.id == resultID })).first)
        XCTAssertEqual(reloaded.weight, 100)
        XCTAssertEqual(reloaded.reps, 5)
        XCTAssertEqual(reloaded.actualRir, 2)
        XCTAssertNil(reloaded.distanceMeters)
        XCTAssertNil(reloaded.durationSeconds)
    }

    func testDistanceBasedSetResultPersistsAndReadsCorrectly() throws {
        let result = SetResult(setIndex: 0, weight: 32, reps: nil, distanceMeters: 38)
        context.insert(result)
        try context.save()
        let resultID = result.id

        let reloaded = try XCTUnwrap(freshContext().fetch(FetchDescriptor<SetResult>(predicate: #Predicate { $0.id == resultID })).first)
        XCTAssertEqual(reloaded.weight, 32)
        XCTAssertNil(reloaded.reps)
        XCTAssertEqual(reloaded.distanceMeters, 38)
    }

    // MARK: 6. Heterogeneous rep and distance sibling records survive round-trip

    func testHeterogeneousRepAndDistanceSiblingResultsSurviveRoundTrip() throws {
        let repResult = SetResult(setIndex: 0, weight: 100, reps: 5)
        let distanceResult = SetResult(setIndex: 0, weight: 32, reps: nil, distanceMeters: 38)
        context.insert(repResult)
        context.insert(distanceResult)
        try context.save()
        let repID = repResult.id
        let distanceID = distanceResult.id

        let fresh = freshContext()
        let reloadedRep = try XCTUnwrap(fresh.fetch(FetchDescriptor<SetResult>(predicate: #Predicate { $0.id == repID })).first)
        let reloadedDistance = try XCTUnwrap(fresh.fetch(FetchDescriptor<SetResult>(predicate: #Predicate { $0.id == distanceID })).first)
        XCTAssertEqual(reloadedRep.reps, 5)
        XCTAssertNil(reloadedRep.distanceMeters)
        XCTAssertNil(reloadedDistance.reps, "the distance sibling must not silently decode a rep value from the rep sibling")
        XCTAssertEqual(reloadedDistance.distanceMeters, 38)
    }

    // MARK: 7. No rep-based progression engine treats a distance result as zero-rep

    func testStrengthBlockProgressionEngineExcludesDistanceBasedPrescriptionRatherThanFabricatingRepRange() throws {
        _ = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let exercise = try XCTUnwrap(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.canonicalName == "Farmer's Carry" })).first)
        let prescription = ExercisePrescription(exercise: exercise)
        context.insert(prescription)
        let setPrescription = SetPrescription(targetDistanceMeters: 40)
        context.insert(setPrescription)
        prescription.addSetPrescription(setPrescription)

        let engine = StrengthBlockProgressionEngine(equipmentIncrement: 2.5, lastKnownWeight: 32)
        let output = engine.recommend(BlockProgressionInput(
            currentPrescription: .exercise([prescription]), relevantHistory: [], hasUsableHistory: false
        ))
        XCTAssertEqual(output.recommendation, .none, "a distance-based prescription must never receive a fabricated weight recommendation")
        XCTAssertEqual(output.reasonCode, .calibrationRequired, "the existing 'no fixed rep range' guard already excludes this honestly — never a crash, never a coerced zero-rep computation")
    }

    // MARK: 8/9. StrengthExecutionViewModel exposes the correct input dimensions

    func testViewModelCurrentSetPrescriptionExposesRepDimensionsForRepBasedMovement() throws {
        let strengthBlock = try makeMuscleGainFFStrengthBlock()
        // See `testLoadedPatternRoleRemainsRepAndLoadBased`'s own doc
        // comment: `appliedLoadReasonCode != nil` is the real signal for
        // a loaded-pattern role now that the main body is 2 pure-`.rir`
        // roles (no `repRangeLow` at all).
        let loadedIndex = try XCTUnwrap(strengthBlock.orderedPrescriptions.firstIndex { $0.appliedLoadReasonCode != nil })
        let viewModel = StrengthExecutionViewModel(block: strengthBlock)
        while viewModel.movementIndex != loadedIndex, viewModel.hasNextMovement {
            viewModel.goToNextMovement(modelContext: context)
        }
        let setPrescription = try XCTUnwrap(viewModel.currentSetPrescription)
        XCTAssertNotNil(setPrescription.targetRir)
        XCTAssertNil(setPrescription.targetDistanceMeters)
        XCTAssertNil(setPrescription.targetDurationSeconds)
    }

    func testViewModelCurrentSetPrescriptionExposesDistanceDimensionForFarmersCarryNeverReps() throws {
        let strengthBlock = try makeMuscleGainFFLowerFatigueStrengthBlock()
        let carryIndex = try XCTUnwrap(strengthBlock.orderedPrescriptions.firstIndex { $0.exercise?.canonicalName == "Farmer's Carry" })
        let viewModel = StrengthExecutionViewModel(block: strengthBlock)
        while viewModel.movementIndex != carryIndex, viewModel.hasNextMovement {
            viewModel.goToNextMovement(modelContext: context)
        }
        let setPrescription = try XCTUnwrap(viewModel.currentSetPrescription)
        XCTAssertEqual(setPrescription.targetDistanceMeters, 40)
        XCTAssertNil(setPrescription.repRangeLow, "the view's reps stepper must never be the active input for this movement")
        XCTAssertNil(setPrescription.repRangeHigh)
    }

    // MARK: 10. Preview formatting uses meters, not reps

    func testTargetTextFormattingUsesMetersNotRepsForDistanceBasedPrescription() {
        let text = StrengthSetPresentation.targetText(
            repRangeLow: nil, repRangeHigh: nil, targetRir: nil, targetDistanceMeters: 40, targetDurationSeconds: nil
        )
        XCTAssertEqual(text, "40 m")
        XCTAssertFalse(text.contains("reps"))
    }

    // MARK: 11. Completed-result formatting uses meters, not reps

    func testCompletedFarmersCarryResultCarriesDistanceNeverAFabricatedRepCount() throws {
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let exercise = try XCTUnwrap(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.canonicalName == "Farmer's Carry" })).first)
        let prescription = ExercisePrescription(exercise: exercise)
        context.insert(prescription)
        let setPrescription = SetPrescription(targetDistanceMeters: 40)
        context.insert(setPrescription)
        prescription.addSetPrescription(setPrescription)
        try context.save()

        let outcome = try LogSetUseCase.logSet(
            setIndex: 0, weight: 32, reps: nil, targetRir: nil, actualRir: nil, prBand: nil,
            scoringDirection: .higherIsBetter, context: .rx, setPrescription: setPrescription,
            exercisePrescription: prescription, exercise: exercise, performanceProfile: try XCTUnwrap(user.performanceProfile),
            completedAt: date(2026, 1, 5), modelContext: context, distanceMeters: 38
        )
        // Exactly the data `CompletedExerciseDetail.resultRow` branches on.
        XCTAssertNil(outcome.result.reps)
        XCTAssertEqual(outcome.result.distanceMeters, 38)
        // Finding J's disclosed limitation: no distance-based PR tracking
        // was built this checkpoint — a nil-reps result never enters the
        // existing rep-band PR path.
        XCTAssertFalse(outcome.result.isPersonalRecord)
    }

    // MARK: 12. Existing Functional Bodybuilding main-body behavior remains intact

    func testFunctionalBodybuildingMainBodyStillHasMultipleRolesWithCalibrationFlowIntact() throws {
        let strengthBlock = try makeMuscleGainFFStrengthBlock()
        let prescriptions = strengthBlock.orderedPrescriptions
        XCTAssertGreaterThan(prescriptions.count, 1, "Finding E's multi-role main body must remain intact")
        // MUSCLE + 5FF FINAL CLOSURE, Section 5 (project-owner decision):
        // Farmer's Carry no longer coexists with this scenario's real
        // main body — carry/trunk and loaded patterns are now mutually
        // exclusive by family (see
        // `causal-analysis/conditioning-test-authority-migration.md`);
        // Farmer's Carry's own real presence is covered by
        // `testFarmersCarryMaterializesAsThreeSetsOfFortyMetersNeverReps`.
        // `makeMuscleGainFFStrengthBlock` already ran the real calibration
        // flow (`completeAnyCalibration`) — Finding L's calibration-
        // required lifecycle is "intact" precisely because a loaded-
        // pattern role now has a real RESOLVED weight (not `.calibrationRequired`
        // pending forever, and not a fabricated number either). The
        // primary/complementary loaded patterns are DIFFERENT exercises
        // (e.g. squat vs. press), each needing its OWN separate RM
        // calibration — `completeAnyPendingCalibrationAndMaterialize`
        // resolves the first pending one it finds, not necessarily both,
        // so this asserts at least one real resolution occurred, not full
        // coverage across every distinct exercise.
        //
        // SOURCE AUTHORITY REUSE IMPLEMENTATION: a loaded-pattern role is
        // now identified by real RM-based load reason codes
        // (`.calibrationRequired`/`.rmBasedLoad`), never by `repRangeLow
        // != nil` — Hypertrophy's own real week-1 schedule is RIR-only
        // (`.rir(3)`, Stage 10R.1D semantics), so a genuinely loaded,
        // correctly-resolved role has NO fixed rep range at all. The old
        // `repRangeLow`-based filter was itself an artifact of the prior,
        // unsourced `.fixedReps(10)` invention this checkpoint corrects.
        let loadedRoles = prescriptions.filter { $0.appliedLoadReasonCode == .calibrationRequired || $0.appliedLoadReasonCode == .rmBasedLoad }
        XCTAssertFalse(loadedRoles.isEmpty)
        XCTAssertTrue(loadedRoles.contains { $0.orderedSetPrescriptions.first?.targetWeight != nil }, "the calibration flow must have resolved a real weight for at least one loaded-pattern role")
    }

    // MARK: 13. Existing relative-load guidance remains intact for other loaded movements

    func testExistingRepAndRirTargetTextFormattingIsByteIdenticalToBeforeThisFinding() {
        let before = StrengthSetPresentation.targetText(repRangeLow: 4, repRangeHigh: 6, targetRir: 2)
        let after = StrengthSetPresentation.targetText(
            repRangeLow: 4, repRangeHigh: 6, targetRir: 2, targetDistanceMeters: nil, targetDurationSeconds: nil
        )
        XCTAssertEqual(before, after, "adding distance/duration support must not change existing rep+RIR formatting at all")
        XCTAssertEqual(before, "4-6 reps · RIR 2")
    }
}
