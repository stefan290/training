import XCTest
@testable import TrainingOS

/// Pure logic, no `ModelContext` needed — `EquipmentProfile`/`IdealLoad`
/// are engine-facing value types, never persisted directly, the same
/// discipline as `DoubleProgressionEngineTests`.
final class EquipmentProfileTests: XCTestCase {
    /// `METRIC_LOAD_MODEL.md`'s own worked example: 180 lb converted to kg
    /// or a real barbell with 2.5 kg plates rounds to 82.5 kg, not the
    /// unrounded 81.646266 kg.
    func test180PoundsRoundsToNearest2Point5Kilograms() {
        let idealLoad = IdealLoad(kilograms: 180 * 0.45359237)
        let barbell = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)
        XCTAssertEqual(barbell.resolve(idealLoad), 82.5, accuracy: 0.0001)
    }

    func testRoundingDownNeverOvershoots() {
        let idealLoad = IdealLoad(kilograms: 83.7)
        let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5, roundingRule: .down)
        XCTAssertEqual(equipment.resolve(idealLoad), 82.5, accuracy: 0.0001)
    }

    func testRoundingUpNeverUndershoots() {
        let idealLoad = IdealLoad(kilograms: 83.7)
        let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5, roundingRule: .up)
        XCTAssertEqual(equipment.resolve(idealLoad), 85.0, accuracy: 0.0001)
    }

    func testExactMultipleOfIncrementIsUnchanged() {
        let idealLoad = IdealLoad(kilograms: 80.0)
        let equipment = EquipmentProfile(equipmentType: .dumbbell, smallestIncrementKg: 2.5)
        XCTAssertEqual(equipment.resolve(idealLoad), 80.0, accuracy: 0.0001)
    }

    /// `.bodyweightPlusExternal`: only the external portion rounds, and
    /// the athlete's own bodyweight is added back unrounded — rounding a
    /// bodyweight-inclusive number to a plate increment would produce an
    /// unloadable value.
    func testBodyweightPlusExternalRoundsOnlyTheExternalPortion() {
        let idealLoad = IdealLoad(kilograms: 88.3) // 73.4 kg bodyweight + 14.9 kg ideal external
        let equipment = EquipmentProfile(equipmentType: .bodyweightPlusExternal, smallestIncrementKg: 2.5, bodyweightKg: 73.4)
        // External portion 14.9 rounds to nearest 2.5 -> 15.0; bodyweight
        // stays exactly 73.4, not itself rounded.
        XCTAssertEqual(equipment.resolve(idealLoad), 88.4, accuracy: 0.0001)
    }

    /// If the ideal load is below bodyweight (a caller error, e.g. a
    /// miscalibrated profile), the external portion floors at zero rather
    /// than going negative.
    func testBodyweightPlusExternalNeverProducesNegativeExternalLoad() {
        let idealLoad = IdealLoad(kilograms: 60.0)
        let equipment = EquipmentProfile(equipmentType: .bodyweightPlusExternal, smallestIncrementKg: 2.5, bodyweightKg: 73.4)
        XCTAssertEqual(equipment.resolve(idealLoad), 73.4, accuracy: 0.0001)
    }

    /// A zero/negative increment is treated as "no rounding," never a
    /// division-by-zero crash.
    func testZeroIncrementReturnsIdealLoadUnchanged() {
        let idealLoad = IdealLoad(kilograms: 81.6466266)
        let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 0)
        XCTAssertEqual(equipment.resolve(idealLoad), 81.6466266, accuracy: 0.0001)
    }

    /// The cascading-rounding rule `METRIC_LOAD_MODEL.md` calls out
    /// explicitly: each week resolves off the *previous week's resolved*
    /// value, not a hypothetical unrounded chain — proven here with
    /// Family A's own numbers (Week 1 = 85, Week 2 = ×1.05, Week 3 =
    /// ×1.075, Week 4 = ×1.1, all off the resolved Week 1, matching
    /// `PROGRAM_REGRESSION_TEST_PLAN.md` §4.1 exactly).
    func testWeeklyResolutionCascadesOffTheResolvedWeekOneValue() {
        let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)
        let weekOneResolved = equipment.resolve(IdealLoad(kilograms: 100 * 0.85))
        XCTAssertEqual(weekOneResolved, 85, accuracy: 0.0001)

        let weekTwo = equipment.resolve(IdealLoad(kilograms: weekOneResolved * 1.05))
        let weekThree = equipment.resolve(IdealLoad(kilograms: weekOneResolved * 1.075))
        let weekFour = equipment.resolve(IdealLoad(kilograms: weekOneResolved * 1.1))
        XCTAssertEqual(weekTwo, 90, accuracy: 0.0001)
        XCTAssertEqual(weekThree, 92.5, accuracy: 0.0001)
        XCTAssertEqual(weekFour, 92.5, accuracy: 0.0001)
    }
}
