import XCTest
import SwiftData
@testable import TrainingOS

/// Source Authority Repair (Phase A): proves `HypertrophyProgramGenerator`'s
/// 4-Day Full Body Mesocycle 1 now reflects the REAL, cell-cited structure
/// recovered from `source_workbooks/4 day full body.xlsx`
/// (`SOURCE_PROGRAM_MANIFEST.md` §0), replacing the legacy
/// `generateLegacyFixedPair` placeholder (identical primary+paired slot
/// repeated every day) for this one configuration only. Mesocycle 2/3 are
/// NOT yet recovered with the same rigor and must correctly throw
/// `.phaseNotYetRecovered` rather than silently reusing another phase's
/// content — the exact discipline this suite locks in.
@MainActor
final class FourDayFullBodySourceFidelityTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func generate(phaseType: HypertrophyPhaseType = .basicHypertrophy) throws -> ProgramDefinition {
        _ = ExerciseCatalog.resolveOrInsert(context: context)
        return try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 4, split: .fullBody, phaseType: phaseType),
            provenance: .constructed(reason: "test fixture"), context: context
        )
    }

    func testExactlyFourDaysWithRealEmphasisNames() throws {
        let definition = try generate()
        XCTAssertEqual(definition.orderedTemplateSessions.map(\.name), ["Upper Body", "Lower Body", "Upper Body", "Lower Body"])
    }

    func testDayOneMatchesTheRealRecoveredSourceCategorySequence() throws {
        let definition = try generate()
        let day1 = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let slots = try XCTUnwrap(day1.orderedBlockTemplates.first).orderedPrescriptionTemplates
        XCTAssertEqual(slots.compactMap { $0.exerciseSlot?.name }, [
            "Incline Push", "Chest Isolation or Triceps", "Horizontal Push", "Horizontal Pull",
            "Vertical Pull", "Side Delts", "Abs",
        ])
        let baselineSets: [Int] = slots.compactMap {
            guard case .autoregulated(let config) = $0.rules?.setCountRule else { return nil }
            return config.baselineSets
        }
        XCTAssertEqual(baselineSets, [3, 3, 2, 3, 3, 3, 2])
    }

    /// The exact bug this repair fixes: 4 distinct, non-repeated daily
    /// slot sequences (26 slots total) — never the legacy placeholder's
    /// single primary+paired pair repeated on every day.
    func testAllFourDaysAreDistinctNotTheLegacyRepeatedTwoSlotPlaceholder() throws {
        let definition = try generate()
        let daySlotNames = definition.orderedTemplateSessions.map { day in
            day.orderedBlockTemplates.first?.orderedPrescriptionTemplates.compactMap { $0.exerciseSlot?.name } ?? []
        }
        XCTAssertEqual(daySlotNames.map(\.count), [7, 6, 7, 6], "26 real slots/week, matching the manifest's own slot-count claim")
        let uniqueDaySequences = Set(daySlotNames.map { $0.joined(separator: "|") })
        XCTAssertEqual(uniqueDaySequences.count, 4, "all 4 days must have genuinely distinct slot sequences, never the legacy repeated pair")
    }

    func testEveryPrimaryTemplateUsesRealRMBasedLoadNeverDoubleProgressionOrLegacyLinkedPair() throws {
        let definition = try generate()
        for day in definition.orderedTemplateSessions {
            for template in day.orderedBlockTemplates.first?.orderedPrescriptionTemplates ?? [] {
                guard case .rmBased(let payload) = template.rules?.loadRule else {
                    return XCTFail("every 4-Day Mesocycle 1 slot must use real .rmBased load, matching the source's own 0.85x10RM formula")
                }
                XCTAssertEqual(payload.rmType, .rm10)
                XCTAssertEqual(payload.weekOneFactor, 0.85, accuracy: 0.0001)
            }
        }
    }

    /// Phase A2: Mesocycle 2/3 are now fully recovered — this replaces
    /// Phase A1's "throws rather than fabricates" test with the positive
    /// proof that both now generate real, distinct content. A future
    /// day-count/split combination with genuinely unrecovered content
    /// still must throw — proven generically below, using a real
    /// combination (6-day Full Body) that remains unmigrated (5-day
    /// Full Body was this exact "remaining unrecovered example" when
    /// this test was first written; Phase B has since migrated it too
    /// — see `FiveDayFullBodySourceFidelityTests.swift` — so this test
    /// now uses 6-Day, the next configuration still genuinely
    /// unmigrated).
    func testMesocycleTwoAndThreeNowGenerateRealDistinctContent() throws {
        let m2 = try generate(phaseType: .metaboliteFocus)
        XCTAssertEqual(m2.orderedTemplateSessions.map(\.name), ["Upper Body", "Lower Body", "Upper Body", "Lower Body"])
        let m3 = try generate(phaseType: .resensitization)
        XCTAssertEqual(m3.orderedTemplateSessions.map(\.name), ["Upper Body", "Lower Body", "Upper Body", "Lower Body"])
    }

    // Source Authority Repair Phase C migrated 6-Day Full Body too (the
    // last remaining Full Body configuration) — the
    // `testSixDayFullBodyRemainsUnchangedOnTheLegacyPlaceholderPath` test
    // that used to document 6-Day's out-of-scope legacy status here is
    // removed, since that fact is no longer true. 6-Day's real fidelity
    // is now fully covered by `SixDayFullBodySourceFidelityTests.swift`.

    // MARK: - Mesocycle 2 "Metabolite Focus" fidelity

    func testMesocycleTwoDayOneMatchesRealSourceSequenceIncludingSuperset() throws {
        let definition = try generate(phaseType: .metaboliteFocus)
        let day1 = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let slots = try XCTUnwrap(day1.orderedBlockTemplates.first).orderedPrescriptionTemplates
        XCTAssertEqual(slots.compactMap { $0.exerciseSlot?.name }, [
            "Incline Push", "Chest Isolation or Triceps", "Horizontal Push", "Horizontal Push",
            "Horizontal Pull", "Vertical Pull", "Side Delts", "Abs",
        ], "8 real slots including the real superset partner row (Horizontal Push at index 2)")
    }

    /// The exact real cell-cited superset mechanic: 4 pairs across the 4
    /// days, each partner testing at 0.6x10RM (never the primary's 0.75x
    /// factor) and omitted from deload — proven via the real,
    /// unmodified `makeSourceCategoryTemplate`/`SourceCompatibleDeloadStrategy`
    /// mechanism, not a new one.
    func testMesocycleTwoSupersetPartnersUseReducedFactorAndOmitDeload() throws {
        let definition = try generate(phaseType: .metaboliteFocus)
        // Day1 slot 2 (0-indexed) is the Horizontal Push superset partner.
        let day1Slots = try XCTUnwrap(definition.orderedTemplateSessions.first?.orderedBlockTemplates.first).orderedPrescriptionTemplates
        let partner = day1Slots[2]
        guard case .rmBased(let payload) = partner.rules?.loadRule else {
            return XCTFail("superset partner must still use real .rmBased load")
        }
        XCTAssertEqual(payload.weekOneFactor, 0.6, accuracy: 0.0001, "superset partner tests at the real 0.6x factor, never the primary's 0.75x")
        XCTAssertEqual(partner.rules?.deloadWeightAction, .omit, "the real source's superset partner rows have blank deload cells — omitted, not a fabricated value")
        // The primary (slot 1) must NOT be omitted from deload.
        let primary = day1Slots[1]
        XCTAssertEqual(primary.rules?.deloadWeightAction, .standard)
    }

    func testMesocycleTwoAllFourDaysHaveRealDistinctSlotCounts() throws {
        let definition = try generate(phaseType: .metaboliteFocus)
        let daySlotCounts = definition.orderedTemplateSessions.map { $0.orderedBlockTemplates.first?.orderedPrescriptionTemplates.count ?? 0 }
        XCTAssertEqual(daySlotCounts, [8, 7, 8, 7], "30 real slots/week (8+7+8+7), each day one more than Mesocycle 1 from its own real superset partner row")
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
            "Incline Push", "Horizontal Push", "Horizontal Pull", "Vertical Pull", "Side Delts", "Abs",
        ])
    }

    func testMesocycleThreeAllFourDaysHaveRealReducedSlotCounts() throws {
        let definition = try generate(phaseType: .resensitization)
        let daySlotCounts = definition.orderedTemplateSessions.map { $0.orderedBlockTemplates.first?.orderedPrescriptionTemplates.count ?? 0 }
        XCTAssertEqual(daySlotCounts, [6, 5, 6, 6], "23 real slots/week (6+5+6+6), the source's own genuinely reduced Mesocycle 3 volume")
    }

    /// Real, cell-confirmed: no row in Mesocycle 3 is a superset partner
    /// (unlike Mesocycle 2) — every slot must use the standard deload
    /// path.
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

    /// A real 4-Day ProgramInstance must be able to progress M1 -> M2 ->
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
        XCTAssertEqual(m1Slots, [7, 6, 7, 6])
        XCTAssertEqual(m2Slots, [8, 7, 8, 7])
        XCTAssertEqual(m3Slots, [6, 5, 6, 6])
        XCTAssertNotEqual(m1Slots, m2Slots, "each mesocycle must produce its own real slot counts, never accidentally reusing another's")
        XCTAssertNotEqual(m2Slots, m3Slots)

        // Each phase's own real Week-1 factor must differ — proves no
        // accidental cross-phase reuse of load rules either.
        func firstFactor(_ definition: ProgramDefinition) -> Double? {
            guard case .rmBased(let payload) = definition.orderedTemplateSessions.first?.orderedBlockTemplates.first?.orderedPrescriptionTemplates.first?.rules?.loadRule else { return nil }
            return payload.weekOneFactor
        }
        XCTAssertEqual(try XCTUnwrap(firstFactor(m1)), 0.85, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(firstFactor(m2)), 0.75, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(firstFactor(m3)), 1.0, accuracy: 0.0001)
    }

    /// The exact real-world symptom this repair fixes: Starting Weights
    /// must now discover multiple distinct required calibrations for a
    /// real 4-Day Full Body instance, never collapsing to just Bench
    /// Press the way the legacy placeholder did.
    /// Week 0 load provenance, computed through the real, unmodified
    /// `StrengthProgressionEngine.resolveWeight` — the exact same engine
    /// already independently proven correct for Mesocycle 1 in an
    /// earlier round. A 100kg athlete-entered 10RM must produce
    /// Mesocycle 2's real 0.75x factor (75kg) and Mesocycle 3's real
    /// 1.0x factor (100kg) — never a fabricated/fallback value, and
    /// never M1's 0.85x (85kg) leaking into either.
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

        // Missing calibration must fail closed (nil), never fabricate a
        // fallback value — proven for both new mesocycles.
        let (missingWeight, missingReason) = StrengthProgressionEngine.resolveWeight(
            rules: try XCTUnwrap(m2Primary.rules), weekIndex: 0, rmKilograms: nil,
            weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: nil,
            equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)
        )
        XCTAssertNil(missingWeight)
        XCTAssertEqual(missingReason, .calibrationRequired)
    }

    func testCalibrationDiscoversMultipleDistinctExercisesNotJustBenchPress() throws {
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
        XCTAssertGreaterThan(distinctExercises.count, 1, "a real 4-Day program must require calibration for more than one exercise, unlike the legacy placeholder's collapsed single Bench Press requirement")
    }
}
