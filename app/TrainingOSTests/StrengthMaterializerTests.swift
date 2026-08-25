import XCTest
import SwiftData
@testable import TrainingOS

/// Proves `StrengthMaterializer` turns a generated template graph into
/// real, dated `Day -> Session -> WorkoutBlock -> ExercisePrescription ->
/// SetPrescription` rows with the exact values `StrengthProgressionEngine`/
/// `SourceCompatibleDeloadStrategy` would independently compute, and that
/// the materialized graph survives a real save/refetch cycle.
@MainActor
final class StrengthMaterializerTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()
    let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func freshContext() -> ModelContext {
        ModelContext(container)
    }

    private func makeInstance(definition: ProgramDefinition) -> ProgramInstance {
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        return instance
    }

    /// `(5, .fullBody)`, not `(3, .fullBody)` — Stage 10B repurposes the
    /// latter for its own day-focus-driven path (variable slot count per
    /// day), which would break this test's "one primary + one paired
    /// accessory" assumption; `(5, .fullBody)` exercises the identical,
    /// unchanged legacy generator this test was always about.
    func testMaterializeWeekZeroCreatesOneSessionPerTemplateSessionWithCorrectValues() throws {
        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 5, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"),
            context: context
        )
        let instance = makeInstance(definition: definition)
        let startDate = Date(timeIntervalSince1970: 0)

        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: startDate, ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )

        XCTAssertEqual(result.sessions.count, 5)
        XCTAssertEqual(instance.sessions.count, 5)

        let session = try XCTUnwrap(result.sessions.first)
        XCTAssertEqual(session.day?.ownerUserID, ownerUserID)
        let block = try XCTUnwrap(session.orderedBlocks.first)
        XCTAssertEqual(block.orderedPrescriptions.count, 2, "one primary + one paired accessory, per the generator")

        let primary = try XCTUnwrap(block.orderedPrescriptions.first { $0.orderedSetPrescriptions.count == 3 })
        XCTAssertEqual(primary.orderedSetPrescriptions.count, 3, "autoregulated baseline for Basic Hypertrophy")
        for setPrescription in primary.orderedSetPrescriptions {
            XCTAssertEqual(setPrescription.targetWeight ?? -1, 85, accuracy: 0.0001) // MROUND(100*0.85, 2.5)
            // Stage 10R.1D: "3/fail" is RIR 3, never a fabricated fixed
            // rep count — see `testMaterializeWeekTranslatesRIRTargetsNeverInventingAFixedRepCount` below.
            XCTAssertNil(setPrescription.repRangeLow)
            XCTAssertNil(setPrescription.repRangeHigh)
        }
    }

    /// **Stage 10R.1D correction:** `RepGoal.prescription` (already
    /// resolved by `StrengthProgressionEngine.resolveRepGoal`) is
    /// translated onto the materialized `SetPrescription.targetRir` — RIR
    /// 3 for the primary (Family A's own `repGoalSchedule` is `.rir(3)`
    /// for week 1), absent for the paired accessory (`pairedRepGoalSchedule`
    /// is a genuine fixed-rep target, `.fixedReps(12)`) — never hardcoded,
    /// never invented for the case the source data doesn't define. This
    /// test previously asserted the pre-correction fabrication (RIR 0 for
    /// a "to failure" flag) — renamed to reflect the corrected reading.
    func testMaterializeWeekTranslatesRIRTargetsNeverInventingAFixedRepCount() throws {
        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 1, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"),
            context: context
        )
        let instance = makeInstance(definition: definition)

        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )

        let block = try XCTUnwrap(result.sessions.first?.orderedBlocks.first)
        let primary = try XCTUnwrap(block.orderedPrescriptions.first { $0.orderedSetPrescriptions.count == 3 })
        let paired = try XCTUnwrap(block.orderedPrescriptions.first { $0.orderedSetPrescriptions.count == 2 })

        XCTAssertTrue(primary.orderedSetPrescriptions.allSatisfy { $0.targetRir == 3 })
        XCTAssertTrue(primary.orderedSetPrescriptions.allSatisfy { $0.repRangeLow == nil && $0.repRangeHigh == nil })
        XCTAssertTrue(paired.orderedSetPrescriptions.allSatisfy { $0.targetRir == nil })
        XCTAssertTrue(paired.orderedSetPrescriptions.allSatisfy { $0.repRangeLow == 12 && $0.repRangeHigh == 12 }, "the paired accessory is a genuine fixed-rep target")
    }

    /// Stage 6D Part 7: the reason code the engine actually produced for
    /// this prescription's weight/set-count/rep-goal decision is captured
    /// onto the movement itself, at materialization time — never
    /// re-derived later, never discarded.
    func testMaterializeWeekPersistsTheReasonCodesTheEngineActuallyProduced() throws {
        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 1, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"),
            context: context
        )
        let instance = makeInstance(definition: definition)

        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )

        let block = try XCTUnwrap(result.sessions.first?.orderedBlocks.first)
        for prescription in block.orderedPrescriptions {
            let template = try XCTUnwrap(prescription.sourcePrescriptionTemplate)
            let rules = try XCTUnwrap(template.rules)

            // Independently recompute what the engine SHOULD have produced
            // for this exact template/week — not a hardcoded literal.
            let pairedResolvedWeight = template.pairedSlot.flatMap { paired in
                block.orderedPrescriptions.first { $0.sourcePrescriptionTemplate?.id == paired.id }?.orderedSetPrescriptions.first?.targetWeight
            }
            let expectedWeight = StrengthProgressionEngine.resolveWeight(
                rules: rules, weekIndex: 0, rmKilograms: 100, weekOneResolvedWeightKg: nil,
                pairedSlotResolvedWeightKg: pairedResolvedWeight, equipmentProfile: equipment
            )
            let expectedRepGoal = StrengthProgressionEngine.resolveRepGoal(rules: rules, weekIndex: 0)
            let expectedSetCount = StrengthProgressionEngine.resolveSetCount(
                rules: rules, weekIndex: 0, previousWeekSetCount: nil, autoregulationRating: nil
            )

            XCTAssertEqual(prescription.appliedLoadReasonCode, expectedWeight.reasonCode)
            XCTAssertEqual(prescription.appliedRepGoalReasonCode, expectedRepGoal.reasonCode)
            XCTAssertEqual(prescription.appliedSetCountReasonCode, expectedSetCount.reasonCode)
        }
    }

    /// The paired accessory's `.linkedToPairedSlot` load must be a
    /// fraction of the primary's weight *resolved in this same
    /// materialization pass*, not some other value.
    func testMaterializeWeekZeroPairedSlotUsesPrimarysResolvedWeightThisPass() throws {
        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 1, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"),
            context: context
        )
        let instance = makeInstance(definition: definition)

        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )

        let session = try XCTUnwrap(result.sessions.first)
        let block = try XCTUnwrap(session.orderedBlocks.first)
        let paired = try XCTUnwrap(block.orderedPrescriptions.first { $0.orderedSetPrescriptions.count == 2 })
        // Primary resolves to 85 (MROUND(100*0.85,2.5)); paired = MROUND(85*0.6,2.5) = 50.
        for setPrescription in paired.orderedSetPrescriptions {
            XCTAssertEqual(setPrescription.targetWeight ?? -1, 50, accuracy: 0.0001)
        }
        XCTAssertEqual(result.resolvedWeightsBySlotID.count, 2, "both primary and paired slots should record a resolved weight")
    }

    func testMaterializeWeekZeroWithoutRMLeavesWeightNilRatherThanGuessing() throws {
        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 1, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"),
            context: context
        )
        let instance = makeInstance(definition: definition)

        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: nil) }, context: context
        )

        let session = try XCTUnwrap(result.sessions.first)
        let block = try XCTUnwrap(session.orderedBlocks.first)
        let primary = try XCTUnwrap(block.orderedPrescriptions.first { $0.orderedSetPrescriptions.count == 3 })
        XCTAssertTrue(primary.orderedSetPrescriptions.allSatisfy { $0.targetWeight == nil }, "no usable RM should never fabricate a weight")
    }

    /// The deload week, given week 0's resolved values: day-boundary
    /// weight asymmetry, the hardcoded 2-set constant, and the paired
    /// slot omitted entirely. **Stage 10R.1D:** deload rep resolution no
    /// longer fabricates a floored rep count from the template — see
    /// `STAGE10R1D_SOURCE_SEMANTICS_CORRECTION.md`.
    func testMaterializeDeloadWeekAppliesFamilyARulesGivenWeekZeroResolvedValues() throws {
        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 4, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"),
            context: context
        )
        let instance = makeInstance(definition: definition)

        let weekZero = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )
        let resolvedWeights = weekZero.resolvedWeightsBySlotID

        let deloadStartDate = Date(timeIntervalSince1970: 7 * 24 * 3600 * 4) // arbitrary later date
        let deload = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 4, isDeload: true,
            startDate: deloadStartDate, ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { slot in .init(weekOneResolvedWeightKg: resolvedWeights[slot.id]) }, context: context
        )

        XCTAssertEqual(deload.sessions.count, 4)
        for (dayIndex, session) in deload.sessions.enumerated() {
            let block = try XCTUnwrap(session.orderedBlocks.first)
            let primary = try XCTUnwrap(block.orderedPrescriptions.first { !$0.orderedSetPrescriptions.isEmpty })
            XCTAssertEqual(primary.orderedSetPrescriptions.count, 2, "deload sets are always the hardcoded constant")
            let expectedWeight = dayIndex < 2 ? 85.0 : 42.5 // ceil(4/2) = 2 full-weight days
            for setPrescription in primary.orderedSetPrescriptions {
                XCTAssertEqual(setPrescription.targetWeight ?? -1, expectedWeight, accuracy: 0.0001, "day \(dayIndex)")
                XCTAssertNil(setPrescription.repRangeLow, "never fabricate a deload rep count from the template")
                XCTAssertNil(setPrescription.targetRir, "unresolved, not fabricated")
            }

            let paired = block.orderedPrescriptions.first { $0.orderedSetPrescriptions.isEmpty }
            XCTAssertNotNil(paired, "the confirmed superset-partner slot should be omitted (zero SetPrescriptions) during deload")
        }
    }

    func testMaterializedGraphSurvivesRoundTrip() throws {
        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 2, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"),
            context: context
        )
        let instance = makeInstance(definition: definition)
        let instanceID = instance.id

        StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )
        try context.save()

        let reloadedInstance = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<ProgramInstance>(predicate: #Predicate { $0.id == instanceID })).first
        )
        XCTAssertEqual(reloadedInstance.sessions.count, 2)
        XCTAssertEqual(reloadedInstance.programDefinition?.id, definition.id)
        let session = try XCTUnwrap(reloadedInstance.sessions.first { $0.day != nil })
        XCTAssertNotNil(session.day)
        let block = try XCTUnwrap(session.orderedBlocks.first)
        XCTAssertFalse(block.orderedPrescriptions.isEmpty)
    }
}
