import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 8B: the readiness check-in / adaptation / progression-neutrality
/// test suite. Every scenario letter below matches the corresponding
/// scenario in the Stage 8B implementation report. Uses the real
/// production materialization path (`SeedScenarios.materializedLowerASession`)
/// wherever a realistic multi-exercise fixture is needed, exactly like
/// `MultiExerciseExecutionTests`/`EndToEndProgressionLoopTests` already do
/// — never a hand-faked result.
@MainActor
final class ReadinessAdaptationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var performanceProfile: PerformanceProfile!
    let ownerUserID = UUID()

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
        performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        let user = User(displayName: "Test User")
        context.insert(user)
        user.attachPerformanceProfile(performanceProfile)
    }

    private func freshContext() -> ModelContext { ModelContext(container) }

    @discardableResult
    private func makeLowerA() -> (session: Session, programInstance: ProgramInstance, multiAlternativeSlot: ExerciseSlot, catalog: ExerciseCatalog) {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let day = Day(ownerUserID: ownerUserID, date: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(day)
        let fixture = SeedScenarios.materializedLowerASession(day: day, catalog: catalog, ownerUserID: ownerUserID, modelContext: context)
        return (fixture.session, fixture.programInstance, fixture.multiAlternativeSlot, catalog)
    }

    private func logSet(
        for movement: ExercisePrescription, setPrescription: SetPrescription, reps: Int, actualRir: Int?, weight: Double? = nil
    ) throws {
        try LogSetUseCase.logSet(
            setIndex: movement.loggedSetResults.count, weight: weight ?? setPrescription.targetWeight ?? 20,
            reps: reps, targetRir: setPrescription.targetRir, actualRir: actualRir,
            prBand: nil, scoringDirection: .higherIsBetter, context: .rx, setPrescription: setPrescription,
            exercisePrescription: movement, exercise: movement.exercise!, performanceProfile: performanceProfile,
            completedAt: Date(), modelContext: context
        )
    }

    private func goodCheckIn() -> ReadinessCheckIn {
        ReadinessCheckIn(recordedAt: Date(), sleep: .good, energy: .good, overallRecovery: .good)
    }

    // MARK: A — skipped vs. all-good

    func testA_SkippedCheckInIsNilDistinguishableFromAllGood() throws {
        // `ExerciseCatalog.resolveOrInsert` is a one-per-context catalog
        // (`Exercise.canonicalName` is unique) — the "skipped" session
        // needs no exercises at all, so it's built minimally rather than
        // calling `makeLowerA()` a second time in the same context.
        let skippedSession = Session(name: "Skipped", modality: .strength)
        context.insert(skippedSession)
        let (goodSession, _, _, _) = makeLowerA()

        try RecordReadinessCheckInUseCase.record(goodCheckIn(), for: goodSession, modelContext: context)

        XCTAssertNil(skippedSession.readinessCheckIn, "a skipped check-in must be nil, never a defaulted-to-good row")
        let recorded = try XCTUnwrap(goodSession.readinessCheckIn)
        XCTAssertTrue(recorded.hasNoAdverseSignal)
    }

    // MARK: B/C — all-good produces no mutation, no upward change

    func testBC_AllGoodReadinessProducesEmptyProposalAndNeverIncreasesDemand() throws {
        let (session, _, _, _) = makeLowerA()
        let originalSetCounts = session.orderedBlocks.flatMap(\.orderedPrescriptions).map { $0.orderedSetPrescriptions.count }

        let proposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: goodCheckIn(),  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)

        XCTAssertTrue(proposal.isEmpty, "an all-good check-in must produce Level 0 — no recommendation screen at all")
        let newSetCounts = session.orderedBlocks.flatMap(\.orderedPrescriptions).map { $0.orderedSetPrescriptions.count }
        XCTAssertEqual(originalSetCounts, newSetCounts, "evaluation must never itself mutate anything")
    }

    // MARK: D — pain and stiffness are independent typed signals

    func testD_PainAndStiffnessAreIndependentTypedSignals() throws {
        let checkIn = ReadinessCheckIn(
            recordedAt: Date(), sleep: .ok, energy: .ok, overallRecovery: .ok,
            reportedPain: [.shoulders], reportedStiffness: [.shoulders]
        )
        context.insert(checkIn)
        try context.save()

        let fetchContext = freshContext()
        let reloaded = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<ReadinessCheckIn>()).first)

        XCTAssertEqual(reloaded.reportedPain, [.shoulders])
        XCTAssertEqual(reloaded.reportedStiffness, [.shoulders])
        XCTAssertFalse(reloaded.reportedPain.isEmpty && reloaded.reportedStiffness.isEmpty)
        // Reporting one must never silently populate or infer the other.
        let painOnly = ReadinessCheckIn(recordedAt: Date(), reportedPain: [.chest])
        XCTAssertTrue(painOnly.reportedStiffness.isEmpty, "pain reported alone must never imply stiffness")
    }

    // MARK: E — local pain only affects the compatible exercise

    func testE_LocalPainOnlyAffectsCompatibleExerciseNotUnrelatedWork() throws {
        let (session, _, _, catalog) = makeLowerA()
        // Squat Pattern targets [.quadriceps, .glutes]; Hip Hinge targets
        // [.hamstrings, .glutes] but resolves to Romanian Deadlift by
        // default — pain reported ONLY in an area unique to the squat
        // pattern (quadriceps) must never touch the hip hinge exercise.
        let checkIn = ReadinessCheckIn(recordedAt: Date(), reportedPain: [.quadriceps])
        let proposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn,  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)

        let squat = try XCTUnwrap(session.orderedBlocks.flatMap(\.orderedPrescriptions).first { $0.exercise?.canonicalName == catalog.backSquat.canonicalName })
        let hipHinge = try XCTUnwrap(session.orderedBlocks.flatMap(\.orderedPrescriptions).first { $0.exercise?.canonicalName == catalog.romanianDeadlift.canonicalName })

        XCTAssertTrue(proposal.items.contains { $0.exercisePrescription?.id == squat.id }, "the affected exercise must get a proposal")
        XCTAssertFalse(proposal.items.contains { $0.exercisePrescription?.id == hipHinge.id }, "an unrelated exercise must never be touched by a local signal")
    }

    // MARK: F — substitution reuses existing validation; original survives

    func testF_SubstitutionUsesExistingValidatorAndPreservesOriginalExercise() throws {
        let painfulExercise = Exercise(canonicalName: "Test Overhead Press", modality: .strength, equipment: "barbell", movementPattern: "verticalPush", primaryTargets: [.shoulders])
        let compatibleAlternative = Exercise(canonicalName: "Test Leg Press", modality: .strength, equipment: "machine", movementPattern: "squat", primaryTargets: [.quadriceps])
        context.insert(painfulExercise)
        context.insert(compatibleAlternative)

        let slot = ExerciseSlot(name: "Test Slot", allowedExercises: [painfulExercise, compatibleAlternative], resolvedExercise: painfulExercise)
        context.insert(slot)

        let session = Session(name: "Test Session", modality: .strength)
        context.insert(session)
        let block = WorkoutBlock(type: .strength)
        context.insert(block)
        session.addBlock(block)
        let prescription = ExercisePrescription(exercise: painfulExercise)
        prescription.sourceExerciseSlot = slot
        context.insert(prescription)
        block.addPrescription(prescription)

        let checkIn = ReadinessCheckIn(recordedAt: Date(), reportedPain: [.shoulders])
        context.insert(checkIn)

        let proposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn,  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)
        let item = try XCTUnwrap(proposal.items.first)
        XCTAssertEqual(item.actionKind, .exerciseSubstituted)
        XCTAssertEqual(item.proposedExercise?.canonicalName, "Test Leg Press", "must never propose a candidate that also hits the painful area")

        let decision = try ReadinessAdaptationDecisionUseCase.accept(item, session: session, checkIn: checkIn, decidedAt: Date(),  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)

        XCTAssertEqual(prescription.exercise?.canonicalName, "Test Leg Press")
        XCTAssertTrue(prescription.substitutionUsed)
        XCTAssertEqual(prescription.substitutionReason, .readinessAdaptation)
        XCTAssertEqual(decision.originalExercise?.canonicalName, "Test Overhead Press", "the original must remain reconstructable from the decision record")
        // Template graph untouched (Scenario Q).
        XCTAssertEqual(slot.resolvedExercise?.canonicalName, "Test Overhead Press", "a this-session-only substitution must never rewrite the template's own default")
    }

    // MARK: F2 — no valid non-painful alternative in a MULTI-exercise block falls back to volume reduction, never removing sibling exercises' work

    func testF2_PainWithNoValidNonPainfulAlternativeInAMultiExerciseBlockReducesOnlyThatExercise() throws {
        let (session, _, multiAlternativeSlot, catalog) = makeLowerA()
        // Both candidate exercises on this real slot share the same
        // primary targets — reporting pain in one of those shared targets
        // must never propose swapping into an equally-painful alternative.
        XCTAssertEqual(Set(catalog.backSquat.primaryTargets), Set(catalog.frontSquat.primaryTargets))
        _ = multiAlternativeSlot

        let checkIn = ReadinessCheckIn(recordedAt: Date(), reportedPain: [.quadriceps])
        let proposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn,  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)

        let squatPrescription = try XCTUnwrap(session.orderedBlocks.flatMap(\.orderedPrescriptions).first { $0.exercise?.canonicalName == catalog.backSquat.canonicalName })
        let item = try XCTUnwrap(proposal.items.first { $0.exercisePrescription?.id == squatPrescription.id })
        XCTAssertEqual(item.actionKind, .setCountReduced, "this block has sibling exercises — removing it would silently drop their work too")
        XCTAssertEqual(item.triggeringSignals, [.pain])
        XCTAssertFalse(proposal.items.contains { $0.actionKind == .blockRemoved }, "no whole-block removal proposed while a less disruptive per-exercise option exists")
    }

    // MARK: F3 — no valid alternative on a SINGLE-exercise block does escalate to block removal (Level 4)

    func testF3_PainWithNoValidAlternativeOnASingleExerciseBlockRemovesTheBlock() throws {
        let painfulExercise = Exercise(canonicalName: "Test Solo Press", modality: .strength, equipment: "barbell", movementPattern: "verticalPush", primaryTargets: [.shoulders])
        context.insert(painfulExercise)
        let slot = ExerciseSlot(name: "Solo Slot", allowedExercises: [painfulExercise], resolvedExercise: painfulExercise)
        context.insert(slot)
        let session = Session(name: "Test Session", modality: .strength)
        context.insert(session)
        let block = WorkoutBlock(type: .strength)
        context.insert(block)
        session.addBlock(block)
        let prescription = ExercisePrescription(exercise: painfulExercise)
        prescription.sourceExerciseSlot = slot
        context.insert(prescription)
        block.addPrescription(prescription)

        let checkIn = ReadinessCheckIn(recordedAt: Date(), reportedPain: [.shoulders])
        let proposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn,  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)

        let item = try XCTUnwrap(proposal.items.first)
        XCTAssertEqual(item.actionKind, .blockRemoved, "a single-exercise block has no sibling to protect — removal is the correct, most conservative option")
        XCTAssertEqual(item.workoutBlock?.id, block.id)
    }

    // MARK: G/H — reject leaves original intact; accept produces a session-local overlay only

    func testGH_RejectLeavesOriginalIntactAcceptProducesSessionLocalSetCountOverlay() throws {
        let (session, _, _, catalog) = makeLowerA()
        let squat = try XCTUnwrap(session.orderedBlocks.flatMap(\.orderedPrescriptions).first { $0.exercise?.canonicalName == catalog.backSquat.canonicalName })
        let originalCount = squat.orderedSetPrescriptions.count
        let checkIn = ReadinessCheckIn(recordedAt: Date(), energy: .poor)

        let proposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn,  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)
        let item = try XCTUnwrap(proposal.items.first { $0.exercisePrescription?.id == squat.id && $0.actionKind == .setCountReduced })

        // G: reject.
        let rejection = try ReadinessAdaptationDecisionUseCase.reject(item, checkIn: checkIn, decidedAt: Date(), modelContext: context)
        XCTAssertEqual(rejection.userResponse, .rejectedKeptOriginal)
        XCTAssertEqual(squat.executableSetPrescriptions.count, originalCount, "rejecting must leave the executable prescription completely unchanged")
        XCTAssertTrue(squat.orderedSetPrescriptions.allSatisfy { !$0.isAdaptedAway })

        // H: a fresh evaluation + accept.
        let secondProposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn,  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)
        let secondItem = try XCTUnwrap(secondProposal.items.first { $0.exercisePrescription?.id == squat.id })
        let acceptance = try ReadinessAdaptationDecisionUseCase.accept(secondItem, session: session, checkIn: checkIn, decidedAt: Date(),  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)

        XCTAssertEqual(acceptance.userResponse, .accepted)
        XCTAssertEqual(squat.executableSetPrescriptions.count, originalCount - 1, "accepting must reduce today's executable count by exactly 1")
        XCTAssertEqual(squat.orderedSetPrescriptions.count, originalCount, "the ORIGINAL prescription is never shrunk — the full historical set list survives (Scenario P)")
        XCTAssertEqual(squat.orderedSetPrescriptions.filter(\.isAdaptedAway).count, 1)
    }

    // MARK: I/J — relaunch durability

    func testIJ_RelaunchAfterAcceptedAdaptationPreservesAllState() throws {
        let (session, _, _, catalog) = makeLowerA()
        let sessionID = session.id
        let squat = try XCTUnwrap(session.orderedBlocks.flatMap(\.orderedPrescriptions).first { $0.exercise?.canonicalName == catalog.backSquat.canonicalName })
        let prescriptionID = squat.id
        let checkIn = ReadinessCheckIn(recordedAt: Date(), energy: .poor)
        try RecordReadinessCheckInUseCase.record(checkIn, for: session, modelContext: context)

        let proposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn,  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)
        let item = try XCTUnwrap(proposal.items.first { $0.exercisePrescription?.id == squat.id })
        try ReadinessAdaptationDecisionUseCase.accept(item, session: session, checkIn: checkIn, decidedAt: Date(),  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)

        let fetchContext = freshContext()
        let reloadedSession = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionID })).first)
        let reloadedPrescription = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<ExercisePrescription>(predicate: #Predicate { $0.id == prescriptionID })).first)

        XCTAssertNotNil(reloadedSession.readinessCheckIn, "the check-in survives a relaunch")
        XCTAssertEqual(reloadedPrescription.orderedSetPrescriptions.filter(\.isAdaptedAway).count, 1, "the adapted-away flag survives a relaunch")
        XCTAssertFalse(reloadedPrescription.readinessAdaptationDecisions.isEmpty, "the decision record survives a relaunch")
    }

    // MARK: K/M/N/O/P — the progression-neutrality contract

    /// **Stage 10R.1D:** uses "Leg Press" (a genuine fixed-rep-range
    /// prescription), not "Back Squat" — Back Squat's `toFailure` is now
    /// correctly RIR-based, and `DoubleProgressionEngine` has no fixed
    /// rep range to evaluate for an RIR-only prescription, so it never
    /// produces a preview item at all (proven separately by
    /// `EndToEndProgressionLoopTests.testE_...`). This test's own purpose
    /// — proving the readiness-adapted-hold progression-neutrality
    /// contract THROUGH a real preview — needs a movement the engine can
    /// actually evaluate.
    func testK_CompletingAnAdaptedSessionPreservesOriginalAdaptedAndPerformedAsThreeTruths() throws {
        let (session, _, _, _) = makeLowerA()
        let squat = try XCTUnwrap(session.orderedBlocks.flatMap(\.orderedPrescriptions).first { $0.exercise?.canonicalName == "Leg Press" })
        let originalCount = squat.orderedSetPrescriptions.count
        let checkIn = ReadinessCheckIn(recordedAt: Date(), energy: .poor)
        try RecordReadinessCheckInUseCase.record(checkIn, for: session, modelContext: context)

        let proposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn,  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)
        let item = try XCTUnwrap(proposal.items.first { $0.exercisePrescription?.id == squat.id })
        try ReadinessAdaptationDecisionUseCase.accept(item, session: session, checkIn: checkIn, decidedAt: Date(),  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)

        for setPrescription in squat.executableSetPrescriptions {
            try logSet(for: squat, setPrescription: setPrescription, reps: setPrescription.repRangeHigh ?? 0, actualRir: setPrescription.targetRir)
        }

        let summary = try CompleteSessionUseCase.complete(session, context: .partial, asOf: Date(), modelContext: context)

        XCTAssertEqual(squat.orderedSetPrescriptions.count, originalCount, "original prescription intact")
        XCTAssertEqual(squat.executableSetPrescriptions.count, originalCount - 1, "adapted target")
        XCTAssertEqual(squat.loggedSetResults.count, originalCount - 1, "performed matches what was actually asked today")

        let preview = try XCTUnwrap(summary.progressionPreview.first { $0.exerciseName == "Leg Press" })
        XCTAssertEqual(preview.reasonCode, .readinessAdaptedHold, "an adapted-and-successfully-completed session is neutral, never a load increase")
    }

    /// Scenario M (exact worked example): 100kg -> adapted 95kg -> performed
    /// 95kg successfully. Constructed directly since Stage 8B's evaluator
    /// never automatically produces a load-reduction magnitude (§13 gate)
    /// — this proves the progression-neutral SAFETY MECHANISM itself is
    /// correct for whichever field a decision touches, not that the
    /// evaluator invents this magnitude.
    func testM_LoadAdaptedAndSuccessfullyCompletedIsNeutralNeverAFalseFloorOrCeiling() throws {
        let exercise = Exercise(canonicalName: "Test Squat", modality: .strength, equipment: "barbell", movementPattern: "squat")
        context.insert(exercise)
        let session = Session(name: "Test", modality: .strength)
        context.insert(session)
        let block = WorkoutBlock(type: .strength)
        context.insert(block)
        session.addBlock(block)
        let prescription = ExercisePrescription(exercise: exercise)
        context.insert(prescription)
        block.addPrescription(prescription)
        let setPrescription = SetPrescription(repRangeLow: 4, repRangeHigh: 6, targetWeight: 100, targetRir: 0)
        context.insert(setPrescription)
        prescription.addSetPrescription(setPrescription)

        let checkIn = ReadinessCheckIn(recordedAt: Date(), energy: .poor)
        context.insert(checkIn)
        let decision = ReadinessAdaptationDecision(
            decidedAt: Date(), triggeringSignals: [.lowEnergy], actionKind: .loadReduced,
            userResponse: .accepted, explanation: "test", originalWeight: 100, proposedWeight: 95,
            exercisePrescription: prescription, readinessCheckIn: checkIn
        )
        context.insert(decision)

        try logSet(for: prescription, setPrescription: setPrescription, reps: 6, actualRir: 0, weight: 95)

        let summary = try CompleteSessionUseCase.complete(session, context: .partial, asOf: Date(), modelContext: context)
        let preview = try XCTUnwrap(summary.progressionPreview.first)

        XCTAssertEqual(preview.reasonCode, .readinessAdaptedHold)
        XCTAssertEqual(preview.recommendedWeight, 100, "holds at the ORIGINAL pre-adaptation weight — never silently proposes progressing beyond 95, and never implies 100 was itself completed")
    }

    /// Scenario N: adapted to 95kg but materially missed even that target.
    func testN_AdaptedButMaterialUnderperformanceStillReadsAsAGenuineMiss() throws {
        let exercise = Exercise(canonicalName: "Test Squat 2", modality: .strength, equipment: "barbell", movementPattern: "squat")
        context.insert(exercise)
        let session = Session(name: "Test", modality: .strength)
        context.insert(session)
        let block = WorkoutBlock(type: .strength)
        context.insert(block)
        session.addBlock(block)
        let prescription = ExercisePrescription(exercise: exercise)
        context.insert(prescription)
        block.addPrescription(prescription)
        let setPrescription = SetPrescription(repRangeLow: 4, repRangeHigh: 6, targetWeight: 100, targetRir: 0)
        context.insert(setPrescription)
        prescription.addSetPrescription(setPrescription)

        let checkIn = ReadinessCheckIn(recordedAt: Date(), energy: .poor)
        context.insert(checkIn)
        let decision = ReadinessAdaptationDecision(
            decidedAt: Date(), triggeringSignals: [.lowEnergy], actionKind: .loadReduced,
            userResponse: .accepted, explanation: "test", originalWeight: 100, proposedWeight: 95,
            exercisePrescription: prescription, readinessCheckIn: checkIn
        )
        context.insert(decision)

        // Missed even the (already reduced) rep-range bottom at 95kg.
        try logSet(for: prescription, setPrescription: setPrescription, reps: 2, actualRir: 0, weight: 95)

        let summary = try CompleteSessionUseCase.complete(session, context: .partial, asOf: Date(), modelContext: context)
        let preview = try XCTUnwrap(summary.progressionPreview.first)

        XCTAssertNotEqual(preview.reasonCode, .readinessAdaptedHold, "a genuine miss must stay visible, never masked by the neutrality override")
        XCTAssertEqual(preview.reasonCode, .hold, "existing methodology's own conservative reaction — unmodified")
    }

    /// Scenario O: no adaptation at all — existing behavior is byte-for-byte unchanged.
    func testO_NonAdaptedSessionKeepsExistingProgressionBehaviorUnchanged() throws {
        let (session, profile) = try makeSingleExerciseNonAdaptedFixture()
        let block = try XCTUnwrap(session.orderedBlocks.first)
        let prescription = try XCTUnwrap(block.orderedPrescriptions.first)
        for setPrescription in prescription.orderedSetPrescriptions {
            try LogSetUseCase.logSet(
                setIndex: prescription.loggedSetResults.count, weight: setPrescription.targetWeight ?? 100,
                reps: setPrescription.repRangeHigh ?? 0, targetRir: setPrescription.targetRir, actualRir: setPrescription.targetRir,
                prBand: nil, scoringDirection: .higherIsBetter, context: .rx, setPrescription: setPrescription,
                exercisePrescription: prescription, exercise: prescription.exercise!, performanceProfile: profile,
                completedAt: Date(), modelContext: context
            )
        }
        let summary = try CompleteSessionUseCase.complete(session, context: .partial, asOf: Date(), modelContext: context)
        let preview = try XCTUnwrap(summary.progressionPreview.first)
        XCTAssertEqual(preview.reasonCode, .loadIncrease, "unaffected by any Stage 8B code when nothing was adapted")
    }

    private func makeSingleExerciseNonAdaptedFixture() throws -> (Session, PerformanceProfile) {
        let exercise = Exercise(canonicalName: "Test Bench", modality: .strength, equipment: "barbell", movementPattern: "horizontalPush")
        context.insert(exercise)
        let session = Session(name: "Test", modality: .strength)
        context.insert(session)
        let block = WorkoutBlock(type: .strength)
        context.insert(block)
        session.addBlock(block)
        let prescription = ExercisePrescription(exercise: exercise)
        context.insert(prescription)
        block.addPrescription(prescription)
        let setPrescription = SetPrescription(repRangeLow: 4, repRangeHigh: 6, targetWeight: 60, targetRir: 0)
        context.insert(setPrescription)
        prescription.addSetPrescription(setPrescription)
        return (session, performanceProfile)
    }

    /// Scenario P: the adapted-away 4th set is never confused with a
    /// failed/missed set, and future progression reads the true original
    /// count — proven directly against the real `AutoregulationRatingResolver`.
    func testP_AdaptedAwaySetNeverMisreadAsOriginalPrescribedCountByFutureProgression() throws {
        let (session, programInstance, _, catalog) = makeLowerA()
        let squat = try XCTUnwrap(session.orderedBlocks.flatMap(\.orderedPrescriptions).first { $0.exercise?.canonicalName == catalog.backSquat.canonicalName })
        let template = try XCTUnwrap(squat.sourcePrescriptionTemplate)
        let originalCount = squat.orderedSetPrescriptions.count
        session.status = .completed
        session.completedAt = Date()

        let checkIn = ReadinessCheckIn(recordedAt: Date(), energy: .poor)
        let proposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn,  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)
        let item = try XCTUnwrap(proposal.items.first { $0.exercisePrescription?.id == squat.id })
        try ReadinessAdaptationDecisionUseCase.accept(item, session: session, checkIn: checkIn, decidedAt: Date(),  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)

        XCTAssertEqual(squat.orderedSetPrescriptions.filter(\.isAdaptedAway).count, 1)
        let resolvedCount = AutoregulationRatingResolver.previousWeekSetCount(for: template, in: programInstance)
        XCTAssertEqual(resolvedCount, originalCount, "future progression must read the TRUE original prescribed count, never the readiness-reduced executable count")
    }

    // MARK: Q — substitution never mutates the template graph (also covered inline in F)

    func testQ_SubstitutionNeverMutatesProgramDefinitionTemplateGraph() throws {
        let (session, _, multiAlternativeSlot, catalog) = makeLowerA()
        let originalResolvedExercise = multiAlternativeSlot.resolvedExercise?.canonicalName
        let squat = try XCTUnwrap(session.orderedBlocks.flatMap(\.orderedPrescriptions).first { $0.exercise?.canonicalName == catalog.backSquat.canonicalName })
        guard let slot = squat.sourceExerciseSlot else { return }

        try SubstituteExerciseUseCase.substituteThisSessionOnly(prescription: squat, slot: slot, with: catalog.frontSquat, reason: .readinessAdaptation, environment: TrainingEnvironmentTestSupport.full(context: context))

        XCTAssertEqual(multiAlternativeSlot.resolvedExercise?.canonicalName, originalResolvedExercise, "the template's own default is never rewritten by a this-session-only change")
    }

    // MARK: R — Level 4 block removal is session-local

    func testR_BlockRemovalIsSessionLocal() throws {
        let painfulExercise = Exercise(canonicalName: "Test Solo Deadlift", modality: .strength, equipment: "barbell", movementPattern: "hinge", primaryTargets: [.hamstrings])
        context.insert(painfulExercise)
        let slot = ExerciseSlot(name: "Solo Hinge Slot", allowedExercises: [painfulExercise], resolvedExercise: painfulExercise)
        context.insert(slot)
        let session = Session(name: "Test Session", modality: .strength)
        context.insert(session)
        let block = WorkoutBlock(type: .strength)
        context.insert(block)
        session.addBlock(block)
        let prescription = ExercisePrescription(exercise: painfulExercise)
        prescription.sourceExerciseSlot = slot
        context.insert(prescription)
        block.addPrescription(prescription)

        let checkIn = ReadinessCheckIn(recordedAt: Date(), reportedPain: [.hamstrings])
        let proposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn,  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)
        let item = try XCTUnwrap(proposal.items.first { $0.actionKind == .blockRemoved })
        try ReadinessAdaptationDecisionUseCase.accept(item, session: session, checkIn: checkIn, decidedAt: Date(),  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)

        XCTAssertEqual(block.status, .skipped)
        XCTAssertEqual(session.status, .scheduled, "removing one block is never itself a session-level status change")
    }

    // MARK: S — Level 6 postpone is a recommendation, never a silent plan rewrite

    func testS_PostponeRecommendationOnlyChangesThisSessionsStatus() throws {
        let (session, programInstance, _, _) = makeLowerA()
        let phaseBefore = programInstance.phase
        let checkIn = ReadinessCheckIn(recordedAt: Date(), sleep: .poor, energy: .poor, overallRecovery: .poor)

        let proposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn,  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)
        let item = try XCTUnwrap(proposal.items.first { $0.actionKind == .postponeRecommended })
        XCTAssertEqual(item.triggeringSignals.count, 3)

        try ReadinessAdaptationDecisionUseCase.accept(item, session: session, checkIn: checkIn, decidedAt: Date(),  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)

        XCTAssertEqual(session.status, .skipped)
        XCTAssertTrue(programInstance.phase === phaseBefore, "accepting a postpone recommendation must never itself touch the strategic phase/plan")
    }

    func testS2_ExactlyOnePoorSignalProposesLevel2NotLevel6() throws {
        let (session, _, _, catalog) = makeLowerA()
        let checkIn = ReadinessCheckIn(recordedAt: Date(), energy: .poor)
        let proposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn,  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)

        XCTAssertFalse(proposal.items.contains { $0.actionKind == .postponeRecommended }, "a single poor signal must not escalate to a postpone recommendation")
        XCTAssertTrue(proposal.items.contains { $0.actionKind == .setCountReduced && $0.exercisePrescription?.exercise?.canonicalName == catalog.backSquat.canonicalName })
    }

    // MARK: T — repeated check-ins are independently queryable, never trigger LongTermPlanner

    func testT_RepeatedCheckInsAreQueryableWithoutTriggeringLongTermPlanner() throws {
        // No exercises needed here — a minimal Session per check-in avoids
        // re-inserting `ExerciseCatalog` (unique `canonicalName`) into the
        // same context more than once.
        for i in 0..<3 {
            let session = Session(name: "Test Session \(i)", modality: .strength)
            context.insert(session)
            let checkIn = ReadinessCheckIn(recordedAt: Date(), sleep: .poor)
            try RecordReadinessCheckInUseCase.record(checkIn, for: session, modelContext: context)
        }

        let allCheckIns = try context.fetch(FetchDescriptor<ReadinessCheckIn>())
        XCTAssertEqual(allCheckIns.count, 3)
        XCTAssertEqual(allCheckIns.filter { $0.sleep == .poor }.count, 3, "a longitudinal query over a typed field, independent of any planner")

        let plannerDecisions = try context.fetch(FetchDescriptor<PlannerDecision>())
        XCTAssertTrue(plannerDecisions.isEmpty, "repeated poor readiness must never itself produce a PlannerDecision in Stage 8B")
    }

    // MARK: U — the shared substitution mechanism stays reason-agnostic

    func testU_SharedSubstitutionMechanismRemainsUsableForNonReadinessReasons() throws {
        let (session, _, _, catalog) = makeLowerA()
        let squat = try XCTUnwrap(session.orderedBlocks.flatMap(\.orderedPrescriptions).first { $0.exercise?.canonicalName == catalog.backSquat.canonicalName })
        let slot = try XCTUnwrap(squat.sourceExerciseSlot)

        try SubstituteExerciseUseCase.substituteThisSessionOnly(prescription: squat, slot: slot, with: catalog.frontSquat, reason: .userPreference, environment: TrainingEnvironmentTestSupport.full(context: context))

        XCTAssertEqual(squat.substitutionReason, .userPreference, "the mechanism itself is never hardwired to readiness — a future environment-provenance caller can use it exactly the same way")
    }

    // MARK: Functional Fitness — narrower, audit-scoped support

    func testFunctionalFitness_SubstitutionFollowsSameMechanismStiffnessProducesNoProposal() throws {
        let painfulMovementExercise = Exercise(canonicalName: "Test Pull-up", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "pull", primaryTargets: [.back, .biceps])
        let alternativeExercise = Exercise(canonicalName: "Test Ring Row", modality: .functionalFitness, equipment: "rings", movementPattern: "pull", primaryTargets: [.back])
        context.insert(painfulMovementExercise)
        context.insert(alternativeExercise)
        let slot = ExerciseSlot(name: "Pull Slot", allowedExercises: [painfulMovementExercise, alternativeExercise], resolvedExercise: painfulMovementExercise)
        context.insert(slot)

        let session = Session(name: "Test Metcon", modality: .functionalFitness)
        context.insert(session)
        let block = WorkoutBlock(type: .functionalFitness)
        context.insert(block)
        session.addBlock(block)
        let ffPrescription = FunctionalFitnessPrescription(stimulus: Stimulus(
            targetDurationDomain: .short, intensity: .high, loading: .light, movementFunctions: [.gymnasticsPull],
            movementModalityMix: [ModalityCount(modality: .gymnastics, count: 1)], skillDemand: .moderate, systemicDemand: .moderate, scoreType: .roundsAndReps
        ), format: .amrap(capSeconds: 600))
        context.insert(ffPrescription)
        block.attachFunctionalFitnessPrescription(ffPrescription)
        let movement = FunctionalFitnessMovement(exercise: painfulMovementExercise, reps: 10)
        movement.sourceExerciseSlot = slot
        context.insert(movement)
        ffPrescription.addMovement(movement)

        // Pain -> substitution, same mechanism.
        let painCheckIn = ReadinessCheckIn(recordedAt: Date(), reportedPain: [.biceps])
        let painProposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: painCheckIn,  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)
        let item = try XCTUnwrap(painProposal.items.first)
        XCTAssertEqual(item.actionKind, .exerciseSubstituted)
        try ReadinessAdaptationDecisionUseCase.accept(item, session: session, checkIn: painCheckIn, decidedAt: Date(),  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)
        XCTAssertEqual(movement.exercise?.canonicalName, "Test Ring Row")
        XCTAssertEqual(movement.substitutionReason, .readinessAdaptation)

        // Stiffness -> no Level 2 mechanism exists for Functional Fitness in
        // Stage 8B (audit finding) — must produce no proposal, never an
        // invented one.
        let stiffnessCheckIn = ReadinessCheckIn(recordedAt: Date(), reportedStiffness: [.back])
        let stiffnessProposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: stiffnessCheckIn,  environment: TrainingEnvironmentTestSupport.full(context: context), modelContext: context)
        XCTAssertTrue(stiffnessProposal.isEmpty, "Functional Fitness has no implemented Level 2 mechanism in Stage 8B — must not silently invent one")
    }

    // MARK: TE.1 closure — an anatomically valid substitute is rejected when the environment can't support it, proven end-to-end through the real readiness path

    /// Mirrors `testF_SubstitutionUsesExistingValidatorAndPreservesOriginalExercise`
    /// exactly, except the one candidate that would otherwise be proposed
    /// (`compatibleAlternative`) requires equipment (`.machine`) absent from
    /// a deliberately restrictive environment. Proves the environment reaches
    /// `EvaluateReadinessAdaptationUseCase` end-to-end — not merely that
    /// `TrainingEnvironmentCompatibilityRule`/`SubstitutionValidator` reject it
    /// in isolation, but that the real readiness proposal falls back to
    /// `.blockRemoved` rather than proposing an unusable substitute.
    func testTE1_PainWithAnAnatomicallyValidButEnvironmentIncompatibleAlternativeFallsBackToBlockRemoval() throws {
        let painfulExercise = Exercise(canonicalName: "Test Overhead Press", modality: .strength, equipment: "barbell", movementPattern: "verticalPush", primaryTargets: [.shoulders])
        let compatibleAlternative = Exercise(canonicalName: "Test Leg Press", modality: .strength, equipment: "machine", movementPattern: "squat", primaryTargets: [.quadriceps], requiredEquipment: [.machine])
        context.insert(painfulExercise)
        context.insert(compatibleAlternative)

        let slot = ExerciseSlot(name: "Test Slot", allowedExercises: [painfulExercise, compatibleAlternative], resolvedExercise: painfulExercise)
        context.insert(slot)

        let session = Session(name: "Test Session", modality: .strength)
        context.insert(session)
        let block = WorkoutBlock(type: .strength)
        context.insert(block)
        session.addBlock(block)
        let prescription = ExercisePrescription(exercise: painfulExercise)
        prescription.sourceExerciseSlot = slot
        context.insert(prescription)
        block.addPrescription(prescription)

        let checkIn = ReadinessCheckIn(recordedAt: Date(), reportedPain: [.shoulders])
        context.insert(checkIn)

        let noMachineEnvironment = TrainingEnvironment(name: "No Machines", availableEquipment: [.barbell, .rack, .bench, .dumbbells])
        context.insert(noMachineEnvironment)

        let restrictedProposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn, environment: noMachineEnvironment, modelContext: context)
        let restrictedItem = try XCTUnwrap(restrictedProposal.items.first)
        XCTAssertEqual(restrictedItem.actionKind, .blockRemoved, "the only anatomically valid alternative requires equipment this environment doesn't have -> must fall back to removal, never propose an unusable substitute")
        XCTAssertNil(restrictedItem.proposedExercise)

        // Control: the exact same painful exercise/slot/check-in, but a
        // compatible environment — proves the fixture itself is capable of
        // proposing the substitution, so `.blockRemoved` above is caused by
        // the environment, not by some other property of this fixture.
        let fullyEquippedEnvironment = TrainingEnvironment(name: "Full Gym Control", availableEquipment: EquipmentRequirement.allCases)
        context.insert(fullyEquippedEnvironment)
        let compatibleProposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn, environment: fullyEquippedEnvironment, modelContext: context)
        let compatibleItem = try XCTUnwrap(compatibleProposal.items.first)
        XCTAssertEqual(compatibleItem.actionKind, .exerciseSubstituted)
        XCTAssertEqual(compatibleItem.proposedExercise?.canonicalName, "Test Leg Press")
    }
}
