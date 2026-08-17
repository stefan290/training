import XCTest
import SwiftData
@testable import TrainingOS

/// Real SwiftData round-trip coverage for Slice 7's incremental interval
/// persistence: `LogIntervalRepUseCase` (durable the instant each interval
/// finishes, CLAUDE.md rule 20) and `FinalizeIntervalResultUseCase` (the
/// later, idempotent finalize step — never the first durability point).
@MainActor
final class IntervalExecutionUseCaseTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func freshContext() -> ModelContext {
        ModelContext(container)
    }

    private func makeBlock() -> WorkoutBlock {
        let block = WorkoutBlock(type: .intervals, status: .active)
        context.insert(block)
        return block
    }

    func testFirstLoggedRepCreatesAndAttachesAnIntervalResult() throws {
        let block = makeBlock()
        let rep = IntervalRepResult(actualWorkDurationSeconds: 30, wasCompletedAsPrescribed: true)

        try LogIntervalRepUseCase.logRep(rep, for: block, modelContext: context)

        XCTAssertNotNil(block.intervalResult)
        XCTAssertEqual(block.intervalResult?.repResults.count, 1)
    }

    /// Never collapsed into a session average — each rep survives as its
    /// own row, in order.
    func testMultipleRepsAccumulateIndividuallyNeverAveraged() throws {
        let block = makeBlock()
        try LogIntervalRepUseCase.logRep(IntervalRepResult(actualWorkDurationSeconds: 30, wasCompletedAsPrescribed: true), for: block, modelContext: context)
        try LogIntervalRepUseCase.logRep(IntervalRepResult(actualWorkDurationSeconds: 28, wasCompletedAsPrescribed: false), for: block, modelContext: context)
        try LogIntervalRepUseCase.logRep(IntervalRepResult(actualWorkDurationSeconds: 31, wasCompletedAsPrescribed: true), for: block, modelContext: context)

        let ordered = try XCTUnwrap(block.intervalResult).orderedRepResults
        XCTAssertEqual(ordered.map(\.actualWorkDurationSeconds), [30, 28, 31])
        XCTAssertEqual(ordered.map(\.wasCompletedAsPrescribed), [true, false, true])
    }

    /// A crash before "Finish" must lose at most the one unconfirmed rep
    /// in flight, never anything already confirmed (CLAUDE.md rule 20) —
    /// simulated here by fetching from a completely fresh ModelContext
    /// without ever calling `FinalizeIntervalResultUseCase`.
    func testLoggedRepsSurviveIndependentlyOfFinalizing() throws {
        let blockID = UUID()
        let block = WorkoutBlock(id: blockID, type: .intervals, status: .active)
        context.insert(block)
        try LogIntervalRepUseCase.logRep(IntervalRepResult(actualWorkDurationSeconds: 30, wasCompletedAsPrescribed: true), for: block, modelContext: context)

        let fetchContext = freshContext()
        let reloadedBlock = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<WorkoutBlock>(predicate: #Predicate { $0.id == blockID })).first)

        XCTAssertEqual(reloadedBlock.intervalResult?.repResults.count, 1)
    }

    private func makeUserWithPerformanceProfile() -> (User, PerformanceProfile) {
        let profile = PerformanceProfile()
        context.insert(profile)
        let user = User(displayName: "Test User")
        context.insert(user)
        user.attachPerformanceProfile(profile)
        return (user, profile)
    }

    func testFinalizeFillsInSessionSummaryAndAttachesToActivityProfile() throws {
        let block = makeBlock()
        try LogIntervalRepUseCase.logRep(IntervalRepResult(actualWorkDurationSeconds: 30, wasCompletedAsPrescribed: true), for: block, modelContext: context)
        let (_, performanceProfile) = makeUserWithPerformanceProfile()

        let result = try XCTUnwrap(block.intervalResult)
        let outcome = try FinalizeIntervalResultUseCase.finalize(
            result, activityType: .running, sessionDurationSeconds: 300, sessionDistanceMeters: 1200,
            averagePaceSecondsPerKilometer: nil, averageHeartRate: 150, rpe: 7,
            prCandidateValue: 1200, scoringDirection: .higherIsBetter, performanceProfile: performanceProfile, modelContext: context
        )

        XCTAssertEqual(outcome.result.sessionDistanceMeters, 1200)
        XCTAssertEqual(outcome.result.rpe, 7)
        XCTAssertTrue(outcome.isFirstEverEntry)
        XCTAssertTrue(performanceProfile.activityProfile(for: .running, context: nil)?.intervalResults.contains(where: { $0.id == result.id }) ?? false)
    }

    /// Idempotent: a double-tapped Finish must never duplicate this
    /// result inside the ActivityPerformanceProfile.
    func testFinalizeCalledTwiceNeverDuplicatesInActivityProfile() throws {
        let block = makeBlock()
        try LogIntervalRepUseCase.logRep(IntervalRepResult(actualWorkDurationSeconds: 30, wasCompletedAsPrescribed: true), for: block, modelContext: context)
        let (_, performanceProfile) = makeUserWithPerformanceProfile()
        let result = try XCTUnwrap(block.intervalResult)

        try FinalizeIntervalResultUseCase.finalize(
            result, activityType: .running, sessionDurationSeconds: 300, sessionDistanceMeters: 1200,
            averagePaceSecondsPerKilometer: nil, averageHeartRate: nil, rpe: nil,
            prCandidateValue: nil, scoringDirection: .none, performanceProfile: performanceProfile, modelContext: context
        )
        try FinalizeIntervalResultUseCase.finalize(
            result, activityType: .running, sessionDurationSeconds: 999, sessionDistanceMeters: 999,
            averagePaceSecondsPerKilometer: nil, averageHeartRate: nil, rpe: nil,
            prCandidateValue: nil, scoringDirection: .none, performanceProfile: performanceProfile, modelContext: context
        )

        let activityProfile = try XCTUnwrap(performanceProfile.activityProfile(for: .running, context: nil))
        XCTAssertEqual(activityProfile.intervalResults.filter { $0.id == result.id }.count, 1)
        // The second (would-be) finalize never overwrote the first's real values.
        XCTAssertEqual(result.sessionDurationSeconds, 300)
    }
}
