import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 10C.1: proves the exercise-catalog/movement-family foundation
/// is semantically correct and safe for substitution — never a
/// technically-overlapping-target producing a semantically wrong
/// candidate (D-10C1-8). Uses ad hoc `ExerciseSlot`s directly, never
/// touching `HypertrophyProgramGenerator`'s own day-focus tables — this
/// stage is catalog/semantics only, no 4/5-Day split construction.
@MainActor
final class CatalogSemanticFoundationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func isValid(_ candidate: Exercise, for slot: ExerciseSlot) -> Bool {
        SubstitutionValidator.isValid(candidate: candidate, for: slot)
    }

    // MARK: D — promoted exercises participate in candidate resolution

    func testPromotedExercisesSatisfyTheSameSlotsTheyAlwaysCouldHave() throws {
        let catalog = ExerciseCatalog.makeAndInsert(context: context)
        let unilateralQuadSlot = ExerciseSlot(name: "Unilateral Knee-Dominant", allowedTargets: [.quadriceps, .glutes], allowedMovementFunctions: [.squatLoaded])
        context.insert(unilateralQuadSlot)
        XCTAssertTrue(isValid(catalog.bulgarianSplitSquat, for: unilateralQuadSlot))

        let hingeSlot = ExerciseSlot(name: "Hip Hinge", allowedTargets: [.hamstrings, .glutes], allowedMovementFunctions: [.hingeLoaded])
        context.insert(hingeSlot)
        XCTAssertTrue(isValid(catalog.conventionalDeadlift, for: hingeSlot))

        let hamstringIsolationSlot = ExerciseSlot(name: "Hamstring Isolation", allowedTargets: [.hamstrings])
        context.insert(hamstringIsolationSlot)
        XCTAssertTrue(isValid(catalog.seatedLegCurl, for: hamstringIsolationSlot))

        let calfSlot = ExerciseSlot(name: "Calves", allowedTargets: [.calves])
        context.insert(calfSlot)
        XCTAssertTrue(isValid(catalog.seatedCalfRaise, for: calfSlot))

        let verticalPullSlot = ExerciseSlot(name: "Vertical Pull", allowedTargets: [.back], allowedMovementFunctions: [.verticalPullLoaded])
        context.insert(verticalPullSlot)
        XCTAssertTrue(isValid(catalog.pullUp, for: verticalPullSlot), "Pull-up keeps its existing .gymnasticsPull tag and gains .verticalPullLoaded additively")
    }

    // MARK: E — new exercises resolve from the correct slot intent

    func testNewExercisesResolveFromTheirIntendedSlotIntent() throws {
        let catalog = ExerciseCatalog.makeAndInsert(context: context)

        let verticalPushSlot = ExerciseSlot(name: "Vertical Push", allowedTargets: [.shoulders], allowedMovementFunctions: [.verticalPushLoaded])
        context.insert(verticalPushSlot)
        XCTAssertTrue(isValid(catalog.overheadPress, for: verticalPushSlot))

        let quadIsolationSlot = ExerciseSlot(name: "Quadriceps Isolation", allowedTargets: [.quadriceps])
        context.insert(quadIsolationSlot)
        XCTAssertTrue(isValid(catalog.legExtension, for: quadIsolationSlot))

        let chestIsolationSlot = ExerciseSlot(name: "Chest Isolation", allowedTargets: [.chest])
        context.insert(chestIsolationSlot)
        XCTAssertTrue(isValid(catalog.cableChestFly, for: chestIsolationSlot))

        let rearDeltSlot = ExerciseSlot(name: "Rear Delt", allowedTargets: [.rearDelt])
        context.insert(rearDeltSlot)
        XCTAssertTrue(isValid(catalog.facePull, for: rearDeltSlot))

        let verticalPullSlot = ExerciseSlot(name: "Vertical Pull", allowedTargets: [.back], allowedMovementFunctions: [.verticalPullLoaded])
        context.insert(verticalPullSlot)
        XCTAssertTrue(isValid(catalog.latPulldown, for: verticalPullSlot))

        let horizontalPullSlot = ExerciseSlot(name: "Horizontal Pull", allowedTargets: [.back], allowedMovementFunctions: [.horizontalPullLoaded])
        context.insert(horizontalPullSlot)
        XCTAssertTrue(isValid(catalog.seatedCableRow, for: horizontalPullSlot))
    }

    // MARK: F/G — horizontal pull and vertical pull are mutually exclusive

    func testHorizontalPullSlotNeverResolvesAVerticalPullOnlyExercise() throws {
        let catalog = ExerciseCatalog.makeAndInsert(context: context)
        let horizontalPullSlot = ExerciseSlot(name: "Horizontal Pull", allowedTargets: [.back], allowedMovementFunctions: [.horizontalPullLoaded])
        context.insert(horizontalPullSlot)

        XCTAssertTrue(isValid(catalog.barbellRow, for: horizontalPullSlot))
        XCTAssertTrue(isValid(catalog.seatedCableRow, for: horizontalPullSlot))
        XCTAssertFalse(isValid(catalog.latPulldown, for: horizontalPullSlot), "Lat Pulldown is vertical-pull-only — sharing .back must never be enough on its own")
        XCTAssertFalse(isValid(catalog.pullUp, for: horizontalPullSlot), "Pull-up is vertical-pull-only despite also sharing .back/.biceps")
    }

    func testVerticalPullSlotNeverResolvesAHorizontalPullOnlyExercise() throws {
        let catalog = ExerciseCatalog.makeAndInsert(context: context)
        let verticalPullSlot = ExerciseSlot(name: "Vertical Pull", allowedTargets: [.back], allowedMovementFunctions: [.verticalPullLoaded])
        context.insert(verticalPullSlot)

        XCTAssertTrue(isValid(catalog.latPulldown, for: verticalPullSlot))
        XCTAssertTrue(isValid(catalog.pullUp, for: verticalPullSlot))
        XCTAssertFalse(isValid(catalog.barbellRow, for: verticalPullSlot), "Barbell Row is horizontal-pull-only despite sharing .back/.biceps")
        XCTAssertFalse(isValid(catalog.seatedCableRow, for: verticalPullSlot))
    }

    /// A discovered, not-explicitly-requested collision this stage's own
    /// work introduced and then fixed: reusing generic `.pressLoaded`
    /// for Overhead Press would have let it satisfy the EXISTING
    /// "Horizontal Push" grouping via shared `.shoulders`/`.pressLoaded`
    /// — exactly the "technically overlapping target, semantically
    /// wrong exercise" risk D-10C1-8 warned about. `.verticalPushLoaded`
    /// fixes it; this test proves the fix, not just the new exercise's
    /// own positive case (already covered by `testNewExercisesResolveFromTheirIntendedSlotIntent`).
    func testVerticalPushNeverSatisfiesTheExistingHorizontalPushSlotGrouping() throws {
        let catalog = ExerciseCatalog.makeAndInsert(context: context)
        let horizontalPushSlot = ExerciseSlot(name: "Horizontal Push", allowedTargets: [.chest, .shoulders], allowedMovementFunctions: [.pressLoaded])
        context.insert(horizontalPushSlot)

        XCTAssertTrue(isValid(catalog.benchPress, for: horizontalPushSlot), "sanity: the real Horizontal Push candidate must still match")
        XCTAssertFalse(isValid(catalog.overheadPress, for: horizontalPushSlot), "Overhead Press shares .shoulders but is a vertical push, not horizontal — must not satisfy this slot")
    }

    // MARK: H — lateral delt and rear delt are distinguishable

    func testLateralDeltAndRearDeltSlotsAreMutuallyExclusive() throws {
        let catalog = ExerciseCatalog.makeAndInsert(context: context)
        let lateralDeltSlot = ExerciseSlot(name: "Lateral Delt", allowedTargets: [.lateralDelt])
        context.insert(lateralDeltSlot)
        let rearDeltSlot = ExerciseSlot(name: "Rear Delt", allowedTargets: [.rearDelt])
        context.insert(rearDeltSlot)

        XCTAssertTrue(isValid(catalog.dumbbellLateralRaise, for: lateralDeltSlot))
        XCTAssertFalse(isValid(catalog.facePull, for: lateralDeltSlot), "Face Pull is rear-delt, not lateral-delt")
        XCTAssertTrue(isValid(catalog.facePull, for: rearDeltSlot))
        XCTAssertFalse(isValid(catalog.dumbbellLateralRaise, for: rearDeltSlot), "Lateral Raise is lateral-delt, not rear-delt")

        // Both still satisfy a plain generic-shoulders slot — additive,
        // never a replacement of the existing coarse tag.
        let genericShoulderSlot = ExerciseSlot(name: "Shoulders", allowedTargets: [.shoulders])
        context.insert(genericShoulderSlot)
        XCTAssertTrue(isValid(catalog.dumbbellLateralRaise, for: genericShoulderSlot))
        XCTAssertTrue(isValid(catalog.facePull, for: genericShoulderSlot))
    }

    // MARK: I — equipment requirements are structured and deterministic

    func testEquipmentRequirementsAreStructuredNotFreeStrings() throws {
        let catalog = ExerciseCatalog.makeAndInsert(context: context)
        XCTAssertEqual(Set(catalog.benchPress.requiredEquipment), [.barbell, .rack, .bench])
        XCTAssertEqual(Set(catalog.backSquat.requiredEquipment), [.barbell, .rack])
        XCTAssertEqual(Set(catalog.inclineDumbbellPress.requiredEquipment), [.dumbbells, .bench])
        XCTAssertEqual(Set(catalog.latPulldown.requiredEquipment), [.cableStation])
        XCTAssertEqual(Set(catalog.pullUp.requiredEquipment), [.pullUpBar])
        // Every catalog exercise has been assigned at least one typed
        // requirement — none silently left at the pre-Stage-10C.1 empty
        // default, which would be indistinguishable from "not yet recorded."
        let allExercises: [Exercise] = [
            catalog.benchPress, catalog.inclineDumbbellPress, catalog.backSquat, catalog.wallBall, catalog.burpee,
            catalog.kettlebellSwing, catalog.thruster, catalog.pullUp, catalog.bike, catalog.row, catalog.skiErg,
            catalog.toesToBar, catalog.pushUp, catalog.handstandPushUp, catalog.deadlift, catalog.dumbbellSnatch,
            catalog.romanianDeadlift, catalog.legPress, catalog.bulgarianSplitSquat, catalog.legCurl, catalog.calfRaise,
            catalog.frontSquat, catalog.conventionalDeadlift, catalog.seatedLegCurl, catalog.seatedCalfRaise,
            catalog.barbellCurl, catalog.cableTricepsPushdown, catalog.dumbbellLateralRaise, catalog.barbellRow,
            catalog.overheadPress, catalog.legExtension, catalog.cableChestFly, catalog.facePull,
            catalog.latPulldown, catalog.seatedCableRow,
        ]
        for exercise in allExercises {
            XCTAssertFalse(exercise.requiredEquipment.isEmpty, "\(exercise.canonicalName) has no recorded equipment requirement")
        }
    }

    // MARK: J — existing substitution behavior does not regress

    func testExistingBenchPressSubstitutionStillResolvesInclineDumbbellPress() throws {
        let catalog = ExerciseCatalog.makeAndInsert(context: context)
        let horizontalPushSlot = ExerciseSlot(name: "Horizontal Push", allowedTargets: [.chest, .shoulders], allowedMovementFunctions: [.pressLoaded])
        context.insert(horizontalPushSlot)
        XCTAssertTrue(isValid(catalog.benchPress, for: horizontalPushSlot))
        XCTAssertTrue(isValid(catalog.inclineDumbbellPress, for: horizontalPushSlot), "unaffected by any Stage 10C.1 tagging change")
    }
}
