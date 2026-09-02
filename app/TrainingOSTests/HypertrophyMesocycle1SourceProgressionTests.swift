import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 10R.1 Slice 1B: the source-derived test matrix
/// (`STAGE10R1_SLICE1B_SOURCE_PROGRESSION_DESIGN.md` Part 10) proving the
/// restored 3-Day Full Body / Mesocycle 1 "Basic Hypertrophy" progression
/// reproduces the real recovered workbook exactly — load, reps, set
/// autoregulation (including the real fixed source pairing web and the
/// blank-rating-is-no-change source behavior), deload, and routing
/// (`.rmBased`/`StrengthProgressionEngine`, never
/// `HypertrophyV2ProgressionEngine`/`DoubleProgressionEngine`). Every
/// fixture is CONSTRUCTED (the real workbook ships with blank RM cells),
/// labeled per this project's established discipline.
@MainActor
final class HypertrophyMesocycle1SourceProgressionTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()
    let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func generateDefinition() throws -> ProgramDefinition {
        try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 3, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: context
        )
    }

    private func horizontalPushTemplate(in definition: ProgramDefinition, day: String) throws -> PrescriptionTemplate {
        let session = try XCTUnwrap(definition.orderedTemplateSessions.first { $0.name == day })
        let templates = try XCTUnwrap(session.orderedBlockTemplates.first).orderedPrescriptionTemplates
        return try XCTUnwrap(templates.first { $0.exerciseSlot?.name == "Horizontal Push" })
    }

    // MARK: - LOAD (Part 10, items 1-6): CONSTRUCTED 10RM = 100 kg

    func testLoadWeek1IsRMTimesWeekOneFactorRounded() throws {
        let definition = try generateDefinition()
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition

        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )
        let template = try horizontalPushTemplate(in: definition, day: "Push Emphasis")
        let prescription = try XCTUnwrap(result.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).first {
            $0.sourcePrescriptionTemplate?.id == template.id
        })
        let expected = equipment.resolve(IdealLoad(kilograms: 100 * 0.85))
        XCTAssertEqual(prescription.orderedSetPrescriptions.first?.targetWeight ?? -1, expected, accuracy: 0.0001)
        XCTAssertEqual(prescription.appliedLoadReasonCode, .rmBasedLoad)
    }

    /// Weeks 2-4 all multiply the *resolved* Week-1 value by the shared
    /// Family A later-week multipliers, never chaining week to week — the
    /// fixed-anchor proof: Week 3/4 use `weekOneResolvedWeightKg`
    /// (threaded from week 0's own materialization), never Week 2's own
    /// resolved value.
    func testLoadWeeks2Through4UseTheFixedWeekOneAnchorNeverChained() throws {
        let definition = try generateDefinition()
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let template = try horizontalPushTemplate(in: definition, day: "Push Emphasis")

        let week0 = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )
        let weekOneResolvedWeightKg = try XCTUnwrap(
            week0.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions)
                .first { $0.sourcePrescriptionTemplate?.id == template.id }?.orderedSetPrescriptions.first?.targetWeight
        )

        func materialize(weekIndex: Int) -> ExercisePrescription {
            let result = StrengthMaterializer.materializeWeek(
                definition: definition, instance: instance, weekIndex: weekIndex, isDeload: false,
                startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
                slotContext: { _ in .init(weekOneResolvedWeightKg: weekOneResolvedWeightKg, previousWeekSetCount: 3, autoregulationRating: 0) },
                context: context
            )
            return result.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).first { $0.sourcePrescriptionTemplate?.id == template.id }!
        }

        let week1 = materialize(weekIndex: 1)
        let week2 = materialize(weekIndex: 2)
        let week3 = materialize(weekIndex: 3)

        XCTAssertEqual(week1.orderedSetPrescriptions.first?.targetWeight ?? -1, equipment.resolve(IdealLoad(kilograms: weekOneResolvedWeightKg * 1.05)), accuracy: 0.0001, "Week 2")
        XCTAssertEqual(week2.orderedSetPrescriptions.first?.targetWeight ?? -1, equipment.resolve(IdealLoad(kilograms: weekOneResolvedWeightKg * 1.075)), accuracy: 0.0001, "Week 3")
        XCTAssertEqual(week3.orderedSetPrescriptions.first?.targetWeight ?? -1, equipment.resolve(IdealLoad(kilograms: weekOneResolvedWeightKg * 1.1)), accuracy: 0.0001, "Week 4")
    }

    func testLoadRoundsThroughTheUsersOwnEquipmentIncrementNeverTheLiteralSourceFive() throws {
        // A non-2.5-multiple RM proves rounding genuinely happens through
        // `EquipmentProfile`, not a literal "round to nearest 5" copy of
        // the source's pound-flavored MROUND.
        let definition = try generateDefinition()
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let template = try horizontalPushTemplate(in: definition, day: "Push Emphasis")

        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 97) }, context: context
        )
        let prescription = try XCTUnwrap(result.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).first {
            $0.sourcePrescriptionTemplate?.id == template.id
        })
        let expected = equipment.resolve(IdealLoad(kilograms: 97 * 0.85))
        XCTAssertEqual(prescription.orderedSetPrescriptions.first?.targetWeight ?? -1, expected, accuracy: 0.0001)
        XCTAssertEqual(expected.truncatingRemainder(dividingBy: 2.5), 0, accuracy: 0.0001, "resolved through the 2.5 kg equipment increment, not the source's literal 5")
    }

    // MARK: - REPS (Part 10, items 7-8): the literal fixed RIR schedule

    /// **Stage 10R.1D correction:** the source's literal "N/fail" notation
    /// is an RIR/effort target, never a fixed rep count — "3/fail" means
    /// RIR 3, not "3 reps to failure." This test previously asserted the
    /// pre-correction fabrication (`repRangeLow/High == 3` and
    /// `targetRir == 0`) — see `STAGE10R1D_SOURCE_SEMANTICS_CORRECTION.md`.
    /// Now proves the corrected behavior: no fixed rep count is ever
    /// materialized for this program, and `targetRir` carries the literal
    /// 3,3,2,1 schedule.
    func testRepFailureScheduleIsRIRNeverAFabricatedFixedRepCount() throws {
        let definition = try generateDefinition()
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let template = try horizontalPushTemplate(in: definition, day: "Push Emphasis")

        for (weekIndex, expectedRir) in [3, 3, 2, 1].enumerated() {
            let result = StrengthMaterializer.materializeWeek(
                definition: definition, instance: instance, weekIndex: weekIndex, isDeload: false,
                startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
                slotContext: { _ in .init(rmKilograms: 100, weekOneResolvedWeightKg: 85, previousWeekSetCount: 3, autoregulationRating: 0) },
                context: context
            )
            let prescription = try XCTUnwrap(result.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).first {
                $0.sourcePrescriptionTemplate?.id == template.id
            })
            let setPrescription = try XCTUnwrap(prescription.orderedSetPrescriptions.first)
            XCTAssertNil(setPrescription.repRangeLow, "never a fabricated fixed rep count, week \(weekIndex + 1)")
            XCTAssertNil(setPrescription.repRangeHigh, "never a fabricated fixed rep count, week \(weekIndex + 1)")
            XCTAssertEqual(setPrescription.targetRir, expectedRir, "the corrected RIR reading of \"N/fail,\" week \(weekIndex + 1)")
        }
    }

    // MARK: - SETS (Part 10, items 9-15): rating arithmetic + blank + real pairing

    func testAutoregulatedSetsIncrementByOneOnAPositiveRating() {
        let rules = StrengthProgressionRules(
            loadRule: .none,
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 3, treatMissingRatingAsNoChange: true)),
            repGoalSchedule: [RepGoal.rir(3)]
        )
        let result = StrengthProgressionEngine.resolveSetCount(rules: rules, weekIndex: 1, previousWeekSetCount: 3, autoregulationRating: 1)
        XCTAssertEqual(result.sets, 4)
        XCTAssertEqual(result.reasonCode, .autoregulatedSetIncrease)
    }

    func testAutoregulatedSetsHoldOnAZeroRating() {
        let rules = StrengthProgressionRules(
            loadRule: .none,
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 3, treatMissingRatingAsNoChange: true)),
            repGoalSchedule: [RepGoal.rir(3)]
        )
        let result = StrengthProgressionEngine.resolveSetCount(rules: rules, weekIndex: 1, previousWeekSetCount: 3, autoregulationRating: 0)
        XCTAssertEqual(result.sets, 3)
        XCTAssertEqual(result.reasonCode, .autoregulatedSetHold)
    }

    func testAutoregulatedSetsDecrementByOneOnANegativeRating() {
        let rules = StrengthProgressionRules(
            loadRule: .none,
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 3, treatMissingRatingAsNoChange: true)),
            repGoalSchedule: [RepGoal.rir(3)]
        )
        let result = StrengthProgressionEngine.resolveSetCount(rules: rules, weekIndex: 1, previousWeekSetCount: 3, autoregulationRating: -1)
        XCTAssertEqual(result.sets, 2)
        XCTAssertEqual(result.reasonCode, .autoregulatedSetDecrease)
    }

    /// Decision A: for this source-recovered program, a blank
    /// (`nil`) rating is "no change" — the source workbook's own Excel
    /// arithmetic reads a blank cell as `0` — never `.calibrationRequired`.
    func testBlankRatingResolvesToNoChangeForTheSourceRecoveredProgram() {
        let rules = try! XCTUnwrap(makeSourceCategoryTemplateForTest(baselineSets: 3).rules)
        let result = StrengthProgressionEngine.resolveSetCount(rules: rules, weekIndex: 1, previousWeekSetCount: 3, autoregulationRating: nil)
        XCTAssertEqual(result.sets, 3, "no change")
        XCTAssertEqual(result.reasonCode, .autoregulatedSetHold)
    }

    /// Every OTHER caller (a plain `.autoregulated` rule without the
    /// opt-in) keeps the original `.calibrationRequired`-on-missing-rating
    /// behavior exactly — Decision A's scope is this program only.
    func testBlankRatingStillRequiresCalibrationForEveryOtherCaller() {
        let rules = StrengthProgressionRules(
            loadRule: .none,
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 3)),
            repGoalSchedule: [RepGoal.rir(3)]
        )
        let result = StrengthProgressionEngine.resolveSetCount(rules: rules, weekIndex: 1, previousWeekSetCount: 3, autoregulationRating: nil)
        XCTAssertNil(result.sets)
        XCTAssertEqual(result.reasonCode, .calibrationRequired)
    }

    private func makeSourceCategoryTemplateForTest(baselineSets: Int) -> PrescriptionTemplate {
        PrescriptionTemplate(rules: StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.85, laterWeekMultipliers: [1.05, 1.075, 1.1])),
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: baselineSets, treatMissingRatingAsNoChange: true)),
            repGoalSchedule: [RepGoal.rir(3)]
        ))
    }

    /// The real, fixed source pairing table, exercised through the ACTUAL
    /// production path (`RollTacticalWindowUseCase`) rather than asserted
    /// only at the template level (`HypertrophyDayFocusGenerationTests`
    /// already proves the template-level table matches Part 2 exactly) —
    /// this proves the pairing actually *drives* week-to-week set counts
    /// end to end. "Legs Emphasis"'s first Quads slot (row 22) rates
    /// itself from "Push Emphasis"'s Quads slot (row 18) — a real
    /// cross-day relationship from the recovered table.
    func testRealCrossDayPairingDrivesTheNextWeeksSetCountEndToEnd() throws {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let definition = try generateDefinition()
        try ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: [
            catalog.backSquat, catalog.frontSquat, catalog.legPress, catalog.benchPress, catalog.inclineDumbbellPress,
            catalog.romanianDeadlift, catalog.legCurl, catalog.barbellCurl, catalog.barbellRow,
        ], environment: TrainingEnvironmentTestSupport.full(context: context))
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let instance = ProgramInstance(ownerUserID: ownerUserID, startDate: startDate)
        context.insert(instance)
        instance.programDefinition = definition
        let mix = TrainingMix(kind: .selected, name: "Test Source Mesocycle Mix")
        context.insert(mix)
        let component = TrainingMixComponent(label: "Hypertrophy", programmingSystem: .hypertrophy, priority: .primary, frequency: SessionFrequency(target: 3))
        context.insert(component)
        mix.addComponent(component)
        component.programInstance = instance
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        let materializationContext = TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: [], trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context))

        let week0Sessions = try RollTacticalWindowUseCase.materializeFirstWindow(
            system: .hypertrophy, definition: definition, instance: instance, startDate: startDate, ownerUserID: ownerUserID,
            performanceProfile: performanceProfile, materializationContext: materializationContext, context: context
        )
        let allWeek0 = week0Sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions)
        let pushQuads = try XCTUnwrap(allWeek0.first { $0.workoutBlock?.session?.name == "Push Emphasis" && $0.sourceExerciseSlot?.name == "Quads" })
        let legsQuadsFirst = try XCTUnwrap(allWeek0.first { $0.workoutBlock?.session?.name == "Legs Emphasis" && $0.sourceExerciseSlot?.name == "Quads" })
        XCTAssertEqual(pushQuads.sourcePrescriptionTemplate?.id, legsQuadsFirst.sourcePrescriptionTemplate?.pairedSlot?.id, "sanity: matches the recovered table (row22<-row18)")

        // Rate Push Emphasis's Quads +1 (Legs Emphasis's first Quads slot
        // reads THIS rating next week, per the recovered table), log/complete
        // every session so the week can roll forward.
        for prescription in allWeek0 {
            for setPrescription in prescription.orderedSetPrescriptions {
                try LogSetUseCase.logSet(
                    setIndex: setPrescription.sortIndex, weight: setPrescription.targetWeight ?? 60, reps: 8,
                    targetRir: setPrescription.targetRir, actualRir: setPrescription.targetRir ?? 2, prBand: nil,
                    scoringDirection: .higherIsBetter, context: .rx, setPrescription: setPrescription, exercisePrescription: prescription,
                    exercise: try XCTUnwrap(prescription.exercise), performanceProfile: performanceProfile, completedAt: startDate, modelContext: context
                )
            }
        }
        try RecordAutoregulationFeedbackUseCase.recordRating(1, for: pushQuads, modelContext: context)
        var seenBlocks = Set<UUID>(); var seenSessions = Set<UUID>()
        for prescription in allWeek0 {
            if let block = prescription.workoutBlock, !seenBlocks.contains(block.id) {
                seenBlocks.insert(block.id)
                try CompleteBlockUseCase.complete(block, context: .full, modelContext: context)
            }
            if let session = prescription.workoutBlock?.session, !seenSessions.contains(session.id) {
                seenSessions.insert(session.id)
                try CompleteSessionUseCase.complete(session, context: .full, asOf: startDate, modelContext: context)
            }
        }

        let week1Date = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: startDate))
        let rollResult = try XCTUnwrap(RollTacticalWindowUseCase.rollForward(
            mix: mix, asOf: week1Date, ownerUserID: ownerUserID, performanceProfile: performanceProfile,
            availability: UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1),
            materializationContext: materializationContext, context: context
        ))
        let week1Prescriptions = rollResult.newSessionsByComponent.values.flatMap { $0 }.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions)
        let legsQuadsFirstWeek1 = try XCTUnwrap(week1Prescriptions.first { $0.sourcePrescriptionTemplate?.id == legsQuadsFirst.sourcePrescriptionTemplate?.id })
        XCTAssertEqual(legsQuadsFirstWeek1.orderedSetPrescriptions.count, legsQuadsFirst.orderedSetPrescriptions.count + 1, "Legs Emphasis's first Quads slot rates itself from Push Emphasis's Quads rating (+1), per the recovered cross-day pairing — not its own prior rating and not any other slot's")

        // The OTHER Quads slot on Legs Emphasis (row 23) also reads row
        // 18's rating (the same source) — proving a repeated category
        // does not dynamically re-target its own pairing.
        let legsQuadsSecond = try XCTUnwrap(allWeek0.first {
            $0.workoutBlock?.session?.name == "Legs Emphasis" && $0.sourceExerciseSlot?.name == "Quads" && $0.id != legsQuadsFirst.id
        })
        let legsQuadsSecondWeek1 = try XCTUnwrap(week1Prescriptions.first { $0.sourcePrescriptionTemplate?.id == legsQuadsSecond.sourcePrescriptionTemplate?.id })
        XCTAssertEqual(legsQuadsSecondWeek1.orderedSetPrescriptions.count, legsQuadsSecond.orderedSetPrescriptions.count + 1, "the second Quads slot reads the identical source row's rating too")
    }

    // MARK: - DELOAD (Part 10, items 16-20)

    func testDeloadFirstHalfDaysUseFullWeekOneWeight() throws {
        let definition = try generateDefinition()
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let template = try horizontalPushTemplate(in: definition, day: "Push Emphasis") // day position 0 of 3 -> boundary ceil(3/2)=2 -> full weight

        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 4, isDeload: true,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(weekOneResolvedWeightKg: 85) }, context: context
        )
        let prescription = try XCTUnwrap(result.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).first { $0.sourcePrescriptionTemplate?.id == template.id })
        XCTAssertEqual(prescription.orderedSetPrescriptions.first?.targetWeight ?? -1, 85, accuracy: 0.0001, "full Week-1 weight for day position 0 (< boundary 2)")
    }

    func testDeloadSecondHalfDaysUseHalfWeekOneWeight() throws {
        let definition = try generateDefinition()
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let template = try horizontalPushTemplate(in: definition, day: "Pull Emphasis") // day position 2 of 3 -> >= boundary 2 -> half weight

        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 4, isDeload: true,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(weekOneResolvedWeightKg: 85) }, context: context
        )
        let prescription = try XCTUnwrap(result.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).first { $0.sourcePrescriptionTemplate?.id == template.id })
        XCTAssertEqual(prescription.orderedSetPrescriptions.first?.targetWeight ?? -1, equipment.resolve(IdealLoad(kilograms: 42.5)), accuracy: 0.0001, "half Week-1 weight for day position 2 (>= boundary 2)")
    }

    func testDeloadSetCountIsAlwaysTwoRegardlessOfBaseline() throws {
        let definition = try generateDefinition()
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition

        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 4, isDeload: true,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(weekOneResolvedWeightKg: 85) }, context: context
        )
        for prescription in result.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions) {
            XCTAssertEqual(prescription.orderedSetPrescriptions.count, 2, "deload set count is a fixed constant, never autoregulated, regardless of the slot's own Week-1 baseline")
        }
    }

    /// **Stage 10R.1D correction:** this used to assert the pre-correction
    /// fabrication (halving the template's RIR value as if it were a rep
    /// count: `floor(3 * 0.5) = 1`). Deload rep resolution no longer
    /// fabricates a number from the template at all — the source's own
    /// "1/2 reps of Week 1" instruction is proven to reference the
    /// athlete's ACTUAL logged Week-1 performance, which TrainingOS does
    /// not yet thread into this resolver (`STAGE10R1D_SOURCE_SEMANTICS_CORRECTION.md`).
    func testDeloadRepsAreUnresolvedNeverFabricatedFromTheTemplate() throws {
        let definition = try generateDefinition()
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let template = try horizontalPushTemplate(in: definition, day: "Push Emphasis")

        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 4, isDeload: true,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(weekOneResolvedWeightKg: 85) }, context: context
        )
        let prescription = try XCTUnwrap(result.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).first { $0.sourcePrescriptionTemplate?.id == template.id })
        XCTAssertNil(prescription.orderedSetPrescriptions.first?.repRangeLow, "never fabricate a deload rep count from the template")
        XCTAssertNil(prescription.orderedSetPrescriptions.first?.targetRir, "unresolved, not fabricated")
        XCTAssertEqual(prescription.appliedRepGoalReasonCode, .deloadRepsRequireLoggedPerformanceData)
    }

    func testDeloadNeverConsumesOrProducesARating() throws {
        let definition = try generateDefinition()
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition

        // Deload materializes correctly with NO autoregulationRating input
        // at all (SlotContext.autoregulationRating stays nil) — the
        // source's own deload columns have no rating column (Part 4).
        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 4, isDeload: true,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(weekOneResolvedWeightKg: 85) }, context: context
        )
        for prescription in result.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions) {
            XCTAssertEqual(prescription.appliedSetCountReasonCode, .deloadWeightPrescribed)
        }
    }

    // MARK: - ROUTING (Part 10, items 21-23): .rmBased, never DoubleProgressionEngine/V2

    func testEveryRealMesocycle1SlotRoutesThroughRMBasedNeverDoubleProgression() throws {
        let definition = try generateDefinition()
        for template in definition.orderedTemplateSessions.flatMap({ $0.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates) }) {
            guard case .rmBased = try XCTUnwrap(template.rules?.loadRule) else {
                return XCTFail("must be .rmBased, never .doubleProgression")
            }
        }
    }

    func testMaterializedPrescriptionsCarryStrengthReasonCodesNeverProgressionReasonCodes() throws {
        let definition = try generateDefinition()
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition

        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )
        for prescription in result.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions) {
            XCTAssertNotNil(prescription.appliedLoadReasonCode, "StrengthReasonCode must be populated — proves the .rmBased/StrengthProgressionEngine path was actually taken")
            XCTAssertNil(prescription.appliedProgressionReasonCode, "DoubleProgressionEngine's reason-code vocabulary must never be populated for this source-recovered program")
        }
    }
}
