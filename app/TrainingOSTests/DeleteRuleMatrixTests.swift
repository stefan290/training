import XCTest
import SwiftData
@testable import TrainingOS

/// One test per row (or row group) in DELETE_RULE_MATRIX.md that touches
/// performance data. `PerformanceProfileContinuityTests` covers the
/// narrative case (Program A ends, Program B begins); this file is the
/// exhaustive delete-rule check: every entity that could plausibly cascade
/// into permanent history, deleted directly, with an explicit assertion
/// that history survives.
@MainActor
final class DeleteRuleMatrixTests: XCTestCase {
    private func session(named name: String, in context: ModelContext) throws -> Session {
        let all = try context.fetch(FetchDescriptor<Session>())
        return try XCTUnwrap(all.first { $0.name == name })
    }

    // MARK: - Program deletion

    func testDeletingProgramDefinitionPreservesPerformanceHistory() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext
        let seed = SeedDataProvider.seedAll(in: context)

        let benchProfile = try XCTUnwrap(seed.performanceProfile.profile(for: seed.catalog.benchPress))
        let countBefore = benchProfile.setResults.count
        XCTAssertGreaterThan(countBefore, 0)

        context.delete(seed.programDefinitionA)
        try context.save()

        let profiles = try context.fetch(FetchDescriptor<ExercisePerformanceProfile>())
        let surviving = try XCTUnwrap(profiles.first { $0.id == benchProfile.id })
        XCTAssertEqual(surviving.setResults.count, countBefore, "Deleting a ProgramDefinition must never delete user performance.")
    }

    // MARK: - Program instance deletion

    func testDeletingProgramInstancePreservesPerformanceHistoryAndItsSessions() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext
        let seed = SeedDataProvider.seedAll(in: context)

        let benchProfile = try XCTUnwrap(seed.performanceProfile.profile(for: seed.catalog.benchPress))
        let countBefore = benchProfile.setResults.count

        let pushDaySessionID = try session(named: "Push Day", in: context).id

        context.delete(seed.programInstanceA)
        try context.save()

        let profiles = try context.fetch(FetchDescriptor<ExercisePerformanceProfile>())
        let survivingProfile = try XCTUnwrap(profiles.first { $0.id == benchProfile.id })
        XCTAssertEqual(survivingProfile.setResults.count, countBefore, "Deleting a ProgramInstance must never delete permanent PerformanceProfile history.")

        let sessions = try context.fetch(FetchDescriptor<Session>())
        let survivingSession = try XCTUnwrap(sessions.first { $0.id == pushDaySessionID })
        XCTAssertNil(survivingSession.programInstance, "The nullify relationship should clear the dangling reference, not cascade the delete.")
    }

    // MARK: - Session / WorkoutResult deletion

    func testDeletingSessionCascadesBlocksButPreservesSetResultsAndPersonalRecords() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext
        let seed = SeedDataProvider.seedAll(in: context)

        let benchProfile = try XCTUnwrap(seed.performanceProfile.profile(for: seed.catalog.benchPress))
        let countBefore = benchProfile.setResults.count

        let pushDay = try session(named: "Push Day", in: context)
        let blockIDs = pushDay.blocks.map(\.id)
        XCTAssertFalse(blockIDs.isEmpty)

        // Bench Press history spans both "Push Day" and the unrelated
        // "Full Body A" continuity session (see
        // PerformanceProfileContinuityTests and
        // testCrossProgramBenchPressHistoryRemainsAvailable) — only the
        // SetResults actually logged under Push Day's Bench Press movement
        // should lose their exercisePrescription; the rest (Full Body A's
        // Bench Press sets, and Push Day's own accessory-movement sets,
        // which belong to a different ExercisePerformanceProfile entirely)
        // legitimately keep theirs.
        let benchSetResultIDsBefore = Set(benchProfile.setResults.map(\.id))
        let pushDaySetResultIDs = Set(
            pushDay.blocks
                .flatMap(\.exercisePrescriptions)
                .flatMap(\.loggedSetResults)
                .map(\.id)
        ).intersection(benchSetResultIDsBefore)
        XCTAssertFalse(pushDaySetResultIDs.isEmpty)

        context.delete(pushDay)
        try context.save()

        // The Session and its Blocks are gone (cascade).
        let remainingSessions = try context.fetch(FetchDescriptor<Session>())
        XCTAssertFalse(remainingSessions.contains { $0.name == "Push Day" })
        let remainingBlocks = try context.fetch(FetchDescriptor<WorkoutBlock>())
        XCTAssertTrue(remainingBlocks.allSatisfy { !blockIDs.contains($0.id) })

        // The logged sets are not (nullify from ExercisePrescription and
        // from SetPrescription both point here; ExercisePerformanceProfile
        // is the one place that legitimately owns them).
        let profiles = try context.fetch(FetchDescriptor<ExercisePerformanceProfile>())
        let survivingProfile = try XCTUnwrap(profiles.first { $0.id == benchProfile.id })
        XCTAssertEqual(survivingProfile.setResults.count, countBefore, "Deleting a Session must never delete the SetResults logged during it.")
        let formerlyPushDayResults = survivingProfile.setResults.filter { pushDaySetResultIDs.contains($0.id) }
        XCTAssertEqual(formerlyPushDayResults.count, pushDaySetResultIDs.count)
        XCTAssertTrue(formerlyPushDayResults.allSatisfy { $0.exercisePrescription == nil }, "Surviving results should have lost their session context, not their identity.")
    }

    /// Stage 4E: migrated from the legacy `WorkoutResult`/`ExercisePerformanceProfile`
    /// path (Fran-as-canonical-Exercise) to the sole canonical benchmark
    /// path (`FunctionalFitnessResult`/`BenchmarkPerformanceProfile`) —
    /// see `RecordWorkoutResultUseCase`'s own doc comment on the
    /// consolidation. `WorkoutBlock.functionalFitnessResult` is
    /// `.nullify`, not `.cascade` (unlike the legacy `WorkoutBlock.result`),
    /// so the equivalent proof here deletes the `FunctionalFitnessResult`
    /// directly rather than via block deletion — the same underlying
    /// invariant (a PersonalRecord survives the deletion of the result
    /// that produced it), proven at its new, correct location.
    func testDeletingFunctionalFitnessResultPreservesItsPersonalRecord() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext
        let seed = SeedDataProvider.seedAll(in: context)

        let benchmarkProfile = try XCTUnwrap(seed.performanceProfile.benchmarkProfiles.first { $0.benchmark?.canonicalID == "benchmark.fran" })
        XCTAssertEqual(benchmarkProfile.personalRecords.count, 1)
        let recordID = try XCTUnwrap(benchmarkProfile.personalRecords.first).id
        let recordValue = try XCTUnwrap(benchmarkProfile.personalRecords.first).value

        let franSession = try session(named: "Fran", in: context)
        let franBlock = try XCTUnwrap(franSession.blocks.first)
        let ffResult = try XCTUnwrap(franBlock.functionalFitnessResult)

        context.delete(ffResult)
        try context.save()

        let remainingResults = try context.fetch(FetchDescriptor<FunctionalFitnessResult>())
        XCTAssertFalse(remainingResults.contains { $0.id == ffResult.id })

        let profiles = try context.fetch(FetchDescriptor<BenchmarkPerformanceProfile>())
        let survivingProfile = try XCTUnwrap(profiles.first { $0.id == benchmarkProfile.id })
        let survivingRecord = try XCTUnwrap(survivingProfile.personalRecords.first { $0.id == recordID })
        XCTAssertEqual(survivingRecord.value, recordValue, "A PersonalRecord must survive the deletion of the FunctionalFitnessResult that produced it.")
        XCTAssertNil(survivingRecord.sourceFunctionalFitnessResult, "The traceability pointer should be nullified, not the record itself.")
    }

    // MARK: - Explicit PersonalRecord deletion

    /// Stage 4E: migrated to the canonical benchmark path — see
    /// `testDeletingFunctionalFitnessResultPreservesItsPersonalRecord`'s
    /// own doc comment.
    func testExplicitPersonalRecordDeletionOnlyRemovesThatRecord() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext
        let seed = SeedDataProvider.seedAll(in: context)

        let benchmarkProfile = try XCTUnwrap(seed.performanceProfile.benchmarkProfiles.first { $0.benchmark?.canonicalID == "benchmark.fran" })
        let record = try XCTUnwrap(benchmarkProfile.personalRecords.first)
        let benchmarkProfileID = benchmarkProfile.id

        let benchProfile = try XCTUnwrap(seed.performanceProfile.profile(for: seed.catalog.benchPress))
        let benchResultCountBefore = benchProfile.setResults.count

        context.delete(record)
        try context.save()

        let benchmarkProfiles = try context.fetch(FetchDescriptor<BenchmarkPerformanceProfile>())
        let survivingBenchmarkProfile = try XCTUnwrap(benchmarkProfiles.first { $0.id == benchmarkProfileID })
        XCTAssertTrue(survivingBenchmarkProfile.personalRecords.isEmpty, "Deleting the record should remove it, and only it.")

        let exerciseProfiles = try context.fetch(FetchDescriptor<ExercisePerformanceProfile>())
        let survivingBenchProfile = try XCTUnwrap(exerciseProfiles.first { $0.id == benchProfile.id })
        XCTAssertEqual(survivingBenchProfile.setResults.count, benchResultCountBefore, "Deleting one PersonalRecord must not touch an unrelated ExercisePerformanceProfile.")
    }

    // MARK: - PerformanceProfile as durable owner

    func testPerformanceProfileSurvivesDeletionOfAllPlanAndProgramStructure() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext
        let seed = SeedDataProvider.seedAll(in: context)

        let benchProfile = try XCTUnwrap(seed.performanceProfile.profile(for: seed.catalog.benchPress))
        let countBefore = benchProfile.setResults.count

        // Delete every planning/program artifact the seed created, short of
        // the PerformanceProfile itself.
        context.delete(seed.plan)
        context.delete(seed.programDefinitionA)
        context.delete(seed.programDefinitionB)
        context.delete(seed.programInstanceA)
        context.delete(seed.programInstanceB)
        try context.save()

        let profiles = try context.fetch(FetchDescriptor<ExercisePerformanceProfile>())
        let survivingProfile = try XCTUnwrap(profiles.first { $0.id == benchProfile.id })
        XCTAssertEqual(survivingProfile.setResults.count, countBefore, "PerformanceProfile must remain the durable owner of history regardless of what happens to planning/program structure.")

        let performanceProfiles = try context.fetch(FetchDescriptor<PerformanceProfile>())
        XCTAssertEqual(performanceProfiles.count, 1)
    }

    // MARK: - Cross-program continuity (restated here for the matrix; see
    // also PerformanceProfileContinuityTests for the narrative version)

    func testCrossProgramBenchPressHistoryRemainsAvailable() throws {
        let container = PersistenceController.makeInMemoryContainer()
        let context = container.mainContext
        let seed = SeedDataProvider.seedAll(in: context)

        let benchProfile = try XCTUnwrap(seed.performanceProfile.profile(for: seed.catalog.benchPress))
        let instanceIDs = Set(benchProfile.setResults.compactMap { $0.exercisePrescription?.workoutBlock?.session?.programInstance?.id })

        XCTAssertEqual(instanceIDs, [seed.programInstanceA.id, seed.programInstanceB.id], "Bench Press history should span both program instances without needing either to still be active.")
    }
}
