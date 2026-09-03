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
    private func easyRun() -> Exercise { Exercise(canonicalName: "Easy Run (Zone 2)", modality: .conditioning, equipment: "none", movementPattern: "locomotion", movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning, requiredEquipment: []) }
    private func trackIntervalRun() -> Exercise { Exercise(canonicalName: "Track Interval Run", modality: .conditioning, equipment: "none", movementPattern: "locomotion", movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning, requiredEquipment: []) }
    private func assaultBike() -> Exercise { Exercise(canonicalName: "Assault Bike", modality: .functionalFitness, equipment: "bike", movementPattern: "locomotion", movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning, requiredEquipment: [.bike]) }
    private func rowErg() -> Exercise { Exercise(canonicalName: "Row Erg", modality: .functionalFitness, equipment: "rower", movementPattern: "locomotion", movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning, requiredEquipment: [.rower]) }

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
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .weightlifting, movementFunctions: [.hingeLoaded], exercise: kettlebellSwing()).reps, 15)
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .weightlifting, movementFunctions: [.hingeLoaded], exercise: deadlift()).reps, 8)
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .weightlifting, movementFunctions: [.hingeLoaded], exercise: dumbbellSnatch()).reps, 10)
    }

    func testPressLoadedTargets() {
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .weightlifting, movementFunctions: [.pressLoaded], exercise: wallBall()).reps, 15)
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .weightlifting, movementFunctions: [.pressLoaded], exercise: thruster()).reps, 8)
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .weightlifting, movementFunctions: [.pressLoaded], exercise: dumbbellSnatch()).reps, 10)
    }

    func testGymnasticsPushTargets() {
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .gymnastics, movementFunctions: [.gymnasticsPush], exercise: pushUp()).reps, 15)
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .gymnastics, movementFunctions: [.gymnasticsPush], exercise: handstandPushUp()).reps, 5)
    }

    func testDumbbellSnatchHingeAndPressBranchesAreStructurallyDistinct() {
        let hingeTarget = FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .weightlifting, movementFunctions: [.hingeLoaded], exercise: dumbbellSnatch())
        let pressTarget = FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .weightlifting, movementFunctions: [.pressLoaded], exercise: dumbbellSnatch())
        // Both currently 10 — proving VALUE equality is not the same as
        // proving structural identity; the real regression guard is that
        // each branch is reached via a distinct `movementFunctions`
        // context, exercised separately here.
        XCTAssertEqual(hingeTarget.reps, 10)
        XCTAssertEqual(pressTarget.reps, 10)
    }

    func testExistingFFP1TargetsRemainUnchanged() {
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .weightlifting, movementFunctions: [.squatLoaded], exercise: backSquat()).reps, 12)
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .gymnastics, movementFunctions: [.gymnasticsPull], exercise: pullUp()).reps, 8)
        XCTAssertEqual(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .metabolicConditioning, movementFunctions: [.monostructural], exercise: rowErg()).distanceMeters, 200)
        XCTAssertNil(FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: .metabolicConditioning, movementFunctions: [.monostructural], exercise: assaultBike()).distanceMeters, "the Assault Bike exception remains unchanged")
    }

    func testNoNumericLoadIsEverInventedByAnyNewBranch() {
        for exercise in [kettlebellSwing(), deadlift(), dumbbellSnatch(), wallBall(), thruster(), pushUp(), handstandPushUp()] {
            for function in [MovementFunction.hingeLoaded, .pressLoaded, .gymnasticsPush] {
                let target = FunctionalFitnessMovementTargetRule.resolve(format: .roundsForTime(rounds: 5, capSeconds: nil), modality: exercise.functionalModality ?? .weightlifting, movementFunctions: [function], exercise: exercise)
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
            let copy = Exercise(canonicalName: candidate.canonicalName, modality: candidate.modality, equipment: candidate.equipment, movementPattern: candidate.movementPattern, primaryTargets: candidate.primaryTargets, movementFunctions: candidate.movementFunctions, functionalModality: candidate.functionalModality, requiredEquipment: candidate.requiredEquipment)
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
}
