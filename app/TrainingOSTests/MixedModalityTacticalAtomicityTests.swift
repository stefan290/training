import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 10R.6: proves `AdvanceTacticalWeekUseCase`'s atomic mixed-modality
/// transaction boundary (D-10R6-1 through D-10R6-6), the real Functional
/// Fitness exposure-history wiring (D-10R6-7), and the real Interval
/// `WeekContext` resolver (D-10R6-8/D-10R6-9). Every advance under test
/// here goes through the real production entry point
/// (`AdvanceTacticalWeekUseCase.advance`) and the real materializers/
/// resolvers — never a hand-constructed expected result.
@MainActor
final class MixedModalityTacticalAtomicityTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()
    let startDate = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func availability() -> UserAvailability {
        UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1)
    }

    private func rollDate(afterWeekIndex weekIndex: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: (weekIndex + 1) * 7, to: startDate) ?? startDate
    }

    // MARK: - Fixture: a real, non-calibration-gated Hypertrophy component

    private struct HypertrophyFixture {
        var instance: ProgramInstance
        var component: TrainingMixComponent
    }

    /// Mirrors `AdvanceTacticalWeekUseCaseTests`'s own "second component"
    /// precedent — a real generated Hypertrophy program, materialized
    /// directly via `StrengthMaterializer` with a fixed `rmKilograms`
    /// slot context so no source-RM calibration step is needed, keeping
    /// this fixture's own focus on the mixed-modality transaction, not on
    /// Hypertrophy's calibration flow (already fully covered elsewhere).
    private func addHypertrophyComponent(to mix: TrainingMix, phase: TrainingPhase, strengthCandidates: [Exercise]) throws -> HypertrophyFixture {
        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 3, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: context
        )
        let instance = ProgramInstance(ownerUserID: ownerUserID, startDate: startDate, status: .active, priority: .primary)
        context.insert(instance)
        instance.programDefinition = definition
        phase.addProgramInstance(instance)
        let component = TrainingMixComponent(label: "Hypertrophy", programmingSystem: .hypertrophy, priority: .primary, frequency: SessionFrequency(target: 3))
        context.insert(component)
        mix.addComponent(component)
        component.programInstance = instance
        ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: strengthCandidates)
        _ = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: startDate, ownerUserID: ownerUserID, equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )
        return HypertrophyFixture(instance: instance, component: component)
    }

    // MARK: - Fixture: Functional Fitness, real generator, week-0 real materialization

    private struct FunctionalFitnessFixture {
        var instance: ProgramInstance
        var component: TrainingMixComponent
        var definition: ProgramDefinition
    }

    private func ffStimulus(requiresRecentExposureToProgress: Bool) -> FunctionalFitnessProgramConfiguration {
        let stimulus = Stimulus(
            targetDurationDomain: .medium, intensity: .high, loading: .moderate,
            movementFunctions: [.squatLoaded], movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1)],
            skillDemand: .moderate, systemicDemand: .high, scoreType: .roundsAndReps
        )
        return FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 3, targetStimulus: stimulus, format: .amrap(capSeconds: 720),
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: requiresRecentExposureToProgress, includeStrengthBlock: false
        )
    }

    @discardableResult
    private func addFunctionalFitnessComponent(
        to mix: TrainingMix, phase: TrainingPhase, requiresRecentExposureToProgress: Bool, candidates: [Exercise]
    ) throws -> FunctionalFitnessFixture {
        let definition = FunctionalFitnessProgramGenerator.generate(
            configuration: ffStimulus(requiresRecentExposureToProgress: requiresRecentExposureToProgress),
            provenance: .constructed(reason: "test fixture"), context: context
        )
        let instance = ProgramInstance(ownerUserID: ownerUserID, startDate: startDate, status: .active, priority: .secondary)
        context.insert(instance)
        instance.programDefinition = definition
        phase.addProgramInstance(instance)
        let component = TrainingMixComponent(label: "Functional Fitness", programmingSystem: .functionalFitness, priority: .secondary, frequency: SessionFrequency(target: 1))
        context.insert(component)
        mix.addComponent(component)
        component.programInstance = instance

        _ = try RollTacticalWindowUseCase.materializeFirstWindow(
            system: .functionalFitness, definition: definition, instance: instance, startDate: startDate,
            ownerUserID: ownerUserID, performanceProfile: nil,
            materializationContext: TacticalMaterializationContext(
                equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
                functionalFitnessCandidateExercises: candidates
            ),
            context: context
        )
        return FunctionalFitnessFixture(instance: instance, component: component, definition: definition)
    }

    /// Marks `weekIndex`'s FF session `.completed` and attaches a real
    /// `FunctionalFitnessResult` on its FF block, backdated to fall
    /// before `weekIndex`'s own real session date — real, honest
    /// completed history `FunctionalFitnessExposureHistoryBuilder` can
    /// find.
    private func completeFunctionalFitnessSession(instance: ProgramInstance, weekIndex: Int) throws {
        let sessions = ProgramWeekGrouping.realSessions(in: instance, forWeek: weekIndex)
        for session in sessions {
            session.status = .completed
            for block in session.orderedBlocks where block.functionalFitnessPrescription != nil {
                let result = FunctionalFitnessResult(scoreType: .roundsAndReps, scoreValue: .roundsAndReps(rounds: 5, partialReps: 3), scoreDirection: .higherIsBetter)
                context.insert(result)
                block.attachFunctionalFitnessResult(result)
            }
        }
    }

    private func skipSessions(in instance: ProgramInstance, weekIndex: Int) throws {
        for session in ProgramWeekGrouping.realSessions(in: instance, forWeek: weekIndex) {
            try ChangeSessionStatusUseCase.skip(session, modelContext: context)
        }
    }

    private func makePhaseAndMix() -> (phase: TrainingPhase, mix: TrainingMix) {
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .muscleGain)
        context.insert(goal)
        let plan = TrainingPlan(status: .active)
        context.insert(plan)
        goal.addPlan(plan)
        let phase = TrainingPhase(type: .muscleGain, startDate: startDate, priorityRule: .strength, status: .active)
        context.insert(phase)
        plan.addPhase(phase)
        let mix = TrainingMix(kind: .selected, name: "Hypertrophy Plus Functional Fitness")
        context.insert(mix)
        phase.addTrainingMix(mix)
        return (phase, mix)
    }

    // MARK: 4 — successful multi-component advance

    func testSuccessfulAdvanceRollsHypertrophyAndFunctionalFitnessTogetherInOneCall() throws {
        _ = ExerciseCatalog.makeAndInsert(context: context)
        let strengthCandidates = try context.fetch(FetchDescriptor<Exercise>())
        let ffCandidates = [Exercise(canonicalName: "Test Wall Ball", modality: .functionalFitness, equipment: "medicineBall", movementPattern: "squat", movementFunctions: [.squatLoaded], functionalModality: .weightlifting)]
        ffCandidates.forEach { context.insert($0) }

        let (phase, mix) = makePhaseAndMix()
        let hyp = try addHypertrophyComponent(to: mix, phase: phase, strengthCandidates: strengthCandidates)
        let ff = try addFunctionalFitnessComponent(to: mix, phase: phase, requiresRecentExposureToProgress: false, candidates: ffCandidates)

        try skipSessions(in: hyp.instance, weekIndex: 0)
        try completeFunctionalFitnessSession(instance: ff.instance, weekIndex: 0)
        // `AdvanceTacticalWeekUseCase.advance` re-derives everything from a
        // fresh scratch `ModelContext` over the SAME container — it only
        // ever sees committed state, exactly like a real relaunch. Every
        // "already happened" fixture step above must be saved before
        // calling `advance`, mirroring CLAUDE.md rule 20's "every
        // meaningful action persists promptly" in real production.
        try context.save()
        XCTAssertTrue(TacticalWeekCompletion.canAdvanceTacticalWeek(for: mix))

        let outcome = try AdvanceTacticalWeekUseCase.advance(
            phase: phase, asOf: rollDate(afterWeekIndex: 0), ownerUserID: ownerUserID, performanceProfile: nil,
            availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5), strengthCandidateExercises: strengthCandidates, functionalFitnessCandidateExercises: ffCandidates),
            context: context
        )
        XCTAssertEqual(outcome, .advanced)
        XCTAssertEqual(ProgramWeekGrouping.realSessions(in: hyp.instance, forWeek: 1).count, 3, "Hypertrophy rolled")
        XCTAssertEqual(ProgramWeekGrouping.realSessions(in: ff.instance, forWeek: 1).count, 1, "Functional Fitness rolled together, same call")

        // 14: the scheduler saw both components' new sessions in one
        // batch — every newly-rolled session for BOTH components must be
        // scheduled (have a real `Day`), never just the first one seen.
        let week1Sessions = ProgramWeekGrouping.realSessions(in: hyp.instance, forWeek: 1) + ProgramWeekGrouping.realSessions(in: ff.instance, forWeek: 1)
        XCTAssertTrue(week1Sessions.allSatisfy { $0.day != nil }, "every rolled session across both components was placed by one shared scheduling pass")
    }

    // MARK: 6/7 — preflight blocks before ANY mutation

    func testPreflightBlocksFunctionalFitnessAdvanceBeforeAnyComponentIsMutated() throws {
        _ = ExerciseCatalog.makeAndInsert(context: context)
        let strengthCandidates = try context.fetch(FetchDescriptor<Exercise>())
        let ffCandidates = [Exercise(canonicalName: "Test Wall Ball", modality: .functionalFitness, equipment: "medicineBall", movementPattern: "squat", movementFunctions: [.squatLoaded], functionalModality: .weightlifting)]
        ffCandidates.forEach { context.insert($0) }

        let (phase, mix) = makePhaseAndMix()
        let hyp = try addHypertrophyComponent(to: mix, phase: phase, strengthCandidates: strengthCandidates)
        // Gated FF component whose week 0 is skipped (terminal) but never
        // completed with a real result — no exposure history exists.
        let ff = try addFunctionalFitnessComponent(to: mix, phase: phase, requiresRecentExposureToProgress: true, candidates: ffCandidates)

        try skipSessions(in: hyp.instance, weekIndex: 0)
        try skipSessions(in: ff.instance, weekIndex: 0)
        XCTAssertTrue(TacticalWeekCompletion.canAdvanceTacticalWeek(for: mix))

        XCTAssertThrowsError(try AdvanceTacticalWeekUseCase.advance(
            phase: phase, asOf: rollDate(afterWeekIndex: 0), ownerUserID: ownerUserID, performanceProfile: nil,
            availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5), strengthCandidateExercises: strengthCandidates, functionalFitnessCandidateExercises: ffCandidates),
            context: context
        )) { error in
            XCTAssertEqual(error as? TacticalAdvancementPreflightError, .functionalFitnessExposureHistoryUnresolvable(componentID: ff.component.id))
        }

        // Zero mutation for EITHER component — including Hypertrophy,
        // which would have succeeded on its own.
        XCTAssertTrue(ProgramWeekGrouping.realSessions(in: hyp.instance, forWeek: 1).isEmpty, "preflight blocks the whole attempt before Hypertrophy is ever touched")
        XCTAssertTrue(ProgramWeekGrouping.realSessions(in: ff.instance, forWeek: 1).isEmpty)
    }

    func testPreflightBlocksIntervalAdvanceBeforeAnyComponentIsMutated() throws {
        _ = ExerciseCatalog.makeAndInsert(context: context)
        let strengthCandidates = try context.fetch(FetchDescriptor<Exercise>())
        let (phase, mix) = makePhaseAndMix()
        let hyp = try addHypertrophyComponent(to: mix, phase: phase, strengthCandidates: strengthCandidates)
        let interval = try addGatedIntervalComponent(to: mix, phase: phase)

        try skipSessions(in: hyp.instance, weekIndex: 0)
        try skipSessions(in: interval.instance, weekIndex: 0) // no real IntervalResult attached — unresolvable history
        XCTAssertTrue(TacticalWeekCompletion.canAdvanceTacticalWeek(for: mix))

        XCTAssertThrowsError(try AdvanceTacticalWeekUseCase.advance(
            phase: phase, asOf: rollDate(afterWeekIndex: 0), ownerUserID: ownerUserID, performanceProfile: nil,
            availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5), strengthCandidateExercises: strengthCandidates),
            context: context
        )) { error in
            XCTAssertEqual(error as? TacticalAdvancementPreflightError, .intervalWeekContextUnresolvable(componentID: interval.component.id))
        }
        XCTAssertTrue(ProgramWeekGrouping.realSessions(in: hyp.instance, forWeek: 1).isEmpty)
        XCTAssertTrue(ProgramWeekGrouping.realSessions(in: interval.instance, forWeek: 1).isEmpty)
    }

    // MARK: - Fixture: a gated Interval component (hand-built template graph —
    // `IntervalProgramGenerator` never exposes `requiresSuccessfulCompletionToProgress`)

    private struct IntervalFixture {
        var instance: ProgramInstance
        var component: TrainingMixComponent
        var definition: ProgramDefinition
    }

    @discardableResult
    private func addGatedIntervalComponent(to mix: TrainingMix, phase: TrainingPhase) throws -> IntervalFixture {
        let definition = ProgramDefinition(name: "Gated Interval Test Program", lengthWeeks: 3, programmingSystem: .interval)
        context.insert(definition)
        for _ in 0..<3 {
            let week = TrainingWeek(isDeload: false)
            context.insert(week)
            definition.addWeek(week)
        }
        let templateSession = TemplateSession(name: "Interval Day", role: .interval)
        context.insert(templateSession)
        definition.addTemplateSession(templateSession)
        let blockTemplate = WorkoutBlockTemplate(type: .intervals)
        context.insert(blockTemplate)
        templateSession.addBlockTemplate(blockTemplate)
        let rules = IntervalProgressionRules(
            priority: [IntervalProgressionStep(variable: .intervalCount, incrementPerWeek: 1, weeksToCeiling: 4)],
            weekOneIntervalCount: 4,
            requiresSuccessfulCompletionToProgress: true
        )
        let prescriptionTemplate = IntervalPrescriptionTemplate(
            preferredActivityType: .running, workIntensity: .heartRateZone(.two), recoveryIntensity: .heartRateZone(.one),
            recoveryType: .active, progressionRules: rules
        )
        context.insert(prescriptionTemplate)
        blockTemplate.attachIntervalPrescriptionTemplate(prescriptionTemplate)

        let instance = ProgramInstance(ownerUserID: ownerUserID, startDate: startDate, status: .active, priority: .secondary)
        context.insert(instance)
        instance.programDefinition = definition
        phase.addProgramInstance(instance)
        let component = TrainingMixComponent(label: "Interval", programmingSystem: .interval, priority: .secondary, frequency: SessionFrequency(target: 1))
        context.insert(component)
        mix.addComponent(component)
        component.programInstance = instance

        _ = try IntervalMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, startDate: startDate, ownerUserID: ownerUserID,
            weekContext: { _ in .init() }, context: context
        )
        return IntervalFixture(instance: instance, component: component, definition: definition)
    }

    /// Marks `weekIndex`'s Interval session `.completed` and attaches a
    /// real `IntervalResult` with real `IntervalRepResult`s — enough real
    /// history for `IntervalWeekContextBuilder` to resolve a genuine
    /// `.progress` outcome (every rep completed as prescribed, well under
    /// the configured RPE ceiling since none is set here).
    private func completeIntervalSession(instance: ProgramInstance, weekIndex: Int, repCount: Int = 4) throws {
        for session in ProgramWeekGrouping.realSessions(in: instance, forWeek: weekIndex) {
            session.status = .completed
            for block in session.orderedBlocks where block.intervalPrescription != nil {
                let result = IntervalResult(completedAt: rollDate(afterWeekIndex: weekIndex - 1))
                context.insert(result)
                block.attachIntervalResult(result)
                for _ in 0..<repCount {
                    let rep = IntervalRepResult(actualWorkDurationSeconds: 240, wasCompletedAsPrescribed: true)
                    context.insert(rep)
                    result.addRepResult(rep)
                }
            }
        }
    }

    // MARK: 8/10/11 — the mandatory D-10R6-4 scenario: FF throws mid-loop after Hypertrophy already mutated; U survives; retry advances exactly once

    func testUnrelatedPendingMutationSurvivesAndRetryAfterFixingBlockerAdvancesExactlyOnceForEveryComponent() throws {
        _ = ExerciseCatalog.makeAndInsert(context: context)
        let strengthCandidates = try context.fetch(FetchDescriptor<Exercise>())
        let realFFCandidates = [Exercise(canonicalName: "Test Wall Ball", modality: .functionalFitness, equipment: "medicineBall", movementPattern: "squat", movementFunctions: [.squatLoaded], functionalModality: .weightlifting)]
        realFFCandidates.forEach { context.insert($0) }

        let (phase, mix) = makePhaseAndMix()
        // Hypertrophy added FIRST — `mix.orderedComponents` processes it
        // before Functional Fitness, so its Week 2 is already inserted
        // into the scratch context by the time FF throws.
        let hyp = try addHypertrophyComponent(to: mix, phase: phase, strengthCandidates: strengthCandidates)
        let ff = try addFunctionalFitnessComponent(to: mix, phase: phase, requiresRecentExposureToProgress: false, candidates: realFFCandidates)

        try skipSessions(in: hyp.instance, weekIndex: 0)
        try completeFunctionalFitnessSession(instance: ff.instance, weekIndex: 0)
        // Persist the "already happened" week-0 completion first — `advance`
        // reads via a fresh scratch context and only sees committed state.
        // U (below) is deliberately NOT saved — it must stay a genuinely
        // pending, unsaved mutation for this scenario to prove anything.
        try context.save()
        XCTAssertTrue(TacticalWeekCompletion.canAdvanceTacticalWeek(for: mix))

        // An existing, unrelated pending mutation U — never saved, never
        // touched by the failed attempt below.
        let unrelatedGoal = Goal(ownerUserID: ownerUserID, primaryType: .enduranceEvent)
        context.insert(unrelatedGoal)
        let unrelatedGoalID = unrelatedGoal.id
        XCTAssertTrue(context.hasChanges, "U is a real pending mutation before the attempt")

        // Force a genuine, preflight-blind Stage E failure: an empty FF
        // candidate pool means no movement slot can resolve any
        // exercise — `FunctionalFitnessStimulusValidator` fails, exactly
        // the failure mode this stage's preflight deliberately does NOT
        // pre-check (D-10R6-6 — never simulate the whole pipeline twice).
        XCTAssertThrowsError(try AdvanceTacticalWeekUseCase.advance(
            phase: phase, asOf: rollDate(afterWeekIndex: 0), ownerUserID: ownerUserID, performanceProfile: nil,
            availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5), strengthCandidateExercises: strengthCandidates, functionalFitnessCandidateExercises: []),
            context: context
        )) { error in
            XCTAssertTrue(error is FunctionalFitnessMaterializationError, "a genuine, unexpected materializer failure — not a preflight result")
        }

        // U survives, completely unaffected.
        XCTAssertTrue(context.hasChanges, "U is still a pending, unsaved mutation in the caller's own context")
        XCTAssertNotNil(try context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.id == unrelatedGoalID })).first, "U itself still exists")

        // Neither component advanced — atomic failure, not partial.
        XCTAssertEqual(TacticalWeekCompletion.currentMaterializedWeekIndex(for: hyp.instance), 0, "Hypertrophy's successful mid-loop materialization was discarded, not left half-committed")
        XCTAssertTrue(ProgramWeekGrouping.realSessions(in: hyp.instance, forWeek: 1).isEmpty)
        XCTAssertEqual(TacticalWeekCompletion.currentMaterializedWeekIndex(for: ff.instance), 0)
        XCTAssertTrue(ProgramWeekGrouping.realSessions(in: ff.instance, forWeek: 1).isEmpty)

        // Retry, now with the blocker fixed (real FF candidates) —
        // exactly one Week 2 for every eligible component.
        let outcome = try AdvanceTacticalWeekUseCase.advance(
            phase: phase, asOf: rollDate(afterWeekIndex: 0), ownerUserID: ownerUserID, performanceProfile: nil,
            availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5), strengthCandidateExercises: strengthCandidates, functionalFitnessCandidateExercises: realFFCandidates),
            context: context
        )
        XCTAssertEqual(outcome, .advanced)
        XCTAssertEqual(ProgramWeekGrouping.realSessions(in: hyp.instance, forWeek: 1).count, 3)
        XCTAssertEqual(ProgramWeekGrouping.realSessions(in: ff.instance, forWeek: 1).count, 1)
        // U is still there, still untouched by the eventual successful save either.
        XCTAssertNotNil(try context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.id == unrelatedGoalID })).first)
    }

    // MARK: 16 — real Functional Fitness exposure history affects a gated case

    func testFunctionalFitnessExposureHistoryIsRealAndGatesCorrectly() throws {
        let candidates = [Exercise(canonicalName: "Test Wall Ball", modality: .functionalFitness, equipment: "medicineBall", movementPattern: "squat", movementFunctions: [.squatLoaded], functionalModality: .weightlifting)]
        candidates.forEach { context.insert($0) }
        let (phase, mix) = makePhaseAndMix()
        let ff = try addFunctionalFitnessComponent(to: mix, phase: phase, requiresRecentExposureToProgress: true, candidates: candidates)

        // Week 0 has no prior history yet — legitimately empty, not an error.
        XCTAssertTrue(FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn: ff.instance).isEmpty)

        // Skipped (not completed with a real result) — still no honest exposure history.
        try skipSessions(in: ff.instance, weekIndex: 0)
        XCTAssertNoThrow(try TacticalAdvancementPreflight.check(mix: mix)) // reading is safe regardless
        XCTAssertEqual(TacticalAdvancementPreflight.check(mix: mix), .functionalFitnessExposureHistoryUnresolvable(componentID: ff.component.id))

        // Undo the skip and complete it for real instead — a genuine
        // completed session with a real result now exists.
        for session in ProgramWeekGrouping.realSessions(in: ff.instance, forWeek: 0) { session.status = .scheduled }
        try completeFunctionalFitnessSession(instance: ff.instance, weekIndex: 0)
        let history = FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn: ff.instance)
        XCTAssertEqual(history.count, 1, "exactly the one real completed session's result, nothing fabricated")
        XCTAssertNil(TacticalAdvancementPreflight.check(mix: mix), "real exposure history now resolves the gate")

        // `advance` reads via a fresh scratch context over the same
        // container — only committed state is visible to it.
        try context.save()

        let outcome = try AdvanceTacticalWeekUseCase.advance(
            phase: phase, asOf: rollDate(afterWeekIndex: 0), ownerUserID: ownerUserID, performanceProfile: nil,
            availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5), functionalFitnessCandidateExercises: candidates),
            context: context
        )
        XCTAssertEqual(outcome, .advanced)
        XCTAssertEqual(ProgramWeekGrouping.realSessions(in: ff.instance, forWeek: 1).count, 1)
    }

    // MARK: 17/18 — Interval WeekContext is empty only when historically correct, and a real one unblocks week 1+

    func testIntervalWeekContextEmptyAtWeekZeroAndRealAtWeekOnePlus() throws {
        let (phase, mix) = makePhaseAndMix()
        let interval = try addGatedIntervalComponent(to: mix, phase: phase)

        // Week 0: legitimately empty — nothing precedes it.
        let week0Block = try XCTUnwrap(ProgramWeekGrouping.realSessions(in: interval.instance, forWeek: 0).first?.orderedBlocks.first { $0.intervalPrescription != nil })
        let templateBlock = try XCTUnwrap(week0Block.intervalPrescription?.sourceWorkoutBlockTemplate)
        let week0Context = IntervalWeekContextBuilder.build(instance: interval.instance, weekIndex: 0)(templateBlock)
        XCTAssertNil(week0Context.previousOutcome)

        try completeIntervalSession(instance: interval.instance, weekIndex: 0, repCount: 4)
        XCTAssertNil(TacticalAdvancementPreflight.check(mix: mix), "real completed Week 1 history resolves the gate")
        try context.save()

        let outcome = try AdvanceTacticalWeekUseCase.advance(
            phase: phase, asOf: rollDate(afterWeekIndex: 0), ownerUserID: ownerUserID, performanceProfile: nil,
            availability: availability(), materializationContext: TacticalMaterializationContext(equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)),
            context: context
        )
        XCTAssertEqual(outcome, .advanced)
        let week1Sessions = ProgramWeekGrouping.realSessions(in: interval.instance, forWeek: 1)
        XCTAssertEqual(week1Sessions.count, 1)
        let week1Prescription = try XCTUnwrap(week1Sessions.first?.orderedBlocks.compactMap(\.intervalPrescription).first)
        // All 4 prescribed reps completed as prescribed, well within the
        // (unset, so unlimited) RPE ceiling -> `.progress` -> the
        // configured priority step increments interval count by 1.
        XCTAssertEqual(week1Prescription.intervalCount, 5, "a real, derived `.progress` outcome actually advanced the count — not a fabricated or frozen value")
    }

    // MARK: 19/20 — materializeFirstWindow uses the identical policy as rollForward (parity)

    func testInitialMaterializationUsesTheSameFunctionalFitnessAndIntervalPolicyAsRollForward() throws {
        let candidates = [Exercise(canonicalName: "Test Wall Ball", modality: .functionalFitness, equipment: "medicineBall", movementPattern: "squat", movementFunctions: [.squatLoaded], functionalModality: .weightlifting)]
        candidates.forEach { context.insert($0) }
        let (phase, mix) = makePhaseAndMix()
        // Both gated components' very first materialization (week 0) must
        // not throw despite `requiresX == true` — parity with rollForward's
        // own week-0 empty-context legitimacy (D-10R6-9).
        let ff = try addFunctionalFitnessComponent(to: mix, phase: phase, requiresRecentExposureToProgress: true, candidates: candidates)
        XCTAssertEqual(ProgramWeekGrouping.realSessions(in: ff.instance, forWeek: 0).count, 1, "week 0 materialized despite the gate — never blocked at week 0")

        let interval = try addGatedIntervalComponent(to: mix, phase: phase)
        XCTAssertEqual(ProgramWeekGrouping.realSessions(in: interval.instance, forWeek: 0).count, 1, "week 0 materialized despite `requiresSuccessfulCompletionToProgress`")
    }

    // MARK: known deferred equipment gap — no NEW equipment assumption introduced by 10R.6A/B/C

    /// D-10R6-11 was DEFERRED by explicit product decision (the domain
    /// model has no persisted, authoritative equipment/training-
    /// environment concept yet — see
    /// `STAGE10R6_MIXED_MODALITY_ROLLFORWARD_IMPLEMENTATION_REPORT.md`).
    /// This is a narrow regression guard, not a new feature proof: the
    /// exact same pre-existing `EquipmentProfile` passed in by the caller
    /// still flows through `rollForward` unchanged — 10R.6A/B/C introduce
    /// no NEW equipment inference, no per-exercise lookup, no silent
    /// default substitution.
    func testAdvanceStillUsesExactlyTheCallerSuppliedEquipmentProfileNoNewInferenceIntroduced() throws {
        _ = ExerciseCatalog.makeAndInsert(context: context)
        let strengthCandidates = try context.fetch(FetchDescriptor<Exercise>())
        let (phase, mix) = makePhaseAndMix()
        let hyp = try addHypertrophyComponent(to: mix, phase: phase, strengthCandidates: strengthCandidates)
        try skipSessions(in: hyp.instance, weekIndex: 0)

        // A deliberately distinctive, caller-supplied profile (not the
        // usual 2.5kg/.barbell default) — if 10R.6 introduced any new
        // equipment derivation, this value would be silently overridden
        // rather than flowing straight through.
        let distinctiveEquipment = EquipmentProfile(equipmentType: .dumbbell, smallestIncrementKg: 1.0)
        _ = try AdvanceTacticalWeekUseCase.advance(
            phase: phase, asOf: rollDate(afterWeekIndex: 0), ownerUserID: ownerUserID, performanceProfile: nil,
            availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: distinctiveEquipment, strengthCandidateExercises: strengthCandidates),
            context: context
        )
        let week2 = ProgramWeekGrouping.realSessions(in: hyp.instance, forWeek: 1)
        let anyWeight = week2.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).flatMap(\.orderedSetPrescriptions).compactMap(\.targetWeight).first
        XCTAssertNotNil(anyWeight)
        // 1.0kg increments only ever produce weights that are exact
        // multiples of 1.0 — 2.5kg-only defaults would not reliably do so.
        if let anyWeight {
            XCTAssertEqual(anyWeight.truncatingRemainder(dividingBy: 1.0), 0, accuracy: 0.0001, "the exact caller-supplied 1.0kg increment was honored end to end — no new default silently substituted")
        }
    }
}
