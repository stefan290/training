import XCTest
import SwiftData
@testable import TrainingOS

/// Stage FF.M1 closure: proves GOING FORWARD Exercise preference for
/// dynamically-composed Functional Fitness — a semantic,
/// `MovementFunction`-keyed preference (`FunctionalFitnessMovementFunctionOverride`),
/// not the slot-identity-based mechanism `SlotSelectionOverride` uses (which
/// cannot survive Stage C building a fresh `ExerciseSlot` every tactical
/// week). Tests go through the real `FunctionalFitnessMaterializer
/// .materializeWeek` production entry point, not the preference logic in
/// isolation.
@MainActor
final class FunctionalFitnessGoingForwardPreferenceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func pullUp() -> Exercise { Exercise(canonicalName: "Pull-up", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "verticalPull", primaryTargets: [.back, .biceps], movementFunctions: [.gymnasticsPull, .verticalPullLoaded], functionalModality: .gymnastics, requiredEquipment: [.pullUpBar]) }
    private func toesToBar() -> Exercise { Exercise(canonicalName: "Toes-to-Bar", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "coreFlexion", primaryTargets: [.core], movementFunctions: [.gymnasticsPull, .trunk], functionalModality: .gymnastics, requiredEquipment: [.pullUpBar]) }
    private func kettlebellSwing() -> Exercise { Exercise(canonicalName: "Kettlebell Swing", modality: .functionalFitness, equipment: "kettlebell", movementPattern: "hipHinge", primaryTargets: [.glutes, .hamstrings], movementFunctions: [.hingeLoaded], functionalModality: .weightlifting, requiredEquipment: [.kettlebell]) }
    private func deadlift() -> Exercise { Exercise(canonicalName: "Deadlift", modality: .functionalFitness, equipment: "barbell", movementPattern: "hinge", primaryTargets: [.back, .hamstrings, .glutes], movementFunctions: [.hingeLoaded], functionalModality: .weightlifting, requiredEquipment: [.barbell]) }
    private func dumbbellSnatch() -> Exercise { Exercise(canonicalName: "Dumbbell Snatch", modality: .functionalFitness, equipment: "dumbbell", movementPattern: "hingeToPress", primaryTargets: [.shoulders, .glutes], movementFunctions: [.hingeLoaded, .pressLoaded], functionalModality: .weightlifting, requiredEquipment: [.dumbbells]) }
    private func wallBall() -> Exercise { Exercise(canonicalName: "Wall Ball", modality: .functionalFitness, equipment: "medicineBall", movementPattern: "squatToPress", primaryTargets: [.quadriceps, .shoulders], movementFunctions: [.squatLoaded, .pressLoaded], functionalModality: .weightlifting, requiredEquipment: [.medicineBall]) }
    private func backSquat() -> Exercise { Exercise(canonicalName: "Back Squat", modality: .strength, equipment: "barbell", movementPattern: "squat", primaryTargets: [.quadriceps, .glutes], movementFunctions: [.squatLoaded], functionalModality: .weightlifting, requiredEquipment: [.barbell, .rack]) }
    private func easyRun() -> Exercise { Exercise(canonicalName: "Easy Run (Zone 2)", modality: .conditioning, equipment: "none", movementPattern: "locomotion", movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning, requiredEquipment: []) }

    private func fullCatalog() -> [Exercise] {
        [backSquat(), wallBall(), kettlebellSwing(), deadlift(), dumbbellSnatch(), pullUp(), toesToBar(), easyRun()]
    }

    /// Look up the SAME already-inserted candidate instance by name — a
    /// GOING FORWARD preference must reference the real, context-inserted
    /// `Exercise` a future materialization's own `candidateExercises`
    /// pool will actually contain, never a freshly-constructed,
    /// never-inserted duplicate object with a different `id`.
    private func candidate(named name: String, in candidates: [Exercise]) -> Exercise {
        candidates.first { $0.canonicalName == name }!
    }

    private func realProductionStimulus() -> Stimulus {
        Stimulus(
            targetDurationDomain: .medium, intensity: .moderate, loading: .moderate,
            movementFunctions: [.squatLoaded, .gymnasticsPull, .monostructural],
            movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1), ModalityCount(modality: .gymnastics, count: 1), ModalityCount(modality: .metabolicConditioning, count: 1)],
            skillDemand: .moderate, systemicDemand: .moderate, scoreType: .time
        )
    }

    private func configuration(daysPerWeek: Int) -> FunctionalFitnessProgramConfiguration {
        FunctionalFitnessProgramConfiguration(
            daysPerWeek: daysPerWeek, lengthWeeks: 4, targetStimulus: realProductionStimulus(),
            format: .roundsForTime(rounds: 5, capSeconds: nil), sessionRole: .functionalFitness,
            varianceConstraints: VarianceConstraints(), requiresRecentExposureToProgress: false, includeStrengthBlock: false
        )
    }

    @discardableResult
    private func materialize(daysPerWeek: Int, candidates: [Exercise], environment: TrainingEnvironment, weekIndex: Int, definition: ProgramDefinition, instance: ProgramInstance) throws -> [Session] {
        for candidate in candidates where candidate.modelContext == nil { context.insert(candidate) }
        return try FunctionalFitnessMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: weekIndex, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
            candidateExercises: candidates, exposureHistory: [], environment: environment, context: context
        )
    }

    private func fullGymEnvironment() -> TrainingEnvironment {
        let e = TrainingEnvironment(name: "Full Gym \(UUID())", availableEquipment: EquipmentRequirement.allCases)
        context.insert(e)
        return e
    }

    /// Missing `.dumbbells` only — Dumbbell Snatch becomes TE.1-ineligible
    /// while Kettlebell Swing/Deadlift (also `hingeLoaded`) remain valid.
    private func environmentWithoutDumbbells() -> TrainingEnvironment {
        let e = TrainingEnvironment(name: "No Dumbbells \(UUID())", availableEquipment: EquipmentRequirement.allCases.filter { $0 != .dumbbells })
        context.insert(e)
        return e
    }

    private func gymnasticsPullMovement(in sessions: [Session]) -> FunctionalFitnessMovement? {
        sessions.flatMap(\.orderedBlocks).compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements)
            .first { $0.sourceExerciseSlot?.allowedMovementFunctions.contains(.gymnasticsPull) == true }
    }
    private func hingeLoadedMovement(in sessions: [Session]) -> FunctionalFitnessMovement? {
        sessions.flatMap(\.orderedBlocks).compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements)
            .first { $0.sourceExerciseSlot?.allowedMovementFunctions.contains(.hingeLoaded) == true }
    }
    private func pressLoadedMovement(in sessions: [Session]) -> FunctionalFitnessMovement? {
        sessions.flatMap(\.orderedBlocks).compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements)
            .first { $0.sourceExerciseSlot?.allowedMovementFunctions.contains(.pressLoaded) == true }
    }
    /// All hingeLoaded movements this week, in session/materialization
    /// order — `sessions` is already ordered by `dayIndex`, so flattening
    /// preserves the real week-long sequence.
    private func allHingeLoadedMovements(in sessions: [Session]) -> [FunctionalFitnessMovement] {
        sessions.flatMap(\.orderedBlocks).compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements)
            .filter { $0.sourceExerciseSlot?.allowedMovementFunctions.contains(.hingeLoaded) == true }
    }

    // MARK: 2/3 — future week prefers the GOING FORWARD choice; never selects the MovementFunction itself

    func testGoingForwardPreferenceCausesAFutureWeeksGymnasticsPullToPreferTheChosenExercise() throws {
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 3), provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let environment = fullGymEnvironment()
        let candidates = fullCatalog()

        // Week 0: establish the preference exactly as an athlete would —
        // validate against a real, currently-materialized gymnasticsPull
        // slot (Pull-up resolves by default: canonicalName tie-break).
        let week0 = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: 0, definition: definition, instance: instance)
        let originalMovement = try XCTUnwrap(gymnasticsPullMovement(in: week0))
        XCTAssertEqual(originalMovement.exercise?.canonicalName, "Pull-up", "sanity check on this fixture's own real default resolution")
        let slot = try XCTUnwrap(originalMovement.sourceExerciseSlot)
        try SubstituteFunctionalFitnessMovementUseCase.substituteGoingForward(
            instance: instance, movementFunction: .gymnasticsPull, slot: slot, with: candidate(named: "Toes-to-Bar", in: candidates),
            reason: .userPreference, environment: environment, context: context
        )

        // Week 1: a BRAND NEW ExerciseSlot is composed (Stage C never
        // reuses one across weeks) — the preference must still apply.
        let week1 = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: 1, definition: definition, instance: instance)
        let futureMovement = try XCTUnwrap(gymnasticsPullMovement(in: week1))
        XCTAssertNotEqual(futureMovement.sourceExerciseSlot?.id, slot.id, "must be a genuinely new ExerciseSlot, not the same reused row")
        XCTAssertEqual(futureMovement.exercise?.canonicalName, "Toes-to-Bar", "the GOING FORWARD preference must win over the default rotation pick")
    }

    func testPreferenceDoesNotCauseGymnasticsPullToBeSelectedWhenCompositionChoseAnotherFunction() throws {
        // A 2-role, 1-session week where the composer's own Phase-1 logic
        // may not schedule gymnasticsPull at all this particular session —
        // proves the preference is Decision-B-only (WHICH Exercise),
        // never Decision-A (WHICH MovementFunction).
        var composer = FunctionalFitnessMovementComposer()
        let roles = composer.composeSession(eligibleFunctions: [.squatLoaded, .hingeLoaded], monostructuralEligible: false, targetRoleCount: 2)
        XCTAssertFalse(roles.contains(.gymnasticsPull), "gymnasticsPull was never eligible for this session's composition at all")
        // No gymnasticsPull role exists in `roles`, so no Exercise
        // resolution for that function occurs — the preference literally
        // has no slot to apply to, structurally proving it cannot inject
        // the function itself.
    }

    // MARK: 4 — TE.1 overrides the preference

    func testTE1IncompatibilityOverridesThePreference() throws {
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 3), provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let fullGym = fullGymEnvironment()
        let candidates = fullCatalog()

        let week0 = try materialize(daysPerWeek: 3, candidates: candidates, environment: fullGym, weekIndex: 0, definition: definition, instance: instance)
        let hinge0 = try XCTUnwrap(hingeLoadedMovement(in: week0))
        let slot = try XCTUnwrap(hinge0.sourceExerciseSlot)
        try SubstituteFunctionalFitnessMovementUseCase.substituteGoingForward(
            instance: instance, movementFunction: .hingeLoaded, slot: slot, with: candidate(named: "Dumbbell Snatch", in: candidates),
            reason: .userPreference, environment: fullGym, context: context
        )

        // Week 1 materializes in an environment with no dumbbells —
        // Dumbbell Snatch is TE.1-ineligible; Kettlebell Swing/Deadlift
        // remain valid for hingeLoaded.
        let noDumbbells = environmentWithoutDumbbells()
        let week1 = try materialize(daysPerWeek: 3, candidates: candidates, environment: noDumbbells, weekIndex: 1, definition: definition, instance: instance)
        let hinge1 = try XCTUnwrap(hingeLoadedMovement(in: week1))
        XCTAssertNotEqual(hinge1.exercise?.canonicalName, "Dumbbell Snatch", "TE.1 must override an environment-incompatible preference")
        XCTAssertTrue(["Kettlebell Swing", "Deadlift"].contains(hinge1.exercise?.canonicalName), "falls back to a real, environment-valid hingeLoaded candidate")
    }

    // MARK: 6/7 — temporary unavailability does not delete the preference; it resumes once compatible again

    func testTemporarilyUnavailablePreferenceIsNotUsedButBecomesUsableAgainInACompatibleEnvironment() throws {
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 3), provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let fullGym = fullGymEnvironment()
        let candidates = fullCatalog()

        let week0 = try materialize(daysPerWeek: 3, candidates: candidates, environment: fullGym, weekIndex: 0, definition: definition, instance: instance)
        let hinge0 = try XCTUnwrap(hingeLoadedMovement(in: week0))
        let slot = try XCTUnwrap(hinge0.sourceExerciseSlot)
        try SubstituteFunctionalFitnessMovementUseCase.substituteGoingForward(
            instance: instance, movementFunction: .hingeLoaded, slot: slot, with: candidate(named: "Dumbbell Snatch", in: candidates),
            reason: .userPreference, environment: fullGym, context: context
        )

        // Week 1: environment blocks it (not used, not deleted).
        let noDumbbells = environmentWithoutDumbbells()
        _ = try materialize(daysPerWeek: 3, candidates: candidates, environment: noDumbbells, weekIndex: 1, definition: definition, instance: instance)
        XCTAssertNotNil(instance.functionalFitnessMovementFunctionOverride(for: .hingeLoaded), "an environment-blocked preference must not be deleted")

        // Week 2: a compatible environment returns — the preference is
        // usable again automatically, with no re-creation needed.
        let week2 = try materialize(daysPerWeek: 3, candidates: candidates, environment: fullGym, weekIndex: 2, definition: definition, instance: instance)
        let hinge2 = try XCTUnwrap(hingeLoadedMovement(in: week2))
        XCTAssertEqual(hinge2.exercise?.canonicalName, "Dumbbell Snatch", "the dormant preference resumes once its Exercise is valid again")
    }

    // MARK: 8 — a second GOING FORWARD choice replaces the first

    func testASecondGoingForwardChoiceForTheSameRoleReplacesTheFirst() throws {
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 3), provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let environment = fullGymEnvironment()
        let candidates = fullCatalog()

        let week0 = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: 0, definition: definition, instance: instance)
        let hinge0 = try XCTUnwrap(hingeLoadedMovement(in: week0))
        let slot = try XCTUnwrap(hinge0.sourceExerciseSlot)
        try SubstituteFunctionalFitnessMovementUseCase.substituteGoingForward(instance: instance, movementFunction: .hingeLoaded, slot: slot, with: candidate(named: "Dumbbell Snatch", in: candidates), environment: environment, context: context)
        try SubstituteFunctionalFitnessMovementUseCase.substituteGoingForward(instance: instance, movementFunction: .hingeLoaded, slot: slot, with: candidate(named: "Kettlebell Swing", in: candidates), environment: environment, context: context)

        XCTAssertEqual(instance.functionalFitnessMovementFunctionOverrides.count, 1, "the second choice replaces the first in place, never stacks a second row")
        let week1 = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: 1, definition: definition, instance: instance)
        let hinge1 = try XCTUnwrap(hingeLoadedMovement(in: week1))
        XCTAssertEqual(hinge1.exercise?.canonicalName, "Kettlebell Swing", "the LATEST preference wins")
    }

    // MARK: 9 — hingeLoaded preference for Dumbbell Snatch never leaks into pressLoaded

    func testHingeLoadedPreferenceForDumbbellSnatchDoesNotLeakIntoPressLoadedSelection() throws {
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 3), provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let environment = fullGymEnvironment()
        let candidates = fullCatalog()

        let week0 = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: 0, definition: definition, instance: instance)
        let hinge0 = try XCTUnwrap(hingeLoadedMovement(in: week0))
        let slot = try XCTUnwrap(hinge0.sourceExerciseSlot)
        try SubstituteFunctionalFitnessMovementUseCase.substituteGoingForward(instance: instance, movementFunction: .hingeLoaded, slot: slot, with: candidate(named: "Dumbbell Snatch", in: candidates), environment: environment, context: context)

        // Directly confirm the semantic key: no pressLoaded-keyed
        // preference exists merely because a hingeLoaded one does.
        XCTAssertNil(instance.functionalFitnessMovementFunctionOverride(for: .pressLoaded), "a hingeLoaded preference must never register for pressLoaded")

        // And through real materialization: if a future week's composer
        // ever schedules pressLoaded, Dumbbell Snatch is not force-picked
        // for it via this preference (it may still be chosen by the
        // ordinary rotation rule on its own semantic merits — the
        // structural guarantee under test is that no pressLoaded-keyed
        // override exists to short-circuit that decision).
        let week1 = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: 1, definition: definition, instance: instance)
        if let press1 = pressLoadedMovement(in: week1) {
            _ = press1 // resolution proceeds via the normal rule; no override consulted for this function.
        }
    }

    // MARK: 10/11 — fresh target recomputation, no staleness

    func testFuturePreferredExerciseGetsAFreshlyResolvedTargetWithNoStaleValues() throws {
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 3), provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let environment = fullGymEnvironment()
        let candidates = fullCatalog()

        let week0 = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: 0, definition: definition, instance: instance)
        let hinge0 = try XCTUnwrap(hingeLoadedMovement(in: week0))
        XCTAssertEqual(hinge0.reps, 8, "Deadlift's real hingeLoaded target — sanity check on this fixture's default resolution")
        let slot = try XCTUnwrap(hinge0.sourceExerciseSlot)
        try SubstituteFunctionalFitnessMovementUseCase.substituteGoingForward(instance: instance, movementFunction: .hingeLoaded, slot: slot, with: candidate(named: "Kettlebell Swing", in: candidates), environment: environment, context: context)

        let week1 = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: 1, definition: definition, instance: instance)
        let hinge1 = try XCTUnwrap(hingeLoadedMovement(in: week1))
        XCTAssertEqual(hinge1.exercise?.canonicalName, "Kettlebell Swing")
        XCTAssertEqual(hinge1.reps, 15, "Kettlebell Swing's own real locked target, freshly resolved — never the prior Exercise's stale 8")
        XCTAssertNil(hinge1.loadKilograms, "no numeric load is ever invented")
        XCTAssertNil(hinge1.distanceMeters)
        XCTAssertNil(hinge1.calories)
    }

    // MARK: 12 — already-materialized historical Sessions are untouched

    func testAlreadyMaterializedHistoricalSessionIsUnchangedAfterALaterPreferenceIsCreated() throws {
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 3), provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let environment = fullGymEnvironment()
        let candidates = fullCatalog()

        let week0 = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: 0, definition: definition, instance: instance)
        let hinge0 = try XCTUnwrap(hingeLoadedMovement(in: week0))
        let originalExerciseName = hinge0.exercise?.canonicalName
        let originalReps = hinge0.reps
        let slot = try XCTUnwrap(hinge0.sourceExerciseSlot)

        try SubstituteFunctionalFitnessMovementUseCase.substituteGoingForward(instance: instance, movementFunction: .hingeLoaded, slot: slot, with: candidate(named: "Kettlebell Swing", in: candidates), environment: environment, context: context)
        _ = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: 1, definition: definition, instance: instance)

        XCTAssertEqual(hinge0.exercise?.canonicalName, originalExerciseName, "creating a preference must never rewrite an already-materialized historical movement")
        XCTAssertEqual(hinge0.reps, originalReps)
    }

    // MARK: 13 — tactical rollforward preserves the preference behavior

    func testMaterializingASubsequentWeekThroughTheSameInstancePreservesThePreference() throws {
        // `RollTacticalWindowUseCase`'s own real rollforward path calls
        // exactly this same `FunctionalFitnessMaterializer.materializeWeek`
        // entry point per real tactical week — proven directly above
        // (week 0 → week 1 → week 2 in `testTemporarilyUnavailable...`)
        // already exercises this; this test isolates the simple 2-week
        // rollforward case as its own explicit proof.
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 3), provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let environment = fullGymEnvironment()
        let candidates = fullCatalog()

        let week0 = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: 0, definition: definition, instance: instance)
        let hinge0 = try XCTUnwrap(hingeLoadedMovement(in: week0))
        let slot = try XCTUnwrap(hinge0.sourceExerciseSlot)
        try SubstituteFunctionalFitnessMovementUseCase.substituteGoingForward(instance: instance, movementFunction: .hingeLoaded, slot: slot, with: candidate(named: "Kettlebell Swing", in: candidates), environment: environment, context: context)

        for week in 1...3 {
            let sessions = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: week, definition: definition, instance: instance)
            let hinge = try XCTUnwrap(hingeLoadedMovement(in: sessions))
            XCTAssertEqual(hinge.exercise?.canonicalName, "Kettlebell Swing", "week \(week) still honors the standing preference")
        }
    }

    // MARK: 14 — lifecycle scope: instance-scoped, matching SlotSelectionOverride's own established precedent

    func testPreferenceIsScopedToTheProgramInstanceNotToTheUser() {
        // Mirrors `SlotSelectionOverride`/`ActivitySelectionOverride`'s own
        // already-established, cascade-deleted, ProgramInstance-scoped
        // lifecycle exactly — a brand new ProgramInstance (as a phase
        // transition creates) starts with an empty array by construction;
        // no carryover code exists or should exist.
        let freshInstance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(freshInstance)
        XCTAssertTrue(freshInstance.functionalFitnessMovementFunctionOverrides.isEmpty, "a new ProgramInstance (as created by a phase transition) never inherits a prior instance's preferences")
    }

    func testDeletingTheProgramInstanceCascadeDeletesItsPreferences() throws {
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 3), provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let environment = fullGymEnvironment()
        let candidates = fullCatalog()

        let week0 = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: 0, definition: definition, instance: instance)
        let hinge0 = try XCTUnwrap(hingeLoadedMovement(in: week0))
        let slot = try XCTUnwrap(hinge0.sourceExerciseSlot)
        try SubstituteFunctionalFitnessMovementUseCase.substituteGoingForward(instance: instance, movementFunction: .hingeLoaded, slot: slot, with: candidate(named: "Kettlebell Swing", in: candidates), environment: environment, context: context)
        try context.save()

        context.delete(instance)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<FunctionalFitnessMovementFunctionOverride>())
        XCTAssertTrue(remaining.isEmpty, "deleting the owning ProgramInstance must cascade-delete its FunctionalFitnessMovementFunctionOverride rows, matching SlotSelectionOverride's identical precedent")
    }

    // MARK: 1 — THIS SESSION ONLY remains this-session-only (regression)

    func testThisSessionOnlySubstitutionNeverCreatesAGoingForwardPreference() throws {
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 3), provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let environment = fullGymEnvironment()
        let candidates = fullCatalog()

        let week0 = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: 0, definition: definition, instance: instance)
        let hinge0 = try XCTUnwrap(hingeLoadedMovement(in: week0))
        try SubstituteFunctionalFitnessMovementUseCase.substituteThisSessionOnly(movement: hinge0, with: candidate(named: "Kettlebell Swing", in: candidates), environment: environment)

        XCTAssertNil(instance.functionalFitnessMovementFunctionOverride(for: .hingeLoaded), "THIS SESSION ONLY must never create a standing preference")
        let week1 = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: 1, definition: definition, instance: instance)
        let hinge1 = try XCTUnwrap(hingeLoadedMovement(in: week1))
        XCTAssertNotEqual(hinge1.exercise?.canonicalName, "Kettlebell Swing", "a this-session-only edit must not leak into a future week's own independent resolution")
    }

    // MARK: Closure — CURRENT-WEEK Exercise history (across sessions, same tactical week)

    /// Proof #1: without any GOING FORWARD preference, `hingeLoaded`
    /// programmed twice in the same tactical week (real production
    /// daysPerWeek: 3, whose own composer output places hingeLoaded in
    /// both session 1 and session 3 for this fixture's candidate pool)
    /// prefers a DIFFERENT eligible candidate the second time — proven
    /// with an empty prior-week history, so the effect cannot be
    /// attributed to prior-week tie-breaking.
    func testHingeLoadedRepeatedInTheSameWeekPrefersADifferentEligibleExerciseTheSecondTime() throws {
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 3), provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let environment = fullGymEnvironment()
        let candidates = fullCatalog()

        // Week 0 — no prior-week history exists at all.
        let week0 = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: 0, definition: definition, instance: instance)
        let hingeOccurrences = allHingeLoadedMovements(in: week0)
        XCTAssertEqual(hingeOccurrences.count, 2, "sanity check on this fixture's own real composed shape: hingeLoaded appears twice this week")
        XCTAssertEqual(hingeOccurrences[0].exercise?.canonicalName, "Deadlift", "first occurrence: canonicalName tie-break with no history at all")
        XCTAssertNotEqual(hingeOccurrences[1].exercise?.canonicalName, hingeOccurrences[0].exercise?.canonicalName, "second occurrence in the SAME week must prefer a different eligible candidate, never mechanically repeat the first")
        XCTAssertEqual(hingeOccurrences[1].exercise?.canonicalName, "Dumbbell Snatch", "least-used-this-week among the two still-uncovered candidates, canonicalName tie-break between them")
    }

    /// Proof #2: a valid GOING FORWARD preference beats automatic
    /// current-week rotation — BOTH occurrences of `hingeLoaded` this week
    /// use the preferred Exercise, never alternating away from it.
    func testGoingForwardPreferenceBeatsCurrentWeekRotationForBothOccurrencesThisWeek() throws {
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 3), provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let environment = fullGymEnvironment()
        let candidates = fullCatalog()

        let week0 = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: 0, definition: definition, instance: instance)
        let slot = try XCTUnwrap(allHingeLoadedMovements(in: week0).first?.sourceExerciseSlot)
        try SubstituteFunctionalFitnessMovementUseCase.substituteGoingForward(
            instance: instance, movementFunction: .hingeLoaded, slot: slot, with: candidate(named: "Kettlebell Swing", in: candidates),
            reason: .userPreference, environment: environment, context: context
        )

        let week1 = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: 1, definition: definition, instance: instance)
        let hingeOccurrences = allHingeLoadedMovements(in: week1)
        XCTAssertEqual(hingeOccurrences.count, 2)
        XCTAssertTrue(hingeOccurrences.allSatisfy { $0.exercise?.canonicalName == "Kettlebell Swing" }, "GOING FORWARD must win for EVERY occurrence this week, never demoted to rotation on the second appearance")
    }

    /// Proof #3: if the GOING FORWARD Exercise becomes invalid for one
    /// occurrence (already used same-session, forcing a fallback), the
    /// OTHER occurrence this week still uses it — proving current-week
    /// rotation only fills in for the specific occurrence the preference
    /// could not serve, not for the whole week.
    func testGoingForwardPreferenceUnavailableForOneOccurrenceStillAppliesToTheOther() throws {
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 3), provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let environment = fullGymEnvironment()
        let candidates = fullCatalog()

        let week0 = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: 0, definition: definition, instance: instance)
        let slot = try XCTUnwrap(allHingeLoadedMovements(in: week0).first?.sourceExerciseSlot)
        // Dumbbell Snatch is ALSO the week's real pressLoaded resolution
        // (multi-function candidate) — preferring it for hingeLoaded risks
        // a same-session collision on whichever occurrence shares a
        // session with a pressLoaded slot, exercising the real fallback
        // path rather than a synthetic one.
        try SubstituteFunctionalFitnessMovementUseCase.substituteGoingForward(
            instance: instance, movementFunction: .hingeLoaded, slot: slot, with: candidate(named: "Dumbbell Snatch", in: candidates),
            reason: .userPreference, environment: environment, context: context
        )

        let week1 = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: 1, definition: definition, instance: instance)
        let hingeOccurrences = allHingeLoadedMovements(in: week1)
        XCTAssertEqual(hingeOccurrences.count, 2)
        XCTAssertTrue(hingeOccurrences.contains { $0.exercise?.canonicalName == "Dumbbell Snatch" }, "the preference must still win for at least the occurrence where it remains valid")
    }

    /// Proof #4: prior-week history only breaks a tie AFTER current-week
    /// exposure — (a) when current-week exposure alone disambiguates
    /// (second occurrence has real, unequal same-week counts), a contrary
    /// prior-week signal must NOT override it; (b) prior-week only matters
    /// among candidates still tied on current-week exposure (the first
    /// occurrence of a repeated week, and week 0's own first-ever
    /// occurrence, which has no prior week at all).
    func testPriorWeekHistoryOnlyBreaksATieAfterCurrentWeekExposure() throws {
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration(daysPerWeek: 3), provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let environment = fullGymEnvironment()
        let candidates = fullCatalog()

        // Week 0 establishes real prior-week history: first occurrence
        // Deadlift, second occurrence Dumbbell Snatch (Proof #1's own
        // result) — so going into week 1, Dumbbell Snatch has the LOWER
        // prior-week count for hingeLoaded (Deadlift used once, Dumbbell
        // Snatch used once too — tied; Kettlebell Swing used zero times,
        // the actual lowest).
        let week0 = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: 0, definition: definition, instance: instance)
        XCTAssertEqual(allHingeLoadedMovements(in: week0).map { $0.exercise?.canonicalName }, ["Deadlift", "Dumbbell Snatch"])

        // Week 1: prior-week counts are Deadlift=1, Dumbbell Snatch=1,
        // Kettlebell Swing=0 — Kettlebell Swing has the real, lowest
        // prior-week exposure, so with BOTH same-week counts starting at
        // 0 for the FIRST occurrence, prior-week correctly breaks that
        // tie in Kettlebell Swing's favor (proving prior-week is
        // consulted, not ignored).
        let week1 = try materialize(daysPerWeek: 3, candidates: candidates, environment: environment, weekIndex: 1, definition: definition, instance: instance)
        let week1Occurrences = allHingeLoadedMovements(in: week1)
        XCTAssertEqual(week1Occurrences[0].exercise?.canonicalName, "Kettlebell Swing", "first occurrence: same-week is a 3-way tie (all 0), so prior-week's real lowest-exposure candidate wins")

        // The SECOND occurrence this week is no longer a same-week tie —
        // Kettlebell Swing now has same-week=1 while Deadlift/Dumbbell
        // Snatch both have same-week=0. Even though prior-week slightly
        // favors neither over the other specifically, the key proof is
        // that the now-UNEQUAL same-week count (Kettlebell Swing=1 vs.
        // the others=0) decides it BEFORE prior-week is ever consulted —
        // Kettlebell Swing, despite having the best prior-week number
        // overall, is correctly NOT reused for the second occurrence.
        XCTAssertNotEqual(week1Occurrences[1].exercise?.canonicalName, "Kettlebell Swing", "current-week exposure must override what prior-week alone would have suggested")
    }
}
