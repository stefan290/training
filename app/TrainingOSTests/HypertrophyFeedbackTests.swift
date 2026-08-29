import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 6D Part 6/8 (Test E): the RP-style volume autoregulation loop
/// `StrengthProgressionEngine.resolveSetCount` already fully implements —
/// collect the rating, prove it reaches the engine, prove the next
/// set-count decision changes/holds per the existing rule. No new
/// progression mechanism; this wires the existing one end to end.
@MainActor
final class HypertrophyFeedbackTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()
    let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func makeUserWithPerformanceProfile() -> PerformanceProfile {
        let profile = PerformanceProfile()
        context.insert(profile)
        let user = User(displayName: "Test User")
        context.insert(user)
        user.attachPerformanceProfile(profile)
        return profile
    }

    private func makeLowerA() -> (session: Session, programInstance: ProgramInstance, definition: ProgramDefinition) {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let day = Day(ownerUserID: ownerUserID, date: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(day)
        let fixture = SeedScenarios.materializedLowerASession(day: day, catalog: catalog, ownerUserID: ownerUserID, modelContext: context)
        let definition = try! XCTUnwrap(fixture.programInstance.programDefinition)
        return (fixture.session, fixture.programInstance, definition)
    }

    private func logAllSets(for movement: ExercisePrescription, performanceProfile: PerformanceProfile) throws {
        for setPrescription in movement.orderedSetPrescriptions {
            try LogSetUseCase.logSet(
                setIndex: movement.loggedSetResults.count, weight: setPrescription.targetWeight ?? 20,
                reps: setPrescription.repRangeHigh ?? 0, targetRir: setPrescription.targetRir, actualRir: setPrescription.targetRir,
                prBand: nil, scoringDirection: .higherIsBetter, context: .rx, setPrescription: setPrescription,
                exercisePrescription: movement, exercise: movement.exercise!, performanceProfile: performanceProfile,
                completedAt: Date(), modelContext: context
            )
        }
    }

    // MARK: Which exercises need a prompt

    func testPendingPromptsOnlyIncludesExercisesSomeOtherSlotDependsOn() throws {
        let fixture = makeLowerA()
        let performanceProfile = makeUserWithPerformanceProfile()
        for movement in fixture.session.orderedBlocks.first!.orderedPrescriptions {
            try logAllSets(for: movement, performanceProfile: performanceProfile)
        }

        let pending = HypertrophyFeedbackPrompts.pending(for: fixture.session)
        XCTAssertEqual(pending.map { $0.exercise?.canonicalName }, ["Leg Press"], "only Leg Press is some other slot's (Squat Pattern's) paired-slot rating source")
    }

    func testPendingPromptsExcludesAnExerciseThatWasNeverPerformed() throws {
        let fixture = makeLowerA()
        // Deliberately log nothing.
        XCTAssertTrue(HypertrophyFeedbackPrompts.pending(for: fixture.session).isEmpty)
    }

    func testPendingPromptsExcludesAnAlreadyRatedExercise() throws {
        let fixture = makeLowerA()
        let performanceProfile = makeUserWithPerformanceProfile()
        let block = fixture.session.orderedBlocks.first!
        for movement in block.orderedPrescriptions {
            try logAllSets(for: movement, performanceProfile: performanceProfile)
        }
        let legPress = block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Leg Press" }!
        try RecordAutoregulationFeedbackUseCase.recordRating(1, for: legPress, modelContext: context)

        XCTAssertTrue(HypertrophyFeedbackPrompts.pending(for: fixture.session).isEmpty)
    }

    // MARK: Recording + resolving the rating

    func testRecordedRatingPersistsImmediately() throws {
        let fixture = makeLowerA()
        let legPress = fixture.session.orderedBlocks.first!.orderedPrescriptions.first { $0.exercise?.canonicalName == "Leg Press" }!
        try RecordAutoregulationFeedbackUseCase.recordRating(-1, for: legPress, modelContext: context)
        XCTAssertEqual(legPress.autoregulationRating, -1)
    }

    func testResolverFindsTheRatingFromThePairedSlotsMostRecentlyCompletedExercise() throws {
        let fixture = makeLowerA()
        let block = fixture.session.orderedBlocks.first!
        let squat = block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Back Squat" }!
        let legPress = block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Leg Press" }!
        try RecordAutoregulationFeedbackUseCase.recordRating(1, for: legPress, modelContext: context)

        let squatTemplate = try XCTUnwrap(squat.sourcePrescriptionTemplate)
        XCTAssertEqual(AutoregulationRatingResolver.rating(for: squatTemplate, in: fixture.programInstance), 1)
    }

    func testResolverReturnsNilWhenNothingHasBeenRatedYet() throws {
        let fixture = makeLowerA()
        let squat = fixture.session.orderedBlocks.first!.orderedPrescriptions.first { $0.exercise?.canonicalName == "Back Squat" }!
        let squatTemplate = try XCTUnwrap(squat.sourcePrescriptionTemplate)
        XCTAssertNil(AutoregulationRatingResolver.rating(for: squatTemplate, in: fixture.programInstance))
    }

    // MARK: Test E — the full loop: feedback reaches the engine and changes the next decision

    func testCollectedRatingChangesNextWeeksSetCountPerTheExistingEngineRule() throws {
        let fixture = makeLowerA()
        let performanceProfile = makeUserWithPerformanceProfile()
        let block = fixture.session.orderedBlocks.first!
        for movement in block.orderedPrescriptions {
            try logAllSets(for: movement, performanceProfile: performanceProfile)
        }
        try CompleteBlockUseCase.complete(block, context: .full, modelContext: context)
        try CompleteSessionUseCase.complete(fixture.session, context: .full, asOf: Date(), modelContext: context)

        let squatWeek0 = block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Back Squat" }!
        let legPress = block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Leg Press" }!
        XCTAssertEqual(squatWeek0.orderedSetPrescriptions.count, 3, "week 0's baseline")

        // The user reports Leg Press (the paired slot) felt easy — +1.
        try RecordAutoregulationFeedbackUseCase.recordRating(1, for: legPress, modelContext: context)

        let squatTemplate = try XCTUnwrap(squatWeek0.sourcePrescriptionTemplate)
        let weekOneStart = Calendar.current.date(byAdding: .day, value: 7, to: Date(timeIntervalSince1970: 1_700_000_000))!

        let result = StrengthMaterializer.materializeWeek(
            definition: fixture.definition, instance: fixture.programInstance, weekIndex: 1, isDeload: false,
            startDate: weekOneStart, ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { slot in
                guard let template = slot.prescriptionTemplate else { return .init() }
                return StrengthMaterializer.SlotContext(
                    rmKilograms: slot.name == "Squat Pattern" ? 140 : 180,
                    previousWeekSetCount: AutoregulationRatingResolver.previousWeekSetCount(for: template, in: fixture.programInstance),
                    autoregulationRating: AutoregulationRatingResolver.rating(for: template, in: fixture.programInstance)
                )
            },
            context: context
        )

        let week1Block = try XCTUnwrap(result.sessions.first?.orderedBlocks.first)
        let squatWeek1 = try XCTUnwrap(week1Block.orderedPrescriptions.first { $0.sourcePrescriptionTemplate?.id == squatTemplate.id })
        XCTAssertEqual(squatWeek1.orderedSetPrescriptions.count, 4, "3 (week 0 baseline) + 1 (the collected rating) per the existing autoregulation formula")
    }

    func testANegativeRatingHoldsOrReducesNextWeeksSetCountPerTheExistingRule() throws {
        let fixture = makeLowerA()
        let performanceProfile = makeUserWithPerformanceProfile()
        let block = fixture.session.orderedBlocks.first!
        for movement in block.orderedPrescriptions {
            try logAllSets(for: movement, performanceProfile: performanceProfile)
        }
        try CompleteSessionUseCase.complete(fixture.session, context: .full, asOf: Date(), modelContext: context)

        let squatWeek0 = block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Back Squat" }!
        let legPress = block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Leg Press" }!
        try RecordAutoregulationFeedbackUseCase.recordRating(-1, for: legPress, modelContext: context)

        let squatTemplate = try XCTUnwrap(squatWeek0.sourcePrescriptionTemplate)
        let weekOneStart = Calendar.current.date(byAdding: .day, value: 7, to: Date(timeIntervalSince1970: 1_700_000_000))!

        let result = StrengthMaterializer.materializeWeek(
            definition: fixture.definition, instance: fixture.programInstance, weekIndex: 1, isDeload: false,
            startDate: weekOneStart, ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { slot in
                guard let template = slot.prescriptionTemplate else { return .init() }
                return StrengthMaterializer.SlotContext(
                    rmKilograms: slot.name == "Squat Pattern" ? 140 : 180,
                    previousWeekSetCount: AutoregulationRatingResolver.previousWeekSetCount(for: template, in: fixture.programInstance),
                    autoregulationRating: AutoregulationRatingResolver.rating(for: template, in: fixture.programInstance)
                )
            },
            context: context
        )

        let week1Block = try XCTUnwrap(result.sessions.first?.orderedBlocks.first)
        let squatWeek1 = try XCTUnwrap(week1Block.orderedPrescriptions.first { $0.sourcePrescriptionTemplate?.id == squatTemplate.id })
        XCTAssertEqual(squatWeek1.orderedSetPrescriptions.count, 2, "3 (week 0 baseline) - 1 per the existing autoregulation formula")
    }

    // MARK: Copy varies by programming system, mechanic stays generic

    func testFeedbackCopyIsHypertrophyFramingWhenNoProgrammingSystemIsAuthored() {
        let options = HypertrophyFeedbackCopy.options(for: nil)
        XCTAssertTrue(options.contains { $0.label == "Wasn't very sore" })
    }

    func testFeedbackCopyIsBarSpeedFramingForPowerlifting() {
        let options = HypertrophyFeedbackCopy.options(for: .powerlifting)
        XCTAssertTrue(options.contains { $0.label.contains("fast") })
    }

    func testFeedbackCopyRatingValuesAreIdenticalRegardlessOfFraming() {
        let hypertrophyRatings = Set(HypertrophyFeedbackCopy.options(for: .hypertrophy).map(\.rating))
        let powerliftingRatings = Set(HypertrophyFeedbackCopy.options(for: .powerlifting).map(\.rating))
        XCTAssertEqual(hypertrophyRatings, powerliftingRatings, "only the copy differs — the underlying -1/0/+1 mechanic is generic")
    }
}
