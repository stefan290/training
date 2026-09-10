import XCTest
import SwiftData
@testable import TrainingOS

/// Proves `PowerliftingProgramGenerator`'s structural output for both
/// families — day count/names, per-slot RM type, the Triples protocol,
/// the confirmed Week-4 asymmetry (Family B) / freeze (Family C)
/// parameters, and the Friday backoff's structural `pairedSlot` reference
/// — and that the generated graph survives a real save/refetch cycle.
/// See the generator's own doc comment for what this intentionally does
/// not claim (a complete, realistic per-day exercise selection, or a
/// source-confirmed Family C rep-goal schedule/deload set count for
/// either family).
@MainActor
final class PowerliftingProgramGeneratorTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func freshContext() -> ModelContext {
        ModelContext(container)
    }

    private func generate(family: PowerliftingFamily, dayCount: Int) -> ProgramDefinition {
        PowerliftingProgramGenerator.generate(
            configuration: PowerliftingProgramConfiguration(family: family, dayCount: dayCount),
            provenance: .constructed(reason: "test fixture"),
            context: context
        )
    }

    // MARK: - Family B structure

    func testFamilyBProducesFourNamedDays() throws {
        let definition = generate(family: .b, dayCount: 4)
        XCTAssertEqual(definition.orderedTemplateSessions.map(\.name), ["Monday", "Tuesday", "Thursday", "Friday"])
        XCTAssertEqual(definition.programmingSystem, .powerlifting)
        XCTAssertEqual(definition.powerliftingConfiguration, PowerliftingProgramConfiguration(family: .b, dayCount: 4))
    }

    /// Powerlifting Source Authority Repair: every day now carries its full
    /// real row set, so lookups key on `ExerciseSlot.name` (the real
    /// source category), never `.first` — see
    /// `PowerliftingSourceFidelityTests.swift` for the complete, canonical
    /// per-row fixture comparison this file's own tests do not attempt to
    /// duplicate.
    private func row(_ dayName: String, _ slotName: String, in definition: ProgramDefinition) throws -> PrescriptionTemplate {
        let session = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == dayName })
        let block = try XCTUnwrap(session.orderedBlockTemplates.first)
        return try XCTUnwrap(block.orderedPrescriptionTemplates.first { $0.exerciseSlot?.name == slotName })
    }

    func testFamilyBUsesMixed5And8RMBasisPerSlot() throws {
        let definition = generate(family: .b, dayCount: 4)

        func rmType(_ day: String, _ slot: String) throws -> RMType {
            guard case .rmBased(let payload) = try XCTUnwrap(row(day, slot, in: definition).rules?.loadRule) else {
                XCTFail("expected .rmBased for \(day)/\(slot)")
                return .rm10
            }
            return payload.rmType
        }

        XCTAssertEqual(try rmType("Monday", "Pushing Move 1"), .rm5, "Push1 is a 5RM slot (FAMILY_B_RM_BASIS)")
        XCTAssertEqual(try rmType("Tuesday", "Legs Move 2"), .rm5, "Legs2 is a 5RM slot")
        XCTAssertEqual(try rmType("Thursday", "Deadlift Move"), .rm5, "Deadlift is a 5RM slot")
        XCTAssertEqual(try rmType("Monday", "Hamstring Move"), .rm8, "Hamstring is an 8RM slot")
        XCTAssertEqual(try rmType("Tuesday", "Upper Body Pulling Move 1"), .rm8, "Upper-Pull is an 8RM slot")
        XCTAssertEqual(try rmType("Tuesday", "Shoulder Move 1"), .rm8, "Shoulder is an 8RM slot")
    }

    func testFamilyBTriplesSessionsUseTheLighterFactorAndFlatRepGoal() throws {
        let definition = generate(family: .b, dayCount: 4)
        for (day, slot) in [("Monday", "Pushing Move 1"), ("Thursday", "Deadlift Move")] {
            let template = try row(day, slot, in: definition)
            guard case .rmBased(let payload) = try XCTUnwrap(template.rules?.loadRule) else {
                return XCTFail("expected .rmBased")
            }
            XCTAssertEqual(payload.weekOneFactor, 0.7, accuracy: 0.0001, "\(day)'s \(slot) is a Triples session")
            XCTAssertEqual(template.rules?.repGoalSchedule, Array(repeating: RepGoal.fixedReps(3), count: 4), "\(day)'s rep goal never changes")
        }

        // Friday's Push1 is the SAME RM cell as Monday's Triples row, but
        // an ordinary (not Triples) protocol on this day — confirmed
        // directly from the source (`FAMILY_B_WEEK1_BASELINE`: the factor
        // depends on the session's own protocol label, not the RM type).
        let fridayPush1 = try row("Friday", "Pushing Move 1", in: definition)
        guard case .rmBased(let fridayPayload) = try XCTUnwrap(fridayPush1.rules?.loadRule) else {
            return XCTFail("expected .rmBased")
        }
        XCTAssertEqual(fridayPayload.weekOneFactor, 0.95, accuracy: 0.0001, "Friday's Push1 is ordinary, not Triples")

        let tuesdayLegs2 = try row("Tuesday", "Legs Move 2", in: definition)
        guard case .rmBased(let tuesdayPayload) = try XCTUnwrap(tuesdayLegs2.rules?.loadRule) else {
            return XCTFail("expected .rmBased")
        }
        XCTAssertEqual(tuesdayPayload.weekOneFactor, 0.95, accuracy: 0.0001, "Tuesday's Legs2 is an ordinary, not Triples, session")
    }

    func testFamilyBWeekFourAsymmetryDiffersMondayTuesdayVsThursdayFriday() throws {
        let definition = generate(family: .b, dayCount: 4)

        for (day, slot) in [("Monday", "Deadlift Move"), ("Tuesday", "Legs Move 2")] {
            guard case .autoregulated(let config) = try XCTUnwrap(row(day, slot, in: definition).rules?.setCountRule) else {
                return XCTFail("expected .autoregulated")
            }
            XCTAssertTrue(config.applyRatingOnFinalWeek, "\(day)'s \(slot) keeps applying the rating in Week 4")
        }

        for (day, slot) in [("Thursday", "Deadlift Move"), ("Friday", "Pushing Move 1"), ("Friday", "Legs Move 2")] {
            guard case .autoregulated(let config) = try XCTUnwrap(row(day, slot, in: definition).rules?.setCountRule) else {
                return XCTFail("expected .autoregulated")
            }
            XCTAssertFalse(config.applyRatingOnFinalWeek, "\(day)'s \(slot) Week-4 set count is a flat copy of Week 3")
            XCTAssertNil(config.freezeAfterWeek, "Family B uses the asymmetry shape, not Family C's freeze")
        }
    }

    func testFamilyBFridayAccessoryUsesFixedNeverAutoregulatedSchedule() throws {
        let definition = generate(family: .b, dayCount: 4)
        for slot in ["Upper Body Pulling Move 1", "Shoulder Move 1"] {
            let template = try row("Friday", slot, in: definition)
            XCTAssertEqual(template.rules?.setCountRule, .fixed(setsByWeek: [2, 2, 3, 3]), "8RM accessory row \(slot) never autoregulates")
        }
    }

    /// Every one of the 15 real rows is now present — this is the
    /// checkpoint's own headline structural claim, asserted directly
    /// (not merely inferred from day count). Full per-row content is
    /// `PowerliftingSourceFidelityTests.swift`'s job; this proves only the
    /// row COUNT per day matches the real source (`SOURCE_PROGRAM_MANIFEST.md`
    /// §8): Monday 4, Tuesday 4, Thursday 3, Friday 4 = 15 total, no
    /// fabricated extras, no omissions (in particular: Shoulder is no
    /// longer entirely missing, the prior version's confirmed gap).
    func testFamilyBHasTheCompleteFifteenRealRowsAcrossFourDays() throws {
        let definition = generate(family: .b, dayCount: 4)
        func count(_ day: String) throws -> Int {
            try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == day }?.orderedBlockTemplates.first).orderedPrescriptionTemplates.count
        }
        XCTAssertEqual(try count("Monday"), 4)
        XCTAssertEqual(try count("Tuesday"), 4)
        XCTAssertEqual(try count("Thursday"), 3)
        XCTAssertEqual(try count("Friday"), 4)
        let total = try count("Monday") + count("Tuesday") + count("Thursday") + count("Friday")
        XCTAssertEqual(total, 15, "the complete real Family B row count, not the prior version's 4-row placeholder")
        // Every one of the 10 real categories must appear at least once.
        let allSlotNames = Set(definition.orderedTemplateSessions.flatMap { $0.orderedBlockTemplates.first?.orderedPrescriptionTemplates.compactMap(\.exerciseSlot?.name) ?? [] })
        XCTAssertEqual(allSlotNames, [
            "Legs Move 1", "Legs Move 2", "Pushing Move 1", "Pushing Move 2", "Deadlift Move",
            "Hamstring Move", "Upper Body Pulling Move 1", "Upper Body Pulling Move 2",
            "Shoulder Move 1", "Shoulder Move 2",
        ], "Shoulder (both slots) must no longer be missing — the prior version's confirmed content gap")
    }

    func testFamilyBDeloadUsesTheDocumentedDaySplitFactors() throws {
        let definition = generate(family: .b, dayCount: 4)
        let mondayTemplate = try row("Monday", "Deadlift Move", in: definition)
        XCTAssertEqual(mondayTemplate.rules?.deloadWeightPositionOverride, DeloadPositionOverride(boundaryDayIndex: 2, fullPositionFactor: 0.7, halfPositionFactor: 0.5))
        XCTAssertEqual(mondayTemplate.rules?.deloadRepPositionOverride, DeloadPositionOverride(boundaryDayIndex: 2, fullPositionFactor: 2.0 / 3.0, halfPositionFactor: 0.5))
    }

    // MARK: - Family C structure

    func testFamilyCProducesFiveNamedDays() throws {
        let definition = generate(family: .c, dayCount: 5)
        XCTAssertEqual(definition.orderedTemplateSessions.map(\.name), ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"])
        XCTAssertEqual(definition.powerliftingConfiguration, PowerliftingProgramConfiguration(family: .c, dayCount: 5))
    }

    func testFamilyCUsesUniform10RMBasis() throws {
        let definition = generate(family: .c, dayCount: 5)
        for session in definition.orderedTemplateSessions {
            for template in try XCTUnwrap(session.orderedBlockTemplates.first).orderedPrescriptionTemplates {
                if case .rmBased(let payload) = template.rules?.loadRule {
                    XCTAssertEqual(payload.rmType, .rm10, "\(session.name) should be 10RM-based")
                }
            }
        }
    }

    func testFamilyCFreezesThursdayAndFridayButNotMondayThroughWednesday() throws {
        let definition = generate(family: .c, dayCount: 5)

        for (day, slot) in [("Monday", "Pushing Move 1"), ("Tuesday", "Deadlift Move"), ("Wednesday", "Pushing Move 2")] {
            guard case .autoregulated(let config) = try XCTUnwrap(row(day, slot, in: definition).rules?.setCountRule) else {
                return XCTFail("expected .autoregulated")
            }
            XCTAssertNil(config.freezeAfterWeek, "\(day)'s \(slot) keeps incrementing through Week 4")
        }

        for (day, slot) in [("Thursday", "Deadlift Move"), ("Thursday", "Hamstring Move"), ("Friday", "Legs Move 2")] {
            guard case .autoregulated(let config) = try XCTUnwrap(row(day, slot, in: definition).rules?.setCountRule) else {
                return XCTFail("expected .autoregulated")
            }
            XCTAssertEqual(config.freezeAfterWeek, 2, "\(day)'s \(slot) freezes after Week 3 (0-based index 2)")
            XCTAssertTrue(config.applyRatingOnFinalWeek, "Family C uses the freeze shape, not Family B's asymmetry")
        }
    }

    func testFamilyCFridayHasPrimaryRowsAndTheBackoffStructurallyPairedToMonday() throws {
        let definition = generate(family: .c, dayCount: 5)
        let mondayPush1 = try row("Monday", "Pushing Move 1", in: definition)

        let friday = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == "Friday" })
        let fridayBlock = try XCTUnwrap(friday.orderedBlockTemplates.first)
        XCTAssertEqual(fridayBlock.orderedPrescriptionTemplates.count, 4, "Legs2, backoff, UpperPull2, Shoulder2 — the complete real Friday row set")

        let backoff = try XCTUnwrap(fridayBlock.orderedPrescriptionTemplates.first { if case .linkedToPairedSlot = $0.rules?.loadRule { return true } else { return false } })
        XCTAssertEqual(backoff.pairedSlot?.id, mondayPush1.id, "the backoff's LOAD is structurally paired to Monday's Push1 slot (decision A5's shape) — confirmed directly from the live workbook's own formula, not the source's own contradicting footnote (see POWERLIFTING_SOURCE_AUTHORITY_REPAIR_V1.md §10)")
        XCTAssertEqual(backoff.rules?.loadRule, .linkedToPairedSlot(fractionOfSourceResult: 0.85 / 0.95))
        XCTAssertEqual(backoff.rules?.deloadRepFraction, 1.0, "the backoff's deload reps are the sole exception: unchanged from Week 1")

        let legs2 = try row("Friday", "Legs Move 2", in: definition)
        XCTAssertEqual(legs2.rules?.deloadRepFraction, 0.5, "every other Family C row deloads reps to half of Week 1")
    }

    func testFamilyCDeloadWeightIsUnchangedMondayTuesdayHalvedWednesdayOnward() throws {
        let definition = generate(family: .c, dayCount: 5)
        for (day, slot) in [("Monday", "Pushing Move 1"), ("Tuesday", "Deadlift Move")] {
            let template = try row(day, slot, in: definition)
            XCTAssertEqual(template.rules?.deloadWeightPositionOverride?.fullPositionFactor, 1.0, "\(day) is unchanged during deload")
        }
        for (day, slot) in [("Wednesday", "Pushing Move 2"), ("Thursday", "Deadlift Move"), ("Friday", "Legs Move 2")] {
            let template = try row(day, slot, in: definition)
            XCTAssertEqual(template.rules?.deloadWeightPositionOverride?.boundaryDayIndex, 2)
            XCTAssertEqual(template.rules?.deloadWeightPositionOverride?.halfPositionFactor, 0.5)
        }
    }

    /// The complete real 16-row structure (`SOURCE_PROGRAM_MANIFEST.md`
    /// §9): Monday 3, Tuesday 3, Wednesday 3, Thursday 3, Friday 4 = 16 —
    /// in particular, Hamstring is no longer entirely missing (the prior
    /// version's confirmed gap).
    func testFamilyCHasTheCompleteSixteenRealRowsAcrossFiveDays() throws {
        let definition = generate(family: .c, dayCount: 5)
        func count(_ day: String) throws -> Int {
            try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == day }?.orderedBlockTemplates.first).orderedPrescriptionTemplates.count
        }
        XCTAssertEqual(try count("Monday"), 3)
        XCTAssertEqual(try count("Tuesday"), 3)
        XCTAssertEqual(try count("Wednesday"), 3)
        XCTAssertEqual(try count("Thursday"), 3)
        XCTAssertEqual(try count("Friday"), 4)
        let total = try count("Monday") + count("Tuesday") + count("Wednesday") + count("Thursday") + count("Friday")
        XCTAssertEqual(total, 16, "the complete real Family C row count, not the prior version's 6-row placeholder")
        let allSlotNames = Set(definition.orderedTemplateSessions.flatMap { $0.orderedBlockTemplates.first?.orderedPrescriptionTemplates.compactMap(\.exerciseSlot?.name) ?? [] })
        XCTAssertTrue(allSlotNames.contains("Hamstring Move"), "Hamstring must no longer be missing — the prior version's confirmed content gap")
    }

    // MARK: - Round trip

    func testFamilyBGraphSurvivesRoundTrip() throws {
        let definition = generate(family: .b, dayCount: 4)
        let definitionID = definition.id
        try context.save()

        let reloaded = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<ProgramDefinition>(predicate: #Predicate { $0.id == definitionID })).first
        )
        XCTAssertEqual(reloaded.powerliftingConfiguration, PowerliftingProgramConfiguration(family: .b, dayCount: 4))
        XCTAssertEqual(reloaded.orderedTemplateSessions.count, 4)
    }

    func testFamilyCGraphSurvivesRoundTripIncludingPairedSlot() throws {
        let definition = generate(family: .c, dayCount: 5)
        let definitionID = definition.id
        try context.save()

        let reloaded = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<ProgramDefinition>(predicate: #Predicate { $0.id == definitionID })).first
        )
        let monday = try XCTUnwrap(reloaded.orderedTemplateSessions.first { $0.name == "Monday" })
        let mondayBlock = try XCTUnwrap(monday.orderedBlockTemplates.first)
        let mondayPush1 = try XCTUnwrap(mondayBlock.orderedPrescriptionTemplates.first { $0.exerciseSlot?.name == "Pushing Move 1" })
        let friday = try XCTUnwrap(reloaded.orderedTemplateSessions.first { $0.name == "Friday" })
        let fridayBlock = try XCTUnwrap(friday.orderedBlockTemplates.first)
        let backoff = try XCTUnwrap(fridayBlock.orderedPrescriptionTemplates.first { if case .linkedToPairedSlot = $0.rules?.loadRule { return true } else { return false } })
        XCTAssertEqual(backoff.pairedSlot?.id, mondayPush1.id)
    }
}
