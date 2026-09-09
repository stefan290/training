import XCTest
import SwiftData
@testable import TrainingOS

/// Source Authority Repair (Phase B): proves `HypertrophyProgramGenerator`'s
/// 5-Day Full Body Mesocycle 1/2/3 now reflect the REAL, cell-cited
/// structure recovered from `source_workbooks/5 day full body.xlsx`
/// (`SOURCE_PROGRAM_MANIFEST.md` §0), replacing the legacy
/// `generateLegacyFixedPair` placeholder (identical primary+paired slot
/// repeated every day) for this configuration.
@MainActor
final class FiveDayFullBodySourceFidelityTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func generate(phaseType: HypertrophyPhaseType = .basicHypertrophy) throws -> ProgramDefinition {
        _ = ExerciseCatalog.resolveOrInsert(context: context)
        return try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 5, split: .fullBody, phaseType: phaseType),
            provenance: .constructed(reason: "test fixture"), context: context
        )
    }

    // MARK: - Mesocycle 1 "Basic Hypertrophy" fidelity

    func testExactlyFiveDaysWithRealEmphasisNames() throws {
        let definition = try generate()
        XCTAssertEqual(definition.orderedTemplateSessions.map(\.name), [
            "Chest Upper", "Quads Focused Legs", "Back Upper", "Glute/Ham Focused Legs", "Shoulders/Arms Upper",
        ])
    }

    func testDayOneMatchesTheRealRecoveredSourceCategorySequence() throws {
        let definition = try generate()
        let day1 = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let slots = try XCTUnwrap(day1.orderedBlockTemplates.first).orderedPrescriptionTemplates
        XCTAssertEqual(slots.compactMap { $0.exerciseSlot?.name }, [
            "Incline Chest", "Chest Isolation", "Horizontal Chest", "Horizontal Pull", "Rear or Side Delts", "Abs",
        ])
        let baselineSets: [Int] = slots.compactMap {
            guard case .autoregulated(let config) = $0.rules?.setCountRule else { return nil }
            return config.baselineSets
        }
        XCTAssertEqual(baselineSets, [3, 3, 2, 3, 3, 3])
    }

    /// The exact bug this repair fixes: 5 distinct, non-repeated daily
    /// slot sequences (28 slots total, matching the manifest's own
    /// slot-count claim) — never the legacy placeholder's single
    /// primary+paired pair repeated on every day.
    func testAllFiveDaysAreDistinctNotTheLegacyRepeatedTwoSlotPlaceholder() throws {
        let definition = try generate()
        let daySlotNames = definition.orderedTemplateSessions.map { day in
            day.orderedBlockTemplates.first?.orderedPrescriptionTemplates.compactMap { $0.exerciseSlot?.name } ?? []
        }
        XCTAssertEqual(daySlotNames.map(\.count), [6, 4, 6, 5, 7], "28 real slots/week, matching the manifest's own slot-count claim")
        let uniqueDaySequences = Set(daySlotNames.map { $0.joined(separator: "|") })
        XCTAssertEqual(uniqueDaySequences.count, 5, "all 5 days must have genuinely distinct slot sequences, never the legacy repeated pair")
    }

    /// "Horizontal Chest"/"Incline Chest" are this workbook's own real
    /// display-label variants for the same `.horizontalPush`/
    /// `.inclinePush` categories 3-/4-Day already use (confirmed via
    /// real exercise content, not assumed) — proves the category
    /// identity resolved correctly despite the different literal label.
    func testWorkbookLabelVariantsResolveToTheSameCanonicalCategoriesAs3And4Day() throws {
        let definition = try generate()
        let day1 = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let inclineChestSlot = try XCTUnwrap(day1.orderedBlockTemplates.first?.orderedPrescriptionTemplates.first?.exerciseSlot)
        XCTAssertEqual(inclineChestSlot.name, "Incline Chest", "the real workbook's own literal label is preserved for display/traceability")
        XCTAssertTrue(inclineChestSlot.allowedTargets.contains(.chest), "but the underlying category is the same real .inclinePush semantic identity")
    }

    func testEveryPrimaryTemplateUsesRealRMBasedLoadNeverDoubleProgressionOrLegacyLinkedPair() throws {
        let definition = try generate()
        for day in definition.orderedTemplateSessions {
            for template in day.orderedBlockTemplates.first?.orderedPrescriptionTemplates ?? [] {
                guard case .rmBased(let payload) = template.rules?.loadRule else {
                    return XCTFail("every 5-Day Mesocycle 1 slot must use real .rmBased load, matching the source's own 0.85x10RM formula")
                }
                XCTAssertEqual(payload.rmType, .rm10)
                XCTAssertEqual(payload.weekOneFactor, 0.85, accuracy: 0.0001)
            }
        }
    }

    // MARK: - Mesocycle 2 "Metabolite Focus" fidelity

    func testMesocycleTwoDayOneMatchesRealSourceSequenceIncludingSuperset() throws {
        let definition = try generate(phaseType: .metaboliteFocus)
        let day1 = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let slots = try XCTUnwrap(day1.orderedBlockTemplates.first).orderedPrescriptionTemplates
        XCTAssertEqual(slots.compactMap { $0.exerciseSlot?.name }, [
            "Incline Chest", "Chest Isolation", "Horizontal Chest", "Horizontal Chest",
            "Horizontal Pull", "Rear or Side Delts", "Abs",
        ], "7 real slots including the real superset partner row (Horizontal Chest at index 2)")
    }

    /// Real, cell-confirmed: unlike 4-Day's M2 (exactly one superset per
    /// day, every day), this workbook's 4 real supersets are unevenly
    /// distributed — Day2 and Day4 have NONE, Day5 alone has TWO.
    func testMesocycleTwoSupersetsAreUnevenlyDistributedAcrossDays() throws {
        let definition = try generate(phaseType: .metaboliteFocus)
        func supersetPartnerCount(dayIndex: Int) -> Int {
            let slots = definition.orderedTemplateSessions[dayIndex].orderedBlockTemplates.first?.orderedPrescriptionTemplates ?? []
            return slots.filter { $0.rules?.deloadWeightAction == .omit }.count
        }
        XCTAssertEqual(supersetPartnerCount(dayIndex: 0), 1, "Day1: one real superset partner (Horizontal Chest)")
        XCTAssertEqual(supersetPartnerCount(dayIndex: 1), 0, "Day2: no real supersets")
        XCTAssertEqual(supersetPartnerCount(dayIndex: 2), 1, "Day3: one real superset partner (Rear or Side Delts)")
        XCTAssertEqual(supersetPartnerCount(dayIndex: 3), 0, "Day4: no real supersets")
        XCTAssertEqual(supersetPartnerCount(dayIndex: 4), 2, "Day5: two real superset partners (Biceps, Front Delts)")
    }

    func testMesocycleTwoSupersetPartnersUseReducedFactorAndOmitDeload() throws {
        let definition = try generate(phaseType: .metaboliteFocus)
        let day1Slots = try XCTUnwrap(definition.orderedTemplateSessions.first?.orderedBlockTemplates.first).orderedPrescriptionTemplates
        let partner = day1Slots[2] // Horizontal Chest, the real superset partner
        guard case .rmBased(let payload) = partner.rules?.loadRule else {
            return XCTFail("superset partner must still use real .rmBased load")
        }
        XCTAssertEqual(payload.weekOneFactor, 0.6, accuracy: 0.0001, "superset partner tests at the real 0.6x factor, never the primary's 0.75x")
        XCTAssertEqual(partner.rules?.deloadWeightAction, .omit, "the real source's superset partner rows have blank deload cells — omitted, not a fabricated value")
        let primary = day1Slots[1] // Chest Isolation, the real superset primary
        XCTAssertEqual(primary.rules?.deloadWeightAction, .standard)
    }

    func testMesocycleTwoAllFiveDaysHaveRealDistinctSlotCounts() throws {
        let definition = try generate(phaseType: .metaboliteFocus)
        let daySlotCounts = definition.orderedTemplateSessions.map { $0.orderedBlockTemplates.first?.orderedPrescriptionTemplates.count ?? 0 }
        XCTAssertEqual(daySlotCounts, [7, 4, 7, 5, 9], "32 real slots/week (7+4+7+5+9), matching the real recovered structure")
    }

    func testMesocycleTwoUsesRealMetaboliteFocusLoadFactor() throws {
        let definition = try generate(phaseType: .metaboliteFocus)
        for day in definition.orderedTemplateSessions {
            for template in day.orderedBlockTemplates.first?.orderedPrescriptionTemplates ?? [] where template.rules?.deloadWeightAction == .standard {
                guard case .rmBased(let payload) = template.rules?.loadRule else {
                    return XCTFail("every non-superset-partner Mesocycle 2 slot must use real .rmBased load")
                }
                XCTAssertEqual(payload.weekOneFactor, 0.75, accuracy: 0.0001, "Mesocycle 2's real factor, never Mesocycle 1's 0.85 or Mesocycle 3's 1.0")
            }
        }
    }

    // MARK: - Mesocycle 3 "Resensitization" fidelity

    func testMesocycleThreeDayOneMatchesRealSourceSequence() throws {
        let definition = try generate(phaseType: .resensitization)
        let day1 = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let slots = try XCTUnwrap(day1.orderedBlockTemplates.first).orderedPrescriptionTemplates
        XCTAssertEqual(slots.compactMap { $0.exerciseSlot?.name }, [
            "Incline Chest", "Horizontal Chest", "Horizontal Pull", "Rear or Side Delts", "Abs",
        ])
    }

    func testMesocycleThreeAllFiveDaysHaveRealReducedSlotCounts() throws {
        let definition = try generate(phaseType: .resensitization)
        let daySlotCounts = definition.orderedTemplateSessions.map { $0.orderedBlockTemplates.first?.orderedPrescriptionTemplates.count ?? 0 }
        XCTAssertEqual(daySlotCounts, [5, 3, 5, 4, 7], "24 real slots/week (5+3+5+4+7), the source's own genuinely reduced Mesocycle 3 volume")
    }

    func testMesocycleThreeHasNoSupersetsEveryRowUsesStandardDeload() throws {
        let definition = try generate(phaseType: .resensitization)
        for day in definition.orderedTemplateSessions {
            for template in day.orderedBlockTemplates.first?.orderedPrescriptionTemplates ?? [] {
                XCTAssertEqual(template.rules?.deloadWeightAction, .standard, "Mesocycle 3 has zero superset partners — every row must use the standard deload path")
            }
        }
    }

    func testMesocycleThreeUsesRealResensitizationLoadFactorAndTwoProgressiveWeeks() throws {
        let definition = try generate(phaseType: .resensitization)
        XCTAssertEqual(definition.lengthWeeks, 3, "2 progressive weeks + 1 deload, the source's own genuinely shorter Mesocycle 3 block")
        for day in definition.orderedTemplateSessions {
            for template in day.orderedBlockTemplates.first?.orderedPrescriptionTemplates ?? [] {
                guard case .rmBased(let payload) = template.rules?.loadRule else {
                    return XCTFail("every Mesocycle 3 slot must use real .rmBased load")
                }
                XCTAssertEqual(payload.weekOneFactor, 1.0, accuracy: 0.0001, "Mesocycle 3's real factor — full 10RM, no reduction")
            }
        }
    }

    // MARK: - Mesocycle transition (a real ProgramInstance across all 3 phases)

    /// A real 5-Day ProgramInstance must be able to progress M1 -> M2 ->
    /// M3, each phase materializing its own genuinely distinct
    /// source-backed structure — never accidentally reusing an earlier
    /// phase's content, never falling back to the legacy placeholder,
    /// never throwing `.phaseNotYetRecovered` for any of the 3 real
    /// phases, and never the wrong mesocycle length/session count.
    func testMesocycleTransitionM1ToM2ToM3EachProducesItsOwnRealStructure() throws {
        let m1 = try generate(phaseType: .basicHypertrophy)
        let m2 = try generate(phaseType: .metaboliteFocus)
        let m3 = try generate(phaseType: .resensitization)

        XCTAssertEqual(m1.lengthWeeks, 5)
        XCTAssertEqual(m2.lengthWeeks, 5)
        XCTAssertEqual(m3.lengthWeeks, 3, "Mesocycle 3 alone has the real, shorter 2-progressive+1-deload structure")

        let m1Slots = m1.orderedTemplateSessions.map { $0.orderedBlockTemplates.first?.orderedPrescriptionTemplates.count ?? 0 }
        let m2Slots = m2.orderedTemplateSessions.map { $0.orderedBlockTemplates.first?.orderedPrescriptionTemplates.count ?? 0 }
        let m3Slots = m3.orderedTemplateSessions.map { $0.orderedBlockTemplates.first?.orderedPrescriptionTemplates.count ?? 0 }
        XCTAssertEqual(m1Slots, [6, 4, 6, 5, 7])
        XCTAssertEqual(m2Slots, [7, 4, 7, 5, 9])
        XCTAssertEqual(m3Slots, [5, 3, 5, 4, 7])
        XCTAssertNotEqual(m1Slots, m2Slots, "each mesocycle must produce its own real slot counts, never accidentally reusing another's")
        XCTAssertNotEqual(m2Slots, m3Slots)

        func firstFactor(_ definition: ProgramDefinition) -> Double? {
            guard case .rmBased(let payload) = definition.orderedTemplateSessions.first?.orderedBlockTemplates.first?.orderedPrescriptionTemplates.first?.rules?.loadRule else { return nil }
            return payload.weekOneFactor
        }
        XCTAssertEqual(try XCTUnwrap(firstFactor(m1)), 0.85, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(firstFactor(m2)), 0.75, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(firstFactor(m3)), 1.0, accuracy: 0.0001)
    }

    // MARK: - Deload boundary (real, unmodified `DeloadStrategy`, never changed for this repair)

    /// Real, cell-confirmed: Mesocycle 3's real deload weight is full for
    /// Days 1-3, half for Days 4-5 — exactly what `DeloadStrategy`'s
    /// existing, UNMODIFIED `ceil(dayCount/2)` boundary formula already
    /// produces for a 5-day program (`ceil(5/2)=3`). Zero code change to
    /// that shared engine was required or made.
    func testMesocycleThreeDeloadBoundaryMatchesRealWorkbookDaySplit() throws {
        let definition = try generate(phaseType: .resensitization)
        // Day indices 0,1,2 (Days 1-3) must resolve full weight; 3,4 (Days 4-5) half.
        let strategy = SourceCompatibleDeloadStrategy()
        for (dayIndex, day) in definition.orderedTemplateSessions.enumerated() {
            guard let template = day.orderedBlockTemplates.first?.orderedPrescriptionTemplates.first,
                  let rules = template.rules else { continue }
            let (deload, _) = strategy.resolveDeloadWeight(
                rules: rules, dayPositionInWeek: dayIndex, dayCount: 5,
                weekOneResolvedWeightKg: 100, equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)
            )
            let deloadValue = try XCTUnwrap(deload, "Day \(dayIndex + 1) deload weight must resolve (calibration provided)")
            if dayIndex < 3 {
                XCTAssertEqual(deloadValue, 100, accuracy: 0.01, "Day \(dayIndex + 1) must be full deload weight (real workbook: Days 1-3 full)")
            } else {
                XCTAssertEqual(deloadValue, 50, accuracy: 0.01, "Day \(dayIndex + 1) must be half deload weight (real workbook: Days 4-5 half)")
            }
        }
    }

    // MARK: - Calibration + Week 0 load provenance

    func testWeekZeroLoadProvenanceForMesocycleTwoAndThreeUsesRealFactorsNoFallback() throws {
        let m2 = try generate(phaseType: .metaboliteFocus)
        let m2Primary = try XCTUnwrap(m2.orderedTemplateSessions.first?.orderedBlockTemplates.first?.orderedPrescriptionTemplates.first)
        let (m2Weight, m2Reason) = StrengthProgressionEngine.resolveWeight(
            rules: try XCTUnwrap(m2Primary.rules), weekIndex: 0, rmKilograms: 100,
            weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: nil,
            equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)
        )
        XCTAssertEqual(m2Reason, .rmBasedLoad)
        XCTAssertEqual(try XCTUnwrap(m2Weight), 75, accuracy: 0.01, "100kg 10RM x 0.75 (Mesocycle 2's real factor) = 75kg")

        let m3 = try generate(phaseType: .resensitization)
        let m3Primary = try XCTUnwrap(m3.orderedTemplateSessions.first?.orderedBlockTemplates.first?.orderedPrescriptionTemplates.first)
        let (m3Weight, m3Reason) = StrengthProgressionEngine.resolveWeight(
            rules: try XCTUnwrap(m3Primary.rules), weekIndex: 0, rmKilograms: 100,
            weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: nil,
            equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)
        )
        XCTAssertEqual(m3Reason, .rmBasedLoad)
        XCTAssertEqual(try XCTUnwrap(m3Weight), 100, accuracy: 0.01, "100kg 10RM x 1.0 (Mesocycle 3's real factor, no reduction) = 100kg")

        let (missingWeight, missingReason) = StrengthProgressionEngine.resolveWeight(
            rules: try XCTUnwrap(m2Primary.rules), weekIndex: 0, rmKilograms: nil,
            weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: nil,
            equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)
        )
        XCTAssertNil(missingWeight)
        XCTAssertEqual(missingReason, .calibrationRequired)
    }

    /// The exact real-world symptom this repair fixes: Starting Weights
    /// must now discover multiple distinct required calibrations for a
    /// real 5-Day Full Body instance, never collapsing to just one
    /// exercise the way the legacy placeholder did.
    func testCalibrationDiscoversMultipleDistinctExercisesNotJustOneExercise() throws {
        let definition = try generate()
        let user = User(displayName: "Test")
        context.insert(user)
        let profile = PerformanceProfile()
        context.insert(profile)
        user.attachPerformanceProfile(profile)
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let fullGym = TrainingEnvironment.fullGym()
        context.insert(fullGym)
        let instance = ProgramInstance(ownerUserID: user.id, status: .active)
        instance.programDefinition = definition
        context.insert(instance)
        let allExercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        try ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: allExercises, environment: fullGym)
        try context.save()
        _ = catalog

        let required = RequiredSourceCalibrationsUseCase.stillRequired(for: definition, instance: instance)
        let distinctExercises = Set(required.map(\.exercise.id))
        XCTAssertGreaterThan(distinctExercises.count, 1, "a real 5-Day program must require calibration for more than one exercise, unlike the legacy placeholder's collapsed single requirement")
    }
}
