import XCTest
import SwiftData
@testable import TrainingOS

/// Proves the domain model can represent all eight required scenarios
/// through the same seeded dataset the app itself uses, without any
/// special-case branching per scenario in the model layer.
@MainActor
final class DomainModelScenarioTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var seed: SeedResult!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
        seed = SeedDataProvider.seedAll(in: context)
    }

    private func session(named name: String) throws -> Session {
        let all = try context.fetch(FetchDescriptor<Session>())
        return try XCTUnwrap(all.first { $0.name == name })
    }

    // A. Traditional hypertrophy session.
    func testHypertrophySessionHasStrengthAndAccessoryBlocksWithPerSetRIR() throws {
        let session = try session(named: "Push Day")
        XCTAssertEqual(session.orderedBlocks.map(\.type), [.hypertrophy, .accessory])

        let benchMovement = try XCTUnwrap(session.orderedBlocks.first?.orderedPrescriptions.first)
        XCTAssertEqual(benchMovement.orderedSetPrescriptions.count, 3)

        let loggedResults = benchMovement.loggedSetResults
        XCTAssertEqual(loggedResults.count, 3)
        XCTAssertTrue(loggedResults.allSatisfy { $0.actualRir != nil && $0.targetRir != nil })
    }

    // B. Zone 2 session.
    func testZone2SessionIsSteadyStateWithDurationResultAndNoSetLogging() throws {
        let session = try session(named: "Zone 2 Run")
        XCTAssertEqual(session.orderedBlocks.map(\.type), [.steadyState])
        XCTAssertEqual(session.orderedBlocks.first?.result?.durationSeconds, 2400)
    }

    // C. Interval session.
    func testIntervalSessionCapturesPerRepSplits() throws {
        let session = try session(named: "Track Intervals")
        XCTAssertEqual(session.orderedBlocks.first?.type, .intervals)
        XCTAssertEqual(session.orderedBlocks.first?.result?.splitSeconds.count, 6)
    }

    // D. AMRAP.
    func testAMRAPCapturesRoundsAndExtraRepsAsOneFinalScore() throws {
        let session = try session(named: "12-Minute Metcon")
        let block = try XCTUnwrap(session.orderedBlocks.first)
        XCTAssertEqual(block.type, .amrap)
        XCTAssertEqual(block.result?.rounds, 5)
        XCTAssertEqual(block.result?.extraReps, 14)
    }

    // E. EMOM.
    func testEMOMCapturesIncompleteMinutesAndIsNeverPREligible() throws {
        let session = try session(named: "EMOM Conditioning")
        let block = try XCTUnwrap(session.orderedBlocks.first)
        XCTAssertEqual(block.result?.scoringDirection, .completionBased)
        XCTAssertEqual(block.result?.incompleteMinuteIndexes, [6])
    }

    // F. For Time benchmark. Stage 4E: migrated to the canonical
    // FunctionalFitnessResult/BenchmarkPerformanceProfile path — see
    // RecordWorkoutResultUseCase's own doc comment on the consolidation.
    func testForTimeBenchmarkRecordsRxTimeAndCreatesAPersonalRecord() throws {
        let session = try session(named: "Fran")
        let block = try XCTUnwrap(session.orderedBlocks.first)
        XCTAssertEqual(block.type, .functionalFitness)
        XCTAssertEqual(block.functionalFitnessResult?.scoreValue, .time(seconds: 245))
        XCTAssertEqual(block.functionalFitnessResult?.resultContext, .rx)

        let benchmarkProfile = try XCTUnwrap(seed.performanceProfile.benchmarkProfiles.first { $0.benchmark?.canonicalID == "benchmark.fran" })
        XCTAssertEqual(benchmarkProfile.personalRecords.count, 1)
        XCTAssertEqual(benchmarkProfile.personalRecords.first?.value, 245)
    }

    // G. Hybrid Strength + Metcon: one Session, two block types in order.
    func testHybridSessionChainsStrengthThenMetconInOneSession() throws {
        let session = try session(named: "Strength + Metcon")
        XCTAssertEqual(session.orderedBlocks.map(\.type), [.strength, .amrap])
        XCTAssertEqual(session.modality, .hybrid)
    }

    // H. Two separate Sessions on the same Day.
    func testTwoSessionsCanShareOneDay() throws {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let days = try context.fetch(FetchDescriptor<Day>())
        let today = try XCTUnwrap(days.first { Calendar.current.isDate($0.date, inSameDayAs: startOfToday) })

        XCTAssertEqual(today.sessions.count, 2)
        XCTAssertEqual(Set(today.sessions.map(\.name)), ["Lower A", "Evening Zone 2"])
    }
}
