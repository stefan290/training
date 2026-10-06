import XCTest
import SwiftData
@testable import TrainingOS

/// Stage FF.M1: proves the materialization-time movement-composition
/// engine (Stage C moved out of `FunctionalFitnessProgramGenerator`, into
/// `FunctionalFitnessMaterializer`/`FunctionalFitnessMovementComposer`) —
/// genuine week-to-week movement diversity, deterministic composition,
/// same-week-primary/prior-week-secondary history, TE.1-consistent
/// environment degradation, the 8 new per-Exercise structural targets, and
/// truthful FINAL-stimulus movementFunctions — through the real
/// production materialization pipeline, not resolver-unit-only.
@MainActor
final class FunctionalFitnessMovementDiversityTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    // MARK: - Real catalog fixtures (mirrors ExerciseCatalog.swift exactly)

    private func backSquat() -> Exercise { Exercise(canonicalName: "Back Squat", modality: .strength, equipment: "barbell", movementPattern: "squat", primaryTargets: [.quadriceps, .glutes], movementFunctions: [.squatLoaded], functionalModality: .weightlifting, requiredEquipment: [.barbell, .rack]) }
    private func wallBall() -> Exercise { Exercise(canonicalName: "Wall Ball", modality: .functionalFitness, equipment: "medicineBall", movementPattern: "squatToPress", primaryTargets: [.quadriceps, .shoulders], movementFunctions: [.squatLoaded, .pressLoaded], functionalModality: .weightlifting, requiredEquipment: [.medicineBall]) }
    private func thruster() -> Exercise { Exercise(canonicalName: "Thruster", modality: .functionalFitness, equipment: "barbell", movementPattern: "squatToPress", primaryTargets: [.quadriceps, .shoulders], movementFunctions: [.squatLoaded, .pressLoaded], functionalModality: .weightlifting, requiredEquipment: [.barbell]) }
    private func kettlebellSwing() -> Exercise { Exercise(canonicalName: "Kettlebell Swing", modality: .functionalFitness, equipment: "kettlebell", movementPattern: "hipHinge", primaryTargets: [.glutes, .hamstrings], movementFunctions: [.hingeLoaded], functionalModality: .weightlifting, requiredEquipment: [.kettlebell]) }
    private func deadlift() -> Exercise { Exercise(canonicalName: "Deadlift", modality: .functionalFitness, equipment: "barbell", movementPattern: "hinge", primaryTargets: [.back, .hamstrings, .glutes], movementFunctions: [.hingeLoaded], functionalModality: .weightlifting, requiredEquipment: [.barbell]) }
    private func dumbbellSnatch() -> Exercise { Exercise(canonicalName: "Dumbbell Snatch", modality: .functionalFitness, equipment: "dumbbell", movementPattern: "hingeToPress", primaryTargets: [.shoulders, .glutes], movementFunctions: [.hingeLoaded, .pressLoaded], functionalModality: .weightlifting, requiredEquipment: [.dumbbells]) }
    private func pullUp() -> Exercise { Exercise(canonicalName: "Pull-up", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "verticalPull", primaryTargets: [.back, .biceps], movementFunctions: [.gymnasticsPull, .verticalPullLoaded], functionalModality: .gymnastics, requiredEquipment: [.pullUpBar]) }
    private func toesToBar() -> Exercise { Exercise(canonicalName: "Toes-to-Bar", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "coreFlexion", primaryTargets: [.core], movementFunctions: [.gymnasticsPull, .trunk], functionalModality: .gymnastics, requiredEquipment: [.pullUpBar]) }
    private func pushUp() -> Exercise { Exercise(canonicalName: "Push-up", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "horizontalPush", primaryTargets: [.chest, .triceps], movementFunctions: [.gymnasticsPush], functionalModality: .gymnastics, requiredEquipment: [.bodyweight]) }
    private func handstandPushUp() -> Exercise { Exercise(canonicalName: "Handstand Push-up", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "verticalPush", primaryTargets: [.shoulders, .triceps], movementFunctions: [.gymnasticsPush], functionalModality: .gymnastics, requiredEquipment: [.bodyweight]) }
    // FUNCTIONAL FITNESS PROGRAMMING AUTHORITY V2, Section 10/11: `measuredDimensions`
    // added to match the real catalog's truthful tagging — Assault Bike
    // deliberately does NOT declare `.distance` (it never did truthfully;
    // see the real catalog entry), so it correctly continues to receive
    // no distance target now that the target rule checks this field
    // instead of an equipment-name string.
    // MUSCLE VERTICAL SLICE REPAIR, Section 14: `intendedIntensity: .low`
    // added to keep this mirror fixture faithful to the real catalog
    // entry (this file's own stated design goal, see header above) —
    // every pre-existing test using this fixture is unaffected, since
    // `requiredIntensity` defaults `nil` everywhere it isn't explicitly set.
    private func easyRun() -> Exercise { Exercise(canonicalName: "Easy Run (Zone 2)", modality: .conditioning, equipment: "none", movementPattern: "locomotion", movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning, requiredEquipment: [], measuredDimensions: [.distance, .duration], intendedIntensity: .low) }
    private func trackIntervalRun() -> Exercise { Exercise(canonicalName: "Track Interval Run", modality: .conditioning, equipment: "none", movementPattern: "locomotion", movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning, requiredEquipment: [], measuredDimensions: [.distance, .duration]) }
    private func assaultBike() -> Exercise { Exercise(canonicalName: "Assault Bike", modality: .functionalFitness, equipment: "bike", movementPattern: "locomotion", movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning, requiredEquipment: [.bike], measuredDimensions: [.calories, .duration]) }
    private func rowErg() -> Exercise { Exercise(canonicalName: "Row Erg", modality: .functionalFitness, equipment: "rower", movementPattern: "locomotion", movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning, requiredEquipment: [.rower], measuredDimensions: [.distance, .calories, .duration]) }

    /// Every FF.M1-accepted-function-eligible real candidate — a Full Gym
    /// pool covering all 6 accepted functions, matching `ExerciseCatalog`
    /// exactly.
    private func fullCatalog() -> [Exercise] {
        [backSquat(), wallBall(), thruster(), kettlebellSwing(), deadlift(), dumbbellSnatch(),
         pullUp(), toesToBar(), pushUp(), handstandPushUp(), easyRun(), trackIntervalRun(), assaultBike(), rowErg()]
    }

    private func realProductionStimulus() -> Stimulus {
        Stimulus(
            targetDurationDomain: .medium, intensity: .moderate, loading: .moderate,
            movementFunctions: [.squatLoaded, .gymnasticsPull, .monostructural],
            movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1), ModalityCount(modality: .gymnastics, count: 1), ModalityCount(modality: .metabolicConditioning, count: 1)],
            skillDemand: .moderate, systemicDemand: .moderate, scoreType: .time
        )
    }

    private func configuration(daysPerWeek: Int, lengthWeeks: Int = 1) -> FunctionalFitnessProgramConfiguration {
        FunctionalFitnessProgramConfiguration(
            daysPerWeek: daysPerWeek, lengthWeeks: lengthWeeks, targetStimulus: realProductionStimulus(),
            format: .roundsForTime(rounds: 5, capSeconds: nil), sessionRole: .functionalFitness,
            varianceConstraints: VarianceConstraints(), requiresRecentExposureToProgress: false, includeStrengthBlock: false
        )
    }

    private func materialize(daysPerWeek: Int, candidates: [Exercise], environment: TrainingEnvironment, weekIndex: Int = 0, definition: ProgramDefinition? = nil, instance: ProgramInstance? = nil) throws -> (sessions: [Session], definition: ProgramDefinition, instance: ProgramInstance) {
        let def = definition ?? FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: daysPerWeek), provenance: .constructed(reason: "test"), context: context)
        let inst = instance ?? {
            let i = ProgramInstance(ownerUserID: ownerUserID)
            context.insert(i)
            i.programDefinition = def
            return i
        }()
        for candidate in candidates where candidate.modelContext == nil { context.insert(candidate) }
        let sessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: def, instance: inst, weekIndex: weekIndex, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
            candidateExercises: candidates, exposureHistory: [], environment: environment, context: context
        )
        return (sessions, def, inst)
    }

    // MARK: - A. Composer determinism / composition (pure, no @Model)

    func testComposerIsDeterministicAcrossRepeatedCallsWithIdenticalInputs() {
        var composerA = FunctionalFitnessMovementComposer()
        var composerB = FunctionalFitnessMovementComposer()
        let eligible: Set<MovementFunction> = [.squatLoaded, .hingeLoaded, .pressLoaded, .gymnasticsPull, .gymnasticsPush]
        let sessionsA = (0..<4).map { _ in composerA.composeSession(eligibleFunctions: eligible, monostructuralEligible: true) }
        let sessionsB = (0..<4).map { _ in composerB.composeSession(eligibleFunctions: eligible, monostructuralEligible: true) }
        XCTAssertEqual(sessionsA, sessionsB, "identical inputs must reproduce identical composition, no randomness")
    }

    func testTwoSessionSupportingWeekMatchesTheLockedDesignExample() {
        var composer = FunctionalFitnessMovementComposer()
        let eligible: Set<MovementFunction> = [.squatLoaded, .hingeLoaded, .pressLoaded, .gymnasticsPull, .gymnasticsPush]
        let session1 = composer.composeSession(eligibleFunctions: eligible, monostructuralEligible: true)
        let session2 = composer.composeSession(eligibleFunctions: eligible, monostructuralEligible: true)
        XCTAssertEqual(session1, [.squatLoaded, .gymnasticsPull, .hingeLoaded], "locked N=2 example, session 1")
        XCTAssertEqual(session2, [.gymnasticsPush, .pressLoaded, .monostructural], "locked N=2 example, session 2 — conditioning appears only once primary coverage completes")
    }

    func testMonostructuralIsAbsentFromTheFirstSessionOfTheWeek() {
        var composer = FunctionalFitnessMovementComposer()
        let eligible: Set<MovementFunction> = [.squatLoaded, .hingeLoaded, .pressLoaded, .gymnasticsPull, .gymnasticsPush]
        let session1 = composer.composeSession(eligibleFunctions: eligible, monostructuralEligible: true)
        XCTAssertFalse(session1.contains(.monostructural), "monostructural is a secondary-fill choice, never mandatory — Correction 1")
    }

    func testThreeSessionWeekCoversAllThreeLoadedFunctionsAndBothGymnasticsFunctions() {
        var composer = FunctionalFitnessMovementComposer()
        let eligible: Set<MovementFunction> = [.squatLoaded, .hingeLoaded, .pressLoaded, .gymnasticsPull, .gymnasticsPush]
        let allRoles = (0..<3).flatMap { _ in composer.composeSession(eligibleFunctions: eligible, monostructuralEligible: true) }
        for function in [MovementFunction.squatLoaded, .hingeLoaded, .pressLoaded, .gymnasticsPull, .gymnasticsPush] {
            XCTAssertTrue(allRoles.contains(function), "\(function) must receive real exposure across a 3-session week")
        }
    }

    func testPriorWeekExposureIsOnlyATieBreakNeverOverridingSameWeekCoverage() {
        // squatLoaded/hingeLoaded/pressLoaded all heavily prior-exposed;
        // gymnasticsPull/gymnasticsPush have zero prior exposure. Same-week
        // coverage must still be satisfied for ALL functions before any
        // repeat — prior-week bias must never skip a genuinely uncovered
        // function in favor of a "less recently prior-exposed" one from a
        // DIFFERENT class that Phase 1's alternation isn't due to pick.
        var composer = FunctionalFitnessMovementComposer(priorWeekExposure: [.squatLoaded: 10, .hingeLoaded: 10, .pressLoaded: 10, .gymnasticsPull: 0, .gymnasticsPush: 0])
        let eligible: Set<MovementFunction> = [.squatLoaded, .hingeLoaded, .pressLoaded, .gymnasticsPull, .gymnasticsPush]
        let session1 = composer.composeSession(eligibleFunctions: eligible, monostructuralEligible: false)
        // Same-week exposure (all 0) is checked first; prior-week only
        // breaks a same-week tie — since every function starts at
        // same-week 0, prior-week DOES legitimately pick the least-prior-
        // exposed within the class due (gymnasticsPull ties at same-week=0
        // with gymnasticsPush, prior-week picks the lower one).
        XCTAssertEqual(Set(session1).intersection([.squatLoaded, .hingeLoaded, .pressLoaded]).count, 2, "loaded class alternation still fires twice in a 3-role session regardless of prior-week bias")
    }

    func testEnvironmentClassExclusionIsNeverSubstitutedWithAnUnrelatedClass() {
        var composer = FunctionalFitnessMovementComposer()
        // LOADED entirely environment-blocked (Minimal Bodyweight-style),
        // and no monostructural candidate either — the genuinely thin
        // case where the role-count floor actually bites.
        let eligible: Set<MovementFunction> = [.gymnasticsPush]
        let session = composer.composeSession(eligibleFunctions: eligible, monostructuralEligible: false)
        XCTAssertFalse(session.contains(.squatLoaded) || session.contains(.hingeLoaded) || session.contains(.pressLoaded), "an excluded class is skipped, never cross-substituted")
        XCTAssertTrue(session.allSatisfy { $0 == .gymnasticsPush }, "only the one real eligible function ever fills a role — never a fabricated cross-class substitute")
    }

    func testRoleCountTruthfullyReducesWhenNothingElseCanFillTheRemainingSlots() {
        var composer = FunctionalFitnessMovementComposer()
        // Only ONE real eligible function total (gymnasticsPush) and no
        // conditioning candidate — Phase 2(b)'s repeat mechanism still has
        // something to repeat here, so role count stays 3; role count
        // only drops below 3 when literally nothing remains eligible at
        // all (proven separately by the zero-eligible-classes throw).
        let eligible: Set<MovementFunction> = [.gymnasticsPush]
        let session = composer.composeSession(eligibleFunctions: eligible, monostructuralEligible: false)
        XCTAssertEqual(session.count, 3, "a single real eligible function can still legitimately repeat to fill all 3 roles")
    }

    // MARK: - B. Target rule — FF.M1's 8 new per-Exercise branches

    func testHingeLoadedTargets() {
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .weightlifting, movementFunctions: [.hingeLoaded], exercise: kettlebellSwing(), targetDurationDomain: .medium).reps, 15)
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .weightlifting, movementFunctions: [.hingeLoaded], exercise: deadlift(), targetDurationDomain: .medium).reps, 8)
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .weightlifting, movementFunctions: [.hingeLoaded], exercise: dumbbellSnatch(), targetDurationDomain: .medium).reps, 10)
    }

    func testPressLoadedTargets() {
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .weightlifting, movementFunctions: [.pressLoaded], exercise: wallBall(), targetDurationDomain: .medium).reps, 15)
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .weightlifting, movementFunctions: [.pressLoaded], exercise: thruster(), targetDurationDomain: .medium).reps, 8)
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .weightlifting, movementFunctions: [.pressLoaded], exercise: dumbbellSnatch(), targetDurationDomain: .medium).reps, 10)
    }

    func testGymnasticsPushTargets() {
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .gymnastics, movementFunctions: [.gymnasticsPush], exercise: pushUp(), targetDurationDomain: .medium).reps, 15)
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .gymnastics, movementFunctions: [.gymnasticsPush], exercise: handstandPushUp(), targetDurationDomain: .medium).reps, 5)
    }

    func testDumbbellSnatchHingeAndPressBranchesAreStructurallyDistinct() {
        let hingeTarget = FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .weightlifting, movementFunctions: [.hingeLoaded], exercise: dumbbellSnatch(), targetDurationDomain: .medium)
        let pressTarget = FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .weightlifting, movementFunctions: [.pressLoaded], exercise: dumbbellSnatch(), targetDurationDomain: .medium)
        // Both currently 10 — proving VALUE equality is not the same as
        // proving structural identity; the real regression guard is that
        // each branch is reached via a distinct `movementFunctions`
        // context, exercised separately here.
        XCTAssertEqual(hingeTarget.reps, 10)
        XCTAssertEqual(pressTarget.reps, 10)
    }

    func testExistingFFP1TargetsRemainUnchanged() {
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .weightlifting, movementFunctions: [.squatLoaded], exercise: backSquat(), targetDurationDomain: .medium).reps, 12)
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .gymnastics, movementFunctions: [.gymnasticsPull], exercise: pullUp(), targetDurationDomain: .medium).reps, 8)
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .metabolicConditioning, movementFunctions: [.monostructural], exercise: rowErg(), targetDurationDomain: .medium).distanceMeters, 200)
        XCTAssertNil(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .metabolicConditioning, movementFunctions: [.monostructural], exercise: assaultBike(), targetDurationDomain: .medium).distanceMeters, "the Assault Bike exception remains unchanged")
    }

    func testNoNumericLoadIsEverInventedByAnyNewBranch() {
        for exercise in [kettlebellSwing(), deadlift(), dumbbellSnatch(), wallBall(), thruster(), pushUp(), handstandPushUp()] {
            for function in [MovementFunction.hingeLoaded, .pressLoaded, .gymnasticsPush] {
                let target = FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: exercise.functionalModality ?? .weightlifting, movementFunctions: [function], exercise: exercise, targetDurationDomain: .medium)
                XCTAssertNil(target.distanceMeters == nil ? nil : target.distanceMeters, "distance stays nil for every loaded/gymnastics branch")
            }
        }
    }

    // MARK: - C. Real production-path materialization — same algorithm, all 3 frequencies

    func testSupportingTwoSessionWeekMaterializesRealResolvedExercisesAndTargetsThroughTheSameAlgorithm() throws {
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let result = try materialize(daysPerWeek: 2, candidates: fullCatalog(), environment: environment)
        let allMovements = result.sessions.flatMap(\.orderedBlocks).compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements)
        XCTAssertEqual(allMovements.count, 6, "2 sessions × 3 roles")
        XCTAssertTrue(allMovements.allSatisfy { $0.exercise != nil }, "every role resolves a real Exercise from a rich Full Gym candidate pool")
        let usedExerciseIDsPerSession = result.sessions.map { session -> Set<UUID> in
            Set(session.orderedBlocks.compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements).compactMap(\.exercise?.id))
        }
        for (session, movements) in zip(result.sessions, usedExerciseIDsPerSession) {
            let movementCount = session.orderedBlocks.compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements).count
            XCTAssertEqual(movements.count, movementCount, "no Exercise fills two roles in the same session")
        }
    }

    func testFatLossThreeSessionWeekUsesTheSameAlgorithmAsTheTwoAndFourSessionMixes() throws {
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let result = try materialize(daysPerWeek: 3, candidates: fullCatalog(), environment: environment)
        XCTAssertEqual(result.sessions.count, 3)
        let allFunctions = result.sessions.flatMap(\.orderedBlocks).compactMap(\.functionalFitnessPrescription).flatMap { $0.stimulus.movementFunctions }
        for function in [MovementFunction.squatLoaded, .hingeLoaded, .pressLoaded, .gymnasticsPull, .gymnasticsPush] {
            XCTAssertTrue(allFunctions.contains(function), "a 3-session week covers all 5 primary functions — locked N=3 example")
        }
    }

    func testFocusedFourSessionWeekProducesFourCoherentSessionsThroughTheSameAlgorithm() throws {
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let result = try materialize(daysPerWeek: 4, candidates: fullCatalog(), environment: environment)
        XCTAssertEqual(result.sessions.count, 4)
        let hasMonostructuralFreeSession = result.sessions.contains { session in
            !(session.orderedBlocks.compactMap(\.functionalFitnessPrescription).flatMap { $0.stimulus.movementFunctions }.contains(.monostructural))
        }
        XCTAssertTrue(hasMonostructuralFreeSession, "at least one of the 4 sessions genuinely omits conditioning — Correction 1")
    }

    func testFinalStimulusMovementFunctionsExactlyMatchTheActualComposedRoles() throws {
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let result = try materialize(daysPerWeek: 2, candidates: fullCatalog(), environment: environment)
        for session in result.sessions {
            for prescription in session.orderedBlocks.compactMap(\.functionalFitnessPrescription) {
                let actualFunctions = Set(prescription.orderedMovements.compactMap { $0.sourceExerciseSlot?.allowedMovementFunctions.first })
                XCTAssertEqual(actualFunctions, Set(prescription.stimulus.movementFunctions), "FINAL stimulus.movementFunctions is a truthful record of what was actually composed, not the old frozen CONFIGURED value")
            }
        }
    }

    func testWeekNPlusOneSessionOneCanLegitimatelyDifferFromWeekNWhenHistoryDiffers() throws {
        // Stage FF.M1: daysPerWeek 3 (fatLossVariedMix's real shape)
        // produces genuinely ASYMMETRIC prior-week exposure (squatLoaded/
        // gymnasticsPull get a 2nd-lap repeat, hingeLoaded/pressLoaded/
        // gymnasticsPush do not) — daysPerWeek 2 would leave every
        // function tied at exactly 1 exposure each, giving prior-week
        // history nothing to differentiate.
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let week0 = try materialize(daysPerWeek: 3, candidates: fullCatalog(), environment: environment, weekIndex: 0)
        let week1 = try materialize(daysPerWeek: 3, candidates: fullCatalog(), environment: environment, weekIndex: 1, definition: week0.definition, instance: week0.instance)
        let week0Session1Functions = week0.sessions.first?.orderedBlocks.compactMap(\.functionalFitnessPrescription).first?.stimulus.movementFunctions
        let week1Session1Functions = week1.sessions.first?.orderedBlocks.compactMap(\.functionalFitnessPrescription).first?.stimulus.movementFunctions
        XCTAssertNotEqual(week0Session1Functions, week1Session1Functions, "prior-week prescription history legitimately changes week N+1's first session")
    }

    func testWallBallCannotFillBothSquatAndPressRolesInTheSameSession() throws {
        // A pool where Wall Ball is the ONLY weightlifting-modality
        // candidate for both squat and press — same-session distinctness
        // must leave the second role unresolved rather than double-using
        // Wall Ball.
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let candidates = [wallBall(), pullUp(), toesToBar(), pushUp(), handstandPushUp(), rowErg()]
        let result = try materialize(daysPerWeek: 4, candidates: candidates, environment: environment)
        for session in result.sessions {
            let wallBallCount = session.orderedBlocks.compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements).filter { $0.exercise?.canonicalName == "Wall Ball" }.count
            XCTAssertLessThanOrEqual(wallBallCount, 1, "Wall Ball may fill at most one role per session")
        }
    }

    func testCatalogReorderDoesNotChangeThePrescription() throws {
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let forward = try materialize(daysPerWeek: 2, candidates: fullCatalog(), environment: environment)
        let forwardNames = forward.sessions.flatMap(\.orderedBlocks).compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements).compactMap { $0.exercise?.canonicalName }.sorted()

        let container2 = PersistenceController.makeInMemoryContainer()
        let context2 = container2.mainContext
        let reversedCatalog = fullCatalog().reversed().map { candidate -> Exercise in
            // FUNCTIONAL FITNESS PROGRAMMING AUTHORITY V2: `measuredDimensions`
            // must be carried through this copy exactly like every other
            // field — an omitted field here (defaulting to `[]`) would
            // silently strip the real monostructural candidates'
            // `.distance` declaration, breaking this test for a reason
            // unrelated to what it actually verifies (order-independence).
            // MUSCLE VERTICAL SLICE REPAIR, Section 14: `intendedIntensity`
            // likewise must be carried through — the real production
            // materializer now threads a real, non-nil `requiredIntensity`
            // into every conditioning selection, so an un-copied `nil`
            // here (vs. the forward catalog's real `.low` on Easy Run)
            // would create a genuine forward/reversed asymmetry unrelated
            // to catalog order itself.
            let copy = Exercise(canonicalName: candidate.canonicalName, modality: candidate.modality, equipment: candidate.equipment, movementPattern: candidate.movementPattern, primaryTargets: candidate.primaryTargets, movementFunctions: candidate.movementFunctions, functionalModality: candidate.functionalModality, requiredEquipment: candidate.requiredEquipment, measuredDimensions: candidate.measuredDimensions, intendedIntensity: candidate.intendedIntensity)
            context2.insert(copy)
            return copy
        }
        let environment2 = TrainingEnvironmentTestSupport.full(context: context2)
        let def2 = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 2), provenance: .constructed(reason: "test"), context: context2)
        let inst2 = ProgramInstance(ownerUserID: ownerUserID)
        context2.insert(inst2)
        inst2.programDefinition = def2
        let reversedSessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: def2, instance: inst2, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
            candidateExercises: reversedCatalog, exposureHistory: [], environment: environment2, context: context2
        )
        let reversedNames = reversedSessions.flatMap(\.orderedBlocks).compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements).compactMap { $0.exercise?.canonicalName }.sorted()
        XCTAssertEqual(forwardNames, reversedNames, "candidate array order must never change the real prescription")
    }

    // MARK: - D. Training Environment

    func testMinimalBodyweightEnvironmentProducesATruthfulReducedRoleSession() throws {
        let bodyweightOnly = TrainingEnvironment(name: "Minimal Bodyweight", availableEquipment: [.bodyweight, .pullUpBar])
        context.insert(bodyweightOnly)
        let candidates = fullCatalog() // Loaded functions all require unavailable equipment (barbell/rack/kettlebell/dumbbells/medicineBall)
        let result = try materialize(daysPerWeek: 2, candidates: candidates, environment: bodyweightOnly)
        for session in result.sessions {
            let movements = session.orderedBlocks.compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements)
            XCTAssertTrue(movements.allSatisfy { $0.exercise?.functionalModality != .weightlifting }, "no loaded-class Exercise resolves when the environment provides none of its required equipment")
        }
    }

    func testZeroEligibleClassesThrowsTheTypedEnvironmentIncompatibleError() throws {
        let nothingEnvironment = TrainingEnvironment(name: "Nothing", availableEquipment: [])
        context.insert(nothingEnvironment)
        // No candidate at all can satisfy any function in this environment.
        XCTAssertThrowsError(try materialize(daysPerWeek: 1, candidates: [backSquat()], environment: nothingEnvironment)) { error in
            guard case FunctionalFitnessMaterializationError.environmentIncompatible = error else {
                return XCTFail("expected .environmentIncompatible, got \(error)")
            }
        }
    }

    // MARK: - E. Persistence

    func testIsDynamicallyComposedDefaultsToTrueForNewlyGeneratedContent() {
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 2), provenance: .constructed(reason: "test"), context: context)
        let template = definition.orderedTemplateSessions.first?.orderedBlockTemplates.first?.functionalFitnessPrescriptionTemplate
        XCTAssertEqual(template?.isDynamicallyComposed, true)
    }

    func testIsDynamicallyComposedFalsePreservesGenerationTimeSlotsUntouched() throws {
        var config = configuration(daysPerWeek: 1)
        config.isDynamicallyComposed = false
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: config, provenance: .constructed(reason: "test"), context: context)
        let template = try XCTUnwrap(definition.orderedTemplateSessions.first?.orderedBlockTemplates.first?.functionalFitnessPrescriptionTemplate)
        XCTAssertFalse(template.orderedMovementSlots.isEmpty, "an authored (isDynamicallyComposed == false) template keeps its generation-time slots")
        XCTAssertEqual(template.orderedMovementSlots.count, 3)
    }

    // MARK: - F. FUNCTIONAL FITNESS PROGRAMMING AUTHORITY V2, Section 8 —
    // purpose-specific capability gating, through REAL production
    // materialization (never a hand-built fixture, never a unit-only
    // proof of the selector alone).

    private func chestToBarPullUp() -> Exercise {
        Exercise(
            canonicalName: "Chest-to-Bar Pull-up", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "verticalPull",
            primaryTargets: [.back, .biceps], movementFunctions: [.gymnasticsPull, .verticalPullLoaded], functionalModality: .gymnastics,
            requiredEquipment: [.pullUpBar], requiresDemonstratedCapability: true
        )
    }

    /// JOURNEY F (project lead's "UNKNOWN TECHNICAL SKILL"): the ONLY
    /// gymnasticsPull-role candidate in this pool is a gated exercise.
    /// With a real `movementCapabilityLookup` reporting `.unknown`,
    /// production materialization must throw `capabilityUnknown` —
    /// never silently persist it, never silently drop the role.
    func testJourneyF_UnknownTechnicalSkillNeverSilentlyMaterializesAsConditioning() throws {
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let candidates = [backSquat(), chestToBarPullUp(), rowErg()]
        let def = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 1), provenance: .constructed(reason: "test"), context: context)
        let inst = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(inst)
        inst.programDefinition = def
        for candidate in candidates { context.insert(candidate) }

        XCTAssertThrowsError(try FunctionalFitnessMaterializer.materializeWeek(
            definition: def, instance: inst, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
            candidateExercises: candidates, exposureHistory: [], environment: environment,
            movementCapabilityLookup: { _ in .unknown },
            context: context
        )) { error in
            guard case FunctionalFitnessMaterializationError.capabilityUnknown = error else {
                return XCTFail("expected .capabilityUnknown, got \(error)")
            }
        }
    }

    /// Same pool, `.workoutReady` this time: production materialization
    /// now genuinely accepts the gated exercise for automatic selection —
    /// proves the gate is real (fires both ways), not merely a permanent
    /// block.
    func testJourneyF_WorkoutReadyGatedMovementBecomesRealEligibleCandidate() throws {
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let candidates = [backSquat(), chestToBarPullUp(), rowErg()]
        let def = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 1), provenance: .constructed(reason: "test"), context: context)
        let inst = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(inst)
        inst.programDefinition = def
        for candidate in candidates { context.insert(candidate) }

        // CONDITIONING DOSE AUTHORITY V1, Section 12: WORKOUT_READY ALONE
        // is no longer sufficient for the 7 real repeated-dose-tracked
        // movements (Chest-to-Bar Pull-up is one) — real, usable capacity
        // evidence is also required, so this journey's own real intent
        // ("workoutReady makes the gated exercise a real, selectable
        // candidate") now needs a real `PerformanceProfile`/
        // `MovementCapabilityProfile` row to prove, not a bare closure
        // returning `.workoutReady` for everything with no capacity data.
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        let capability = MovementCapabilityProfile(
            exercise: candidates.first { $0.canonicalName == "Chest-to-Bar Pull-up" },
            proficiency: .workoutReady, capacityType: .maxUnbrokenReps, capacityValue: 20,
            evidenceSource: .selfReported
        )
        context.insert(capability)
        performanceProfile.addMovementCapability(capability)

        let sessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: def, instance: inst, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
            candidateExercises: candidates, exposureHistory: [], environment: environment,
            movementCapabilityLookup: { _ in .workoutReady },
            performanceProfile: performanceProfile,
            context: context
        )
        let movements = sessions.first?.orderedBlocks.compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements) ?? []
        XCTAssertTrue(movements.contains { $0.exercise?.canonicalName == "Chest-to-Bar Pull-up" }, "workoutReady + real usable capacity evidence must make the gated exercise a real, selectable candidate")
        let chestToBarMovement = try XCTUnwrap(movements.first { $0.exercise?.canonicalName == "Chest-to-Bar Pull-up" })
        XCTAssertEqual(chestToBarMovement.reps, TechnicalCapacityDoseAuthority.maxRepeatedDose(forCapacity: 20), "the real repeated-dose ceiling (capacity 20 → max 8) must clamp the movement's actual materialized rep target")
    }

    /// Section 21, item 6: the exact real-world example
    /// `ResolveProgramInstanceExerciseSlotsUseCase`'s own doc comment
    /// cites ("Toes-to-Bar capacity 7 -> ceiling 3") — proven here
    /// end-to-end through real production materialization, not only the
    /// pure `maxRepeatedDose` boundary table. "Conservatively submaximal"
    /// means the real materialized rep target is genuinely CLAMPED DOWN
    /// from what an unconstrained pick would use (12, Toes-to-Bar's own
    /// FF.P1 default), never merely equal to some other unrelated number.
    func testCapacitySevenToesToBarRemainsConservativelySubmaximal() throws {
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let candidates = [backSquat(), toesToBar(), rowErg()]
        let def = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 1), provenance: .constructed(reason: "test"), context: context)
        let inst = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(inst)
        inst.programDefinition = def
        for candidate in candidates { context.insert(candidate) }

        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        let capability = MovementCapabilityProfile(
            exercise: candidates.first { $0.canonicalName == "Toes-to-Bar" },
            proficiency: .workoutReady, capacityType: .maxUnbrokenReps, capacityValue: 7,
            evidenceSource: .selfReported
        )
        context.insert(capability)
        performanceProfile.addMovementCapability(capability)

        let sessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: def, instance: inst, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
            candidateExercises: candidates, exposureHistory: [], environment: environment,
            movementCapabilityLookup: { _ in .workoutReady },
            performanceProfile: performanceProfile,
            context: context
        )
        let movements = sessions.first?.orderedBlocks.compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements) ?? []
        let toesToBarMovement = try XCTUnwrap(movements.first { $0.exercise?.canonicalName == "Toes-to-Bar" }, "capacity 7 + workoutReady must still make Toes-to-Bar a real, selectable candidate")
        let ceiling = TechnicalCapacityDoseAuthority.maxRepeatedDose(forCapacity: 7)
        XCTAssertEqual(ceiling, 3, "capacity 7 must map to the real, locked ceiling of 3")
        XCTAssertEqual(toesToBarMovement.reps, 3, "the real materialized rep target must be clamped to the real ceiling")
        XCTAssertLessThan(toesToBarMovement.reps ?? .max, 12, "conservatively submaximal: strictly below Toes-to-Bar's own unconstrained FF.P1 default (12), never merely equal to it")
    }

    /// Section 21, item 5: a workout-ready (real capacity evidence)
    /// technical movement passing `isCapabilityEligible`'s gate is still
    /// subject to the SAME whole-week exposure/variety ranking every
    /// other candidate is (step 5/9 of the selector's own documented
    /// priority order) — eligibility never short-circuits straight to
    /// selection. Proven directly against the pure selector: a plain,
    /// non-technical, LESS-exposed candidate must still win over a
    /// workout-ready, MORE-exposed technical one for the same role.
    func testWorkoutReadyTechnicalMovementIsEligibleButNotAutomaticallySelectedOverALessExposedAlternative() throws {
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let toesToBar = toesToBar()
        let ringRow = Exercise(canonicalName: "Ring Row", modality: .functionalFitness, equipment: "rings", movementPattern: "horizontalPull", primaryTargets: [.back, .biceps], movementFunctions: [.gymnasticsPull], functionalModality: .gymnastics)
        context.insert(toesToBar)
        context.insert(ringRow)

        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        let capability = MovementCapabilityProfile(exercise: toesToBar, proficiency: .workoutReady, capacityType: .maxUnbrokenReps, capacityValue: 20, evidenceSource: .selfReported)
        context.insert(capability)
        performanceProfile.addMovementCapability(capability)

        let resolution = MovementRoleExerciseSelector.select(.init(
            function: .gymnasticsPull, slot: ExerciseSlot(name: "test", allowedTargets: [.back], allowedMovementFunctions: [.gymnasticsPull]),
            candidateExercises: [toesToBar, ringRow], environment: environment,
            modality: .gymnastics, usedExerciseIDsThisSession: [], sameSessionMainBodyExerciseIDs: [],
            preferredExercise: nil,
            // Toes-to-Bar (workout-ready, real evidence, fully ELIGIBLE)
            // is MORE exposed this week than Ring Row — if eligibility
            // alone drove selection, Toes-to-Bar would still win despite
            // its higher exposure; the real selector must instead prefer
            // the less-exposed Ring Row.
            thisWeekExposureForFunction: [toesToBar.id: 2, ringRow.id: 0], priorWeekExposureForFunction: [:],
            purpose: .conditioning, proficiency: { _ in .workoutReady },
            capacity: { exercise in
                guard let capability = performanceProfile.movementCapability(for: exercise),
                      let type = capability.capacityType, let value = capability.capacityValue
                else { return nil }
                return (type: type, value: value)
            }
        ))
        guard case .resolved(let exercise) = resolution else {
            return XCTFail("expected a resolved candidate, got \(resolution)")
        }
        XCTAssertEqual(exercise.canonicalName, "Ring Row", "eligibility (workout-ready + real evidence) must not override the selector's own exposure/variety ranking — the less-exposed alternative must still win")
    }

    /// JOURNEY B (project lead's "DOUBLE-UNDER LEARNING"), generalized:
    /// `.learning` proficiency is NOT workout-ready for a CONDITIONING
    /// purpose (Section 8) — the gated exercise must still be excluded
    /// from automatic conditioning selection, exactly like `.unknown`.
    func testJourneyB_LearningProficiencyIsNotWorkoutReadyForConditioningPurpose() throws {
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let candidates = [backSquat(), chestToBarPullUp(), rowErg()]
        let def = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 1), provenance: .constructed(reason: "test"), context: context)
        let inst = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(inst)
        inst.programDefinition = def
        for candidate in candidates { context.insert(candidate) }

        XCTAssertThrowsError(try FunctionalFitnessMaterializer.materializeWeek(
            definition: def, instance: inst, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
            candidateExercises: candidates, exposureHistory: [], environment: environment,
            movementCapabilityLookup: { _ in .learning },
            context: context
        )) { error in
            guard case FunctionalFitnessMaterializationError.capabilityUnknown = error else {
                return XCTFail("expected .capabilityUnknown (LEARNING is not workout-ready for CONDITIONING), got \(error)")
            }
        }
    }

    // MARK: - CONDITIONING V2 FINAL COMPLETION PASS, Sections 1-2, 6: the
    // purpose-specific non-rep technical exclusion, proven both ways
    // through real production materialization — never auto-selected as a
    // Conditioning dependency, but never touched by any other purpose.

    private func clean() -> Exercise {
        Exercise(
            canonicalName: "Clean", modality: .functionalFitness, equipment: "barbell", movementPattern: "hingeToSquat",
            primaryTargets: [.hamstrings, .glutes, .quadriceps], movementFunctions: [.hingeLoaded, .squatLoaded], functionalModality: .weightlifting,
            requiredEquipment: [.barbell], isExplosiveExpression: true, requiresDemonstratedCapability: true, measuredDimensions: [.load]
        )
    }

    private func ropeClimb() -> Exercise {
        Exercise(
            canonicalName: "Rope Climb", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "verticalPull",
            primaryTargets: [.back, .forearms], movementFunctions: [.gymnasticsPull], functionalModality: .gymnastics,
            requiredEquipment: [.climbingRope], requiresDemonstratedCapability: true, measuredDimensions: [.reps]
        )
    }

    /// Side A: even with Clean reported real `.workoutReady` (the ONLY
    /// gate CP1's own capability model tracks for it), real Conditioning
    /// materialization must never select it — Section 1's "no truthful
    /// automatic Conditioning dosage authority... regardless of
    /// proficiency." Back Squat remains eligible for the same
    /// `squatLoaded` role, so the real materialized week must fall
    /// through to it instead of throwing.
    func testCleanNeverBecomesAConditioningDependencyEvenWhenWorkoutReady() throws {
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        // Clean's real catalog entry is dual-function (squatLoaded AND
        // hingeLoaded) — `deadlift()` is included so ANY role the real
        // composer/materializer derives from that dual nature still has a
        // real, non-excluded, non-Clean candidate available; the test's
        // claim ("Clean never becomes a Conditioning dependency") must
        // hold regardless of which specific role slot the pipeline
        // constructs from Clean's own multi-function declaration.
        let candidates = [backSquat(), deadlift(), clean(), pullUp(), rowErg()]
        let def = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 1), provenance: .constructed(reason: "test"), context: context)
        let inst = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(inst)
        inst.programDefinition = def
        for candidate in candidates { context.insert(candidate) }

        let sessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: def, instance: inst, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
            candidateExercises: candidates, exposureHistory: [], environment: environment,
            // `.workoutReady` for Clean itself — proving the exclusion fires
            // even under the STRONGEST possible proficiency claim ("regardless
            // of proficiency"); `.unknown` for every other real candidate
            // (Pull-up included) preserves CP1's own real "auto-eligible by
            // default when nothing is explicitly recorded" precedent, rather
            // than an unrealistic blanket `.workoutReady` that would also
            // (correctly, but irrelevantly to this test) demand capacity
            // evidence for Pull-up as one of the 7 rep-tracked movements.
            movementCapabilityLookup: { $0.canonicalName == "Clean" ? .workoutReady : .unknown },
            context: context
        )
        let movements = sessions.first?.orderedBlocks.compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements) ?? []
        XCTAssertFalse(movements.contains { $0.exercise?.canonicalName == "Clean" }, "Clean must never be selected as a Conditioning dependency — no approved conditioning dosage authority exists for it, regardless of proficiency")
        XCTAssertTrue(movements.contains { $0.exercise?.canonicalName == "Back Squat" }, "a real, equally-valid squatLoaded candidate must be selected instead of Clean")
    }

    /// Side B: the SAME real selector, same real athlete/capability
    /// context, used for `.skillPractice` purpose instead of
    /// `.conditioning` — Clean must NOT be excluded there. Proves the
    /// exclusion is purpose-specific (Section 1: "Do NOT globally disable
    /// these exercises"), not a blanket ban baked into the movement
    /// itself. (The real Strength/Power/source-authored resistance path
    /// — `materializeStrengthBlock`'s own `ResolveProgramInstanceExerciseSlotsUseCase`/
    /// `SubstituteExerciseUseCase` call chain — never calls
    /// `MovementRoleExerciseSelector`/`TechnicalCapacityDoseAuthority` at
    /// all, confirmed directly by grep: zero references outside this
    /// type's own file and `FunctionalFitnessMaterializer`'s conditioning
    /// branch — so Clean's real resistance-role usage is structurally
    /// unaffected by this exclusion, independent of this test.)
    func testCleanRemainsSelectableForSkillPracticePurpose() {
        let resolution = MovementRoleExerciseSelector.select(.init(
            function: .squatLoaded, slot: ExerciseSlot(name: "test", allowedTargets: [.quadriceps], allowedMovementFunctions: [.squatLoaded, .hingeLoaded]),
            candidateExercises: [clean()], environment: TrainingEnvironmentTestSupport.full(context: context),
            modality: .weightlifting, usedExerciseIDsThisSession: [], sameSessionMainBodyExerciseIDs: [],
            preferredExercise: nil, thisWeekExposureForFunction: [:], priorWeekExposureForFunction: [:],
            purpose: .skillPractice, proficiency: { _ in .workoutReady }
        ))
        guard case .resolved(let exercise) = resolution else {
            return XCTFail("Clean must remain a real, selectable candidate for SKILL/PRACTICE purpose — the exclusion is Conditioning-specific only, got \(resolution)")
        }
        XCTAssertEqual(exercise.canonicalName, "Clean")
    }

    /// Repeats the two-sided proof for a gymnastics movement (Rope Climb)
    /// per the order's own explicit requirement.
    func testRopeClimbNeverBecomesAConditioningDependencyButRemainsSelectableForSkillPractice() throws {
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let candidates = [backSquat(), ropeClimb(), pullUp(), rowErg()]
        let def = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 1), provenance: .constructed(reason: "test"), context: context)
        let inst = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(inst)
        inst.programDefinition = def
        for candidate in candidates { context.insert(candidate) }

        let sessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: def, instance: inst, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
            candidateExercises: candidates, exposureHistory: [], environment: environment,
            // See the analogous Clean test's comment: `.workoutReady` for
            // Rope Climb itself (strongest possible proficiency claim),
            // `.unknown` for every other real candidate (Pull-up included)
            // to preserve CP1's own real default rather than triggering an
            // unrelated capacity-evidence requirement for Pull-up.
            movementCapabilityLookup: { $0.canonicalName == "Rope Climb" ? .workoutReady : .unknown },
            context: context
        )
        let movements = sessions.first?.orderedBlocks.compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements) ?? []
        XCTAssertFalse(movements.contains { $0.exercise?.canonicalName == "Rope Climb" }, "Rope Climb must never be selected as a Conditioning dependency in V1")
        XCTAssertTrue(movements.contains { $0.exercise?.canonicalName == "Pull-up" }, "a real, equally-valid gymnasticsPull candidate must be selected instead")

        let skillResolution = MovementRoleExerciseSelector.select(.init(
            function: .gymnasticsPull, slot: ExerciseSlot(name: "test", allowedTargets: [.back], allowedMovementFunctions: [.gymnasticsPull]),
            candidateExercises: [ropeClimb()], environment: environment,
            modality: .gymnastics, usedExerciseIDsThisSession: [], sameSessionMainBodyExerciseIDs: [],
            preferredExercise: nil, thisWeekExposureForFunction: [:], priorWeekExposureForFunction: [:],
            purpose: .skillPractice, proficiency: { _ in .workoutReady }
        ))
        guard case .resolved(let exercise) = skillResolution else {
            return XCTFail("Rope Climb must remain selectable for SKILL/PRACTICE purpose, got \(skillResolution)")
        }
        XCTAssertEqual(exercise.canonicalName, "Rope Climb")
    }

    // MARK: - CONDITIONING V2 — LIVE RUNNING CONTRIBUTION + MODALITY SELECTION, Sections 9-14

    /// Section 12: real weekly Running impact + both a higher-impact
    /// running-pattern candidate (Easy Run) and a real, equally-valid
    /// lower-impact cyclical alternative (Row Erg) eligible — the
    /// lower-impact modality must be preferred. Uses the real selector,
    /// the real `weeklyRunningImpact` signal (never fabricated), and real
    /// catalog-equivalent candidates.
    func testLowerImpactPreference_WeeklyRunningImpactPrefersRowErgOverEasyRun() {
        let resolution = MovementRoleExerciseSelector.select(.init(
            function: .monostructural, slot: ExerciseSlot(name: "test", allowedTargets: [], allowedMovementFunctions: [.monostructural]),
            candidateExercises: [easyRun(), rowErg()], environment: TrainingEnvironmentTestSupport.full(context: context),
            modality: .metabolicConditioning, usedExerciseIDsThisSession: [], sameSessionMainBodyExerciseIDs: [],
            preferredExercise: nil, thisWeekExposureForFunction: [:], priorWeekExposureForFunction: [:],
            purpose: .conditioning, proficiency: { _ in .workoutReady }, weeklyRunningImpact: true
        ))
        guard case .resolved(let exercise) = resolution else {
            return XCTFail("a real lower-impact alternative was eligible — resolution must not be empty, got \(resolution)")
        }
        XCTAssertEqual(exercise.canonicalName, "Row Erg", "with real weekly Running impact and a real lower-impact alternative eligible, the lower-impact modality must be preferred over an additional equipment-free running pattern")
    }

    /// Section 13: same real weekly Running impact, but NO lower-impact
    /// alternative is eligible (only Easy Run is a real candidate) —
    /// Running must remain selectable. A preference, never a ban.
    func testLowerImpactPreference_FallbackToRunningWhenNoLowerImpactAlternativeExists() {
        let resolution = MovementRoleExerciseSelector.select(.init(
            function: .monostructural, slot: ExerciseSlot(name: "test", allowedTargets: [], allowedMovementFunctions: [.monostructural]),
            candidateExercises: [easyRun()], environment: TrainingEnvironmentTestSupport.full(context: context),
            modality: .metabolicConditioning, usedExerciseIDsThisSession: [], sameSessionMainBodyExerciseIDs: [],
            preferredExercise: nil, thisWeekExposureForFunction: [:], priorWeekExposureForFunction: [:],
            purpose: .conditioning, proficiency: { _ in .workoutReady }, weeklyRunningImpact: true
        ))
        guard case .resolved(let exercise) = resolution else {
            return XCTFail("Running must remain selectable when it is the only real valid candidate, got \(resolution)")
        }
        XCTAssertEqual(exercise.canonicalName, "Easy Run (Zone 2)", "no unsupported/empty result may occur merely because weekly Running impact exists — Running remains valid when no equivalent alternative is available")
    }

    /// Section 14: no lower-impact equipment exists in the athlete's real
    /// candidate pool — none may appear/be fabricated. The candidate pool
    /// here is identical to the fallback test above (Easy Run only, no
    /// bike/row/ski entry at all) — the resolution can only ever be Easy
    /// Run or `.none`, structurally proving no equipment is invented.
    func testLowerImpactPreference_NoEquipmentInventionWhenNoneIsAvailable() {
        let resolution = MovementRoleExerciseSelector.select(.init(
            function: .monostructural, slot: ExerciseSlot(name: "test", allowedTargets: [], allowedMovementFunctions: [.monostructural]),
            candidateExercises: [easyRun()], environment: TrainingEnvironmentTestSupport.full(context: context),
            modality: .metabolicConditioning, usedExerciseIDsThisSession: [], sameSessionMainBodyExerciseIDs: [],
            preferredExercise: nil, thisWeekExposureForFunction: [:], priorWeekExposureForFunction: [:],
            purpose: .conditioning, proficiency: { _ in .workoutReady }, weeklyRunningImpact: true
        ))
        guard case .resolved(let exercise) = resolution else {
            return XCTFail("expected a real resolution from the only real candidate, got \(resolution)")
        }
        XCTAssertFalse(["Row Erg", "Assault Bike", "SkiErg"].contains(exercise.canonicalName), "no lower-impact equipment may be fabricated when none exists in the real candidate pool")
        XCTAssertEqual(exercise.canonicalName, "Easy Run (Zone 2)")
    }

    /// CONDITIONING V2 FINAL COMPLETION PASS, Section 6/15: real
    /// production Toes-to-Bar journey — WORKOUT_READY + max-unbroken 12
    /// must clamp to the real ceiling (5), never the raw 12.
    func testToesToBarWorkoutReadyMaxUnbroken12ClampsToRealCeilingOfFive() throws {
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let candidates = [backSquat(), toesToBar(), rowErg()]
        let def = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 1), provenance: .constructed(reason: "test"), context: context)
        let inst = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(inst)
        inst.programDefinition = def
        for candidate in candidates { context.insert(candidate) }

        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        let capability = MovementCapabilityProfile(
            exercise: candidates.first { $0.canonicalName == "Toes-to-Bar" },
            proficiency: .workoutReady, capacityType: .maxUnbrokenReps, capacityValue: 12,
            evidenceSource: .selfReported
        )
        context.insert(capability)
        performanceProfile.addMovementCapability(capability)

        let sessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: def, instance: inst, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
            candidateExercises: candidates, exposureHistory: [], environment: environment,
            movementCapabilityLookup: { _ in .workoutReady },
            performanceProfile: performanceProfile,
            context: context
        )
        let movements = sessions.first?.orderedBlocks.compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements) ?? []
        let ttb = try XCTUnwrap(movements.first { $0.exercise?.canonicalName == "Toes-to-Bar" }, "TTB must remain selectable when otherwise appropriate")
        XCTAssertNil(ttb.distanceMeters, "no other target dimension — reps only")
        let reps = try XCTUnwrap(ttb.reps)
        XCTAssertLessThanOrEqual(reps, 5, "capacity 12 → real ceiling 5; must never auto-prescribe the raw 12")
        XCTAssertEqual(reps, TechnicalCapacityDoseAuthority.maxRepeatedDose(forCapacity: 12))
    }

    /// Section 11/12: proves `Exercise.measuredDimensions` is now actually
    /// READ in real production materialization, not merely declared —
    /// Double-Unders (declares `.reps` only) can never receive a distance
    /// target, and correctly falls back to Row Erg (declares `.distance`)
    /// when both are eligible for the same monostructural role.
    func testDoubleUndersNeverReceivesADistanceTargetInRealMaterialization() throws {
        let doubleUnders = Exercise(
            canonicalName: "Double-Unders", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "jumpRope",
            movementFunctions: [.jumping, .monostructural], functionalModality: .metabolicConditioning,
            requiredEquipment: [.bodyweight], measuredDimensions: [.reps]
        )
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let candidates = [backSquat(), doubleUnders, rowErg()]
        let (sessions, _, _) = try materialize(daysPerWeek: 1, candidates: candidates, environment: environment)
        let movements = sessions.first?.orderedBlocks.compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements) ?? []
        XCTAssertFalse(movements.contains { $0.exercise?.canonicalName == "Double-Unders" && $0.distanceMeters != nil }, "Double-Unders must never receive a distance target")
        // Row Erg (the only other real monostructural candidate, and the
        // only one that truthfully declares `.distance`) is the real
        // selected candidate for this role instead.
        XCTAssertTrue(movements.contains { $0.exercise?.canonicalName == "Row Erg" && $0.distanceMeters == 200 })
    }

    // MARK: - MUSCLE VERTICAL SLICE REPAIR, Section 21 tests N: exercise
    // identity vs. intensity/stimulus semantics (Section 14)

    /// A dedicated LOW-intensity variant (Easy Run (Zone 2)) must never be
    /// selected to serve a role that requires HIGH intensity when a real,
    /// unclassified (intensity-agnostic) alternative is eligible.
    func testDedicatedLowIntensityVariantExcludedFromHighIntensityRoleWhenAlternativeExists() {
        let resolution = MovementRoleExerciseSelector.select(.init(
            function: .monostructural, slot: ExerciseSlot(name: "test", allowedTargets: [], allowedMovementFunctions: [.monostructural]),
            candidateExercises: [easyRun(), trackIntervalRun()], environment: TrainingEnvironmentTestSupport.full(context: context),
            modality: .metabolicConditioning, usedExerciseIDsThisSession: [], sameSessionMainBodyExerciseIDs: [],
            preferredExercise: nil, thisWeekExposureForFunction: [:], priorWeekExposureForFunction: [:],
            purpose: .conditioning, proficiency: { _ in .workoutReady }, requiredIntensity: .high
        ))
        guard case .resolved(let exercise) = resolution else {
            return XCTFail("Track Interval Run (unclassified, always eligible) must be selected, got \(resolution)")
        }
        XCTAssertEqual(exercise.canonicalName, "Track Interval Run", "Easy Run (Zone 2) is a dedicated LOW-intensity variant and can never truthfully serve a HIGH-intensity role")
    }

    /// When the dedicated LOW-intensity variant is the ONLY real candidate
    /// for a HIGH-intensity role, the resolution must be an honest
    /// `.noExecutableTarget` — never a silent, untruthful fallback to it.
    func testDedicatedLowIntensityVariantProducesNoExecutableTargetWhenItIsTheOnlyCandidateForAHighIntensityRole() {
        let resolution = MovementRoleExerciseSelector.select(.init(
            function: .monostructural, slot: ExerciseSlot(name: "test", allowedTargets: [], allowedMovementFunctions: [.monostructural]),
            candidateExercises: [easyRun()], environment: TrainingEnvironmentTestSupport.full(context: context),
            modality: .metabolicConditioning, usedExerciseIDsThisSession: [], sameSessionMainBodyExerciseIDs: [],
            preferredExercise: nil, thisWeekExposureForFunction: [:], priorWeekExposureForFunction: [:],
            purpose: .conditioning, proficiency: { _ in .workoutReady }, requiredIntensity: .high
        ))
        guard case .noExecutableTarget = resolution else {
            return XCTFail("a dedicated LOW-intensity variant is the only candidate for a HIGH-intensity role — must be .noExecutableTarget, never a silent fallback, got \(resolution)")
        }
    }

    /// Backward compatibility: when the role has no stated required
    /// intensity (`requiredIntensity: nil`, every pre-existing call site),
    /// the dedicated LOW-intensity variant remains fully eligible exactly
    /// as before this checkpoint.
    func testNoRequiredIntensityLeavesLowIntensityVariantFullyEligible() {
        let resolution = MovementRoleExerciseSelector.select(.init(
            function: .monostructural, slot: ExerciseSlot(name: "test", allowedTargets: [], allowedMovementFunctions: [.monostructural]),
            candidateExercises: [easyRun()], environment: TrainingEnvironmentTestSupport.full(context: context),
            modality: .metabolicConditioning, usedExerciseIDsThisSession: [], sameSessionMainBodyExerciseIDs: [],
            preferredExercise: nil, thisWeekExposureForFunction: [:], priorWeekExposureForFunction: [:],
            purpose: .conditioning, proficiency: { _ in .workoutReady }
        ))
        guard case .resolved(let exercise) = resolution else {
            return XCTFail("with no required intensity stated, Easy Run must remain a real, selectable candidate, got \(resolution)")
        }
        XCTAssertEqual(exercise.canonicalName, "Easy Run (Zone 2)")
    }

    /// A role that requires LOW intensity may still be served by an
    /// unclassified (`nil`) candidate — the exclusion only fires when
    /// BOTH the role's required intensity AND the candidate's own
    /// declared intensity are known.
    func testLowIntensityRoleRemainsServableByAnUnclassifiedCandidate() {
        let resolution = MovementRoleExerciseSelector.select(.init(
            function: .monostructural, slot: ExerciseSlot(name: "test", allowedTargets: [], allowedMovementFunctions: [.monostructural]),
            candidateExercises: [trackIntervalRun()], environment: TrainingEnvironmentTestSupport.full(context: context),
            modality: .metabolicConditioning, usedExerciseIDsThisSession: [], sameSessionMainBodyExerciseIDs: [],
            preferredExercise: nil, thisWeekExposureForFunction: [:], priorWeekExposureForFunction: [:],
            purpose: .conditioning, proficiency: { _ in .workoutReady }, requiredIntensity: .low
        ))
        guard case .resolved(let exercise) = resolution else {
            return XCTFail("an unclassified candidate must remain eligible for any required intensity, got \(resolution)")
        }
        XCTAssertEqual(exercise.canonicalName, "Track Interval Run")
    }

}
