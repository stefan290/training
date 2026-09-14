import XCTest
import SwiftData
@testable import TrainingOS

/// Running Athlete Journey Completion (Vertical Completion V1) — proves
/// the wiring fix for RUN-PACE-1 (Whole Athlete Journey audit): a real
/// athlete can be prompted for, enter, and persist a Threshold Pace
/// calibration, and a real %threshold-prescribed Running block then
/// resolves to an actual, actionable pace through
/// `IntensityPresentation.resolvedLabel` — never a raw, unresolved
/// percentage, never a fabricated pace when calibration is missing.
@MainActor
final class RunningAthleteJourneyCompletionTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var definition: ProgramDefinition!
    var environment: TrainingEnvironment!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
        definition = try RunningProgramGenerator.generate(
            configuration: RunningProgramConfiguration(distance: .fiveK, daysPerWeek: 2),
            provenance: .constructed(reason: "test"), context: context
        )
        environment = TrainingEnvironment(name: "Test Environment", availableEquipment: [])
        context.insert(environment)
    }

    private func makeInstance() -> ProgramInstance {
        let instance = ProgramInstance(ownerUserID: UUID())
        instance.programDefinition = definition
        instance.status = .active
        context.insert(instance)
        return instance
    }

    // MARK: A — the view-model surfaces an outstanding requirement

    func testViewModelSurfacesPendingRunningCalibrationWhenRequired() throws {
        let instance = makeInstance()
        try context.save()
        let viewModel = RunningThresholdCalibrationViewModel()
        viewModel.load(modelContext: context)
        XCTAssertTrue(viewModel.hasPendingCalibration, "an active instance requiring Threshold Pace with none entered must surface as pending")
    }

    func testViewModelHasNoPendingCalibrationOnceEntered() throws {
        let instance = makeInstance()
        RecordRunningThresholdCalibrationUseCase.record(
            thresholdPaceSecondsPerKilometer: 300, for: instance, isScheduledCheckpoint: false, modelContext: context
        )
        try context.save()
        let viewModel = RunningThresholdCalibrationViewModel()
        viewModel.load(modelContext: context)
        XCTAssertFalse(viewModel.hasPendingCalibration, "already-calibrated instance must never re-surface as pending")
    }

    // MARK: B — athlete-entered value persists through the real model

    func testCompletingCalibrationPersistsThroughTheRealCalibrationModel() throws {
        let instance = makeInstance()
        try context.save()
        let viewModel = RunningThresholdCalibrationViewModel()
        viewModel.load(modelContext: context)
        XCTAssertTrue(viewModel.hasPendingCalibration)

        viewModel.enteredMinutesText = "5"
        viewModel.enteredSecondsText = "0"
        XCTAssertTrue(viewModel.isSatisfied)
        viewModel.completeCalibration(modelContext: context)

        XCTAssertFalse(viewModel.hasPendingCalibration, "pending state must clear once persistence succeeds")
        let recorded = RecordRunningThresholdCalibrationUseCase.currentThreshold(for: instance)
        XCTAssertEqual(recorded?.thresholdPaceSecondsPerKilometer, 300, "5:00/km must persist as exactly 300 seconds/km")
    }

    func testIncompleteEntryNeverSatisfiesOrPersists() {
        let instance = makeInstance()
        let viewModel = RunningThresholdCalibrationViewModel()
        viewModel.load(modelContext: context)
        viewModel.enteredMinutesText = ""
        viewModel.enteredSecondsText = ""
        XCTAssertFalse(viewModel.isSatisfied)
        viewModel.completeCalibration(modelContext: context)
        XCTAssertNil(RecordRunningThresholdCalibrationUseCase.currentThreshold(for: instance), "an unsatisfied entry must never be recorded")
    }

    // MARK: C/D/E — ThresholdPaceEngine called through the real production resolution path

    /// Threshold 5:00/km (300s) TEST FIXTURE; 80% of threshold =
    /// 300/0.8 = 375s = 6:15/km — computed exactly, not approximated.
    func testPercentOfThresholdPrescriptionResolvesToTheCorrectPace() {
        let target = IntensityTarget.percentOfReference(BoundedRange(lower: 0.8, upper: 0.8), metric: .thresholdPace)
        let resolved = IntensityPresentation.resolvedLabel(target, thresholdPaceSecondsPerKilometer: 300)
        XCTAssertEqual(resolved, "6:15-6:15/km · 80-80% Threshold Pace")
    }

    /// A real range: 80-85% of a 300s threshold => 375s (80%, slower) and
    /// 352.94s (85%, faster) => sorted ascending (faster pace first):
    /// "5:53-6:15/km".
    func testPercentRangeResolvesCorrectlyBothBounds() {
        let target = IntensityTarget.percentOfReference(BoundedRange(lower: 0.80, upper: 0.85), metric: .thresholdPace)
        let resolved = IntensityPresentation.resolvedLabel(target, thresholdPaceSecondsPerKilometer: 300)
        let expectedFaster = ThresholdPaceEngine.targetPace(thresholdPaceSecondsPerKilometer: 300, percentOfThreshold: 0.85)
        let expectedSlower = ThresholdPaceEngine.targetPace(thresholdPaceSecondsPerKilometer: 300, percentOfThreshold: 0.80)
        XCTAssertEqual(expectedFaster.secondsPerKilometer, 352.94, accuracy: 0.1)
        XCTAssertEqual(expectedSlower.secondsPerKilometer, 375, accuracy: 0.1)
        XCTAssertEqual(resolved, "5:53-6:15/km · 80-85% Threshold Pace")
    }

    // MARK: F — missing calibration never fabricates a pace

    func testMissingCalibrationNeverResolvesToAFabricatedPaceAndShowsHonestPercentage() {
        let target = IntensityTarget.percentOfReference(BoundedRange(lower: 0.80, upper: 0.85), metric: .thresholdPace)
        let resolved = IntensityPresentation.resolvedLabel(target, thresholdPaceSecondsPerKilometer: nil)
        XCTAssertEqual(resolved, "80-85% Threshold Pace", "no calibration must fall back to the honest raw-percentage text, never a guessed pace")
    }

    /// Regression proof for the pre-existing display bug this checkpoint
    /// also fixed: `range.lower`/`range.upper` are stored as fractions
    /// (`0.8`, not `80.0`) — `Int(range.lower)` on `0.8` truncated to `0`,
    /// so every Running block was rendering as the literal "0-0% Threshold
    /// Pace" before this fix, independent of the resolution work.
    func testRawPercentLabelNoLongerTruncatesFractionalStorageToZero() {
        let target = IntensityTarget.percentOfReference(BoundedRange(lower: 0.6993006993006993, upper: 0.6993006993006993), metric: .thresholdPace)
        XCTAssertEqual(IntensityPresentation.label(target), "69-69% Threshold Pace")
    }

    // MARK: G — the real Running source prescription is unchanged

    /// Re-derives the exact same golden-pace assertion already proven in
    /// `RunningProgramMaterializerTests.testMaterializingWithTheCapturedFiveMinuteThresholdReproducesGoldenPaces`
    /// — that test (unmodified by this checkpoint) is the authoritative
    /// regression proof that `RunningProgramGenerator`'s own source output
    /// is unchanged; this test additionally proves the SAME structural
    /// intensity now also resolves correctly through the new presentation
    /// path, tying the two together.
    func testExistingSourcePrescriptionStructureUnchangedAndNowResolvesThroughPresentation() throws {
        let instance = makeInstance()
        RecordRunningThresholdCalibrationUseCase.record(
            thresholdPaceSecondsPerKilometer: 300, for: instance, isScheduledCheckpoint: false, modelContext: context
        )
        let sessions = try RunningProgramMaterializer.materializeAllWeeks(
            definition: definition, instance: instance, startDate: Date(), ownerUserID: instance.ownerUserID,
            environment: environment, context: context
        )
        let tempoBlock = sessions[0].blocks.first { $0.steadyStatePrescription?.sourceLabel == .tempo }
        let intensity = tempoBlock?.steadyStatePrescription?.primaryIntensity
        guard case .percentOfReference(let range, .thresholdPace)? = intensity else {
            return XCTFail("expected an unchanged percentOfReference source intensity")
        }
        XCTAssertEqual(range.lower, 0.9009009009009009, accuracy: 0.0001, "source percent-of-threshold value itself must be unchanged")
        let threshold = RecordRunningThresholdCalibrationUseCase.currentThreshold(for: instance)?.thresholdPaceSecondsPerKilometer
        let resolved = IntensityPresentation.resolvedLabel(intensity, thresholdPaceSecondsPerKilometer: threshold)
        XCTAssertEqual(resolved, "5:33-5:33/km · 90-90% Threshold Pace", "300/0.9009... = 333s/km = 5:33/km, the exact golden pace, now athlete-facing")
    }

    // MARK: H — RunningExecutionOverrideEngine reachability

    /// N/A per this checkpoint's own investigation: `SteadyStateExecutionView`/
    /// `IntervalExecutionView` (read in full) have no existing in-session
    /// "run faster than prescribed" affordance of any kind — no button,
    /// gesture, or control that could be wired to
    /// `RunningExecutionOverrideEngine` without inventing new athlete-
    /// facing UI, which is out of this checkpoint's scope per its own STOP
    /// condition ("if wiring it requires unrelated redesign, STOP and
    /// report why rather than broadening this checkpoint"). Deliberately
    /// NOT wired this pass — see `RUNNING_ATHLETE_JOURNEY_COMPLETION.md`
    /// §7. This test documents that decision rather than forcing a
    /// caller into existence to satisfy the letter of item H.
    func testRunningExecutionOverrideEngineDeliberatelyNotWiredThisCheckpoint() {
        // `RunningExecutionOverrideEngine.evaluateIntensityOverride` remains
        // exactly as tested in isolation by `RunningExecutionOverrideEngineTests`
        // — unchanged, untouched, and still correctly has zero production
        // callers, a deliberate, disclosed FOLLOW-UP rather than a gap
        // this checkpoint silently ignored.
        XCTAssertTrue(true)
    }
}

/// I/J — full production-path scenarios (J3/J5-shaped), mirroring
/// `ConcurrentProgrammingGoldenScenarioTests`'s own established harness
/// exactly (each test file in this codebase keeps its own copy of these
/// private helpers — no cross-file sharing mechanism exists for
/// `private` XCTestCase helpers, matching this codebase's own existing
/// convention).
@MainActor
final class RunningAthleteJourneyCompletionScenarioTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

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

    @discardableResult
    private func makeOnboardedAthlete(
        goalType: GoalType = .muscleGain, trainingDays: Int, allowsDoubles: Bool = false
    ) throws -> (user: User, goal: Goal) {
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        user.profile?.trainingEnvironments = [environment]
        user.profile?.defaultTrainingEnvironment = environment
        let goal = Goal(
            ownerUserID: user.id, primaryType: goalType,
            preferences: GoalPreferences(availableTrainingDaysPerWeek: trainingDays, allowsDoubleSessions: allowsDoubles)
        )
        context.insert(goal)
        user.addGoal(goal)
        try context.save()
        return (user, goal)
    }

    private func loadedViewModel(referenceDate: Date) -> StrategicPlanSelectionViewModel {
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context, referenceDate: referenceDate)
        return viewModel
    }

    private func completeAnyCalibration(goal: Goal, trainingDays: Int, allowsDoubles: Bool = false, asOf: Date) throws {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let environment = goal.user?.profile?.defaultTrainingEnvironment
        guard let phase = goal.plans.first?.orderedPhases.first else { return }
        try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: phase, performanceProfile: goal.user?.performanceProfile,
            availability: UserAvailability(trainingDaysPerWeek: trainingDays, allowsDoubleSessions: allowsDoubles, maxSessionsPerDay: allowsDoubles ? 2 : 1),
            materializationContext: TacticalMaterializationContext(
                equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
                strengthCandidateExercises: exercises, functionalFitnessCandidateExercises: exercises,
                trainingEnvironment: environment
            ),
            asOf: asOf,
            context: context
        )
    }

    private func realRunningComponent(mix: TrainingMix) -> TrainingMixComponent? {
        mix.orderedComponents.first { $0.programmingSystem == .running }
    }

    /// I — J3-shaped: Build Muscle + exactly 2 Running sessions/week
    /// becomes executable end-to-end: real recommendation/build ->
    /// athlete approval -> Running materializes regardless of
    /// calibration -> required Running calibration detected -> athlete
    /// enters it through the real view-model -> Today's own resolution
    /// path (`IntensityPresentation.resolvedLabel`) now shows an actual
    /// pace for a real materialized session -> primary Goal remains
    /// Build Muscle throughout.
    func testJ3_BuildMusclePlusExactTwoRunningSessionsBecomesExecutable() throws {
        let monday = date(2026, 1, 5)
        let (_, goal) = try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: 6)
        let viewModel = loadedViewModel(referenceDate: monday)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.hypertrophy, 4), (.running, 2)]))
        let mix = try XCTUnwrap(viewModel.reviewedMix)

        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))
        try completeAnyCalibration(goal: goal, trainingDays: 6, asOf: monday)

        XCTAssertEqual(goal.primaryType, .muscleGain, "primary Goal must remain unchanged by adding a Running component")

        let runningComponent = try XCTUnwrap(realRunningComponent(mix: mix))
        let runningInstance = try XCTUnwrap(runningComponent.programInstance)
        let runningDefinition = try XCTUnwrap(runningInstance.programDefinition)

        // Running already materialized regardless of calibration.
        XCTAssertFalse(runningInstance.sessions.isEmpty, "Running materializes its whole block regardless of calibration")
        XCTAssertTrue(RequiredRunningCalibrationUseCase.isThresholdCalibrationRequired(for: runningDefinition, instance: runningInstance))

        // Athlete enters their pace through the real view-model.
        let calibrationViewModel = RunningThresholdCalibrationViewModel()
        calibrationViewModel.load(modelContext: context)
        XCTAssertTrue(calibrationViewModel.hasPendingCalibration)
        calibrationViewModel.enteredMinutesText = "5"
        calibrationViewModel.enteredSecondsText = "0"
        calibrationViewModel.completeCalibration(modelContext: context)
        XCTAssertFalse(RequiredRunningCalibrationUseCase.isThresholdCalibrationRequired(for: runningDefinition, instance: runningInstance))

        // A real materialized session now resolves to an actual pace.
        let firstBlockWithIntensity = runningInstance.sessions
            .flatMap(\.blocks)
            .first { $0.steadyStatePrescription?.primaryIntensity != nil }
        let intensity = try XCTUnwrap(firstBlockWithIntensity?.steadyStatePrescription?.primaryIntensity)
        let threshold = RecordRunningThresholdCalibrationUseCase.currentThreshold(for: runningInstance)?.thresholdPaceSecondsPerKilometer
        let resolved = try XCTUnwrap(IntensityPresentation.resolvedLabel(intensity, thresholdPaceSecondsPerKilometer: threshold))
        XCTAssertTrue(resolved.contains("/km"), "must contain an actual resolved pace, not only a raw percentage — got: \(resolved)")
    }

    /// J — J5-shaped: Hypertrophy + Functional Fitness + exactly 2
    /// Running sessions/week — the Running component specifically
    /// becomes executable without the exact TrainingMix changing.
    func testJ5_HybridMixRunningComponentBecomesExecutableWithoutChangingTheMix() throws {
        let monday = date(2026, 1, 5)
        // Same exact composition already proven feasible by
        // `ConcurrentProgrammingGoldenScenarioTests.testG1_...` (3H + 1FF +
        // 2Running, trainingDays: 6) — this test is not re-proving
        // scheduling feasibility, only that the Running component within
        // an already-feasible hybrid mix resolves an actual pace.
        let (_, _) = try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: 6)
        let viewModel = loadedViewModel(referenceDate: monday)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.hypertrophy, 3), (.functionalFitness, 1), (.running, 2)]))
        let mix = try XCTUnwrap(viewModel.reviewedMix)
        let componentCountBefore = mix.orderedComponents.count
        let systemsBefore = Set(mix.orderedComponents.compactMap(\.programmingSystem))

        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))

        // Exact mix unchanged by anything this checkpoint touches.
        XCTAssertEqual(mix.orderedComponents.count, componentCountBefore, "no component may appear or disappear")
        XCTAssertEqual(Set(mix.orderedComponents.compactMap(\.programmingSystem)), systemsBefore)

        let runningComponent = try XCTUnwrap(realRunningComponent(mix: mix))
        let runningInstance = try XCTUnwrap(runningComponent.programInstance)
        let runningDefinition = try XCTUnwrap(runningInstance.programDefinition)
        XCTAssertFalse(runningInstance.sessions.isEmpty)
        XCTAssertTrue(RequiredRunningCalibrationUseCase.isThresholdCalibrationRequired(for: runningDefinition, instance: runningInstance))

        RecordRunningThresholdCalibrationUseCase.record(
            thresholdPaceSecondsPerKilometer: 300, for: runningInstance, isScheduledCheckpoint: false, modelContext: context
        )
        XCTAssertFalse(RequiredRunningCalibrationUseCase.isThresholdCalibrationRequired(for: runningDefinition, instance: runningInstance))

        let firstBlockWithIntensity = runningInstance.sessions
            .flatMap(\.blocks)
            .first { $0.steadyStatePrescription?.primaryIntensity != nil }
        let intensity = try XCTUnwrap(firstBlockWithIntensity?.steadyStatePrescription?.primaryIntensity)
        let resolved = try XCTUnwrap(IntensityPresentation.resolvedLabel(intensity, thresholdPaceSecondsPerKilometer: 300))
        XCTAssertTrue(resolved.contains("/km"), "Running component must resolve to an actual pace within the hybrid mix — got: \(resolved)")

        // Exact mix still unchanged after resolving Running's own pace.
        XCTAssertEqual(mix.orderedComponents.count, componentCountBefore)
        XCTAssertEqual(Set(mix.orderedComponents.compactMap(\.programmingSystem)), systemsBefore)
    }
}
