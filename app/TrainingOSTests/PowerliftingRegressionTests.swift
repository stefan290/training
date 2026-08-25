import XCTest
@testable import TrainingOS

/// Engine-level regression fixtures for Family B ("RP Powerlifting
/// Strength") and Family C ("RP Powerlifting Hypertrophy-block"),
/// exercising `StrengthProgressionEngine`/`SourceCompatibleDeloadStrategy`
/// directly — the same discipline as `StrengthProgressionEngineTests`
/// (Family A). Every numeric fixture is **CONSTRUCTED** (RM=100) per
/// `PROGRAM_REGRESSION_TEST_PLAN.md`'s labeling convention; no real Family
/// B/C source workbook survives in this repository (confirmed by this
/// pass's own research). Every formula is still cited to its
/// `PROGRAM_LOGIC_SPEC.md` rule name.
final class PowerliftingRegressionTests: XCTestCase {
    private let barbell = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)
    private let barbellFive = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 5)

    // MARK: - §RM basis

    func testMixed5And8RMBasisResolveIndependently() {
        let fiveRMRules = StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm5, weekOneFactor: 0.95, laterWeekMultipliers: [1.05, 1.075, 1.1])),
            setCountRule: .fixed(setsByWeek: [3, 3, 3, 3]),
            repGoalSchedule: [RepGoal.rir(2)]
        )
        let eightRMRules = StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm8, weekOneFactor: 0.95, laterWeekMultipliers: [1.05, 1.075, 1.1])),
            setCountRule: .fixed(setsByWeek: [2, 2, 3, 3]),
            repGoalSchedule: [RepGoal.rir(2)]
        )
        // Both resolve identically off whatever RM value is supplied — the
        // basis (5RM vs 8RM) only determines *which tested number* a
        // caller must supply, never a different formula shape.
        let fiveResult = StrengthProgressionEngine.resolveWeight(rules: fiveRMRules, weekIndex: 0, rmKilograms: 100, weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: nil, equipmentProfile: barbell)
        let eightResult = StrengthProgressionEngine.resolveWeight(rules: eightRMRules, weekIndex: 0, rmKilograms: 100, weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: nil, equipmentProfile: barbell)
        XCTAssertEqual(fiveResult.weightKg ?? -1, 95, accuracy: 0.0001)
        XCTAssertEqual(eightResult.weightKg ?? -1, 95, accuracy: 0.0001)
        XCTAssertEqual(fiveResult.reasonCode, .rmBasedLoad)
        XCTAssertEqual(eightResult.reasonCode, .rmBasedLoad)
    }

    func testUniform10RMBasisForFamilyC() {
        let rules = StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.95, laterWeekMultipliers: [1.05, 1.075, 1.1])),
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 3)),
            repGoalSchedule: [RepGoal.rir(8)]
        )
        let result = StrengthProgressionEngine.resolveWeight(rules: rules, weekIndex: 0, rmKilograms: 100, weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: nil, equipmentProfile: barbellFive)
        XCTAssertEqual(result.weightKg ?? -1, 95, accuracy: 0.0001)
    }

    // MARK: - §Triples protocol (CONSTRUCTED, RM=100)
    //
    // Week1 = MROUND(100×0.7, 2.5) = 70 — the lighter Triples factor,
    // distinct from the ordinary 0.95 factor (Week1 = 95, proven above).
    // "Triples sessions never change" (`FAMILY_B_REP_GOAL`): the rep goal
    // is flat across all 4 weeks, not stepping like ordinary sessions.

    func testTriplesProtocolUsesTheLighterFactorAndNeverChangesRepGoal() {
        let rules = StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm5, weekOneFactor: 0.7, laterWeekMultipliers: [1.05, 1.075, 1.1])),
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 3)),
            repGoalSchedule: Array(repeating: RepGoal.fixedReps(3), count: 4)
        )
        let week1 = StrengthProgressionEngine.resolveWeight(rules: rules, weekIndex: 0, rmKilograms: 100, weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: nil, equipmentProfile: barbell)
        XCTAssertEqual(week1.weightKg ?? -1, 70, accuracy: 0.0001)

        for week in 0..<4 {
            let repGoal = StrengthProgressionEngine.resolveRepGoal(rules: rules, weekIndex: week)
            XCTAssertEqual(repGoal.repGoal, RepGoal.fixedReps(3), "Triples rep goal is flat at week \(week)")
        }
    }

    // MARK: - §Family B Week-4 autoregulation asymmetry (CONSTRUCTED)
    //
    // Baseline 3. Week2 rating +1 -> 4. Week3 rating 0 -> 4. Week4 (final
    // week, applyRatingOnFinalWeek=false): the rating is *ignored*
    // entirely, regardless of what's supplied — the previous week's value
    // (4) carries forward unchanged.

    func testFamilyBWeekFourAsymmetryIgnoresTheSuppliedRatingEntirely() {
        let rules = StrengthProgressionRules(
            loadRule: .none,
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 3, applyRatingOnFinalWeek: false)),
            repGoalSchedule: [RepGoal.rir(2)]
        )
        let week1 = StrengthProgressionEngine.resolveSetCount(rules: rules, weekIndex: 0, previousWeekSetCount: nil, autoregulationRating: nil)
        XCTAssertEqual(week1.sets, 3)

        let week2 = StrengthProgressionEngine.resolveSetCount(rules: rules, weekIndex: 1, previousWeekSetCount: 3, autoregulationRating: 1)
        XCTAssertEqual(week2.sets, 4)

        let week3 = StrengthProgressionEngine.resolveSetCount(rules: rules, weekIndex: 2, previousWeekSetCount: 4, autoregulationRating: 0)
        XCTAssertEqual(week3.sets, 4)

        // Deliberately supply a rating of +1 (which *would* increase sets
        // to 5 under normal rules) to prove it's ignored, not merely
        // untested.
        let week4 = StrengthProgressionEngine.resolveSetCount(rules: rules, weekIndex: 3, previousWeekSetCount: 4, autoregulationRating: 1, isFinalWeek: true)
        XCTAssertEqual(week4.sets, 4, "Week 4 must carry Week 3's value forward unchanged, ignoring the supplied +1 rating")
        XCTAssertEqual(week4.reasonCode, .autoregulatedSetFinalWeekUnchanged)
    }

    // MARK: - §Family C Week-4 autoregulation freeze (CONSTRUCTED)
    //
    // Baseline 2. Week2 rating +1 -> 3. Week3 rating +1 -> 4 (freeze takes
    // effect *after* week 3, so week 3 itself still applies its own
    // rating normally). Week4: frozen at week 3's value (4), ignoring
    // Week4's own rating entirely — proven here with a deliberately
    // supplied *negative* rating specifically to rule out the freeze
    // being mistaken for "the rating happened to be 0."

    func testFamilyCWeekFourFreezeIgnoresTheSuppliedRatingEvenWhenNegative() {
        let rules = StrengthProgressionRules(
            loadRule: .none,
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 2, freezeAfterWeek: 2)),
            repGoalSchedule: [RepGoal.rir(8)]
        )
        let week1 = StrengthProgressionEngine.resolveSetCount(rules: rules, weekIndex: 0, previousWeekSetCount: nil, autoregulationRating: nil)
        XCTAssertEqual(week1.sets, 2)

        let week2 = StrengthProgressionEngine.resolveSetCount(rules: rules, weekIndex: 1, previousWeekSetCount: 2, autoregulationRating: 1)
        XCTAssertEqual(week2.sets, 3)

        let week3 = StrengthProgressionEngine.resolveSetCount(rules: rules, weekIndex: 2, previousWeekSetCount: 3, autoregulationRating: 1)
        XCTAssertEqual(week3.sets, 4, "week 3 itself still applies its own rating normally — the freeze starts only after this week")

        let week4 = StrengthProgressionEngine.resolveSetCount(rules: rules, weekIndex: 3, previousWeekSetCount: 4, autoregulationRating: -1, frozenSetCount: 4)
        XCTAssertEqual(week4.sets, 4, "frozen at Week 3's value, ignoring the deliberately-supplied -1 rating")
        XCTAssertEqual(week4.reasonCode, .autoregulatedSetFrozen)
    }

    /// Proves Family B and Family C's Week-4 shapes are genuinely
    /// distinct mechanisms, not the same behavior under two names — a
    /// rule engine that infers one family's Week-4 handling by analogy
    /// with the other would be wrong for at least one of them (Stage 3
    /// decision B4's own stated risk).
    func testFamilyBAsymmetryAndFamilyCFreezeAreDistinctMechanisms() {
        let familyBRules = StrengthProgressionRules(
            loadRule: .none,
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 3, applyRatingOnFinalWeek: false)),
            repGoalSchedule: [RepGoal.rir(2)]
        )
        let familyCRules = StrengthProgressionRules(
            loadRule: .none,
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 3, freezeAfterWeek: 2)),
            repGoalSchedule: [RepGoal.rir(8)]
        )
        XCTAssertNotEqual(familyBRules.setCountRule, familyCRules.setCountRule)

        guard case .autoregulated(let bConfig) = familyBRules.setCountRule,
              case .autoregulated(let cConfig) = familyCRules.setCountRule else {
            return XCTFail("expected .autoregulated for both")
        }
        // Family B: no freeze at all, just a final-week exception.
        XCTAssertNil(bConfig.freezeAfterWeek)
        XCTAssertFalse(bConfig.applyRatingOnFinalWeek)
        // Family C: freeze, with the ordinary final-week flag left at its
        // default (irrelevant once frozen, but distinct in shape).
        XCTAssertEqual(cConfig.freezeAfterWeek, 2)
        XCTAssertTrue(cConfig.applyRatingOnFinalWeek)
    }

    // MARK: - §Family C backoff reference (CONSTRUCTED, RM=100)
    //
    // Monday Squat: Week1 = MROUND(100×0.95, 5) = 95. Friday backoff:
    // `linkedToPairedSlot(fractionOfSourceResult: 0.85/0.95)` applied to
    // Monday's *resolved* Week1 value = MROUND(95×(0.85/0.95), 5) = 85 —
    // matching what an independent `10RM×0.85` computation would also
    // produce for this particular RM, the structural mechanism
    // (Stage 3 decision A5) applied to Family C's specific case.

    func testFamilyCBackoffResolvesAsAFractionOfMondaysResolvedWeight() {
        let mondayRules = StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.95, laterWeekMultipliers: [1.05, 1.075, 1.1])),
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 3)),
            repGoalSchedule: [RepGoal.rir(8)]
        )
        let mondayResult = StrengthProgressionEngine.resolveWeight(rules: mondayRules, weekIndex: 0, rmKilograms: 100, weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: nil, equipmentProfile: barbellFive)
        XCTAssertEqual(mondayResult.weightKg ?? -1, 95, accuracy: 0.0001)

        let backoffRules = StrengthProgressionRules(
            loadRule: .linkedToPairedSlot(fractionOfSourceResult: 0.85 / 0.95),
            setCountRule: .fixed(setsByWeek: [2, 2, 2, 2]),
            repGoalSchedule: [RepGoal.rir(8)],
            deloadRepFraction: 1.0
        )
        let backoffResult = StrengthProgressionEngine.resolveWeight(
            rules: backoffRules, weekIndex: 0, rmKilograms: nil,
            weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: mondayResult.weightKg,
            equipmentProfile: barbellFive
        )
        XCTAssertEqual(backoffResult.weightKg ?? -1, 85, accuracy: 0.0001)
        XCTAssertEqual(backoffResult.reasonCode, .linkedToPairedSlotLoad)
    }

    // MARK: - §Family B deload (CONSTRUCTED, RM=100, 4-day)
    //
    // Weight split: boundary=2, full(Mon/Tue)=0.7×, half(Thu/Fri)=0.5×.
    // Rep split: boundary=2, full(Mon/Tue)=2/3, half(Thu/Fri)=1/2 — both
    // genuinely different from Family A's uniform, day-position-
    // independent deload.

    func testFamilyBDeloadWeightSplitsByDayPositionWithItsOwnFactors() {
        let strategy = SourceCompatibleDeloadStrategy()
        let triplesRules = StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm5, weekOneFactor: 0.7, laterWeekMultipliers: [1.05, 1.075, 1.1])),
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 3)),
            repGoalSchedule: Array(repeating: RepGoal.fixedReps(3), count: 4),
            deloadRepPositionOverride: DeloadPositionOverride(boundaryDayIndex: 2, fullPositionFactor: 2.0 / 3.0, halfPositionFactor: 0.5),
            deloadWeightPositionOverride: DeloadPositionOverride(boundaryDayIndex: 2, fullPositionFactor: 0.7, halfPositionFactor: 0.5)
        )
        // Week1 = 70 (proven above).
        let mondayDeload = strategy.resolveDeloadWeight(rules: triplesRules, dayPositionInWeek: 0, dayCount: 4, weekOneResolvedWeightKg: 70, equipmentProfile: barbell)
        XCTAssertEqual(mondayDeload.weightKg ?? -1, 50, accuracy: 0.0001)
        let thursdayDeload = strategy.resolveDeloadWeight(rules: triplesRules, dayPositionInWeek: 2, dayCount: 4, weekOneResolvedWeightKg: 70, equipmentProfile: barbell)
        XCTAssertEqual(thursdayDeload.weightKg ?? -1, 35, accuracy: 0.0001)

        // Stage 10R.1D: deload rep resolution no longer fabricates a
        // number by halving the Week-1 template's rep goal — the source's
        // own "X reps of Week 1" instruction is proven to reference
        // ACTUAL logged Week-1 performance, which TrainingOS does not yet
        // thread into this resolver, and "which Week-1 set" has no
        // source-provided answer (`STAGE10R1D_SOURCE_SEMANTICS_CORRECTION.md`).
        let mondayRep = strategy.resolveDeloadRepGoal(rules: triplesRules, dayPositionInWeek: 0, dayCount: 4)
        XCTAssertNil(mondayRep.repGoal, "never fabricate a deload rep count from the template")
        XCTAssertEqual(mondayRep.reasonCode, .deloadRepsRequireLoggedPerformanceData)
        let thursdayRep = strategy.resolveDeloadRepGoal(rules: triplesRules, dayPositionInWeek: 2, dayCount: 4)
        XCTAssertNil(thursdayRep.repGoal, "never fabricate a deload rep count from the template")
        XCTAssertEqual(thursdayRep.reasonCode, .deloadRepsRequireLoggedPerformanceData)
    }

    func testFamilyBOrdinaryRowDeloadUsesTheSameSplitAtItsOwnWeekOneValue() {
        let strategy = SourceCompatibleDeloadStrategy()
        let ordinaryRules = StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm5, weekOneFactor: 0.95, laterWeekMultipliers: [1.05, 1.075, 1.1])),
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 3)),
            repGoalSchedule: [RepGoal.rir(2), RepGoal.rir(2), RepGoal.rir(2), RepGoal.rir(1)],
            deloadRepPositionOverride: DeloadPositionOverride(boundaryDayIndex: 2, fullPositionFactor: 2.0 / 3.0, halfPositionFactor: 0.5),
            deloadWeightPositionOverride: DeloadPositionOverride(boundaryDayIndex: 2, fullPositionFactor: 0.7, halfPositionFactor: 0.5)
        )
        // Week1 = 95 (proven above).
        let tuesdayDeload = strategy.resolveDeloadWeight(rules: ordinaryRules, dayPositionInWeek: 1, dayCount: 4, weekOneResolvedWeightKg: 95, equipmentProfile: barbell)
        XCTAssertEqual(tuesdayDeload.weightKg ?? -1, 67.5, accuracy: 0.0001)
        let fridayDeload = strategy.resolveDeloadWeight(rules: ordinaryRules, dayPositionInWeek: 3, dayCount: 4, weekOneResolvedWeightKg: 95, equipmentProfile: barbell)
        XCTAssertEqual(fridayDeload.weightKg ?? -1, 47.5, accuracy: 0.0001)

        // Stage 10R.1D: see the Triples test above for why this is now
        // unresolved rather than fabricated.
        let tuesdayRep = strategy.resolveDeloadRepGoal(rules: ordinaryRules, dayPositionInWeek: 1, dayCount: 4)
        XCTAssertNil(tuesdayRep.repGoal, "never fabricate a deload rep count from the template")
        XCTAssertEqual(tuesdayRep.reasonCode, .deloadRepsRequireLoggedPerformanceData)
        let fridayRep = strategy.resolveDeloadRepGoal(rules: ordinaryRules, dayPositionInWeek: 3, dayCount: 4)
        XCTAssertNil(fridayRep.repGoal, "never fabricate a deload rep count from the template")
        XCTAssertEqual(fridayRep.reasonCode, .deloadRepsRequireLoggedPerformanceData)
    }

    // MARK: - §Family C deload (CONSTRUCTED, RM=100, 5-day)
    //
    // Weight split: boundary=2, full(Mon/Tue)=1.0× (unchanged), half
    // (Wed/Thu/Fri)=0.5×. Reps: uniform 1/2 for every row *except* the
    // Friday backoff, whose reps are unchanged (1.0×) — the sole
    // exception, proven as a negative case against an ordinary Wed-Fri
    // row.

    func testFamilyCDeloadWeightIsUnchangedMondayTuesdayHalvedThereafter() {
        let strategy = SourceCompatibleDeloadStrategy()
        let rules = StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.95, laterWeekMultipliers: [1.05, 1.075, 1.1])),
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 3)),
            repGoalSchedule: [RepGoal.rir(8)],
            deloadWeightPositionOverride: DeloadPositionOverride(boundaryDayIndex: 2, fullPositionFactor: 1.0, halfPositionFactor: 0.5)
        )
        // Week1 = 95 (proven above).
        let mondayDeload = strategy.resolveDeloadWeight(rules: rules, dayPositionInWeek: 0, dayCount: 5, weekOneResolvedWeightKg: 95, equipmentProfile: barbellFive)
        XCTAssertEqual(mondayDeload.weightKg ?? -1, 95, accuracy: 0.0001, "Monday/Tuesday: no reduction at all")
        let wednesdayDeload = strategy.resolveDeloadWeight(rules: rules, dayPositionInWeek: 2, dayCount: 5, weekOneResolvedWeightKg: 95, equipmentProfile: barbellFive)
        XCTAssertEqual(wednesdayDeload.weightKg ?? -1, 50, accuracy: 0.0001, "Wednesday onward: halved")
    }

    func testFamilyCFridayBackoffRepsAreTheSoleDeloadExceptionUnchanged() {
        let strategy = SourceCompatibleDeloadStrategy()
        let ordinaryRow = StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.95, laterWeekMultipliers: [1.05, 1.075, 1.1])),
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 3, freezeAfterWeek: 2)),
            repGoalSchedule: [RepGoal.rir(8)]
        )
        let backoffRow = StrengthProgressionRules(
            loadRule: .linkedToPairedSlot(fractionOfSourceResult: 0.85 / 0.95),
            setCountRule: .fixed(setsByWeek: [2, 2, 2, 2]),
            repGoalSchedule: [RepGoal.rir(8)],
            deloadRepFraction: 1.0
        )
        // Stage 10R.1D: see the Family B Triples test above for why this
        // is now unresolved rather than fabricated — applies uniformly
        // regardless of the (now-corrected) day-position exception.
        let ordinaryDeloadRep = strategy.resolveDeloadRepGoal(rules: ordinaryRow)
        XCTAssertNil(ordinaryDeloadRep.repGoal, "never fabricate a deload rep count from the template")
        XCTAssertEqual(ordinaryDeloadRep.reasonCode, .deloadRepsRequireLoggedPerformanceData)

        let backoffDeloadRep = strategy.resolveDeloadRepGoal(rules: backoffRow)
        XCTAssertNil(backoffDeloadRep.repGoal, "never fabricate a deload rep count from the template")
        XCTAssertEqual(backoffDeloadRep.reasonCode, .deloadRepsRequireLoggedPerformanceData)
    }

    // MARK: - §Metric-native, no lb-specific rounding leakage

    /// Every family's arithmetic runs through the same
    /// `IdealLoad -> EquipmentProfile.resolve()` split — no rule stores or
    /// assumes a rounding increment itself (`METRIC_LOAD_MODEL.md`).
    /// Swapping the `EquipmentProfile`'s increment changes the resolved
    /// number without touching the rule at all.
    func testResolvedWeightChangesOnlyWithEquipmentProfileNeverWithTheRuleItself() {
        let rules = StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm5, weekOneFactor: 0.7, laterWeekMultipliers: [1.05, 1.075, 1.1])),
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 3)),
            repGoalSchedule: Array(repeating: RepGoal.fixedReps(3), count: 4)
        )
        let withBarbell = StrengthProgressionEngine.resolveWeight(rules: rules, weekIndex: 0, rmKilograms: 100, weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: nil, equipmentProfile: barbell)
        let withFiveKgPlates = StrengthProgressionEngine.resolveWeight(rules: rules, weekIndex: 0, rmKilograms: 100, weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: nil, equipmentProfile: barbellFive)
        XCTAssertEqual(withBarbell.weightKg ?? -1, 70, accuracy: 0.0001)
        XCTAssertEqual(withFiveKgPlates.weightKg ?? -1, 70, accuracy: 0.0001, "70 happens to be a clean multiple of both 2.5 and 5")

        let dumbbellQuarterKg = EquipmentProfile(equipmentType: .dumbbell, smallestIncrementKg: 0.25)
        let fineGrained = StrengthProgressionEngine.resolveWeight(rules: rules, weekIndex: 0, rmKilograms: 100.3, weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: nil, equipmentProfile: dumbbellQuarterKg)
        // 100.3 * 0.7 = 70.21 -> nearest 0.25 = 70.25, proving the
        // increment alone (not the rule) determines rounding granularity.
        XCTAssertEqual(fineGrained.weightKg ?? -1, 70.25, accuracy: 0.0001)
    }
}
