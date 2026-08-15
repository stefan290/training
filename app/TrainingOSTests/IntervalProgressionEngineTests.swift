import XCTest
@testable import TrainingOS

/// Engine-level regression fixtures for `IntervalProgressionEngine` — the
/// interval sibling of `StrengthProgressionEngineTests`/
/// `SteadyStateProgressionEngineTests`. Every CONSTRUCTED numeric fixture
/// is precomputed by hand before being asserted; the one SOURCE-DERIVED
/// fixture (Helgerud's 4×4) cites its exact source figures directly from
/// `PROGRAMMING_SOURCES.md` §3.
final class IntervalProgressionEngineTests: XCTestCase {
    // MARK: - §36/§46: same system, four modalities, required interval shapes

    /// §9 example A / §36.1: 5×1km running, distance-based work.
    func test5x1kmRunningIsDistanceBasedNotTimeBased() {
        let rules = IntervalProgressionRules(weekOneIntervalCount: 5, weekOneWorkDistanceMeters: 1000, weekOneRecoveryDurationSeconds: 120)
        let duration = IntervalProgressionEngine.resolveWorkDuration(rules: rules, weekIndex: 0, previousActualDurationSeconds: nil, previousOutcome: nil)
        let distance = IntervalProgressionEngine.resolveWorkDistance(rules: rules, weekIndex: 0, previousActualDistanceMeters: nil, previousOutcome: nil)
        XCTAssertNil(duration.durationSeconds, "a distance-based work interval must not also carry a dummy duration")
        XCTAssertEqual(distance.distanceMeters, 1000)
    }

    /// §9 example C / §36.2: 4×4min running, time-based work.
    func test4x4RunningIsDurationBasedNotDistanceBased() {
        let rules = IntervalProgressionRules(weekOneIntervalCount: 4, weekOneWorkDurationSeconds: 240, weekOneRecoveryDurationSeconds: 180)
        let duration = IntervalProgressionEngine.resolveWorkDuration(rules: rules, weekIndex: 0, previousActualDurationSeconds: nil, previousOutcome: nil)
        let distance = IntervalProgressionEngine.resolveWorkDistance(rules: rules, weekIndex: 0, previousActualDistanceMeters: nil, previousOutcome: nil)
        XCTAssertEqual(duration.durationSeconds, 240)
        XCTAssertNil(distance.distanceMeters, "a duration-based work interval must not also carry a dummy distance")
    }

    // MARK: - §37/§47.18-22: recovery variety

    func testTimeBasedAndActiveRecoveryResolveTogether() {
        let rules = IntervalProgressionRules(weekOneIntervalCount: 4, weekOneWorkDurationSeconds: 240, weekOneRecoveryDurationSeconds: 180)
        let recovery = IntervalProgressionEngine.resolveRecoveryDuration(rules: rules, weekIndex: 0, previousActualRecoverySeconds: nil, previousOutcome: nil)
        XCTAssertEqual(recovery.recoveryDurationSeconds, 180)
    }

    // MARK: - §13/§37.13-16: progression strategies

    func testIntervalCountProgressesByWeek() {
        let rules = IntervalProgressionRules(
            priority: [IntervalProgressionStep(variable: .intervalCount, incrementPerWeek: 1, weeksToCeiling: 3)],
            weekOneIntervalCount: 4
        )
        XCTAssertEqual(IntervalProgressionEngine.resolveIntervalCount(rules: rules, weekIndex: 0, previousActualCount: nil, previousOutcome: nil).count, 4)
        XCTAssertEqual(IntervalProgressionEngine.resolveIntervalCount(rules: rules, weekIndex: 1, previousActualCount: 4, previousOutcome: .progress).count, 5)
        XCTAssertEqual(IntervalProgressionEngine.resolveIntervalCount(rules: rules, weekIndex: 1, previousActualCount: 4, previousOutcome: .progress).reasonCode, .intervalCountIncrease)
    }

    func testWorkDurationProgressesByWeek() {
        let rules = IntervalProgressionRules(
            priority: [IntervalProgressionStep(variable: .workDuration, incrementPerWeek: 60, weeksToCeiling: 4)],
            weekOneIntervalCount: 5, weekOneWorkDurationSeconds: 180
        )
        XCTAssertEqual(IntervalProgressionEngine.resolveWorkDuration(rules: rules, weekIndex: 2, previousActualDurationSeconds: 240, previousOutcome: .progress).durationSeconds, 300)
    }

    func testWorkDistanceProgressesByWeek() {
        let rules = IntervalProgressionRules(
            priority: [IntervalProgressionStep(variable: .workDistance, incrementPerWeek: 200, weeksToCeiling: 3)],
            weekOneIntervalCount: 5, weekOneWorkDistanceMeters: 1000
        )
        XCTAssertEqual(IntervalProgressionEngine.resolveWorkDistance(rules: rules, weekIndex: 1, previousActualDistanceMeters: 1000, previousOutcome: .progress).distanceMeters, 1200)
    }

    func testIntensityProgressesUsingIntensityZoneProgressionsOwnStepSizeNotThePriorityStepsIncrement() {
        // The priority step's incrementPerWeek (99, deliberately nonsensical)
        // must be ignored — the real step size is `stepPerWeek: 1` on
        // IntensityZoneProgression itself. See resolveIntensity's own doc comment.
        let rules = IntervalProgressionRules(
            priority: [IntervalProgressionStep(variable: .intensity, incrementPerWeek: 99, weeksToCeiling: 2)],
            weekOneIntervalCount: 4,
            intensityZoneProgression: IntensityZoneProgression(startZone: .two, stepPerWeek: 1, maxZone: .four)
        )
        let result = IntervalProgressionEngine.resolveIntensity(rules: rules, weekIndex: 1, previousActualZone: nil, previousOutcome: nil)
        XCTAssertEqual(result.intensity, .heartRateZone(.three), "must step by 1 zone, not by the nonsensical 99 in the priority step")
        XCTAssertEqual(result.reasonCode, .intensityIncrease)
    }

    func testRecoveryDurationReducesByWeekAndClampsAtItsFloor() {
        let rules = IntervalProgressionRules(
            priority: [IntervalProgressionStep(variable: .recoveryDuration, incrementPerWeek: 40, weeksToCeiling: 4)],
            weekOneIntervalCount: 4, weekOneRecoveryDurationSeconds: 150, recoveryDurationFloorSeconds: 60
        )
        XCTAssertEqual(IntervalProgressionEngine.resolveRecoveryDuration(rules: rules, weekIndex: 1, previousActualRecoverySeconds: nil, previousOutcome: nil).recoveryDurationSeconds, 110)
        XCTAssertEqual(IntervalProgressionEngine.resolveRecoveryDuration(rules: rules, weekIndex: 2, previousActualRecoverySeconds: nil, previousOutcome: nil).recoveryDurationSeconds, 70)
        XCTAssertEqual(IntervalProgressionEngine.resolveRecoveryDuration(rules: rules, weekIndex: 3, previousActualRecoverySeconds: nil, previousOutcome: nil).recoveryDurationSeconds, 60, "must clamp at the floor, not go to 30")
        XCTAssertEqual(IntervalProgressionEngine.resolveRecoveryDuration(rules: rules, weekIndex: 4, previousActualRecoverySeconds: nil, previousOutcome: nil).recoveryDurationSeconds, 60)
    }

    // MARK: - §14/§37.18: explicit progression priority

    /// The exact example from Stage 4D §14: "1. increase interval count
    /// until ceiling, then 2. increase work duration." Precomputed by
    /// hand: count +1/week for 3 weeks (ceiling), then duration +60s/week
    /// for 4 weeks.
    func testProgressionPriorityAdvancesEarlierStepFullyBeforeLaterStepStarts() {
        let rules = IntervalProgressionRules(
            priority: [
                IntervalProgressionStep(variable: .intervalCount, incrementPerWeek: 1, weeksToCeiling: 3),
                IntervalProgressionStep(variable: .workDuration, incrementPerWeek: 60, weeksToCeiling: 4)
            ],
            weekOneIntervalCount: 4, weekOneWorkDurationSeconds: 240
        )
        let expected: [(week: Int, count: Int, duration: Int)] = [
            (0, 4, 240), (1, 5, 240), (2, 6, 240), (3, 7, 240),
            (4, 7, 300), (5, 7, 360), (6, 7, 420), (7, 7, 480)
        ]
        for fixture in expected {
            let count = IntervalProgressionEngine.resolveIntervalCount(rules: rules, weekIndex: fixture.week, previousActualCount: nil, previousOutcome: nil).count
            let duration = IntervalProgressionEngine.resolveWorkDuration(rules: rules, weekIndex: fixture.week, previousActualDurationSeconds: nil, previousOutcome: nil).durationSeconds
            XCTAssertEqual(count, fixture.count, "week \(fixture.week) count")
            XCTAssertEqual(duration, fixture.duration, "week \(fixture.week) duration")
        }
        // Once duration starts advancing (week 4+), count must have
        // stopped changing — proving one variable at a time, never both
        // simultaneously (§14's explicit "do NOT automatically increase
        // count + duration... at the same time").
        let week4Duration = IntervalProgressionEngine.resolveWorkDuration(rules: rules, weekIndex: 4, previousActualDurationSeconds: nil, previousOutcome: nil)
        XCTAssertEqual(week4Duration.reasonCode, .workDurationIncrease)
        let week4Count = IntervalProgressionEngine.resolveIntervalCount(rules: rules, weekIndex: 4, previousActualCount: nil, previousOutcome: nil)
        XCTAssertEqual(week4Count.reasonCode, .noProgressionConfigured, "count already reached its ceiling and is not the active dimension this week")
    }

    // MARK: - §16-17/§37.19-22: completion criteria and failure outcomes

    func testFullCompletionWithinRpeYieldsProgress() {
        let criteria = IntervalCompletionCriteria(maxRpeAllowed: 9)
        XCTAssertEqual(IntervalProgressionEngine.evaluateSessionOutcome(criteria: criteria, completedCount: 4, totalCount: 4, worstRpe: 8), .progress)
    }

    /// Full completion but an excessive RPE must NOT count as success —
    /// downgraded to HOLD, not silently treated as a pass.
    func testFullCompletionWithExcessiveRpeDoesNotCountAsProgress() {
        let criteria = IntervalCompletionCriteria(maxRpeAllowed: 9)
        XCTAssertEqual(IntervalProgressionEngine.evaluateSessionOutcome(criteria: criteria, completedCount: 4, totalCount: 4, worstRpe: 10), .hold)
    }

    func testPartialCompletionYieldsHoldThenRepeatThenReductionAsCompletionWorsens() {
        let criteria = IntervalCompletionCriteria(reductionStrategy: .reduceIntervalCount)
        XCTAssertEqual(IntervalProgressionEngine.evaluateSessionOutcome(criteria: criteria, completedCount: 3, totalCount: 4, worstRpe: nil), .hold, "0.75 completion")
        XCTAssertEqual(IntervalProgressionEngine.evaluateSessionOutcome(criteria: criteria, completedCount: 2, totalCount: 4, worstRpe: nil), .repeatSession, "0.5 completion")
        XCTAssertEqual(IntervalProgressionEngine.evaluateSessionOutcome(criteria: criteria, completedCount: 1, totalCount: 4, worstRpe: nil), .reduceIntervalCount, "0.25 completion, configured to reduce count")
    }

    func testReductionStrategyIsConfiguredNotGuessed() {
        let criteria = IntervalCompletionCriteria(reductionStrategy: .reduceIntensity)
        XCTAssertEqual(IntervalProgressionEngine.evaluateSessionOutcome(criteria: criteria, completedCount: 0, totalCount: 4, worstRpe: nil), .reduceIntensity)
    }

    /// §17.22/§37.22: no reps logged at all -> CALIBRATION_REQUIRED, never
    /// an invented completion fraction.
    func testNoDataAtAllYieldsCalibrationRequired() {
        let criteria = IntervalCompletionCriteria()
        XCTAssertEqual(IntervalProgressionEngine.evaluateSessionOutcome(criteria: criteria, completedCount: 0, totalCount: 0, worstRpe: nil), .calibrationRequired)
    }

    /// §37.19: a failed session HOLDs — does not progress even though
    /// the rule *would* progress if given `.progress` instead.
    func testFailedSessionOutcomeHoldsRatherThanProgressingRegardlessOfConfiguredIncrement() {
        let rules = IntervalProgressionRules(
            priority: [IntervalProgressionStep(variable: .intervalCount, incrementPerWeek: 1, weeksToCeiling: 3)],
            weekOneIntervalCount: 4
        )
        let result = IntervalProgressionEngine.resolveIntervalCount(rules: rules, weekIndex: 2, previousActualCount: 5, previousOutcome: .hold)
        XCTAssertEqual(result.count, 5, "must repeat the previous actual count, not calendar-advance to 6")
        XCTAssertEqual(result.reasonCode, .hold)
    }

    /// §37.20: a successful session progresses normally.
    func testSuccessfulSessionOutcomeProgressesNormally() {
        let rules = IntervalProgressionRules(
            priority: [IntervalProgressionStep(variable: .intervalCount, incrementPerWeek: 1, weeksToCeiling: 3)],
            weekOneIntervalCount: 4
        )
        let result = IntervalProgressionEngine.resolveIntervalCount(rules: rules, weekIndex: 2, previousActualCount: 5, previousOutcome: .progress)
        XCTAssertEqual(result.count, 6)
        XCTAssertEqual(result.reasonCode, .intervalCountIncrease)
    }

    /// §37.21: REPEAT behavior — same prescription repeats, explicitly
    /// distinct from HOLD's reason code even though both freeze the
    /// number.
    func testRepeatOutcomeFreezesTheNumberWithItsOwnDistinctReasonCode() {
        let rules = IntervalProgressionRules(weekOneIntervalCount: 4, weekOneWorkDurationSeconds: 240)
        let result = IntervalProgressionEngine.resolveWorkDuration(rules: rules, weekIndex: 1, previousActualDurationSeconds: 240, previousOutcome: .repeatSession)
        XCTAssertEqual(result.durationSeconds, 240)
        XCTAssertEqual(result.reasonCode, .repeatSession)
    }

    func testReduceIntervalCountOutcomeReducesByOneAndFloorsAtOne() {
        let rules = IntervalProgressionRules(weekOneIntervalCount: 4)
        let result = IntervalProgressionEngine.resolveIntervalCount(rules: rules, weekIndex: 1, previousActualCount: 1, previousOutcome: .reduceIntervalCount)
        XCTAssertEqual(result.count, 1, "must never reduce below 1 interval")
    }

    func testReduceIntensityOutcomeStepsDownOneZoneAndFloorsAtZoneOne() {
        let rules = IntervalProgressionRules(
            weekOneIntervalCount: 4,
            intensityZoneProgression: IntensityZoneProgression(startZone: .two, stepPerWeek: 1, maxZone: .four)
        )
        let result = IntervalProgressionEngine.resolveIntensity(rules: rules, weekIndex: 1, previousActualZone: .one, previousOutcome: .reduceIntensity)
        XCTAssertEqual(result.intensity, .heartRateZone(.one), "must never reduce below zone 1")
        XCTAssertEqual(result.reasonCode, .reduceIntensity)
    }

    // MARK: - §47.13: deterministic output for identical input

    func testSameInputsAlwaysProduceTheSameOutput() {
        let rules = IntervalProgressionRules(
            priority: [IntervalProgressionStep(variable: .intervalCount, incrementPerWeek: 1, weeksToCeiling: 3)],
            weekOneIntervalCount: 4
        )
        let first = IntervalProgressionEngine.resolveIntervalCount(rules: rules, weekIndex: 2, previousActualCount: nil, previousOutcome: nil)
        let second = IntervalProgressionEngine.resolveIntervalCount(rules: rules, weekIndex: 2, previousActualCount: nil, previousOutcome: nil)
        XCTAssertEqual(first.count, second.count)
        XCTAssertEqual(first.reasonCode, second.reasonCode)
    }

    // MARK: - §19-20: Helgerud 4×4 (SOURCE-DERIVED) + cross-modality proof

    /// `PROGRAMMING_SOURCES.md` §3: "4 intervals of 4 min running at
    /// 90-95% HRmax, each followed by 3 min active recovery at 70%
    /// HRmax." The source study fixes this protocol — it is never
    /// progressed (`priority: []`), matching
    /// `ENDURANCE_PROGRAMMING_MODEL.md` §3.1's own explicit note that
    /// presenting this preset as needing to "progress" would misrepresent
    /// the source.
    private func helgerud4x4Rules() -> IntervalProgressionRules {
        IntervalProgressionRules(
            priority: [],
            weekOneIntervalCount: 4,
            weekOneWorkDurationSeconds: 240,
            weekOneRecoveryDurationSeconds: 180,
            requiresSuccessfulCompletionToProgress: false
        )
    }

    func testHelgerud4x4NeverProgressesAcrossAnyWeek() {
        let rules = helgerud4x4Rules()
        for week in 0...5 {
            let count = IntervalProgressionEngine.resolveIntervalCount(rules: rules, weekIndex: week, previousActualCount: nil, previousOutcome: nil)
            let duration = IntervalProgressionEngine.resolveWorkDuration(rules: rules, weekIndex: week, previousActualDurationSeconds: nil, previousOutcome: nil)
            let recovery = IntervalProgressionEngine.resolveRecoveryDuration(rules: rules, weekIndex: week, previousActualRecoverySeconds: nil, previousOutcome: nil)
            XCTAssertEqual(count.count, 4, "week \(week)")
            XCTAssertEqual(duration.durationSeconds, 240, "week \(week)")
            XCTAssertEqual(recovery.recoveryDurationSeconds, 180, "week \(week)")
        }
    }

    /// §20: the same rules/engine represent Running, Cycling and Rowing
    /// 4×4 sessions — only the `IntensityTarget` *idiom* changes per
    /// modality (HR percent for Running, matching the source study;
    /// power zone for Cycling; stroke rate for Rowing), proving no
    /// per-modality engine duplication is needed.
    func testHelgerud4x4StructureIsIdenticalAcrossRunningCyclingAndRowingWithModalityAppropriateIntensity() {
        let rules = helgerud4x4Rules()
        let fixtures: [(activity: ActivityType, workIntensity: IntensityTarget, recoveryIntensity: IntensityTarget)] = [
            (.running, .heartRatePercent(BoundedRange(lower: 0.90, upper: 0.95)), .heartRatePercent(BoundedRange(lower: 0.70, upper: 0.70))),
            (.cycling, .powerZone(.four), .powerZone(.one)),
            (.rowing, .strokeRate(BoundedRange(lower: 28, upper: 32)), .strokeRate(BoundedRange(lower: 18, upper: 20)))
        ]
        for fixture in fixtures {
            let template = IntervalPrescriptionTemplate(
                preferredActivityType: fixture.activity,
                workIntensity: fixture.workIntensity,
                recoveryIntensity: fixture.recoveryIntensity,
                recoveryType: .active,
                progressionRules: rules
            )
            XCTAssertEqual(template.progressionRules?.weekOneIntervalCount, 4, "\(fixture.activity)")
            XCTAssertEqual(template.progressionRules?.weekOneWorkDurationSeconds, 240, "\(fixture.activity)")
            XCTAssertEqual(template.progressionRules?.weekOneRecoveryDurationSeconds, 180, "\(fixture.activity)")
            XCTAssertEqual(template.workIntensity, fixture.workIntensity, "\(fixture.activity)")
            XCTAssertEqual(template.recoveryType, .active, "\(fixture.activity)")

            let count = IntervalProgressionEngine.resolveIntervalCount(rules: template.progressionRules!, weekIndex: 3, previousActualCount: nil, previousOutcome: nil)
            XCTAssertEqual(count.count, 4, "\(fixture.activity) must not silently progress a fixed protocol")
        }
    }
}
