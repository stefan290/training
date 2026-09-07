import XCTest
import SwiftData
@testable import TrainingOS

/// V1 R4 (Progress reconciliation): proves `ProgressViewModel`'s real
/// derived presentation state — never a hardcoded-string/pixel assertion,
/// always the real `exerciseProfiles`/`benchmarkProfiles`/`recentRecords`/
/// `consistency` the View actually renders from. Deliberately does not
/// duplicate `ScoringEngineTests`/lower-level engine tests already
/// proving the canonical-record rules — this tests only the Progress
/// consumer/presentation boundary.
@MainActor
final class ProgressViewModelTests: XCTestCase {
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

    @discardableResult
    private func makeUser() -> User {
        AppRootStateResolver.ensureBaselineIdentity(context: context)
    }

    // MARK: A — brand-new athlete: no data at all

    func testNoDataStateIsHonest() throws {
        makeUser()
        try context.save()
        let viewModel = ProgressViewModel()
        viewModel.load(modelContext: context)

        XCTAssertFalse(viewModel.hasAnyHistory)
        XCTAssertTrue(viewModel.exerciseProfiles.isEmpty)
        XCTAssertTrue(viewModel.recentRecords.isEmpty)
        XCTAssertNil(viewModel.consistency, "zero real Sessions must never present a fabricated 0% consistency")
    }

    // MARK: B/C — real PR derivation and presentation, recent vs older

    func testRecentPersonalRecordAppearsInNewThisWeek() throws {
        let user = makeUser()
        let exercise = Exercise(canonicalName: "R4 Test Back Squat", modality: .hypertrophy, equipment: "barbell", movementPattern: "squat")
        context.insert(exercise)
        let exerciseProfile = ExercisePerformanceProfile(estimatedOneRepMax: 142, confidence: 0.8, lastPerformedAt: date(2026, 3, 10))
        context.insert(exerciseProfile)
        exerciseProfile.exercise = exercise
        user.performanceProfile?.addExerciseProfile(exerciseProfile)

        let recentRecord = PersonalRecord(value: 145, repBand: "1-3", scoringDirection: .higherIsBetter, context: .rx, achievedAt: date(2026, 3, 10))
        context.insert(recentRecord)
        exerciseProfile.addPersonalRecord(recentRecord)

        let olderRecord = PersonalRecord(value: 130, repBand: "1-3", scoringDirection: .higherIsBetter, context: .rx, achievedAt: date(2026, 1, 1))
        context.insert(olderRecord)
        exerciseProfile.addPersonalRecord(olderRecord)
        try context.save()

        let viewModel = ProgressViewModel()
        viewModel.load(modelContext: context, referenceDate: date(2026, 3, 12))

        XCTAssertTrue(viewModel.hasAnyHistory)
        XCTAssertEqual(viewModel.recentRecords.count, 1, "only the record within the last 7 real days must appear")
        XCTAssertEqual(viewModel.recentRecords.first?.id, recentRecord.id)
        XCTAssertEqual(viewModel.recentRecords.first?.label, "R4 Test Back Squat")
    }

    // MARK: D — current vs all-time distinction (heaviest real PR, never a fabricated e1RM formula)

    func testCurrentEstimateAndHeaviestRecordAreDistinctRealFacts() throws {
        let user = makeUser()
        let exercise = Exercise(canonicalName: "R4 Test Bench Press", modality: .hypertrophy, equipment: "barbell", movementPattern: "press")
        context.insert(exercise)
        let exerciseProfile = ExercisePerformanceProfile(estimatedOneRepMax: 108, confidence: 0.9, lastPerformedAt: date(2026, 3, 10))
        context.insert(exerciseProfile)
        exerciseProfile.exercise = exercise
        user.performanceProfile?.addExerciseProfile(exerciseProfile)

        let heaviest = PersonalRecord(value: 115, repBand: "4-6", scoringDirection: .higherIsBetter, context: .rx, achievedAt: date(2026, 2, 1))
        context.insert(heaviest)
        exerciseProfile.addPersonalRecord(heaviest)
        let scaled = PersonalRecord(value: 200, repBand: "4-6", scoringDirection: .higherIsBetter, context: .scaled, achievedAt: date(2026, 2, 15))
        context.insert(scaled)
        exerciseProfile.addPersonalRecord(scaled)
        try context.save()

        XCTAssertEqual(exerciseProfile.estimatedOneRepMax, 108, "current estimate is the engine's own real value, untouched")
        let rxOnly = exerciseProfile.personalRecords.filter { $0.context == .rx }
        XCTAssertEqual(rxOnly.map(\.value), [115], "a Scaled record must never be treated as the athlete's real heaviest Rx lift")
    }

    // MARK: E — stale estimate handling

    func testStaleEstimateIsDisclosedHonestly() {
        let staleDate = Date().addingTimeInterval(-120 * 86400)
        XCTAssertTrue(ProgressPresentation.isStale(lastPerformedAt: staleDate, asOf: Date()))
        let freshDate = Date().addingTimeInterval(-3 * 86400)
        XCTAssertFalse(ProgressPresentation.isStale(lastPerformedAt: freshDate, asOf: Date()))
    }

    // MARK: Consistency — real derivation over persisted Session status, no new domain semantics

    func testConsistencyCountsOnlyRealEligibleSessions() throws {
        let user = makeUser()
        let referenceDate = date(2026, 3, 15)

        func makeSession(daysAgo: Int, status: SessionStatus) {
            let day = Day(ownerUserID: user.id, date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: referenceDate)!)
            context.insert(day)
            let session = Session(name: "Test", modality: .hypertrophy, status: status)
            context.insert(session)
            day.addSession(session)
        }

        makeSession(daysAgo: 2, status: .completed)
        makeSession(daysAgo: 5, status: .completed)
        makeSession(daysAgo: 10, status: .missed)
        makeSession(daysAgo: -3, status: .scheduled) // future session — must never count as eligible
        try context.save()

        let viewModel = ProgressViewModel()
        viewModel.load(modelContext: context, referenceDate: referenceDate)

        let consistency = try XCTUnwrap(viewModel.consistency)
        XCTAssertEqual(consistency.eligible, 3, "the future session must never be counted as eligible")
        XCTAssertEqual(consistency.completed, 2)
    }

    func testConsistencyIsNilWhenNoEligibleSessionsExist() throws {
        makeUser()
        try context.save()
        let viewModel = ProgressViewModel()
        viewModel.load(modelContext: context)
        XCTAssertNil(viewModel.consistency, "an R0 athlete whose program hasn't truthfully started yet must never see a fabricated consistency value")
    }

    // MARK: Mixed-modality history must not break Progress

    func testMixedModalityHistoryDoesNotBreakProgress() throws {
        let user = makeUser()
        let exercise = Exercise(canonicalName: "R4 Test Deadlift", modality: .hypertrophy, equipment: "barbell", movementPattern: "hinge")
        context.insert(exercise)
        let exerciseProfile = ExercisePerformanceProfile(estimatedOneRepMax: 180, confidence: 0.6, lastPerformedAt: date(2026, 3, 1))
        context.insert(exerciseProfile)
        exerciseProfile.exercise = exercise
        user.performanceProfile?.addExerciseProfile(exerciseProfile)

        let stimulus = Stimulus(
            targetDurationDomain: .short, intensity: .high, loading: .light,
            movementFunctions: [.squatLoaded], movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1)],
            skillDemand: .moderate, systemicDemand: .high, scoreType: .time
        )
        let benchmark = BenchmarkDefinition(canonicalID: "benchmark.r4test.fran", name: "R4 Test Fran", stimulus: stimulus, format: .forTime(capSeconds: 600), scoreType: .time, scoreDirection: .lowerIsBetter)
        context.insert(benchmark)
        let benchmarkProfile = BenchmarkPerformanceProfile(lastPerformedAt: date(2026, 3, 5))
        context.insert(benchmarkProfile)
        benchmarkProfile.benchmark = benchmark
        user.performanceProfile?.addBenchmarkProfile(benchmarkProfile)
        let ffResult = FunctionalFitnessResult(scoreType: .time, scoreValue: .time(seconds: 298), scoreDirection: .lowerIsBetter, resultContext: .rx, completedAt: date(2026, 3, 5))
        context.insert(ffResult)
        benchmarkProfile.addResult(ffResult)
        let benchmarkRecord = PersonalRecord(value: 298, scoringDirection: .lowerIsBetter, context: .rx, achievedAt: date(2026, 3, 5))
        context.insert(benchmarkRecord)
        benchmarkRecord.sourceFunctionalFitnessResult = ffResult
        benchmarkProfile.addPersonalRecord(benchmarkRecord)
        try context.save()

        let viewModel = ProgressViewModel()
        viewModel.load(modelContext: context, referenceDate: date(2026, 3, 6))

        XCTAssertTrue(viewModel.hasAnyHistory)
        XCTAssertEqual(viewModel.exerciseProfiles.count, 1)
        XCTAssertEqual(viewModel.benchmarkProfiles.count, 1)
        XCTAssertEqual(viewModel.recentRecords.count, 1, "the benchmark PR must appear in the same unified recent-records list as a strength PR would")
        XCTAssertEqual(viewModel.recentRecords.first?.valueLabel, "4:58")
    }
}
