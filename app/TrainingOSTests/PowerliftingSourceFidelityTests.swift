import XCTest
import SwiftData
@testable import TrainingOS

/// Powerlifting Source Authority Repair: canonical, per-family fixture
/// comparison against the complete real row structure — independently
/// re-verified directly against the live workbooks
/// (`RP-PowerliftingStr-4-Day.xlsx`, a filled real example used as an
/// exact numeric golden fixture; `RP-PowerliftingHyp-5-Day.xlsx`, the
/// canonical blank template) this pass, not merely inherited from
/// `PROGRAM_LOGIC_SPEC.md`/`SOURCE_PROGRAM_MANIFEST.md` (though both
/// agree with every fixture below).
@MainActor
final class PowerliftingSourceFidelityTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func generate(family: PowerliftingFamily, dayCount: Int) -> ProgramDefinition {
        PowerliftingProgramGenerator.generate(
            configuration: PowerliftingProgramConfiguration(family: family, dayCount: dayCount),
            provenance: .constructed(reason: "fidelity test fixture"),
            context: context
        )
    }

    private func row(_ day: String, _ category: String, in definition: ProgramDefinition) throws -> PrescriptionTemplate {
        let session = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == day }, "no \(day) session")
        let block = try XCTUnwrap(session.orderedBlockTemplates.first)
        return try XCTUnwrap(block.orderedPrescriptionTemplates.first { $0.exerciseSlot?.name == category }, "no \(category) row on \(day)")
    }

    // MARK: - Canonical Family B fixture — every one of the 15 real rows
    // (day, category, rmType, weekOneFactor) — re-verified directly
    // against `RP-PowerliftingStr-4-Day.xlsx` this pass.

    private struct FamilyBRow {
        let day: String, category: String, rmType: RMType, weekOneFactor: Double
    }
    private let familyBFixture: [FamilyBRow] = [
        FamilyBRow(day: "Monday", category: "Deadlift Move", rmType: .rm5, weekOneFactor: 0.95),
        FamilyBRow(day: "Monday", category: "Legs Move 1", rmType: .rm5, weekOneFactor: 0.95),
        FamilyBRow(day: "Monday", category: "Pushing Move 1", rmType: .rm5, weekOneFactor: 0.7),
        FamilyBRow(day: "Monday", category: "Hamstring Move", rmType: .rm8, weekOneFactor: 0.95),
        FamilyBRow(day: "Tuesday", category: "Legs Move 2", rmType: .rm5, weekOneFactor: 0.95),
        FamilyBRow(day: "Tuesday", category: "Pushing Move 2", rmType: .rm5, weekOneFactor: 0.95),
        FamilyBRow(day: "Tuesday", category: "Upper Body Pulling Move 1", rmType: .rm8, weekOneFactor: 0.95),
        FamilyBRow(day: "Tuesday", category: "Shoulder Move 1", rmType: .rm8, weekOneFactor: 0.95),
        FamilyBRow(day: "Thursday", category: "Deadlift Move", rmType: .rm5, weekOneFactor: 0.7),
        FamilyBRow(day: "Thursday", category: "Upper Body Pulling Move 2", rmType: .rm8, weekOneFactor: 0.95),
        FamilyBRow(day: "Thursday", category: "Shoulder Move 2", rmType: .rm8, weekOneFactor: 0.95),
        FamilyBRow(day: "Friday", category: "Pushing Move 1", rmType: .rm5, weekOneFactor: 0.95),
        FamilyBRow(day: "Friday", category: "Legs Move 2", rmType: .rm5, weekOneFactor: 0.95),
        FamilyBRow(day: "Friday", category: "Upper Body Pulling Move 1", rmType: .rm8, weekOneFactor: 0.95),
        FamilyBRow(day: "Friday", category: "Shoulder Move 1", rmType: .rm8, weekOneFactor: 0.95),
    ]

    // 1-3: exact row/day/category counts
    func testFamilyBExactlyFifteenRowsAcrossFourDays() throws {
        let definition = generate(family: .b, dayCount: 4)
        XCTAssertEqual(definition.orderedTemplateSessions.count, 4)
        let total = definition.orderedTemplateSessions.reduce(0) { $0 + ($1.orderedBlockTemplates.first?.orderedPrescriptionTemplates.count ?? 0) }
        XCTAssertEqual(total, 15)
        for fixture in familyBFixture {
            _ = try row(fixture.day, fixture.category, in: definition)
        }
    }

    // 4: Shoulder present (both slots)
    func testFamilyBShoulderSlotsArePresent() throws {
        let definition = generate(family: .b, dayCount: 4)
        _ = try row("Tuesday", "Shoulder Move 1", in: definition)
        _ = try row("Thursday", "Shoulder Move 2", in: definition)
        _ = try row("Friday", "Shoulder Move 1", in: definition)
    }

    // 5: correct 5RM vs 8RM per row (every fixture row, exhaustively)
    func testFamilyBRMTypePerRowMatchesSource() throws {
        let definition = generate(family: .b, dayCount: 4)
        for fixture in familyBFixture {
            let template = try row(fixture.day, fixture.category, in: definition)
            guard case .rmBased(let payload) = try XCTUnwrap(template.rules?.loadRule) else {
                return XCTFail("\(fixture.day)/\(fixture.category): expected .rmBased")
            }
            XCTAssertEqual(payload.rmType, fixture.rmType, "\(fixture.day)/\(fixture.category) RM type")
        }
    }

    // 6-8: Week-1 factor + rounding + weekly progression, verified against
    // real computed golden numbers from `RP-PowerliftingStr-4-Day.xlsx`.
    func testFamilyBWeekOneFactorAndGoldenWeeklyProgression() throws {
        let definition = generate(family: .b, dayCount: 4)
        // (day, category, RM kg, expected W1, W2, W3, W4) — every value
        // re-verified directly this pass (data_only=True) against the
        // filled canonical workbook.
        let golden: [(String, String, Double, Double, Double, Double, Double)] = [
            ("Monday", "Deadlift Move", 90, 85, 90, 92.5, 92.5),
            ("Monday", "Legs Move 1", 67.5, 65, 67.5, 70, 72.5),
            ("Monday", "Pushing Move 1", 60, 42.5, 45, 45, 47.5),
            ("Monday", "Hamstring Move", 10, 10, 10, 10, 10),
            ("Tuesday", "Legs Move 2", 80, 75, 80, 80, 82.5),
            ("Tuesday", "Pushing Move 2", 45, 42.5, 45, 45, 47.5),
            ("Tuesday", "Upper Body Pulling Move 1", 78, 75, 80, 80, 82.5),
            ("Tuesday", "Shoulder Move 1", 35, 32.5, 35, 35, 35),
            ("Thursday", "Deadlift Move", 90, 62.5, 65, 67.5, 70),
            ("Thursday", "Upper Body Pulling Move 2", 50, 47.5, 50, 50, 52.5),
            ("Thursday", "Shoulder Move 2", 9, 7.5, 7.5, 7.5, 7.5),
            ("Friday", "Pushing Move 1", 60, 57.5, 60, 62.5, 62.5),
            ("Friday", "Legs Move 2", 80, 75, 80, 80, 82.5),
            ("Friday", "Upper Body Pulling Move 1", 78, 75, 80, 80, 82.5),
            ("Friday", "Shoulder Move 1", 35, 32.5, 35, 35, 35),
        ]
        let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)
        for (day, category, rmKg, w1, w2, w3, w4) in golden {
            let template = try row(day, category, in: definition)
            let rules = try XCTUnwrap(template.rules)
            let week0 = StrengthProgressionEngine.resolveWeight(rules: rules, weekIndex: 0, rmKilograms: rmKg, weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: nil, equipmentProfile: equipment)
            XCTAssertEqual(week0.weightKg ?? -1, w1, accuracy: 0.01, "\(day)/\(category) Week 1")
            for (weekIndex, expected) in [(1, w2), (2, w3), (3, w4)] {
                let result = StrengthProgressionEngine.resolveWeight(rules: rules, weekIndex: weekIndex, rmKilograms: nil, weekOneResolvedWeightKg: week0.weightKg, pairedSlotResolvedWeightKg: nil, equipmentProfile: equipment)
                XCTAssertEqual(result.weightKg ?? -1, expected, accuracy: 0.01, "\(day)/\(category) Week \(weekIndex + 1)")
            }
        }
    }

    // 9-10: Triples occurs only where source-defined, and is a fixed
    // 3-rep protocol.
    func testFamilyBTriplesOnlyOnTheTwoSourceDefinedRows() throws {
        let definition = generate(family: .b, dayCount: 4)
        let triplesRows: Set<String> = ["Monday|Pushing Move 1", "Thursday|Deadlift Move"]
        for fixture in familyBFixture {
            let template = try row(fixture.day, fixture.category, in: definition)
            let key = "\(fixture.day)|\(fixture.category)"
            let isTriples = triplesRows.contains(key)
            guard case .rmBased(let payload) = try XCTUnwrap(template.rules?.loadRule) else { return XCTFail() }
            XCTAssertEqual(payload.weekOneFactor == 0.7, isTriples, "\(key) Triples-factor mismatch")
            if isTriples {
                XCTAssertEqual(template.rules?.repGoalSchedule, Array(repeating: RepGoal.fixedReps(3), count: 4), "\(key) must be a fixed 3-rep protocol")
            }
        }
    }

    // 11-12: complete cross-day rating graph matches source; dead
    // (fixed-schedule) rows remain behaviorally dead.
    func testFamilyBCompleteCrossDayAutoregulationGraph() throws {
        let definition = generate(family: .b, dayCount: 4)
        let expectedPairing: [(String, String, String, String)] = [
            ("Monday", "Deadlift Move", "Thursday", "Deadlift Move"),
            ("Monday", "Legs Move 1", "Friday", "Legs Move 2"),
            ("Monday", "Pushing Move 1", "Friday", "Pushing Move 1"),
            ("Tuesday", "Legs Move 2", "Friday", "Legs Move 2"),
            ("Tuesday", "Pushing Move 2", "Friday", "Pushing Move 1"),
            ("Thursday", "Deadlift Move", "Monday", "Deadlift Move"),
            ("Friday", "Pushing Move 1", "Tuesday", "Pushing Move 2"),
            ("Friday", "Legs Move 2", "Tuesday", "Legs Move 2"),
        ]
        for (day, category, pairedDay, pairedCategory) in expectedPairing {
            let template = try row(day, category, in: definition)
            let expectedPaired = try row(pairedDay, pairedCategory, in: definition)
            XCTAssertEqual(template.pairedSlot?.id, expectedPaired.id, "\(day)/\(category) must pair to \(pairedDay)/\(pairedCategory)")
        }
        // Dead (fixed) rows: no pairedSlot at all, never autoregulated.
        for (day, category) in [("Monday", "Hamstring Move"), ("Tuesday", "Upper Body Pulling Move 1"), ("Tuesday", "Shoulder Move 1"), ("Thursday", "Upper Body Pulling Move 2"), ("Thursday", "Shoulder Move 2"), ("Friday", "Upper Body Pulling Move 1"), ("Friday", "Shoulder Move 1")] {
            let template = try row(day, category, in: definition)
            XCTAssertNil(template.pairedSlot, "\(day)/\(category) is a fixed-schedule accessory row, never autoregulated")
            XCTAssertEqual(template.rules?.setCountRule, .fixed(setsByWeek: [2, 2, 3, 3]))
        }
    }

    // 13-14: deload matches source per day-position split.
    func testFamilyBDeloadSplitByDayPosition() throws {
        let definition = generate(family: .b, dayCount: 4)
        for (day, category) in [("Monday", "Deadlift Move"), ("Tuesday", "Legs Move 2")] {
            let template = try row(day, category, in: definition)
            XCTAssertEqual(template.rules?.deloadWeightPositionOverride?.fullPositionFactor, 0.7, "\(day) deload weight = 0.7x")
            XCTAssertEqual(template.rules?.deloadRepPositionOverride?.fullPositionFactor, 2.0 / 3.0, "\(day) deload reps = 2/3")
        }
        for (day, category) in [("Thursday", "Deadlift Move"), ("Friday", "Legs Move 2")] {
            let template = try row(day, category, in: definition)
            XCTAssertEqual(template.rules?.deloadWeightPositionOverride?.halfPositionFactor, 0.5, "\(day) deload weight = 0.5x")
            XCTAssertEqual(template.rules?.deloadRepPositionOverride?.halfPositionFactor, 0.5, "\(day) deload reps = 1/2")
        }
    }

    // 15: no extra fabricated rows.
    func testFamilyBNoFabricatedRows() throws {
        let definition = generate(family: .b, dayCount: 4)
        let allSlotKeys = definition.orderedTemplateSessions.flatMap { session in
            (session.orderedBlockTemplates.first?.orderedPrescriptionTemplates ?? []).map { "\(session.name)|\($0.exerciseSlot?.name ?? "?")" }
        }
        let expectedKeys = Set(familyBFixture.map { "\($0.day)|\($0.category)" })
        XCTAssertEqual(Set(allSlotKeys), expectedKeys)
        XCTAssertEqual(allSlotKeys.count, 15)
    }

    // MARK: - Canonical Family C fixture — every one of the 16 real rows,
    // re-verified directly against `RP-PowerliftingHyp-5-Day.xlsx`.

    private let familyCRows: [(String, String)] = [
        ("Monday", "Pushing Move 1"), ("Monday", "Legs Move 1"), ("Monday", "Upper Body Pulling Move 1"),
        ("Tuesday", "Legs Move 1"), ("Tuesday", "Deadlift Move"), ("Tuesday", "Shoulder Move 1"),
        ("Wednesday", "Pushing Move 2"), ("Wednesday", "Upper Body Pulling Move 1"), ("Wednesday", "Shoulder Move 1"),
        ("Thursday", "Deadlift Move"), ("Thursday", "Hamstring Move"), ("Thursday", "Shoulder Move 2"),
        ("Friday", "Legs Move 2"), ("Friday", "Upper Body Pulling Move 2"), ("Friday", "Shoulder Move 2"),
        ("Friday", "Pushing Move 1 (Friday Backoff)"),
    ]

    func testFamilyCExactlySixteenRowsAcrossFiveDays() throws {
        let definition = generate(family: .c, dayCount: 5)
        XCTAssertEqual(definition.orderedTemplateSessions.count, 5)
        let total = definition.orderedTemplateSessions.reduce(0) { $0 + ($1.orderedBlockTemplates.first?.orderedPrescriptionTemplates.count ?? 0) }
        XCTAssertEqual(total, 16)
        for (day, category) in familyCRows { _ = try row(day, category, in: definition) }
    }

    func testFamilyCHamstringIsPresent() throws {
        let definition = generate(family: .c, dayCount: 5)
        _ = try row("Thursday", "Hamstring Move", in: definition)
    }

    func testFamilyCUniform10RMCalibration() throws {
        let definition = generate(family: .c, dayCount: 5)
        for (day, category) in familyCRows where category != "Pushing Move 1 (Friday Backoff)" {
            let template = try row(day, category, in: definition)
            guard case .rmBased(let payload) = try XCTUnwrap(template.rules?.loadRule) else { return XCTFail("\(day)/\(category)") }
            XCTAssertEqual(payload.rmType, .rm10)
        }
    }

    func testFamilyCWeekOneFactorMatchesSource() throws {
        let definition = generate(family: .c, dayCount: 5)
        // Every standard row = 0.95; the backoff = 0.85 (as a fraction of
        // Monday's resolved weight, via `.linkedToPairedSlot`, not its own
        // `.rmBased` factor).
        for (day, category) in familyCRows where category != "Pushing Move 1 (Friday Backoff)" {
            let template = try row(day, category, in: definition)
            guard case .rmBased(let payload) = try XCTUnwrap(template.rules?.loadRule) else { return XCTFail() }
            XCTAssertEqual(payload.weekOneFactor, 0.95, accuracy: 0.0001, "\(day)/\(category)")
        }
        let backoff = try row("Friday", "Pushing Move 1 (Friday Backoff)", in: definition)
        XCTAssertEqual(backoff.rules?.loadRule, .linkedToPairedSlot(fractionOfSourceResult: 0.85 / 0.95))
    }

    /// **Disclosed architectural finding, not a defect this test papers
    /// over:** the live source spreadsheets round Family B to the
    /// nearest 2.5 and Family C to the nearest 5 — a real, confirmed
    /// `MROUND(...)` unit difference in the original workbooks (re-
    /// verified directly this pass). But `StrengthProgressionRules`
    /// itself deliberately carries NO rounding-increment field — rounding
    /// is entirely `EquipmentProfile.resolve()`'s job, supplied by
    /// whatever caller materializes the program (see that type's own doc
    /// comment: "Deliberately does not carry a rounding increment").
    /// This means the 2.5-vs-5 distinction is a real SOURCE FACT that is
    /// **not currently reproduced as a per-family generator invariant** —
    /// it only manifests if/when a caller happens to supply matching
    /// per-family equipment profiles, which nothing in this checkpoint's
    /// scope wires up (no existing production path selects
    /// `EquipmentProfile` by `PowerliftingFamily`). Flagged as an
    /// unresolved source-fidelity gap for a future pass — see
    /// `POWERLIFTING_SOURCE_AUTHORITY_REPAIR_V1.md` §5. This test proves
    /// only that `EquipmentProfile.resolve` itself rounds correctly to
    /// whatever increment it's given — it does NOT prove the generator
    /// enforces 5 for Family C, because the generator has no mechanism to.
    func testEquipmentProfileRoundingMechanismItselfWorksForBothIncrements() throws {
        let definition = generate(family: .c, dayCount: 5)
        let template = try row("Monday", "Pushing Move 1", in: definition)
        let rules = try XCTUnwrap(template.rules)
        let fiveKgProfile = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 5)
        let pointFiveKgProfile = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)
        // 46 * 0.95 = 43.7 — chosen specifically so the two increments
        // diverge (42.5 vs 45), proving the rounding mechanism itself
        // genuinely respects whichever increment it's given.
        let roundedToFive = StrengthProgressionEngine.resolveWeight(rules: rules, weekIndex: 0, rmKilograms: 46, weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: nil, equipmentProfile: fiveKgProfile)
        let roundedToPointFive = StrengthProgressionEngine.resolveWeight(rules: rules, weekIndex: 0, rmKilograms: 46, weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: nil, equipmentProfile: pointFiveKgProfile)
        XCTAssertEqual(roundedToFive.weightKg ?? -1, 45, accuracy: 0.01)
        XCTAssertEqual(roundedToPointFive.weightKg ?? -1, 42.5, accuracy: 0.01)
        XCTAssertNotEqual(roundedToFive.weightKg, roundedToPointFive.weightKg, "confirms the two increments genuinely diverge for this input")
    }

    func testFamilyCAutoregulationFreezeBoundaryMonWedContinueThuFriFreeze() throws {
        let definition = generate(family: .c, dayCount: 5)
        for (day, category) in [("Monday", "Pushing Move 1"), ("Monday", "Legs Move 1"), ("Tuesday", "Legs Move 1"), ("Tuesday", "Deadlift Move"), ("Wednesday", "Pushing Move 2")] {
            guard case .autoregulated(let config) = try XCTUnwrap(row(day, category, in: definition).rules?.setCountRule) else { return XCTFail("\(day)/\(category)") }
            XCTAssertNil(config.freezeAfterWeek, "\(day)/\(category) continues through Week 4")
        }
        for (day, category) in [("Thursday", "Deadlift Move"), ("Thursday", "Hamstring Move"), ("Friday", "Legs Move 2")] {
            guard case .autoregulated(let config) = try XCTUnwrap(row(day, category, in: definition).rules?.setCountRule) else { return XCTFail("\(day)/\(category)") }
            XCTAssertEqual(config.freezeAfterWeek, 2, "\(day)/\(category) freezes after Week 3")
        }
    }

    func testFamilyCDeloadWeightBoundaryDiffersFromFreezeBoundary() throws {
        // Wednesday freezes WITH Monday/Tuesday for autoregulation but
        // halves WITH Thursday/Friday for deload weight — genuinely
        // different day groupings, confirmed directly from the workbook.
        let definition = generate(family: .c, dayCount: 5)
        let monday = try row("Monday", "Pushing Move 1", in: definition)
        let tuesday = try row("Tuesday", "Deadlift Move", in: definition)
        let wednesday = try row("Wednesday", "Pushing Move 2", in: definition)
        XCTAssertEqual(monday.rules?.deloadWeightPositionOverride?.fullPositionFactor, 1.0)
        XCTAssertEqual(tuesday.rules?.deloadWeightPositionOverride?.fullPositionFactor, 1.0)
        XCTAssertEqual(wednesday.rules?.deloadWeightPositionOverride?.halfPositionFactor, 0.5, "Wednesday deload weight halves, unlike its own autoregulation-freeze grouping")
    }

    func testFamilyCCompleteCrossDayAutoregulationGraph() throws {
        let definition = generate(family: .c, dayCount: 5)
        let expectedPairing: [(String, String, String, String)] = [
            ("Monday", "Pushing Move 1", "Wednesday", "Pushing Move 2"),
            ("Monday", "Legs Move 1", "Friday", "Legs Move 2"),
            ("Tuesday", "Legs Move 1", "Friday", "Legs Move 2"),
            ("Tuesday", "Deadlift Move", "Thursday", "Deadlift Move"),
            ("Wednesday", "Pushing Move 2", "Monday", "Pushing Move 1"),
            ("Thursday", "Deadlift Move", "Tuesday", "Deadlift Move"),
            ("Thursday", "Hamstring Move", "Tuesday", "Deadlift Move"),
            ("Friday", "Legs Move 2", "Tuesday", "Legs Move 1"),
        ]
        for (day, category, pairedDay, pairedCategory) in expectedPairing {
            let template = try row(day, category, in: definition)
            let expectedPaired = try row(pairedDay, pairedCategory, in: definition)
            XCTAssertEqual(template.pairedSlot?.id, expectedPaired.id, "\(day)/\(category) must pair to \(pairedDay)/\(pairedCategory)")
        }
    }

    /// The one KNOWN, DISCLOSED V1 simplification: the backoff's set-count
    /// autoregulation rating currently reads from the same `pairedSlot`
    /// used for load (Monday-Push1), not the literal source's
    /// Wednesday-Push2 — see `PowerliftingProgramGenerator`'s own top-of-
    /// file doc comment and `POWERLIFTING_SOURCE_AUTHORITY_REPAIR_V1.md`
    /// §"KNOWN CONFLICT" for the full disclosure.
    // MARK: - Dual-reference fix: Family C Friday backoff's load and
    // autoregulation-rating sources are DIFFERENT slots (load ← Monday,
    // rating ← Wednesday) — re-verified directly against
    // `RP-PowerliftingHyp-5-Day.xlsx`'s own `D42`/`H42` formulas this
    // pass. These tests exercise RESOLVED behavior via
    // `AutoregulationRatingResolver.rating(for:in:)`, not merely stored
    // `pairedSlot`/`autoregulationReferenceSlot` IDs.

    /// Builds one completed `ExercisePrescription` for `template`, in a
    /// fresh `Day`/`Session`/`WorkoutBlock`, carrying `rating`, and
    /// attaches it to `instance` — the minimal real graph
    /// `AutoregulationRatingResolver` reads from.
    @discardableResult
    private func completedPrescription(for template: PrescriptionTemplate, rating: Int, in instance: ProgramInstance, daysAgo: Int) -> ExercisePrescription {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let day = Day(ownerUserID: instance.ownerUserID, date: date)
        context.insert(day)
        let session = Session(name: template.exerciseSlot?.name ?? "session", modality: .strength, status: .completed)
        session.completedAt = date
        context.insert(session)
        day.addSession(session)
        instance.addSession(session)
        let block = WorkoutBlock(type: .strength)
        context.insert(block)
        session.addBlock(block)
        let prescription = ExercisePrescription()
        context.insert(prescription)
        prescription.sourcePrescriptionTemplate = template
        prescription.autoregulationRating = rating
        block.addPrescription(prescription)
        return prescription
    }

    private func makeInstance() -> ProgramInstance {
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        return instance
    }

    /// 1-2: load still reads Monday; rating reads Wednesday (resolved,
    /// not merely stored).
    func testFamilyCBackoffLoadReadsMondayRatingReadsWednesdayResolved() throws {
        let definition = generate(family: .c, dayCount: 5)
        let backoff = try row("Friday", "Pushing Move 1 (Friday Backoff)", in: definition)
        let monday = try row("Monday", "Pushing Move 1", in: definition)
        let wednesday = try row("Wednesday", "Pushing Move 2", in: definition)
        XCTAssertEqual(backoff.rules?.loadRule, .linkedToPairedSlot(fractionOfSourceResult: 0.85 / 0.95), "load still 0.85/0.95 of Monday")
        XCTAssertEqual(backoff.pairedSlot?.id, monday.id, "load-reference slot is Monday")
        XCTAssertEqual(backoff.autoregulationReferenceSlot?.id, wednesday.id, "explicit rating-reference slot is Wednesday")

        let instance = makeInstance()
        completedPrescription(for: monday, rating: 1, in: instance, daysAgo: 10)
        completedPrescription(for: wednesday, rating: -1, in: instance, daysAgo: 8)

        // 3-5: Monday and Wednesday hold intentionally DIFFERENT ratings;
        // the resolved rating for the backoff row follows Wednesday's.
        let resolved = AutoregulationRatingResolver.rating(for: backoff, in: instance)
        XCTAssertEqual(resolved, -1, "resolved autoregulation rating must come from Wednesday (-1), never Monday (1)")
    }

    /// 6: changing Monday's rating alone must NOT alter the resolved
    /// rating the backoff row's set-count adjustment would use.
    func testFamilyCBackoffRatingUnaffectedByChangingMondayAlone() throws {
        let definition = generate(family: .c, dayCount: 5)
        let backoff = try row("Friday", "Pushing Move 1 (Friday Backoff)", in: definition)
        let monday = try row("Monday", "Pushing Move 1", in: definition)
        let wednesday = try row("Wednesday", "Pushing Move 2", in: definition)
        let instance = makeInstance()
        completedPrescription(for: monday, rating: 1, in: instance, daysAgo: 10)
        completedPrescription(for: wednesday, rating: 0, in: instance, daysAgo: 8)
        XCTAssertEqual(AutoregulationRatingResolver.rating(for: backoff, in: instance), 0)

        // Monday's rating changes; Wednesday's does not.
        completedPrescription(for: monday, rating: -1, in: instance, daysAgo: 3)
        XCTAssertEqual(AutoregulationRatingResolver.rating(for: backoff, in: instance), 0, "changing Monday alone must not move the resolved rating")
    }

    /// 7: changing Wednesday's rating DOES alter the resolved rating.
    func testFamilyCBackoffRatingChangesWhenWednesdayChanges() throws {
        let definition = generate(family: .c, dayCount: 5)
        let backoff = try row("Friday", "Pushing Move 1 (Friday Backoff)", in: definition)
        let monday = try row("Monday", "Pushing Move 1", in: definition)
        let wednesday = try row("Wednesday", "Pushing Move 2", in: definition)
        let instance = makeInstance()
        completedPrescription(for: monday, rating: 1, in: instance, daysAgo: 10)
        completedPrescription(for: wednesday, rating: 0, in: instance, daysAgo: 8)
        XCTAssertEqual(AutoregulationRatingResolver.rating(for: backoff, in: instance), 0)

        completedPrescription(for: wednesday, rating: 1, in: instance, daysAgo: 1)
        XCTAssertEqual(AutoregulationRatingResolver.rating(for: backoff, in: instance), 1, "changing Wednesday must move the resolved rating")
    }

    /// 10: existing same-slot/single-`pairedSlot` behavior (every row
    /// except the one backoff row) is completely unaffected —
    /// `autoregulationReferenceSlot` is `nil` and resolution falls back
    /// to `pairedSlot` exactly as before this fix existed.
    func testExistingSinglePairedSlotBehaviorUnaffectedForEveryOtherRow() throws {
        let definition = generate(family: .c, dayCount: 5)
        let monPush1 = try row("Monday", "Pushing Move 1", in: definition)
        let wedPush2 = try row("Wednesday", "Pushing Move 2", in: definition)
        XCTAssertNil(monPush1.autoregulationReferenceSlot, "ordinary rows never set the new field")
        XCTAssertEqual(monPush1.pairedSlot?.id, wedPush2.id)

        let instance = makeInstance()
        completedPrescription(for: wedPush2, rating: -1, in: instance, daysAgo: 5)
        XCTAssertEqual(AutoregulationRatingResolver.rating(for: monPush1, in: instance), -1, "falls back to pairedSlot exactly as before the fix")
    }

    /// The Friday-backoff SOURCE AUTHORING INCONSISTENCY, explicit
    /// regression coverage per the checkpoint's own requirement: the
    /// live `RP-PowerliftingHyp-5-Day.xlsx` sheet's own footnote says
    /// "1/2 Thursday's," but the sheet's own executable formula/rep-goal
    /// cells read "1/2 Monday's." The formula is executable source truth
    /// and wins. This test locks the backoff's LOAD pairing to Monday so
    /// a future cleanup pass never "corrects" it to Thursday.
    func testFamilyCBackoffPairsToMondayNotThursdayDespiteTheSourceFootnote() throws {
        let definition = generate(family: .c, dayCount: 5)
        let backoff = try row("Friday", "Pushing Move 1 (Friday Backoff)", in: definition)
        let monday = try row("Monday", "Pushing Move 1", in: definition)
        XCTAssertEqual(backoff.pairedSlot?.id, monday.id)
        XCTAssertEqual(backoff.rules?.loadRule, .linkedToPairedSlot(fractionOfSourceResult: 0.85 / 0.95))
        // No Thursday row shares this backoff's identity or is ever
        // referenced by it.
        let thursdayDeadlift = try row("Thursday", "Deadlift Move", in: definition)
        XCTAssertNotEqual(backoff.pairedSlot?.id, thursdayDeadlift.id)
    }

    func testFamilyCDeloadRepFractionBackoffIsSoleExceptionUnchanged() throws {
        let definition = generate(family: .c, dayCount: 5)
        let backoff = try row("Friday", "Pushing Move 1 (Friday Backoff)", in: definition)
        XCTAssertEqual(backoff.rules?.deloadRepFraction, 1.0, "the backoff's deload reps are unchanged from Week 1 — the sole exception")
        let legs2 = try row("Friday", "Legs Move 2", in: definition)
        XCTAssertEqual(legs2.rules?.deloadRepFraction, 0.5, "every other row halves")
    }

    func testFamilyCNoFabricatedRows() throws {
        let definition = generate(family: .c, dayCount: 5)
        let allSlotKeys = definition.orderedTemplateSessions.flatMap { session in
            (session.orderedBlockTemplates.first?.orderedPrescriptionTemplates ?? []).map { "\(session.name)|\($0.exerciseSlot?.name ?? "?")" }
        }
        XCTAssertEqual(Set(allSlotKeys), Set(familyCRows.map { "\($0.0)|\($0.1)" }))
        XCTAssertEqual(allSlotKeys.count, 16)
    }

    // MARK: - Capability gate

    func testCapabilityGateReportsBothFamiliesSourceVerified() {
        XCTAssertTrue(ProgramCapabilityRegistry.isPowerliftingSourceVerified(family: .b))
        XCTAssertTrue(ProgramCapabilityRegistry.isPowerliftingSourceVerified(family: .c))
    }

    // MARK: - Materialization dogfood: real week-0 materialization
    // reproduces the golden fixture exactly for every Family B row.

    func testDogfoodFamilyBWeekZeroMaterializationMatchesGoldenFixture() throws {
        let definition = generate(family: .b, dayCount: 4)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition
        let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)

        // (day, category) -> real athlete RM (kg), matching the filled
        // canonical workbook's own calibration inputs exactly.
        let rmByRow: [String: Double] = [
            "Monday|Deadlift Move": 90, "Monday|Legs Move 1": 67.5, "Monday|Pushing Move 1": 60, "Monday|Hamstring Move": 10,
            "Tuesday|Legs Move 2": 80, "Tuesday|Pushing Move 2": 45, "Tuesday|Upper Body Pulling Move 1": 78, "Tuesday|Shoulder Move 1": 35,
            "Thursday|Deadlift Move": 90, "Thursday|Upper Body Pulling Move 2": 50, "Thursday|Shoulder Move 2": 9,
            "Friday|Pushing Move 1": 60, "Friday|Legs Move 2": 80, "Friday|Upper Body Pulling Move 1": 78, "Friday|Shoulder Move 1": 35,
        ]
        let expectedWeekOneWeight: [String: Double] = [
            "Monday|Deadlift Move": 85, "Monday|Legs Move 1": 65, "Monday|Pushing Move 1": 42.5, "Monday|Hamstring Move": 10,
            "Tuesday|Legs Move 2": 75, "Tuesday|Pushing Move 2": 42.5, "Tuesday|Upper Body Pulling Move 1": 75, "Tuesday|Shoulder Move 1": 32.5,
            "Thursday|Deadlift Move": 62.5, "Thursday|Upper Body Pulling Move 2": 47.5, "Thursday|Shoulder Move 2": 7.5,
            "Friday|Pushing Move 1": 57.5, "Friday|Legs Move 2": 75, "Friday|Upper Body Pulling Move 1": 75, "Friday|Shoulder Move 1": 32.5,
        ]
        let expectedWeekOneSets: [String: Int] = [
            "Monday|Deadlift Move": 2, "Monday|Legs Move 1": 2, "Monday|Pushing Move 1": 2, "Monday|Hamstring Move": 2,
            "Tuesday|Legs Move 2": 5, "Tuesday|Pushing Move 2": 3, "Tuesday|Upper Body Pulling Move 1": 2, "Tuesday|Shoulder Move 1": 2,
            "Thursday|Deadlift Move": 2, "Thursday|Upper Body Pulling Move 2": 2, "Thursday|Shoulder Move 2": 2,
            "Friday|Pushing Move 1": 3, "Friday|Legs Move 2": 2, "Friday|Upper Body Pulling Move 1": 2, "Friday|Shoulder Move 1": 2,
        ]

        let (sessions, resolvedWeights) = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(), ownerUserID: instance.ownerUserID, equipmentProfile: equipment,
            slotContext: { slot in
                let key = self.keyFor(slot: slot, in: definition)
                return StrengthMaterializer.SlotContext(rmKilograms: rmByRow[key])
            },
            context: context
        )

        XCTAssertEqual(sessions.count, 4, "one real Session per real training day")
        var checkedCount = 0
        for session in sessions {
            for block in session.orderedBlocks {
                for prescription in block.orderedPrescriptions {
                    guard let slot = prescription.sourcePrescriptionTemplate?.exerciseSlot else { continue }
                    let key = keyFor(slot: slot, in: definition)
                    guard let expectedWeight = expectedWeekOneWeight[key] else { continue }
                    XCTAssertEqual(prescription.orderedSetPrescriptions.first?.targetWeight ?? -1, expectedWeight, accuracy: 0.01, "\(key) week-1 materialized weight")
                    XCTAssertEqual(prescription.orderedSetPrescriptions.count, expectedWeekOneSets[key], "\(key) week-1 materialized set count")
                    checkedCount += 1
                }
            }
        }
        XCTAssertEqual(checkedCount, 15, "every one of the 15 real rows must have materialized and been checked")
        XCTAssertEqual(resolvedWeights.count, 15)
    }

    private func keyFor(slot: ExerciseSlot, in definition: ProgramDefinition) -> String {
        for session in definition.orderedTemplateSessions {
            for block in session.orderedBlockTemplates {
                for template in block.orderedPrescriptionTemplates where template.exerciseSlot?.id == slot.id {
                    return "\(session.name)|\(slot.name)"
                }
            }
        }
        return "unknown|\(slot.name)"
    }
}
