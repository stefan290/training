import XCTest
@testable import TrainingOS

/// Pure rule-arithmetic tests for `HypertrophyProgressionEngine` and
/// `SourceCompatibleDeloadStrategy` — no `ModelContext` needed, same
/// discipline as `DoubleProgressionEngineTests`. Every numeric fixture
/// here is **CONSTRUCTED** (RM=100, chosen for arithmetic convenience) per
/// `PROGRAM_REGRESSION_TEST_PLAN.md` — no real Family A source workbook
/// survives in this repository to derive sourced fixtures from (confirmed
/// by this pass's own research; see `STAGE4_IMPLEMENTATION_REPORT.md`).
/// Every formula transcribed here is still cited to its
/// `PROGRAM_LOGIC_SPEC.md` rule name and this plan's own section number.
final class HypertrophyProgressionEngineTests: XCTestCase {
    private let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)

    // MARK: - §4.1 Load progression (CONSTRUCTED, RM=100)
    //
    // Week1 = MROUND(100×0.85, 2.5) = 85
    // Week2 = MROUND(85×1.05, 2.5) = 90
    // Week3 = MROUND(85×1.075, 2.5) = 92.5
    // Week4 = MROUND(85×1.1, 2.5) = 92.5
    // — always off the resolved Week-1 cell, never compounding
    // (`FAMILY_A_WEEKLY_PROGRESSION`).

    func testLoadProgressionAcrossFourWeeks() {
        let rules = StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.85, laterWeekMultipliers: [1.05, 1.075, 1.1])),
            setCountRule: .fixed(setsByWeek: [3, 3, 3, 3]),
            repGoalSchedule: [RepGoal(reps: 3, toFailure: true)]
        )

        let week1 = HypertrophyProgressionEngine.resolveWeight(
            rules: rules, weekIndex: 0, rmKilograms: 100, weekOneResolvedWeightKg: nil,
            pairedSlotResolvedWeightKg: nil, equipmentProfile: equipment
        )
        XCTAssertEqual(week1.weightKg ?? -1, 85, accuracy: 0.0001)
        XCTAssertEqual(week1.reasonCode, .rmBasedLoad)

        let week1Resolved = try! XCTUnwrap(week1.weightKg)

        let week2 = HypertrophyProgressionEngine.resolveWeight(
            rules: rules, weekIndex: 1, rmKilograms: nil, weekOneResolvedWeightKg: week1Resolved,
            pairedSlotResolvedWeightKg: nil, equipmentProfile: equipment
        )
        XCTAssertEqual(week2.weightKg ?? -1, 90, accuracy: 0.0001)

        let week3 = HypertrophyProgressionEngine.resolveWeight(
            rules: rules, weekIndex: 2, rmKilograms: nil, weekOneResolvedWeightKg: week1Resolved,
            pairedSlotResolvedWeightKg: nil, equipmentProfile: equipment
        )
        XCTAssertEqual(week3.weightKg ?? -1, 92.5, accuracy: 0.0001)

        let week4 = HypertrophyProgressionEngine.resolveWeight(
            rules: rules, weekIndex: 3, rmKilograms: nil, weekOneResolvedWeightKg: week1Resolved,
            pairedSlotResolvedWeightKg: nil, equipmentProfile: equipment
        )
        XCTAssertEqual(week4.weightKg ?? -1, 92.5, accuracy: 0.0001)
    }

    func testLoadResolutionRequiresRMOnWeekOne() {
        let rules = StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.85, laterWeekMultipliers: [1.05])),
            setCountRule: .fixed(setsByWeek: [3]),
            repGoalSchedule: [RepGoal(reps: 3)]
        )
        let result = HypertrophyProgressionEngine.resolveWeight(
            rules: rules, weekIndex: 0, rmKilograms: nil, weekOneResolvedWeightKg: nil,
            pairedSlotResolvedWeightKg: nil, equipmentProfile: equipment
        )
        XCTAssertNil(result.weightKg)
        XCTAssertEqual(result.reasonCode, .calibrationRequired)
    }

    func testNoLoadRuleNeverProducesAWeight() {
        let rules = StrengthProgressionRules(loadRule: .none, setCountRule: .fixed(setsByWeek: [3]), repGoalSchedule: [RepGoal(reps: 12)])
        let result = HypertrophyProgressionEngine.resolveWeight(
            rules: rules, weekIndex: 0, rmKilograms: 100, weekOneResolvedWeightKg: nil,
            pairedSlotResolvedWeightKg: nil, equipmentProfile: equipment
        )
        XCTAssertNil(result.weightKg)
        XCTAssertEqual(result.reasonCode, .noLoadProgression)
    }

    /// `linkedResultReference`: reads the paired slot's *current week's*
    /// resolved value every week, not just Week 1 — the fraction is
    /// constant (0.6 here), but the paired slot's own value already
    /// progresses on its own rules.
    func testLinkedToPairedSlotTracksPairedSlotEveryWeek() {
        let rules = StrengthProgressionRules(
            loadRule: .linkedToPairedSlot(fractionOfSourceResult: 0.6),
            setCountRule: .fixed(setsByWeek: [2, 2, 2, 2]),
            repGoalSchedule: [RepGoal(reps: 12)]
        )
        let week1 = HypertrophyProgressionEngine.resolveWeight(
            rules: rules, weekIndex: 0, rmKilograms: nil, weekOneResolvedWeightKg: nil,
            pairedSlotResolvedWeightKg: 85, equipmentProfile: equipment
        )
        XCTAssertEqual(week1.weightKg ?? -1, 50, accuracy: 0.0001) // MROUND(85*0.6, 2.5) = MROUND(51, 2.5) = 50
        XCTAssertEqual(week1.reasonCode, .linkedToPairedSlotLoad)

        let week2 = HypertrophyProgressionEngine.resolveWeight(
            rules: rules, weekIndex: 1, rmKilograms: nil, weekOneResolvedWeightKg: nil,
            pairedSlotResolvedWeightKg: 90, equipmentProfile: equipment
        )
        XCTAssertEqual(week2.weightKg ?? -1, 55, accuracy: 0.0001) // MROUND(90*0.6, 2.5) = MROUND(54, 2.5) = 55
    }

    // MARK: - §4.2 Autoregulation with a negative rating (CONSTRUCTED)
    //
    // Compound baseline = 3 sets. Week2 rating +1 -> 4. Week3 rating 0 ->
    // 4. Week4 rating -1 -> 3. Proves subtraction works, not just
    // addition — no sourced Family A/B fixture exercises a negative
    // rating.

    func testAutoregulatedSetCountAcrossFourWeeksWithNegativeRating() {
        let rules = StrengthProgressionRules(
            loadRule: .none,
            setCountRule: .autoregulated(baselineSets: 3),
            repGoalSchedule: [RepGoal(reps: 3, toFailure: true)]
        )

        let week1 = HypertrophyProgressionEngine.resolveSetCount(rules: rules, weekIndex: 0, previousWeekSetCount: nil, autoregulationRating: nil)
        XCTAssertEqual(week1.sets, 3)
        XCTAssertEqual(week1.reasonCode, .fixedSetSchedule)

        let week2 = HypertrophyProgressionEngine.resolveSetCount(rules: rules, weekIndex: 1, previousWeekSetCount: 3, autoregulationRating: 1)
        XCTAssertEqual(week2.sets, 4)
        XCTAssertEqual(week2.reasonCode, .autoregulatedSetIncrease)

        let week3 = HypertrophyProgressionEngine.resolveSetCount(rules: rules, weekIndex: 2, previousWeekSetCount: 4, autoregulationRating: 0)
        XCTAssertEqual(week3.sets, 4)
        XCTAssertEqual(week3.reasonCode, .autoregulatedSetHold)

        let week4 = HypertrophyProgressionEngine.resolveSetCount(rules: rules, weekIndex: 3, previousWeekSetCount: 4, autoregulationRating: -1)
        XCTAssertEqual(week4.sets, 3)
        XCTAssertEqual(week4.reasonCode, .autoregulatedSetDecrease)
    }

    func testAutoregulatedSetCountNeverGoesNegative() {
        let rules = StrengthProgressionRules(loadRule: .none, setCountRule: .autoregulated(baselineSets: 0), repGoalSchedule: [RepGoal(reps: 3)])
        let result = HypertrophyProgressionEngine.resolveSetCount(rules: rules, weekIndex: 1, previousWeekSetCount: 0, autoregulationRating: -1)
        XCTAssertEqual(result.sets, 0)
    }

    func testFixedSetScheduleIsAPlainLookup() {
        let rules = StrengthProgressionRules(loadRule: .none, setCountRule: .fixed(setsByWeek: [2, 2, 2, 2]), repGoalSchedule: [RepGoal(reps: 12)])
        for week in 0..<4 {
            let result = HypertrophyProgressionEngine.resolveSetCount(rules: rules, weekIndex: week, previousWeekSetCount: nil, autoregulationRating: nil)
            XCTAssertEqual(result.sets, 2)
            XCTAssertEqual(result.reasonCode, .fixedSetSchedule)
        }
    }

    // MARK: - §4.3 Deload weight day-boundary (CONSTRUCTED, 4-day, boundary = ceil(4/2) = 2)
    //
    // Day 1-2 (indices 0-1) = 85 unchanged. Day 3-4 (indices 2-3) =
    // MROUND(85×0.5, 2.5) = 42.5.

    func testDeloadWeightDayBoundaryFourDayProgram() {
        let rules = StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.85, laterWeekMultipliers: [1.05, 1.075, 1.1])),
            setCountRule: .fixed(setsByWeek: [3, 3, 3, 3]),
            repGoalSchedule: [RepGoal(reps: 3, toFailure: true)]
        )
        let strategy = SourceCompatibleDeloadStrategy()

        for day in 0...1 {
            let result = strategy.resolveDeloadWeight(rules: rules, dayPositionInWeek: day, dayCount: 4, weekOneResolvedWeightKg: 85, equipmentProfile: equipment)
            XCTAssertEqual(result.weightKg ?? -1, 85, accuracy: 0.0001, "day \(day) should be full Week-1 weight")
            XCTAssertEqual(result.reasonCode, .deloadWeightPrescribed)
        }
        for day in 2...3 {
            let result = strategy.resolveDeloadWeight(rules: rules, dayPositionInWeek: day, dayCount: 4, weekOneResolvedWeightKg: 85, equipmentProfile: equipment)
            XCTAssertEqual(result.weightKg ?? -1, 42.5, accuracy: 0.0001, "day \(day) should be half Week-1 weight")
        }
    }

    func testDeloadWeightOmittedForConfirmedSupersetPartner() {
        let rules = StrengthProgressionRules(
            loadRule: .linkedToPairedSlot(fractionOfSourceResult: 0.6),
            setCountRule: .fixed(setsByWeek: [2, 2, 2, 2]),
            repGoalSchedule: [RepGoal(reps: 12)],
            deloadWeightAction: .omit,
            deloadRepAction: .omit
        )
        let strategy = SourceCompatibleDeloadStrategy()
        let result = strategy.resolveDeloadWeight(rules: rules, dayPositionInWeek: 0, dayCount: 4, weekOneResolvedWeightKg: 52.5, equipmentProfile: equipment)
        XCTAssertNil(result.weightKg)
        XCTAssertEqual(result.reasonCode, .deloadWeightOmitted)
    }

    /// Deload-week sets are a hardcoded constant (2) regardless of the
    /// slot's normal `setCountRule` — even an otherwise-`.autoregulated`
    /// slot never autoregulates during deload.
    func testDeloadSetCountIsAHardcodedConstantRegardlessOfNormalSetCountRule() {
        let strategy = SourceCompatibleDeloadStrategy()
        let autoregulated = StrengthProgressionRules(loadRule: .none, setCountRule: .autoregulated(baselineSets: 5), repGoalSchedule: [RepGoal(reps: 3)])
        XCTAssertEqual(strategy.resolveDeloadSetCount(rules: autoregulated).sets, 2)

        let fixed = StrengthProgressionRules(loadRule: .none, setCountRule: .fixed(setsByWeek: [4, 4, 4, 4]), repGoalSchedule: [RepGoal(reps: 12)])
        XCTAssertEqual(strategy.resolveDeloadSetCount(rules: fixed).sets, 2)

        let omitted = StrengthProgressionRules(loadRule: .none, setCountRule: .fixed(setsByWeek: [2]), repGoalSchedule: [RepGoal(reps: 12)], deloadWeightAction: .omit)
        XCTAssertNil(strategy.resolveDeloadSetCount(rules: omitted).sets)
    }

    /// §9.2 negative case: the pair's *primary* exercise, same day, same
    /// deload week, must still compute a normal deload value — guards
    /// against an evaluator that omits the whole day-pair instead of just
    /// the one confirmed slot.
    func testDeloadOmitAppliesOnlyToTheConfirmedSlotNotItsPrimaryPartner() {
        let primaryRules = StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.85, laterWeekMultipliers: [1.05])),
            setCountRule: .autoregulated(baselineSets: 3),
            repGoalSchedule: [RepGoal(reps: 3, toFailure: true)],
            deloadWeightAction: .standard,
            deloadRepAction: .standard
        )
        let strategy = SourceCompatibleDeloadStrategy()
        let result = strategy.resolveDeloadWeight(rules: primaryRules, dayPositionInWeek: 0, dayCount: 4, weekOneResolvedWeightKg: 85, equipmentProfile: equipment)
        XCTAssertEqual(result.weightKg ?? -1, 85, accuracy: 0.0001)
        XCTAssertEqual(result.reasonCode, .deloadWeightPrescribed)
    }

    // MARK: - §9.1 Deload rep rounding (universal, always floor)
    //
    // 7 reps x 1/2 = 3.5 -> 3. 5 reps x 2/3 = 3.333 -> 3 (rules out
    // round-to-nearest coincidence — 2/3 is not Family A's own fraction,
    // exercised here purely to prove the rounding function itself, per
    // the regression plan's own stated purpose). 8 reps x 1/2 = 4.0 -> 4
    // (exact, sanity check).

    func testDeloadRepRoundingAlwaysFloors() {
        let strategy = SourceCompatibleDeloadStrategy()

        let sevenReps = StrengthProgressionRules(loadRule: .none, setCountRule: .fixed(setsByWeek: [3]), repGoalSchedule: [RepGoal(reps: 7, toFailure: true)], deloadRepFraction: 0.5)
        XCTAssertEqual(strategy.resolveDeloadRepGoal(rules: sevenReps).repGoal?.reps, 3)

        let fiveReps = StrengthProgressionRules(loadRule: .none, setCountRule: .fixed(setsByWeek: [3]), repGoalSchedule: [RepGoal(reps: 5, toFailure: true)], deloadRepFraction: 2.0 / 3.0)
        XCTAssertEqual(strategy.resolveDeloadRepGoal(rules: fiveReps).repGoal?.reps, 3)

        let eightReps = StrengthProgressionRules(loadRule: .none, setCountRule: .fixed(setsByWeek: [3]), repGoalSchedule: [RepGoal(reps: 8, toFailure: true)], deloadRepFraction: 0.5)
        XCTAssertEqual(strategy.resolveDeloadRepGoal(rules: eightReps).repGoal?.reps, 4)
    }

    func testDeloadRepOmittedForConfirmedSupersetPartner() {
        let rules = StrengthProgressionRules(
            loadRule: .linkedToPairedSlot(fractionOfSourceResult: 0.6),
            setCountRule: .fixed(setsByWeek: [2]),
            repGoalSchedule: [RepGoal(reps: 12)],
            deloadRepAction: .omit
        )
        let result = SourceCompatibleDeloadStrategy().resolveDeloadRepGoal(rules: rules)
        XCTAssertNil(result.repGoal)
        XCTAssertEqual(result.reasonCode, .deloadRepOmitted)
    }

    // MARK: - Rep goal schedule

    func testRepGoalScheduleIsAPlainLookup() {
        let rules = StrengthProgressionRules(
            loadRule: .none, setCountRule: .fixed(setsByWeek: [3, 3, 3, 3]),
            repGoalSchedule: [RepGoal(reps: 3, toFailure: true), RepGoal(reps: 3, toFailure: true), RepGoal(reps: 2, toFailure: true), RepGoal(reps: 1, toFailure: true)]
        )
        XCTAssertEqual(HypertrophyProgressionEngine.resolveRepGoal(rules: rules, weekIndex: 0).repGoal, RepGoal(reps: 3, toFailure: true))
        XCTAssertEqual(HypertrophyProgressionEngine.resolveRepGoal(rules: rules, weekIndex: 2).repGoal, RepGoal(reps: 2, toFailure: true))
        XCTAssertEqual(HypertrophyProgressionEngine.resolveRepGoal(rules: rules, weekIndex: 3).repGoal, RepGoal(reps: 1, toFailure: true))
    }
}
