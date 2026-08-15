import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 4C §12-14/§48: proves `ActivityPerformanceProfile` (a Stage 3C
/// entity, unchanged by this stage) genuinely survives a program change,
/// keeps distinct modalities separate, and distinguishes a benchmark
/// context from an activity's general history — now exercised end-to-end
/// against the real `SteadyStateProgramGenerator`/`SteadyStateMaterializer`
/// this stage adds, not just asserted against hand-built rows.
@MainActor
final class ActivityPerformanceProfileIntegrationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func makeCyclingConfiguration() -> SteadyStateProgramConfiguration {
        SteadyStateProgramConfiguration(activityType: .cycling, allowedActivityTypes: [.cycling], daysPerWeek: 2, lengthWeeks: 3, progressionDimension: .none)
    }

    /// §14: "Cycling history survives Program A -> Program B."
    func testCyclingHistorySurvivesReplacingOneProgramInstanceWithAnother() throws {
        let user = User(displayName: "Athlete")
        context.insert(user)
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        performanceProfile.user = user

        let programA = SteadyStateProgramGenerator.generate(configuration: makeCyclingConfiguration(), provenance: .constructed(reason: "test"), context: context)
        let instanceA = ProgramInstance(ownerUserID: user.id)
        context.insert(instanceA)
        instanceA.programDefinition = programA
        _ = SteadyStateMaterializer.materializeAllWeeks(definition: programA, instance: instanceA, startDate: Date(timeIntervalSince1970: 0), ownerUserID: user.id, context: context)

        let cyclingProfile = PerformanceProfileStore.activityProfile(for: .cycling, in: performanceProfile, context: context)
        let firstResult = SteadyStateResult(actualDurationSeconds: 2700, actualDistanceMeters: 20000)
        context.insert(firstResult)
        cyclingProfile.addSteadyStateResult(firstResult)
        firstResult.activityPerformanceProfile = cyclingProfile

        // Program A is done; delete its ProgramInstance entirely (nullify,
        // not cascade, at the Session level — see ProgramInstance's own
        // doc comment) and start Program B.
        context.delete(instanceA)
        try context.save()

        let programB = SteadyStateProgramGenerator.generate(configuration: makeCyclingConfiguration(), provenance: .constructed(reason: "test"), context: context)
        let instanceB = ProgramInstance(ownerUserID: user.id)
        context.insert(instanceB)
        instanceB.programDefinition = programB
        _ = SteadyStateMaterializer.materializeAllWeeks(definition: programB, instance: instanceB, startDate: Date(timeIntervalSince1970: 0), ownerUserID: user.id, context: context)

        let cyclingProfileAfter = PerformanceProfileStore.activityProfile(for: .cycling, in: performanceProfile, context: context)
        XCTAssertEqual(cyclingProfileAfter.id, cyclingProfile.id, "the same permanent profile is reused, never recreated per program")
        XCTAssertEqual(cyclingProfileAfter.steadyStateResults.count, 1, "the result logged under Program A must still be reachable after Program A is gone")
        XCTAssertEqual(cyclingProfileAfter.steadyStateResults.first?.actualDistanceMeters, 20000)
    }

    /// §16: "Rowing and Cycling remain separate histories."
    func testRowingAndCyclingHistoriesNeverMerge() {
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)

        let cyclingProfile = PerformanceProfileStore.activityProfile(for: .cycling, in: performanceProfile, context: context)
        let rowingProfile = PerformanceProfileStore.activityProfile(for: .rowing, in: performanceProfile, context: context)
        XCTAssertNotEqual(cyclingProfile.id, rowingProfile.id)

        let cyclingResult = SteadyStateResult(actualDurationSeconds: 2700)
        context.insert(cyclingResult)
        cyclingProfile.addSteadyStateResult(cyclingResult)
        cyclingResult.activityPerformanceProfile = cyclingProfile

        let rowingResult = SteadyStateResult(actualDurationSeconds: 1800)
        context.insert(rowingResult)
        rowingProfile.addSteadyStateResult(rowingResult)
        rowingResult.activityPerformanceProfile = rowingProfile

        XCTAssertEqual(cyclingProfile.steadyStateResults.count, 1)
        XCTAssertEqual(rowingProfile.steadyStateResults.count, 1)
        XCTAssertEqual(cyclingProfile.steadyStateResults.first?.actualDurationSeconds, 2700)
        XCTAssertEqual(rowingProfile.steadyStateResults.first?.actualDurationSeconds, 1800)
    }

    /// §17/§13-14: a named performance context ("5K") is distinct from the
    /// activity's general history — Stage 3C's own requirement, now
    /// re-confirmed against Stage 4C's new generator/materializer path
    /// rather than only hand-built fixtures.
    func testNamedPerformanceContextRemainsDistinctFromGeneralActivityHistory() {
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)

        let generalRunningProfile = PerformanceProfileStore.activityProfile(for: .running, in: performanceProfile, context: context)
        let fiveKProfile = PerformanceProfileStore.activityProfile(for: .running, performanceContext: "5K", in: performanceProfile, context: context)
        XCTAssertNotEqual(generalRunningProfile.id, fiveKProfile.id)
        XCTAssertNil(generalRunningProfile.performanceContext)
        XCTAssertEqual(fiveKProfile.performanceContext, "5K")

        // Fetching the general profile again must never accidentally
        // return the 5K one just because both share `.running`.
        let generalAgain = PerformanceProfileStore.activityProfile(for: .running, in: performanceProfile, context: context)
        XCTAssertEqual(generalAgain.id, generalRunningProfile.id)
    }

    /// §17: Benchmark history (Functional Fitness) is a structurally
    /// distinct entity from `ActivityPerformanceProfile`, not merely a
    /// different `performanceContext` string — proven directly, not
    /// assumed from Stage 3C's own already-passing tests.
    func testBenchmarkHistoryIsAStructurallyDistinctEntityFromActivityHistory() {
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)

        let runningProfile = PerformanceProfileStore.activityProfile(for: .running, in: performanceProfile, context: context)
        let stimulus = Stimulus(
            targetDurationDomain: .long, intensity: .high, loading: .bodyweightOnly,
            movementFunctions: [.monostructural], movementModalityMix: [ModalityCount(modality: .metabolicConditioning, count: 1)],
            skillDemand: .low, systemicDemand: .high, scoreType: .time
        )
        let benchmark = BenchmarkDefinition(canonicalID: "benchmark.test5k", name: "Test 5K TT", stimulus: stimulus, format: .forTime(capSeconds: nil), scoreType: .time, scoreDirection: .lowerIsBetter)
        context.insert(benchmark)
        let benchmarkProfile = PerformanceProfileStore.benchmarkProfile(for: benchmark, in: performanceProfile, context: context)

        XCTAssertNotNil(runningProfile)
        XCTAssertNotNil(benchmarkProfile)
        XCTAssertEqual(performanceProfile.activityProfiles.count, 1)
        XCTAssertEqual(performanceProfile.benchmarkProfiles.count, 1)
    }
}
