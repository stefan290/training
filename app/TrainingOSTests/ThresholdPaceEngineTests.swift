import XCTest
@testable import TrainingOS

/// Running R2.2/Testing A/B: pure threshold-pace math, no `ModelContext`
/// needed — same discipline as `StrengthProgressionEngineTests`. Every
/// pace fixture here is a SOURCE FACT, independently re-verified via
/// `openpyxl` against `RP_5K_TrainingPeaks_Reference.xlsx`'s `Intensity
/// Map` sheet (13 rows) and `Workout Blocks`' own `Source Pace min/km`
/// column (13 distinct values, same 13) at the captured threshold
/// 5:00/km = 300s — `RUNNING_PROGRAMMING_MODEL_R1.md` §6, corrected count.
final class ThresholdPaceEngineTests: XCTestCase {
    private let thresholdSeconds = 300.0 // 5:00/km

    // MARK: A — dogfood-cited spot checks

    func testEightyPercentOfFiveMinuteThresholdIsSixFifteen() {
        let pace = ThresholdPaceEngine.targetPace(thresholdPaceSecondsPerKilometer: thresholdSeconds, percentOfThreshold: 0.80)
        XCTAssertEqual(pace.secondsPerKilometer, 375, accuracy: 0.0001)
    }

    func testOneHundredPercentOfThresholdEqualsThresholdItself() {
        let pace = ThresholdPaceEngine.targetPace(thresholdPaceSecondsPerKilometer: thresholdSeconds, percentOfThreshold: 1.00)
        XCTAssertEqual(pace.secondsPerKilometer, 300, accuracy: 0.0001)
    }

    func testOneHundredTenPercentOfThresholdIsApproximatelyFourThirtyThree() {
        let pace = ThresholdPaceEngine.targetPace(thresholdPaceSecondsPerKilometer: thresholdSeconds, percentOfThreshold: 1.10)
        // Source's own observed 110%-band pace is 04:33/km = 273s, at
        // %threshold 1.0989 (not exactly 1.10) — see the golden table
        // below for the exact reproduction. This spot check merely proves
        // ~110% lands in the same ballpark the dogfood proof cites.
        XCTAssertEqual(pace.secondsPerKilometer, 300 / 1.10, accuracy: 0.0001)
        XCTAssertEqual(pace.secondsPerKilometer, 272.7, accuracy: 0.1)
    }

    // MARK: B — all 13 observed source paces, golden, exact

    private struct Fixture { let displayPace: String; let observedSeconds: Double; let derivedPercent: Double }

    /// Independently re-verified this pass via `openpyxl` against
    /// `Intensity Map` (13 rows) and `Workout Blocks`' distinct
    /// `Source Pace min/km` values (13, identical set).
    private let goldenFixtures: [Fixture] = [
        Fixture(displayPace: "08:20", observedSeconds: 500, derivedPercent: 0.6),
        Fixture(displayPace: "07:09", observedSeconds: 429, derivedPercent: 0.6993006993006993),
        Fixture(displayPace: "06:40", observedSeconds: 400, derivedPercent: 0.75),
        Fixture(displayPace: "06:30", observedSeconds: 390, derivedPercent: 0.7692307692307693),
        Fixture(displayPace: "06:15", observedSeconds: 375, derivedPercent: 0.8),
        Fixture(displayPace: "05:45", observedSeconds: 345, derivedPercent: 0.8695652173913043),
        Fixture(displayPace: "05:33", observedSeconds: 333, derivedPercent: 0.9009009009009009),
        Fixture(displayPace: "05:23", observedSeconds: 323, derivedPercent: 0.9287925696594427),
        Fixture(displayPace: "05:16", observedSeconds: 316, derivedPercent: 0.9493670886075949),
        Fixture(displayPace: "05:09", observedSeconds: 309, derivedPercent: 0.970873786407767),
        Fixture(displayPace: "05:00", observedSeconds: 300, derivedPercent: 1.0),
        Fixture(displayPace: "04:46", observedSeconds: 286, derivedPercent: 1.048951048951049),
        Fixture(displayPace: "04:33", observedSeconds: 273, derivedPercent: 1.098901098901099),
    ]

    func testAllThirteenObservedPacesReproduceExactly() {
        XCTAssertEqual(goldenFixtures.count, 13, "R1 correction: exactly 13 distinct observed paces, not 14")
        for fixture in goldenFixtures {
            let computed = ThresholdPaceEngine.targetPace(thresholdPaceSecondsPerKilometer: thresholdSeconds, percentOfThreshold: fixture.derivedPercent)
            XCTAssertEqual(computed.secondsPerKilometer, fixture.observedSeconds, accuracy: 0.01, "\(fixture.displayPace) mismatch")

            let inversePercent = ThresholdPaceEngine.percentOfThreshold(pace: Pace(secondsPerKilometer: fixture.observedSeconds), thresholdPaceSecondsPerKilometer: thresholdSeconds)
            XCTAssertEqual(inversePercent, fixture.derivedPercent, accuracy: 0.0001, "\(fixture.displayPace) inverse mismatch")
        }
    }

    func testDisplayRoundingIsolatesSourceEstablishedFloorMinutesOnly() {
        let pace = Pace(secondsPerKilometer: 375) // 6:15
        let (minutes, seconds) = ThresholdPaceEngine.displayMinutesAndSeconds(for: pace)
        XCTAssertEqual(minutes, 6)
        XCTAssertEqual(seconds, 15, accuracy: 0.0001)
    }

    // MARK: Regression — no artificial floor/ceiling, no TrainingPeaks Zone required

    func testSixtyPercentIsARepresentableValidPercentage() {
        let pace = ThresholdPaceEngine.targetPace(thresholdPaceSecondsPerKilometer: thresholdSeconds, percentOfThreshold: 0.60)
        XCTAssertEqual(pace.secondsPerKilometer, 500, accuracy: 0.0001)
    }

    func testOneHundredTenPercentIsRepresentable() {
        let target = IntensityTarget.percentOfReference(BoundedRange(lower: 1.10, upper: 1.10), metric: .thresholdPace)
        if case .percentOfReference(let range, let metric) = target {
            XCTAssertEqual(range.lower, 1.10)
            XCTAssertEqual(metric, .thresholdPace)
        } else {
            XCTFail("expected .percentOfReference")
        }
    }

    func testNoTrainingPeaksZoneIsRequiredToComputeATargetPace() {
        // `targetPace` never accepts a zone parameter at all — this is a
        // compile-time guarantee, not just a runtime assertion. The
        // function signature itself is the proof; this test exists so a
        // future signature change that added a zone parameter would be a
        // visible, deliberate diff.
        let pace = ThresholdPaceEngine.targetPace(thresholdPaceSecondsPerKilometer: 300, percentOfThreshold: 0.80)
        XCTAssertEqual(pace.secondsPerKilometer, 375, accuracy: 0.0001)
    }
}
