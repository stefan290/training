import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 3C §29: proves the permanence invariant (CLAUDE.md rule 1) holds
/// for the new profile types exactly as it already holds for
/// `ExercisePerformanceProfile` — deleting program structure must never
/// delete permanent user performance, regardless of modality.
@MainActor
final class ModalityContinuityTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var performanceProfile: PerformanceProfile!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
        performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
    }

    private func makeRunningInstance(named name: String) -> (definition: ProgramDefinition, instance: ProgramInstance) {
        let definition = ProgramDefinition(name: name, lengthWeeks: 4)
        context.insert(definition)
        let instance = ProgramInstance(ownerUserID: UUID())
        instance.programDefinition = definition
        context.insert(instance)
        return (definition, instance)
    }

    private func logIntervalResult(for instance: ProgramInstance, sessionDuration: Int) -> IntervalResult {
        let session = Session(name: "Track Session", modality: .conditioning, role: .interval)
        context.insert(session)
        instance.addSession(session)

        let block = WorkoutBlock(type: .intervals)
        context.insert(block)
        session.addBlock(block)

        let activityProfile = PerformanceProfileStore.activityProfile(
            for: .running, in: performanceProfile, context: context
        )
        let result = IntervalResult(sessionDurationSeconds: sessionDuration)
        context.insert(result)
        block.attachIntervalResult(result)
        activityProfile.addIntervalResult(result)
        activityProfile.lastPerformedAt = Date()
        return result
    }

    // MARK: 1. Running performance survives Running Program A -> Program B.

    func testRunningPerformanceSurvivesProgramAToProgramB() throws {
        let (definitionA, instanceA) = makeRunningInstance(named: "Running Program A")
        _ = logIntervalResult(for: instanceA, sessionDuration: 1680)

        let activityProfileID = try XCTUnwrap(
            performanceProfile.activityProfile(for: .running)?.id
        )
        let countBefore = try XCTUnwrap(performanceProfile.activityProfile(for: .running)?.intervalResults.count)
        XCTAssertEqual(countBefore, 1)

        // Program A ends.
        context.delete(definitionA)
        context.delete(instanceA)
        try context.save()

        let survivingProfiles = try context.fetch(FetchDescriptor<ActivityPerformanceProfile>())
        let survivingProfile = try XCTUnwrap(survivingProfiles.first { $0.id == activityProfileID })
        XCTAssertEqual(survivingProfile.intervalResults.count, 1, "Deleting Running Program A must never delete logged interval history.")

        // Program B begins; logging again must land in the SAME activity profile.
        let (_, instanceB) = makeRunningInstance(named: "Running Program B")
        _ = logIntervalResult(for: instanceB, sessionDuration: 1700)
        try context.save()

        XCTAssertEqual(survivingProfile.intervalResults.count, 2, "A second program's logged run must accumulate in the same permanent ActivityPerformanceProfile, not a new one.")
    }

    // MARK: 2. Benchmark history survives program changes.

    func testBenchmarkHistorySurvivesProgramChange() throws {
        let benchmark = BenchmarkDefinition(
            canonicalID: "benchmark.fran",
            name: "Fran",
            stimulus: Stimulus(
                targetDurationDomain: .short, intensity: .high, loading: .moderate,
                movementFunctions: [.hingeLoaded, .gymnasticsPull],
                movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1), ModalityCount(modality: .gymnastics, count: 1)],
                skillDemand: .moderate, systemicDemand: .high, scoreType: .time
            ),
            format: .forTime(capSeconds: nil),
            scoreType: .time,
            scoreDirection: .lowerIsBetter
        )
        context.insert(benchmark)

        let definition = ProgramDefinition(name: "Functional Fitness Block", lengthWeeks: 4)
        context.insert(definition)
        let instance = ProgramInstance(ownerUserID: UUID())
        instance.programDefinition = definition
        context.insert(instance)

        let session = Session(name: "Fran", modality: .functionalFitness)
        context.insert(session)
        instance.addSession(session)
        let block = WorkoutBlock(type: .functionalFitness)
        context.insert(block)
        session.addBlock(block)

        let benchmarkProfile = PerformanceProfileStore.benchmarkProfile(
            for: benchmark, in: performanceProfile, context: context
        )
        let result = FunctionalFitnessResult(
            scoreType: .time, scoreValue: .time(seconds: 245), scoreDirection: .lowerIsBetter
        )
        context.insert(result)
        block.attachFunctionalFitnessResult(result)
        result.benchmark = benchmark
        benchmarkProfile.addResult(result)

        let benchmarkProfileID = benchmarkProfile.id
        try context.save()

        // The program that hosted this attempt ends.
        context.delete(instance)
        context.delete(definition)
        try context.save()

        let survivingProfiles = try context.fetch(FetchDescriptor<BenchmarkPerformanceProfile>())
        let survivingProfile = try XCTUnwrap(survivingProfiles.first { $0.id == benchmarkProfileID })
        XCTAssertEqual(survivingProfile.results.count, 1, "Deleting the program that hosted a Fran attempt must never delete the benchmark history.")
        XCTAssertEqual(survivingProfile.results.first?.scoreValue, .time(seconds: 245))
        XCTAssertEqual(survivingProfile.benchmark?.canonicalID, "benchmark.fran")
    }

    // MARK: 3. Exercise continuity still holds alongside the new profile types.

    func testExerciseContinuityStillHoldsAlongsideNewProfileTypes() throws {
        // Re-confirms CLAUDE.md rule 1 for the pre-existing strength path,
        // in the same test file that now also exercises the new
        // Activity/Benchmark paths — not a new mechanism, a same-suite
        // sanity check that Stage 3C's additions didn't disturb it.
        let benchPress = Exercise(canonicalName: "Barbell Bench Press", modality: .hypertrophy, equipment: "barbell", movementPattern: "horizontalPush")
        context.insert(benchPress)

        let definitionA = ProgramDefinition(name: "Program A", lengthWeeks: 4)
        context.insert(definitionA)
        let instanceA = ProgramInstance(ownerUserID: UUID())
        instanceA.programDefinition = definitionA
        context.insert(instanceA)

        let session = Session(name: "Full Body A", modality: .strength)
        context.insert(session)
        instanceA.addSession(session)
        let block = WorkoutBlock(type: .strength)
        context.insert(block)
        session.addBlock(block)
        let movement = ExercisePrescription(exercise: benchPress)
        context.insert(movement)
        block.addPrescription(movement)

        RecordSetResultUseCase.recordSet(
            setIndex: 0, weight: 60, reps: 10, targetRir: 2, actualRir: 2, prBand: "8-12",
            scoringDirection: .higherIsBetter, context: .rx, setPrescription: nil,
            exercisePrescription: movement, exercise: benchPress, performanceProfile: performanceProfile,
            completedAt: Date(), modelContext: context
        )

        let exerciseProfileID = try XCTUnwrap(performanceProfile.profile(for: benchPress)?.id)
        try context.save()

        context.delete(definitionA)
        context.delete(instanceA)
        try context.save()

        let survivingProfiles = try context.fetch(FetchDescriptor<ExercisePerformanceProfile>())
        let survivingProfile = try XCTUnwrap(survivingProfiles.first { $0.id == exerciseProfileID })
        XCTAssertEqual(survivingProfile.setResults.count, 1)
    }
}
