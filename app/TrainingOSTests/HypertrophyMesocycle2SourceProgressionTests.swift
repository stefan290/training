import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 10R.2A: the source-derived test matrix proving the restored
/// 3-Day Full Body / Mesocycle 2 "Metabolite Focus" content reproduces
/// the real recovered workbook exactly — day/category structure, the
/// superset mechanic, load (0.75/0.6), RIR (3,3,2,1), set baselines, the
/// real rating-pairing web, and deload (partner omitted). Mirrors
/// `HypertrophyMesocycle1SourceProgressionTests`'s own discipline; every
/// fixture RM is CONSTRUCTED (the real workbook ships with blank RM
/// cells).
@MainActor
final class HypertrophyMesocycle2SourceProgressionTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()
    let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func generateMesocycle1() throws -> ProgramDefinition {
        try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 3, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: context
        )
    }

    private func generateMesocycle2() throws -> ProgramDefinition {
        try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 3, split: .fullBody, phaseType: .metaboliteFocus),
            provenance: .constructed(reason: "test fixture"), context: context
        )
    }

    // MARK: 1 — Mesocycle 1 content is unchanged

    func testMesocycle1ContentIsUnchangedByThisStage() throws {
        let definition = try generateMesocycle1()
        XCTAssertEqual(definition.orderedTemplateSessions.map(\.name), ["Push Emphasis", "Legs Emphasis", "Pull Emphasis"])
        let pushSlots = try XCTUnwrap(definition.orderedTemplateSessions.first).orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates)
        XCTAssertEqual(pushSlots.count, 8, "Mesocycle 1 still has 8 slots/day, never 9 — no superset row leaked in")
        for slot in pushSlots {
            guard case .rmBased(let payload) = try XCTUnwrap(slot.rules?.loadRule) else { return XCTFail("expected .rmBased") }
            XCTAssertEqual(payload.weekOneFactor, 0.85, accuracy: 0.0001, "\(slot.exerciseSlot?.name ?? "") still uses Mesocycle 1's 0.85 factor")
            XCTAssertEqual(slot.deloadWeightAction, .standard, "no Mesocycle 2 superset-omission logic leaked into Mesocycle 1")
        }
    }

    // MARK: 2 — Mesocycle 2 resolves as Metabolite Focus

    func testMesocycle2ResolvesAsMetaboliteFocusWithDistinctContentFromMesocycle1() throws {
        let definition = try generateMesocycle2()
        XCTAssertEqual(definition.hypertrophyConfiguration?.phaseType, .metaboliteFocus)
        XCTAssertTrue(definition.name.contains("Metabolite Focus"))
        let pushSlots = try XCTUnwrap(definition.orderedTemplateSessions.first).orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates)
        XCTAssertEqual(pushSlots.count, 9, "Mesocycle 2 has 9 slots/day — the 8 Mesocycle 1 categories plus 1 superset-partner row")
    }

    // MARK: 3/4/5 — exact Day 1/2/3 category sequences

    func testExactDayCategorySequences() throws {
        let definition = try generateMesocycle2()
        let expected: [(String, [String])] = [
            ("Push Emphasis", [
                "Horizontal Push", "Chest Isolation or Triceps", "Incline Push or Front Delts", "Incline Push or Front Delts",
                "Side Delts", "Vertical Pull", "Horizontal Pull", "Hamstrings Isolation", "Quads",
            ]),
            ("Legs Emphasis", [
                "Quads", "Quads", "Hamstrings Hip Hinge", "Side Delts", "Side Delts",
                "Vertical Pull", "Horizontal Pull", "Incline Push or Front Delts", "Horizontal Push",
            ]),
            ("Pull Emphasis", [
                "Vertical Pull", "Horizontal Pull", "Rear Delts or Side Delts", "Biceps", "Biceps",
                "Horizontal Push", "Incline Push", "Glutes", "Hamstrings Isolation",
            ]),
        ]
        for (dayName, categories) in expected {
            let session = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == dayName })
            let slots = session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates)
            XCTAssertEqual(slots.map { $0.exerciseSlot?.name }, categories, dayName)
        }
    }

    // MARK: 6 — exact Week-1 baseline sets per source row

    func testExactWeekOneBaselineSetsPerRow() throws {
        let definition = try generateMesocycle2()
        let expectedSetsByDay: [[Int]] = [
            [4, 4, 4, 4, 3, 3, 3, 2, 2], // Push
            [4, 4, 4, 3, 3, 3, 3, 2, 2], // Legs
            [4, 4, 4, 3, 3, 3, 3, 2, 2], // Pull
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
        let definition = try generateMesocycle2()
        let templatesByDay = definition.orderedTemplateSessions.map { $0.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates) }
        for pairing in HypertrophyProgramGenerator.threeDayFullBodyMesocycle2RatingPairings {
            let slot = templatesByDay[pairing.dayIndex][pairing.slotIndex]
            let pairedSlot = templatesByDay[pairing.pairedDayIndex][pairing.pairedSlotIndex]
            XCTAssertEqual(slot.pairedSlot?.id, pairedSlot.id, "(\(pairing.dayIndex),\(pairing.slotIndex)) -> (\(pairing.pairedDayIndex),\(pairing.pairedSlotIndex))")
        }
    }

    // MARK: 8 — exact source superset pair per day

    func testExactSupersetPairPerDay() throws {
        let definition = try generateMesocycle2()
        let expectedPartnerSlotIndex = [2, 4, 4] // Push, Legs, Pull — 0-indexed
        for (dayIndex, session) in definition.orderedTemplateSessions.enumerated() {
            let slots = session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates)
            let partnerIndex = try XCTUnwrap(slots.firstIndex { slot in
                guard case .rmBased(let payload) = slot.rules?.loadRule else { return false }
                return abs(payload.weekOneFactor - 0.6) < 0.0001
            })
            XCTAssertEqual(partnerIndex, expectedPartnerSlotIndex[dayIndex], "day \(dayIndex)")
            XCTAssertEqual(slots.filter { slot in
                guard case .rmBased(let payload) = slot.rules?.loadRule else { return false }
                return abs(payload.weekOneFactor - 0.6) < 0.0001
            }.count, 1, "exactly one superset partner per day")
        }
    }

    // MARK: 9 — primary Week-1 factor = 0.75

    func testPrimaryWeekOneFactorIs075() throws {
        let definition = try generateMesocycle2()
        let session = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let horizontalPush = try XCTUnwrap(session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).first { $0.exerciseSlot?.name == "Horizontal Push" })
        guard case .rmBased(let payload) = try XCTUnwrap(horizontalPush.rules?.loadRule) else { return XCTFail() }
        XCTAssertEqual(payload.weekOneFactor, 0.75, accuracy: 0.0001)
    }

    // MARK: 10/11 — superset partner Week-1 factor = 0.60, uses its OWN RM

    func testSupersetPartnerWeekOneFactorIs060AndUsesItsOwnRM() throws {
        let definition = try generateMesocycle2()
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let session = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let slots = session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates)
        let primaryTemplate = slots[1]
        let partnerTemplate = slots[2]
        guard case .rmBased(let payload) = try XCTUnwrap(partnerTemplate.rules?.loadRule) else { return XCTFail() }
        XCTAssertEqual(payload.weekOneFactor, 0.6, accuracy: 0.0001)
        XCTAssertEqual(partnerTemplate.deloadWeightAction, .omit)
        XCTAssertEqual(partnerTemplate.deloadRepAction, .omit)

        let primarySlotID = try XCTUnwrap(primaryTemplate.exerciseSlot).id
        let partnerSlotID = try XCTUnwrap(partnerTemplate.exerciseSlot).id
        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { slot in
                if slot.id == primarySlotID { return .init(rmKilograms: 100) }
                if slot.id == partnerSlotID { return .init(rmKilograms: 40) }
                return .init(rmKilograms: 999)
            }, context: context
        )
        let partnerPrescription = try XCTUnwrap(result.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).first { $0.sourceExerciseSlot?.id == partnerSlotID })
        let primaryPrescription = try XCTUnwrap(result.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).first { $0.sourceExerciseSlot?.id == primarySlotID })
        XCTAssertEqual(partnerPrescription.orderedSetPrescriptions.first?.targetWeight ?? -1, equipment.resolve(IdealLoad(kilograms: 40 * 0.6)), accuracy: 0.0001, "the partner's own RM, never the primary's")
        XCTAssertNotEqual(partnerPrescription.orderedSetPrescriptions.first?.targetWeight, primaryPrescription.orderedSetPrescriptions.first?.targetWeight)
    }

    // MARK: 12-15 — RIR schedule 3,3,2,1, never a fabricated rep count

    func testRIRScheduleAcrossWeeksNeverFabricatesRepCount() throws {
        let definition = try generateMesocycle2()
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let session = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let templateID = try XCTUnwrap(session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).first { $0.exerciseSlot?.name == "Horizontal Push" }).id

        for (weekIndex, expectedRir) in [3, 3, 2, 1].enumerated() {
            let result = StrengthMaterializer.materializeWeek(
                definition: definition, instance: instance, weekIndex: weekIndex, isDeload: false,
                startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
                slotContext: { _ in .init(rmKilograms: 100, weekOneResolvedWeightKg: 75, previousWeekSetCount: 4, autoregulationRating: 0) },
                context: context
            )
            let prescription = try XCTUnwrap(result.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).first { $0.sourcePrescriptionTemplate?.id == templateID })
            XCTAssertEqual(prescription.orderedSetPrescriptions.first?.targetRir, expectedRir, "week \(weekIndex + 1)")
            XCTAssertNil(prescription.orderedSetPrescriptions.first?.repRangeLow, "never a fabricated rep count, week \(weekIndex + 1)")
        }
    }

    // MARK: 16/17 — no fabricated rep prescription anywhere; actual reps remain athlete output

    func testNoFabricatedRepPrescriptionAndActualRepsRemainAthleteOutput() throws {
        _ = ExerciseCatalog.resolveOrInsert(context: context) // resolves `.exercise` for every slot, needed by `LogSetUseCase` below
        let definition = try generateMesocycle2()
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)

        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )
        for prescription in result.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions) {
            for setPrescription in prescription.orderedSetPrescriptions {
                XCTAssertNil(setPrescription.repRangeLow, "\(prescription.exercise?.canonicalName ?? "") must never have a fabricated rep count")
            }
        }

        let firstPrescription = try XCTUnwrap(result.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).first { !$0.orderedSetPrescriptions.isEmpty })
        let setPrescription = try XCTUnwrap(firstPrescription.orderedSetPrescriptions.first)
        _ = try LogSetUseCase.logSet(
            setIndex: 0, weight: setPrescription.targetWeight ?? 50, reps: 8, targetRir: setPrescription.targetRir, actualRir: 2,
            prBand: nil, scoringDirection: .higherIsBetter, context: .rx, setPrescription: setPrescription,
            exercisePrescription: firstPrescription, exercise: try XCTUnwrap(firstPrescription.exercise), performanceProfile: performanceProfile,
            completedAt: Date(), modelContext: context
        )
        XCTAssertEqual(firstPrescription.loggedSetResults.first?.reps, 8, "actual reps are a real, independently-logged athlete output")
        XCTAssertEqual(firstPrescription.loggedSetResults.first?.actualRir, 2)
    }

    // MARK: 18/19 — partner set count follows primary, never its own independent feedback

    func testPartnerSetCountFollowsPrimaryNeverIndependentFeedback() throws {
        let definition = try generateMesocycle2()
        let session = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let slots = session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates)
        let primary = slots[1]
        let partner = slots[2]

        guard
            case .autoregulated(let primaryConfig) = try XCTUnwrap(primary.rules?.setCountRule),
            case .autoregulated(let partnerConfig) = try XCTUnwrap(partner.rules?.setCountRule)
        else { return XCTFail("expected .autoregulated") }
        XCTAssertEqual(partnerConfig.baselineSets, primaryConfig.baselineSets, "partner's own baseline matches its primary's")
        XCTAssertEqual(partner.pairedSlot?.id, primary.pairedSlot?.id, "partner reads the SAME external rating target its primary does — never its own independent feedback")

        // End to end: identical rating input produces an identical
        // resolved set count for both — proving "follows the primary" is
        // a real, provable mathematical consequence, not a coincidence.
        let primaryResult = StrengthProgressionEngine.resolveSetCount(
            rules: try XCTUnwrap(primary.rules), weekIndex: 1, previousWeekSetCount: primaryConfig.baselineSets, autoregulationRating: 1
        )
        let partnerResult = StrengthProgressionEngine.resolveSetCount(
            rules: try XCTUnwrap(partner.rules), weekIndex: 1, previousWeekSetCount: partnerConfig.baselineSets, autoregulationRating: 1
        )
        XCTAssertEqual(partnerResult.sets, primaryResult.sets)
    }

    /// The one confirmed exception (Pull Emphasis's Biceps partner):
    /// pinned from Week 2 onward rather than cascading further, per the
    /// direct formula trace (`STAGE10R2_MESOCYCLE2_SOURCE_RECOVERY_DESIGN.md`).
    func testFrozenSupersetPartnerPinsFromWeekTwoOnward() throws {
        let definition = try generateMesocycle2()
        let session = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == "Pull Emphasis" })
        let slots = session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates)
        let partner = slots[4]
        guard case .autoregulated(let config) = try XCTUnwrap(partner.rules?.setCountRule) else { return XCTFail() }
        XCTAssertEqual(config.freezeAfterWeek, 1)

        let weekTwo = StrengthProgressionEngine.resolveSetCount(rules: try XCTUnwrap(partner.rules), weekIndex: 1, previousWeekSetCount: 3, autoregulationRating: 1)
        let weekThree = StrengthProgressionEngine.resolveSetCount(
            rules: try XCTUnwrap(partner.rules), weekIndex: 2, previousWeekSetCount: 3, autoregulationRating: 1, frozenSetCount: weekTwo.sets
        )
        XCTAssertEqual(weekThree.sets, weekTwo.sets, "pinned, never advancing further")
        XCTAssertEqual(weekThree.reasonCode, .autoregulatedSetFrozen)
    }

    // MARK: 20 — partner omitted from deload

    func testPartnerOmittedFromDeload() throws {
        let definition = try generateMesocycle2()
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition

        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 4, isDeload: true,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(weekOneResolvedWeightKg: 75) }, context: context
        )
        let session = try XCTUnwrap(result.sessions.first { $0.name == "Push Emphasis" })
        let prescriptions = session.orderedBlocks.flatMap(\.orderedPrescriptions)

        let templates = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == "Push Emphasis" }).orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates)
        let partnerPrescription = try XCTUnwrap(prescriptions.first { $0.sourcePrescriptionTemplate?.id == templates[2].id })
        XCTAssertTrue(partnerPrescription.orderedSetPrescriptions.isEmpty, "the confirmed superset-partner slot has zero SetPrescriptions during deload")

        let standalonePrescription = try XCTUnwrap(prescriptions.first { $0.sourcePrescriptionTemplate?.id == templates[0].id })
        XCTAssertFalse(standalonePrescription.orderedSetPrescriptions.isEmpty, "an ordinary row still deloads normally")
    }
}
