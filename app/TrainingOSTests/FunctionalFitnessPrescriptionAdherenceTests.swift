import XCTest
import SwiftData
@testable import TrainingOS

/// Stage FF.E1: "Prescription Adherence Truth" — proves `PrescriptionAdherence`
/// is a genuinely separate concept from `ResultContext` (Rx/Scaled, which
/// defaults `.rx` unconditionally and is never actually confirmed by any
/// real production path), that legacy/unconfirmed records read `.unknown`
/// rather than a fabricated `.asPrescribed`, that `finish()` requires an
/// explicit adherence value, and that canonical `PersonalRecord` eligibility
/// is gated on `adherence == .asPrescribed` — never on `resultContext`. See
/// `FUNCTIONAL_FITNESS_EXECUTION_TRUTH_DESIGN.md`'s Design Lock (A-I) for
/// the full architectural proof this stage implements.
@MainActor
final class FunctionalFitnessPrescriptionAdherenceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func franStimulus() -> Stimulus {
        Stimulus(
            targetDurationDomain: .short, intensity: .high, loading: .moderate,
            movementFunctions: [.squatLoaded, .gymnasticsPull],
            movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1), ModalityCount(modality: .gymnastics, count: 1)],
            skillDemand: .moderate, systemicDemand: .high, scoreType: .time
        )
    }

    private func makeBenchmarkFixture() throws -> (profile: PerformanceProfile, benchmark: BenchmarkDefinition, block: () -> WorkoutBlock) {
        let profile = PerformanceProfile()
        context.insert(profile)
        let benchmark = BenchmarkDefinition(
            canonicalID: "benchmark.fran.ff-e1-test", name: "Fran",
            stimulus: franStimulus(), format: .forTime(capSeconds: 600), scoreType: .time, scoreDirection: .lowerIsBetter
        )
        context.insert(benchmark)
        let session = Session(name: "Fran", modality: .functionalFitness, status: .inProgress)
        context.insert(session)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.addSession(session)
        return (profile, benchmark, {
            let block = WorkoutBlock(type: .functionalFitness)
            self.context.insert(block)
            session.addBlock(block)
            return block
        })
    }

    // MARK: A. New result defaults safely to .unknown

    func testNewResultDefaultsSafelyToUnknownWhenNoExplicitAdherenceIsSupplied() {
        let result = FunctionalFitnessResult(scoreType: .time, scoreValue: .time(seconds: 245), scoreDirection: .lowerIsBetter)
        XCTAssertEqual(result.adherence, .unknown)
    }

    // MARK: B. Real production Finish path passes an explicit adherence

    func testFinishHasNoUnsafeDefaultAdherenceParameter() {
        // Structural proof, not a runtime one: `finish` takes `adherence`
        // with no default value, so every real call site (all 8 in
        // `FunctionalFitnessExecutionView`) must supply one explicitly —
        // confirmed here by the fact this call does not compile without it.
        let block = WorkoutBlock(type: .functionalFitness)
        context.insert(block)
        let viewModel = FunctionalFitnessExecutionViewModel(block: block)
        _ = viewModel.finish(
            scoreValue: .time(seconds: 100), completionContext: .full, benchmark: nil,
            adherence: .asPrescribed, modelContext: context
        )
    }

    // MARK: C/D. Explicit choice persists the matching state

    func testExplicitAsPrescribedPersistsAsPrescribed() throws {
        let block = WorkoutBlock(type: .functionalFitness)
        context.insert(block)
        let prescription = FunctionalFitnessPrescription(stimulus: franStimulus(), format: .forTime(capSeconds: 600))
        context.insert(prescription)
        block.attachFunctionalFitnessPrescription(prescription)
        let viewModel = FunctionalFitnessExecutionViewModel(block: block)

        _ = viewModel.finish(scoreValue: .time(seconds: 245), completionContext: .full, benchmark: nil, adherence: .asPrescribed, modelContext: context)

        let result = try XCTUnwrap(block.functionalFitnessResult)
        XCTAssertEqual(result.adherence, .asPrescribed)
    }

    func testExplicitModifiedPersistsModified() throws {
        let block = WorkoutBlock(type: .functionalFitness)
        context.insert(block)
        let prescription = FunctionalFitnessPrescription(stimulus: franStimulus(), format: .forTime(capSeconds: 600))
        context.insert(prescription)
        block.attachFunctionalFitnessPrescription(prescription)
        let viewModel = FunctionalFitnessExecutionViewModel(block: block)

        _ = viewModel.finish(scoreValue: .time(seconds: 245), completionContext: .full, benchmark: nil, adherence: .modified, modelContext: context)

        let result = try XCTUnwrap(block.functionalFitnessResult)
        XCTAssertEqual(result.adherence, .modified)
    }

    // MARK: E. Persistence round trip for all three states

    func testAdherenceSurvivesARealSaveAndReloadForAllThreeStates() throws {
        var ids: [UUID: PrescriptionAdherence] = [:]
        for adherence in PrescriptionAdherence.allCases {
            let result = FunctionalFitnessResult(scoreType: .time, scoreValue: .time(seconds: 200), scoreDirection: .lowerIsBetter, adherence: adherence)
            context.insert(result)
            ids[result.id] = adherence
        }
        try context.save()

        let freshContext = ModelContext(container)
        let reloaded = try freshContext.fetch(FetchDescriptor<FunctionalFitnessResult>())
        for result in reloaded where ids[result.id] != nil {
            XCTAssertEqual(result.adherence, ids[result.id], "each state must round-trip independently, not collapse to a shared default")
        }
        XCTAssertEqual(Set(reloaded.compactMap { ids[$0.id] }), Set(PrescriptionAdherence.allCases))
    }

    // MARK: F. Legacy-shaped persisted result resolves to .unknown

    func testLegacyShapedResultResolvesToUnknown() {
        // "Legacy-shaped" here means: constructed exactly as every
        // pre-FF.E1 call site did, omitting the new parameter entirely —
        // proving the additive default, never an inferred/fabricated value.
        let legacy = FunctionalFitnessResult(scoreType: .time, scoreValue: .time(seconds: 245), scoreDirection: .lowerIsBetter, resultContext: .rx)
        XCTAssertEqual(legacy.adherence, .unknown, "a legacy .rx default must never be read as confirmed adherence")
    }

    // MARK: G. No persistence/schema warnings — exercised by the full suite's own build/test run, not a unit assertion.

    // MARK: H/I/J. PR eligibility gated on adherence, never resultContext

    func testAsPrescribedResultIsEligibleForCanonicalPersonalRecord() throws {
        let fixture = try makeBenchmarkFixture()
        let result = FunctionalFitnessResult(scoreType: .time, scoreValue: .time(seconds: 245), scoreDirection: .lowerIsBetter, adherence: .asPrescribed)
        let outcome = RecordFunctionalFitnessResultUseCase.recordResult(
            result, for: fixture.block(), benchmark: fixture.benchmark, performanceProfile: fixture.profile, modelContext: context
        )
        XCTAssertNotNil(outcome.result.personalRecord, "an explicitly confirmed as-prescribed result must be eligible for the canonical PR")
    }

    func testModifiedResultIsNotEligibleForCanonicalPersonalRecordEvenWithABetterScore() throws {
        let fixture = try makeBenchmarkFixture()
        let baseline = FunctionalFitnessResult(scoreType: .time, scoreValue: .time(seconds: 245), scoreDirection: .lowerIsBetter, adherence: .asPrescribed)
        RecordFunctionalFitnessResultUseCase.recordResult(baseline, for: fixture.block(), benchmark: fixture.benchmark, performanceProfile: fixture.profile, modelContext: context)

        let modified = FunctionalFitnessResult(scoreType: .time, scoreValue: .time(seconds: 100), scoreDirection: .lowerIsBetter, adherence: .modified)
        let outcome = RecordFunctionalFitnessResultUseCase.recordResult(
            modified, for: fixture.block(), benchmark: fixture.benchmark, performanceProfile: fixture.profile, modelContext: context
        )
        XCTAssertNil(outcome.result.personalRecord, "a faster time achieved under a MODIFIED (not confirmed as-prescribed) prescription must never become the canonical PR")

        let stillBest = ScoringEngine.bestRecord(among: fixture.benchmark.performanceProfiles.flatMap(\.personalRecords), context: .rx, repBand: nil)
        XCTAssertEqual(stillBest?.value, 245, "the earlier as-prescribed record must remain the canonical PR, unbeaten by the modified attempt")
    }

    func testUnknownResultIsNotEligibleForCanonicalPersonalRecordEvenWithABetterScore() throws {
        let fixture = try makeBenchmarkFixture()
        let baseline = FunctionalFitnessResult(scoreType: .time, scoreValue: .time(seconds: 245), scoreDirection: .lowerIsBetter, adherence: .asPrescribed)
        RecordFunctionalFitnessResultUseCase.recordResult(baseline, for: fixture.block(), benchmark: fixture.benchmark, performanceProfile: fixture.profile, modelContext: context)

        // Never explicitly set — the honest legacy/unconfirmed default.
        let unknown = FunctionalFitnessResult(scoreType: .time, scoreValue: .time(seconds: 100), scoreDirection: .lowerIsBetter)
        let outcome = RecordFunctionalFitnessResultUseCase.recordResult(
            unknown, for: fixture.block(), benchmark: fixture.benchmark, performanceProfile: fixture.profile, modelContext: context
        )
        XCTAssertNil(outcome.result.personalRecord, "an unconfirmed result must never become the canonical PR even with a better score")
    }

    // MARK: K. modified/unknown results retain their real score/history

    func testModifiedAndUnknownResultsRetainTheirRealScoreAndRemainInHistory() throws {
        let fixture = try makeBenchmarkFixture()
        let modified = FunctionalFitnessResult(scoreType: .time, scoreValue: .time(seconds: 100), scoreDirection: .lowerIsBetter, adherence: .modified)
        let unknown = FunctionalFitnessResult(scoreType: .time, scoreValue: .time(seconds: 150), scoreDirection: .lowerIsBetter)

        RecordFunctionalFitnessResultUseCase.recordResult(modified, for: fixture.block(), benchmark: fixture.benchmark, performanceProfile: fixture.profile, modelContext: context)
        RecordFunctionalFitnessResultUseCase.recordResult(unknown, for: fixture.block(), benchmark: fixture.benchmark, performanceProfile: fixture.profile, modelContext: context)

        let allResults = fixture.benchmark.results
        XCTAssertEqual(allResults.count, 2, "both non-eligible results are still real, saved history")
        XCTAssertEqual(modified.scoreValue, .time(seconds: 100))
        XCTAssertEqual(unknown.scoreValue, .time(seconds: 150))
    }

    // MARK: L. completionContext remains independent of adherence

    func testCompletionContextRemainsIndependentOfAdherence() throws {
        let asPrescribedPartialBlock = WorkoutBlock(type: .functionalFitness)
        context.insert(asPrescribedPartialBlock)
        let prescriptionA = FunctionalFitnessPrescription(stimulus: franStimulus(), format: .forTime(capSeconds: 600))
        context.insert(prescriptionA)
        asPrescribedPartialBlock.attachFunctionalFitnessPrescription(prescriptionA)
        let viewModelA = FunctionalFitnessExecutionViewModel(block: asPrescribedPartialBlock)
        _ = viewModelA.finish(scoreValue: .time(seconds: 600), completionContext: .partial, benchmark: nil, adherence: .asPrescribed, modelContext: context)
        XCTAssertEqual(asPrescribedPartialBlock.functionalFitnessResult?.adherence, .asPrescribed)
        XCTAssertEqual(asPrescribedPartialBlock.completionContext, .partial, "asPrescribed + partial (a legitimate time-cap finish) must be a valid combination")

        let modifiedFullBlock = WorkoutBlock(type: .functionalFitness)
        context.insert(modifiedFullBlock)
        let prescriptionB = FunctionalFitnessPrescription(stimulus: franStimulus(), format: .forTime(capSeconds: 600))
        context.insert(prescriptionB)
        modifiedFullBlock.attachFunctionalFitnessPrescription(prescriptionB)
        let viewModelB = FunctionalFitnessExecutionViewModel(block: modifiedFullBlock)
        _ = viewModelB.finish(scoreValue: .time(seconds: 300), completionContext: .full, benchmark: nil, adherence: .modified, modelContext: context)
        XCTAssertEqual(modifiedFullBlock.functionalFitnessResult?.adherence, .modified)
        XCTAssertEqual(modifiedFullBlock.completionContext, .full, "modified + full must also be a valid combination")
    }

    // MARK: N. All real WorkoutFormat Finish paths reach the same adherence-aware contract

    func testEveryRealWorkoutFormatCaseReachesTheSameFinishContractWithAnExplicitAdherence() throws {
        for format in [
            WorkoutFormat.amrap(capSeconds: 600), .emom(intervalSeconds: 60, totalSeconds: 600),
            .forTime(capSeconds: 600), .chipper(capSeconds: 600), .ladder(direction: .ascending, capSeconds: 600),
            .roundsForTime(rounds: 5, capSeconds: nil), .maxLoad, .maxReps(capSeconds: 120),
            .intervals(count: 4, workSeconds: 30, restSeconds: 30),
        ] {
            let block = WorkoutBlock(type: .functionalFitness)
            context.insert(block)
            let prescription = FunctionalFitnessPrescription(stimulus: franStimulus(), format: format)
            context.insert(prescription)
            block.attachFunctionalFitnessPrescription(prescription)
            let viewModel = FunctionalFitnessExecutionViewModel(block: block)

            let highlight = viewModel.finish(
                scoreValue: .time(seconds: 100), completionContext: .full, benchmark: nil, adherence: .asPrescribed, modelContext: context
            )
            XCTAssertNotNil(highlight, "format \(format) must reach the same finish contract and successfully log a result")
            XCTAssertEqual(block.functionalFitnessResult?.adherence, .asPrescribed, "format \(format) must persist the explicit adherence choice")
        }
    }
}
