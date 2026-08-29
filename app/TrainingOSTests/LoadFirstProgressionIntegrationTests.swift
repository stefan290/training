import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 10R.5: real production-path integration tests proving
/// `LoadFirstOverlayEngine`/`LoadFirstExposureResolver` are correctly
/// wired through `StrengthExecutionViewModel.effectiveTargetWeight` —
/// SOURCE and LOAD_FOCUSED modes coexist for the identical source
/// program, `SetPrescription.targetWeight` is never mutated, calibration
/// is never auto-changed, and a completed exposure's provenance is
/// frozen, never subject to later recomputation drift.
@MainActor
final class LoadFirstProgressionIntegrationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()
    let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)
    let startDate = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func availability() -> UserAvailability {
        UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1)
    }

    private func materializationContext() throws -> TacticalMaterializationContext {
        TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: try context.fetch(FetchDescriptor<Exercise>()))
    }

    private struct Fixture {
        var user: User
        var phase: TrainingPhase
        var instance: ProgramInstance
    }

    /// Builds a real, calibrated Mesocycle-1 (Basic Hypertrophy) instance
    /// through the real production path, with a real `User`/`UserProfile`
    /// so `progressionStyleOverride`/`preferredProgressionStyle` are both
    /// reachable exactly as `StrengthExecutionViewModel` reads them.
    @discardableResult
    private func makeCalibratedInstance(rmKilograms: Double = 100, instanceOverride: ProgressionStyle? = nil, profileDefault: ProgressionStyle = .loadFocused) throws -> Fixture {
        // A test that builds two coexisting instances (e.g. one SOURCE,
        // one LOAD_FOCUSED) calls this helper twice — the catalog must
        // only ever be inserted once per test, or duplicate
        // `canonicalName`-unique Exercise rows fail SwiftData validation.
        if try context.fetch(FetchDescriptor<Exercise>()).isEmpty {
            _ = ExerciseCatalog.resolveOrInsert(context: context)
        }
        let user = User(displayName: "Test User")
        context.insert(user)
        let profile = UserProfile(preferredProgressionStyle: profileDefault)
        context.insert(profile)
        user.attachProfile(profile)

        let goal = Goal(ownerUserID: ownerUserID, primaryType: .muscleGain)
        context.insert(goal)
        let plan = TrainingPlan(status: .active)
        context.insert(plan)
        goal.addPlan(plan)

        let phase = TrainingPhase(type: .muscleGain, startDate: startDate, priorityRule: .strength, status: .active)
        context.insert(phase)
        plan.addPhase(phase)

        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 3, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: context
        )
        let instance = ProgramInstance(ownerUserID: ownerUserID, startDate: startDate, status: .active, priority: .primary, progressionStyleOverride: instanceOverride)
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

        ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: try context.fetch(FetchDescriptor<Exercise>()))

        for requirement in RequiredSourceCalibrationsUseCase.stillRequired(for: definition, instance: instance) {
            RecordSourceRMCalibrationUseCase.record(exercise: requirement.exercise, rmType: requirement.rmType, kilograms: rmKilograms, for: instance, modelContext: context)
        }
        try context.save()

        _ = try StartPhaseUseCase.materializeOnceCalibrationComplete(
            component: component, instance: instance, phase: phase, mix: mix, asOf: startDate,
            ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: try materializationContext(), context: context
        )
        return Fixture(user: user, phase: phase, instance: instance)
    }

    private func pushDayHorizontalPush(in instance: ProgramInstance, weekIndex: Int) throws -> ExercisePrescription {
        let session = try XCTUnwrap(ProgramWeekGrouping.realSessions(in: instance, forWeek: weekIndex).first { $0.name == "Push Emphasis" })
        return try XCTUnwrap(session.orderedBlocks.flatMap(\.orderedPrescriptions).first { $0.exercise?.canonicalName == "Barbell Bench Press" })
    }

    private func logExposure(_ prescription: ExercisePrescription, actualRirPerSet: [Int]) throws {
        for (index, setPrescription) in prescription.orderedSetPrescriptions.enumerated() {
            let actualRir = index < actualRirPerSet.count ? actualRirPerSet[index] : actualRirPerSet.last ?? 0
            _ = try LogSetUseCase.logSet(
                setIndex: setPrescription.sortIndex, weight: setPrescription.targetWeight ?? 50, reps: 8,
                targetRir: setPrescription.targetRir, actualRir: actualRir, prBand: nil, scoringDirection: .higherIsBetter,
                context: .rx, setPrescription: setPrescription, exercisePrescription: prescription,
                exercise: try XCTUnwrap(prescription.exercise), performanceProfile: try performanceProfile(),
                completedAt: Date(), modelContext: context
            )
        }
    }

    private func performanceProfile() throws -> PerformanceProfile {
        if let existing = try context.fetch(FetchDescriptor<PerformanceProfile>()).first { return existing }
        let profile = PerformanceProfile()
        context.insert(profile)
        return profile
    }

    /// Marks every real Session in `weekIndex` terminal — `loggedSession`
    /// (if given) via a real `CompleteSessionUseCase.complete` (it has
    /// genuine logged sets), every other session via a Locked-Decision-3
    /// skip (no fabricated evidence) — so the week is actually terminal
    /// and `AdvanceTacticalWeekUseCase` can really roll it forward.
    private func completeWeek(in instance: ProgramInstance, weekIndex: Int, loggedSession: Session? = nil) throws {
        for session in ProgramWeekGrouping.realSessions(in: instance, forWeek: weekIndex) {
            if let loggedSession, session.id == loggedSession.id {
                _ = try CompleteSessionUseCase.complete(session, context: .full, asOf: Date(), modelContext: context)
            } else {
                try ChangeSessionStatusUseCase.skip(session, modelContext: context)
            }
        }
    }

    private func advance(_ fixture: Fixture, afterWeekIndex weekIndex: Int) throws {
        let asOf = Calendar.current.date(byAdding: .day, value: (weekIndex + 1) * 7, to: startDate) ?? startDate
        _ = try AdvanceTacticalWeekUseCase.advance(
            phase: fixture.phase, asOf: asOf, ownerUserID: ownerUserID, performanceProfile: nil,
            availability: availability(), materializationContext: try materializationContext(), context: context
        )
    }

    // MARK: 18 — SOURCE and LOAD_FOCUSED coexist for the identical source program

    func testSourceModeNeverComputesAnOverlayRecommendation() throws {
        let fixture = try makeCalibratedInstance(instanceOverride: .source)
        let prescription = try pushDayHorizontalPush(in: fixture.instance, weekIndex: 0)
        let viewModel = StrengthExecutionViewModel(block: try XCTUnwrap(prescription.workoutBlock))

        let effective = viewModel.effectiveTargetWeight(modelContext: context)
        XCTAssertEqual(effective, prescription.orderedSetPrescriptions.first?.targetWeight)
        XCTAssertNil(prescription.appliedLoadOverlayReasonCode, "SOURCE mode never computes or freezes an overlay recommendation")
        XCTAssertNil(prescription.loadOverlayRecommendedWeight)
    }

    func testLoadFocusedModeWithNoHistoryHoldsAtSourceWithInsufficientData() throws {
        let fixture = try makeCalibratedInstance(instanceOverride: .loadFocused)
        let prescription = try pushDayHorizontalPush(in: fixture.instance, weekIndex: 0)
        let viewModel = StrengthExecutionViewModel(block: try XCTUnwrap(prescription.workoutBlock))

        let sourceWeight = try XCTUnwrap(prescription.orderedSetPrescriptions.first?.targetWeight)
        let effective = viewModel.effectiveTargetWeight(modelContext: context)
        XCTAssertEqual(effective, sourceWeight, "Week 1 has no prior exposure — holds at source")
        XCTAssertEqual(prescription.appliedLoadOverlayReasonCode, .holdInsufficientData)
    }

    /// Test 16/17/18 together: identical source program, two instances,
    /// one in each mode — proves the source's own `targetWeight` is
    /// byte-identical in both, while the EFFECTIVE recommendation only
    /// ever diverges in LOAD_FOCUSED mode after real easy performance.
    func testSourceAndLoadFocusedCoexistAndSourceWeightNeverMutated() throws {
        let sourceFixture = try makeCalibratedInstance(instanceOverride: .source)
        let loadFocusedFixture = try makeCalibratedInstance(instanceOverride: .loadFocused)

        let sourcePrescriptionWeek1 = try pushDayHorizontalPush(in: sourceFixture.instance, weekIndex: 0)
        let loadFocusedPrescriptionWeek1 = try pushDayHorizontalPush(in: loadFocusedFixture.instance, weekIndex: 0)
        XCTAssertEqual(sourcePrescriptionWeek1.orderedSetPrescriptions.first?.targetWeight, loadFocusedPrescriptionWeek1.orderedSetPrescriptions.first?.targetWeight, "identical source program, identical Week 1 source load regardless of mode")

        // Log a clearly-easy Week 1 exposure (target RIR 3, actual RIR 5) for the load-focused instance only.
        try logExposure(loadFocusedPrescriptionWeek1, actualRirPerSet: [5, 5, 5])
        try completeWeek(in: loadFocusedFixture.instance, weekIndex: 0, loggedSession: loadFocusedPrescriptionWeek1.workoutBlock?.session)
        try advance(loadFocusedFixture, afterWeekIndex: 0)

        // Source instance: skip the whole week (no evidence either way) and advance too, for a fair comparison at Week 2.
        try completeWeek(in: sourceFixture.instance, weekIndex: 0)
        try advance(sourceFixture, afterWeekIndex: 0)

        let sourcePrescriptionWeek2 = try pushDayHorizontalPush(in: sourceFixture.instance, weekIndex: 1)
        let loadFocusedPrescriptionWeek2 = try pushDayHorizontalPush(in: loadFocusedFixture.instance, weekIndex: 1)
        let sourceWeek2TargetWeight = try XCTUnwrap(sourcePrescriptionWeek2.orderedSetPrescriptions.first?.targetWeight)
        let loadFocusedWeek2TargetWeight = try XCTUnwrap(loadFocusedPrescriptionWeek2.orderedSetPrescriptions.first?.targetWeight)
        // Both instances' SOURCE schedule is identical (same source program) — proves the overlay never mutates SetPrescription.targetWeight anywhere, in either instance.
        XCTAssertEqual(sourceWeek2TargetWeight, loadFocusedWeek2TargetWeight, accuracy: 0.001, "source's own Week 2 target weight is identical in both instances — never mutated by the overlay")

        let sourceViewModel = StrengthExecutionViewModel(block: try XCTUnwrap(sourcePrescriptionWeek2.workoutBlock))
        let sourceEffective = sourceViewModel.effectiveTargetWeight(modelContext: context)
        XCTAssertEqual(sourceEffective, sourceWeek2TargetWeight, "SOURCE mode: effective always equals source, regardless of what LOAD_FOCUSED's sibling instance did")

        let loadFocusedViewModel = StrengthExecutionViewModel(block: try XCTUnwrap(loadFocusedPrescriptionWeek2.workoutBlock))
        let loadFocusedEffective = loadFocusedViewModel.effectiveTargetWeight(modelContext: context)
        XCTAssertEqual(loadFocusedEffective ?? -1, loadFocusedWeek2TargetWeight + equipment.smallestIncrementKg, accuracy: 0.001, "LOAD_FOCUSED mode: one increment above source's own Week 2 value, from the real easy Week 1 exposure")
        XCTAssertEqual(loadFocusedPrescriptionWeek2.appliedLoadOverlayReasonCode, .loadIncreaseEasyPerformance)
    }

    // MARK: 14 — calibration never automatically changed

    func testCalibrationNeverAutomaticallyChangedByTheOverlay() throws {
        let fixture = try makeCalibratedInstance(rmKilograms: 100, instanceOverride: .loadFocused)
        let definition = try XCTUnwrap(fixture.instance.programDefinition)
        let exercise = try XCTUnwrap(try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.canonicalName == "Barbell Bench Press" })).first)
        let calibrationBefore = fixture.instance.sourceRMCalibration(for: exercise, rmType: .rm10)?.kilograms

        let prescription = try pushDayHorizontalPush(in: fixture.instance, weekIndex: 0)
        try logExposure(prescription, actualRirPerSet: [5, 5, 5])
        try completeWeek(in: fixture.instance, weekIndex: 0, loggedSession: prescription.workoutBlock?.session)
        try advance(fixture, afterWeekIndex: 0)
        let week2Prescription = try pushDayHorizontalPush(in: fixture.instance, weekIndex: 1)
        let viewModel = StrengthExecutionViewModel(block: try XCTUnwrap(week2Prescription.workoutBlock))
        _ = viewModel.effectiveTargetWeight(modelContext: context) // triggers a real overlay computation

        let calibrationAfter = fixture.instance.sourceRMCalibration(for: exercise, rmType: .rm10)?.kilograms
        XCTAssertEqual(calibrationBefore, calibrationAfter, "the overlay must never touch SourceRMCalibration, regardless of how much it adjusts the effective load")
        XCTAssertEqual(calibrationAfter, 100)
        _ = definition
    }

    // MARK: 20 — completed historical exposure retains correct, frozen provenance

    /// Proves D-10R5-19 for real: NEW evidence that accumulates AFTER an
    /// exposure was already shown/frozen must never retroactively change
    /// that already-completed exposure's own recorded recommendation —
    /// not by manually corrupting the frozen field (trivially "whatever
    /// is stored is returned," which proves nothing), but by genuinely
    /// advancing to a real, dramatically different Week 2 exposure and
    /// confirming Week 1's own frozen record is untouched by it.
    func testCompletedExposureProvenanceIsFrozenNotRecomputed() throws {
        let fixture = try makeCalibratedInstance(instanceOverride: .loadFocused)
        let week1Prescription = try pushDayHorizontalPush(in: fixture.instance, weekIndex: 0)
        let week1ViewModel = StrengthExecutionViewModel(block: try XCTUnwrap(week1Prescription.workoutBlock))

        let week1Effective = week1ViewModel.effectiveTargetWeight(modelContext: context)
        XCTAssertEqual(week1Prescription.appliedLoadOverlayReasonCode, .holdInsufficientData, "precondition: Week 1 has no prior history")

        // Advance to Week 2 with a real, dramatically easy exposure —
        // genuinely NEW evidence that did not exist when Week 1's own
        // recommendation was frozen.
        try logExposure(week1Prescription, actualRirPerSet: [5, 5, 5])
        try completeWeek(in: fixture.instance, weekIndex: 0, loggedSession: week1Prescription.workoutBlock?.session)
        try advance(fixture, afterWeekIndex: 0)
        let week2Prescription = try pushDayHorizontalPush(in: fixture.instance, weekIndex: 1)
        let week2ViewModel = StrengthExecutionViewModel(block: try XCTUnwrap(week2Prescription.workoutBlock))
        _ = week2ViewModel.effectiveTargetWeight(modelContext: context)
        XCTAssertEqual(week2Prescription.appliedLoadOverlayReasonCode, .loadIncreaseEasyPerformance, "precondition: Week 2 really did compute a different, new recommendation")

        // Week 1's own already-frozen record must be completely unaffected.
        XCTAssertEqual(week1Prescription.loadOverlayRecommendedWeight, week1Effective, "Week 1's frozen recommendation is untouched by Week 2's later, different evidence")
        XCTAssertEqual(week1Prescription.appliedLoadOverlayReasonCode, .holdInsufficientData, "Week 1's frozen reason code is untouched")

        // A fresh ViewModel re-reading Week 1 again gets the same frozen answer, not a recompute.
        let week1ViewModelAgain = StrengthExecutionViewModel(block: try XCTUnwrap(week1Prescription.workoutBlock))
        XCTAssertEqual(week1ViewModelAgain.effectiveTargetWeight(modelContext: context), week1Effective)
    }

    // MARK: Feature-mode ownership (D-10R5-15/16)

    func testProfileDefaultIsLoadFocusedWhenNoOverrideIsSet() throws {
        let fixture = try makeCalibratedInstance(instanceOverride: nil, profileDefault: .loadFocused)
        XCTAssertEqual(fixture.instance.effectiveProgressionStyle(userProfile: fixture.user.profile), .loadFocused)
    }

    func testInstanceOverrideAlwaysWinsOverProfileDefault() throws {
        let fixture = try makeCalibratedInstance(instanceOverride: .source, profileDefault: .loadFocused)
        XCTAssertEqual(fixture.instance.effectiveProgressionStyle(userProfile: fixture.user.profile), .source, "instance override beats the profile default")

        let reversed = try makeCalibratedInstance(instanceOverride: .loadFocused, profileDefault: .source)
        XCTAssertEqual(reversed.instance.effectiveProgressionStyle(userProfile: reversed.user.profile), .loadFocused, "instance override beats the profile default in the other direction too")
    }
}
