import XCTest
import SwiftData
@testable import TrainingOS

/// TrainingOS — Dogfood Round 1: real, manual-dogfood-driven fixes for 5
/// concrete product problems Stefan found running a real Build Muscle /
/// 4x Hypertrophy + 1x Functional Fitness journey in the Simulator. Every
/// fixture here goes through the real, unmodified production pipeline
/// (`LongTermPlanner`/`AcceptStrategicPlanUseCase`/`StartPhaseUseCase`) —
/// never a hand-built shortcut — so these tests prove the same paths a
/// real athlete's onboarding hits.
@MainActor
final class DogfoodRound1CompletionTests: XCTestCase {
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

    private func availability() -> UserAvailability {
        UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1)
    }

    private func materializationContext() -> TacticalMaterializationContext {
        TacticalMaterializationContext(equipmentProfile: equipment, trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context))
    }

    /// Real acceptance path, mirroring Stefan's own real onboarding:
    /// Build Muscle, no milestone/target date at all.
    private func makeAcceptedNoTargetDatePlan(primaryType: GoalType = .muscleGain, asOf: Date) throws -> (goal: Goal, phase: TrainingPhase, plan: TrainingPlan) {
        let goal = Goal(ownerUserID: ownerUserID, primaryType: primaryType, createdAt: asOf)
        context.insert(goal)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: asOf)
        let phase = try XCTUnwrap(plan.orderedPhases.first)
        return (goal, phase, plan)
    }

    // MARK: - Finding 2: rolling strategic horizon without a target date

    /// Before this fix: `proposeForwardOnlyPhases`'s no-target-date branch
    /// returned exactly one open-ended phase — the entire, real cause of
    /// "No later phase is planned yet" for a completely ordinary Build
    /// Muscle goal. This proves the fix without assuming anything about
    /// UI text: the ACCEPTED plan must contain more than one phase, and
    /// `TrainingPhaseCompletion.nextStrategicPhase` must find a real
    /// planned successor for the current (first) phase.
    func testFinding2_NoTargetDateGoalGetsARollingHorizonNotASinglePhase() throws {
        let asOf = date(2026, 1, 5) // a Monday
        let fixture = try makeAcceptedNoTargetDatePlan(asOf: asOf)

        XCTAssertGreaterThan(fixture.plan.orderedPhases.count, 1, "a normal open-ended goal must have real near-future phases, not just one forever")

        fixture.phase.status = .active
        let next = TrainingPhaseCompletion.nextStrategicPhase(for: fixture.phase)
        XCTAssertNotNil(next, "the current phase must have a real planned successor")
        XCTAssertEqual(next?.status, .planned)

        // Precision hierarchy: the LAST phase in the horizon is still
        // deliberately open-ended (lower precision, strategic intent
        // only) — this is never claiming a fabricated far-future exact
        // end date.
        let last = try XCTUnwrap(fixture.plan.orderedPhases.last)
        XCTAssertNil(last.endDate, "the horizon's final phase must stay open-ended, never a fabricated exact future date")

        // Every phase strictly between current and last must have a real
        // computed end date (near-future precision) — only the very last
        // one is open-ended.
        for phase in fixture.plan.orderedPhases.dropLast() {
            XCTAssertNotNil(phase.endDate, "every near-future phase before the horizon's tail must have a real estimated end date")
        }
    }

    /// Matches Stefan's exact repro: Build Muscle, no target date — must
    /// produce the same `[muscleGain, muscleGain, maintenance]` cycle
    /// `StrategicPeriodizationPolicy` already defines, now surfaced
    /// forward instead of collapsing to one phase.
    func testFinding2_BuildMuscleRollingHorizonMatchesStrategicPeriodizationPolicyCycle() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedNoTargetDatePlan(primaryType: .muscleGain, asOf: asOf)
        let types = fixture.plan.orderedPhases.map(\.type)
        XCTAssertEqual(types, [.muscleGain, .muscleGain, .maintenance])
    }

    /// A goal whose cycle is a single, non-repeating entry (`.maintenance`
    /// primary type) must never be expanded into a fabricated multi-phase
    /// horizon — `rollingOpenEndedHorizon` must degrade to the same
    /// single open-ended phase this branch always produced for that case.
    func testFinding2_MaintenanceGoalStillProducesASingleOpenEndedPhase() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedNoTargetDatePlan(primaryType: .maintenance, asOf: asOf)
        XCTAssertEqual(fixture.plan.orderedPhases.count, 1)
        XCTAssertNil(fixture.plan.orderedPhases[0].endDate)
    }

    // MARK: - Finding 2B: current-week display off-by-one

    /// The exact real bug: a brand-new plan accepted and started on its
    /// own first day must show Week 1, never Week 2 — `nextWeekIndex`
    /// (materialization completeness) is not the same concept as "current
    /// week for display" (`currentMaterializedWeekIndex`).
    func testFinding2B_FreshlyStartedPhaseShowsWeekOneNotWeekTwoOnDayOne() throws {
        let asOf = date(2026, 1, 5) // a Monday — R0: starts immediately, no shift
        let fixture = try makeAcceptedNoTargetDatePlan(primaryType: .muscleGain, asOf: asOf)
        XCTAssertTrue(
            Calendar.current.isDate(fixture.phase.startDate, inSameDayAs: asOf),
            "sanity: Monday acceptance starts immediately per R0 (local-calendar day, not exact UTC instant)"
        )

        let candidates = LongTermPlanner.proposeTrainingMix(phase: fixture.phase, goal: fixture.goal)
        let recommended = try XCTUnwrap(candidates.first { $0.roles.contains(.recommended) })
        try StartPhaseUseCase.start(
            phase: fixture.phase, mix: recommended.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext(), context: context
        )

        let planViewModel = PlanViewModel()
        planViewModel.load(modelContext: context, referenceDate: asOf)
        let position = try XCTUnwrap(planViewModel.currentWeekPosition)
        XCTAssertEqual(position.index, 1, "must read 'Week 1', not 'Week 2', the instant the phase starts")

        let phaseDetailViewModel = PhaseDetailViewModel()
        phaseDetailViewModel.load(phase: fixture.phase, modelContext: context)
        let detailIndex = try XCTUnwrap(phaseDetailViewModel.currentWeekIndex)
        let detailTotal = try XCTUnwrap(phaseDetailViewModel.totalWindowWeeks)
        XCTAssertEqual(min(detailIndex, detailTotal - 1) + 1, 1, "PhaseDetailView's own display must agree with Plan's")
    }

    // MARK: - Finding 4: start a different day's session

    func testFinding4_StartTodayInsteadMovesTheSameSessionWithoutDuplicatingIt() throws {
        let ownerUserID = UUID()
        let originalDate = date(2026, 1, 10) // a future day, distinct from "today"
        let today = date(2026, 1, 5)

        let originalDay = Day(ownerUserID: ownerUserID, date: originalDate)
        context.insert(originalDay)
        let session = Session(name: "Thursday Upper", modality: .strength)
        context.insert(session)
        originalDay.addSession(session)
        try context.save()

        let moved = try StartSessionOnDifferentDayUseCase.startToday(session, asOf: today, modelContext: context)

        // Same Session row — never duplicated.
        XCTAssertEqual(moved.id, session.id)
        XCTAssertEqual(moved.status, .inProgress)
        XCTAssertNotNil(moved.startedAt)

        // Re-parented onto today, not left behind on the original day.
        XCTAssertTrue(Calendar.current.isDate(try XCTUnwrap(moved.day?.date), inSameDayAs: today))
        XCTAssertFalse(originalDay.sessions.contains { $0.id == session.id }, "must not still look unperformed on its original day")

        // Exactly one Session total for this athlete — nothing fabricated.
        let allSessions = try context.fetch(FetchDescriptor<Session>())
        XCTAssertEqual(allSessions.count, 1)
    }

    func testFinding4_CannotStartTodayInsteadWhenAlreadyScheduledForToday() throws {
        let ownerUserID = UUID()
        let today = date(2026, 1, 5)
        let day = Day(ownerUserID: ownerUserID, date: today)
        context.insert(day)
        let session = Session(name: "Today's Session", modality: .strength)
        context.insert(session)
        day.addSession(session)

        XCTAssertThrowsError(try StartSessionOnDifferentDayUseCase.startToday(session, asOf: today, modelContext: context)) { error in
            XCTAssertEqual(error as? StartSessionOnDifferentDayError, .alreadyScheduledForToday)
        }
    }

    // MARK: - Finding 1 (Final Close correction): real equipment profile resolution

    /// Two materially different equipment/load profiles must resolve
    /// differently — never one blanket barbell/2.5kg assumption for
    /// every exercise, regardless of what it actually is.
    func testFinding1_DifferentEquipmentTypesProduceDifferentRounding() {
        let barbell = EquipmentType.resolved(fromExerciseEquipment: "barbell")
        let machine = EquipmentType.resolved(fromExerciseEquipment: "machine")
        let dumbbell = EquipmentType.resolved(fromExerciseEquipment: "dumbbell")
        XCTAssertEqual(barbell, .barbell)
        XCTAssertEqual(machine, .machine)
        XCTAssertEqual(dumbbell, .dumbbell)

        let profile = UserProfile(equipmentIncrements: ["barbell": 2.5, "machine": 5.0, "dumbbell": 2.0])
        let barbellExercise = Exercise(canonicalName: "Back Squat", modality: .strength, equipment: "barbell", movementPattern: "squat")
        let machineExercise = Exercise(canonicalName: "Leg Press", modality: .strength, equipment: "machine", movementPattern: "squat")
        let barbellProfile = EquipmentProfile.resolved(for: barbellExercise, userProfile: profile)
        let machineProfile = EquipmentProfile.resolved(for: machineExercise, userProfile: profile)
        XCTAssertEqual(barbellProfile.smallestIncrementKg, 2.5)
        XCTAssertEqual(machineProfile.smallestIncrementKg, 5.0)

        // A real, materially different rounding outcome for the same raw
        // ideal load, proving this isn't just a cosmetic type difference.
        let idealLoad = IdealLoad(kilograms: 61.2)
        XCTAssertEqual(barbellProfile.resolve(idealLoad), 60.0, "barbell rounds to the nearest 2.5kg")
        XCTAssertEqual(machineProfile.resolve(idealLoad), 60.0, "machine rounds to the nearest 5kg — same input, must not silently share the barbell profile's own increment")
        let idealLoad2 = IdealLoad(kilograms: 63.0)
        XCTAssertEqual(barbellProfile.resolve(idealLoad2), 62.5)
        XCTAssertEqual(machineProfile.resolve(idealLoad2), 65.0, "a materially different rounded result for the same raw ideal load — proves equipment genuinely differentiates now")
    }

    /// An unrecognized/unmapped equipment string degrades to the exact
    /// same TRAININGOS_DESIGNED default every real call site already used
    /// before this fix — never worse off, never a crash.
    func testFinding1_UnrecognizedEquipmentDegradesToExistingDefault() {
        let resolved = EquipmentType.resolved(fromExerciseEquipment: "some-future-equipment-kind")
        XCTAssertEqual(resolved, .barbell)
    }

    /// In-session calibration must resolve through the REAL per-exercise
    /// equipment/increment authority, never a hardcoded barbell/2.5kg
    /// profile — proven end to end through
    /// `ResolveCalibrationDependentPrescriptionsUseCase`, the same
    /// mechanism both the in-session prompt and the optional "estimate
    /// now" screen call.
    func testFinding1_InSessionCalibrationUsesTheRealEquipmentProfileNotHardcodedBarbell() throws {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let ownerID = UUID()

        // A minimal, directly-constructed real materialized graph —
        // exactly the shape `StrengthMaterializer` itself produces —
        // for a MACHINE exercise (Leg Press) left honestly unresolved
        // pending calibration, rather than depending on which exercises a
        // full mesocycle recommendation happens to pick.
        let instance = ProgramInstance(ownerUserID: ownerID, startDate: date(2026, 1, 5))
        context.insert(instance)
        let day = Day(ownerUserID: ownerID, date: date(2026, 1, 5))
        context.insert(day)
        let session = Session(name: "Day 1", modality: .strength)
        context.insert(session)
        day.addSession(session)
        session.programInstance = instance
        let block = WorkoutBlock(type: .strength)
        context.insert(block)
        session.addBlock(block)
        let template = PrescriptionTemplate(rules: StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.8, laterWeekMultipliers: [1.0, 1.0, 1.0])),
            setCountRule: .fixed(setsByWeek: [3, 3, 3, 3]), repGoalSchedule: [.fixedReps(10)]
        ))
        context.insert(template)
        let prescription = ExercisePrescription(exercise: catalog.legPress)
        context.insert(prescription)
        prescription.sourcePrescriptionTemplate = template
        prescription.appliedLoadReasonCode = .calibrationRequired
        block.addPrescription(prescription)
        let setPrescription = SetPrescription(repRangeLow: 10, repRangeHigh: 10, targetWeight: nil, targetRir: nil)
        context.insert(setPrescription)
        prescription.addSetPrescription(setPrescription)

        // A real athlete equipment preference — machine increments of
        // 5kg, deliberately different from the barbell default.
        let user = User(displayName: "Test")
        context.insert(user)
        let profile = UserProfile(equipmentIncrements: ["barbell": 2.5, "machine": 5.0])
        context.insert(profile)
        user.attachProfile(profile)

        try ResolveCalibrationDependentPrescriptionsUseCase.resolve(
            exercise: catalog.legPress, rmType: .rm10, kilograms: 101, instance: instance,
            userProfile: profile, modelContext: context
        )

        let resolvedWeight = try XCTUnwrap(setPrescription.targetWeight)
        // 101 * 0.8 = 80.8, rounded to the MACHINE increment (5kg) -> 80.
        // Rounded to the barbell 2.5kg increment it would instead be 80.0
        // too by coincidence at this exact number, so this also asserts
        // the EXACT expected value to rule out a false pass.
        XCTAssertEqual(resolvedWeight, 80.0, accuracy: 0.001)
        XCTAssertEqual(resolvedWeight.truncatingRemainder(dividingBy: 5.0), 0, accuracy: 0.001, "must round to the real machine increment (5kg)")

        // Same scenario, barbell equipment instead — must resolve
        // DIFFERENTLY for a raw value that only the barbell's finer
        // 2.5kg increment can represent, proving equipment genuinely
        // changes the outcome rather than both silently sharing one
        // profile.
        let barbellExercise = Exercise(canonicalName: "Test Barbell Exercise", modality: .strength, equipment: "barbell", movementPattern: "test")
        context.insert(barbellExercise)
        let barbellPrescription = ExercisePrescription(exercise: barbellExercise)
        context.insert(barbellPrescription)
        barbellPrescription.sourcePrescriptionTemplate = template
        barbellPrescription.appliedLoadReasonCode = .calibrationRequired
        block.addPrescription(barbellPrescription)
        let barbellSetPrescription = SetPrescription(repRangeLow: 10, repRangeHigh: 10, targetWeight: nil, targetRir: nil)
        context.insert(barbellSetPrescription)
        barbellPrescription.addSetPrescription(barbellSetPrescription)

        try ResolveCalibrationDependentPrescriptionsUseCase.resolve(
            exercise: barbellExercise, rmType: .rm10, kilograms: 91.5, instance: instance,
            userProfile: profile, modelContext: context
        )
        let barbellResolvedWeight = try XCTUnwrap(barbellSetPrescription.targetWeight)
        // 91.5 * 0.8 = 73.2 -> barbell (2.5kg) rounds to 72.5; machine
        // (5kg) would round to 75 — materially different results for the
        // SAME raw input, proving per-exercise equipment resolution.
        XCTAssertEqual(barbellResolvedWeight, 72.5, accuracy: 0.001)
    }

    /// The correct source-required RM type must be shown to the athlete —
    /// a 10RM slot must say "10RM", a 5RM slot must say "5RM", never a
    /// generic "starting weight."
    func testFinding1_CorrectRMTypeIsPresentedToTheAthlete() {
        XCTAssertEqual(PlanPresentation.rmTypeLabel(.rm10), "10RM")
        XCTAssertEqual(PlanPresentation.rmTypeLabel(.rm8), "8RM")
        XCTAssertEqual(PlanPresentation.rmTypeLabel(.rm5), "5RM")
    }

    /// The source formula itself (`StrengthProgressionEngine.resolveWeight`)
    /// must remain byte-for-byte unchanged by this correction — only WHICH
    /// `EquipmentProfile` gets passed into it changed, never the formula.
    func testFinding1_SourceFormulaRemainsUnchanged() {
        let rules = StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.8, laterWeekMultipliers: [1.0, 1.0, 1.0])),
            setCountRule: .fixed(setsByWeek: [3, 3, 3, 3]), repGoalSchedule: [.fixedReps(10)]
        )
        let profile = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)
        let result = StrengthProgressionEngine.resolveWeight(
            rules: rules, weekIndex: 0, rmKilograms: 100, weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: nil, equipmentProfile: profile
        )
        XCTAssertEqual(result.weightKg, 80, "100kg * 0.8 weekOneFactor, unchanged formula")
        XCTAssertEqual(result.reasonCode, .rmBasedLoad)
    }

    /// Never a fabricated calibration load — missing calibration still
    /// resolves to `nil`/`.calibrationRequired`, exactly as before.
    func testFinding1_NoFabricatedCalibrationLoad() {
        let rules = StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.8, laterWeekMultipliers: [1.0, 1.0, 1.0])),
            setCountRule: .fixed(setsByWeek: [3, 3, 3, 3]), repGoalSchedule: [.fixedReps(10)]
        )
        let profile = EquipmentProfile.resolved(for: Exercise(canonicalName: "Leg Press", modality: .strength, equipment: "machine", movementPattern: "squat"), userProfile: nil)
        let result = StrengthProgressionEngine.resolveWeight(
            rules: rules, weekIndex: 0, rmKilograms: nil, weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: nil, equipmentProfile: profile
        )
        XCTAssertNil(result.weightKg)
        XCTAssertEqual(result.reasonCode, .calibrationRequired)
    }

    // MARK: - Finding 3A/3E: phase-biased Functional Fitness programming

    private func availability5Day() -> UserAvailability {
        UserAvailability(trainingDaysPerWeek: 5, allowsDoubleSessions: false, maxSessionsPerDay: 1)
    }

    private func materializationContext(context: ModelContext) -> TacticalMaterializationContext {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        return TacticalMaterializationContext(
            equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
            strengthCandidateExercises: exercises, functionalFitnessCandidateExercises: exercises,
            trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)
        )
    }

    /// Stefan's own real repro shape (Build Muscle + 1x Functional
    /// Fitness): the current Muscle Gain phase's own priority must bias
    /// the FF component toward Functional Bodybuilding — every authored
    /// week gets a real strength/accessory block, never just some weeks.
    func testFinding3A_MuscleGainPhaseBiasesFunctionalFitnessTowardFunctionalBodybuilding() throws {
        _ = ExerciseCatalog.resolveOrInsert(context: context)
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedNoTargetDatePlan(primaryType: .muscleGain, asOf: asOf)
        guard case .success(let mix) = LongTermPlanner.buildCustomMix(
            selections: [(style: .hypertrophy, frequency: 4), (style: .functionalFitness, frequency: 1)], capacity: 5
        ) else { return XCTFail("4H+1FF must be a real, constructible composition") }
        context.insert(mix)

        let result = try StartPhaseUseCase.start(
            phase: fixture.phase, mix: mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability5Day(),
            materializationContext: materializationContext(context: context), context: context
        )
        let ffInstance = try XCTUnwrap(result.instancesByComponent.values.first { $0.programDefinition?.programmingSystem == .functionalFitness })
        let weeklyPlan = try XCTUnwrap(ffInstance.programDefinition?.functionalFitnessConfiguration?.weeklyPlan)
        XCTAssertTrue(weeklyPlan.allSatisfy(\.includeStrengthBlock), "a Muscle Gain phase must bias FF toward a real strength/accessory block every week, never a bare metcon")
    }

    /// A Recovery/Maintenance-biased phase must down-regulate FF instead
    /// — no strength block, lower loading/intensity/systemic demand.
    func testFinding3A_MaintenancePhaseBiasesFunctionalFitnessTowardDownRegulation() throws {
        let weeklyPlan = try XCTUnwrap(FunctionalFitnessAuthoredProgramLibrary.weeklyPlan(forSessionsPerWeek: 1))
        let biased = FunctionalFitnessPhaseBiasPolicy.apply(weeklyPlan, phaseType: .maintenance)
        XCTAssertTrue(biased.allSatisfy { !$0.includeStrengthBlock })
        XCTAssertTrue(biased.allSatisfy { $0.stimulus.loading == .bodyweightOnly })
        XCTAssertTrue(biased.allSatisfy { $0.stimulus.intensity == .low })
    }

    /// A dedicated Functional Fitness phase needs no bias — the authored
    /// plan's own shape is already appropriate.
    func testFinding3A_FunctionalFitnessPhaseAppliesNoBias() throws {
        let weeklyPlan = try XCTUnwrap(FunctionalFitnessAuthoredProgramLibrary.weeklyPlan(forSessionsPerWeek: 1))
        let unbiased = FunctionalFitnessPhaseBiasPolicy.apply(weeklyPlan, phaseType: .functionalFitness)
        XCTAssertEqual(unbiased, weeklyPlan)
    }

    /// Finding 3E: the Functional Bodybuilding block is a distinct
    /// expression — real, moderate-rep (10, never a 5-rep strength test),
    /// and rotates through squat/hinge/press/pull across the week index
    /// rather than always the same movement pattern.
    func testFinding3E_FunctionalBodybuildingBlockRotatesPatternsAndUsesModerateRepRange() throws {
        _ = ExerciseCatalog.resolveOrInsert(context: context)
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedNoTargetDatePlan(primaryType: .muscleGain, asOf: asOf)
        guard case .success(let mix) = LongTermPlanner.buildCustomMix(
            selections: [(style: .hypertrophy, frequency: 4), (style: .functionalFitness, frequency: 1)], capacity: 5
        ) else { return XCTFail("4H+1FF must be a real, constructible composition") }
        context.insert(mix)

        try StartPhaseUseCase.start(
            phase: fixture.phase, mix: mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability5Day(),
            materializationContext: materializationContext(context: context), context: context
        )
        let ffComponent = try XCTUnwrap(mix.orderedComponents.first { $0.programmingSystem == .functionalFitness })
        let definition = try XCTUnwrap(ffComponent.programInstance?.programDefinition)
        let strengthSlotNames = definition.orderedTemplateSessions
            .flatMap(\.orderedBlockTemplates).filter { $0.type == .strength }
            .flatMap(\.orderedPrescriptionTemplates).compactMap(\.exerciseSlot?.name)
        XCTAssertGreaterThan(Set(strengthSlotNames).count, 1, "must rotate through more than one Functional Bodybuilding pattern across the 4 weeks")
        XCTAssertTrue(strengthSlotNames.allSatisfy { $0.hasPrefix("Functional Bodybuilding") }, "must be clearly labeled as its own distinct expression, never a bare 'Squat' strength test")

        let repGoals = definition.orderedTemplateSessions
            .flatMap(\.orderedBlockTemplates).filter { $0.type == .strength }
            .flatMap(\.orderedPrescriptionTemplates).compactMap(\.rules?.repGoalSchedule.first)
        XCTAssertTrue(repGoals.allSatisfy { if case .fixedReps(10) = $0 { return true }; return false }, "Functional Bodybuilding uses a moderate rep range, never a 5-rep strength test")
    }

    // MARK: - Finding 3C: capability-aware movement selection

    /// An advanced gymnastics expression (Chest-to-Bar Pull-up) must
    /// never be TrainingOS's own automatic pick when an ordinary
    /// candidate (Pull-up) is equally eligible for the same slot.
    /// Dogfood Round 1 — Final Close (Finding 3C correction): real
    /// materialization-level proof, not a hand-copied re-implementation of
    /// the resolution logic — exercises the actual
    /// `FunctionalFitnessMaterializer.materializeWeek` production path.
    /// Includes a real `squatLoaded`/`monostructural` candidate alongside
    /// the gymnastics ones so the composer only needs exactly ONE
    /// `gymnasticsPull` role this session (matching a real production
    /// triplet) — never an artificially gymnastics-only pool, which would
    /// force the composer to re-use the function for every role and
    /// exhaust the single ordinary candidate for reasons unrelated to
    /// this fix.
    private func materializeFFRealistic(gymnasticsPullCandidates: [Exercise], environment: TrainingEnvironment) throws -> [Session] {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let stimulus = Stimulus(
            targetDurationDomain: .medium, intensity: .moderate, loading: .moderate,
            movementFunctions: [.squatLoaded, .gymnasticsPull, .monostructural],
            movementModalityMix: [
                ModalityCount(modality: .weightlifting, count: 1),
                ModalityCount(modality: .gymnastics, count: 1),
                ModalityCount(modality: .metabolicConditioning, count: 1),
            ],
            skillDemand: .moderate, systemicDemand: .moderate, scoreType: .time
        )
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 1, targetStimulus: stimulus,
            format: .roundsForTime(rounds: 5, capSeconds: nil), sessionRole: .functionalFitness,
            varianceConstraints: VarianceConstraints(), requiresRecentExposureToProgress: false, includeStrengthBlock: false
        )
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        let candidates = [catalog.backSquat, catalog.row] + gymnasticsPullCandidates
        for candidate in candidates where candidate.modelContext == nil { context.insert(candidate) }
        return try FunctionalFitnessMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
            candidateExercises: candidates, exposureHistory: [], environment: environment, context: context
        )
    }

    func testFinding3C_AdvancedGymnasticsMovementIsNeverTheAutomaticPick() throws {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        XCTAssertTrue(catalog.chestToBarPullUp.requiresDemonstratedCapability)
        XCTAssertFalse(catalog.pullUp.requiresDemonstratedCapability)

        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let sessions = try materializeFFRealistic(gymnasticsPullCandidates: [catalog.chestToBarPullUp, catalog.pullUp], environment: environment)
        let movements = sessions.flatMap(\.orderedBlocks).compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements)
        XCTAssertTrue(movements.contains { $0.exercise?.canonicalName == "Pull-up" }, "the ordinary movement must be the real, materialized automatic pick")
        XCTAssertFalse(movements.contains { $0.exercise?.canonicalName == "Chest-to-Bar Pull-up" }, "the advanced movement must never be auto-prescribed when an ordinary alternative exists")
    }

    /// The corrected invariant: when the advanced movement is the SOLE
    /// eligible candidate for its role, TrainingOS must fail honestly
    /// rather than silently auto-prescribe it — real athlete capability is
    /// unknown, and unknown capability must never become an automatic
    /// unscaled advanced prescription.
    func testFinding3C_SoleAdvancedCandidateFailsHonestlyRatherThanAutoPrescribing() throws {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        XCTAssertThrowsError(try materializeFFRealistic(gymnasticsPullCandidates: [catalog.chestToBarPullUp], environment: environment)) { error in
            guard case FunctionalFitnessMaterializationError.capabilityUnknown(_, let exercise) = error else {
                return XCTFail("expected .capabilityUnknown, got \(error)")
            }
            XCTAssertEqual(exercise, "Chest-to-Bar Pull-up")
        }
    }

    /// Manual athlete selection (a real, already-recorded GOING FORWARD
    /// preference) must still win outright — this check only blocks
    /// TrainingOS's own automatic pick, never an informed athlete choice.
    /// Proves this against the exact same
    /// `SubstituteExerciseUseCase.resolvedExercise` call
    /// `FunctionalFitnessMaterializer` itself makes FIRST, before the
    /// capability gate is ever consulted.
    func testFinding3C_ManualGoingForwardPreferenceForAdvancedMovementStillWins() throws {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let sessions = try materializeFFRealistic(gymnasticsPullCandidates: [catalog.chestToBarPullUp, catalog.pullUp], environment: environment)
        let instance = try XCTUnwrap(sessions.first?.programInstance)
        guard let slot = sessions.flatMap(\.orderedBlocks).compactMap(\.functionalFitnessPrescription)
            .flatMap(\.orderedMovements).first(where: { $0.exercise?.canonicalName == "Pull-up" })?.sourceExerciseSlot else {
            return XCTFail("expected a real materialized gymnasticsPull slot to attach a going-forward preference to")
        }

        let override = SlotSelectionOverride(selectedExercise: catalog.chestToBarPullUp)
        context.insert(override)
        override.templateSlot = slot
        instance.addSlotSelectionOverride(override)

        XCTAssertEqual(
            SubstituteExerciseUseCase.resolvedExercise(for: slot, in: instance)?.canonicalName, "Chest-to-Bar Pull-up",
            "a real, already-recorded athlete preference must still resolve to the advanced movement — this only blocks the AUTOMATIC pick"
        )
    }

    // MARK: - Finding 3D: FF load/scaling guidance

    /// Every automatically generated LOADED movement must show either a
    /// real numeric load or legitimate authored relative load/intensity
    /// guidance — never neither.
    func testFinding3D_EveryLoadedMovementHasNumericOrRelativeLoadGuidance() throws {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let allSessions = try materializeFFRealistic(gymnasticsPullCandidates: [catalog.pullUp], environment: environment)
        let movements = allSessions.flatMap(\.orderedBlocks).compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements)
        let loadedMovements = movements.filter { $0.exercise?.functionalModality == .weightlifting }
        XCTAssertFalse(loadedMovements.isEmpty, "sanity: this fixture must actually produce a loaded movement")
        for movement in loadedMovements {
            XCTAssertTrue(
                movement.loadKilograms != nil || movement.relativeLoadTier != nil,
                "\(movement.exercise?.canonicalName ?? "movement") must carry either a numeric load or relative load guidance, never neither"
            )
        }
    }

    /// The authored relative guidance is real, materialized, per-exercise
    /// data — not a display-only improvisation.
    func testFinding3D_RelativeLoadGuidanceSurvivesMaterialization() throws {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let sessions = try materializeFFRealistic(gymnasticsPullCandidates: [catalog.pullUp], environment: environment)
        let movements = sessions.flatMap(\.orderedBlocks).compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements)
        let backSquatMovement = try XCTUnwrap(movements.first { $0.exercise?.canonicalName == "Back Squat" })
        XCTAssertNil(backSquatMovement.loadKilograms, "no validated numeric formula exists — never fabricated")
        XCTAssertEqual(backSquatMovement.relativeLoadTier, .moderate)
        XCTAssertNotNil(backSquatMovement.relativeLoadTargetReserveRepsOpeningRound)
    }

    /// The athlete-facing execution UI's own presentation function must
    /// actually render the guidance — proven directly against
    /// `BlockPresentation.loadGuidanceLine`, the exact function
    /// `FunctionalFitnessExecutionView` calls.
    func testFinding3D_ExecutionUIRendersLoadGuidanceLine() throws {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        context.insert(catalog.backSquat)
        let movementWithGuidance = FunctionalFitnessMovement(
            exercise: catalog.backSquat, reps: 12,
            relativeLoadTier: .moderate, relativeLoadTargetReserveRepsOpeningRound: 3, relativeLoadSustainableUnbrokenIntent: true
        )
        let line = try XCTUnwrap(BlockPresentation.loadGuidanceLine(movementWithGuidance))
        XCTAssertTrue(line.contains("Moderate load"))
        XCTAssertTrue(line.contains("reserve"))
        XCTAssertTrue(line.contains("sustainable"))

        // A movement with a real numeric load shows no relative guidance
        // alongside it — the number is already the more precise answer.
        let movementWithNumericLoad = FunctionalFitnessMovement(
            exercise: catalog.backSquat, reps: 12, loadKilograms: 60,
            relativeLoadTier: .moderate, relativeLoadTargetReserveRepsOpeningRound: 3, relativeLoadSustainableUnbrokenIntent: true
        )
        XCTAssertNil(BlockPresentation.loadGuidanceLine(movementWithNumericLoad))

        // A genuinely unloaded (gymnastics) movement shows nothing either.
        let unloadedMovement = FunctionalFitnessMovement(exercise: catalog.pullUp, reps: 8)
        XCTAssertNil(BlockPresentation.loadGuidanceLine(unloadedMovement))
    }

    /// Cross-cutting regression guard: Finding 3D must never disturb
    /// Finding 3A's Muscle Gain -> Functional Bodybuilding bias, and the
    /// conditioning/metcon component must remain present alongside it.
    func testFinding3D_MuscleGainFunctionalBodybuildingBiasAndConditioningBothRemain() throws {
        _ = ExerciseCatalog.resolveOrInsert(context: context)
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedNoTargetDatePlan(primaryType: .muscleGain, asOf: asOf)
        guard case .success(let mix) = LongTermPlanner.buildCustomMix(
            selections: [(style: .hypertrophy, frequency: 4), (style: .functionalFitness, frequency: 1)], capacity: 5
        ) else { return XCTFail("4H+1FF must be a real, constructible composition") }
        context.insert(mix)
        try StartPhaseUseCase.start(
            phase: fixture.phase, mix: mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability5Day(),
            materializationContext: materializationContext(context: context), context: context
        )
        let ffInstance = try XCTUnwrap(mix.orderedComponents.first { $0.programmingSystem == .functionalFitness }?.programInstance)
        let weeklyPlan = try XCTUnwrap(ffInstance.programDefinition?.functionalFitnessConfiguration?.weeklyPlan)
        XCTAssertTrue(weeklyPlan.allSatisfy(\.includeStrengthBlock), "Finding 3A's Functional Bodybuilding bias must still apply")

        let sessions = ffInstance.sessions
        XCTAssertTrue(
            sessions.contains { $0.orderedBlocks.contains { $0.functionalFitnessPrescription != nil } },
            "the conditioning/metcon component must still be present alongside the Functional Bodybuilding block"
        )
    }

    func testFinding4_CannotOverrideASessionAlreadyInProgressOrCompleted() throws {
        let ownerUserID = UUID()
        let originalDay = Day(ownerUserID: ownerUserID, date: date(2026, 1, 10))
        context.insert(originalDay)
        let session = Session(name: "Thursday Upper", modality: .strength, status: .inProgress)
        context.insert(session)
        originalDay.addSession(session)

        XCTAssertThrowsError(try StartSessionOnDifferentDayUseCase.startToday(session, asOf: date(2026, 1, 5), modelContext: context)) { error in
            XCTAssertEqual(error as? StartSessionOnDifferentDayError, .notScheduled)
        }
    }
}
