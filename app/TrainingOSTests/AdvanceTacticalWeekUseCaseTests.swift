import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 10R.4B/4C: proves the real, safe, user-initiated production
/// trigger for tactical week advancement — idempotency, the defense-in-
/// depth final-week bounds guard, the real 3-Day Full Body reference
/// program's M1/M2/M3 week-to-week progression driven through the real
/// `AdvanceTacticalWeekUseCase` (not direct `StrengthMaterializer` calls),
/// mixed-modality gating, the tightened mesocycle-transition gate, and
/// persistence/crash-recovery.
///
/// **Fixture boundary, stated plainly** (mirrors
/// `StartNextHypertrophyPhaseUseCaseTests`'s own documented precedent):
/// exactly ONE test (`testMesocycle1RealWalkthroughFullyLoggedThroughExhaustion`)
/// logs a real `SetResult` for every set of every week, end to end,
/// through the real `SessionDetailView`-equivalent completion sequence
/// (`LogSetUseCase` + `RecordAutoregulationFeedbackUseCase` +
/// `CompleteSessionUseCase`) — proving the full real production path
/// genuinely works, including real progression math driven by real
/// logged data. Every other test uses the cheaper, Locked-Decision-3-
/// sanctioned `.skipped` terminal-marking helper (`skipEveryRealSession`)
/// to reach a terminal week without fabricating performance data — this
/// is not a weaker proof of the LIFECYCLE mechanism (idempotency,
/// bounds, gating, exhaustion, persistence all work identically
/// regardless of *why* a week is terminal), only a cheaper one, and
/// content/progression-value fidelity at each materialized week is
/// still asserted directly against the already-accepted source values
/// from Stage 10R.1-10R.3.
@MainActor
final class AdvanceTacticalWeekUseCaseTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()
    let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)
    let startDate = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
        // Stage TE.1: real fixture default — see identical note in
        // StartNextHypertrophyMesocycleUseCaseTests.setUpWithError.
        let user = User(displayName: "TE.1 Fixture User")
        context.insert(user)
        let profile = UserProfile()
        context.insert(profile)
        user.attachProfile(profile)
        let fullGym = TrainingEnvironment(name: "Test Full Gym", availableEquipment: EquipmentRequirement.allCases)
        context.insert(fullGym)
        profile.trainingEnvironments = [fullGym]
        profile.defaultTrainingEnvironment = fullGym
        try? context.save()
    }

    private func freshContext() -> ModelContext { ModelContext(container) }

    private func availability() -> UserAvailability {
        UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1)
    }

    private func materializationContext(using ctx: ModelContext? = nil) throws -> TacticalMaterializationContext {
        TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try (ctx ?? context).fetch(FetchDescriptor<Exercise>()), trainingEnvironment: TrainingEnvironmentTestSupport.full(context: ctx ?? context))
    }

    private struct Fixture {
        var plan: TrainingPlan
        var phase: TrainingPhase
        var instance: ProgramInstance
        var mix: TrainingMix
        var component: TrainingMixComponent
    }

    /// Builds a real, calibrated `phaseType` phase/instance/mix/component
    /// through the real production path (resolve slots -> calibrate ->
    /// `materializeOnceCalibrationComplete`), ending with a real
    /// materialized Week 1 — the same discipline
    /// `StartNextHypertrophyPhaseUseCaseTests.makeCalibratedMesocycle1`
    /// already established, generalized here to any of the 3 recovered
    /// phase types (Stage 10R.1/10R.2/10R.3 all landed real content for
    /// all 3).
    @discardableResult
    private func makeCalibratedInstance(phaseType: HypertrophyPhaseType, rmKilograms: Double = 100, startDateOverride: Date? = nil) throws -> Fixture {
        let effectiveStartDate = startDateOverride ?? startDate
        _ = ExerciseCatalog.resolveOrInsert(context: context)
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .muscleGain)
        context.insert(goal)
        let plan = TrainingPlan(status: .active)
        context.insert(plan)
        goal.addPlan(plan)

        let phase = TrainingPhase(type: .muscleGain, startDate: effectiveStartDate, priorityRule: .strength, status: .active)
        context.insert(phase)
        plan.addPhase(phase)

        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 3, split: .fullBody, phaseType: phaseType),
            provenance: .constructed(reason: "test fixture"), context: context
        )
        let instance = ProgramInstance(ownerUserID: ownerUserID, startDate: effectiveStartDate, status: .active, priority: .primary)
        context.insert(instance)
        instance.programDefinition = definition
        phase.addProgramInstance(instance)

        let mix = TrainingMix(kind: .selected, name: "3-Day Full Body Hypertrophy")
        context.insert(mix)
        phase.addTrainingMix(mix)
        let component = TrainingMixComponent(label: "Hypertrophy", programmingSystem: .hypertrophy, priority: .primary, frequency: SessionFrequency(target: 3))
        context.insert(component)
        mix.addComponent(component)
        component.programInstance = instance

        try ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: try context.fetch(FetchDescriptor<Exercise>()), environment: TrainingEnvironmentTestSupport.full(context: context))

        for requirement in RequiredSourceCalibrationsUseCase.stillRequired(for: definition, instance: instance) {
            RecordSourceRMCalibrationUseCase.record(exercise: requirement.exercise, rmType: requirement.rmType, kilograms: rmKilograms, for: instance, modelContext: context)
        }
        try context.save()

        _ = try StartPhaseUseCase.materializeOnceCalibrationComplete(
            component: component, instance: instance, phase: phase, mix: mix, asOf: effectiveStartDate,
            ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: try materializationContext(), context: context
        )
        return Fixture(plan: plan, phase: phase, instance: instance, mix: mix, component: component)
    }

    /// Locked Decision 3: marks every real Session in `weekIndex`
    /// `.skipped` — terminal, with zero fabricated `SetResult`/rating.
    private func skipEveryRealSession(in instance: ProgramInstance, weekIndex: Int) throws {
        for session in ProgramWeekGrouping.realSessions(in: instance, forWeek: weekIndex) {
            try ChangeSessionStatusUseCase.skip(session, modelContext: context)
        }
    }

    /// Logs a real `SetResult` for every prescribed set in `weekIndex`,
    /// answers every pending rating prompt, then completes every session
    /// — the real `SessionDetailView.beginFinish`/`finish` sequence.
    private func completeEveryRealSessionFully(in instance: ProgramInstance, weekIndex: Int, rating: Int, performanceProfile: PerformanceProfile) throws {
        for session in ProgramWeekGrouping.realSessions(in: instance, forWeek: weekIndex) {
            for block in session.orderedBlocks {
                for prescription in block.orderedPrescriptions {
                    guard let exercise = prescription.exercise else { continue }
                    for setPrescription in prescription.orderedSetPrescriptions {
                        _ = try LogSetUseCase.logSet(
                            setIndex: setPrescription.sortIndex, weight: setPrescription.targetWeight ?? 50,
                            reps: 8, targetRir: setPrescription.targetRir, actualRir: setPrescription.targetRir,
                            prBand: nil, scoringDirection: .higherIsBetter, context: .rx, setPrescription: setPrescription,
                            exercisePrescription: prescription, exercise: exercise, performanceProfile: performanceProfile,
                            completedAt: Date(), modelContext: context
                        )
                    }
                }
            }
            for prescription in HypertrophyFeedbackPrompts.pending(for: session) {
                try RecordAutoregulationFeedbackUseCase.recordRating(rating, for: prescription, modelContext: context)
            }
            _ = try CompleteSessionUseCase.complete(session, context: .full, asOf: Date(), modelContext: context)
        }
    }

    /// The real-world "now" a caller would supply when rolling forward
    /// from `weekIndex` to `weekIndex + 1` — roughly a week after that
    /// week itself started. `RollTacticalWindowUseCase.rollForward`'s own
    /// `SchedulingConstraints.window` is anchored at this `asOf`
    /// (`RollTacticalWindowUseCase.swift`), completely independent of the
    /// materializer's own internal week-offset math — passing a stale
    /// `asOf` (e.g. always `startDate`) makes every rolled week compete
    /// for the SAME 7-day scheduling window the first week already
    /// occupies, which is genuinely infeasible, not a test bug to work
    /// around silently.
    private func rollDate(afterWeekIndex weekIndex: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: (weekIndex + 1) * 7, to: startDate) ?? startDate
    }

    @discardableResult
    private func advanceOnce(_ fixture: Fixture, performanceProfile: PerformanceProfile? = nil) throws -> AdvanceTacticalWeekUseCase.Outcome {
        let weekIndex = TacticalWeekCompletion.currentMaterializedWeekIndex(for: fixture.instance) ?? 0
        return try AdvanceTacticalWeekUseCase.advance(
            phase: fixture.phase, asOf: rollDate(afterWeekIndex: weekIndex), ownerUserID: ownerUserID, performanceProfile: performanceProfile,
            availability: availability(), materializationContext: try materializationContext(), context: context
        )
    }

    /// Walks `fixture.instance` from wherever it currently is all the way
    /// to real tactical exhaustion, using only skips + the real
    /// `AdvanceTacticalWeekUseCase` — the cheap path shared by every test
    /// below that doesn't need fully-logged content.
    @discardableResult
    private func skipToExhaustion(_ fixture: Fixture) throws -> Int {
        var rolls = 0
        while !TacticalWeekCompletion.isInstanceExhausted(for: fixture.instance) {
            guard let weekIndex = TacticalWeekCompletion.currentMaterializedWeekIndex(for: fixture.instance) else { break }
            try skipEveryRealSession(in: fixture.instance, weekIndex: weekIndex)
            let outcome = try advanceOnce(fixture)
            guard outcome == .advanced else { break }
            rolls += 1
        }
        return rolls
    }

    // MARK: A/J — basic mechanism + idempotency

    func testM1Week1ToWeek2ViaRealAdvanceTacticalWeekUseCase() throws {
        let fixture = try makeCalibratedInstance(phaseType: .basicHypertrophy)
        try skipEveryRealSession(in: fixture.instance, weekIndex: 0)
        XCTAssertTrue(TacticalWeekCompletion.canAdvanceTacticalWeek(for: fixture.instance))

        let outcome = try advanceOnce(fixture)
        XCTAssertEqual(outcome, .advanced)
        XCTAssertEqual(ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: 1).count, 3, "Week 2 materialized once, 3 real sessions")
    }

    func testRepeatedImmediateAdvanceDoesNotAdvanceTwice() throws {
        let fixture = try makeCalibratedInstance(phaseType: .basicHypertrophy)
        try skipEveryRealSession(in: fixture.instance, weekIndex: 0)

        let first = try advanceOnce(fixture)
        XCTAssertEqual(first, .advanced)
        let week2SessionIDs = Set(ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: 1).map(\.id))
        XCTAssertEqual(week2SessionIDs.count, 3)

        // Immediately again, no intervening completion of Week 2.
        let second = try advanceOnce(fixture)
        XCTAssertEqual(second, .notEligible, "Week 2 is not yet terminal — must not advance to Week 3")
        XCTAssertTrue(ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: 2).isEmpty, "no Week 3 materialized")
        XCTAssertEqual(Set(ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: 1).map(\.id)), week2SessionIDs, "Week 2's own sessions are unchanged, no duplicates")
    }

    // MARK: bounds/final-week protection (M1/M2/M3, no Week 6/6/4)

    func testMesocycle1FinalDeloadTerminalNoWeekSix() throws {
        let fixture = try makeCalibratedInstance(phaseType: .basicHypertrophy)
        let rolls = try skipToExhaustion(fixture)
        XCTAssertEqual(rolls, 4, "4 rolls: week1->2->3->4->5(deload)")
        XCTAssertTrue(TacticalWeekCompletion.isInstanceExhausted(for: fixture.instance))
        XCTAssertFalse(TacticalWeekCompletion.canAdvanceTacticalWeek(for: fixture.instance))

        let outcome = try advanceOnce(fixture)
        XCTAssertEqual(outcome, .notEligible)
        XCTAssertTrue(ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: 5).isEmpty, "no Week 6")
    }

    func testMesocycle2FinalDeloadTerminalNoWeekSix() throws {
        let fixture = try makeCalibratedInstance(phaseType: .metaboliteFocus)
        let rolls = try skipToExhaustion(fixture)
        XCTAssertEqual(rolls, 4)
        XCTAssertTrue(TacticalWeekCompletion.isInstanceExhausted(for: fixture.instance))
        let outcome = try advanceOnce(fixture)
        XCTAssertEqual(outcome, .notEligible)
        XCTAssertTrue(ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: 5).isEmpty, "no Week 6")
    }

    /// Critical phase-length proof: M3 has only 3 weeks — rollForward
    /// must not be hardcoded to 5.
    func testMesocycle3FinalDeloadTerminalAtWeekThreeNoWeekFour() throws {
        let fixture = try makeCalibratedInstance(phaseType: .resensitization)
        let rolls = try skipToExhaustion(fixture)
        XCTAssertEqual(rolls, 2, "only 2 rolls: week1->2->3(deload) — proves rollForward is not hardcoded to a 5-week structure")
        XCTAssertTrue(TacticalWeekCompletion.isInstanceExhausted(for: fixture.instance))
        let outcome = try advanceOnce(fixture)
        XCTAssertEqual(outcome, .notEligible)
        XCTAssertTrue(ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: 3).isEmpty, "no Week 4")
    }

    // MARK: Source-progression regression — load/RIR/superset/deload preserved by the real trigger

    func testMesocycle1SourceLoadAndRIRPreservedAcrossRealAdvancement() throws {
        let fixture = try makeCalibratedInstance(phaseType: .basicHypertrophy, rmKilograms: 100)
        try skipEveryRealSession(in: fixture.instance, weekIndex: 0)
        try advanceOnce(fixture)
        let week2Push = try XCTUnwrap(ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: 1).first { $0.name == "Push Emphasis" })
        let horizontalPush = try XCTUnwrap(week2Push.orderedBlocks.flatMap(\.orderedPrescriptions).first { $0.exercise?.canonicalName == "Barbell Bench Press" })
        // Week-1 anchor = 100 * 0.85 = 85; Week-2 = 85 * 1.05 = 89.25 -> rounded to the 2.5kg increment.
        let expectedWeekOneAnchor = equipment.resolve(IdealLoad(kilograms: 100 * 0.85))
        XCTAssertEqual(horizontalPush.orderedSetPrescriptions.first?.targetWeight ?? -1, equipment.resolve(IdealLoad(kilograms: expectedWeekOneAnchor * 1.05)), accuracy: 0.01)
        XCTAssertEqual(horizontalPush.orderedSetPrescriptions.first?.targetRir, 3, "Week 2 RIR unchanged from the source schedule")
    }

    func testMesocycle2SupersetMechanicsAndCalibrationReuseAcrossRealAdvancement() throws {
        let fixture = try makeCalibratedInstance(phaseType: .metaboliteFocus, rmKilograms: 100)
        // M2's calibration was entered once at fixture creation — proves
        // Locked Decision (calibration) by never re-recording it below.
        try skipEveryRealSession(in: fixture.instance, weekIndex: 0)
        try advanceOnce(fixture)
        XCTAssertTrue(RequiredSourceCalibrationsUseCase.stillRequired(for: try XCTUnwrap(fixture.instance.programDefinition), instance: fixture.instance).isEmpty, "M2 calibration entered once at Week 1 remains valid — no re-prompt for Week 2")

        let week2Push = try XCTUnwrap(ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: 1).first { $0.name == "Push Emphasis" })
        let prescriptions = week2Push.orderedBlocks.flatMap(\.orderedPrescriptions)
        XCTAssertEqual(prescriptions.count, 9, "the real recovered Mesocycle 2 Day 1 (9 slots, including the superset partner), materialized via the real trigger")

        try skipEveryRealSession(in: fixture.instance, weekIndex: 1)
        try advanceOnce(fixture)
        try skipEveryRealSession(in: fixture.instance, weekIndex: 2)
        try advanceOnce(fixture)
        try skipEveryRealSession(in: fixture.instance, weekIndex: 3)
        try advanceOnce(fixture)
        // Deload (week 4): the superset partner is confirmed OMITTED — zero SetPrescriptions.
        let deloadPush = try XCTUnwrap(ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: 4).first { $0.name == "Push Emphasis" })
        let deloadPrescriptions = deloadPush.orderedBlocks.flatMap(\.orderedPrescriptions)
        let partnerPrescription = try XCTUnwrap(deloadPrescriptions.first { $0.sourcePrescriptionTemplate?.exerciseSlot?.name == "Incline Push or Front Delts" && $0.orderedSetPrescriptions.isEmpty })
        XCTAssertTrue(partnerPrescription.orderedSetPrescriptions.isEmpty, "the confirmed Mesocycle 2 superset-partner deload omission is preserved via the real trigger")
    }

    func testMesocycle3NoSupersetsAndShorterProgressionPreservedAcrossRealAdvancement() throws {
        let fixture = try makeCalibratedInstance(phaseType: .resensitization, rmKilograms: 100)
        let week1Push = try XCTUnwrap(ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: 0).first { $0.name == "Push Emphasis" })
        XCTAssertEqual(week1Push.orderedBlocks.flatMap(\.orderedPrescriptions).count, 7, "Mesocycle 3's real 7-slot Push day, no Chest Isolation or Triceps, no superset partner")

        try skipEveryRealSession(in: fixture.instance, weekIndex: 0)
        try advanceOnce(fixture)
        let week2Push = try XCTUnwrap(ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: 1).first { $0.name == "Push Emphasis" })
        let horizontalPush = try XCTUnwrap(week2Push.orderedBlocks.flatMap(\.orderedPrescriptions).first { $0.exercise?.canonicalName == "Barbell Bench Press" })
        let expectedWeekOneAnchor = equipment.resolve(IdealLoad(kilograms: 100 * 1.0))
        XCTAssertEqual(horizontalPush.orderedSetPrescriptions.first?.targetWeight ?? -1, equipment.resolve(IdealLoad(kilograms: expectedWeekOneAnchor * 1.05)), accuracy: 0.01)
        XCTAssertEqual(horizontalPush.orderedSetPrescriptions.first?.targetRir, 3)

        try skipEveryRealSession(in: fixture.instance, weekIndex: 1)
        try advanceOnce(fixture)
        // Week 3 is the deload — day-position weight split, same mechanism as M1/M2.
        let deloadPull = try XCTUnwrap(ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: 2).first { $0.name == "Pull Emphasis" })
        let deloadPush = try XCTUnwrap(ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: 2).first { $0.name == "Push Emphasis" })
        let deloadPushWeight = try XCTUnwrap(deloadPush.orderedBlocks.flatMap(\.orderedPrescriptions).first { $0.exercise?.canonicalName == "Barbell Bench Press" }?.orderedSetPrescriptions.first?.targetWeight)
        let deloadPullFirstWeight = deloadPull.orderedBlocks.flatMap(\.orderedPrescriptions).first?.orderedSetPrescriptions.first?.targetWeight
        XCTAssertEqual(deloadPushWeight, expectedWeekOneAnchor, accuracy: 0.01, "day 0 (Push) keeps full Week-1 weight during deload")
        XCTAssertEqual(deloadPullFirstWeight ?? -1, equipment.resolve(IdealLoad(kilograms: 100 * 1.0 * 0.5)), accuracy: 0.01, "day 2 (Pull) is halved during deload")
    }

    // MARK: real production integration — one fully-logged M1 walkthrough

    func testMesocycle1RealWalkthroughFullyLoggedThroughExhaustion() throws {
        let fixture = try makeCalibratedInstance(phaseType: .basicHypertrophy)
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)

        XCTAssertFalse(TacticalWeekCompletion.canAdvanceTacticalWeek(for: fixture.instance), "Week 1 not yet terminal")

        for weekIndex in 0..<4 {
            try completeEveryRealSessionFully(in: fixture.instance, weekIndex: weekIndex, rating: weekIndex % 2 == 0 ? 1 : -1, performanceProfile: performanceProfile)
            XCTAssertTrue(TacticalWeekCompletion.canAdvanceTacticalWeek(for: fixture.instance), "week \(weekIndex) fully logged and completed")
            let outcome = try advanceOnce(fixture, performanceProfile: performanceProfile)
            XCTAssertEqual(outcome, .advanced, "week \(weekIndex + 1) should materialize")
            XCTAssertEqual(ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: weekIndex + 1).count, 3)
        }

        // Week 5 (deload) is now materialized. Complete it too.
        XCTAssertEqual(ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: 4).count, 3, "deload week really materialized")
        try completeEveryRealSessionFully(in: fixture.instance, weekIndex: 4, rating: 0, performanceProfile: performanceProfile)

        XCTAssertTrue(TacticalWeekCompletion.isInstanceExhausted(for: fixture.instance))
        XCTAssertFalse(TacticalWeekCompletion.canAdvanceTacticalWeek(for: fixture.instance))
        let finalOutcome = try advanceOnce(fixture, performanceProfile: performanceProfile)
        XCTAssertEqual(finalOutcome, .notEligible)
        XCTAssertTrue(ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: 5).isEmpty, "no Week 6")

        // Real logged data survived every roll — nothing was lost.
        let week1Sessions = ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: 0)
        XCTAssertTrue(week1Sessions.allSatisfy { $0.status == .completed })
        XCTAssertFalse(week1Sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).flatMap(\.loggedSetResults).isEmpty, "Week 1's real logged SetResults are still there")
    }

    // MARK: substitution persists across weekly advancement

    func testSubstitutionMadeInWeekTwoPersistsIntoWeekThree() throws {
        let fixture = try makeCalibratedInstance(phaseType: .basicHypertrophy)
        let inclineDumbbellPress = try XCTUnwrap(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.canonicalName == "Incline Dumbbell Press" })).first)

        try skipEveryRealSession(in: fixture.instance, weekIndex: 0)
        try advanceOnce(fixture)

        let week2Push = try XCTUnwrap(fixture.instance.programDefinition?.orderedTemplateSessions.first { $0.name == "Push Emphasis" })
        let horizontalPushSlot = try XCTUnwrap(week2Push.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).first { $0.exerciseSlot?.name == "Horizontal Push" }?.exerciseSlot)
        try SubstituteExerciseUseCase.substituteGoingForward(instance: fixture.instance, slot: horizontalPushSlot, with: inclineDumbbellPress,  environment: TrainingEnvironmentTestSupport.full(context: context), context: context)

        try skipEveryRealSession(in: fixture.instance, weekIndex: 1)
        try advanceOnce(fixture)

        let week3Push = try XCTUnwrap(ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: 2).first { $0.name == "Push Emphasis" })
        let horizontalPushWeek3 = try XCTUnwrap(week3Push.orderedBlocks.flatMap(\.orderedPrescriptions).first { $0.sourceExerciseSlot?.id == horizontalPushSlot.id })
        XCTAssertEqual(horizontalPushWeek3.exercise?.canonicalName, "Incline Dumbbell Press", "the Week-2 substitution automatically applies to Week 3, no weekly copy needed")
    }

    // MARK: persistence / crash recovery

    /// A: terminal Week 1 saved -> reopen -> Start Next Week still
    /// eligible -> one roll.
    func testTerminalWeekPersistsAcrossRelaunchAndStillRollsExactlyOnce() throws {
        let fixture = try makeCalibratedInstance(phaseType: .basicHypertrophy)
        try skipEveryRealSession(in: fixture.instance, weekIndex: 0)
        try context.save()
        let planID = fixture.plan.id

        let reloadedContext = freshContext()
        let reloadedPlan = try XCTUnwrap(reloadedContext.fetch(FetchDescriptor<TrainingPlan>(predicate: #Predicate { $0.id == planID })).first)
        let reloadedPhase = try XCTUnwrap(reloadedPlan.orderedPhases.first)
        let reloadedInstance = try XCTUnwrap(reloadedPhase.primaryInstance)
        XCTAssertTrue(TacticalWeekCompletion.canAdvanceTacticalWeek(for: reloadedInstance), "terminal state survived relaunch")

        let outcome = try AdvanceTacticalWeekUseCase.advance(
            phase: reloadedPhase, asOf: rollDate(afterWeekIndex: 0), ownerUserID: ownerUserID, performanceProfile: nil,
            availability: availability(), materializationContext: try materializationContext(using: reloadedContext), context: reloadedContext
        )
        XCTAssertEqual(outcome, .advanced)
        XCTAssertEqual(ProgramWeekGrouping.realSessions(in: reloadedInstance, forWeek: 1).count, 3)
    }

    /// B: roll successfully to Week 2 -> reopen -> Start Next Week NOT
    /// eligible until Week 2 becomes terminal.
    func testRolledWeekNotEligibleAgainUntilItBecomesTerminalAfterRelaunch() throws {
        let fixture = try makeCalibratedInstance(phaseType: .basicHypertrophy)
        try skipEveryRealSession(in: fixture.instance, weekIndex: 0)
        try advanceOnce(fixture)
        try context.save()
        let planID = fixture.plan.id

        let reloadedContext = freshContext()
        let reloadedPlan = try XCTUnwrap(reloadedContext.fetch(FetchDescriptor<TrainingPlan>(predicate: #Predicate { $0.id == planID })).first)
        let reloadedPhase = try XCTUnwrap(reloadedPlan.orderedPhases.first)
        let reloadedInstance = try XCTUnwrap(reloadedPhase.primaryInstance)
        XCTAssertFalse(TacticalWeekCompletion.canAdvanceTacticalWeek(for: reloadedInstance), "Week 2 is freshly materialized, not terminal — must not be eligible")

        let prematureOutcome = try AdvanceTacticalWeekUseCase.advance(
            phase: reloadedPhase, asOf: rollDate(afterWeekIndex: 1), ownerUserID: ownerUserID, performanceProfile: nil,
            availability: availability(), materializationContext: try materializationContext(using: reloadedContext), context: reloadedContext
        )
        XCTAssertEqual(prematureOutcome, .notEligible)
    }

    // MARK: Mesocycle-transition gate fix (canStartNextHypertrophyMesocycle requires tactical exhaustion)

    func testCannotStartMesocycleTwoWhileMesocycleOneWeeksRemain() throws {
        let fixture = try makeCalibratedInstance(phaseType: .basicHypertrophy)
        try skipEveryRealSession(in: fixture.instance, weekIndex: 0) // Week 1 terminal, but source weeks remain
        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: fixture.phase, modelContext: context)
        XCTAssertFalse(viewModel.canStartNextHypertrophyMesocycle, "must not offer the next mesocycle while M1 tactical weeks remain")
    }

    func testCanStartMesocycleTwoOnceMesocycleOneFinalDeloadIsTerminal() throws {
        let fixture = try makeCalibratedInstance(phaseType: .basicHypertrophy)
        try skipToExhaustion(fixture)
        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: fixture.phase, modelContext: context)
        XCTAssertTrue(viewModel.canStartNextHypertrophyMesocycle, "M1 is tactically exhausted — the next mesocycle should now be offered")
        XCTAssertEqual(viewModel.nextHypertrophyMesocycleTypeLabel, "Metabolite Focus")
    }

    func testCannotStartMesocycleThreeWhileMesocycleTwoWeeksRemain() throws {
        let fixture = try makeCalibratedInstance(phaseType: .metaboliteFocus)
        try skipEveryRealSession(in: fixture.instance, weekIndex: 0)
        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: fixture.phase, modelContext: context)
        XCTAssertFalse(viewModel.canStartNextHypertrophyMesocycle)
    }

    func testCanStartMesocycleThreeOnceMesocycleTwoFinalDeloadIsTerminal() throws {
        let fixture = try makeCalibratedInstance(phaseType: .metaboliteFocus)
        try skipToExhaustion(fixture)
        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: fixture.phase, modelContext: context)
        XCTAssertTrue(viewModel.canStartNextHypertrophyMesocycle)
        XCTAssertEqual(viewModel.nextHypertrophyMesocycleTypeLabel, "Resensitization")
    }

    /// M3's final deload terminal -> no next source mesocycle exists in
    /// `HypertrophyProgramJourney.orderedPhaseTypes` — never auto-started.
    func testNoFurtherMesocycleOfferedOnceMesocycleThreeIsExhausted() throws {
        let fixture = try makeCalibratedInstance(phaseType: .resensitization)
        try skipToExhaustion(fixture)
        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: fixture.phase, modelContext: context)
        XCTAssertFalse(viewModel.canStartNextHypertrophyMesocycle, "Resensitization has no next phase in HypertrophyProgramJourney.orderedPhaseTypes")
        XCTAssertNil(viewModel.nextHypertrophyMesocycleTypeLabel)
    }

    /// Regression: the previously-existing M1->M2 real transition must
    /// still work end to end after the gate was tightened.
    func testUserInitiatedMesocycleTransitionStillWorksAfterGateTightening() throws {
        let fixture = try makeCalibratedInstance(phaseType: .basicHypertrophy)
        try skipToExhaustion(fixture)
        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: fixture.phase, modelContext: context)
        XCTAssertTrue(viewModel.canStartNextHypertrophyMesocycle)
        XCTAssertTrue(viewModel.startNextHypertrophyMesocycle(modelContext: context))
        XCTAssertEqual(fixture.plan.orderedPhases.count, 1, "Stage 10R.7A: a mesocycle succession never creates a new strategic phase")
        let nextDefinition = try XCTUnwrap(fixture.phase.primaryInstance?.programDefinition)
        XCTAssertEqual(nextDefinition.hypertrophyConfiguration?.phaseType, .metaboliteFocus)
    }

    /// `AdvanceTacticalWeekUseCase` itself must never start a new
    /// mesocycle, regardless of how many times it's called at exhaustion.
    func testAdvanceTacticalWeekNeverStartsTheNextMesocycleItself() throws {
        let fixture = try makeCalibratedInstance(phaseType: .basicHypertrophy)
        try skipToExhaustion(fixture)
        for _ in 0..<3 {
            _ = try advanceOnce(fixture)
        }
        XCTAssertEqual(fixture.plan.orderedPhases.count, 1, "still only the original Mesocycle 1 phase — no automatic transition")
    }

    // MARK: 10R.4C — mixed-modality integration

    func testMixedModalityGateWithholdsUntilEveryComponentTerminalThenRollsCoherently() throws {
        let fixture = try makeCalibratedInstance(phaseType: .basicHypertrophy)

        // A second, real Hypertrophy-configured component simulating a
        // second concurrent modality's own ProgramInstance (data-isolated
        // from the first, same as any two real components would be).
        let secondDefinition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 3, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: context
        )
        let secondInstance = ProgramInstance(ownerUserID: ownerUserID, startDate: startDate, status: .active, priority: .secondary)
        context.insert(secondInstance)
        secondInstance.programDefinition = secondDefinition
        fixture.phase.addProgramInstance(secondInstance)
        let secondComponent = TrainingMixComponent(label: "Second Component", programmingSystem: .hypertrophy, priority: .secondary, frequency: SessionFrequency(target: 3))
        context.insert(secondComponent)
        fixture.mix.addComponent(secondComponent)
        secondComponent.programInstance = secondInstance
        try ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: secondDefinition, candidateExercises: try context.fetch(FetchDescriptor<Exercise>()), environment: TrainingEnvironmentTestSupport.full(context: context))
        // Materialize the second component's own Week 1 directly (mirrors
        // what a real second calibration-gated component would end up
        // with) — no calibration entities needed since `.rmBased` weight
        // resolution failure doesn't block Session creation.
        _ = StrengthMaterializer.materializeWeek(
            definition: secondDefinition, instance: secondInstance, weekIndex: 0, isDeload: false,
            startDate: startDate, ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )

        // First component terminal, second still scheduled -> withheld.
        try skipEveryRealSession(in: fixture.instance, weekIndex: 0)
        XCTAssertFalse(TacticalWeekCompletion.canAdvanceTacticalWeek(for: fixture.mix), "second component not yet terminal")
        let withheldOutcome = try advanceOnce(fixture)
        XCTAssertEqual(withheldOutcome, .notEligible)
        XCTAssertTrue(ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: 1).isEmpty, "first component must not roll ahead of the mix gate either")

        // Now both terminal -> one call rolls both coherently.
        try skipEveryRealSession(in: secondInstance, weekIndex: 0)
        XCTAssertTrue(TacticalWeekCompletion.canAdvanceTacticalWeek(for: fixture.mix))
        let bothOutcome = try advanceOnce(fixture)
        XCTAssertEqual(bothOutcome, .advanced)
        XCTAssertEqual(ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: 1).count, 3, "first component rolled")
        XCTAssertEqual(ProgramWeekGrouping.realSessions(in: secondInstance, forWeek: 1).count, 3, "second component rolled together in the same call")

        // Repeated call does not advance twice.
        let repeated = try advanceOnce(fixture)
        XCTAssertEqual(repeated, .notEligible)
        XCTAssertTrue(ProgramWeekGrouping.realSessions(in: fixture.instance, forWeek: 2).isEmpty)
        XCTAssertTrue(ProgramWeekGrouping.realSessions(in: secondInstance, forWeek: 2).isEmpty)
    }

    // MARK: PhaseDetailViewModel wiring — the closest honest substitute for tapping "Start Week N+1"

    /// This sandbox has no UI-tap automation (confirmed repeatedly across
    /// this project) — this test drives the exact `PhaseDetailViewModel`
    /// state the real "Start Week N+1" button
    /// (`PhaseDetailView.advanceTacticalWeekCard`) reads, proving the
    /// ViewModel's own gating/labeling is correctly wired to
    /// `TacticalWeekCompletion` (not just `AdvanceTacticalWeekUseCase`
    /// itself, already proven directly above).
    ///
    /// **Disclosed scope limitation, not silently worked around:**
    /// `PhaseDetailViewModel.advanceTacticalWeek` hardcodes `asOf: Date()`
    /// internally (correct production behavior — mirrors
    /// `startNextHypertrophyPhase`'s identical precedent). In real
    /// production, real wall-clock days elapse between a phase starting
    /// and a user later tapping "Start Week 2," so `Date()` at that later
    /// moment naturally lands in a fresh scheduling window. A fast
    /// synchronous unit test cannot reproduce that elapsed time (no clock
    /// is injectable into this ViewModel method, and none should be added
    /// for this stage), so this test does not call `advanceTacticalWeek`
    /// itself — the identical underlying `rollForward` mechanism is
    /// already proven directly, with an explicitly-advanced `asOf`, by
    /// every other test in this file (which is the actual proof of
    /// correctness; this test's job is only the ViewModel-layer wiring).
    func testPhaseDetailViewModelOffersTheRealTacticalWeekAdvance() throws {
        let fixture = try makeCalibratedInstance(phaseType: .basicHypertrophy)
        let viewModel = PhaseDetailViewModel()
        viewModel.load(phase: fixture.phase, modelContext: context)
        XCTAssertFalse(viewModel.canAdvanceTacticalWeek, "Week 1 not yet terminal")
        XCTAssertNil(viewModel.nextTacticalWeekNumber)

        try skipEveryRealSession(in: fixture.instance, weekIndex: 0)
        viewModel.load(phase: fixture.phase, modelContext: context)
        XCTAssertTrue(viewModel.canAdvanceTacticalWeek, "Week 1 is now terminal and Mesocycle 1 has a next source-defined week")
        XCTAssertEqual(viewModel.nextTacticalWeekNumber, 2)
    }

    // MARK: LongTermPlanner boundary — never invoked by tactical advancement

    func testAdvancingDoesNotChangeThePlanOrPhaseCount() throws {
        let fixture = try makeCalibratedInstance(phaseType: .basicHypertrophy)
        let planID = fixture.plan.id
        try skipEveryRealSession(in: fixture.instance, weekIndex: 0)
        try advanceOnce(fixture)
        XCTAssertEqual(fixture.plan.id, planID)
        XCTAssertEqual(fixture.plan.orderedPhases.count, 1, "weekly advancement never regenerates the strategic plan or adds a phase")
    }
}
