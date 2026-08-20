import XCTest
import SwiftData
@testable import TrainingOS

/// Tactical Planning Orchestration: closes `TACTICAL_PLANNING_HANDOFF.md`
/// §3's "starting a new phase" gap. Every fixture here goes through the
/// real, unmodified `AcceptStrategicPlanUseCase`/`LongTermPlanner`
/// pipeline — never a seed-only shortcut — so these tests prove the same
/// entry points a real onboarding flow will call later.
@MainActor
final class TacticalPlanningOrchestrationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()
    let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar.current.date(from: components)!
    }

    /// Real acceptance path: Goal -> proposeStrategicPlan -> AcceptStrategicPlanUseCase.
    /// Returns the first (still `.planned`) phase and its goal.
    private func makeAcceptedPlan(primaryType: GoalType = .muscleGain, asOf: Date) throws -> (goal: Goal, phase: TrainingPhase) {
        let goal = Goal(ownerUserID: ownerUserID, primaryType: primaryType, targetDate: Calendar.current.date(byAdding: .year, value: 1, to: asOf), createdAt: asOf)
        context.insert(goal)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: asOf)
        let phase = try XCTUnwrap(plan.orderedPhases.first)
        return (goal, phase)
    }

    private func availability() -> UserAvailability {
        UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1)
    }

    private func materializationContext() -> TacticalMaterializationContext {
        TacticalMaterializationContext(equipmentProfile: equipment)
    }

    // MARK: Basic phase start

    func testStartingAPlannedPhaseActivatesItAndAttachesTheMixExactlyOnce() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        XCTAssertEqual(fixture.phase.status, .planned)

        let candidates = LongTermPlanner.proposeTrainingMix(phase: fixture.phase, goal: fixture.goal)
        let recommended = try XCTUnwrap(candidates.first { $0.roles.contains(.recommended) })

        let result = try StartPhaseUseCase.start(
            phase: fixture.phase, mix: recommended.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext(), context: context
        )

        XCTAssertEqual(fixture.phase.status, .active)
        XCTAssertEqual(fixture.phase.trainingMixes.count, 1, "attached exactly once")
        XCTAssertEqual(fixture.phase.selectedTrainingMix?.id, recommended.mix.id)
        XCTAssertFalse(result.instancesByComponent.isEmpty)
        XCTAssertFalse(result.scheduleProposal.placements.isEmpty)
    }

    func testStartingAnAlreadyActivePhaseThrowsRatherThanReInstantiating() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        let candidates = LongTermPlanner.proposeTrainingMix(phase: fixture.phase, goal: fixture.goal)
        let recommended = try XCTUnwrap(candidates.first { $0.roles.contains(.recommended) })

        try StartPhaseUseCase.start(
            phase: fixture.phase, mix: recommended.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext(), context: context
        )
        let instanceCountBefore = fixture.phase.programInstances.count

        XCTAssertThrowsError(try StartPhaseUseCase.start(
            phase: fixture.phase, mix: recommended.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext(), context: context
        )) { error in
            XCTAssertEqual(error as? StartPhaseError, .phaseNotPlanned)
        }
        XCTAssertEqual(fixture.phase.programInstances.count, instanceCountBefore, "never re-instantiates")
    }

    // MARK: Real Sessions reach Today/Week

    func testStartingAPhaseProducesRealSessionsPlacedOnRealDays() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(primaryType: .generalStrength, asOf: asOf)
        let candidates = LongTermPlanner.proposeTrainingMix(phase: fixture.phase, goal: fixture.goal)
        let recommended = try XCTUnwrap(candidates.first { $0.roles.contains(.recommended) })

        try StartPhaseUseCase.start(
            phase: fixture.phase, mix: recommended.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext(), context: context
        )

        let instance = try XCTUnwrap(fixture.phase.primaryInstance)
        XCTAssertFalse(instance.sessions.isEmpty)
        for session in instance.sessions {
            XCTAssertNotNil(session.day, "every real Session is actually placed on a real Day")
            XCTAssertEqual(session.status, .scheduled)
        }
    }

    // MARK: No fabrication — PerformanceProfile untouched, no future weeks fabricated

    func testStartingAPhaseNeverTouchesPerformanceProfileAndNeverFabricatesBeyondWeekZeroForStrength() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(primaryType: .generalStrength, asOf: asOf)
        let profile = PerformanceProfile()
        context.insert(profile)
        let setResultCountBefore = try context.fetchCount(FetchDescriptor<SetResult>())

        let candidates = LongTermPlanner.proposeTrainingMix(phase: fixture.phase, goal: fixture.goal)
        let recommended = try XCTUnwrap(candidates.first { $0.roles.contains(.recommended) })
        try StartPhaseUseCase.start(
            phase: fixture.phase, mix: recommended.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: profile, availability: availability(),
            materializationContext: materializationContext(), context: context
        )

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetResult>()), setResultCountBefore, "starting a phase creates prescriptions, never results")
        XCTAssertTrue(profile.exerciseProfiles.isEmpty, "no history is fabricated just from starting a phase")

        let instance = try XCTUnwrap(fixture.phase.primaryInstance)
        XCTAssertEqual(ProgramWeekGrouping.realSessions(in: instance, forWeek: 1).count, 0, "week 1 is never fabricated ahead of real week-0 results")
    }

    // MARK: Preserving user choice over the recommendation

    func testUserSelectedMixIsMaterializedNotSilentlyReplacedByTheRecommendation() throws {
        let asOf = date(2026, 1, 5)
        // enduranceEvent's two candidate mixes are both Steady State/
        // Interval/Hypertrophy only — no Functional Fitness component, so
        // this test doesn't need a candidateExercises pool to materialize
        // cleanly (that's exercised directly in the mixed-modality test).
        let fixture = try makeAcceptedPlan(primaryType: .enduranceEvent, asOf: asOf)
        let candidates = LongTermPlanner.proposeTrainingMix(phase: fixture.phase, goal: fixture.goal)
        let recommended = try XCTUnwrap(candidates.first { $0.roles.contains(.recommended) })
        let alternative = try XCTUnwrap(candidates.first { $0.mix.id != recommended.mix.id })

        // The user explicitly picked the non-recommended alternative.
        let userSelectedMix = alternative.mix
        userSelectedMix.kind = .selected

        let result = try StartPhaseUseCase.start(
            phase: fixture.phase, mix: userSelectedMix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext(), context: context
        )

        XCTAssertEqual(fixture.phase.selectedTrainingMix?.id, userSelectedMix.id, "the user's own choice is what got materialized")
        XCTAssertEqual(result.mix.id, userSelectedMix.id)
    }

    // MARK: Slice 2 — the real cross-window hypertrophy centerpiece

    /// 3 disjoint-tagged primary candidates (one per possible
    /// `HypertrophyProgramGenerator` split — `fullBody`/`armsShoulders`
    /// share `.shoulders`, `legs` uses `.quadriceps`, `backChest` uses
    /// `.back`) plus a paired/accessory candidate (`[.chest, .triceps]`,
    /// constant across every split) — deliberately non-overlapping so slot
    /// resolution is unambiguous regardless of which built-in candidate
    /// `LongTermPlanner.proposeProgram` ranks first, and each real
    /// prescription can be identified by its resolved exercise's name
    /// rather than by guessing which split won.
    private struct SlotCandidates {
        let primaryShoulders: Exercise
        let primaryQuads: Exercise
        let primaryBack: Exercise
        let pairedAccessory: Exercise
        let pairedAccessoryAlt: Exercise
        var all: [Exercise] { [primaryShoulders, primaryQuads, primaryBack, pairedAccessory, pairedAccessoryAlt] }
        var primaryNames: Set<String> { [primaryShoulders.canonicalName, primaryQuads.canonicalName, primaryBack.canonicalName] }
    }

    private func makeSlotCandidates() -> SlotCandidates {
        func exercise(_ name: String, _ targets: [MuscleGroup]) -> Exercise {
            let ex = Exercise(canonicalName: name, modality: .hypertrophy, equipment: "barbell", movementPattern: "test", primaryTargets: targets)
            context.insert(ex)
            return ex
        }
        // "Aaa"/"Zzz" prefixes are load-bearing, not cosmetic: fullBody's
        // primary targets ([.chest, .shoulders]) overlap pairedAccessory's
        // tags ([.chest, .triceps]) on `.chest` (and armsShoulders'
        // primary overlaps on `.triceps`), so BOTH a primary candidate and
        // pairedAccessory are legitimately eligible for those splits'
        // primary slot — resolution's own alphabetical tie-break must
        // therefore prefer the primary candidates every time, which
        // requires them to consistently sort first.
        return SlotCandidates(
            primaryShoulders: exercise("Aaa Centerpiece Primary Shoulders", [.shoulders]),
            primaryQuads: exercise("Aaa Centerpiece Primary Quads", [.quadriceps]),
            primaryBack: exercise("Aaa Centerpiece Primary Back", [.back]),
            pairedAccessory: exercise("Zzz Centerpiece Paired Accessory", [.chest, .triceps]),
            pairedAccessoryAlt: exercise("Zzz Centerpiece Paired Accessory Alt", [.chest, .triceps])
        )
    }

    /// Point 12's centerpiece test, end to end through the REAL production
    /// path — no hand-authored `ProgramDefinition`, no shortcut:
    /// `HypertrophyProgramGenerator` (via `LongTermPlanner.proposeProgram`)
    /// -> `StartPhaseUseCase` (which now also resolves every `ExerciseSlot`
    /// to a concrete `Exercise`, GAP A) -> real week-0 `ExercisePrescription`s
    /// -> real logged sets (`RecordSetResultUseCase`) -> real collected
    /// hypertrophy feedback (`RecordAutoregulationFeedbackUseCase`, now
    /// reaching the primary movement's own set count via GAP B's fix) ->
    /// `RollTacticalWindowUseCase.rollForward` materializes week 1 -> every
    /// resulting value is checked against an independent call to the same
    /// pure `StrengthProgressionEngine` functions the orchestration itself
    /// calls, fed the same real captured inputs — proving wiring
    /// correctness, never re-deriving the math by hand.
    func testRealCrossWindowHypertrophyProgressionUsesRealLoggedResultsAndCollectedFeedback() throws {
        let asOf = date(2026, 1, 5)
        // `.muscleGain` — unlike `.generalStrength`, which can recommend a
        // Powerlifting primary component instead — always maps to a
        // Hypertrophy primary component (`muscleGainFocusedHypertrophyMix`/
        // `muscleGainVariedMix` both use `programmingSystem: .hypertrophy`),
        // which this centerpiece test specifically needs.
        let fixture = try makeAcceptedPlan(primaryType: .muscleGain, asOf: asOf)
        let candidates = makeSlotCandidates()
        let mixCandidates = LongTermPlanner.proposeTrainingMix(phase: fixture.phase, goal: fixture.goal)
        let recommended = try XCTUnwrap(mixCandidates.first { $0.roles.contains(.recommended) })
        XCTAssertEqual(recommended.mix.orderedComponents.first { $0.priority == .primary }?.programmingSystem, .hypertrophy)

        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        // Real history for every possible winning split's primary — week 0
        // must resolve a REAL (non-calibrationRequired) weight regardless
        // of which built-in candidate ranks first.
        for primaryCandidate in [candidates.primaryShoulders, candidates.primaryQuads, candidates.primaryBack] {
            let exerciseProfile = ExercisePerformanceProfile(estimatedOneRepMax: 100, confidence: 0.9)
            exerciseProfile.exercise = primaryCandidate
            context.insert(exerciseProfile)
            performanceProfile.addExerciseProfile(exerciseProfile)
        }

        let materializationContext = TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.all)

        try StartPhaseUseCase.start(
            phase: fixture.phase, mix: recommended.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: performanceProfile, availability: availability(),
            materializationContext: materializationContext, context: context
        )

        let instance = try XCTUnwrap(fixture.phase.primaryInstance)
        let week0Prescriptions = instance.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions)
        let primaryWeek0 = try XCTUnwrap(week0Prescriptions.first { candidates.primaryNames.contains($0.exercise?.canonicalName ?? "") })
        let pairedWeek0 = try XCTUnwrap(week0Prescriptions.first { $0.exercise?.canonicalName == candidates.pairedAccessory.canonicalName })

        // Week 0 must have used REAL history, never calibrationRequired.
        XCTAssertEqual(primaryWeek0.appliedLoadReasonCode, .rmBasedLoad, "seeded history must be used — this is not a calibrationRequired case")
        XCTAssertEqual(primaryWeek0.appliedSetCountReasonCode, .fixedSetSchedule, "week 0's autoregulated baseline is a fixed schedule value, per the engine's own contract")
        XCTAssertEqual(primaryWeek0.orderedSetPrescriptions.count, 3, "AutoregulatedSetCount.baselineSets")

        // Real logged sets for both movements — actual results, not fabricated.
        for prescription in [primaryWeek0, pairedWeek0] {
            for setPrescription in prescription.orderedSetPrescriptions {
                RecordSetResultUseCase.recordSet(
                    setIndex: setPrescription.sortIndex, weight: setPrescription.targetWeight ?? 60, reps: 8,
                    targetRir: setPrescription.targetRir, actualRir: setPrescription.targetRir, prBand: nil,
                    scoringDirection: .higherIsBetter, context: .rx, setPrescription: setPrescription,
                    exercisePrescription: prescription, exercise: try XCTUnwrap(prescription.exercise),
                    performanceProfile: performanceProfile, completedAt: asOf, modelContext: context
                )
            }
        }
        let week0Block = try XCTUnwrap(instance.sessions.first { $0.orderedBlocks.contains { $0.orderedPrescriptions.contains { $0.id == primaryWeek0.id } } }?.orderedBlocks.first)
        try CompleteBlockUseCase.complete(week0Block, context: .full, modelContext: context)
        let week0Session = try XCTUnwrap(week0Block.session)
        try CompleteSessionUseCase.complete(week0Session, context: .full, asOf: asOf, modelContext: context)

        // Real collected hypertrophy feedback: the paired accessory (now
        // the primary's own rating source, GAP B) felt easy — +1.
        try RecordAutoregulationFeedbackUseCase.recordRating(1, for: pairedWeek0, modelContext: context)

        // Roll forward — real week 1, from real results/feedback alone.
        let rollForwardDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: asOf))
        let rollResult = try XCTUnwrap(RollTacticalWindowUseCase.rollForward(
            mix: recommended.mix, asOf: rollForwardDate, ownerUserID: ownerUserID,
            performanceProfile: performanceProfile, availability: availability(),
            materializationContext: materializationContext, context: context
        ))
        XCTAssertFalse(rollResult.newSessionsByComponent.isEmpty)

        let week1Prescriptions = rollResult.newSessionsByComponent.values.flatMap { $0 }.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions)
        let primaryWeek1 = try XCTUnwrap(week1Prescriptions.first { $0.sourcePrescriptionTemplate?.id == primaryWeek0.sourcePrescriptionTemplate?.id })
        let pairedWeek1 = try XCTUnwrap(week1Prescriptions.first { $0.sourcePrescriptionTemplate?.id == pairedWeek0.sourcePrescriptionTemplate?.id })

        // F: real feedback reaches the primary's own next-window set count.
        XCTAssertEqual(primaryWeek1.appliedSetCountReasonCode, .autoregulatedSetIncrease)
        XCTAssertEqual(primaryWeek1.orderedSetPrescriptions.count, 4, "3 (week 0 baseline) + 1 (the real collected rating), per the existing unmodified engine formula")

        // Independently recompute week 1's expected weight from the same
        // real, captured inputs the orchestration itself used — never a
        // hardcoded literal (the winning split's weekOneFactor legitimately
        // varies — 0.85 normally, 1.0 for the confirmed Legs Heavy
        // exception — so this must be derived, not guessed).
        let primaryTemplate = try XCTUnwrap(primaryWeek0.sourcePrescriptionTemplate)
        let primaryRules = try XCTUnwrap(primaryTemplate.rules)
        let weekZeroResolvedWeight = try XCTUnwrap(AutoregulationRatingResolver.weekZeroResolvedWeight(for: primaryTemplate, in: instance))
        XCTAssertEqual(weekZeroResolvedWeight, primaryWeek0.orderedSetPrescriptions.first?.targetWeight)

        let expectedPrimaryWeek1 = StrengthProgressionEngine.resolveWeight(
            rules: primaryRules, weekIndex: 1, rmKilograms: nil, weekOneResolvedWeightKg: weekZeroResolvedWeight,
            pairedSlotResolvedWeightKg: nil, equipmentProfile: equipment
        )
        XCTAssertEqual(primaryWeek1.orderedSetPrescriptions.first?.targetWeight, expectedPrimaryWeek1.weightKg)
        XCTAssertEqual(primaryWeek1.appliedLoadReasonCode, expectedPrimaryWeek1.reasonCode)

        let expectedPrimaryRepGoal = StrengthProgressionEngine.resolveRepGoal(rules: primaryRules, weekIndex: 1)
        XCTAssertEqual(primaryWeek1.appliedRepGoalReasonCode, expectedPrimaryRepGoal.reasonCode)
        XCTAssertTrue(primaryWeek1.orderedSetPrescriptions.allSatisfy { $0.targetRir == 0 }, "Family A's rep goal is always toFailure -> RIR 0, never invented")

        // G: the paired/accessory's own linkedToPairedSlot load and fixed
        // set schedule are unchanged by primary now also having its own
        // pairedSlot (GAP B must not have disturbed this).
        let pairedTemplate = try XCTUnwrap(pairedWeek0.sourcePrescriptionTemplate)
        let pairedRules = try XCTUnwrap(pairedTemplate.rules)
        XCTAssertEqual(pairedWeek1.appliedSetCountReasonCode, .fixedSetSchedule)
        XCTAssertEqual(pairedWeek1.orderedSetPrescriptions.count, 2, "fixed schedule [2,2,2,2] — week index 1")

        let expectedPairedWeek1 = StrengthProgressionEngine.resolveWeight(
            rules: pairedRules, weekIndex: 1, rmKilograms: nil, weekOneResolvedWeightKg: nil,
            pairedSlotResolvedWeightKg: primaryWeek1.orderedSetPrescriptions.first?.targetWeight, equipmentProfile: equipment
        )
        XCTAssertEqual(pairedWeek1.orderedSetPrescriptions.first?.targetWeight, expectedPairedWeek1.weightKg, "the accessory's load must still be a fraction of the PRIMARY's just-resolved week-1 weight, not disturbed by primary's own separate pairedSlot use")
        XCTAssertEqual(pairedWeek1.appliedLoadReasonCode, .linkedToPairedSlotLoad)
    }

    // MARK: GOING FORWARD override still wins after slot resolution

    func testGoingForwardOverrideStillWinsOverTheResolvedDefaultAcrossRollForward() throws {
        let asOf = date(2026, 1, 5)
        // `.muscleGain` guarantees a Hypertrophy primary component (see the
        // centerpiece test's own comment) — keeps this test's candidate
        // tag sets (built around Hypertrophy's specific slot shapes)
        // unambiguous.
        let fixture = try makeAcceptedPlan(primaryType: .muscleGain, asOf: asOf)
        let candidates = makeSlotCandidates()
        let mixCandidates = LongTermPlanner.proposeTrainingMix(phase: fixture.phase, goal: fixture.goal)
        let recommended = try XCTUnwrap(mixCandidates.first { $0.roles.contains(.recommended) })
        let materializationContext = TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.all)

        try StartPhaseUseCase.start(
            phase: fixture.phase, mix: recommended.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext, context: context
        )

        let instance = try XCTUnwrap(fixture.phase.primaryInstance)
        let week0Prescriptions = instance.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions)
        let pairedWeek0 = try XCTUnwrap(week0Prescriptions.first { $0.exercise?.canonicalName == candidates.pairedAccessory.canonicalName })
        let pairedSlot = try XCTUnwrap(pairedWeek0.sourceExerciseSlot)
        XCTAssertEqual(pairedWeek0.exercise?.id, candidates.pairedAccessory.id, "sanity check on the resolved default before overriding it")

        try SubstituteExerciseUseCase.substituteGoingForward(instance: instance, slot: pairedSlot, with: candidates.pairedAccessoryAlt, context: context)
        try CompleteBlockUseCase.complete(try XCTUnwrap(pairedWeek0.workoutBlock), context: .full, modelContext: context)
        try CompleteSessionUseCase.complete(try XCTUnwrap(pairedWeek0.workoutBlock?.session), context: .full, asOf: asOf, modelContext: context)

        let rollForwardDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: asOf))
        let rollResult = try XCTUnwrap(RollTacticalWindowUseCase.rollForward(
            mix: recommended.mix, asOf: rollForwardDate, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext, context: context
        ))

        let week1Prescriptions = rollResult.newSessionsByComponent.values.flatMap { $0 }.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions)
        let pairedWeek1 = try XCTUnwrap(week1Prescriptions.first { $0.sourcePrescriptionTemplate?.id == pairedWeek0.sourcePrescriptionTemplate?.id })
        XCTAssertEqual(pairedWeek1.exercise?.id, candidates.pairedAccessoryAlt.id, "the GOING FORWARD override must win over the slot's originally-resolved default for every future materialization")
    }
}
