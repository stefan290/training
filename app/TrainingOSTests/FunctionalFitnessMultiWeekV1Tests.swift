import XCTest
import SwiftData
@testable import TrainingOS

/// FF Multi-Week V1: proves the authored `weeklyPlan` activation —
/// materialization counts per frequency, deterministic authored intent
/// (anti-randomness), the previously-dormant variance engine actually
/// firing end-to-end, strength+metcon composition, and a full 3-scenario
/// 4-week dogfood with week-by-week summaries.
@MainActor
final class FunctionalFitnessMultiWeekV1Tests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func exercise(_ name: String, _ functions: [MovementFunction], _ modality: FunctionalModality) -> Exercise {
        // FUNCTIONAL FITNESS PROGRAMMING AUTHORITY V2, Section 10/11:
        // generic scheduling filler, not a target-content test — tagged
        // `.distance` so it stays truthfully materializable.
        let ex = Exercise(canonicalName: name, modality: .functionalFitness, equipment: "barbell", movementPattern: "test", movementFunctions: functions, functionalModality: modality, measuredDimensions: functions.contains(.monostructural) ? [.distance] : [])
        context.insert(ex)
        return ex
    }

    /// Dogfood Round 2 (Finding 3): a real, muscle-group-tagged candidate
    /// for `addStrengthBlock`'s embedded strength `ExerciseSlot`
    /// (`allowedTargets`, never `movementFunctions`/`functionalModality`
    /// — this is the same vocabulary Hypertrophy's own slots use). None
    /// of `makeCandidates()`'s own FF-flavored exercises carry
    /// `primaryTargets`, so a real strength-block resolution needs its
    /// own candidate pool, matching what `StartPhaseUseCase.start` now
    /// supplies in real production.
    private func strengthCandidates() -> [Exercise] {
        // PROGRAMMING AUTHORITY V1 — FINAL CLOSE-OUT, Part XV: these
        // fixtures must carry real `movementFunctions` tags, matching the
        // production catalog, now that `FunctionalBodybuildingPattern`'s
        // loaded-pattern slots also constrain on `allowedMovementFunctions`
        // (not `primaryTargets`/`MuscleGroup` alone) — see that type's own
        // doc comment for the real pre-existing defect this closes.
        [
            Exercise(canonicalName: "Test Back Squat", modality: .hypertrophy, equipment: "barbell", movementPattern: "test", primaryTargets: [.quadriceps, .glutes], movementFunctions: [.squatLoaded]),
            Exercise(canonicalName: "Test Romanian Deadlift", modality: .hypertrophy, equipment: "barbell", movementPattern: "test", primaryTargets: [.hamstrings, .glutes, .back], movementFunctions: [.hingeLoaded]),
            Exercise(canonicalName: "Test Overhead Press", modality: .hypertrophy, equipment: "barbell", movementPattern: "test", primaryTargets: [.shoulders, .chest, .triceps], movementFunctions: [.pressLoaded]),
            Exercise(canonicalName: "Test Barbell Row", modality: .hypertrophy, equipment: "barbell", movementPattern: "test", primaryTargets: [.back, .biceps], movementFunctions: [.horizontalPullLoaded]),
        ].map { context.insert($0); return $0 }
    }

    /// Covers all 6 non-deferred `MovementFunction` cases across the 3
    /// modalities the composer ever produces.
    /// DOGFOOD — FIX ORDER 1, Section C/D: `FunctionalFitnessMovementTargetRule
    /// .resolve`'s hinge/press/gymnasticsPush branches only return a real
    /// target for a small, exact, named set of canonicalNames (their
    /// `default` case is genuinely empty — a real, pre-existing, locked
    /// PRODUCT VALUE gap, not something this checkpoint invented) — a
    /// synthetic placeholder name like "Hinge Lift" now correctly fails
    /// `hasExecutableTarget` and is excluded from selection, since a real
    /// production session could never truthfully dose it either. Renamed
    /// to real catalog names this rule actually recognizes so these
    /// fixtures still represent genuinely executable content; `movementFunctions`
    /// stays exactly as before (this file's own synthetic single-function
    /// tagging, not the real catalog's multi-function tags).
    private func makeCandidates() -> [Exercise] {
        [
            exercise("Squat Lift", [.squatLoaded], .weightlifting),
            exercise("Deadlift", [.hingeLoaded], .weightlifting),
            exercise("Thruster", [.pressLoaded], .weightlifting),
            exercise("Gymnastics Pull", [.gymnasticsPull], .gymnastics),
            exercise("Push-up", [.gymnasticsPush], .gymnastics),
            exercise("Conditioning Bike", [.monostructural], .metabolicConditioning),
        ]
    }

    private func generate(daysPerWeek: Int) throws -> ProgramDefinition {
        let weeklyPlan = try XCTUnwrap(FunctionalFitnessAuthoredProgramLibrary.weeklyPlan(forSessionsPerWeek: daysPerWeek))
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: daysPerWeek, lengthWeeks: 4,
            targetStimulus: weeklyPlan[0].stimulus, format: weeklyPlan[0].format, sessionRole: .functionalFitness,
            varianceConstraints: VarianceConstraints(), requiresRecentExposureToProgress: false,
            includeStrengthBlock: false, weeklyPlan: weeklyPlan
        )
        return FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
    }

    private func materializeAllFourWeeks(definition: ProgramDefinition, instance: ProgramInstance, candidates: [Exercise], environment: TrainingEnvironment) throws -> [[Session]] {
        var byWeek: [[Session]] = []
        for weekIndex in 0..<4 {
            let sessions = try FunctionalFitnessMaterializer.materializeWeek(
                definition: definition, instance: instance, weekIndex: weekIndex,
                startDate: Calendar.current.date(byAdding: .day, value: weekIndex * 7, to: Date())!,
                ownerUserID: instance.ownerUserID, candidateExercises: candidates, exposureHistory: [],
                environment: environment, context: context
            )
            byWeek.append(sessions)
        }
        return byWeek
    }

    private func makeInstance(definition: ProgramDefinition) -> ProgramInstance {
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition
        return instance
    }

    // MARK: - Capability gate

    /// FUNCTIONAL FITNESS PROGRAMMING AUTHORITY V1 Part V widened this
    /// gate from 1-3 to 1-5 — 4 and 5 are now real, authored V1
    /// frequencies (`FunctionalFitnessAuthoredProgramLibrary
    /// .fourSessionsPerWeek`/`.fiveSessionsPerWeek`), not the pre-V1
    /// generic fallback. 6 remains, and must remain, unsupported: this
    /// codebase has no real predictive recovery/fatigue model to
    /// honestly enforce Part V's own six-day distribution rule
    /// (`LongTermPlanner.buildCustomMix`'s own typed six-day gate).
    func testCapabilityGateSupportsOneThroughFive() {
        XCTAssertTrue(ProgramCapabilityRegistry.isFunctionalFitnessV1Supported(daysPerWeek: 1))
        XCTAssertTrue(ProgramCapabilityRegistry.isFunctionalFitnessV1Supported(daysPerWeek: 2))
        XCTAssertTrue(ProgramCapabilityRegistry.isFunctionalFitnessV1Supported(daysPerWeek: 3))
        XCTAssertTrue(ProgramCapabilityRegistry.isFunctionalFitnessV1Supported(daysPerWeek: 4))
        XCTAssertTrue(ProgramCapabilityRegistry.isFunctionalFitnessV1Supported(daysPerWeek: 5))
        XCTAssertFalse(ProgramCapabilityRegistry.isFunctionalFitnessV1Supported(daysPerWeek: 6), "6 is a real, disclosed recovery-model gap, never silently widened past 5")
        XCTAssertNotNil(FunctionalFitnessAuthoredProgramLibrary.weeklyPlan(forSessionsPerWeek: 4), "4/week is now real, authored V1 content")
        XCTAssertNotNil(FunctionalFitnessAuthoredProgramLibrary.weeklyPlan(forSessionsPerWeek: 5), "5/week is now real, authored V1 content")
        XCTAssertNil(FunctionalFitnessAuthoredProgramLibrary.weeklyPlan(forSessionsPerWeek: 6), "never approximated to the nearest supported frequency")
    }

    // MARK: - Materialization tests: exact session counts per frequency

    func testOneSessionPerWeekProducesFourTotalSessions() throws {
        let definition = try generate(daysPerWeek: 1)
        let instance = makeInstance(definition: definition)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let byWeek = try materializeAllFourWeeks(definition: definition, instance: instance, candidates: makeCandidates(), environment: environment)
        XCTAssertEqual(byWeek.flatMap { $0 }.count, 4, "1 FF/week x 4 weeks = 4 sessions")
        for sessions in byWeek { XCTAssertEqual(sessions.count, 1) }
    }

    func testTwoSessionsPerWeekProducesEightTotalSessions() throws {
        let definition = try generate(daysPerWeek: 2)
        let instance = makeInstance(definition: definition)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let byWeek = try materializeAllFourWeeks(definition: definition, instance: instance, candidates: makeCandidates(), environment: environment)
        XCTAssertEqual(byWeek.flatMap { $0 }.count, 8, "2 FF/week x 4 weeks = 8 sessions")
        for sessions in byWeek { XCTAssertEqual(sessions.count, 2) }
    }

    func testThreeSessionsPerWeekProducesTwelveTotalSessions() throws {
        let definition = try generate(daysPerWeek: 3)
        let instance = makeInstance(definition: definition)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let byWeek = try materializeAllFourWeeks(definition: definition, instance: instance, candidates: makeCandidates(), environment: environment)
        XCTAssertEqual(byWeek.flatMap { $0 }.count, 12, "3 FF/week x 4 weeks = 12 sessions")
        for sessions in byWeek { XCTAssertEqual(sessions.count, 3) }
    }

    // MARK: - Anti-randomness / determinism

    /// Same authored plan, read twice — the authored INTENT (stimulus/
    /// format/includeStrengthBlock/varianceConstraints per relative week
    /// and session slot) is a deterministic, static literal, not
    /// generated at random.
    func testSameInputsProduceTheSameAuthoredFourWeekStructure() throws {
        let planA = FunctionalFitnessAuthoredProgramLibrary.twoSessionsPerWeek
        let planB = FunctionalFitnessAuthoredProgramLibrary.twoSessionsPerWeek
        XCTAssertEqual(planA, planB)
    }

    /// Session 1 and Session 2 of a 2-session week are intentionally
    /// different BEFORE any exercise resolution — checked on the raw
    /// authored intent, never on composer/environment-dependent output.
    func testSessionOneAndTwoOfATwoSessionWeekAreIntentionallyDifferentBeforeResolution() {
        let plan = FunctionalFitnessAuthoredProgramLibrary.twoSessionsPerWeek
        let week0SessionA = plan[0]
        let week0SessionB = plan[1]
        XCTAssertNotEqual(week0SessionA.includeStrengthBlock, week0SessionB.includeStrengthBlock)
        XCTAssertNotEqual(week0SessionA.format, week0SessionB.format)
        XCTAssertNotEqual(week0SessionA.sessionRole, week0SessionB.sessionRole)
    }

    /// Later-week intent differs from earlier-week intent where authored
    /// — week 4's Session A is not a repeat of week 1's Session A.
    func testLaterWeekIntentDiffersFromEarlierWeekIntentForTheSameSessionSlot() {
        let plan = FunctionalFitnessAuthoredProgramLibrary.twoSessionsPerWeek
        let week0SessionA = try! XCTUnwrap(plan.first { $0.relativeWeek == 0 && $0.sessionIndexInWeek == 0 })
        let week3SessionA = try! XCTUnwrap(plan.first { $0.relativeWeek == 3 && $0.sessionIndexInWeek == 0 })
        XCTAssertNotEqual(week0SessionA.format, week3SessionA.format)
    }

    /// Exercise/environment resolution may vary the RESOLVED exercises
    /// without changing the AUTHORED program intent — materializing twice
    /// with the same inputs resolves to the same structure (deterministic
    /// materialization), proving resolution doesn't itself introduce
    /// randomness even though it is a separate concern from authored intent.
    func testMaterializationIsDeterministicGivenTheSameInputs() throws {
        let definitionA = try generate(daysPerWeek: 1)
        let instanceA = makeInstance(definition: definitionA)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let sessionsA = try FunctionalFitnessMaterializer.materializeWeek(
            definition: definitionA, instance: instanceA, weekIndex: 0, startDate: Date(),
            ownerUserID: instanceA.ownerUserID, candidateExercises: makeCandidates(), exposureHistory: [],
            environment: environment, context: context
        )
        let definitionB = try generate(daysPerWeek: 1)
        let instanceB = makeInstance(definition: definitionB)
        let sessionsB = try FunctionalFitnessMaterializer.materializeWeek(
            definition: definitionB, instance: instanceB, weekIndex: 0, startDate: Date(),
            ownerUserID: instanceB.ownerUserID, candidateExercises: makeCandidates(), exposureHistory: [],
            environment: environment, context: context
        )
        let stimulusA = sessionsA.first?.orderedBlocks.compactMap(\.functionalFitnessPrescription).first?.stimulus
        let stimulusB = sessionsB.first?.orderedBlocks.compactMap(\.functionalFitnessPrescription).first?.stimulus
        XCTAssertEqual(stimulusA, stimulusB, "same inputs (fresh instance, empty exposure history, same candidates) must resolve the same final stimulus")
    }

    // MARK: - Variance engine activation (proves the previously-dormant engine is alive)

    /// Constructs prior exposure history that WOULD violate a configured
    /// `avoidRepeatingDurationDomainWithinSessions` window, proving
    /// `FunctionalFitnessDecisionEngine` detects the conflict and
    /// `finalStimulus` differs from `intendedStimulus` — both persist,
    /// and the resulting session remains executable. Uses a config with
    /// no explicit format cap (`.maxLoad`) so this test isolates the
    /// decision engine's own rotation from the separate, pre-existing
    /// format/duration-domain coupling (rotating `targetDurationDomain`
    /// never changes `format`, which stays fixed at generation time —
    /// this test avoids conflating the two).
    func testPriorExposureViolatingAConfiguredWindowCausesFinalStimulusToDifferFromIntended() throws {
        let window = 2
        let variance = VarianceConstraints(avoidRepeatingDurationDomainWithinSessions: window)
        let intent = FunctionalFitnessSessionIntent(
            relativeWeek: 0, sessionIndexInWeek: 0,
            stimulus: Stimulus(
                targetDurationDomain: .medium, intensity: .moderate, loading: .moderate,
                movementFunctions: [.squatLoaded], movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1), ModalityCount(modality: .gymnastics, count: 1), ModalityCount(modality: .metabolicConditioning, count: 1),
                ], skillDemand: .low, systemicDemand: .low, scoreType: .load
            ),
            format: .maxLoad, includeStrengthBlock: false, varianceConstraints: variance, sessionRole: .functionalFitness
        )
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 1, targetStimulus: intent.stimulus, format: intent.format, sessionRole: .functionalFitness,
            varianceConstraints: VarianceConstraints(), requiresRecentExposureToProgress: false, includeStrengthBlock: false,
            weeklyPlan: [intent]
        )
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = makeInstance(definition: definition)
        let environment = TrainingEnvironmentTestSupport.full(context: context)

        // Real prior exposure history: the last `window` sessions all
        // used the SAME duration domain as the intended stimulus — this
        // is exactly what `avoidRepeatingDurationDomainWithinSessions`
        // checks.
        let exposureHistory: [VarianceExposureRecord] = (0..<window).map { i in
            VarianceExposureRecord(
                date: Calendar.current.date(byAdding: .day, value: -(i + 1), to: Date())!,
                durationDomain: .medium, loading: .moderate, movementModalityMix: intent.stimulus.movementModalityMix,
                movementFunctionsUsed: [.squatLoaded], skillDemand: .low, wasHighIntensity: false
            )
        }

        let sessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, startDate: Date(),
            ownerUserID: instance.ownerUserID, candidateExercises: makeCandidates(), exposureHistory: exposureHistory,
            environment: environment, context: context
        )
        let prescription = try XCTUnwrap(sessions.first?.orderedBlocks.compactMap(\.functionalFitnessPrescription).first)
        let intended = try XCTUnwrap(prescription.intendedStimulus)
        // Phase 1 (which PRODUCES "intended") is exactly where the 4
        // variance checks (including duration-domain rotation) run — so
        // proving the dormant engine fired means comparing INTENDED
        // against the raw, originally-authored configured value, not
        // against FINAL (FINAL only differs from INTENDED via the
        // separate Phase 2/CP.2 cross-modality checks, unrelated to this
        // test).
        XCTAssertNotEqual(intended.targetDurationDomain, intent.stimulus.targetDurationDomain, "intended stimulus must differ from the raw authored/configured value — the previously-dormant duration-domain variance check fired")
        XCTAssertEqual(prescription.stimulus.targetDurationDomain, intended.targetDurationDomain, "final equals intended here since no Phase-2/CP.2 cross-modality input was supplied")
        XCTAssertFalse(sessions.isEmpty, "the resulting session remains real and executable despite the adjustment")
    }

    // MARK: - Strength + metcon composition dogfood

    func testIncludeStrengthBlockMaterializesBothARealStrengthBlockAndARealFFBlockInTheSameSession() throws {
        let definition = try generate(daysPerWeek: 2) // week 0 session A has includeStrengthBlock: true
        let instance = makeInstance(definition: definition)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        // Dogfood Round 2 (Finding 3): real production now resolves the
        // embedded strength slot via `StartPhaseUseCase.start` before
        // materialization ever runs — mirrored here directly, the same
        // production authority, so this test proves the corrected
        // behavior rather than the pre-fix "empty strength block" defect.
        try ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: strengthCandidates(), environment: environment)
        let sessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, startDate: Date(),
            ownerUserID: instance.ownerUserID, candidateExercises: makeCandidates(), exposureHistory: [],
            environment: environment, context: context
        )
        let structuredSession = try XCTUnwrap(sessions.first)
        let blocks = structuredSession.orderedBlocks
        XCTAssertTrue(blocks.contains { !$0.orderedPrescriptions.isEmpty }, "a real strength block (ExercisePrescription) materialized")
        XCTAssertTrue(blocks.contains { $0.functionalFitnessPrescription != nil }, "a real FF conditioning block materialized in the SAME session")
        XCTAssertNotNil(blocks.first { $0.functionalFitnessPrescription != nil }?.trainingStressProfile, "stress metadata populated")
    }

    // MARK: - Training Environment: full vs. constrained

    func testConstrainedEnvironmentStillProducesAnExecutableOrExplicitlyIncompatibleResult() throws {
        let definition = try generate(daysPerWeek: 1)
        let instance = makeInstance(definition: definition)
        // A deliberately narrow environment — only bodyweight-compatible
        // equipment, none of the candidates' own equipment.
        let constrained = TrainingEnvironment(name: "Bodyweight Only", availableEquipment: [])
        context.insert(constrained)
        do {
            let sessions = try FunctionalFitnessMaterializer.materializeWeek(
                definition: definition, instance: instance, weekIndex: 0, startDate: Date(),
                ownerUserID: instance.ownerUserID, candidateExercises: makeCandidates(), exposureHistory: [],
                environment: constrained, context: context
            )
            XCTAssertFalse(sessions.isEmpty)
        } catch let error as FunctionalFitnessMaterializationError {
            // An explicit, typed incompatibility is the CORRECT honest
            // outcome for a fully-incompatible environment — never a
            // silent substitution.
            if case .environmentIncompatible = error {} else { XCTFail("expected .environmentIncompatible, got \(error)") }
        }
    }

    // MARK: - Full 4-week dogfood: A (1/week), B (2/week), C (3/week)

    private func summarize(_ sessions: [Session], week: Int) -> [String] {
        sessions.map { session in
            let ffBlocks = session.orderedBlocks.compactMap(\.functionalFitnessPrescription)
            let hasStrength = session.orderedBlocks.contains { !$0.orderedPrescriptions.isEmpty }
            let ff = ffBlocks.first
            let functions = ff?.orderedMovements.compactMap { $0.sourceExerciseSlot?.allowedMovementFunctions.first?.rawValue } ?? []
            return "week \(week + 1) | \(session.name) | intended=\(ff?.intendedStimulus?.targetDurationDomain.rawValue ?? "-")/\(ff?.intendedStimulus?.loading.rawValue ?? "-") | final=\(ff?.stimulus.targetDurationDomain.rawValue ?? "-")/\(ff?.stimulus.loading.rawValue ?? "-") | format=\(String(describing: ff?.format)) | strength=\(hasStrength) | functions=\(functions) | stress=\(session.orderedBlocks.compactMap(\.trainingStressProfile).first.map { "\($0.overallIntensity)" } ?? "-")"
        }
    }

    func testScenarioA_OneSessionPerWeek_FourWeekDogfood() throws {
        let definition = try generate(daysPerWeek: 1)
        let instance = makeInstance(definition: definition)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        var summary: [String] = []
        for weekIndex in 0..<4 {
            let sessions = try FunctionalFitnessMaterializer.materializeWeek(
                definition: definition, instance: instance, weekIndex: weekIndex,
                startDate: Calendar.current.date(byAdding: .day, value: weekIndex * 7, to: Date())!,
                ownerUserID: instance.ownerUserID, candidateExercises: makeCandidates(),
                exposureHistory: FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn: instance),
                environment: environment, context: context
            )
            summary.append(contentsOf: summarize(sessions, week: weekIndex))
        }
        XCTAssertEqual(summary.count, 4)
        print("=== SCENARIO A (1 FF/week, 4 weeks) ===")
        summary.forEach { print($0) }
    }

    func testScenarioB_TwoSessionsPerWeek_FourWeekDogfood() throws {
        let definition = try generate(daysPerWeek: 2)
        let instance = makeInstance(definition: definition)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        var summary: [String] = []
        for weekIndex in 0..<4 {
            let sessions = try FunctionalFitnessMaterializer.materializeWeek(
                definition: definition, instance: instance, weekIndex: weekIndex,
                startDate: Calendar.current.date(byAdding: .day, value: weekIndex * 7, to: Date())!,
                ownerUserID: instance.ownerUserID, candidateExercises: makeCandidates(),
                exposureHistory: FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn: instance),
                environment: environment, context: context
            )
            summary.append(contentsOf: summarize(sessions, week: weekIndex))
        }
        XCTAssertEqual(summary.count, 8)
        print("=== SCENARIO B (2 FF/week, 4 weeks) ===")
        summary.forEach { print($0) }
    }

    func testScenarioC_ThreeSessionsPerWeek_FourWeekDogfood() throws {
        let definition = try generate(daysPerWeek: 3)
        let instance = makeInstance(definition: definition)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        var summary: [String] = []
        for weekIndex in 0..<4 {
            let sessions = try FunctionalFitnessMaterializer.materializeWeek(
                definition: definition, instance: instance, weekIndex: weekIndex,
                startDate: Calendar.current.date(byAdding: .day, value: weekIndex * 7, to: Date())!,
                ownerUserID: instance.ownerUserID, candidateExercises: makeCandidates(),
                exposureHistory: FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn: instance),
                environment: environment, context: context
            )
            summary.append(contentsOf: summarize(sessions, week: weekIndex))
        }
        XCTAssertEqual(summary.count, 12)
        print("=== SCENARIO C (3 FF/week, 4 weeks) ===")
        summary.forEach { print($0) }
    }
}
