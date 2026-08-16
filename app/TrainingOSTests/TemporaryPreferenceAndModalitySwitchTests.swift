import XCTest
import SwiftData
@testable import TrainingOS

/// `ADHERENCE_AWARE_PLANNING.md` §2/§2a — temporary preference detection
/// (pure) plus the modality-switching proof cases (§48): switching to
/// Functional Fitness/Running/Cycling/Powerlifting must never reset the
/// annual roadmap or any `PerformanceProfile`.
final class TemporaryPreferenceEvaluatorTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar.current.date(from: components)!
    }

    func testStableMixWithNoValidUntilIsNeverExpired() {
        let mix = TrainingMix(kind: .selected, name: "Stable")
        XCTAssertFalse(TemporaryPreferenceEvaluator.isExpired(mix, asOf: date(2026, 6, 1)))
    }

    func testMixExpiresExactlyAtItsValidUntilDate() {
        let mix = TrainingMix(kind: .selected, name: "Temp", validFrom: date(2026, 5, 1), validUntil: date(2026, 6, 1))
        XCTAssertFalse(TemporaryPreferenceEvaluator.isExpired(mix, asOf: date(2026, 5, 31)))
        XCTAssertTrue(TemporaryPreferenceEvaluator.isExpired(mix, asOf: date(2026, 6, 1)))
    }

    func testMaterialityThresholdFiresAtHalfThePhaseTypicalDuration() {
        // muscleGain's typical is 12 weeks -> half is 6 weeks.
        let phaseDuration = PhaseDurationDefaults.range(for: .muscleGain)
        let mix = TrainingMix(kind: .selected, name: "Temp", validFrom: date(2026, 1, 1), validUntil: date(2026, 12, 1))

        XCTAssertFalse(TemporaryPreferenceEvaluator.hasCrossedMaterialityThreshold(
            mix, asOf: date(2026, 2, 1), consecutiveRenewals: 0, enclosingPhaseDuration: phaseDuration
        ))
        XCTAssertTrue(TemporaryPreferenceEvaluator.hasCrossedMaterialityThreshold(
            mix, asOf: date(2026, 2, 15), consecutiveRenewals: 0, enclosingPhaseDuration: phaseDuration
        ))
    }

    func testMaterialityThresholdFiresAfterMoreThanOneConsecutiveRenewalRegardlessOfElapsedTime() {
        let phaseDuration = PhaseDurationDefaults.range(for: .muscleGain)
        let mix = TrainingMix(kind: .selected, name: "Temp", validFrom: date(2026, 1, 1), validUntil: date(2026, 1, 8))

        XCTAssertFalse(TemporaryPreferenceEvaluator.hasCrossedMaterialityThreshold(
            mix, asOf: date(2026, 1, 5), consecutiveRenewals: 1, enclosingPhaseDuration: phaseDuration
        ))
        XCTAssertTrue(TemporaryPreferenceEvaluator.hasCrossedMaterialityThreshold(
            mix, asOf: date(2026, 1, 5), consecutiveRenewals: 2, enclosingPhaseDuration: phaseDuration
        ))
    }

    func testMaterialityDoesNotApplyToAMixThatWasNeverTemporary() {
        let phaseDuration = PhaseDurationDefaults.range(for: .muscleGain)
        let mix = TrainingMix(kind: .selected, name: "AlwaysStable")
        XCTAssertFalse(TemporaryPreferenceEvaluator.hasCrossedMaterialityThreshold(
            mix, asOf: date(2027, 1, 1), consecutiveRenewals: 0, enclosingPhaseDuration: phaseDuration
        ))
    }
}

@MainActor
final class ModalitySwitchProofTests: XCTestCase {
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

    /// Builds a fully-realized annual Muscle Gain roadmap: a real
    /// accepted `TrainingPlan`/active `TrainingPhase` with a stable
    /// `.selected` Hypertrophy mix, plus real `PerformanceProfile`
    /// history — exactly the fixture every proof case below must leave
    /// untouched.
    private func makeAnnualRoadmapWithHistory() throws -> (goal: Goal, plan: TrainingPlan, phase: TrainingPhase, profile: PerformanceProfile) {
        let goal = Goal(ownerUserID: UUID(), primaryType: .muscleGain, targetDate: date(2027, 8, 14), createdAt: date(2026, 8, 14))
        context.insert(goal)
        let plan = TrainingPlan(status: .active, createdAt: date(2026, 8, 14))
        context.insert(plan)
        goal.addPlan(plan)

        let phase = TrainingPhase(type: .muscleGain, startDate: date(2026, 8, 14), endDate: date(2027, 8, 14), priorityRule: .strength, status: .active)
        context.insert(phase)
        plan.addPhase(phase)

        let stableMix = TrainingMix(kind: .selected, name: "Hypertrophy Focus")
        context.insert(stableMix)
        stableMix.addComponent(TrainingMixComponent(label: "Hypertrophy", programmingSystem: .hypertrophy, priority: .primary, frequency: SessionFrequency(target: 5)))
        phase.addTrainingMix(stableMix)

        let profile = PerformanceProfile()
        context.insert(profile)
        let exercise = Exercise(canonicalName: "Barbell Back Squat", modality: .hypertrophy, equipment: "barbell", movementPattern: "squat")
        context.insert(exercise)
        let exerciseProfile = ExercisePerformanceProfile(estimatedOneRepMax: 140, confidence: 0.9)
        exerciseProfile.exercise = exercise
        context.insert(exerciseProfile)
        profile.addExerciseProfile(exerciseProfile)

        try context.save()
        return (goal, plan, phase, profile)
    }

    private func temporaryMix(_ name: String, system: ProgrammingSystemKind, from: Date, until: Date) -> TrainingMix {
        let mix = TrainingMix(kind: .selected, name: name, validFrom: from, validUntil: until)
        mix.addComponent(TrainingMixComponent(label: name, programmingSystem: system, priority: .primary, frequency: SessionFrequency(target: 3)))
        return mix
    }

    private func assertRoadmapAndHistoryUntouched(
        goal: Goal, plan: TrainingPlan, phase: TrainingPhase, profile: PerformanceProfile, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(goal.primaryType, .muscleGain, file: file, line: line)
        XCTAssertEqual(goal.targetDate, date(2027, 8, 14), file: file, line: line)
        XCTAssertEqual(plan.orderedPhases.count, 1, file: file, line: line)
        XCTAssertEqual(phase.type, .muscleGain, file: file, line: line)
        XCTAssertEqual(phase.startDate, date(2026, 8, 14), file: file, line: line)
        XCTAssertEqual(phase.endDate, date(2027, 8, 14), file: file, line: line)
        XCTAssertEqual(profile.exerciseProfiles.count, 1, file: file, line: line)
        XCTAssertEqual(profile.exerciseProfiles.first?.confidence, 0.9, file: file, line: line)
        XCTAssertEqual(profile.exerciseProfiles.first?.estimatedOneRepMax, 140, file: file, line: line)
    }

    private func runSwitchProof(system: ProgrammingSystemKind, label: String) throws {
        let (goal, plan, phase, profile) = try makeAnnualRoadmapWithHistory()
        let originalMix = try XCTUnwrap(phase.trainingMixes.first)
        let switchDate = date(2026, 10, 1)
        let newMix = temporaryMix(label, system: system, from: switchDate, until: date(2026, 11, 1))

        SwitchTrainingModalityUseCase.apply(
            newMix, to: phase, asOf: switchDate, reasonCode: .temporaryPreferenceApplied, source: .userSelected,
            explanation: "Switched to \(label) for 4 weeks.", context: context
        )
        try context.save()

        XCTAssertEqual(phase.activeTrainingMix(asOf: switchDate)?.id, newMix.id)
        XCTAssertEqual(phase.activeTrainingMix(asOf: date(2026, 10, 15))?.id, newMix.id)
        XCTAssertEqual(originalMix.validUntil, switchDate, "the prior mix is closed, never deleted")
        XCTAssertEqual(phase.trainingMixes.count, 2, "history retained, nothing removed")
        assertRoadmapAndHistoryUntouched(goal: goal, plan: plan, phase: phase, profile: profile)
    }

    func testSwitchingToFunctionalFitnessNeverResetsAnnualPlanOrPerformanceHistory() throws {
        try runSwitchProof(system: .functionalFitness, label: "Functional Fitness")
    }

    func testSwitchingToRunningNeverResetsAnnualPlanOrPerformanceHistory() throws {
        try runSwitchProof(system: .steadyState, label: "Running")
    }

    func testSwitchingToCyclingNeverResetsAnnualPlanOrPerformanceHistory() throws {
        try runSwitchProof(system: .steadyState, label: "Cycling")
    }

    func testSwitchingToPowerliftingNeverResetsAnnualPlanOrPerformanceHistory() throws {
        try runSwitchProof(system: .powerlifting, label: "Powerlifting")
    }

    // MARK: - The 3-option resolution paths (§2)

    func testContinuingATemporaryMixCreatesANewStableMixAndPreservesTheOldOneAsHistory() throws {
        let (_, _, phase, _) = try makeAnnualRoadmapWithHistory()
        let switchDate = date(2026, 10, 1)
        let tempMix = temporaryMix("Functional Fitness", system: .functionalFitness, from: switchDate, until: date(2026, 11, 1))
        SwitchTrainingModalityUseCase.apply(
            tempMix, to: phase, asOf: switchDate, reasonCode: .temporaryPreferenceApplied, source: .userSelected,
            explanation: "temporary", context: context
        )

        let expiryDate = date(2026, 11, 1)
        let continuedMix = TrainingMix(kind: .selected, name: "Functional Fitness (continued)")
        continuedMix.addComponent(TrainingMixComponent(label: "Functional Fitness", programmingSystem: .functionalFitness, priority: .primary, frequency: SessionFrequency(target: 3)))
        SwitchTrainingModalityUseCase.apply(
            continuedMix, to: phase, asOf: expiryDate, reasonCode: .temporaryPreferenceConvertedToPhase, source: .userSelected,
            explanation: "made stable", context: context
        )
        try context.save()

        XCTAssertNil(continuedMix.validUntil, "the promoted mix is now stable, no end date")
        XCTAssertEqual(tempMix.validUntil, expiryDate, "the original temporary mix is closed, never deleted")
        XCTAssertEqual(phase.activeTrainingMix(asOf: expiryDate)?.id, continuedMix.id)
        XCTAssertEqual(phase.trainingMixes.count, 3, "original stable + temporary + continued, all retained")
    }

    func testReturningToRecommendedAfterExpiryClosesTheTemporaryMixAndActivatesANewSelectedMix() throws {
        let (_, _, phase, _) = try makeAnnualRoadmapWithHistory()
        let switchDate = date(2026, 10, 1)
        let expiryDate = date(2026, 11, 1)
        let tempMix = temporaryMix("Functional Fitness", system: .functionalFitness, from: switchDate, until: expiryDate)
        SwitchTrainingModalityUseCase.apply(
            tempMix, to: phase, asOf: switchDate, reasonCode: .temporaryPreferenceApplied, source: .userSelected,
            explanation: "temporary", context: context
        )

        // Recommended composition restored as a fresh, currently-active `.selected` mix.
        let revertedMix = TrainingMix(kind: .selected, name: "Hypertrophy Focus (resumed)")
        revertedMix.addComponent(TrainingMixComponent(label: "Hypertrophy", programmingSystem: .hypertrophy, priority: .primary, frequency: SessionFrequency(target: 5)))
        SwitchTrainingModalityUseCase.apply(
            revertedMix, to: phase, asOf: expiryDate, reasonCode: .temporaryPreferenceExpired, source: .systemRecommended,
            explanation: "reverted", context: context
        )
        try context.save()

        XCTAssertEqual(tempMix.validUntil, expiryDate)
        XCTAssertEqual(phase.activeTrainingMix(asOf: expiryDate)?.id, revertedMix.id)
        XCTAssertNil(revertedMix.validUntil)
    }
}
