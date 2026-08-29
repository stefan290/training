import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 9B: the warm-up generation / persistence / readiness-adaptation-
/// ordering test suite. Uses the real production materialization path
/// (`SeedScenarios.materializedLowerASession`) for the lower-body/hinge
/// scenarios, exactly like `ReadinessAdaptationTests` already does — never
/// a hand-faked result.
@MainActor
final class WarmupGenerationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func freshContext() -> ModelContext { ModelContext(container) }

    @discardableResult
    private func seedCatalogs() -> (exercise: ExerciseCatalog, warmup: [WarmupMovement]) {
        let exerciseCatalog = ExerciseCatalog.resolveOrInsert(context: context)
        let warmupCatalog = WarmupCatalog.makeAndInsert(exerciseCatalog: exerciseCatalog, context: context)
        return (exerciseCatalog, warmupCatalog)
    }

    @discardableResult
    private func makeLowerA(exerciseCatalog: ExerciseCatalog) -> (session: Session, programInstance: ProgramInstance) {
        let day = Day(ownerUserID: ownerUserID, date: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(day)
        let fixture = SeedScenarios.materializedLowerASession(day: day, catalog: exerciseCatalog, ownerUserID: ownerUserID, modelContext: context)
        return (fixture.session, fixture.programInstance)
    }

    /// A simple, hand-built upper-body pressing Session (Bench Press +
    /// Incline Dumbbell Press) — mirrors the real seeded "Day 1
    /// Hypertrophy" Today card exactly.
    private func makeUpperBodyPressingSession(exerciseCatalog: ExerciseCatalog) -> Session {
        let session = Session(name: "Upper Body", modality: .hypertrophy)
        context.insert(session)
        let block = WorkoutBlock(type: .hypertrophy)
        context.insert(block)
        session.addBlock(block)
        for exercise in [exerciseCatalog.benchPress, exerciseCatalog.inclineDumbbellPress] {
            let prescription = ExercisePrescription(exercise: exercise)
            context.insert(prescription)
            block.addPrescription(prescription)
            let set = SetPrescription(repRangeLow: 8, repRangeHigh: 10, targetWeight: 60)
            context.insert(set)
            prescription.addSetPrescription(set)
        }
        return session
    }

    /// A Functional Fitness Session containing a jumping movement — no
    /// catalog Exercise is tagged `.jumping` yet, so one is built directly
    /// for this test, exactly the same "construct realistic domain data
    /// directly" pattern already used for edge cases in
    /// `ReadinessAdaptationTests`.
    private func makeFunctionalFitnessSessionWithJumping() -> Session {
        let boxJump = Exercise(
            canonicalName: "Box Jump", modality: .functionalFitness, equipment: "box", movementPattern: "jump",
            primaryTargets: [.quadriceps, .calves], movementFunctions: [.jumping], functionalModality: .gymnastics
        )
        context.insert(boxJump)
        let session = Session(name: "Metcon", modality: .functionalFitness)
        context.insert(session)
        let block = WorkoutBlock(type: .functionalFitness)
        context.insert(block)
        session.addBlock(block)
        let ffPrescription = FunctionalFitnessPrescription(
            stimulus: Stimulus(
                targetDurationDomain: .short, intensity: .high, loading: .light, movementFunctions: [.jumping],
                movementModalityMix: [ModalityCount(modality: .gymnastics, count: 1)],
                skillDemand: .moderate, systemicDemand: .high, scoreType: .roundsAndReps
            ),
            format: .amrap(capSeconds: 600)
        )
        context.insert(ffPrescription)
        block.attachFunctionalFitnessPrescription(ffPrescription)
        let movement = FunctionalFitnessMovement(exercise: boxJump, reps: 10)
        context.insert(movement)
        ffPrescription.addMovement(movement)
        return session
    }

    // MARK: 1 — upper-body pressing gets a relevant sequence

    func test1_UpperBodyPressingSessionGetsRelevantSequence() throws {
        let (exerciseCatalog, _) = seedCatalogs()
        let session = makeUpperBodyPressingSession(exerciseCatalog: exerciseCatalog)

        let sequence = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: nil), modelContext: context
        ))

        let names = Set(sequence.orderedItems.compactMap { $0.movement?.name })
        XCTAssertTrue(names.contains("Arm Circles") || names.contains("Band Pull-Apart") || names.contains("Scapular Wall Slide"),
                      "a pressing-dominant session should include shoulder/scapular preparation")
        XCTAssertFalse(names.contains("Ankle Rocks"), "an upper-body-only session should not need ankle mobility")
    }

    // MARK: 2/3 — lower-body/hinge session gets a meaningfully different, hinge-appropriate sequence

    func test2And3_LowerBodySessionGetsMeaningfullyDifferentHingeAppropriateSequence() throws {
        let (exerciseCatalog, _) = seedCatalogs()
        let upper = makeUpperBodyPressingSession(exerciseCatalog: exerciseCatalog)
        let (lower, _) = makeLowerA(exerciseCatalog: exerciseCatalog)

        let upperSequence = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: upper, readiness: nil), modelContext: context
        ))
        let lowerSequence = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: lower, readiness: nil), modelContext: context
        ))

        let upperNames = Set(upperSequence.orderedItems.compactMap { $0.movement?.name })
        let lowerNames = Set(lowerSequence.orderedItems.compactMap { $0.movement?.name })
        XCTAssertNotEqual(upperNames, lowerNames, "an upper-body and a lower-body/hinge session must not produce the same sequence")
        XCTAssertTrue(lowerNames.contains("Single-Leg RDL Reach (Bodyweight)") || lowerNames.contains("Glute Bridge") || lowerNames.contains("World's Greatest Stretch"),
                      "a hinge-heavy (Romanian Deadlift) session should include hinge/hip preparation")
    }

    // MARK: 4 — Functional Fitness session with jumping produces plyometric preparation

    func test4_FunctionalFitnessJumpingProducesPlyometricPreparation() throws {
        seedCatalogs()
        let session = makeFunctionalFitnessSessionWithJumping()

        let sequence = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: nil), modelContext: context
        ))

        let names = Set(sequence.orderedItems.compactMap { $0.movement?.name })
        XCTAssertTrue(names.contains("Pogo Hops"), "a jumping movement in the executable workout must surface plyometric preparation")
    }

    // MARK: 5 — stiffness re-ranks WITHOUT growing the nominal time budget

    func test5_StiffHipsChangeSelectionWithoutGrowingTimeBudget() throws {
        let (exerciseCatalog, _) = seedCatalogs()
        let (session, _) = makeLowerA(exerciseCatalog: exerciseCatalog)

        let baseline = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: nil), modelContext: context
        ))
        let stiffCheckIn = ReadinessCheckIn(recordedAt: Date(), reportedStiffness: [.glutes])
        let stiffSequence = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: stiffCheckIn), modelContext: context
        ))

        let baselineTotal = baseline.orderedItems.reduce(0) { $0 + ($1.movement?.estimatedSeconds ?? 0) }
        let stiffTotal = stiffSequence.orderedItems.reduce(0) { $0 + ($1.movement?.estimatedSeconds ?? 0) }
        XCTAssertLessThanOrEqual(stiffTotal, WarmupPolicy.targetDurationSeconds + WarmupPolicy.perItemMaxSeconds,
                                  "stiffness must re-rank within the budget, never materially grow it")
        XCTAssertNotEqual(baseline.orderedItems.map { $0.movement?.name }, stiffSequence.orderedItems.map { $0.movement?.name },
                          "a stiffness-flagged area must actually change ordering/selection")
        _ = baselineTotal
    }

    // MARK: 6 — pain excludes matching risky candidates

    func test6_PainExcludesMatchingCandidates() throws {
        let (exerciseCatalog, _) = seedCatalogs()
        let (session, _) = makeLowerA(exerciseCatalog: exerciseCatalog)

        let painCheckIn = ReadinessCheckIn(recordedAt: Date(), reportedPain: [.hamstrings])
        let sequence = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: painCheckIn), modelContext: context
        ))

        for item in sequence.orderedItems {
            let groups = Set(item.movement?.effectiveMuscleGroups ?? [])
            XCTAssertFalse(groups.contains(.hamstrings), "no candidate targeting a reported pain area may ever be included")
        }
    }

    // MARK: 7/8 — reads the FINAL EXECUTABLE workout, not the original prescription

    func test7_AcceptedRemovalOfRDLMeansHingePreparationNotDerivedFromOriginal() throws {
        let (exerciseCatalog, _) = seedCatalogs()
        let (session, _) = makeLowerA(exerciseCatalog: exerciseCatalog)
        let rdl = try XCTUnwrap(session.orderedBlocks.flatMap(\.orderedPrescriptions).first { $0.exercise?.canonicalName == "Romanian Deadlift" })
        let rdlBlock = try XCTUnwrap(rdl.workoutBlock)

        let checkIn = ReadinessCheckIn(recordedAt: Date(), reportedPain: [.back])
        // Simulate an ACCEPTED Stage 8B Level 4 removal of the RDL block.
        try ReadinessAdaptationDecisionUseCase.accept(
            ReadinessAdaptationProposalItem(triggeringSignals: [.pain], actionKind: .blockRemoved, explanation: "test", workoutBlock: rdlBlock),
            session: session, checkIn: checkIn, decidedAt: Date(), modelContext: context
        )

        let sequence = GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: checkIn), modelContext: context
        )

        let names = Set(sequence?.orderedItems.compactMap { $0.movement?.name } ?? [])
        XCTAssertFalse(names.contains("Single-Leg RDL Reach (Bodyweight)"),
                       "hinge-specific preparation must not be derived from a block the accepted adaptation already removed")
    }

    func test8_RejectedAdaptationMeansOriginalDemandsRemainAndWarmupReflectsThem() throws {
        let (exerciseCatalog, _) = seedCatalogs()
        let (session, _) = makeLowerA(exerciseCatalog: exerciseCatalog)
        let rdl = try XCTUnwrap(session.orderedBlocks.flatMap(\.orderedPrescriptions).first { $0.exercise?.canonicalName == "Romanian Deadlift" })
        let rdlBlock = try XCTUnwrap(rdl.workoutBlock)

        let checkIn = ReadinessCheckIn(recordedAt: Date(), reportedPain: [.back])
        // User REJECTS the proposed removal — original workout stands.
        try ReadinessAdaptationDecisionUseCase.reject(
            ReadinessAdaptationProposalItem(triggeringSignals: [.pain], actionKind: .blockRemoved, explanation: "test", workoutBlock: rdlBlock),
            checkIn: checkIn, decidedAt: Date(), modelContext: context
        )
        XCTAssertEqual(rdlBlock.status, .pending, "rejecting must leave the block exactly as it was")

        // Since the pain signal is still reported, hinge/hamstring prep is
        // still excluded from the CANDIDATE POOL by pain-exclusion (a
        // separate, correct mechanism) — but the point under test is that
        // the RDL block itself is still part of the executable workout
        // (not removed), which is what determines whether its demand is
        // derived at all going forward once the pain signal is absent.
        let noPainCheckIn = ReadinessCheckIn(recordedAt: Date())
        let sequence = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: noPainCheckIn), modelContext: context
        ))
        let names = Set(sequence.orderedItems.compactMap { $0.movement?.name })
        XCTAssertTrue(names.contains("Single-Leg RDL Reach (Bodyweight)") || names.contains("Glute Bridge") || names.contains("World's Greatest Stretch"),
                     "the rejected-adaptation workout still contains the RDL block, so hinge preparation is still derived")
    }

    // MARK: 9 — determinism

    func test9_SameInputsProduceExactSameOrderedSequence() throws {
        let (exerciseCatalog, _) = seedCatalogs()
        let (session, _) = makeLowerA(exerciseCatalog: exerciseCatalog)
        let checkIn = ReadinessCheckIn(recordedAt: Date(), reportedStiffness: [.glutes])

        let first = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: checkIn), modelContext: context
        ))
        let second = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: checkIn), modelContext: context
        ))

        XCTAssertEqual(first.orderedItems.map { $0.movement?.name }, second.orderedItems.map { $0.movement?.name })
    }

    // MARK: 10 — generic fallback

    func test10_GenericFallbackWhenSpecificCoverageUnavailable() throws {
        // A tiny, deliberately sparse catalog containing ONLY a general-
        // activation item — no squat/hinge/press-specific coverage at all.
        let fallback = WarmupMovement(name: "Marching in Place", emphasis: [.generalActivation], instructionText: "March in place.", defaultDurationSeconds: 30)
        context.insert(fallback)
        let exerciseCatalog = ExerciseCatalog.resolveOrInsert(context: context)
        let session = makeUpperBodyPressingSession(exerciseCatalog: exerciseCatalog)

        let sequence = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: nil), modelContext: context
        ))

        XCTAssertEqual(sequence.orderedItems.first?.movement?.name, "Marching in Place", "the general fallback tier must still produce a usable sequence")
    }

    // MARK: 11 — prefers a shorter relevant sequence over irrelevant padding

    func test11_PrefersShorterRelevantSequenceOverIrrelevantPadding() throws {
        let (exerciseCatalog, _) = seedCatalogs()
        let (session, _) = makeLowerA(exerciseCatalog: exerciseCatalog)
        // Pain excludes nearly every squat/hinge-specific candidate (Q6 of
        // the design's Example E). The generator must never include a
        // candidate that targets one of the reported pain areas just to
        // reach the nominal time budget — "irrelevant padding" here would
        // mean either a pain-conflicting item, or one that matches nothing
        // about today's session/readiness at all. The architecture rules
        // the second case out by construction (an unmatched candidate gets
        // no priority tier at all and is never considered) — this test
        // proves the first, safety-critical half directly.
        let checkIn = ReadinessCheckIn(recordedAt: Date(), reportedPain: [.back, .hamstrings, .glutes, .quadriceps])

        let sequence = GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: checkIn), modelContext: context
        )

        if let sequence {
            let painGroups: Set<MuscleGroup> = [.back, .hamstrings, .glutes, .quadriceps]
            for item in sequence.orderedItems {
                let groups = Set(item.movement?.effectiveMuscleGroups ?? [])
                XCTAssertTrue(groups.isDisjoint(with: painGroups),
                             "no candidate touching a reported pain area may ever appear, even to fill the time budget")
            }
            // Confirms the squat/hinge-specific tier was genuinely excluded,
            // not merely deprioritized.
            let names = Set(sequence.orderedItems.compactMap { $0.movement?.name })
            XCTAssertFalse(names.contains("Bodyweight Squat"))
            XCTAssertFalse(names.contains("Glute Bridge"))
            XCTAssertFalse(names.contains("World's Greatest Stretch"))
        }
        // A nil/empty result here (nothing safe survives) is an equally
        // acceptable, explicitly-designed outcome — never padding.
    }

    // MARK: 12/13 — per-item and total item caps

    func test12And13_RespectsPerItemAndMaxItemCaps() throws {
        let (exerciseCatalog, _) = seedCatalogs()
        let (session, _) = makeLowerA(exerciseCatalog: exerciseCatalog)

        let sequence = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: nil), modelContext: context
        ))

        XCTAssertLessThanOrEqual(sequence.orderedItems.count, WarmupPolicy.maxItemCount)
        for item in sequence.orderedItems {
            XCTAssertLessThanOrEqual(item.movement?.estimatedSeconds ?? 0, WarmupPolicy.perItemMaxSeconds)
        }
        _ = exerciseCatalog
    }

    // MARK: 14/15/16 — skip / partial / never gates completion

    func test14And15And16_SkippedOrPartialWarmupNeverAffectsSessionCompletion() throws {
        let (exerciseCatalog, _) = seedCatalogs()
        let session = makeUpperBodyPressingSession(exerciseCatalog: exerciseCatalog)
        let profile = PerformanceProfile()
        context.insert(profile)

        let sequence = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: nil), modelContext: context
        ))
        try RecordWarmupSequenceUseCase.record(sequence, for: session, modelContext: context)

        // Mark only the first item done, leave the rest — a partial warm-up.
        if let first = sequence.orderedItems.first {
            try RecordWarmupSequenceUseCase.markItemCompleted(first, modelContext: context)
        }
        // Then skip entirely is also a valid, independent action.
        try RecordWarmupSequenceUseCase.skipEntirely(sequence, modelContext: context)

        for block in session.orderedBlocks {
            for prescription in block.orderedPrescriptions {
                for setPrescription in prescription.orderedSetPrescriptions {
                    try LogSetUseCase.logSet(
                        setIndex: prescription.loggedSetResults.count, weight: setPrescription.targetWeight ?? 20,
                        reps: setPrescription.repRangeHigh ?? 0, targetRir: setPrescription.targetRir, actualRir: setPrescription.targetRir,
                        prBand: nil, scoringDirection: .higherIsBetter, context: .rx, setPrescription: setPrescription,
                        exercisePrescription: prescription, exercise: prescription.exercise!, performanceProfile: profile,
                        completedAt: Date(), modelContext: context
                    )
                }
            }
        }
        let summary = try CompleteSessionUseCase.complete(session, context: .full, asOf: Date(), modelContext: context)

        XCTAssertEqual(session.status, .completed, "a partially-completed, then explicitly skipped warm-up must never block normal completion")
        XCTAssertEqual(summary.completionContext, .full)
    }

    // MARK: 17/18 — persistence / relaunch / history distinguishability

    func test17And18_WarmupSequencePersistsAndDistinguishesRecommendedVsSkippedState() throws {
        let (exerciseCatalog, _) = seedCatalogs()
        let session = makeUpperBodyPressingSession(exerciseCatalog: exerciseCatalog)
        let sessionID = session.id

        let sequence = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: nil), modelContext: context
        ))
        try RecordWarmupSequenceUseCase.record(sequence, for: session, modelContext: context)
        if let first = sequence.orderedItems.first {
            try RecordWarmupSequenceUseCase.markItemCompleted(first, modelContext: context)
        }
        try RecordWarmupSequenceUseCase.skipEntirely(sequence, modelContext: context)

        let fetchContext = freshContext()
        let reloadedSession = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionID })).first)
        let reloadedSequence = try XCTUnwrap(reloadedSession.warmupSequence)

        XCTAssertTrue(reloadedSequence.wasSkippedEntirely, "the recommended-then-skipped state survives a relaunch")
        XCTAssertTrue(reloadedSequence.orderedItems.contains { $0.wasCompleted }, "which specific items were actually performed survives independently of the overall skip flag")
        XCTAssertTrue(reloadedSequence.orderedItems.contains { !$0.wasCompleted }, "an unfinished item is still distinguishable as unfinished")
    }

    // MARK: 19/20 — Exercise-linked vs. pure WarmupMovement matching

    func test19_ExerciseLinkedWarmupMovementReadsAuthoritativeExerciseMetadata() throws {
        let (exerciseCatalog, warmupCatalog) = seedCatalogs()
        let pushUpWarmup = try XCTUnwrap(warmupCatalog.first { $0.name == "Push-up" })

        XCTAssertTrue(pushUpWarmup.targetMuscleGroups.isEmpty, "an Exercise-linked WarmupMovement must never duplicate target metadata inline")
        XCTAssertEqual(Set(pushUpWarmup.effectiveMuscleGroups), Set(exerciseCatalog.pushUp.primaryTargets),
                      "effective targets must be read from the linked Exercise, not from the row's own (unset) fields")
    }

    func test20_PureWarmupMovementsWithoutExerciseLinksStillMatchCorrectly() throws {
        let (_, warmupCatalog) = seedCatalogs()
        let catCow = try XCTUnwrap(warmupCatalog.first { $0.name == "Cat-Cow" })

        XCTAssertNil(catCow.exercise, "a pure mobility drill has no Exercise equivalent")
        XCTAssertFalse(catCow.targetMuscleGroups.isEmpty, "its own inline tags are authoritative when there is no linked Exercise")
        XCTAssertEqual(catCow.effectiveMuscleGroups, catCow.targetMuscleGroups)
    }

    // MARK: 21 — excluded modalities never get a warm-up

    func test21_NoWarmupInsertedForExcludedModalities() throws {
        seedCatalogs()
        let session = Session(name: "Easy Run", modality: .conditioning)
        context.insert(session)
        let block = WorkoutBlock(type: .steadyState)
        context.insert(block)
        session.addBlock(block)
        let steadyStatePrescription = SteadyStatePrescription(activityType: .running, durationSeconds: 1800)
        context.insert(steadyStatePrescription)
        block.attachSteadyStatePrescription(steadyStatePrescription)

        let sequence = GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: nil), modelContext: context
        )

        XCTAssertNil(sequence, "Steady State/Interval/Running sessions must never receive a generated warm-up")
    }

    // MARK: SwiftData relationship / delete-rule behavior

    func testDeletingSessionCascadesItsWarmupSequenceAndItems() throws {
        let (exerciseCatalog, _) = seedCatalogs()
        let session = makeUpperBodyPressingSession(exerciseCatalog: exerciseCatalog)
        let sequence = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: nil), modelContext: context
        ))
        try RecordWarmupSequenceUseCase.record(sequence, for: session, modelContext: context)
        let sequenceID = sequence.id

        context.delete(session)
        try context.save()

        let survivingSequences = try context.fetch(FetchDescriptor<WarmupSequence>(predicate: #Predicate { $0.id == sequenceID }))
        XCTAssertTrue(survivingSequences.isEmpty, "deleting a Session must cascade its WarmupSequence, mirroring ReadinessCheckIn")
    }

    func testDeletingWarmupMovementNullifiesRatherThanCrashing() throws {
        let (exerciseCatalog, _) = seedCatalogs()
        let session = makeUpperBodyPressingSession(exerciseCatalog: exerciseCatalog)
        let sequence = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: nil), modelContext: context
        ))
        try RecordWarmupSequenceUseCase.record(sequence, for: session, modelContext: context)
        let item = try XCTUnwrap(sequence.orderedItems.first)
        let movement = try XCTUnwrap(item.movement)

        context.delete(movement)
        try context.save()

        XCTAssertNil(item.movement, "deleting the catalog movement must nullify the item's reference, never crash")
    }

    // MARK: Refinement pass — added after Stage 9B manual acceptance found
    // ranking issues (Observations 1 & 2). See STAGE9B_REFINEMENT_REPORT.md.

    /// Refinement test 1: pressing/scapular-relevant candidates must
    /// outrank weak generic fallback candidates for a pressing session —
    /// proves the root-cause-A fix (emphasis derivation no longer gated
    /// behind `MovementFunction`, which the seeded Hypertrophy catalog
    /// doesn't populate).
    func testRefinement1_PressingSessionPrefersScapularRelevantPreparationOverGenericFallback() throws {
        let (exerciseCatalog, _) = seedCatalogs()
        let session = makeUpperBodyPressingSession(exerciseCatalog: exerciseCatalog)

        let sequence = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: nil), modelContext: context
        ))
        let names = Set(sequence.orderedItems.compactMap { $0.movement?.name })

        XCTAssertTrue(names.contains("Band Pull-Apart"), "scapular preparation must now be recognized as relevant to a pressing session")
        XCTAssertTrue(names.contains("Scapular Wall Slide"))
        XCTAssertTrue(names.contains("Cat-Cow"), "thoracic preparation must now be recognized as relevant to a chest-dominant session")
        // Arm Circles legitimately matches via its own overheadShoulderMobility
        // tag (a real shoulder-prep movement, not merely a generalActivation
        // leak) and is correctly allowed to remain — only a movement with NO
        // specific relevance signal at all must be excluded once a relevant
        // pool exists.
        XCTAssertFalse(names.contains("Marching in Place"),
                       "a purely generic fallback item (no specific muscle/emphasis relevance at all) must not appear once specifically relevant candidates exist")
    }

    /// Refinement test 2: when a session's catalog coverage is genuinely
    /// sufficient, the generator must not stop early at a token ~2-minute
    /// result — proves this is a selection issue, not a hard architectural
    /// ceiling, using a dedicated catalog with enough real pressing
    /// coverage to legitimately approach the target window.
    func testRefinement2_SufficientRelevantCoverageDoesNotTerminateAtTwoMinutes() throws {
        let exerciseCatalog = ExerciseCatalog.resolveOrInsert(context: context)
        // A dedicated, deliberately richer press-relevant candidate set —
        // proves the architecture fills toward the budget from RELEVANT
        // content alone when enough of it exists, rather than being
        // capped at whatever a small shipped catalog happens to total.
        let richCatalog: [(String, [MuscleGroup], [PreparationEmphasis], Int?, Int?, Bool)] = [
            ("Band Pull-Apart A", [.shoulders], [.overheadShoulderMobility], nil, 12, false),
            ("Band Pull-Apart B", [.shoulders], [.overheadShoulderMobility], nil, 12, false),
            ("Scapular Wall Slide", [.shoulders, .back], [.overheadShoulderMobility], nil, 10, false),
            ("Cat-Cow", [.core], [.thoracicMobility], 45, nil, false),
            ("Chest Opener Stretch", [.chest], [.thoracicMobility], 45, nil, false),
            ("Push-up Ramp", [.chest, .triceps], [.generalActivation], nil, 10, false),
        ]
        for (name, groups, emphasis, duration, reps, sides) in richCatalog {
            context.insert(WarmupMovement(
                name: name, targetMuscleGroups: groups, emphasis: emphasis, instructionText: "Test movement.",
                defaultDurationSeconds: duration, defaultReps: reps, hasSides: sides
            ))
        }
        let session = makeUpperBodyPressingSession(exerciseCatalog: exerciseCatalog)

        let sequence = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: nil), modelContext: context
        ))
        let total = sequence.orderedItems.reduce(0) { $0 + ($1.movement?.estimatedSeconds ?? 0) }

        XCTAssertGreaterThan(total, 150, "with genuinely sufficient relevant coverage, the sequence must not stop at a token ~2-minute result")
    }

    /// Refinement test 3/4 (Observation 2): a pure lower-body session
    /// must not include an upper-body-only preparation movement merely
    /// to approach the 300-second target — a shorter, fully relevant
    /// sequence is the correct, preferred result.
    func testRefinement3And4_LowerBodySessionExcludesUpperBodyOnlyFillerEvenIfShorterThanTarget() throws {
        let (exerciseCatalog, _) = seedCatalogs()
        let (session, _) = makeLowerA(exerciseCatalog: exerciseCatalog)

        let sequence = try XCTUnwrap(GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: nil), modelContext: context
        ))
        let names = Set(sequence.orderedItems.compactMap { $0.movement?.name })
        let total = sequence.orderedItems.reduce(0) { $0 + ($1.movement?.estimatedSeconds ?? 0) }

        XCTAssertFalse(names.contains("Arm Circles"), "a shoulder-only movement must never appear in a pure lower-body sequence merely to fill the budget")
        XCTAssertFalse(names.contains("Band Pull-Apart"))
        XCTAssertFalse(names.contains("Scapular Wall Slide"))
        // A shorter, fully relevant sequence is an explicitly accepted
        // outcome (D-W3) — never asserting the total must reach 300s.
        XCTAssertGreaterThan(total, 0)
    }

    /// Refinement test 5: when pain exclusion removes nearly every
    /// candidate, the generator stops rather than padding with whatever
    /// remains — re-proven directly against the fix (distinct from
    /// `test11`, which covers the same principle against the shipped
    /// catalog; this uses a maximally-restrictive case).
    func testRefinement5_StopsRatherThanPadsWhenNoRelevantCandidatesRemain() throws {
        let (exerciseCatalog, _) = seedCatalogs()
        let (session, _) = makeLowerA(exerciseCatalog: exerciseCatalog)
        // Excludes every muscle group any seeded catalog movement targets
        // except a bare few — an intentionally extreme case.
        let checkIn = ReadinessCheckIn(recordedAt: Date(), reportedPain: [.quadriceps, .glutes, .hamstrings, .calves, .back, .shoulders, .chest, .core])

        let sequence = GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: checkIn), modelContext: context
        )

        // Either nil (nothing safe survives) or, if something with truly
        // no tagged muscle group at all survives (e.g. a pure fallback
        // item), it must be minimal — never padded toward 300s with
        // irrelevant content.
        if let sequence {
            let total = sequence.orderedItems.reduce(0) { $0 + ($1.movement?.estimatedSeconds ?? 0) }
            XCTAssertLessThan(total, WarmupPolicy.targetDurationSeconds, "must never be padded up toward the target once relevant coverage is exhausted")
        }
    }
}
