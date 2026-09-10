import XCTest
@testable import TrainingOS

/// Running R2.9/Testing R: the graduated pain re-entry ladder. Execution
/// safety state only — no medical diagnosis logic.
final class RunningPainResponseEngineTests: XCTestCase {
    func testPainReportedEntersStoppedStage() {
        XCTAssertEqual(RunningPainResponseEngine.onPainReported(), .stopped)
    }

    func testFullGradualProgressionWhenPainFreeAtEveryStage() {
        var stage = RunningPainResponseEngine.onPainReported()
        XCTAssertEqual(stage, .stopped)
        stage = RunningPainResponseEngine.nextStage(current: stage, painFreeAtCurrentStage: true)
        XCTAssertEqual(stage, .walking)
        stage = RunningPainResponseEngine.nextStage(current: stage, painFreeAtCurrentStage: true)
        XCTAssertEqual(stage, .joggingSlowly)
        stage = RunningPainResponseEngine.nextStage(current: stage, painFreeAtCurrentStage: true)
        XCTAssertEqual(stage, .joggingSlightlyFaster)
        stage = RunningPainResponseEngine.nextStage(current: stage, painFreeAtCurrentStage: true)
        XCTAssertEqual(stage, .fullPrescribedPace)
    }

    func testRecurrenceAtAnyStageForcesImmediatePermanentStop() {
        for startingStage: RunningPainReentryStage in [.stopped, .walking, .joggingSlowly, .joggingSlightlyFaster] {
            let result = RunningPainResponseEngine.nextStage(current: startingStage, painFreeAtCurrentStage: false)
            XCTAssertEqual(result, .discontinuedSeekMedicalAdvice, "recurrence at \(startingStage) must force a full stop")
        }
    }

    func testDiscontinuedStageIsTerminalRegardlessOfFutureInput() {
        let stillDiscontinued = RunningPainResponseEngine.nextStage(current: .discontinuedSeekMedicalAdvice, painFreeAtCurrentStage: true)
        XCTAssertEqual(stillDiscontinued, .discontinuedSeekMedicalAdvice)
    }

    func testFullPrescribedPaceStageIsStableOnceReached() {
        let stage = RunningPainResponseEngine.nextStage(current: .fullPrescribedPace, painFreeAtCurrentStage: true)
        XCTAssertEqual(stage, .fullPrescribedPace)
    }
}
