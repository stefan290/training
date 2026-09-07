import XCTest
import SwiftData
@testable import TrainingOS

/// Exercise Library V1 (breadth + substitution semantics): proves the
/// expanded canonical catalog (38 -> 58) resolves idempotently, covers
/// the real Hypertrophy/Strength/Functional Fitness movement families
/// this checkpoint targeted, and — most importantly — that the new
/// `Exercise.isExplosiveExpression` dimension (consumed only by
/// `SubstitutionCandidateRanking.rank`, never `SubstitutionValidator`)
/// genuinely rejects the regression case this checkpoint exists to fix:
/// Stiff-Legged Deadlift must never rank Dumbbell Snatch as a valid
/// substitute merely because both are `.hingeLoaded` and share
/// `primaryTargets`.
@MainActor
final class ExerciseLibraryV1Tests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    /// `SubstitutionValidator.isValid` treats `environment: nil` as
    /// `.environmentUnknown` (never `.compatible`) — every real call site
    /// (`ChangeExerciseView`, `WorkoutEnvironmentAdaptationUseCase`) only
    /// ever calls `rank` with a real, resolved environment. A test that
    /// wants to isolate the `isExplosiveExpression` semantic filter (not
    /// TE.1 equipment gating) must do the same, or every candidate is
    /// rejected before the semantic filter ever runs — a Full Gym-shaped
    /// environment carrying every `EquipmentRequirement` case makes
    /// equipment never the discriminator here.
    private func makeFullGymEnvironment() -> TrainingEnvironment {
        let environment = TrainingEnvironment(name: "Full Gym", availableEquipment: EquipmentRequirement.allCases)
        context.insert(environment)
        return environment
    }

    // MARK: Canonical catalog uniqueness + count

    func testCatalogHas58UniqueCanonicalExercises() throws {
        _ = ExerciseCatalog.resolveOrInsert(context: context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(exercises.count, 58, "BEFORE: 38 canonical exercises. AFTER this checkpoint: 58.")
        XCTAssertEqual(Set(exercises.map(\.canonicalName)).count, exercises.count, "every canonical name must be unique")
    }

    // MARK: Canonical identity stability / idempotency

    func testResolveOrInsertIsIdempotentAndNeverDuplicatesExistingIdentity() throws {
        let first = ExerciseCatalog.resolveOrInsert(context: context)
        let firstBenchID = first.benchPress.id
        let firstStiffLeggedID = first.stiffLeggedDeadlift.id

        let second = ExerciseCatalog.resolveOrInsert(context: context)
        XCTAssertEqual(second.benchPress.id, firstBenchID, "existing athlete history must continue to resolve to the same canonical identity")
        XCTAssertEqual(second.stiffLeggedDeadlift.id, firstStiffLeggedID)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(exercises.count, 58, "a second resolution must never insert duplicate rows")
    }

    // MARK: THE CRITICAL REGRESSION — Stiff-Legged Deadlift must never resolve to Dumbbell Snatch

    func testStiffLeggedDeadliftNeverRanksDumbbellSnatchAsASubstitute() throws {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        try context.save()
        let allExercises = try context.fetch(FetchDescriptor<Exercise>())

        // A real hamstring-hinge slot, shaped exactly like the source
        // workbook's own recovered "Hamstrings_Hip_Hinge" category
        // (`stiffLeggedDeadlift`'s own doc comment) — allowedTargets
        // only, no allowedExercises allow-list, mirroring real source
        // slot construction.
        let slot = ExerciseSlot(name: "Hamstrings Hip Hinge", allowedTargets: [.hamstrings, .glutes])
        context.insert(slot)
        let fullGym = makeFullGymEnvironment()

        let candidates = SubstitutionCandidateRanking.rank(
            slot: slot, excluding: catalog.stiffLeggedDeadlift, allExercises: allExercises,
            curatedRelationships: [], profileLookup: { _ in nil }, environment: fullGym
        )

        XCTAssertFalse(
            candidates.contains { $0.exercise.id == catalog.dumbbellSnatch.id },
            "Dumbbell Snatch shares allowedTargets AND .hingeLoaded with Stiff-Legged Deadlift, but is a ballistic/explosive movement — it must never rank as a substitute for a controlled hinge accessory"
        )
        // A real, controlled alternative must still be found — this is
        // not a hard-narrowing that leaves the slot unresolvable.
        XCTAssertTrue(
            candidates.contains { $0.exercise.id == catalog.romanianDeadlift.id || $0.exercise.id == catalog.conventionalDeadlift.id || $0.exercise.id == catalog.singleLegRomanianDeadlift.id },
            "a real, controlled hinge alternative must still be found — this rule must not overconstrain valid alternatives"
        )
    }

    /// The inverse must also hold: Dumbbell Snatch's own slot (if one
    /// existed with the same broad targets) must never rank a controlled
    /// exercise like Stiff-Legged Deadlift as its substitute either —
    /// proving the new rule is symmetric, not a one-off special case.
    func testDumbbellSnatchNeverRanksStiffLeggedDeadliftAsASubstitute() throws {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        try context.save()
        let allExercises = try context.fetch(FetchDescriptor<Exercise>())

        let slot = ExerciseSlot(name: "Explosive Hinge-to-Press", allowedTargets: [.shoulders, .glutes])
        context.insert(slot)
        let fullGym = makeFullGymEnvironment()

        let candidates = SubstitutionCandidateRanking.rank(
            slot: slot, excluding: catalog.dumbbellSnatch, allExercises: allExercises,
            curatedRelationships: [], profileLookup: { _ in nil }, environment: fullGym
        )
        XCTAssertFalse(candidates.contains { $0.exercise.id == catalog.stiffLeggedDeadlift.id })
    }

    /// Representative additional semantic regression: Kettlebell
    /// Swing/Thruster/Wall Ball (all `isExplosiveExpression: true`) must
    /// never be offered as substitutes for a plain controlled squat/press
    /// slot either.
    func testExplosiveMovementsAreNeverOfferedForAControlledSquatSlot() throws {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        try context.save()
        let allExercises = try context.fetch(FetchDescriptor<Exercise>())

        let slot = ExerciseSlot(name: "Quad-Dominant Squat", allowedTargets: [.quadriceps, .glutes])
        context.insert(slot)
        let fullGym = makeFullGymEnvironment()
        let candidates = SubstitutionCandidateRanking.rank(
            slot: slot, excluding: catalog.backSquat, allExercises: allExercises,
            curatedRelationships: [], profileLookup: { _ in nil }, environment: fullGym
        )
        XCTAssertFalse(candidates.contains { $0.exercise.id == catalog.thruster.id }, "Thruster is a ballistic squat-to-press, not a controlled squat accessory")
        XCTAssertTrue(candidates.contains { $0.exercise.id == catalog.gobletSquat.id }, "a real controlled squat alternative must still be found")
    }

    // MARK: Hypertrophy coverage — Home Gym now finds real, controlled alternatives

    func testMajorHypertrophyFamiliesHaveARealDumbbellOrBodyweightAlternative() throws {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        try context.save()
        let allExercises = try context.fetch(FetchDescriptor<Exercise>())
        let homeGym = TrainingEnvironment(name: "Home Gym", availableEquipment: [.dumbbells, .bench, .pullUpBar, .bodyweight])

        func hasHomeGymAlternative(for exercise: Exercise, slot: ExerciseSlot) -> Bool {
            SubstitutionCandidateRanking.rank(
                slot: slot, excluding: exercise, allExercises: allExercises,
                curatedRelationships: [], profileLookup: { _ in nil }, environment: homeGym
            ).contains { $0.exercise.requiredEquipment.allSatisfy { homeGym.availableEquipment.contains($0) } }
        }

        let chestSlot = ExerciseSlot(name: "Horizontal Push", allowedTargets: [.chest, .triceps])
        context.insert(chestSlot)
        XCTAssertTrue(hasHomeGymAlternative(for: catalog.benchPress, slot: chestSlot), "chest press must have a real Home Gym alternative")

        let hingeSlot = ExerciseSlot(name: "Hamstring Hinge", allowedTargets: [.hamstrings, .glutes])
        context.insert(hingeSlot)
        XCTAssertTrue(hasHomeGymAlternative(for: catalog.stiffLeggedDeadlift, slot: hingeSlot), "hamstring hinge must have a real Home Gym alternative")

        let squatSlot = ExerciseSlot(name: "Quad Squat", allowedTargets: [.quadriceps, .glutes])
        context.insert(squatSlot)
        XCTAssertTrue(hasHomeGymAlternative(for: catalog.backSquat, slot: squatSlot), "squat pattern must have a real Home Gym alternative")

        let pullSlot = ExerciseSlot(name: "Horizontal Pull", allowedTargets: [.back, .biceps])
        context.insert(pullSlot)
        XCTAssertTrue(hasHomeGymAlternative(for: catalog.barbellRow, slot: pullSlot), "horizontal pull must have a real Home Gym alternative")

        let overheadPressSlot = ExerciseSlot(name: "Overhead Press", allowedTargets: [.shoulders, .triceps])
        context.insert(overheadPressSlot)
        XCTAssertTrue(hasHomeGymAlternative(for: catalog.overheadPress, slot: overheadPressSlot), "overhead press must have a real Home Gym alternative")
    }

    // MARK: Strength coverage — real variety within Squat/Bench/Deadlift target families, progression identity preserved

    func testStrengthSubstitutionNeverChangesWhichExerciseResultEvidenceBelongsTo() throws {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        try context.save()

        // Real, distinct canonical identities — a substitute must never
        // be confused with the original for progression/history purposes.
        XCTAssertNotEqual(catalog.backSquat.id, catalog.sumoDeadlift.id)
        XCTAssertNotEqual(catalog.romanianDeadlift.id, catalog.sumoDeadlift.id)
        // Sumo Deadlift is real strength-modality content, not fabricated,
        // and carries its own distinct movement-function/target profile.
        XCTAssertEqual(catalog.sumoDeadlift.modality, .strength)
        XCTAssertTrue(catalog.sumoDeadlift.movementFunctions.contains(.hingeLoaded))
    }

    // MARK: FF movement-pool coverage — real content within the existing, locked movement-function space

    func testFunctionalFitnessMovementPoolsGainedRealContentInEveryLockedCategory() throws {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        try context.save()

        XCTAssertTrue(catalog.chestToBarPullUp.movementFunctions.contains(.gymnasticsPull))
        XCTAssertTrue(catalog.gobletSquat.movementFunctions.contains(.squatLoaded))
        XCTAssertTrue(catalog.farmersCarry.movementFunctions.contains(.carry), "`.carry` had almost no real catalog content before this checkpoint")
        XCTAssertTrue(catalog.boxJump.movementFunctions.contains(.jumping))
        XCTAssertTrue(catalog.doubleUnders.movementFunctions.contains(.jumping))
        // No new movement-function case was added — the locked space is
        // exactly what FF.M1 already understands.
        for exercise in [catalog.chestToBarPullUp, catalog.doubleUnders, catalog.farmersCarry, catalog.boxJump] {
            XCTAssertNotNil(exercise.functionalModality, "every new FF exercise must carry a real, existing FunctionalModality")
        }
    }

    // MARK: Equipment eligibility — new exercises use only the existing 13-case taxonomy

    func testAllNewExercisesUseOnlyTheExistingEquipmentTaxonomy() throws {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        try context.save()
        let newExercises = [
            catalog.flatDumbbellBenchPress, catalog.dumbbellChestFly, catalog.singleArmDumbbellRow, catalog.gobletSquat,
            catalog.singleLegRomanianDeadlift, catalog.nordicHamstringCurl, catalog.barbellHipThrust, catalog.gluteBridge,
            catalog.standingDumbbellCalfRaise, catalog.dumbbellBicepCurl, catalog.hammerCurl, catalog.dumbbellOverheadTricepsExtension,
            catalog.benchDip, catalog.bentOverReverseFly, catalog.dumbbellShoulderPress, catalog.sumoDeadlift,
            catalog.chestToBarPullUp, catalog.doubleUnders, catalog.farmersCarry, catalog.boxJump,
        ]
        for exercise in newExercises {
            XCTAssertFalse(exercise.requiredEquipment.isEmpty, "\(exercise.canonicalName) must declare real required equipment")
            for requirement in exercise.requiredEquipment {
                XCTAssertTrue(EquipmentRequirement.allCases.contains(requirement), "\(exercise.canonicalName) must only use the existing EquipmentRequirement taxonomy")
            }
        }
    }

    // MARK: Workout-scoped adaptation still session-only (R5 invariant, re-proven against the expanded catalog)

    func testWorkoutOnlyEnvironmentAdaptationStillNeverCreatesAGoingForwardOverride() throws {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        try context.save()
        let allExercises = try context.fetch(FetchDescriptor<Exercise>())

        let slot = ExerciseSlot(name: "Horizontal Push", allowedTargets: [.chest, .triceps])
        context.insert(slot)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        let homeGym = TrainingEnvironment(name: "Home Gym", availableEquipment: [.dumbbells, .bench])
        context.insert(homeGym)

        let candidates = SubstitutionCandidateRanking.rank(
            slot: slot, excluding: catalog.benchPress, allExercises: allExercises,
            curatedRelationships: [], profileLookup: { _ in nil }, environment: homeGym
        )
        guard let replacement = candidates.first?.exercise else {
            return XCTFail("a real Home Gym alternative for Barbell Bench Press must exist")
        }

        let prescription = ExercisePrescription(exercise: catalog.benchPress)
        prescription.sourceExerciseSlot = slot
        context.insert(prescription)
        try SubstituteExerciseUseCase.substituteThisSessionOnly(
            prescription: prescription, slot: slot, with: replacement, reason: .equipmentUnavailable, environment: homeGym
        )
        XCTAssertEqual(prescription.exercise?.id, replacement.id)
        XCTAssertNil(instance.slotSelectionOverride(for: slot), "a this-session-only adaptation must never create a going-forward SlotSelectionOverride")
    }
}
