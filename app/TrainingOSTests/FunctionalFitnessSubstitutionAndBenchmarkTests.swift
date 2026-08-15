import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 4E §48-49: benchmark identity/history/Rx-vs-Scaled, scaling vs.
/// substitution, and confirmation that the Fran consolidation (§22/§55)
/// left exactly one canonical benchmark representation.
@MainActor
final class FunctionalFitnessSubstitutionAndBenchmarkTests: XCTestCase {
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

    // MARK: - §48.18: BenchmarkDefinition canonical identity

    func testBenchmarkDefinitionHasAStableCanonicalIdentity() {
        let benchmark = BenchmarkDefinition(
            canonicalID: "benchmark.fran", name: "Fran", stimulus: franStimulus(),
            format: .forTime(capSeconds: 600), scoreType: .time, scoreDirection: .lowerIsBetter
        )
        context.insert(benchmark)
        XCTAssertEqual(benchmark.canonicalID, "benchmark.fran")
        XCTAssertEqual(benchmark.format, .forTime(capSeconds: 600))
        XCTAssertEqual(benchmark.scoreDirection, .lowerIsBetter)
    }

    // MARK: - §48.19-22: benchmark history, Rx/Scaled independence

    func testBenchmarkHistorySurvivesProgramChangeAndRxScaledRemainIndependent() throws {
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        let benchmark = BenchmarkDefinition(
            canonicalID: "benchmark.fran", name: "Fran", stimulus: franStimulus(),
            format: .forTime(capSeconds: 600), scoreType: .time, scoreDirection: .lowerIsBetter
        )
        context.insert(benchmark)

        let definitionA = ProgramDefinition(name: "FF Block A", lengthWeeks: 2, programmingSystem: .functionalFitness, generatorVersion: 1, provenance: .constructed(reason: "test"))
        context.insert(definitionA)
        let instanceA = ProgramInstance(ownerUserID: UUID())
        context.insert(instanceA)
        instanceA.programDefinition = definitionA
        let sessionA = Session(name: "Fran", modality: .functionalFitness, status: .completed)
        context.insert(sessionA)
        instanceA.addSession(sessionA)
        let blockA = WorkoutBlock(type: .functionalFitness)
        context.insert(blockA)
        sessionA.addBlock(blockA)

        // §48.20: Rx attempt.
        let rxResult = FunctionalFitnessResult(scoreType: .time, scoreValue: .time(seconds: 245), scoreDirection: .lowerIsBetter, resultContext: .rx)
        RecordFunctionalFitnessResultUseCase.recordResult(rxResult, for: blockA, benchmark: benchmark, performanceProfile: performanceProfile, modelContext: context)

        // §48.21: a later Scaled attempt is retained independently, never
        // competing with the Rx record.
        let blockA2 = WorkoutBlock(type: .functionalFitness)
        context.insert(blockA2)
        sessionA.addBlock(blockA2)
        let scaledResult = FunctionalFitnessResult(scoreType: .time, scoreValue: .time(seconds: 200), scoreDirection: .lowerIsBetter, resultContext: .scaled)
        RecordFunctionalFitnessResultUseCase.recordResult(scaledResult, for: blockA2, benchmark: benchmark, performanceProfile: performanceProfile, modelContext: context)

        let benchmarkProfile = try XCTUnwrap(performanceProfile.benchmarkProfile(for: benchmark))
        XCTAssertEqual(benchmarkProfile.results.count, 2, "both the Rx and Scaled attempts are retained")

        // §48.22: Rx vs. Scaled are never treated as equivalent PR
        // contexts — a faster Scaled time must not appear as the Rx PR.
        let rxBest = ScoringEngine.bestRecord(among: benchmarkProfile.personalRecords, context: .rx, repBand: nil)
        let scaledBest = ScoringEngine.bestRecord(among: benchmarkProfile.personalRecords, context: .scaled, repBand: nil)
        XCTAssertEqual(rxBest?.value, 245)
        XCTAssertEqual(scaledBest?.value, 200)
        XCTAssertNotEqual(rxBest?.id, scaledBest?.id)

        // §48.19: history survives the program instance/definition ending.
        context.delete(instanceA)
        context.delete(definitionA)
        try context.save()

        let survivingProfiles = try context.fetch(FetchDescriptor<BenchmarkPerformanceProfile>())
        let survivingProfile = try XCTUnwrap(survivingProfiles.first { $0.id == benchmarkProfile.id })
        XCTAssertEqual(survivingProfile.results.count, 2, "deleting the program that hosted these attempts must never delete benchmark history")
    }

    // MARK: - §48.23: parallel Fran representation eliminated

    func testExactlyOneCanonicalFranRepresentationExistsAfterSeeding() throws {
        let seed = SeedDataProvider.seedAll(in: context)

        // The old path: Fran as a canonical Exercise. Confirmed gone —
        // no Exercise in the seeded catalog is named "Fran."
        let allExercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertFalse(allExercises.contains { $0.canonicalName == "Fran" }, "Fran must not exist as a canonical Exercise — the old, now-eliminated representation")

        // The new, sole path: exactly one BenchmarkDefinition named Fran.
        let benchmarks = try context.fetch(FetchDescriptor<BenchmarkDefinition>())
        let franBenchmarks = benchmarks.filter { $0.canonicalID == "benchmark.fran" }
        XCTAssertEqual(franBenchmarks.count, 1, "exactly one canonical Fran benchmark definition, never two competing identities")

        // Its history lives under BenchmarkPerformanceProfile, not any
        // ExercisePerformanceProfile.
        XCTAssertEqual(seed.performanceProfile.benchmarkProfiles.filter { $0.benchmark?.canonicalID == "benchmark.fran" }.count, 1)
    }

    // MARK: - §49.24-28: scaling — prescription vs. performed

    func testToesToBarPrescribedKneeRaisesPerformedPreservesThePrescriptionAsScaled() {
        let toesToBar = Exercise(canonicalName: "Toes-to-Bar (Sub Test 4E)", modality: .functionalFitness, equipment: "bar", movementPattern: "coreFlexion", movementFunctions: [.gymnasticsPull, .trunk], functionalModality: .gymnastics)
        let kneeRaises = Exercise(canonicalName: "Knee Raises (Sub Test 4E)", modality: .functionalFitness, equipment: "bar", movementPattern: "coreFlexion", movementFunctions: [.gymnasticsPull, .trunk], functionalModality: .gymnastics)
        context.insert(toesToBar)
        context.insert(kneeRaises)

        let prescription = FunctionalFitnessPrescription(stimulus: franStimulus(), format: .amrap(capSeconds: 720))
        context.insert(prescription)
        let movement = FunctionalFitnessMovement(exercise: toesToBar, reps: 12)
        context.insert(movement)
        prescription.addMovement(movement)

        let result = FunctionalFitnessResult(scoreType: .roundsAndReps, scoreValue: .roundsAndReps(rounds: 4, partialReps: 6), scoreDirection: .higherIsBetter, resultContext: .scaled)
        context.insert(result)
        let performed = FunctionalFitnessPerformedMovement(prescribedMovement: movement, performedExercise: kneeRaises, performedReps: 12)
        context.insert(performed)
        result.addPerformedMovement(performed)

        // §49.26: prescription remains Toes-to-Bar.
        XCTAssertEqual(movement.exercise?.canonicalName, "Toes-to-Bar (Sub Test 4E)")
        XCTAssertEqual(performed.prescribedMovement?.exercise?.canonicalName, "Toes-to-Bar (Sub Test 4E)")
        // §49.28: performance history retains the performed movement.
        XCTAssertEqual(performed.performedExercise?.canonicalName, "Knee Raises (Sub Test 4E)")
        // §49.27: result is Scaled.
        XCTAssertEqual(result.resultContext, .scaled)
    }

    // MARK: - §49.29-30: going-forward FF movement substitution never
    // mutates ProgramDefinition, and historical Sessions stay stable —
    // proving the strength substitution machinery generalizes to FF
    // slots via the Stage 4E ExerciseSlot extension.

    func testGoingForwardMovementSlotSubstitutionNeverMutatesProgramDefinitionAndHistoricalSessionStaysStable() throws {
        let barbellThruster = Exercise(canonicalName: "Barbell Thruster (Sub Test 4E)", modality: .functionalFitness, equipment: "barbell", movementPattern: "squatToPress", movementFunctions: [.squatLoaded, .pressLoaded], functionalModality: .weightlifting)
        let dumbbellThruster = Exercise(canonicalName: "Dumbbell Thruster (Sub Test 4E)", modality: .functionalFitness, equipment: "dumbbell", movementPattern: "squatToPress", movementFunctions: [.squatLoaded, .pressLoaded], functionalModality: .weightlifting)
        context.insert(barbellThruster)
        context.insert(dumbbellThruster)

        let amrapStimulus = Stimulus(
            targetDurationDomain: .medium, intensity: .high, loading: .moderate,
            movementFunctions: [.squatLoaded, .pressLoaded],
            movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1), ModalityCount(modality: .gymnastics, count: 1)],
            skillDemand: .moderate, systemicDemand: .high, scoreType: .roundsAndReps
        )
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 2, targetStimulus: amrapStimulus, format: .amrap(capSeconds: 720),
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false
        )
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let slotTemplate = try XCTUnwrap(definition.orderedTemplateSessions.first?.orderedBlockTemplates.first?.functionalFitnessPrescriptionTemplate?.orderedMovementSlots.first { $0.exerciseSlot?.allowedModalities.contains(.weightlifting) == true })
        let exerciseSlot = try XCTUnwrap(slotTemplate.exerciseSlot)

        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition

        let week0 = try FunctionalFitnessMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0),
            ownerUserID: instance.ownerUserID, candidateExercises: [barbellThruster, dumbbellThruster], exposureHistory: [], context: context
        )
        let historicalPrescription = try XCTUnwrap(week0.first?.orderedBlocks.first { $0.type == .functionalFitness }?.functionalFitnessPrescription)
        let historicalMovement = try XCTUnwrap(historicalPrescription.orderedMovements.first { $0.exercise?.id == barbellThruster.id })
        historicalPrescription.workoutBlock?.session?.status = .completed

        try SubstituteExerciseUseCase.substituteGoingForward(instance: instance, slot: exerciseSlot, with: dumbbellThruster, context: context)

        // §49.29: ProgramDefinition/template graph remains unchanged —
        // the slot's own template-level default (nil; concrete-exercise
        // resolution is deliberately deferred to materialization time,
        // see `FunctionalFitnessProgramGenerator`'s own doc comment) is
        // never mutated by an instance-level override.
        XCTAssertNil(exerciseSlot.resolvedExercise)

        // §49.30: the already-materialized historical Session is unaffected.
        XCTAssertEqual(historicalMovement.exercise?.id, barbellThruster.id)

        // The next materialized week picks up the substitution.
        let week1 = try FunctionalFitnessMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 1, startDate: Date(timeIntervalSince1970: 0),
            ownerUserID: instance.ownerUserID, candidateExercises: [barbellThruster, dumbbellThruster], exposureHistory: [], context: context
        )
        let nextPrescription = try XCTUnwrap(week1.first?.orderedBlocks.first { $0.type == .functionalFitness }?.functionalFitnessPrescription)
        XCTAssertTrue(nextPrescription.orderedMovements.contains { $0.exercise?.id == dumbbellThruster.id }, "future materialization must use the GOING FORWARD substitution")
    }
}
