import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 10B manual-acceptance follow-up: the reported gap was that
/// finishing readiness + warm-up (via either "Start Workout" or "Skip
/// Warm-up" in `WarmupView`) left the user back on Today's plain list —
/// never inside the actual workout — because nothing navigated into
/// `SessionDetailView`, and even once there, a single-block Session's
/// one-row block list was an extra, pointless tap before reaching
/// `StrengthExecutionView`. `SessionAutoAdvance.blockToAutoOpen` is the
/// pure decision `SessionDetailView`'s own `.onAppear` now calls (see
/// `SessionDetailView.autoNavigateIfNeeded`/`TodayView`'s
/// `justStartedSession`) — this suite proves that decision directly,
/// against the real production materialization/readiness/warm-up
/// pipeline, never a hand-faked Session.
@MainActor
final class SessionAutoAdvanceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()
    let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    // MARK: - Fixtures (real production path, never hand-faked)

    private func makeStage10BSession() throws -> (session: Session, catalog: ExerciseCatalog) {
        let catalog = ExerciseCatalog.makeAndInsert(context: context)
        let candidates = [
            catalog.backSquat, catalog.benchPress, catalog.inclineDumbbellPress, catalog.romanianDeadlift,
            catalog.legPress, catalog.frontSquat, catalog.legCurl, catalog.calfRaise,
            catalog.barbellCurl, catalog.cableTricepsPushdown, catalog.dumbbellLateralRaise, catalog.barbellRow,
        ]
        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 3, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: context
        )
        ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: candidates)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition

        let materialized = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { slot in Self.stage10B6SlotContext(slot: slot, weekIndex: 0, isDeload: false) }, context: context
        )
        // "Pull Emphasis" specifically — the real recovered source's
        // Biceps/Barbell Curl slot only exists there (Stage 10R.1 Slice
        // 1A; unlike the retired invented rotation, biceps no longer
        // appears on every day).
        let session = try XCTUnwrap(materialized.sessions.first { $0.name == "Pull Emphasis" })
        return (session, catalog)
    }

    /// Stage 10B.6: a real `.doubleProgression` template needs its own 3
    /// resolved fields, not the legacy `rmKilograms` stub — mirrors what
    /// `RollTacticalWindowUseCase.strengthSlotContext` does in production,
    /// just with a fixed calibration weight (100) rather than real
    /// history, since these tests exercise readiness/warm-up/execution,
    /// not progression itself.
    private static func stage10B6SlotContext(slot: ExerciseSlot, weekIndex: Int, isDeload: Bool) -> StrengthMaterializer.SlotContext {
        guard let template = slot.prescriptionTemplate, let rules = template.rules, rules.loadRule == .doubleProgression else {
            return .init(rmKilograms: 100)
        }
        let role = template.slotRole ?? .accessory
        let repGoal = HypertrophyV2ProgressionEngine.resolveRepGoal(rules: rules, weekIndex: weekIndex, isDeload: isDeload)
        let setCount = HypertrophyV2ProgressionEngine.resolveSetCount(
            role: role, rules: rules, isDeload: isDeload, previousWeekSetCount: nil, autoregulationRating: nil
        )
        return .init(doubleProgressionWeightKg: 100, doubleProgressionRepGoal: repGoal, doubleProgressionSetCount: setCount)
    }

    private func goodCheckIn() -> ReadinessCheckIn {
        let checkIn = ReadinessCheckIn(recordedAt: Date(), sleep: .good, energy: .good, overallRecovery: .good)
        context.insert(checkIn)
        return checkIn
    }

    private func painfulCheckIn(_ groups: [MuscleGroup]) -> ReadinessCheckIn {
        let checkIn = ReadinessCheckIn(recordedAt: Date(), reportedPain: groups)
        context.insert(checkIn)
        return checkIn
    }

    // MARK: 1 — readiness good -> warm-up -> Start Workout -> execution opens exercise 1 of 8

    func testGoodReadinessThenWarmupThenStartWorkoutAutoOpensSoleBlockAtExerciseOne() throws {
        let (session, catalog) = try makeStage10BSession()
        WarmupCatalog.makeAndInsert(exerciseCatalog: catalog, context: context)
        let sessionIDBefore = session.id

        let checkIn = goodCheckIn()
        try RecordReadinessCheckInUseCase.record(checkIn, for: session, modelContext: context)
        let proposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn, modelContext: context)
        XCTAssertTrue(proposal.isEmpty, "an all-good check-in must never propose an adaptation")

        let sequence = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: checkIn), modelContext: context
        ))
        try RecordWarmupSequenceUseCase.record(sequence, for: session, modelContext: context)

        // The exact effect of tapping "Start Workout" in WarmupView, via
        // TodayViewModel.start.
        try StartSessionUseCase.start(session, asOf: Date(), modelContext: context)

        let block = try XCTUnwrap(SessionAutoAdvance.blockToAutoOpen(session: session), "must auto-open the sole block once the Session is in progress")
        XCTAssertEqual(session.id, sessionIDBefore, "Session identity must never change across readiness -> warm-up -> execution")
        XCTAssertEqual(block.orderedPrescriptions.count, 8, "Pull Emphasis' real recovered 8-category sequence")
        XCTAssertEqual(block.orderedPrescriptions.first?.exercise?.canonicalName, "Lat Pulldown", "exercise 1 of 8 — Vertical Pull is the first recovered category on this day")
    }

    // MARK: 2 — readiness good -> Skip Warm-up -> execution opens

    func testGoodReadinessThenSkipWarmupStillAutoOpensSoleBlock() throws {
        let (session, catalog) = try makeStage10BSession()
        WarmupCatalog.makeAndInsert(exerciseCatalog: catalog, context: context)

        let checkIn = goodCheckIn()
        try RecordReadinessCheckInUseCase.record(checkIn, for: session, modelContext: context)
        _ = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn, modelContext: context)

        let sequence = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: checkIn), modelContext: context
        ))
        try RecordWarmupSequenceUseCase.skipEntirely(sequence, modelContext: context)

        try StartSessionUseCase.start(session, asOf: Date(), modelContext: context)

        let block = try XCTUnwrap(SessionAutoAdvance.blockToAutoOpen(session: session))
        XCTAssertEqual(block.orderedPrescriptions.first?.exercise?.canonicalName, "Lat Pulldown", "Pull Emphasis' first recovered category, Vertical Pull")
        XCTAssertTrue(sequence.wasSkippedEntirely)
    }

    // MARK: 3 — partial warm-up completion -> Start Workout -> execution opens

    func testPartialWarmupCompletionThenStartWorkoutStillAutoOpens() throws {
        let (session, catalog) = try makeStage10BSession()
        WarmupCatalog.makeAndInsert(exerciseCatalog: catalog, context: context)

        let checkIn = goodCheckIn()
        try RecordReadinessCheckInUseCase.record(checkIn, for: session, modelContext: context)
        _ = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn, modelContext: context)

        let sequence = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: checkIn), modelContext: context
        ))
        try RecordWarmupSequenceUseCase.record(sequence, for: session, modelContext: context)
        if let firstItem = sequence.orderedItems.first {
            try RecordWarmupSequenceUseCase.markItemCompleted(firstItem, modelContext: context)
        }
        XCTAssertFalse(sequence.orderedItems.allSatisfy(\.wasCompleted), "sanity: genuinely partial, not all items done")

        try StartSessionUseCase.start(session, asOf: Date(), modelContext: context)

        XCTAssertNotNil(SessionAutoAdvance.blockToAutoOpen(session: session), "a partially-completed warm-up must never block reaching the workout")
    }

    // MARK: 4 — accepted readiness adaptation -> generated warm-up -> execution uses the adapted final workout

    func testAcceptedReadinessAdaptationFeedsIntoWarmupAndExecutionUsesTheAdaptedWorkout() throws {
        let (session, catalog) = try makeStage10BSession()
        WarmupCatalog.makeAndInsert(exerciseCatalog: catalog, context: context)
        let sessionIDBefore = session.id
        let blockIDBefore = try XCTUnwrap(session.orderedBlocks.first).id

        let checkIn = painfulCheckIn([.biceps])
        try RecordReadinessCheckInUseCase.record(checkIn, for: session, modelContext: context)
        let proposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn, modelContext: context)
        XCTAssertFalse(proposal.isEmpty, "reported pain in a muscle group this session trains (biceps) must propose an adaptation")
        // Barbell Row also targets .biceps (secondary), so it proposes its
        // own item too — target the Barbell Curl one specifically rather
        // than assuming it's first.
        let item = try XCTUnwrap(proposal.items.first { $0.exercisePrescription?.exercise?.canonicalName == "Barbell Curl" })
        try ReadinessAdaptationDecisionUseCase.accept(item, session: session, checkIn: checkIn, decidedAt: Date(), modelContext: context)

        // Warm-up must be generated from the session AS IT NOW STANDS —
        // the already-adapted, final executable workout — never a
        // separate "final workout" projection.
        let warmupSequence = GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: checkIn), modelContext: context
        )
        if let warmupSequence {
            try RecordWarmupSequenceUseCase.record(warmupSequence, for: session, modelContext: context)
        }

        try StartSessionUseCase.start(session, asOf: Date(), modelContext: context)

        let block = try XCTUnwrap(SessionAutoAdvance.blockToAutoOpen(session: session))
        XCTAssertEqual(session.id, sessionIDBefore, "accepting an adaptation must mutate in place, never replace the Session")
        XCTAssertEqual(block.id, blockIDBefore, "accepting an adaptation must mutate in place, never replace the WorkoutBlock")
        // Multi-exercise block, no valid non-painful biceps alternative in
        // this fixture's pool -> the correct adaptation is a set-count
        // reduction on that one exercise (never removing a sibling
        // exercise's work) — matching `ReadinessAdaptationTests`' own
        // F2 scenario exactly.
        let bicepCurl = try XCTUnwrap(block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Barbell Curl" }, "the multi-exercise block must keep its sibling exercises, including the adapted one itself")
        XCTAssertTrue(bicepCurl.orderedSetPrescriptions.contains { $0.isAdaptedAway }, "the accepted adaptation must actually reduce this exercise's executable sets")
    }

    // MARK: 5 — rejected readiness adaptation -> warm-up -> execution uses the original workout

    func testRejectedReadinessAdaptationExecutesTheOriginalWorkout() throws {
        let (session, catalog) = try makeStage10BSession()
        WarmupCatalog.makeAndInsert(exerciseCatalog: catalog, context: context)

        let checkIn = painfulCheckIn([.biceps])
        try RecordReadinessCheckInUseCase.record(checkIn, for: session, modelContext: context)
        let proposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn, modelContext: context)
        let item = try XCTUnwrap(proposal.items.first { $0.exercisePrescription?.exercise?.canonicalName == "Barbell Curl" })
        try ReadinessAdaptationDecisionUseCase.reject(item, checkIn: checkIn, decidedAt: Date(), modelContext: context)

        let warmupSequence = GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: checkIn), modelContext: context
        )
        if let warmupSequence {
            try RecordWarmupSequenceUseCase.record(warmupSequence, for: session, modelContext: context)
        }

        try StartSessionUseCase.start(session, asOf: Date(), modelContext: context)

        let block = try XCTUnwrap(SessionAutoAdvance.blockToAutoOpen(session: session))
        let bicepCurl = try XCTUnwrap(block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Barbell Curl" }, "rejecting must leave the original biceps exercise intact and executable")
        XCTAssertTrue(bicepCurl.orderedSetPrescriptions.allSatisfy { !$0.isAdaptedAway }, "rejecting must leave the executable prescription completely unchanged")
    }

    // MARK: 6 — WarmupSequence persistence never changes Session identity

    func testWarmupSequencePersistenceNeverChangesSessionIdentity() throws {
        let (session, catalog) = try makeStage10BSession()
        WarmupCatalog.makeAndInsert(exerciseCatalog: catalog, context: context)
        let idBefore = session.id

        let sequence = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: nil), modelContext: context
        ))
        try RecordWarmupSequenceUseCase.record(sequence, for: session, modelContext: context)

        XCTAssertEqual(session.id, idBefore)
        XCTAssertEqual(session.warmupSequence?.id, sequence.id)
    }

    // MARK: 7 — legacy (non-Stage-10B) Hypertrophy path still auto-opens correctly

    func testLegacyHypertrophySessionAlsoAutoOpensItsSoleBlock() throws {
        let catalog = ExerciseCatalog.makeAndInsert(context: context)
        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 5, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: context
        )
        ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: [catalog.benchPress, catalog.backSquat])
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let materialized = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )
        let session = try XCTUnwrap(materialized.sessions.first)

        try StartSessionUseCase.start(session, asOf: Date(), modelContext: context)
        XCTAssertNotNil(SessionAutoAdvance.blockToAutoOpen(session: session), "the legacy 2-exercise placeholder shape must auto-open exactly as the Stage 10B shape does")
    }

    // MARK: 8 — Powerlifting shares the same single-block-per-day shape and navigation pipeline

    func testPowerliftingSessionAlsoAutoOpensItsSoleBlock() throws {
        let catalog = ExerciseCatalog.makeAndInsert(context: context)
        let entry = try XCTUnwrap(PowerliftingBuiltInLibrary.all.first)
        let definition = PowerliftingProgramGenerator.generate(
            configuration: entry.configuration, provenance: .constructed(reason: "test fixture"), context: context
        )
        ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: [catalog.benchPress, catalog.backSquat, catalog.romanianDeadlift])
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let materialized = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )
        let session = try XCTUnwrap(materialized.sessions.first)

        try StartSessionUseCase.start(session, asOf: Date(), modelContext: context)
        XCTAssertNotNil(SessionAutoAdvance.blockToAutoOpen(session: session), "Powerlifting shares this same navigation pipeline and single-block-per-day shape")
    }

    // MARK: - Boundary proofs for the pure decision itself

    func testNeverAutoOpensAScheduledSessionEvenWithOneBlock() throws {
        let (session, _) = try makeStage10BSession()
        XCTAssertEqual(session.status, .scheduled)
        XCTAssertNil(SessionAutoAdvance.blockToAutoOpen(session: session), "a not-yet-started Session must still require its own explicit Start Workout tap")
    }

    func testNeverAutoOpensAnAlreadyCompletedBlock() throws {
        let (session, _) = try makeStage10BSession()
        try StartSessionUseCase.start(session, asOf: Date(), modelContext: context)
        let block = try XCTUnwrap(session.orderedBlocks.first)
        block.status = .completed
        XCTAssertNil(SessionAutoAdvance.blockToAutoOpen(session: session), "must never force the user back into a block they already finished")
    }
}
