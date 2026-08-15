import XCTest
@testable import TrainingOS

/// Engine-level regression fixtures for `SteadyStateProgressionEngine` —
/// the steady-state sibling of `StrengthProgressionEngineTests`. Every
/// fixture is CONSTRUCTED/TRAININGOS_DESIGNED and precomputed by hand
/// before being asserted, matching this codebase's established discipline
/// for avoiding arithmetic mistakes in test code itself.
final class SteadyStateProgressionEngineTests: XCTestCase {
    // MARK: - §46: same system, four modalities, no strength dummy values

    /// Zone 2 Bike/Run/Row/SkiErg, 45 minutes — proves one
    /// `SteadyStateProgressionEngine` resolves all four identically, and
    /// that nothing in the resolved output requires reps/sets/RIR/pace
    /// (Stage 4C §3's explicit "does not need" example).
    func testZone2FortyFiveMinutesResolvesIdenticallyAcrossAllFourModalities() {
        let rules = SteadyStateProgressionRules(progressionDimension: .none, weekOneDurationSeconds: 2700)
        for activityType in [ActivityType.cycling, .running, .rowing, .skiErg] {
            let duration = SteadyStateProgressionEngine.resolveDuration(rules: rules, weekIndex: 0, isRecoveryWeek: false)
            let intensity = SteadyStateProgressionEngine.resolveIntensity(rules: rules, weekIndex: 0, isRecoveryWeek: false, staticPrimaryIntensity: .heartRateZone(.two))
            XCTAssertEqual(duration.durationSeconds, 2700, "\(activityType) should resolve to 45 minutes")
            XCTAssertEqual(intensity.intensity, .heartRateZone(.two), "\(activityType) should resolve to Zone 2")
            XCTAssertEqual(duration.reasonCode, .noProgressionConfigured)
            XCTAssertEqual(intensity.reasonCode, .staticIntensity)
        }
    }

    func testDurationProgressionAdvancesByWeekAndFallsBackToWeekOneAtWeekZero() {
        let rules = SteadyStateProgressionRules(progressionDimension: .duration, weekOneDurationSeconds: 2700, laterWeekDurationSeconds: [3000, 3300, 3600])
        XCTAssertEqual(SteadyStateProgressionEngine.resolveDuration(rules: rules, weekIndex: 0, isRecoveryWeek: false).durationSeconds, 2700)
        XCTAssertEqual(SteadyStateProgressionEngine.resolveDuration(rules: rules, weekIndex: 1, isRecoveryWeek: false).durationSeconds, 3000)
        XCTAssertEqual(SteadyStateProgressionEngine.resolveDuration(rules: rules, weekIndex: 2, isRecoveryWeek: false).durationSeconds, 3300)
        XCTAssertEqual(SteadyStateProgressionEngine.resolveDuration(rules: rules, weekIndex: 3, isRecoveryWeek: false).durationSeconds, 3600)
        XCTAssertEqual(SteadyStateProgressionEngine.resolveDuration(rules: rules, weekIndex: 1, isRecoveryWeek: false).reasonCode, .durationProgressed)
    }

    /// §7: "do not assume duration always progresses" — a distance-
    /// progressing rule's duration stays flat at week one's value across
    /// every week, unprogressed.
    func testDurationDoesNotProgressWhenTheChosenDimensionIsDistance() {
        let rules = SteadyStateProgressionRules(progressionDimension: .distance, weekOneDurationSeconds: 2700, weekOneDistanceMeters: 8000, laterWeekDistanceMeters: [9000, 10000])
        XCTAssertEqual(SteadyStateProgressionEngine.resolveDuration(rules: rules, weekIndex: 0, isRecoveryWeek: false).durationSeconds, 2700)
        XCTAssertEqual(SteadyStateProgressionEngine.resolveDuration(rules: rules, weekIndex: 2, isRecoveryWeek: false).durationSeconds, 2700, "duration must not silently progress just because distance does")
        XCTAssertEqual(SteadyStateProgressionEngine.resolveDuration(rules: rules, weekIndex: 2, isRecoveryWeek: false).reasonCode, .noProgressionConfigured)
    }

    func testDistanceProgressionAdvancesByWeek() {
        let rules = SteadyStateProgressionRules(progressionDimension: .distance, weekOneDistanceMeters: 8000, laterWeekDistanceMeters: [9000, 10000, 11000])
        XCTAssertEqual(SteadyStateProgressionEngine.resolveDistance(rules: rules, weekIndex: 0, isRecoveryWeek: false).distanceMeters, 8000)
        XCTAssertEqual(SteadyStateProgressionEngine.resolveDistance(rules: rules, weekIndex: 1, isRecoveryWeek: false).distanceMeters, 9000)
        XCTAssertEqual(SteadyStateProgressionEngine.resolveDistance(rules: rules, weekIndex: 3, isRecoveryWeek: false).distanceMeters, 11000)
        XCTAssertEqual(SteadyStateProgressionEngine.resolveDistance(rules: rules, weekIndex: 1, isRecoveryWeek: false).reasonCode, .distanceProgressed)
    }

    func testIntensityZoneProgressionStepsUpAndClampsAtMaxZone() {
        let progression = IntensityZoneProgression(startZone: .two, stepPerWeek: 1, maxZone: .four)
        let rules = SteadyStateProgressionRules(progressionDimension: .intensityZone, weekOneDurationSeconds: 2700, intensityZoneProgression: progression)
        XCTAssertEqual(SteadyStateProgressionEngine.resolveIntensity(rules: rules, weekIndex: 0, isRecoveryWeek: false, staticPrimaryIntensity: nil).intensity, .heartRateZone(.two))
        XCTAssertEqual(SteadyStateProgressionEngine.resolveIntensity(rules: rules, weekIndex: 1, isRecoveryWeek: false, staticPrimaryIntensity: nil).intensity, .heartRateZone(.three))
        XCTAssertEqual(SteadyStateProgressionEngine.resolveIntensity(rules: rules, weekIndex: 2, isRecoveryWeek: false, staticPrimaryIntensity: nil).intensity, .heartRateZone(.four))
        // Week 5 would compute zone 6, which does not exist — clamp at maxZone (4), never crash or overflow.
        XCTAssertEqual(SteadyStateProgressionEngine.resolveIntensity(rules: rules, weekIndex: 4, isRecoveryWeek: false, staticPrimaryIntensity: nil).intensity, .heartRateZone(.four))
        XCTAssertEqual(SteadyStateProgressionEngine.resolveIntensity(rules: rules, weekIndex: 1, isRecoveryWeek: false, staticPrimaryIntensity: nil).reasonCode, .intensityZoneProgressed)
    }

    // MARK: - §9/§47: recovery-week reduction

    func testRecoveryWeekReducesDurationByItsConfiguredFraction() {
        let rules = SteadyStateProgressionRules(progressionDimension: .duration, weekOneDurationSeconds: 2700, laterWeekDurationSeconds: [3000, 3300, 3600], recoveryWeekDurationFraction: 0.7)
        // Recovery week reduces whatever week 4's value would have been (3600 * 0.7 = 2520), not week 1's.
        let result = SteadyStateProgressionEngine.resolveDuration(rules: rules, weekIndex: 3, isRecoveryWeek: true)
        XCTAssertEqual(result.durationSeconds, 2520)
        XCTAssertEqual(result.reasonCode, .recoveryWeekReduction)
    }

    func testRecoveryWeekReducesDistanceByItsConfiguredFraction() {
        let rules = SteadyStateProgressionRules(progressionDimension: .distance, weekOneDistanceMeters: 8000, laterWeekDistanceMeters: [9000, 10000], recoveryWeekDistanceFraction: 0.5)
        let result = SteadyStateProgressionEngine.resolveDistance(rules: rules, weekIndex: 2, isRecoveryWeek: true)
        XCTAssertEqual(result.distanceMeters, 5000)
        XCTAssertEqual(result.reasonCode, .recoveryWeekReduction)
    }

    func testRecoveryWeekStepsIntensityZoneDown() {
        let progression = IntensityZoneProgression(startZone: .two, stepPerWeek: 1, maxZone: .four)
        let rules = SteadyStateProgressionRules(progressionDimension: .intensityZone, intensityZoneProgression: progression, recoveryWeekIntensityZoneStepDown: 1)
        // Week 2 (index 1) would be zone 3; recovery steps down by 1 -> zone 2.
        let result = SteadyStateProgressionEngine.resolveIntensity(rules: rules, weekIndex: 1, isRecoveryWeek: true, staticPrimaryIntensity: nil)
        XCTAssertEqual(result.intensity, .heartRateZone(.two))
        XCTAssertEqual(result.reasonCode, .recoveryWeekReduction)
    }

    /// A static (unprogressed) Zone 2 target also honors the recovery
    /// step-down when configured — recovery reduction is independent of
    /// which dimension is the chosen progression axis (this file's own
    /// engine doc comment).
    func testRecoveryWeekStepsDownAStaticZoneTargetEvenWhenIntensityIsNotTheChosenDimension() {
        let rules = SteadyStateProgressionRules(progressionDimension: .duration, weekOneDurationSeconds: 2700, recoveryWeekIntensityZoneStepDown: 1)
        let result = SteadyStateProgressionEngine.resolveIntensity(rules: rules, weekIndex: 3, isRecoveryWeek: true, staticPrimaryIntensity: .heartRateZone(.two))
        XCTAssertEqual(result.intensity, .heartRateZone(.one))
        XCTAssertEqual(result.reasonCode, .recoveryWeekReduction)
    }

    /// Recovery step-down never goes below zone 1 — clamped, never
    /// crashes on an out-of-range `HeartRateZone` rawValue.
    func testRecoveryWeekIntensityStepDownNeverGoesBelowZoneOne() {
        let rules = SteadyStateProgressionRules(progressionDimension: .duration, weekOneDurationSeconds: 2700, recoveryWeekIntensityZoneStepDown: 5)
        let result = SteadyStateProgressionEngine.resolveIntensity(rules: rules, weekIndex: 0, isRecoveryWeek: true, staticPrimaryIntensity: .heartRateZone(.two))
        XCTAssertEqual(result.intensity, .heartRateZone(.one))
    }

    // MARK: - §47.13: deterministic output for identical input

    func testSameInputsAlwaysProduceTheSameOutput() {
        let rules = SteadyStateProgressionRules(progressionDimension: .duration, weekOneDurationSeconds: 2700, laterWeekDurationSeconds: [3000])
        let first = SteadyStateProgressionEngine.resolveDuration(rules: rules, weekIndex: 1, isRecoveryWeek: false)
        let second = SteadyStateProgressionEngine.resolveDuration(rules: rules, weekIndex: 1, isRecoveryWeek: false)
        XCTAssertEqual(first.durationSeconds, second.durationSeconds)
        XCTAssertEqual(first.reasonCode, second.reasonCode)
    }

    // MARK: - IntensityTranslation (§37)

    func testPhysiologicalIntensityTargetsSurviveAnActivitySubstitutionUnchanged() {
        XCTAssertEqual(IntensityTranslation.translate(.heartRateZone(.two), from: .cycling, to: .rowing), .heartRateZone(.two))
        XCTAssertEqual(IntensityTranslation.translate(.rpe(BoundedRange(lower: 6, upper: 7)), from: .cycling, to: .rowing), .rpe(BoundedRange(lower: 6, upper: 7)))
    }

    /// §39: "numerical Bike power target is not blindly transferred to
    /// Row" — the exact scenario named in the Stage 4C test requirements.
    func testEquipmentSpecificIntensityTargetsDoNotTransferAcrossActivitySubstitution() {
        let bikePower = IntensityTarget.powerRange(PowerRange(lower: Power(watts: 180), upper: Power(watts: 200)))
        XCTAssertNil(IntensityTranslation.translate(bikePower, from: .cycling, to: .rowing), "a Bike power target must not silently become a Row power target")

        let runPace = IntensityTarget.pace(PaceRange(lower: Pace(secondsPerKilometer: 270), upper: Pace(secondsPerKilometer: 280)))
        XCTAssertNil(IntensityTranslation.translate(runPace, from: .running, to: .cycling))
    }

    func testIntensityTargetIsUnchangedWhenTheActivityDoesNotActuallyChange() {
        let bikePower = IntensityTarget.powerRange(PowerRange(lower: Power(watts: 180), upper: Power(watts: 200)))
        XCTAssertEqual(IntensityTranslation.translate(bikePower, from: .cycling, to: .cycling), bikePower)
    }
}
