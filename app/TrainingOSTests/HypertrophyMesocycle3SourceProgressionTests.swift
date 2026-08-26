import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 10R.3A: the source-derived test matrix proving the restored
/// 3-Day Full Body / Mesocycle 3 "Resensitization" content reproduces the
/// real recovered workbook exactly — day/category structure (22 slots, no
/// "Chest Isolation or Triceps"), no superset mechanic, load (1.0/1.05),
/// RIR (3,3), set baselines, the real 22-row rating-pairing web, exactly
/// 2 progressive weeks + 1 deload (`lengthWeeks == 3`), and deload
/// routing. Mirrors `HypertrophyMesocycle2SourceProgressionTests`'s own
/// discipline; every fixture RM is CONSTRUCTED (the real workbook ships
/// with blank RM cells).
@MainActor
final class HypertrophyMesocycle3SourceProgressionTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()
    let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func generateMesocycle2() throws -> ProgramDefinition {
        try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 3, split: .fullBody, phaseType: .metaboliteFocus),
            provenance: .constructed(reason: "test fixture"), context: context
        )
    }

    private func generateMesocycle3() throws -> ProgramDefinition {
        try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 3, split: .fullBody, phaseType: .resensitization),
            provenance: .constructed(reason: "test fixture"), context: context
        )
    }

    // MARK: 1 — Mesocycle 2 content is unchanged by this stage

    func testMesocycle2ContentIsUnchangedByThisStage() throws {
        let definition = try generateMesocycle2()
        XCTAssertEqual(definition.lengthWeeks, 5, "Mesocycle 2 still 4 progressive + 1 deload, never shortened")
        let pushSlots = try XCTUnwrap(definition.orderedTemplateSessions.first).orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates)
        XCTAssertEqual(pushSlots.count, 9, "Mesocycle 2 still has 9 slots/day, unaffected by Mesocycle 3's phase-aware week construction")
        for slot in pushSlots {
            guard case .rmBased(let payload) = try XCTUnwrap(slot.rules?.loadRule) else { return XCTFail("expected .rmBased") }
            XCTAssertEqual(payload.laterWeekMultipliers, [1.05, 1.075, 1.1], "Mesocycle 2 still uses the shared 3-entry multiplier array")
        }
    }

    // MARK: 2 — Mesocycle 3 resolves as Resensitization with distinct content

    func testMesocycle3ResolvesAsResensitizationWithDistinctContent() throws {
        let definition = try generateMesocycle3()
        XCTAssertEqual(definition.hypertrophyConfiguration?.phaseType, .resensitization)
        XCTAssertTrue(definition.name.contains("Resensitization"))
    }

    // MARK: 3/4/5 — exact Day 1/2/3 category sequences; 4 — exact 7/7/8 slot counts

    func testExactDayCategorySequencesAndSlotCounts() throws {
        let definition = try generateMesocycle3()
        let expected: [(String, [String])] = [
            ("Push Emphasis", [
                "Horizontal Push", "Incline Push or Front Delts", "Side Delts",
                "Vertical Pull", "Horizontal Pull", "Hamstrings Isolation", "Quads",
            ]),
            ("Legs Emphasis", [
                "Quads", "Hamstrings Hip Hinge", "Side Delts",
                "Vertical Pull", "Horizontal Pull", "Incline Push or Front Delts", "Horizontal Push",
            ]),
            ("Pull Emphasis", [
                "Vertical Pull", "Horizontal Pull", "Rear Delts or Side Delts", "Biceps",
                "Horizontal Push", "Incline Push", "Glutes", "Hamstrings Isolation",
            ]),
        ]
        for (dayName, categories) in expected {
            let session = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == dayName })
            let slots = session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates)
            XCTAssertEqual(slots.map { $0.exerciseSlot?.name }, categories, dayName)
        }
        XCTAssertFalse(
            definition.orderedTemplateSessions.contains { session in
                session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).contains { $0.exerciseSlot?.name == "Chest Isolation or Triceps" }
            },
            "\"Chest Isolation or Triceps\" is confirmed absent from Mesocycle 3 — never fabricated back in"
        )
    }

    // MARK: 5 — exact 22 total source slots

    func testExactlyTwentyTwoTotalSourceSlots() throws {
        let definition = try generateMesocycle3()
        let totalSlots = definition.orderedTemplateSessions.flatMap { $0.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates) }.count
        XCTAssertEqual(totalSlots, 22)
    }

    // MARK: 6 — exact Week-1 baseline sets per source row

    func testExactWeekOneBaselineSetsPerRow() throws {
        let definition = try generateMesocycle3()
        let expectedSetsByDay: [[Int]] = [
            [3, 3, 2, 2, 2, 1, 1], // Push
            [3, 3, 2, 2, 2, 1, 1], // Legs
            [3, 3, 3, 2, 2, 2, 1, 1], // Pull
        ]
        for (dayIndex, session) in definition.orderedTemplateSessions.enumerated() {
            let slots = session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates)
            let sets: [Int?] = slots.map {
                guard case .autoregulated(let config) = $0.rules?.setCountRule else { return nil }
                return config.baselineSets
            }
            XCTAssertEqual(sets, expectedSetsByDay[dayIndex], "day \(dayIndex)")
        }
    }

    // MARK: 7 — exact source rating-pairing table

    func testExactRatingPairingTable() throws {
        let definition = try generateMesocycle3()
        let templatesByDay = definition.orderedTemplateSessions.map { $0.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates) }
        XCTAssertEqual(HypertrophyProgramGenerator.threeDayFullBodyMesocycle3RatingPairings.count, 22, "one pairing per slot, exactly")
        for pairing in HypertrophyProgramGenerator.threeDayFullBodyMesocycle3RatingPairings {
            let slot = templatesByDay[pairing.dayIndex][pairing.slotIndex]
            let pairedSlot = templatesByDay[pairing.pairedDayIndex][pairing.pairedSlotIndex]
            XCTAssertEqual(slot.pairedSlot?.id, pairedSlot.id, "(\(pairing.dayIndex),\(pairing.slotIndex)) -> (\(pairing.pairedDayIndex),\(pairing.pairedSlotIndex))")
        }
    }

    // MARK: 8 — zero supersets

    func testZeroSupersetsAnywhereInMesocycle3() throws {
        let definition = try generateMesocycle3()
        for session in definition.orderedTemplateSessions {
            for slot in session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates) {
                XCTAssertEqual(slot.deloadWeightAction, .standard, "no Mesocycle-2-style superset omission leaked into Mesocycle 3")
                XCTAssertEqual(slot.deloadRepAction, .standard)
                guard case .rmBased(let payload) = slot.rules?.loadRule else { return XCTFail("expected .rmBased") }
                XCTAssertEqual(payload.weekOneFactor, 1.0, accuracy: 0.0001, "every Mesocycle 3 row uses the primary 1.0 factor — no 0.6 superset-partner factor anywhere")
                guard case .autoregulated(let config) = slot.rules?.setCountRule else { return XCTFail("expected .autoregulated") }
                XCTAssertNil(config.freezeAfterWeek, "no M2 freeze-after-week behavior survives the transition")
            }
        }
    }

    // MARK: 9 — .rm10 requirement

    func testRMTypeIsRM10() throws {
        let definition = try generateMesocycle3()
        for session in definition.orderedTemplateSessions {
            for slot in session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates) {
                guard case .rmBased(let payload) = slot.rules?.loadRule else { return XCTFail("expected .rmBased") }
                XCTAssertEqual(payload.rmType, .rm10)
            }
        }
    }

    // MARK: 11 — Week-1 load factor = 1.0

    func testWeekOneLoadFactorIsOnePointZero() throws {
        let definition = try generateMesocycle3()
        let session = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let horizontalPush = try XCTUnwrap(session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).first { $0.exerciseSlot?.name == "Horizontal Push" })
        guard case .rmBased(let payload) = try XCTUnwrap(horizontalPush.rules?.loadRule) else { return XCTFail() }
        XCTAssertEqual(payload.weekOneFactor, 1.0, accuracy: 0.0001)
        XCTAssertEqual(payload.laterWeekMultipliers, [1.05], "Mesocycle 3's own shorter multiplier array — never the shared 3-entry M1/M2 array")
    }

    // MARK: 12 — Week-2 multiplier = 1.05 off the resolved Week-1 anchor

    func testWeekTwoLoadIsWeekOneAnchorTimesOnePointZeroFive() throws {
        let definition = try generateMesocycle3()
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let session = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let templateID = try XCTUnwrap(session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).first { $0.exerciseSlot?.name == "Horizontal Push" }).id

        let weekOne = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )
        let weekOnePrescription = try XCTUnwrap(weekOne.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).first { $0.sourcePrescriptionTemplate?.id == templateID })
        let weekOneWeight = try XCTUnwrap(weekOnePrescription.orderedSetPrescriptions.first?.targetWeight)
        XCTAssertEqual(weekOneWeight, equipment.resolve(IdealLoad(kilograms: 100 * 1.0)), accuracy: 0.0001)

        let weekTwo = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 1, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100, weekOneResolvedWeightKg: weekOneWeight, previousWeekSetCount: 3, autoregulationRating: 0) },
            context: context
        )
        let weekTwoPrescription = try XCTUnwrap(weekTwo.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).first { $0.sourcePrescriptionTemplate?.id == templateID })
        XCTAssertEqual(weekTwoPrescription.orderedSetPrescriptions.first?.targetWeight ?? -1, equipment.resolve(IdealLoad(kilograms: weekOneWeight * 1.05)), accuracy: 0.0001)
    }

    // MARK: 13 — RIR 3 / RIR 3, never a fabricated rep count

    func testRIRThreeBothWeeksNeverFabricatesRepCount() throws {
        let definition = try generateMesocycle3()
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let session = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let templateID = try XCTUnwrap(session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).first { $0.exerciseSlot?.name == "Horizontal Push" }).id

        for weekIndex in [0, 1] {
            let result = StrengthMaterializer.materializeWeek(
                definition: definition, instance: instance, weekIndex: weekIndex, isDeload: false,
                startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
                slotContext: { _ in .init(rmKilograms: 100, weekOneResolvedWeightKg: 100, previousWeekSetCount: 3, autoregulationRating: 0) },
                context: context
            )
            let prescription = try XCTUnwrap(result.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).first { $0.sourcePrescriptionTemplate?.id == templateID })
            XCTAssertEqual(prescription.orderedSetPrescriptions.first?.targetRir, 3, "week \(weekIndex + 1)")
            XCTAssertNil(prescription.orderedSetPrescriptions.first?.repRangeLow, "never a fabricated rep count, week \(weekIndex + 1)")
        }
    }

    // MARK: 14/15/16 — exactly 2 progressive weeks, 1 deload week, lengthWeeks == 3

    func testExactlyTwoProgressiveWeeksOneDeloadWeekLengthWeeksThree() throws {
        let definition = try generateMesocycle3()
        XCTAssertEqual(definition.lengthWeeks, 3)
        let weeks = definition.orderedWeeks
        XCTAssertEqual(weeks.count, 3)
        XCTAssertEqual(weeks.map(\.isDeload), [false, false, true], "2 progressive weeks then exactly 1 deload — never Mesocycle 1/2's 4+1")
    }

    // MARK: 17 — SourceCompatibleDeloadStrategy routing

    func testDeloadRoutesThroughSourceCompatibleDeloadStrategy() throws {
        let definition = try generateMesocycle3()
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition

        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 2, isDeload: true,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(weekOneResolvedWeightKg: 100) }, context: context
        )
        // 3-Day Full Body's day-position deload boundary (`ceil(dayCount/2)`
        // = 2): days 0-1 keep the full Week-1 weight, day 2 is halved —
        // the same mechanism Mesocycle 1/2 already use, unmodified.
        let day0 = try XCTUnwrap(result.sessions.first { $0.name == "Push Emphasis" })
        let day2 = try XCTUnwrap(result.sessions.first { $0.name == "Pull Emphasis" })
        let day0Weight = try XCTUnwrap(day0.orderedBlocks.flatMap(\.orderedPrescriptions).first?.orderedSetPrescriptions.first?.targetWeight)
        let day2Weight = try XCTUnwrap(day2.orderedBlocks.flatMap(\.orderedPrescriptions).first?.orderedSetPrescriptions.first?.targetWeight)
        XCTAssertEqual(day0Weight, equipment.resolve(IdealLoad(kilograms: 100)), accuracy: 0.0001, "day 0 keeps full Week-1 weight during deload")
        XCTAssertEqual(day2Weight, equipment.resolve(IdealLoad(kilograms: 50)), accuracy: 0.0001, "day 2 is halved during deload")
    }
}
