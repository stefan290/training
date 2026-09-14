import XCTest
import SwiftData
@testable import TrainingOS

/// Strength Source Content V1: canonical, per-family fixture comparison
/// against the complete real row structure of `Strength_Program_1.xlsx`
/// (`PowerliftingFamily.d`) and `Strength_Program_2.xlsx`
/// (`PowerliftingFamily.e`) — independently re-verified directly against
/// both live workbooks this checkpoint (`data_only=False`, full formula
/// dump), not merely inherited from `STRENGTH_SOURCE_RECOVERY_V1.md`
/// (though that report agrees with every fixture below). Mirrors
/// `PowerliftingSourceFidelityTests.swift`'s exact canonical-fixture-table
/// discipline. RM inputs used for materialization are representative TEST
/// FIXTURES — both workbooks ship with blank athlete-input cells; these
/// numbers are not real athlete source data.
@MainActor
final class StrengthSourceFidelityTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func generate(family: PowerliftingFamily) -> ProgramDefinition {
        PowerliftingProgramGenerator.generate(
            configuration: PowerliftingProgramConfiguration(family: family, dayCount: 4),
            provenance: .constructed(reason: "fidelity test fixture"),
            context: context
        )
    }

    private func row(_ day: String, _ category: String, in definition: ProgramDefinition) throws -> PrescriptionTemplate {
        let session = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == day }, "no \(day) session")
        let block = try XCTUnwrap(session.orderedBlockTemplates.first)
        return try XCTUnwrap(block.orderedPrescriptionTemplates.first { $0.exerciseSlot?.name == category }, "no \(category) row on \(day)")
    }

    // MARK: - Content identity (`StrengthSourceContentLibrary`, never
    // `PowerliftingBuiltInLibrary`)

    func testStrengthSourceContentLibraryIsSeparateFromPowerliftingBuiltInLibrary() {
        let powerliftingFamilies = Set(PowerliftingBuiltInLibrary.all.map(\.configuration.family))
        XCTAssertEqual(powerliftingFamilies, [.b, .c], "adding Family D/E here would change the existing Powerlifting recommendation candidate set")
        let strengthFamilies = Set(StrengthSourceContentLibrary.all.map(\.configuration.family))
        XCTAssertEqual(strengthFamilies, [.d, .e])
        for entry in StrengthSourceContentLibrary.all {
            XCTAssertFalse(entry.name.contains("Powerlifting"), "athlete-facing Strength content must never say Powerlifting")
            XCTAssertFalse(entry.name.contains("RP"), "athlete-facing Strength content must never carry RP branding")
        }
    }

    func testFamilyDAndEProgramDefinitionNamesNeverSayPowerliftingOrRP() {
        for family in [PowerliftingFamily.d, .e] {
            let definition = generate(family: family)
            XCTAssertFalse(definition.name.contains("Powerlifting"), "\(family) name must not say Powerlifting: \(definition.name)")
            XCTAssertFalse(definition.name.contains("RP"), "\(family) name must not carry RP branding: \(definition.name)")
            XCTAssertFalse(definition.intent.contains("Powerlifting"), "\(family) intent must not say Powerlifting: \(definition.intent)")
        }
    }

    func testSupportedFrequenciesForPowerliftingUnchangedByFamilyDAndE() {
        // Family D/E are both 4-day, exactly Family B's own day count —
        // proving they cannot silently widen or change
        // `supportedFrequencies(for: .powerlifting)`, since that query
        // reads only `PowerliftingBuiltInLibrary.all`, never
        // `StrengthSourceContentLibrary`.
        XCTAssertEqual(ProgramCapabilityRegistry.supportedFrequencies(for: .powerlifting), [4, 5])
    }

    func testCapabilityGateReportsFamilyDAndESourceVerified() {
        XCTAssertTrue(ProgramCapabilityRegistry.isPowerliftingSourceVerified(family: .d))
        XCTAssertTrue(ProgramCapabilityRegistry.isPowerliftingSourceVerified(family: .e))
    }

    // MARK: - Canonical Family D fixture (Strength_Program_1.xlsx) —
    // every one of the 16 real rows (day, category, rmType, weekOneFactor)

    private struct FamilyDRow {
        let day: String, category: String, rmType: RMType, weekOneFactor: Double
    }
    private let familyDFixture: [FamilyDRow] = [
        FamilyDRow(day: "Monday", category: "Deadlift Move", rmType: .rm5, weekOneFactor: 0.95),
        FamilyDRow(day: "Monday", category: "Legs Move 1", rmType: .rm5, weekOneFactor: 0.95),
        FamilyDRow(day: "Monday", category: "Pushing Move 1", rmType: .rm5, weekOneFactor: 0.95),
        FamilyDRow(day: "Monday", category: "Hamstring Move", rmType: .rm8, weekOneFactor: 0.95),
        FamilyDRow(day: "Tuesday", category: "Legs Move 2", rmType: .rm5, weekOneFactor: 0.95),
        FamilyDRow(day: "Tuesday", category: "Pushing Move 2", rmType: .rm5, weekOneFactor: 0.95),
        FamilyDRow(day: "Tuesday", category: "Upper Body Pulling Move 1", rmType: .rm8, weekOneFactor: 0.95),
        FamilyDRow(day: "Tuesday", category: "Shoulder Move 1", rmType: .rm8, weekOneFactor: 0.95),
        FamilyDRow(day: "Thursday", category: "Deadlift Move", rmType: .rm5, weekOneFactor: 0.95),
        FamilyDRow(day: "Thursday", category: "Legs Move 1", rmType: .rm5, weekOneFactor: 0.95),
        FamilyDRow(day: "Thursday", category: "Upper Body Pulling Move 2", rmType: .rm8, weekOneFactor: 0.95),
        FamilyDRow(day: "Thursday", category: "Shoulder Move 2", rmType: .rm8, weekOneFactor: 0.95),
        FamilyDRow(day: "Friday", category: "Pushing Move 1", rmType: .rm5, weekOneFactor: 0.95),
        FamilyDRow(day: "Friday", category: "Legs Move 2", rmType: .rm5, weekOneFactor: 0.7),
        FamilyDRow(day: "Friday", category: "Upper Body Pulling Move 1", rmType: .rm8, weekOneFactor: 0.95),
        FamilyDRow(day: "Friday", category: "Shoulder Move 1", rmType: .rm8, weekOneFactor: 0.95),
    ]

    func testFamilyDExactlySixteenRowsFourFourFourFourAcrossFourDays() throws {
        let definition = generate(family: .d)
        XCTAssertEqual(definition.orderedTemplateSessions.map(\.name), ["Monday", "Tuesday", "Thursday", "Friday"])
        for session in definition.orderedTemplateSessions {
            XCTAssertEqual(session.orderedBlockTemplates.first?.orderedPrescriptionTemplates.count, 4, "\(session.name) must have exactly 4 rows")
        }
        let total = definition.orderedTemplateSessions.reduce(0) { $0 + ($1.orderedBlockTemplates.first?.orderedPrescriptionTemplates.count ?? 0) }
        XCTAssertEqual(total, 16)
        for fixture in familyDFixture { _ = try row(fixture.day, fixture.category, in: definition) }
    }

    func testFamilyDFiveWeekMesocycleStructure() {
        let definition = generate(family: .d)
        XCTAssertEqual(definition.lengthWeeks, 5)
        XCTAssertEqual(definition.orderedWeeks.count, 5)
        XCTAssertEqual(definition.orderedWeeks.filter(\.isDeload).count, 1)
        XCTAssertEqual(definition.orderedWeeks.last?.isDeload, true)
    }

    func testFamilyDRMTypePerSlot() throws {
        let definition = generate(family: .d)
        for fixture in familyDFixture {
            let template = try row(fixture.day, fixture.category, in: definition)
            guard case .rmBased(let payload) = try XCTUnwrap(template.rules?.loadRule) else { return XCTFail("\(fixture.day)/\(fixture.category)") }
            XCTAssertEqual(payload.rmType, fixture.rmType, "\(fixture.day)/\(fixture.category)")
        }
    }

    func testFamilyDWeekOneFactorPerSlotAndRelocatedTriples() throws {
        let definition = generate(family: .d)
        for fixture in familyDFixture {
            let template = try row(fixture.day, fixture.category, in: definition)
            guard case .rmBased(let payload) = try XCTUnwrap(template.rules?.loadRule) else { return XCTFail("\(fixture.day)/\(fixture.category)") }
            XCTAssertEqual(payload.weekOneFactor, fixture.weekOneFactor, accuracy: 0.0001, "\(fixture.day)/\(fixture.category)")
        }
        // The Triples protocol is relocated to Friday-Legs2 (0.7x, fixed
        // 3-rep schedule) — NOT Monday-Push1/Thursday-Deadlift (stock
        // Family B's own Triples slots, which are ordinary 0.95x here).
        let friLegs2 = try row("Friday", "Legs Move 2", in: definition)
        XCTAssertEqual(friLegs2.rules?.repGoalSchedule, Array(repeating: RepGoal.fixedReps(3), count: 4))
        for (day, category) in [("Monday", "Pushing Move 1"), ("Thursday", "Deadlift Move")] {
            let template = try row(day, category, in: definition)
            XCTAssertEqual(template.rules?.repGoalSchedule, [.rir(2), .rir(2), .rir(2), .rir(1)], "\(day)/\(category) must be ordinary, not Triples")
        }
    }

    func testFamilyDWeeklyProgressionMultipliersMatchSharedFamily() throws {
        let definition = generate(family: .d)
        let template = try row("Monday", "Deadlift Move", in: definition)
        guard case .rmBased(let payload) = try XCTUnwrap(template.rules?.loadRule) else { return XCTFail() }
        XCTAssertEqual(payload.laterWeekMultipliers, [1.05, 1.075, 1.1])
    }

    func testFamilyDCompleteCrossDayAutoregulationGraph() throws {
        let definition = generate(family: .d)
        let expectedPairing: [(String, String, String, String)] = [
            ("Monday", "Deadlift Move", "Thursday", "Deadlift Move"),
            ("Monday", "Legs Move 1", "Thursday", "Legs Move 1"),
            ("Monday", "Pushing Move 1", "Friday", "Pushing Move 1"),
            ("Tuesday", "Legs Move 2", "Thursday", "Legs Move 1"),
            ("Tuesday", "Pushing Move 2", "Friday", "Pushing Move 1"),
            ("Thursday", "Deadlift Move", "Monday", "Deadlift Move"),
            ("Thursday", "Legs Move 1", "Tuesday", "Legs Move 2"),
            ("Friday", "Pushing Move 1", "Tuesday", "Pushing Move 2"),
            ("Friday", "Legs Move 2", "Thursday", "Legs Move 1"),
        ]
        for (day, category, pairedDay, pairedCategory) in expectedPairing {
            let template = try row(day, category, in: definition)
            let expectedPaired = try row(pairedDay, pairedCategory, in: definition)
            XCTAssertEqual(template.pairedSlot?.id, expectedPaired.id, "\(day)/\(category) must pair to \(pairedDay)/\(pairedCategory)")
        }
        // Fixed-schedule accessory rows: never autoregulated.
        for (day, category) in [("Monday", "Hamstring Move"), ("Tuesday", "Upper Body Pulling Move 1"), ("Tuesday", "Shoulder Move 1"), ("Thursday", "Upper Body Pulling Move 2"), ("Thursday", "Shoulder Move 2"), ("Friday", "Upper Body Pulling Move 1"), ("Friday", "Shoulder Move 1")] {
            let template = try row(day, category, in: definition)
            XCTAssertNil(template.pairedSlot, "\(day)/\(category) is a fixed-schedule accessory row")
            XCTAssertEqual(template.rules?.setCountRule, .fixed(setsByWeek: [2, 2, 3, 3]))
        }
        // No row in this pairing set has anything pointing back to
        // Monday-Legs1 — a genuine, confirmed one-way pairing (its own
        // rating is read by no other row), re-verified directly.
        let monLegs1 = try row("Monday", "Legs Move 1", in: definition)
        let allTemplates = definition.orderedTemplateSessions.flatMap { $0.orderedBlockTemplates.first?.orderedPrescriptionTemplates ?? [] }
        XCTAssertFalse(allTemplates.contains { $0.pairedSlot?.id == monLegs1.id }, "nothing sources its rating from Monday-Legs1")
    }

    func testFamilyDWeekFourAdditiveVsFrozenByDayPosition() throws {
        let definition = generate(family: .d)
        for (day, category) in [("Monday", "Deadlift Move"), ("Monday", "Legs Move 1"), ("Monday", "Pushing Move 1"), ("Tuesday", "Legs Move 2"), ("Tuesday", "Pushing Move 2")] {
            let template = try row(day, category, in: definition)
            guard case .autoregulated(let payload) = try XCTUnwrap(template.rules?.setCountRule) else { return XCTFail("\(day)/\(category)") }
            XCTAssertTrue(payload.applyRatingOnFinalWeek, "\(day)/\(category) must stay additive at week 4")
        }
        for (day, category) in [("Thursday", "Deadlift Move"), ("Thursday", "Legs Move 1"), ("Friday", "Pushing Move 1"), ("Friday", "Legs Move 2")] {
            let template = try row(day, category, in: definition)
            guard case .autoregulated(let payload) = try XCTUnwrap(template.rules?.setCountRule) else { return XCTFail("\(day)/\(category)") }
            XCTAssertFalse(payload.applyRatingOnFinalWeek, "\(day)/\(category) must freeze at week 4")
        }
    }

    func testFamilyDDeloadWeightSplitByDayPosition() throws {
        let definition = generate(family: .d)
        for (day, category) in [("Monday", "Deadlift Move"), ("Tuesday", "Legs Move 2")] {
            let template = try row(day, category, in: definition)
            XCTAssertEqual(template.rules?.deloadWeightPositionOverride?.fullPositionFactor, 0.7, "\(day) deload weight = 0.7x")
        }
        for (day, category) in [("Thursday", "Deadlift Move"), ("Friday", "Legs Move 2")] {
            let template = try row(day, category, in: definition)
            XCTAssertEqual(template.rules?.deloadWeightPositionOverride?.halfPositionFactor, 0.5, "\(day) deload weight = 0.5x")
        }
    }

    func testFamilyDDeloadRepBehaviorIncludingTriplesException() throws {
        let definition = generate(family: .d)
        // Ordinary Monday/Tuesday rows: 2/3.
        let monDeadlift = try row("Monday", "Deadlift Move", in: definition)
        XCTAssertEqual(monDeadlift.rules?.deloadRepPositionOverride?.fullPositionFactor, 2.0 / 3.0)
        // Ordinary Thursday/Friday rows: 1/2.
        let thuDeadlift = try row("Thursday", "Deadlift Move", in: definition)
        XCTAssertEqual(thuDeadlift.rules?.deloadRepPositionOverride?.halfPositionFactor, 0.5)
        // The relocated Triples row is the one disclosed exception: "Same
        // reps as Week 1" (fraction 1.0), bypassing the day-position
        // split entirely — re-verified directly against the source cell.
        let friLegs2 = try row("Friday", "Legs Move 2", in: definition)
        XCTAssertNil(friLegs2.rules?.deloadRepPositionOverride, "Triples row bypasses the position split")
        XCTAssertEqual(friLegs2.rules?.deloadRepFraction, 1.0, "Same reps as Week 1")
    }

    func testFamilyDNoLinkedToPairedSlotLoadRelationshipExistsAnywhere() throws {
        let definition = generate(family: .d)
        for fixture in familyDFixture {
            let template = try row(fixture.day, fixture.category, in: definition)
            guard case .rmBased = try XCTUnwrap(template.rules?.loadRule) else {
                return XCTFail("\(fixture.day)/\(fixture.category) must be .rmBased — Family D has no load-linked backoff")
            }
        }
    }

    func testFamilyDNoFabricatedRows() throws {
        let definition = generate(family: .d)
        let allSlotKeys = definition.orderedTemplateSessions.flatMap { session in
            (session.orderedBlockTemplates.first?.orderedPrescriptionTemplates ?? []).map { "\(session.name)|\($0.exerciseSlot?.name ?? "?")" }
        }
        let expectedKeys = Set(familyDFixture.map { "\($0.day)|\($0.category)" })
        XCTAssertEqual(Set(allSlotKeys), expectedKeys)
        XCTAssertEqual(allSlotKeys.count, 16)
    }

    // MARK: - Canonical Family E fixture (Strength_Program_2.xlsx) —
    // every one of the 16 real rows, all uniform 10RM.

    private let familyERows: [(String, String)] = [
        ("Monday", "Deadlift Move"), ("Monday", "Legs Move 1"), ("Monday", "Pushing Move 1"), ("Monday", "Hamstring Move"),
        ("Tuesday", "Legs Move 2"), ("Tuesday", "Pushing Move 2"), ("Tuesday", "Upper Body Pulling Move 1"), ("Tuesday", "Shoulder Move 1"),
        ("Thursday", "Deadlift Move"), ("Thursday", "Legs Move 1"), ("Thursday", "Upper Body Pulling Move 2"), ("Thursday", "Shoulder Move 2"),
        ("Friday", "Pushing Move 1"), ("Friday", "Legs Move 2"), ("Friday", "Upper Body Pulling Move 1"), ("Friday", "Shoulder Move 1"),
    ]

    func testFamilyEExactlySixteenRowsFourFourFourFourAcrossFourDaysNoWednesday() throws {
        let definition = generate(family: .e)
        XCTAssertEqual(definition.orderedTemplateSessions.map(\.name), ["Monday", "Tuesday", "Thursday", "Friday"], "Wednesday must be genuinely absent")
        for session in definition.orderedTemplateSessions {
            XCTAssertEqual(session.orderedBlockTemplates.first?.orderedPrescriptionTemplates.count, 4, "\(session.name) must have exactly 4 rows")
        }
        let total = definition.orderedTemplateSessions.reduce(0) { $0 + ($1.orderedBlockTemplates.first?.orderedPrescriptionTemplates.count ?? 0) }
        XCTAssertEqual(total, 16)
        for (day, category) in familyERows { _ = try row(day, category, in: definition) }
    }

    func testFamilyEHamstringPresentOnce() throws {
        let definition = generate(family: .e)
        _ = try row("Monday", "Hamstring Move", in: definition)
        // Confirmed only once — never a second Hamstring row anywhere.
        let allHamstring = definition.orderedTemplateSessions.flatMap { session in
            (session.orderedBlockTemplates.first?.orderedPrescriptionTemplates ?? []).filter { $0.exerciseSlot?.name == "Hamstring Move" }
        }
        XCTAssertEqual(allHamstring.count, 1)
    }

    func testFamilyEUniform10RMCalibration() throws {
        let definition = generate(family: .e)
        for (day, category) in familyERows {
            let template = try row(day, category, in: definition)
            guard case .rmBased(let payload) = try XCTUnwrap(template.rules?.loadRule) else { return XCTFail("\(day)/\(category)") }
            XCTAssertEqual(payload.rmType, .rm10, "\(day)/\(category)")
        }
    }

    func testFamilyEWeekOneFactorAndBackoffIsPlainRMBasedNotLinkedToPairedSlot() throws {
        let definition = generate(family: .e)
        for (day, category) in familyERows where category != "Legs Move 2" || day != "Friday" {
            let template = try row(day, category, in: definition)
            guard case .rmBased(let payload) = try XCTUnwrap(template.rules?.loadRule) else { return XCTFail("\(day)/\(category)") }
            XCTAssertEqual(payload.weekOneFactor, 0.95, accuracy: 0.0001, "\(day)/\(category)")
        }
        // The Friday backoff: plain `.rmBased` at 0.85x, sharing "Legs
        // Move 2" with Tuesday's row — deliberately NOT
        // `.linkedToPairedSlot`, unlike stock Family C's own backoff. The
        // source formula (`D36 = MROUND(G4*0.85,2.5)`) reads the RM cell
        // directly, never Tuesday's resolved result.
        let backoff = try row("Friday", "Legs Move 2", in: definition)
        guard case .rmBased(let payload) = try XCTUnwrap(backoff.rules?.loadRule) else { return XCTFail("Friday backoff must be .rmBased") }
        XCTAssertEqual(payload.weekOneFactor, 0.85, accuracy: 0.0001)
        XCTAssertEqual(payload.rmType, .rm10)
    }

    func testFamilyERIRProgressionMatchesStockFamilyCRamp() throws {
        let definition = generate(family: .e)
        let template = try row("Monday", "Deadlift Move", in: definition)
        XCTAssertEqual(template.rules?.repGoalSchedule, [.rir(3), .rir(3), .rir(2), .rir(1)])
    }

    func testFamilyEWeeklyProgressionMultipliersMatchSharedFamily() throws {
        let definition = generate(family: .e)
        let template = try row("Monday", "Deadlift Move", in: definition)
        guard case .rmBased(let payload) = try XCTUnwrap(template.rules?.loadRule) else { return XCTFail() }
        XCTAssertEqual(payload.laterWeekMultipliers, [1.05, 1.075, 1.1])
    }

    func testFamilyECompleteCrossDayAutoregulationGraph() throws {
        let definition = generate(family: .e)
        let expectedPairing: [(String, String, String, String)] = [
            ("Monday", "Deadlift Move", "Thursday", "Deadlift Move"),
            ("Monday", "Legs Move 1", "Thursday", "Legs Move 1"),
            ("Monday", "Pushing Move 1", "Friday", "Pushing Move 1"),
            ("Tuesday", "Legs Move 2", "Thursday", "Legs Move 1"),
            ("Tuesday", "Pushing Move 2", "Friday", "Pushing Move 1"),
            ("Thursday", "Deadlift Move", "Monday", "Deadlift Move"),
            ("Thursday", "Legs Move 1", "Tuesday", "Legs Move 2"),
            ("Friday", "Pushing Move 1", "Tuesday", "Pushing Move 2"),
            ("Friday", "Legs Move 2", "Thursday", "Legs Move 1"),
        ]
        for (day, category, pairedDay, pairedCategory) in expectedPairing {
            let template = try row(day, category, in: definition)
            let expectedPaired = try row(pairedDay, pairedCategory, in: definition)
            XCTAssertEqual(template.pairedSlot?.id, expectedPaired.id, "\(day)/\(category) must pair to \(pairedDay)/\(pairedCategory)")
        }
        // The Friday backoff's rating pairing is to Thursday-Legs1 — a
        // DIFFERENT row than its own "1/2 Tuesday's" rep-count
        // relationship (to Tuesday-Legs2) — the two must never be
        // conflated into one reference.
        let backoff = try row("Friday", "Legs Move 2", in: definition)
        let thuLegs1 = try row("Thursday", "Legs Move 1", in: definition)
        let tueLegs2 = try row("Tuesday", "Legs Move 2", in: definition)
        XCTAssertEqual(backoff.pairedSlot?.id, thuLegs1.id)
        XCTAssertNotEqual(backoff.pairedSlot?.id, tueLegs2.id)
        for (day, category) in [("Monday", "Hamstring Move"), ("Tuesday", "Upper Body Pulling Move 1"), ("Tuesday", "Shoulder Move 1"), ("Thursday", "Upper Body Pulling Move 2"), ("Thursday", "Shoulder Move 2"), ("Friday", "Upper Body Pulling Move 1"), ("Friday", "Shoulder Move 1")] {
            let template = try row(day, category, in: definition)
            XCTAssertNil(template.pairedSlot, "\(day)/\(category) is a fixed-schedule accessory row")
        }
    }

    func testFamilyEWeekFourAdditiveVsFrozenByDayPosition() throws {
        let definition = generate(family: .e)
        for (day, category) in [("Monday", "Deadlift Move"), ("Monday", "Legs Move 1"), ("Monday", "Pushing Move 1"), ("Tuesday", "Legs Move 2"), ("Tuesday", "Pushing Move 2")] {
            let template = try row(day, category, in: definition)
            guard case .autoregulated(let payload) = try XCTUnwrap(template.rules?.setCountRule) else { return XCTFail("\(day)/\(category)") }
            XCTAssertTrue(payload.applyRatingOnFinalWeek, "\(day)/\(category) must stay additive at week 4")
        }
        for (day, category) in [("Thursday", "Deadlift Move"), ("Thursday", "Legs Move 1"), ("Friday", "Pushing Move 1"), ("Friday", "Legs Move 2")] {
            let template = try row(day, category, in: definition)
            guard case .autoregulated(let payload) = try XCTUnwrap(template.rules?.setCountRule) else { return XCTFail("\(day)/\(category)") }
            XCTAssertFalse(payload.applyRatingOnFinalWeek, "\(day)/\(category) must freeze at week 4")
        }
    }

    func testFamilyEDeloadWeightMondayTuesdayUnchangedThursdayFridayHalved() throws {
        let definition = generate(family: .e)
        for (day, category) in [("Monday", "Deadlift Move"), ("Tuesday", "Legs Move 2")] {
            let template = try row(day, category, in: definition)
            XCTAssertEqual(template.rules?.deloadWeightPositionOverride?.fullPositionFactor, 1.0, "\(day) deload weight unchanged (source's literal =D_, no reduction)")
        }
        for (day, category) in [("Thursday", "Deadlift Move"), ("Friday", "Legs Move 2")] {
            let template = try row(day, category, in: definition)
            XCTAssertEqual(template.rules?.deloadWeightPositionOverride?.halfPositionFactor, 0.5, "\(day) deload weight halved")
        }
    }

    func testFamilyEDeloadRepBehaviorUniformExceptBackoffException() throws {
        let definition = generate(family: .e)
        // Every ordinary row: uniform 0.5, no day-position split (unlike
        // Family D) — matches stock Family C's own convention.
        for (day, category) in familyERows where !(day == "Friday" && category == "Legs Move 2") {
            let template = try row(day, category, in: definition)
            XCTAssertNil(template.rules?.deloadRepPositionOverride, "\(day)/\(category) has no day-position rep split")
            XCTAssertEqual(template.rules?.deloadRepFraction, 0.5, "\(day)/\(category)")
        }
        // The Friday backoff: "Same reps as Week 1" (fraction 1.0).
        let backoff = try row("Friday", "Legs Move 2", in: definition)
        XCTAssertEqual(backoff.rules?.deloadRepFraction, 1.0)
    }

    func testFamilyENoFabricatedRows() throws {
        let definition = generate(family: .e)
        let allSlotKeys = definition.orderedTemplateSessions.flatMap { session in
            (session.orderedBlockTemplates.first?.orderedPrescriptionTemplates ?? []).map { "\(session.name)|\($0.exerciseSlot?.name ?? "?")" }
        }
        let expectedKeys = Set(familyERows.map { "\($0.0)|\($0.1)" })
        XCTAssertEqual(Set(allSlotKeys), expectedKeys)
        XCTAssertEqual(allSlotKeys.count, 16)
    }

    // MARK: - Dogfood: real materialization through the production path.
    // Family D: week 0 + rolled through weeks 1-4 + deload. Family E:
    // week 0 (structural dogfood proof — both are the same materializer,
    // the mechanism is proven once end-to-end, verified structurally for
    // the second).

    func testDogfoodFamilyDWeekZeroMaterializationAndFullFiveWeekRoll() throws {
        let definition = generate(family: .d)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition
        let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)

        // TEST FIXTURE RM values — representative, not real athlete
        // source data (both workbooks ship with blank athlete inputs).
        let rmByRow: [String: Double] = [
            "Monday|Deadlift Move": 100, "Monday|Legs Move 1": 80, "Monday|Pushing Move 1": 60, "Monday|Hamstring Move": 20,
            "Tuesday|Legs Move 2": 80, "Tuesday|Pushing Move 2": 60, "Tuesday|Upper Body Pulling Move 1": 40, "Tuesday|Shoulder Move 1": 20,
            "Thursday|Deadlift Move": 100, "Thursday|Legs Move 1": 80, "Thursday|Upper Body Pulling Move 2": 40, "Thursday|Shoulder Move 2": 20,
            "Friday|Pushing Move 1": 60, "Friday|Legs Move 2": 80, "Friday|Upper Body Pulling Move 1": 40, "Friday|Shoulder Move 1": 20,
        ]

        func keyFor(slot: ExerciseSlot) -> String {
            for session in definition.orderedTemplateSessions {
                for template in session.orderedBlockTemplates.first?.orderedPrescriptionTemplates ?? [] where template.exerciseSlot?.id == slot.id {
                    return "\(session.name)|\(slot.name)"
                }
            }
            return "unknown|\(slot.name)"
        }

        let week0 = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: instance.ownerUserID, equipmentProfile: equipment,
            slotContext: { slot in StrengthMaterializer.SlotContext(rmKilograms: rmByRow[keyFor(slot: slot)]) },
            context: context
        )
        XCTAssertEqual(week0.sessions.count, 4, "one real Session per real training day")
        var checkedCount = 0
        for session in week0.sessions {
            for block in session.orderedBlocks {
                for prescription in block.orderedPrescriptions {
                    guard let slot = prescription.sourcePrescriptionTemplate?.exerciseSlot else { continue }
                    let key = keyFor(slot: slot)
                    guard let rm = rmByRow[key] else { continue }
                    guard let fixture = familyDFixture.first(where: { "\($0.day)|\($0.category)" == key }) else { continue }
                    let expected = equipment.resolve(IdealLoad(kilograms: rm * fixture.weekOneFactor))
                    XCTAssertEqual(prescription.orderedSetPrescriptions.first?.targetWeight ?? -1, expected, accuracy: 0.01, "\(key) week-1 materialized weight")
                    checkedCount += 1
                }
            }
        }
        XCTAssertEqual(checkedCount, 16, "every one of the 16 real rows must have materialized and been checked")
        XCTAssertEqual(week0.resolvedWeightsBySlotID.count, 16)

        // Roll the Monday-Deadlift row through weeks 1-4 + deload,
        // exactly mirroring the established Hypertrophy/Powerlifting
        // rollforward dogfood pattern: weeks 2-4 anchor off the resolved
        // Week-1 value, never chained week-to-week.
        let monDeadliftTemplate = try row("Monday", "Deadlift Move", in: definition)
        let weekOneResolvedWeightKg = try XCTUnwrap(week0.resolvedWeightsBySlotID[try XCTUnwrap(monDeadliftTemplate.exerciseSlot?.id)])

        func materializeMonDeadlift(weekIndex: Int, isDeload: Bool) -> ExercisePrescription {
            let result = StrengthMaterializer.materializeWeek(
                definition: definition, instance: instance, weekIndex: weekIndex, isDeload: isDeload,
                startDate: Date(timeIntervalSince1970: 0), ownerUserID: instance.ownerUserID, equipmentProfile: equipment,
                slotContext: { _ in .init(weekOneResolvedWeightKg: weekOneResolvedWeightKg, previousWeekSetCount: 2, autoregulationRating: 0) },
                context: context
            )
            return result.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).first { $0.sourcePrescriptionTemplate?.id == monDeadliftTemplate.id }!
        }

        let week1 = materializeMonDeadlift(weekIndex: 1, isDeload: false)
        let week2 = materializeMonDeadlift(weekIndex: 2, isDeload: false)
        let week3 = materializeMonDeadlift(weekIndex: 3, isDeload: false)
        XCTAssertEqual(week1.orderedSetPrescriptions.first?.targetWeight ?? -1, equipment.resolve(IdealLoad(kilograms: weekOneResolvedWeightKg * 1.05)), accuracy: 0.0001, "Week 2")
        XCTAssertEqual(week2.orderedSetPrescriptions.first?.targetWeight ?? -1, equipment.resolve(IdealLoad(kilograms: weekOneResolvedWeightKg * 1.075)), accuracy: 0.0001, "Week 3")
        XCTAssertEqual(week3.orderedSetPrescriptions.first?.targetWeight ?? -1, equipment.resolve(IdealLoad(kilograms: weekOneResolvedWeightKg * 1.1)), accuracy: 0.0001, "Week 4")

        let deload = materializeMonDeadlift(weekIndex: 4, isDeload: true)
        // Monday is day position 0 (< boundary 2) -> full deload factor
        // 0.7x, per Family D's own recovered deload split.
        XCTAssertEqual(deload.orderedSetPrescriptions.first?.targetWeight ?? -1, equipment.resolve(IdealLoad(kilograms: weekOneResolvedWeightKg * 0.7)), accuracy: 0.0001, "deload weight = 0.7x Week 1 for Monday")
        XCTAssertEqual(deload.appliedRepGoalReasonCode, .deloadRepsRequireLoggedPerformanceData, "deload reps remain unresolved, never fabricated — matches every other family's established treatment")
    }

    func testDogfoodFamilyEWeekZeroMaterializationMatchesStructuralFixture() throws {
        let definition = generate(family: .e)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition
        let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)

        // TEST FIXTURE RM values — representative, not real athlete
        // source data.
        let rm: Double = 100

        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: instance.ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: rm) }, context: context
        )
        XCTAssertEqual(result.sessions.count, 4, "one real Session per real training day (no Wednesday)")
        let backoffTemplate = try row("Friday", "Legs Move 2", in: definition)
        let backoffPrescription = try XCTUnwrap(result.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).first { $0.sourcePrescriptionTemplate?.id == backoffTemplate.id })
        XCTAssertEqual(backoffPrescription.orderedSetPrescriptions.first?.targetWeight ?? -1, equipment.resolve(IdealLoad(kilograms: rm * 0.85)), accuracy: 0.01, "Friday backoff resolves independently from the same RM, at its own 0.85x factor")
        XCTAssertEqual(result.resolvedWeightsBySlotID.count, 16)
    }

    // MARK: - Blocker 1 completion pass: Family E Friday-Legs2 backoff
    // rep goal, derived from Tuesday-Legs2's ACTUAL logged reps
    // (`Strength_Program_2.xlsx`'s own footnote "1/2 Tuesday's").

    private func makePerformanceProfile() -> PerformanceProfile {
        let profile = PerformanceProfile()
        context.insert(profile)
        return profile
    }

    private func makeExercise(_ name: String) -> Exercise {
        let exercise = Exercise(canonicalName: name, modality: .strength, equipment: "barbell", movementPattern: "squat")
        context.insert(exercise)
        return exercise
    }

    /// Materializes Family E's real week 0 with every slot's exercise
    /// explicitly resolved (so `LogSetUseCase` — which requires a real,
    /// non-optional `Exercise` — can log against them), through the real
    /// production `StrengthMaterializer` path.
    private func materializeFamilyEWeekZero() throws -> (instance: ProgramInstance, tuesday: Session, friday: Session, profile: PerformanceProfile) {
        let definition = generate(family: .e)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition
        let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)
        for session in definition.orderedTemplateSessions {
            for template in session.orderedBlockTemplates.first?.orderedPrescriptionTemplates ?? [] {
                template.exerciseSlot?.resolvedExercise = makeExercise("\(session.name) \(template.exerciseSlot?.name ?? "")")
            }
        }
        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: instance.ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )
        // Identify Tuesday/Friday unambiguously via each materialized
        // prescription's own `sourcePrescriptionTemplate` — which traces
        // back to a named `TemplateSession` via `workoutBlockTemplate`
        // (`Session` itself carries no day-name field).
        func sessionNamed(_ name: String) throws -> Session {
            try XCTUnwrap(result.sessions.first { session in
                session.orderedBlocks.flatMap(\.orderedPrescriptions).contains { prescription in
                    prescription.sourcePrescriptionTemplate?.workoutBlockTemplate?.templateSession?.name == name
                }
            }, "no \(name) session")
        }
        let realTuesday = try sessionNamed("Tuesday")
        let realFriday = try sessionNamed("Friday")
        let profile = makePerformanceProfile()
        return (instance, realTuesday, realFriday, profile)
    }

    private func logTuesdayLegs2Reps(_ reps: [Int], tuesday: Session, profile: PerformanceProfile) throws {
        let prescription = try XCTUnwrap(tuesday.orderedBlocks.flatMap(\.orderedPrescriptions).first {
            $0.sourcePrescriptionTemplate?.exerciseSlot?.name == "Legs Move 2"
        }, "Tuesday's Legs Move 2 prescription")
        let exercise = try XCTUnwrap(prescription.exercise)
        for (setPrescription, actualReps) in zip(prescription.orderedSetPrescriptions, reps) {
            try LogSetUseCase.logSet(
                setIndex: setPrescription.sortIndex, weight: setPrescription.targetWeight ?? 50,
                reps: actualReps, targetRir: setPrescription.targetRir, actualRir: setPrescription.targetRir,
                prBand: nil, scoringDirection: .higherIsBetter, context: .rx, setPrescription: setPrescription,
                exercisePrescription: prescription, exercise: exercise, performanceProfile: profile,
                completedAt: Date(), modelContext: context
            )
        }
    }

    private func fridayBackoffPrescription(friday: Session) throws -> ExercisePrescription {
        try XCTUnwrap(friday.orderedBlocks.flatMap(\.orderedPrescriptions).first {
            $0.sourcePrescriptionTemplate?.exerciseSlot?.name == "Legs Move 2"
        }, "Friday's Legs Move 2 backoff prescription")
    }

    /// At week-materialization time (before Tuesday has been performed),
    /// Friday's backoff rep goal must be honestly unresolved — never the
    /// old placeholder RIR schedule, never a fabricated number.
    func testFamilyEFridayBackoffRepGoalHonestlyUnresolvedAtMaterializationTime() throws {
        let (_, _, friday, _) = try materializeFamilyEWeekZero()
        let prescription = try fridayBackoffPrescription(friday: friday)
        XCTAssertEqual(prescription.appliedRepGoalReasonCode, .repGoalRequiresPriorSlotActualResult)
        for setPrescription in prescription.orderedSetPrescriptions {
            XCTAssertNil(setPrescription.repRangeLow, "must never fabricate a target before Tuesday has been performed")
            XCTAssertNil(setPrescription.targetRir, "must never silently fall back to an RIR placeholder")
        }
    }

    /// The canonical source footnote fixture, exactly as recovered:
    /// Tuesday logs 10,8,8,8,7,7 across its real 6 sets; Friday (2 sets)
    /// must resolve to exactly 5,4 — per-set-index halved, floored.
    func testFamilyEFridayBackoffResolvesFromTuesdayActualLoggedRepsCanonicalFootnoteFixture() throws {
        let (instance, tuesday, friday, profile) = try materializeFamilyEWeekZero()
        XCTAssertEqual(tuesday.orderedBlocks.flatMap(\.orderedPrescriptions).first { $0.sourcePrescriptionTemplate?.exerciseSlot?.name == "Legs Move 2" }?.orderedSetPrescriptions.count, 6, "Family E's own Tuesday-Legs2 baseline is 6 sets — matches the footnote's own worked example exactly")
        try logTuesdayLegs2Reps([10, 8, 8, 8, 7, 7], tuesday: tuesday, profile: profile)
        _ = try CompleteSessionUseCase.complete(tuesday, context: .full, asOf: Date(), modelContext: context)

        let backoff = try fridayBackoffPrescription(friday: friday)
        XCTAssertEqual(backoff.orderedSetPrescriptions.count, 2, "Friday's own baseline set count")
        let resolved = backoff.orderedSetPrescriptions.sorted { $0.sortIndex < $1.sortIndex }.map(\.repRangeLow)
        XCTAssertEqual(resolved, [5, 4], "floor(10/2)=5, floor(8/2)=4 — the exact source footnote worked example")
        for setPrescription in backoff.orderedSetPrescriptions {
            XCTAssertEqual(setPrescription.repRangeHigh, setPrescription.repRangeLow)
            XCTAssertNil(setPrescription.targetRir, "resolved via the actual-result rule, never also carrying a fabricated RIR")
        }
        XCTAssertEqual(backoff.appliedRepGoalReasonCode, .repGoalSchedule)
        _ = instance
    }

    /// Always rounds DOWN on an odd actual rep count (established,
    /// universal — same convention as every other deload/rep rounding
    /// rule in this codebase).
    func testFamilyEFridayBackoffRoundsDownOnOddActualReps() throws {
        let (_, tuesday, friday, profile) = try materializeFamilyEWeekZero()
        try logTuesdayLegs2Reps([7, 9, 8, 8, 7, 7], tuesday: tuesday, profile: profile)
        _ = try CompleteSessionUseCase.complete(tuesday, context: .full, asOf: Date(), modelContext: context)
        let backoff = try fridayBackoffPrescription(friday: friday)
        let resolved = backoff.orderedSetPrescriptions.sorted { $0.sortIndex < $1.sortIndex }.map(\.repRangeLow)
        XCTAssertEqual(resolved, [3, 4], "floor(7/2)=3 (rounds down, never up), floor(9/2)=4")
    }

    /// Honest "not yet available" state — Tuesday has not been completed
    /// at all — must never fabricate a target or fall back to RIR.
    func testFamilyEFridayBackoffStaysPendingWhenTuesdayNotYetCompleted() throws {
        let (_, _, friday, _) = try materializeFamilyEWeekZero()
        // Deliberately do NOT log or complete Tuesday.
        let backoff = try fridayBackoffPrescription(friday: friday)
        for setPrescription in backoff.orderedSetPrescriptions {
            XCTAssertNil(setPrescription.repRangeLow)
            XCTAssertNil(setPrescription.targetRir)
        }
        XCTAssertEqual(backoff.appliedRepGoalReasonCode, .repGoalRequiresPriorSlotActualResult)
    }

    /// Backfilling Friday must never mutate Tuesday's own logged,
    /// historical `SetResult`s.
    func testFamilyEBackfillNeverMutatesTuesdaysLoggedResults() throws {
        let (_, tuesday, _, profile) = try materializeFamilyEWeekZero()
        try logTuesdayLegs2Reps([10, 8, 8, 8, 7, 7], tuesday: tuesday, profile: profile)
        let tuesdayPrescription = try XCTUnwrap(tuesday.orderedBlocks.flatMap(\.orderedPrescriptions).first { $0.sourcePrescriptionTemplate?.exerciseSlot?.name == "Legs Move 2" })
        let beforeReps = tuesdayPrescription.loggedSetResults.sorted { $0.setIndex < $1.setIndex }.map(\.reps)
        _ = try CompleteSessionUseCase.complete(tuesday, context: .full, asOf: Date(), modelContext: context)
        let afterReps = tuesdayPrescription.loggedSetResults.sorted { $0.setIndex < $1.setIndex }.map(\.reps)
        XCTAssertEqual(beforeReps, afterReps, "Tuesday's own logged results must be byte-for-byte unchanged by resolving Friday's dependent row")
        XCTAssertEqual(beforeReps, [10, 8, 8, 8, 7, 7])
    }

    /// Idempotent: completing Tuesday twice (e.g. a double-tapped Finish
    /// button) must never re-resolve/duplicate/corrupt Friday's already-
    /// backfilled targets.
    func testFamilyEBackfillIsIdempotentAcrossRepeatedSessionCompletion() throws {
        let (_, tuesday, friday, profile) = try materializeFamilyEWeekZero()
        try logTuesdayLegs2Reps([10, 8, 8, 8, 7, 7], tuesday: tuesday, profile: profile)
        _ = try CompleteSessionUseCase.complete(tuesday, context: .full, asOf: Date(), modelContext: context)
        _ = try CompleteSessionUseCase.complete(tuesday, context: .full, asOf: Date(), modelContext: context)
        let backoff = try fridayBackoffPrescription(friday: friday)
        let resolved = backoff.orderedSetPrescriptions.sorted { $0.sortIndex < $1.sortIndex }.map(\.repRangeLow)
        XCTAssertEqual(resolved, [5, 4])
    }

    // MARK: - Blocker 2 completion pass: `buildCustomMix` capability
    // gating and content-selector wiring for `.strengthTraining`.

    func testBuildCustomMixStrengthTrainingAcceptsExactlyFourAndSetsContentSelector() throws {
        let result = LongTermPlanner.buildCustomMix(selections: [(.strengthTraining, 4)], capacity: 7)
        guard case .success(let mix) = result else { return XCTFail("4/week must be accepted — Strength content's own supported frequency") }
        let component = try XCTUnwrap(mix.orderedComponents.first)
        XCTAssertEqual(component.programmingSystem, .powerlifting)
        XCTAssertEqual(component.strengthContentSelector, .sourceBackedGeneralStrength)
        XCTAssertEqual(component.label, "Strength Training")
    }

    /// 5/week is a REAL, valid Powerlifting engine frequency (Family C) —
    /// but not a real Strength source content frequency. Must fail closed,
    /// never silently approximate to the nearest Strength configuration.
    func testBuildCustomMixStrengthTrainingRejectsFrequencyValidOnlyForPowerlifting() {
        let result = LongTermPlanner.buildCustomMix(selections: [(.strengthTraining, 5)], capacity: 7)
        guard case .failure(let error) = result else { return XCTFail("5/week must be rejected for Strength Training — Powerlifting's own {4,5} must not leak into Strength content's narrower {4}") }
        XCTAssertEqual(error, .unsupportedFrequency(style: .strengthTraining, frequency: 5))
    }
}
