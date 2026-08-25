import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 10B.6: the real cross-window Hypertrophy V2 progression loop,
/// end to end through the actual production path —
/// `HypertrophyProgramGenerator` (day-focus-driven) ->
/// `ResolveProgramInstanceExerciseSlotsUseCase` ->
/// `RollTacticalWindowUseCase.materializeFirstWindow`/`rollForward` (the
/// exact `.doubleProgression` branch added this stage) -> real logged
/// sets (`LogSetUseCase`) -> `CompleteSessionUseCase` -> the next real
/// materialized week. Never a hand-authored prescription bypassing
/// materialization. Deliberately bypasses `LongTermPlanner`'s goal/mix
/// ranking (a separately and already-tested concern) by attaching a
/// directly-generated 3-Day Full Body `ProgramDefinition` to a hand-built
/// `TrainingMixComponent` — this is the one intentional scoping shortcut,
/// so every OTHER step below is the real, unmodified orchestration.
@MainActor
final class HypertrophyV2EndToEndTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()
    let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func availability() -> UserAvailability {
        UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1)
    }

    private func materializationContext(candidates: [Exercise]) -> TacticalMaterializationContext {
        TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates)
    }

    private struct Fixture {
        let definition: ProgramDefinition
        let instance: ProgramInstance
        let mix: TrainingMix
        let component: TrainingMixComponent
        let performanceProfile: PerformanceProfile
        let catalog: ExerciseCatalog
        let startDate: Date
    }

    /// Stage 10R.1 Slice 1B retired `.doubleProgression` from every
    /// `HypertrophyProgramGenerator` production path — 3-Day Full Body now
    /// generates the restored source-compatible `.rmBased` progression
    /// instead (`STAGE10R1_SLICE1B_SOURCE_PROGRESSION_DESIGN.md`); no
    /// built-in configuration emits `.doubleProgression` any longer.
    /// Hypertrophy V2 (`HypertrophyV2ProgressionEngine`/
    /// `DoubleProgressionEngine`) is kept as infrastructure for a future
    /// load-bias overlay stage (Decision on Stage 10B.6 routing — code
    /// stays, authority for THIS program moves) — this fixture builds a
    /// standalone, hand-authored `.doubleProgression` template graph
    /// directly, matching the exact day/slot/baseline shape Stage 10B.6's
    /// day-focus generator used to produce, so the engine itself and the
    /// real `RollTacticalWindowUseCase`/materialization/logging pipeline
    /// around it stay covered by genuine integration-shaped tests without
    /// depending on a generator path that no longer emits this rule.
    private func makeDoubleProgressionTemplateGraph(catalog: ExerciseCatalog) -> ProgramDefinition {
        let configuration = HypertrophyProgramConfiguration(dayCount: 3, split: .fullBody, phaseType: .basicHypertrophy)
        let definition = ProgramDefinition(
            name: "Test Hypertrophy V2 Fixture", lengthWeeks: 5, intent: "Stage 10B.6 engine regression fixture",
            programmingSystem: .hypertrophy, generatorVersion: HypertrophyProgramGenerator.currentVersion,
            provenance: .constructed(reason: "Stage 10B.6 end-to-end test"), hypertrophyConfiguration: configuration
        )
        context.insert(definition)
        for _ in 0..<4 {
            let week = TrainingWeek(isDeload: false)
            context.insert(week)
            definition.addWeek(week)
        }
        let deloadWeek = TrainingWeek(isDeload: true)
        context.insert(deloadWeek)
        definition.addWeek(deloadWeek)

        func addSlot(to block: WorkoutBlockTemplate, name: String, targets: [MuscleGroup], exercise: Exercise, baselineSets: Int) {
            let template = PrescriptionTemplate(rules: StrengthProgressionRules(
                loadRule: .doubleProgression,
                setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: baselineSets)),
                repGoalSchedule: HypertrophyV2ProgressionEngine.makeRepGoalSchedule(for: .primary)
            ), slotRole: .primary)
            let slot = ExerciseSlot(name: name, allowedTargets: targets)
            context.insert(template)
            context.insert(slot)
            template.attachExerciseSlot(slot)
            slot.resolvedExercise = exercise
            block.addPrescriptionTemplate(template)
            // Local, self-attributed pairing — this fixture tests the
            // Hypertrophy V2 engine mechanism itself, not the real source
            // rating-pairing web (that belongs to the `.rmBased` path,
            // covered in `HypertrophyDayFocusGenerationTests.swift`).
            template.pairedSlot = template
        }

        let days: [(name: String, slots: [(name: String, targets: [MuscleGroup], exercise: Exercise, baselineSets: Int)])] = [
            ("Push Emphasis", [
                ("Horizontal Push", [.chest], catalog.benchPress, 3),
                ("Horizontal Pull", [.back], catalog.barbellRow, 3),
                ("Quads", [.quadriceps], catalog.frontSquat, 2),
            ]),
            ("Legs Emphasis", [
                ("Horizontal Push", [.chest], catalog.benchPress, 2),
                ("Horizontal Pull", [.back], catalog.barbellRow, 3),
                ("Quads", [.quadriceps], catalog.frontSquat, 3),
            ]),
            ("Pull Emphasis", [
                ("Horizontal Push", [.chest], catalog.benchPress, 3),
                ("Horizontal Pull", [.back], catalog.barbellRow, 3),
                ("Biceps", [.biceps], catalog.barbellCurl, 3),
            ]),
        ]
        for day in days {
            let session = TemplateSession(name: day.name, role: .hypertrophy)
            context.insert(session)
            definition.addTemplateSession(session)
            let block = WorkoutBlockTemplate(type: .hypertrophy)
            context.insert(block)
            session.addBlockTemplate(block)
            for slot in day.slots {
                addSlot(to: block, name: slot.name, targets: slot.targets, exercise: slot.exercise, baselineSets: slot.baselineSets)
            }
        }
        return definition
    }

    /// Builds the standalone Hypertrophy V2 `ProgramDefinition` fixture
    /// (see `makeDoubleProgressionTemplateGraph`'s doc comment) and wires
    /// a minimal but real `TrainingMix`/`TrainingMixComponent`/
    /// `ProgramInstance` so `RollTacticalWindowUseCase` can be called
    /// exactly as production would.
    private func makeFixture() throws -> Fixture {
        let catalog = ExerciseCatalog.makeAndInsert(context: context)
        let definition = makeDoubleProgressionTemplateGraph(catalog: catalog)

        let startDate = Date(timeIntervalSince1970: 1_700_000_000)
        let instance = ProgramInstance(ownerUserID: ownerUserID, startDate: startDate)
        context.insert(instance)
        instance.programDefinition = definition

        let mix = TrainingMix(kind: .selected, name: "Test V2 Mix")
        context.insert(mix)
        let component = TrainingMixComponent(
            label: "Hypertrophy", programmingSystem: .hypertrophy, priority: .primary,
            frequency: SessionFrequency(target: 3)
        )
        context.insert(component)
        mix.addComponent(component)
        component.programInstance = instance

        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)

        return Fixture(
            definition: definition, instance: instance, mix: mix, component: component,
            performanceProfile: performanceProfile, catalog: catalog, startDate: startDate
        )
    }

    private func materializeWeekZero(_ fixture: Fixture) throws -> [Session] {
        try RollTacticalWindowUseCase.materializeFirstWindow(
            system: .hypertrophy, definition: fixture.definition, instance: fixture.instance,
            startDate: fixture.startDate, ownerUserID: ownerUserID, performanceProfile: fixture.performanceProfile,
            materializationContext: materializationContext(candidates: []), context: context
        )
    }

    /// Logs every prescribed set for `prescription` with the given
    /// reps/RIR — the real `LogSetUseCase` path, never a fabricated
    /// `SetResult`. Does NOT complete the block/session: every exercise
    /// in a Stage 10B day shares ONE `WorkoutBlock`/`Session`, so
    /// completion must happen exactly once, after every exercise in the
    /// session has been logged — see `completeAllSessions`.
    private func logSets(
        for prescription: ExercisePrescription, reps: Int, actualRir: Int, performanceProfile: PerformanceProfile, asOf: Date
    ) throws {
        for setPrescription in prescription.orderedSetPrescriptions {
            try LogSetUseCase.logSet(
                setIndex: setPrescription.sortIndex, weight: setPrescription.targetWeight ?? 60, reps: reps,
                targetRir: setPrescription.targetRir, actualRir: actualRir, prBand: nil, scoringDirection: .higherIsBetter,
                context: .rx, setPrescription: setPrescription, exercisePrescription: prescription,
                exercise: try XCTUnwrap(prescription.exercise), performanceProfile: performanceProfile,
                completedAt: asOf, modelContext: context
            )
        }
    }

    /// Completes every distinct block/session referenced by `prescriptions`
    /// exactly once each, via the real `CompleteBlockUseCase`/
    /// `CompleteSessionUseCase` path — called after every exercise across
    /// all of a week's sessions has already been logged.
    private func completeAllSessions(for prescriptions: [ExercisePrescription], asOf: Date) throws {
        var seenBlockIDs = Set<UUID>()
        for prescription in prescriptions {
            guard let block = prescription.workoutBlock, !seenBlockIDs.contains(block.id) else { continue }
            seenBlockIDs.insert(block.id)
            try CompleteBlockUseCase.complete(block, context: .full, modelContext: context)
        }
        var seenSessionIDs = Set<UUID>()
        for prescription in prescriptions {
            guard let session = prescription.workoutBlock?.session, !seenSessionIDs.contains(session.id) else { continue }
            seenSessionIDs.insert(session.id)
            try CompleteSessionUseCase.complete(session, context: .full, asOf: asOf, modelContext: context)
        }
    }

    /// Logs adequate, on-track performance (within range, at target RIR)
    /// for every prescription in `prescriptions`, then completes every
    /// session exactly once — the common "make this week fully real and
    /// complete" step every scenario needs for its OTHER exercises,
    /// independent of whatever specific performance is being tested for
    /// the one exercise under test.
    private func logAdequatePerformanceAndComplete(_ prescriptions: [ExercisePrescription], performanceProfile: PerformanceProfile, asOf: Date) throws {
        for prescription in prescriptions {
            let target = prescription.orderedSetPrescriptions.first?.targetRir ?? 2
            try logSets(for: prescription, reps: 8, actualRir: target, performanceProfile: performanceProfile, asOf: asOf)
        }
        try completeAllSessions(for: prescriptions, asOf: asOf)
    }

    private func rollForward(_ fixture: Fixture, asOf: Date) throws -> RollTacticalWindowUseCase.Result {
        try XCTUnwrap(RollTacticalWindowUseCase.rollForward(
            mix: fixture.mix, asOf: asOf, ownerUserID: ownerUserID, performanceProfile: fixture.performanceProfile,
            availability: availability(), materializationContext: materializationContext(candidates: []), context: context
        ))
    }

    private func weekPrescriptions(_ result: RollTacticalWindowUseCase.Result) -> [ExercisePrescription] {
        result.newSessionsByComponent.values.flatMap { $0 }.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions)
    }

    /// Logs the SAME reps/RIR for every prescription of `target`'s own
    /// canonical Exercise this week — not just `target` itself. The
    /// 3-Day Full Body rotation legitimately repeats several exercises
    /// (e.g. Back Squat) across more than one day; since progression
    /// history is correctly scoped per Exercise (§15's substitution fix),
    /// every occurrence of that same exercise this week must agree, or
    /// the resolver's "most recent" pick becomes whichever day happened
    /// to complete last — never the specific scenario under test.
    private func logSameExercise(as target: ExercisePrescription, in prescriptions: [ExercisePrescription], reps: Int, actualRir: Int, performanceProfile: PerformanceProfile, asOf: Date) throws {
        for prescription in prescriptions where prescription.exercise?.id == target.exercise?.id {
            try logSets(for: prescription, reps: reps, actualRir: actualRir, performanceProfile: performanceProfile, asOf: asOf)
        }
    }

    private func otherExercises(than target: ExercisePrescription, in prescriptions: [ExercisePrescription]) -> [ExercisePrescription] {
        prescriptions.filter { $0.exercise?.id != target.exercise?.id }
    }

    // MARK: 1 — primary exercise, strong performance, real load increase

    func test1_PrimaryExerciseQualifyingForLoadIncrease() throws {
        let fixture = try makeFixture()
        let week0Sessions = try materializeWeekZero(fixture)
        let allWeek0 = week0Sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions)
        let squat = try XCTUnwrap(allWeek0.first { $0.exercise?.canonicalName == "Front Squat" })
        XCTAssertEqual(squat.appliedProgressionReasonCode, .calibrationRequired, "no history at all for week 0")
        XCTAssertNil(squat.orderedSetPrescriptions.first?.targetWeight)

        // Real calibration set — the user's own first working weight.
        // Week 0's own target RIR is 3 (the trajectory's first entry):
        // hitting the top of the range (10) AT that target RIR is the
        // classic strong-performance path.
        try logSameExercise(as: squat, in: allWeek0, reps: 10, actualRir: 3, performanceProfile: fixture.performanceProfile, asOf: fixture.startDate)
        try logAdequatePerformanceAndComplete(otherExercises(than: squat, in: allWeek0), performanceProfile: fixture.performanceProfile, asOf: fixture.startDate)

        let squatLastWeight = try XCTUnwrap(squat.loggedSetResults.first?.weight)
        let week1Date = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: fixture.startDate))
        let result = try rollForward(fixture, asOf: week1Date)
        let squatWeek1 = try XCTUnwrap(weekPrescriptions(result).first { $0.sourcePrescriptionTemplate?.id == squat.sourcePrescriptionTemplate?.id })

        XCTAssertEqual(squatWeek1.appliedProgressionReasonCode, .loadIncrease)
        XCTAssertEqual(squatWeek1.orderedSetPrescriptions.first?.targetWeight, squatLastWeight + 2.5)
        XCTAssertEqual(squatWeek1.orderedSetPrescriptions.first?.repRangeLow, 5)
        XCTAssertEqual(squatWeek1.orderedSetPrescriptions.first?.repRangeHigh, 10)
        XCTAssertEqual(squatWeek1.orderedSetPrescriptions.first?.targetRir, 2, "week 2's own trajectory value")
    }

    // MARK: 2 — primary exercise, adequate performance, holds and progresses reps

    func test2_PrimaryExerciseHoldingAndProgressingReps() throws {
        let fixture = try makeFixture()
        let week0Sessions = try materializeWeekZero(fixture)
        let allWeek0 = week0Sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions)
        let squat = try XCTUnwrap(allWeek0.first { $0.exercise?.canonicalName == "Front Squat" })

        // 8 reps @ 3 RIR (week 0's own target) — inside range, on-track, not strong.
        try logSameExercise(as: squat, in: allWeek0, reps: 8, actualRir: 3, performanceProfile: fixture.performanceProfile, asOf: fixture.startDate)
        try logAdequatePerformanceAndComplete(otherExercises(than: squat, in: allWeek0), performanceProfile: fixture.performanceProfile, asOf: fixture.startDate)
        let squatLastWeight = try XCTUnwrap(squat.loggedSetResults.first?.weight)

        let week1Date = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: fixture.startDate))
        let result = try rollForward(fixture, asOf: week1Date)
        let squatWeek1 = try XCTUnwrap(weekPrescriptions(result).first { $0.sourcePrescriptionTemplate?.id == squat.sourcePrescriptionTemplate?.id })

        XCTAssertEqual(squatWeek1.appliedProgressionReasonCode, .repIncrease)
        XCTAssertEqual(squatWeek1.orderedSetPrescriptions.first?.targetWeight, squatLastWeight, "load holds, same weight carried forward")
    }

    // MARK: 3 — a second, unrelated slot reaches its own independent decision

    /// Stage 10R.1 Slice 1A: the real recovered Mesocycle 1 has no
    /// `.accessory`-role slot at all (every real category autoregulates
    /// to a rated set count — `SOURCE_PROGRAM_MANIFEST.md` §3) — Barbell
    /// Curl now resolves for the "Biceps" category (Pull Emphasis),
    /// `.primary` role, same as every other slot. This test's actual
    /// point (an independent slot reaches its own progression decision,
    /// uncoupled from Squat's) is unchanged; only the role/baseline
    /// specifics are updated to match the real content.
    func test3_ASecondSlotReachesItsOwnIndependentProgressionDecision() throws {
        let fixture = try makeFixture()
        let week0Sessions = try materializeWeekZero(fixture)
        let allWeek0 = week0Sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions)
        let curl = try XCTUnwrap(allWeek0.first { $0.exercise?.canonicalName == "Barbell Curl" })
        XCTAssertEqual(curl.sourcePrescriptionTemplate?.slotRole, .primary)
        XCTAssertEqual(curl.sourcePrescriptionTemplate?.pairedSlot?.id, curl.sourcePrescriptionTemplate?.id, "self-attributed, same as every other real Mesocycle 1 slot")
        XCTAssertEqual(curl.orderedSetPrescriptions.count, 3, "Biceps' real recovered Week-1 baseline")

        // Hits the top of the primary 5-10 range at week 0's own target
        // RIR (3) — the same "clear load increase" shape as test 1, on a
        // completely different slot, proving the two decisions never
        // interact.
        try logSameExercise(as: curl, in: allWeek0, reps: 10, actualRir: 3, performanceProfile: fixture.performanceProfile, asOf: fixture.startDate)
        try logAdequatePerformanceAndComplete(otherExercises(than: curl, in: allWeek0), performanceProfile: fixture.performanceProfile, asOf: fixture.startDate)
        let curlLastWeight = try XCTUnwrap(curl.loggedSetResults.first?.weight)

        let week1Date = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: fixture.startDate))
        let result = try rollForward(fixture, asOf: week1Date)
        let curlWeek1 = try XCTUnwrap(weekPrescriptions(result).first { $0.sourcePrescriptionTemplate?.id == curl.sourcePrescriptionTemplate?.id })

        XCTAssertEqual(curlWeek1.appliedProgressionReasonCode, .loadIncrease)
        XCTAssertEqual(curlWeek1.orderedSetPrescriptions.first?.targetWeight, curlLastWeight + 2.5)
    }

    /// Front Squat legitimately trains on more than one day of the real
    /// recovered source rotation ("Push Emphasis"'s solo Quads slot and
    /// "Legs Emphasis"'s first of two Quads slots) — a real, intended
    /// feature of the program, not a test artifact. Tests 4/5 specifically
    /// need ONE clean exposure per decision cycle, so they exercise only
    /// "Push Emphasis"'s own occurrence and deliberately leave every OTHER
    /// day's session unlogged/uncompleted for that week — an unlogged
    /// prescription contributes zero exposures to history
    /// (`DoubleProgressionHistoryResolver`'s own "a skipped workout is NOT
    /// an underperformance exposure" rule), so this cleanly isolates a
    /// single real exposure without needing every session in the week to
    /// be touched.
    private func dayASquat(in prescriptions: [ExercisePrescription]) throws -> ExercisePrescription {
        try XCTUnwrap(prescriptions.first { $0.exercise?.canonicalName == "Front Squat" && $0.workoutBlock?.session?.name == "Push Emphasis" })
    }

    private func dayASiblings(of squat: ExercisePrescription, in prescriptions: [ExercisePrescription]) -> [ExercisePrescription] {
        prescriptions.filter { $0.workoutBlock?.session?.id == squat.workoutBlock?.session?.id && $0.id != squat.id }
    }

    // MARK: 4 — underperformance, first exposure: holds, does not regress

    func test4_UnderperformanceFirstExposureHolds() throws {
        let fixture = try makeFixture()
        let week0Sessions = try materializeWeekZero(fixture)
        let allWeek0 = week0Sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions)
        let squat = try dayASquat(in: allWeek0)

        try logSets(for: squat, reps: 3, actualRir: 3, performanceProfile: fixture.performanceProfile, asOf: fixture.startDate) // below the 5-10 minimum
        try logAdequatePerformanceAndComplete(dayASiblings(of: squat, in: allWeek0), performanceProfile: fixture.performanceProfile, asOf: fixture.startDate)
        try completeAllSessions(for: [squat], asOf: fixture.startDate)
        let squatLastWeight = try XCTUnwrap(squat.loggedSetResults.first?.weight)

        let week1Date = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: fixture.startDate))
        let result = try rollForward(fixture, asOf: week1Date)
        let squatWeek1 = try XCTUnwrap(weekPrescriptions(result).first { $0.sourcePrescriptionTemplate?.id == squat.sourcePrescriptionTemplate?.id })

        XCTAssertEqual(squatWeek1.appliedProgressionReasonCode, .hold)
        XCTAssertEqual(squatWeek1.orderedSetPrescriptions.first?.targetWeight, squatLastWeight, "one miss never regresses")
    }

    // MARK: 5 — repeated underperformance causes regression

    func test5_RepeatedUnderperformanceCausesRegression() throws {
        let fixture = try makeFixture()
        let week0Sessions = try materializeWeekZero(fixture)
        let allWeek0 = week0Sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions)
        let squat = try dayASquat(in: allWeek0)
        try logSets(for: squat, reps: 3, actualRir: 3, performanceProfile: fixture.performanceProfile, asOf: fixture.startDate)
        try logAdequatePerformanceAndComplete(dayASiblings(of: squat, in: allWeek0), performanceProfile: fixture.performanceProfile, asOf: fixture.startDate)
        try completeAllSessions(for: [squat], asOf: fixture.startDate)
        let weekZeroWeight = try XCTUnwrap(squat.loggedSetResults.first?.weight)

        let week1Date = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: fixture.startDate))
        let week1Result = try rollForward(fixture, asOf: week1Date)
        let week1Prescriptions = weekPrescriptions(week1Result)
        let squatWeek1 = try dayASquat(in: week1Prescriptions)
        XCTAssertEqual(squatWeek1.sourcePrescriptionTemplate?.id, squat.sourcePrescriptionTemplate?.id)
        XCTAssertEqual(squatWeek1.appliedProgressionReasonCode, .hold, "first miss — sanity check")

        // Second consecutive miss — still isolated to Day A's own occurrence only.
        try logSets(for: squatWeek1, reps: 3, actualRir: 2, performanceProfile: fixture.performanceProfile, asOf: week1Date)
        try logAdequatePerformanceAndComplete(dayASiblings(of: squatWeek1, in: week1Prescriptions), performanceProfile: fixture.performanceProfile, asOf: week1Date)
        try completeAllSessions(for: [squatWeek1], asOf: week1Date)

        let week2Date = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 14, to: fixture.startDate))
        let week2Result = try rollForward(fixture, asOf: week2Date)
        let squatWeek2 = try dayASquat(in: weekPrescriptions(week2Result))

        XCTAssertEqual(squatWeek2.appliedProgressionReasonCode, .loadDecrease)
        XCTAssertEqual(squatWeek2.orderedSetPrescriptions.first?.targetWeight, weekZeroWeight - 2.5)
    }

    // MARK: 6 — local set-count autoregulation moves only the rated slot

    func test6_LocalSetCountAutoregulationAffectsOnlyTheRatedSlot() throws {
        let fixture = try makeFixture()
        let week0Sessions = try materializeWeekZero(fixture)
        let allWeek0 = week0Sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions)
        // "Barbell Row" (Horizontal Pull) has a uniform Week-1 baseline of
        // 3 on every real occurrence (`SOURCE_PROGRAM_MANIFEST.md` §3),
        // unlike Front Squat/Quads (2 on "Push Emphasis," 3 on "Legs
        // Emphasis") — avoids picking an ambiguous occurrence here.
        let squat = try XCTUnwrap(allWeek0.first { $0.exercise?.canonicalName == "Barbell Row" && $0.workoutBlock?.session?.name == "Push Emphasis" })
        let bench = try XCTUnwrap(allWeek0.first { $0.exercise?.canonicalName == "Barbell Bench Press" && $0.workoutBlock?.session?.name == "Push Emphasis" })
        XCTAssertEqual(squat.orderedSetPrescriptions.count, 3, "primary baseline")

        try logAdequatePerformanceAndComplete(allWeek0, performanceProfile: fixture.performanceProfile, asOf: fixture.startDate)
        // Squat rates itself +1 (felt easy); Bench is left unrated.
        try RecordAutoregulationFeedbackUseCase.recordRating(1, for: squat, modelContext: context)

        let week1Date = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: fixture.startDate))
        let result = try rollForward(fixture, asOf: week1Date)
        let squatWeek1 = try XCTUnwrap(weekPrescriptions(result).first { $0.sourcePrescriptionTemplate?.id == squat.sourcePrescriptionTemplate?.id })
        let benchWeek1 = try XCTUnwrap(weekPrescriptions(result).first { $0.sourcePrescriptionTemplate?.id == bench.sourcePrescriptionTemplate?.id })

        XCTAssertEqual(squatWeek1.orderedSetPrescriptions.count, 4, "3 + 1 rating, bounded within baseline-1...baseline+2")
        XCTAssertEqual(benchWeek1.orderedSetPrescriptions.count, 3, "unrated sibling stays at baseline — the fan-out bug is fixed")
    }

    // MARK: 7 — Week 4 -> Week 5 real, reachable deload

    func test7_WeekFourToWeekFiveRealReachableDeload() throws {
        let fixture = try makeFixture()
        // Materialize weeks 0-3 directly (real materializer, real
        // isDeload: false at each) — fast-forwarding through 4 ordinary
        // weeks' worth of "good enough to keep going" performance so
        // `rollForward` naturally reaches weekIndex 4 next.
        var previousSessions = try materializeWeekZero(fixture)
        var weekStart = fixture.startDate
        for weekIndex in 0..<4 {
            let allPrescriptions = previousSessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions)
            try logAdequatePerformanceAndComplete(allPrescriptions, performanceProfile: fixture.performanceProfile, asOf: weekStart)
            guard weekIndex < 3 else { break }
            weekStart = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: weekStart))
            let result = try rollForward(fixture, asOf: weekStart)
            previousSessions = Array(result.newSessionsByComponent.values.flatMap { $0 })
        }

        // "Barbell Row" again, for the same uniform-baseline reason as
        // test 6 — every occurrence resolves to baseline 3, so no
        // day-scoping is needed to get a deterministic `round(3*0.5)=2`.
        let squat = try XCTUnwrap(previousSessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).first { $0.exercise?.canonicalName == "Barbell Row" })
        XCTAssertEqual(fixture.definition.orderedWeeks[4].isDeload, true, "sanity: the 5th templated week is the deload marker")

        let deloadDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: weekStart))
        let deloadResult = try rollForward(fixture, asOf: deloadDate)
        let squatDeload = try XCTUnwrap(weekPrescriptions(deloadResult).first { $0.sourcePrescriptionTemplate?.id == squat.sourcePrescriptionTemplate?.id })

        XCTAssertEqual(squatDeload.orderedSetPrescriptions.count, 2, "round(3 * 0.5) = 2, primary baseline")
        XCTAssertTrue(squatDeload.orderedSetPrescriptions.allSatisfy { $0.targetRir == 4 }, "explicit deload RIR, never inherited toFailure")
        XCTAssertEqual(squatDeload.orderedSetPrescriptions.first?.repRangeLow, 5, "same rep range as week 4 — exercise continuity")
        XCTAssertEqual(squatDeload.orderedSetPrescriptions.first?.repRangeHigh, 10)

        // MARK: 8 — Week 5 -> next appropriate planning state: the week
        // counter itself advances correctly past the deload, ready for
        // whatever future stage handles a mesocycle boundary/rollover
        // (out of this stage's scope — not a new phase-transition here).
        XCTAssertEqual(ProgramWeekGrouping.nextWeekIndex(for: fixture.instance), 5)
    }
}
