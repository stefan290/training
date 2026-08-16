import XCTest
@testable import TrainingOS

/// `TACTICAL_PLANNING_HANDOFF.md` §1/§2 — window-length sizing and the
/// two date-driven regeneration triggers. Pure, deterministic — no
/// `ModelContext` needed.
final class TacticalWindowPolicyTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar.current.date(from: components)!
    }

    // MARK: - Window sizing (§1)

    func testHypertrophyUsesItsOwnFourWeekNaturalMesocycleBlock() {
        let days = TacticalWindowPolicy.windowLengthInDays(
            primarySystem: .hypertrophy, asOf: date(2026, 1, 1), phaseEndDate: date(2027, 1, 1)
        )
        XCTAssertEqual(days, 28)
    }

    func testPowerliftingUsesItsOwnFourWeekNaturalMesocycleBlock() {
        let days = TacticalWindowPolicy.windowLengthInDays(
            primarySystem: .powerlifting, asOf: date(2026, 1, 1), phaseEndDate: date(2027, 1, 1)
        )
        XCTAssertEqual(days, 28)
    }

    func testSteadyStateFallsBackToTheConfigurableDefaultWhenNoNaturalBlockExists() {
        let days = TacticalWindowPolicy.windowLengthInDays(
            primarySystem: .steadyState, asOf: date(2026, 1, 1), phaseEndDate: date(2027, 1, 1)
        )
        XCTAssertEqual(days, TacticalWindowPolicy.fallbackWindowWeeks * 7)
    }

    func testWindowNeverExceedsThePhasesOwnRemainingTime() {
        // Phase ends in only 2 weeks — must cap the 4-week hypertrophy block.
        let days = TacticalWindowPolicy.windowLengthInDays(
            primarySystem: .hypertrophy, asOf: date(2026, 1, 1), phaseEndDate: date(2026, 1, 15)
        )
        XCTAssertEqual(days, 14)
    }

    func testWindowNeverExceedsAKnownUpcomingTransitionDateEvenWhenThePhaseItselfRunsLonger() {
        let days = TacticalWindowPolicy.windowLengthInDays(
            primarySystem: .hypertrophy, asOf: date(2026, 1, 1), phaseEndDate: date(2027, 1, 1),
            upcomingTransitionDate: date(2026, 1, 10)
        )
        XCTAssertLessThan(days, 28)
    }

    func testNoPhaseEndDateAtAllUsesTheNaturalBlockUnmodified() {
        let days = TacticalWindowPolicy.windowLengthInDays(primarySystem: .hypertrophy, asOf: date(2026, 1, 1), phaseEndDate: nil)
        XCTAssertEqual(days, 28)
    }

    func testWindowIsNeverZeroOrNegativeEvenWithNoRemainingTime() {
        let days = TacticalWindowPolicy.windowLengthInDays(
            primarySystem: .hypertrophy, asOf: date(2026, 1, 1), phaseEndDate: date(2026, 1, 1)
        )
        XCTAssertGreaterThanOrEqual(days, 7)
    }

    // MARK: - Regeneration triggers (§2)

    func testNoTriggerFiresWellBeforeTheWindowsEnd() {
        let trigger = TacticalWindowTriggerEvaluator.evaluate(currentWindowEndDate: date(2026, 2, 1), asOf: date(2026, 1, 1))
        XCTAssertNil(trigger)
    }

    func testApproachingEndFiresWithinTheConfiguredBuffer() {
        let trigger = TacticalWindowTriggerEvaluator.evaluate(currentWindowEndDate: date(2026, 1, 10), asOf: date(2026, 1, 5))
        XCTAssertEqual(trigger, .windowApproachingEnd)
    }

    func testWindowCompletedFiresOnceTheWindowHasFullyElapsed() {
        let trigger = TacticalWindowTriggerEvaluator.evaluate(currentWindowEndDate: date(2026, 1, 10), asOf: date(2026, 1, 10))
        XCTAssertEqual(trigger, .windowCompleted)
    }

    func testNoCurrentWindowYieldsNoDateBasedTrigger() {
        let trigger = TacticalWindowTriggerEvaluator.evaluate(currentWindowEndDate: nil, asOf: date(2026, 1, 1))
        XCTAssertNil(trigger)
    }

    func testDeterministicAcrossRepeatedCalls() {
        let first = TacticalWindowPolicy.windowLengthInDays(primarySystem: .functionalFitness, asOf: date(2026, 3, 1), phaseEndDate: date(2026, 6, 1))
        let second = TacticalWindowPolicy.windowLengthInDays(primarySystem: .functionalFitness, asOf: date(2026, 3, 1), phaseEndDate: date(2026, 6, 1))
        XCTAssertEqual(first, second)
    }
}
