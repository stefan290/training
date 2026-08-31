import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 6B: `RecordSteadyStateResultUseCase`/`RecordIntervalResultUseCase`
/// — the identified Stage 6A gap, mirroring `RecordSetResultUseCase`'s
/// exact shape. Also covers the widened `isFirstEverEntry` return value
/// on every recording use case (`STAGE6A_DECISION_MEMO.md` §1b).
@MainActor
final class RecordEnduranceResultUseCaseTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    // MARK: - Steady state

    func testRecordSteadyStateResultAttachesToBlockAndActivityProfile() throws {
        let profile = PerformanceProfile()
        context.insert(profile)
        let block = WorkoutBlock(type: .steadyState, status: .active)
        context.insert(block)

        let result = SteadyStateResult(actualDurationSeconds: 2_700, actualDistanceMeters: 15_000)
        let outcome = RecordSteadyStateResultUseCase.recordResult(
            result, for: block, activityType: .cycling, prCandidateValue: nil,
            scoringDirection: .higherIsBetter, performanceProfile: profile, modelContext: context
        )

        XCTAssertEqual(block.steadyStateResult?.id, result.id)
        let activityProfile = try XCTUnwrap(profile.activityProfile(for: .cycling))
        XCTAssertEqual(activityProfile.steadyStateResults.count, 1)
        XCTAssertEqual(activityProfile.lastPerformedAt, result.completedAt)
        XCTAssertFalse(outcome.isFirstEverEntry, "no PR candidate supplied — never claims a first-entry PR")
    }

    func testRecordSteadyStateResultWithNilCandidateNeverCreatesAPersonalRecord() {
        let profile = PerformanceProfile()
        context.insert(profile)
        let block = WorkoutBlock(type: .steadyState, status: .active)
        context.insert(block)

        let result = SteadyStateResult(actualDurationSeconds: 1_800)
        RecordSteadyStateResultUseCase.recordResult(
            result, for: block, activityType: .running, prCandidateValue: nil,
            scoringDirection: .higherIsBetter, performanceProfile: profile, modelContext: context
        )

        XCTAssertNil(result.personalRecord)
    }

    func testRecordSteadyStateResultFirstEntryCreatesAPersonalRecordAndReportsFirstEverEntry() throws {
        let profile = PerformanceProfile()
        context.insert(profile)
        let block = WorkoutBlock(type: .steadyState, status: .active)
        context.insert(block)

        let result = SteadyStateResult(actualDurationSeconds: 2_700)
        let outcome = RecordSteadyStateResultUseCase.recordResult(
            result, for: block, activityType: .running, prCandidateValue: 2_700,
            scoringDirection: .higherIsBetter, performanceProfile: profile, modelContext: context
        )

        XCTAssertTrue(outcome.isFirstEverEntry)
        let activityProfile = try XCTUnwrap(profile.activityProfile(for: .running))
        XCTAssertEqual(activityProfile.personalRecords.count, 1)
        XCTAssertEqual(activityProfile.personalRecords.first?.sourceSteadyStateResult?.id, result.id)
    }

    func testRecordSteadyStateResultSecondBetterEntryIsNotFirstEverButIsStillAPR() throws {
        let profile = PerformanceProfile()
        context.insert(profile)
        let blockA = WorkoutBlock(type: .steadyState, status: .completed)
        context.insert(blockA)
        let firstResult = SteadyStateResult(actualDurationSeconds: 1_800)
        RecordSteadyStateResultUseCase.recordResult(
            firstResult, for: blockA, activityType: .running, prCandidateValue: 1_800,
            scoringDirection: .higherIsBetter, performanceProfile: profile, modelContext: context
        )

        let blockB = WorkoutBlock(type: .steadyState, status: .active)
        context.insert(blockB)
        let secondResult = SteadyStateResult(actualDurationSeconds: 2_400)
        let outcome = RecordSteadyStateResultUseCase.recordResult(
            secondResult, for: blockB, activityType: .running, prCandidateValue: 2_400,
            scoringDirection: .higherIsBetter, performanceProfile: profile, modelContext: context
        )

        XCTAssertFalse(outcome.isFirstEverEntry)
        let activityProfile = try XCTUnwrap(profile.activityProfile(for: .running))
        XCTAssertEqual(activityProfile.personalRecords.count, 2)
    }

    // MARK: - Interval

    func testRecordIntervalResultAttachesToBlockAndPreservesPerRepRows() {
        let profile = PerformanceProfile()
        context.insert(profile)
        let block = WorkoutBlock(type: .intervals, status: .active)
        context.insert(block)

        let result = IntervalResult(sessionDurationSeconds: 1_200)
        let repA = IntervalRepResult(actualWorkDurationSeconds: 240)
        let repB = IntervalRepResult(actualWorkDurationSeconds: 235, wasCompletedAsPrescribed: false)
        result.addRepResult(repA)
        result.addRepResult(repB)

        RecordIntervalResultUseCase.recordResult(
            result, for: block, activityType: .running, prCandidateValue: nil,
            scoringDirection: .higherIsBetter, performanceProfile: profile, modelContext: context
        )

        XCTAssertEqual(block.intervalResult?.id, result.id)
        XCTAssertEqual(result.orderedRepResults.count, 2, "per-interval rows are never collapsed into an average")
        XCTAssertFalse(result.orderedRepResults[1].wasCompletedAsPrescribed)
    }

    func testRecordIntervalResultFirstEntryReportsFirstEverEntryAndCreatesRecord() throws {
        let profile = PerformanceProfile()
        context.insert(profile)
        let block = WorkoutBlock(type: .intervals, status: .active)
        context.insert(block)

        let result = IntervalResult(sessionDurationSeconds: 1_200)
        let outcome = RecordIntervalResultUseCase.recordResult(
            result, for: block, activityType: .rowing, prCandidateValue: 5, scoringDirection: .higherIsBetter,
            performanceProfile: profile, modelContext: context
        )

        XCTAssertTrue(outcome.isFirstEverEntry)
        let activityProfile = try XCTUnwrap(profile.activityProfile(for: .rowing))
        XCTAssertEqual(activityProfile.personalRecords.first?.sourceIntervalResult?.id, result.id)
    }

    // MARK: - Widened return values on existing recording use cases (§1b)

    func testRecordSetResultReportsFirstEverEntryOnlyForTheTrueFirstEntry() throws {
        let profile = PerformanceProfile()
        context.insert(profile)
        let exercise = Exercise(canonicalName: "Barbell Back Squat", modality: .hypertrophy, equipment: "barbell", movementPattern: "squat")
        context.insert(exercise)
        let prescription = ExercisePrescription(exercise: exercise)
        context.insert(prescription)

        let first = RecordSetResultUseCase.recordSet(
            setIndex: 0, weight: 100, reps: 8, targetRir: 2, actualRir: 2, prBand: "8-12",
            scoringDirection: .higherIsBetter, context: .rx, setPrescription: nil,
            exercisePrescription: prescription, exercise: exercise, performanceProfile: profile,
            completedAt: Date(timeIntervalSince1970: 1_000), modelContext: context
        )
        XCTAssertTrue(first.isFirstEverEntry)
        XCTAssertTrue(first.result.isPersonalRecord)

        let second = RecordSetResultUseCase.recordSet(
            setIndex: 0, weight: 105, reps: 8, targetRir: 2, actualRir: 2, prBand: "8-12",
            scoringDirection: .higherIsBetter, context: .rx, setPrescription: nil,
            exercisePrescription: prescription, exercise: exercise, performanceProfile: profile,
            completedAt: Date(timeIntervalSince1970: 2_000), modelContext: context
        )
        XCTAssertFalse(second.isFirstEverEntry)
        XCTAssertTrue(second.result.isPersonalRecord, "still a genuine PR — just not a first-ever entry")
    }

    func testRecordFunctionalFitnessResultReportsFirstEverEntryOnlyForBenchmarkAttempts() throws {
        let profile = PerformanceProfile()
        context.insert(profile)
        let benchmark = BenchmarkDefinition(
            canonicalID: "benchmark.fran", name: "Fran",
            stimulus: Stimulus(
                targetDurationDomain: .medium, intensity: .moderate, loading: .moderate,
                movementFunctions: [.gymnasticsPull], movementModalityMix: [], skillDemand: .moderate,
                systemicDemand: .moderate, scoreType: .time
            ),
            format: .forTime(capSeconds: 600), scoreType: .time, scoreDirection: .lowerIsBetter
        )
        context.insert(benchmark)
        let block = WorkoutBlock(type: .functionalFitness, status: .active)
        context.insert(block)

        // Stage FF.E1: explicitly confirmed — this test's subject is
        // first-ever-entry-for-benchmark detection, not adherence.
        let result = FunctionalFitnessResult(scoreType: .time, scoreValue: .time(seconds: 298), scoreDirection: .lowerIsBetter, adherence: .asPrescribed)
        let outcome = RecordFunctionalFitnessResultUseCase.recordResult(
            result, for: block, benchmark: benchmark, performanceProfile: profile, modelContext: context
        )

        XCTAssertTrue(outcome.isFirstEverEntry)
    }
}
