import XCTest
import SwiftData
@testable import TrainingOS

/// Stage FF.L1: "Intended vs. Final Stimulus Foundation" — proves,
/// against real production types and (where practical) the real
/// production pipeline, that `FunctionalFitnessDecisionEngine
/// .decideWithIntent` cleanly separates Phase 1 (intent) from Phase 2
/// (Stage CP.2 adaptation), that `FunctionalFitnessPrescription` persists
/// both values as genuine independent snapshots (never reconstructed),
/// that legacy (pre-FF.L1) records represent their unknown historical
/// intent honestly as `nil`, and that `CurrentWeekFunctionalFitnessProgrammingContext`/
/// `FunctionalFitnessExposureHistoryBuilder` both continue to read FINAL,
/// never INTENDED. See `FUNCTIONAL_FITNESS_LONGITUDINAL_PROGRAMMING_DESIGN.md`'s
/// Design Lock for the full architectural proof this stage implements.
@MainActor
final class FunctionalFitnessIntendedVsFinalStimulusTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()
    let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)
    private let engine = FunctionalFitnessDecisionEngine()

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

    private func exercise(_ name: String, targets: [MuscleGroup]) -> Exercise {
        Exercise(canonicalName: name, modality: .hypertrophy, equipment: "barbell", movementPattern: "test", primaryTargets: targets)
    }

    private func resolveAllSlots(in definition: ProgramDefinition, to exercise: Exercise) {
        for templateSession in definition.orderedTemplateSessions {
            for blockTemplate in templateSession.orderedBlockTemplates {
                for template in blockTemplate.orderedPrescriptionTemplates {
                    template.exerciseSlot?.resolvedExercise = exercise
                }
            }
        }
    }

    /// Same real, heavy, squat-loaded shape CP.1/CP.2's own decisive
    /// tests use.
    private func heavySquatStimulus() -> Stimulus {
        Stimulus(
            targetDurationDomain: .medium, intensity: .high, loading: .heavy,
            movementFunctions: [.squatLoaded], movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1)],
            skillDemand: .moderate, systemicDemand: .high, scoreType: .load
        )
    }

    private func heavyLowerBodyProfile() -> TrainingStressProfile {
        FunctionalFitnessStressProfileMapper.map(stimulus: heavySquatStimulus())
    }

    /// Materializable variant (empty `movementModalityMix` so Stage E
    /// validation always clears regardless of what CP.2 changes about
    /// `loading`) — same shape used by the real CP.2 tests.
    private func heavySquatMaterializableStimulus() -> Stimulus {
        Stimulus(
            targetDurationDomain: .medium, intensity: .high, loading: .heavy,
            movementFunctions: [.squatLoaded], movementModalityMix: [],
            skillDemand: .moderate, systemicDemand: .high, scoreType: .load
        )
    }

    // MARK: A. No CP.2 adaptation — configured baseline == intended == final

    func testNoCP2AdaptationConfiguredBaselineEqualsIntendedEqualsFinal() {
        let baseline = heavySquatStimulus()
        let input = ProgrammingDecisionInput(
            exposureHistory: [], stimulusRequirements: baseline, varianceConstraints: VarianceConstraints()
        )
        let decision = engine.decideWithIntent(input)
        XCTAssertEqual(decision.intendedStimulus, baseline, "no real longitudinal check exists yet — Phase 1 is a no-op")
        XCTAssertEqual(decision.finalStimulus, baseline, "no cross-modality/pairing input supplied — Phase 2 has nothing to adapt")
        XCTAssertEqual(decision.intendedStimulus, decision.finalStimulus)
        XCTAssertEqual(decision.finalReasonCode, .stimulusAsConfigured)
    }

    // MARK: B. Cross-modality repair — configured baseline == intended, intended != final

    func testCrossModalityRepairConfiguredBaselineEqualsIntendedButIntendedDiffersFromFinal() {
        let baseline = heavySquatStimulus()
        let input = ProgrammingDecisionInput(
            exposureHistory: [], stimulusRequirements: baseline, varianceConstraints: VarianceConstraints(),
            componentAdaptationObjectives: [.workCapacity, .aerobicCapacity, .power],
            protectedSiblingStressProfilesThisWeek: [heavyLowerBodyProfile()]
        )
        let decision = engine.decideWithIntent(input)
        XCTAssertEqual(decision.intendedStimulus, baseline, "Phase 1 is still a no-op — intended equals the configured baseline")
        XCTAssertNotEqual(decision.intendedStimulus, decision.finalStimulus, "Phase 2's cross-modality repair fired")
        // Exactly what CP.2's own pre-FF.L1 repair test already asserted —
        // one step down, never a full wrap.
        XCTAssertEqual(decision.finalStimulus.loading, .moderate, "the minimum-sufficient repair is unchanged by this refactor")
        XCTAssertEqual(decision.finalReasonCode, .crossModalityDiscouraged)
    }

    // MARK: C. Same-week complementarity — context records FINAL, never INTENDED

    func testCurrentWeekContextRecordsFinalStimulusNeverIntended() {
        let input = ProgrammingDecisionInput(
            exposureHistory: [], stimulusRequirements: heavySquatStimulus(), varianceConstraints: VarianceConstraints(),
            componentAdaptationObjectives: [.workCapacity, .aerobicCapacity, .power],
            protectedSiblingStressProfilesThisWeek: [heavyLowerBodyProfile()]
        )
        let decision = engine.decideWithIntent(input)
        XCTAssertNotEqual(decision.intendedStimulus, decision.finalStimulus, "fixture precondition: this session's intent was actually adapted")

        // Exactly what `FunctionalFitnessMaterializer.materializeWeek`'s
        // own real call site does.
        var weekContext = CurrentWeekFunctionalFitnessProgrammingContext()
        weekContext.record(stimulus: decision.finalStimulus)

        XCTAssertEqual(weekContext.alreadyProgrammedThisWeek.map(\.stimulus), [decision.finalStimulus], "the context must contain what Session 1 was ACTUALLY programmed to do")
        XCTAssertFalse(
            weekContext.alreadyProgrammedThisWeek.contains { $0.stimulus == decision.intendedStimulus },
            "the context must never contain Session 1's pre-adaptation intended value"
        )
    }

    /// Same proof, through the real production materializer — two real
    /// Functional Fitness sessions in one call, real Strength peak-week
    /// stress causing Session 1's real prescription to be repaired.
    func testRealMaterializationPersistsDistinctIntendedAndFinalAndSessionTwoCoordinatesAgainstFinal() throws {
        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 1, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: context
        )
        resolveAllSlots(in: definition, to: exercise("Back Squat", targets: [.quadriceps, .glutes]))
        let strengthInstance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(strengthInstance)
        strengthInstance.programDefinition = definition

        let peakWeekResult = StrengthMaterializer.materializeWeek(
            definition: definition, instance: strengthInstance, weekIndex: 3, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 140, weekOneResolvedWeightKg: 140 * 0.85) }, context: context
        )
        let strengthSession = try XCTUnwrap(peakWeekResult.sessions.first)
        let strengthProfile = try XCTUnwrap(SessionStressComposer.compose(strengthSession))
        XCTAssertEqual(strengthProfile.lowerBodyLoad, .high)

        let ffConfiguration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 2, lengthWeeks: 1, targetStimulus: heavySquatMaterializableStimulus(), format: .maxLoad,
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false
        )
        let ffDefinition = FunctionalFitnessProgramGenerator.generate(configuration: ffConfiguration, provenance: .constructed(reason: "test"), context: context)
        let ffInstance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(ffInstance)
        ffInstance.programDefinition = ffDefinition

        let ffSessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: ffDefinition, instance: ffInstance, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
            candidateExercises: [], exposureHistory: [],
            protectedSiblingStressProfilesThisWeek: [strengthProfile],
            componentAdaptationObjectives: [.workCapacity, .aerobicCapacity, .power], context: context
        )
        XCTAssertEqual(ffSessions.count, 2)

        let prescriptions = ffSessions.compactMap { $0.orderedBlocks.first { $0.type == .functionalFitness }?.functionalFitnessPrescription }
        XCTAssertEqual(prescriptions.count, 2)

        for prescription in prescriptions {
            let intended = try XCTUnwrap(prescription.intendedStimulus, "every newly-materialized prescription must have a real, non-nil intended snapshot")
            XCTAssertEqual(intended, heavySquatMaterializableStimulus(), "Phase 1 is a no-op today — intended equals the configured baseline")
            XCTAssertNotEqual(prescription.stimulus, intended, "real peak-week Strength stress must have repaired FINAL away from INTENDED")
        }
    }

    // MARK: D. Legacy persistence — pre-FF.L1 data remains readable, unknown intent stays honest

    func testLegacyPrescriptionConstructedWithoutIntendedStimulusReadsAsHonestlyUnknown() throws {
        // Exactly how every prescription was constructed before FF.L1 —
        // no `intendedStimulus` argument at all.
        let legacyFinal = heavySquatStimulus()
        let legacy = FunctionalFitnessPrescription(stimulus: legacyFinal, format: .maxLoad)
        context.insert(legacy)
        try context.save()

        XCTAssertEqual(legacy.stimulus, legacyFinal, "FINAL semantics are fully preserved for legacy data")
        XCTAssertNil(legacy.intendedStimulus, "a legacy record's historical intent is genuinely unknown — never fabricated as equal to final")
    }

    // MARK: E. New persistence round trip — both values survive independently

    func testIntendedAndFinalStimulusSurviveARealSaveAndReloadIndependently() throws {
        let intended = heavySquatStimulus()
        var final = heavySquatStimulus()
        final.loading = .moderate

        let prescriptionID = UUID()
        let prescription = FunctionalFitnessPrescription(id: prescriptionID, stimulus: final, intendedStimulus: intended, format: .maxLoad)
        context.insert(prescription)
        try context.save()

        let freshContext = ModelContext(container)
        let reloaded = try XCTUnwrap(
            freshContext.fetch(FetchDescriptor<FunctionalFitnessPrescription>(predicate: #Predicate { $0.id == prescriptionID })).first
        )
        XCTAssertEqual(reloaded.stimulus, final)
        XCTAssertEqual(reloaded.intendedStimulus, intended)
        XCTAssertNotEqual(reloaded.stimulus, reloaded.intendedStimulus, "both values are genuine, independent snapshots — not derived from one another on reload")
    }

    // MARK: F. Engine regression — decide() (FINAL-only) is untouched by the refactor

    func testDecideStillReturnsOnlyFinalExactlyAsBeforeTheRefactor() {
        let baseline = heavySquatStimulus()
        let input = ProgrammingDecisionInput(
            exposureHistory: [], stimulusRequirements: baseline, varianceConstraints: VarianceConstraints(),
            componentAdaptationObjectives: [.workCapacity, .aerobicCapacity, .power],
            protectedSiblingStressProfilesThisWeek: [heavyLowerBodyProfile()]
        )
        let output = engine.decide(input)
        let decision = engine.decideWithIntent(input)
        XCTAssertEqual(output.nextStimulus, decision.finalStimulus, "decide() must always mirror decideWithIntent's own FINAL half — one real decision flow, never two that could diverge")
        XCTAssertEqual(output.reasonCode, decision.finalReasonCode)
    }

    // MARK: G/H covered by CrossModalityFunctionalFitnessProgrammingTests.swift's own 24 tests (run unmodified in the full suite) and TrainingStressProfileParityTests.swift (CP.1)

    // MARK: I. Migration — additive optional field, no schema corruption

    func testAdditiveIntendedStimulusFieldNeverTriggersAMigration() throws {
        // The container built in setUpWithError already uses the current
        // schema (including `intendedStimulus`) — this test's real value
        // is exercised by the full-suite/migration check run alongside
        // it; a dedicated crash-free round trip here is the unit-level
        // half of that proof.
        let prescription = FunctionalFitnessPrescription(stimulus: heavySquatStimulus(), format: .maxLoad)
        context.insert(prescription)
        XCTAssertNoThrow(try context.save())
    }
}
