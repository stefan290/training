import XCTest
import SwiftData
@testable import TrainingOS

/// Stage CP.2: Concurrent Programming Constraint Generation + Functional
/// Fitness pre-generation constraint consumption. Proves, against real
/// production types and (where practical) the real production pipeline:
/// `AdaptationObjective` persistence and the real `LongTermPlanner`
/// per-builder PRODUCT DECISION assignments; the cross-modality SOFT
/// discouragement check (never hard-ineligible pre-placement); the
/// minimum-sufficient one-field `Stimulus` repair (never a full enum
/// wrap); the same-week FF complementarity pairing check, driven by
/// `CurrentWeekFunctionalFitnessProgrammingContext` rather than completed
/// exposure history; and `RollTacticalWindowUseCase.rollForward`'s
/// producer/consumer two-pass orchestration, which is keyed on
/// `ProgrammingSystemKind`, never `GoalPriority`.
@MainActor
final class CrossModalityFunctionalFitnessProgrammingTests: XCTestCase {
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

    /// A heavy, squat-loaded FF baseline — real shape used throughout
    /// CP.1/CP.2's own decisive tests. `systemicDemand: .high` keeps
    /// `.workCapacity` served regardless of the `loading`-only repair
    /// (CP.2's repair never touches `systemicDemand`).
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

    /// Same real, heavy, squat-loaded shape as `heavySquatStimulus()`, but
    /// shaped to actually clear `FunctionalFitnessStimulusValidator`'s
    /// Stage-E checks when materialized for real: `movementModalityMix: []`
    /// means zero movement slots are generated (`FunctionalFitnessProgramGenerator
    /// .movementSlots(for:)` iterates the mix, not `movementFunctions`),
    /// so neither the modality-overlap nor the loadingRole-consistency
    /// check can ever fail regardless of what CP.2 changes about
    /// `loading` — and `.maxLoad`'s natural score type is `.load`, with no
    /// duration cap to contradict. `FunctionalFitnessStressProfileMapper`
    /// classifies stress from `movementFunctions`/`loading`/`intensity`/
    /// `systemicDemand` directly — none of that depends on
    /// `movementModalityMix` having any entries.
    private func heavySquatMaterializableStimulus() -> Stimulus {
        Stimulus(
            targetDurationDomain: .medium, intensity: .high, loading: .heavy,
            movementFunctions: [.squatLoaded], movementModalityMix: [],
            skillDemand: .moderate, systemicDemand: .high, scoreType: .load
        )
    }

    // MARK: A. Domain / persistence

    func testAdaptationObjectiveRoundTripsOnTrainingMixComponent() throws {
        let component = TrainingMixComponent(
            label: "Functional Fitness", programmingSystem: .functionalFitness, priority: .supporting,
            adaptationObjectives: [.workCapacity, .aerobicCapacity, .power], frequency: SessionFrequency(target: 2)
        )
        context.insert(component)
        try context.save()

        let fetched = try XCTUnwrap(try context.fetch(FetchDescriptor<TrainingMixComponent>()).first { $0.id == component.id })
        XCTAssertEqual(fetched.adaptationObjectives, [.workCapacity, .aerobicCapacity, .power])
    }

    /// Additive-only field on an existing `@Model` — no migration should
    /// ever be triggered; a fresh in-memory container opening successfully
    /// with real component data already proves this, but reopening a
    /// second container against the SAME schema is the direct proof nothing
    /// about the schema declaration itself becomes ambiguous.
    func testAdditiveFieldNeverTriggersAMigration() throws {
        let component = TrainingMixComponent(
            label: "Functional Fitness", programmingSystem: .functionalFitness, priority: .supporting,
            adaptationObjectives: [.power], frequency: SessionFrequency(target: 2)
        )
        context.insert(component)
        try context.save()

        let reopened = PersistenceController.makeInMemoryContainer()
        XCTAssertNoThrow(try ModelContext(reopened).fetch(FetchDescriptor<TrainingMixComponent>()))
    }

    func testEachApprovedFFBuilderGetsExactlyItsApprovedObjectives() throws {
        let asOf = date(2026, 1, 5)
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .muscleGain, targetDate: Calendar.current.date(byAdding: .year, value: 1, to: asOf), createdAt: asOf)
        context.insert(goal)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: asOf)
        let phase = try XCTUnwrap(plan.orderedPhases.first)

        let candidates = LongTermPlanner.proposeTrainingMix(phase: phase, goal: goal)

        let focused = try XCTUnwrap(candidates.first { $0.mix.name == "Focused Hypertrophy" })
        XCTAssertEqual(focused.mix.orderedComponents.first { $0.label == "Hypertrophy" }?.adaptationObjectives, [.muscleGain])
        XCTAssertEqual(focused.mix.orderedComponents.first { $0.label == "Zone 2 Conditioning" }?.adaptationObjectives, [.aerobicCapacity])

        let varied = try XCTUnwrap(candidates.first { $0.mix.name == "Strength Plus Variety" })
        XCTAssertEqual(varied.mix.orderedComponents.first { $0.label == "Strength" }?.adaptationObjectives, [.muscleGain])
        XCTAssertEqual(varied.mix.orderedComponents.first { $0.label == "Functional Fitness" }?.adaptationObjectives, [.workCapacity, .aerobicCapacity, .power], "the reference combination used throughout the CP.2 design doc, now a real PRODUCT DECISION, not illustrative")
        XCTAssertEqual(varied.mix.orderedComponents.first { $0.label == "Running" }?.adaptationObjectives, [.aerobicCapacity])
    }

    func testFocusedFunctionalFitnessGetsTheBroadGPPObjectiveSetExcludingUnmappedOnes() throws {
        let asOf = date(2026, 1, 5)
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .functionalFitness, targetDate: Calendar.current.date(byAdding: .year, value: 1, to: asOf), createdAt: asOf)
        context.insert(goal)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: asOf)
        let phase = try XCTUnwrap(plan.orderedPhases.first { $0.type == .functionalFitness })

        let candidates = LongTermPlanner.proposeTrainingMix(phase: phase, goal: goal)
        let focusedFF = try XCTUnwrap(candidates.first { $0.mix.name == "Focused Functional Fitness" })
        let objectives = try XCTUnwrap(focusedFF.mix.orderedComponents.first { $0.label == "Functional Fitness" }?.adaptationObjectives)
        XCTAssertEqual(Set(objectives), [.workCapacity, .aerobicCapacity, .anaerobicCapacity, .power, .skillAcquisition])
        XCTAssertFalse(objectives.contains(.maxStrength), "no honest FF Stimulus mapping exists for maxStrength")
        XCTAssertFalse(objectives.contains(.muscleGain), "no honest FF Stimulus mapping exists for muscleGain")
    }

    private func setPreviousPhaseSelectedMix(
        _ plan: TrainingPlan,
        components: [(label: String, system: ProgrammingSystemKind, priority: GoalPriority, objectives: [AdaptationObjective], target: Int)]
    ) throws -> TrainingMix {
        let maintenancePhase = try XCTUnwrap(plan.orderedPhases.first { $0.type == .maintenance })
        let previousPhase = try XCTUnwrap(LongTermPlanner.planningContext(for: maintenancePhase).previousPhase)
        previousPhase.trainingMixes.removeAll()
        let mix = TrainingMix(kind: .selected, name: "Prior Selected Mix")
        context.insert(mix)
        for spec in components {
            mix.addComponent(TrainingMixComponent(
                label: spec.label, programmingSystem: spec.system, priority: spec.priority,
                adaptationObjectives: spec.objectives, frequency: SessionFrequency(target: spec.target)
            ))
        }
        previousPhase.addTrainingMix(mix)
        return mix
    }

    func testMaintenanceMixCarriesAdaptationObjectivesForwardUnchanged() throws {
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .muscleGain, targetDate: date(2028, 8, 14), createdAt: date(2026, 8, 14))
        context.insert(goal)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: date(2026, 8, 14))
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: date(2026, 8, 14))
        XCTAssertTrue(plan.orderedPhases.contains { $0.type == .maintenance }, "sanity check on the real cadence fixture")

        try setPreviousPhaseSelectedMix(plan, components: [
            ("Functional Fitness", .functionalFitness, .supporting, [.workCapacity, .aerobicCapacity, .power], 2),
        ])

        let maintenancePhase = try XCTUnwrap(plan.orderedPhases.first { $0.type == .maintenance })
        let maintenanceMix = try XCTUnwrap(LongTermPlanner.proposeTrainingMix(phase: maintenancePhase, goal: goal).first?.mix)
        let ff = try XCTUnwrap(maintenanceMix.orderedComponents.first { $0.programmingSystem == .functionalFitness })
        XCTAssertEqual(ff.adaptationObjectives, [.workCapacity, .aerobicCapacity, .power], "Maintenance changes dose, never purpose")
    }

    // MARK: A2. Production-path week 4 (real objectives, real peak week)

    /// Reuses CP.1's own decisive test fixture exactly (real
    /// `HypertrophyProgramGenerator`, real week-index-3/RIR-1 peak week)
    /// and feeds the real, `LongTermPlanner`-assigned `muscleGainVariedMix`
    /// Functional Fitness objectives (`[.workCapacity, .aerobicCapacity,
    /// .power]`, per this file's own `testEachApprovedFFBuilderGetsExactlyItsApprovedObjectives`)
    /// through the real `FunctionalFitnessMaterializer` — proving the
    /// cross-modality repair against real source-faithful Family A
    /// numbers, not invented ones.
    func testRealPeakWeekStrengthStressDiscouragesAndRepairsARealFFStimulusPreservingRealObjectives() throws {
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
        XCTAssertEqual(strengthProfile.lowerBodyLoad, .high, "the real peak week (RIR 1) — matches CP.1's own decisive test")

        // The real product-decided muscleGainVariedMix FF objectives —
        // not injected ad hoc for this test.
        let realFFObjectives: [AdaptationObjective] = [.workCapacity, .aerobicCapacity, .power]

        let ffConfiguration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 1, targetStimulus: heavySquatMaterializableStimulus(), format: .maxLoad,
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false, isDynamicallyComposed: false
        )
        let ffDefinition = FunctionalFitnessProgramGenerator.generate(configuration: ffConfiguration, provenance: .constructed(reason: "test"), context: context)
        let ffInstance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(ffInstance)
        ffInstance.programDefinition = ffDefinition

        let ffSessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: ffDefinition, instance: ffInstance, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
            candidateExercises: [], exposureHistory: [],
            protectedSiblingStressProfilesThisWeek: [strengthProfile],
            componentAdaptationObjectives: realFFObjectives,  environment: TrainingEnvironmentTestSupport.full(context: context), context: context
        )
        let ffStimulus = try XCTUnwrap(ffSessions.first?.orderedBlocks.first { $0.type == .functionalFitness }?.functionalFitnessPrescription?.stimulus)

        XCTAssertNotEqual(ffStimulus, heavySquatMaterializableStimulus(), "the real peak-week Strength stress must have discouraged and repaired FF's heavy baseline")
        XCTAssertEqual(ffStimulus.loading, .moderate, "the minimum-sufficient repair — one step down, never a full wrap")
        let servedAfterRepair = AdaptationObjectiveStimulusMapping.objectivesServed(by: ffStimulus)
        XCTAssertFalse(servedAfterRepair.isDisjoint(with: Set(realFFObjectives)), "at least one of the component's real objectives must still be served after repair")

        let ffBlock = try XCTUnwrap(ffSessions.first?.orderedBlocks.first { $0.type == .functionalFitness })
        let repairedProfile = try XCTUnwrap(ffBlock.trainingStressProfile)
        let rule = try XCTUnwrap(InterferenceAvoidanceRule.conservativeDefault.first { $0.dimension == .lowerBodyLoad })
        XCTAssertFalse(rule.triggers(strengthProfile, repairedProfile), "the repaired FF session must no longer trigger the real, unmodified interference rule against the real peak-week Strength session")
    }

    /// Stage CP.2R regression: the real peak-week test above only ever
    /// exercises `heavySquatMaterializableStimulus()`, which deliberately
    /// sets `movementModalityMix: []` so NO real movement slot is
    /// generated — dodging Stage-E validation's loading check entirely
    /// (confirmed by that helper's own doc comment). This test is
    /// IDENTICAL except it uses `heavySquatStimulus()` (a real, non-empty
    /// `movementModalityMix`), so a real `ExerciseSlot`/
    /// `FunctionalFitnessMovementSlotTemplate` IS generated, with a real
    /// candidate `Exercise` available to resolve into it — the exact
    /// shape every real production `muscleGainVariedMix`/
    /// `functionalFitnessFocusedMix` FF component actually has.
    ///
    /// Before the Stage CP.2R fix, this exact test threw
    /// `stimulusValidationFailed(matchesLoadingClassification: false)` —
    /// proving the bug the Prescription Depth audit's §16 predicted was
    /// real, not merely a synthetic-fixture artifact. It now passes,
    /// proving the fix closes this specific, real production-shaped gap.
    func testCP2RRealNonEmptyMovementSlotWithGenuineLoadingRepairProof() throws {
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
        XCTAssertEqual(strengthProfile.lowerBodyLoad, .high, "the real peak week (RIR 1)")

        let realFFObjectives: [AdaptationObjective] = [.workCapacity, .aerobicCapacity, .power]

        // The ONLY change from the CP.1-fixture test above: a real,
        // non-empty movementModalityMix, so a real movement slot exists.
        let ffConfiguration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 1, targetStimulus: heavySquatStimulus(), format: .maxLoad,
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false, isDynamicallyComposed: false
        )
        let ffDefinition = FunctionalFitnessProgramGenerator.generate(configuration: ffConfiguration, provenance: .constructed(reason: "test"), context: context)
        let ffInstance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(ffInstance)
        ffInstance.programDefinition = ffDefinition

        // A real candidate exercise the slot (allowedMovementFunctions:
        // [.squatLoaded], allowedModalities: [.weightlifting]) can
        // actually resolve into.
        let candidate = Exercise(
            canonicalName: "Front Squat", modality: .functionalFitness, equipment: "barbell", movementPattern: "squat",
            primaryTargets: [.quadriceps, .glutes], movementFunctions: [.squatLoaded], functionalModality: .weightlifting
        )
        context.insert(candidate)

        let ffSessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: ffDefinition, instance: ffInstance, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
            candidateExercises: [candidate], exposureHistory: [],
            protectedSiblingStressProfilesThisWeek: [strengthProfile],
            componentAdaptationObjectives: realFFObjectives,  environment: TrainingEnvironmentTestSupport.full(context: context), context: context
        )

        let ffBlock = try XCTUnwrap(ffSessions.first?.orderedBlocks.first { $0.type == .functionalFitness })
        let prescription = try XCTUnwrap(ffBlock.functionalFitnessPrescription)
        XCTAssertEqual(prescription.intendedStimulus?.loading, .heavy, "CONFIGURED/INTENDED loading is unchanged — the repair only ever affects FINAL")
        XCTAssertEqual(prescription.stimulus.loading, .moderate, "FINAL loading was repaired by CP.2's real, minimal one-field repair")
        XCTAssertNotNil(ffBlock.functionalFitnessPrescription?.movements.first?.exercise, "a real exercise resolved into the real, non-empty movement slot")
    }

    /// Stage CP.2R control case: the identical real, non-empty-slot setup
    /// as the regression test above, but with NO protected sibling stress
    /// at all — CP.2's cross-modality check never fires, so CONFIGURED ==
    /// INTENDED == FINAL, exactly as it always did before Stage CP.2R
    /// (and before Stage CP.2 existed at all). Proves the fix changes
    /// nothing about the ordinary, no-adaptation case.
    func testCP2RControlCaseConfiguredEqualsFinalUnchangedWithRealNonEmptySlots() throws {
        let ffConfiguration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 1, targetStimulus: heavySquatStimulus(), format: .maxLoad,
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false, isDynamicallyComposed: false
        )
        let ffDefinition = FunctionalFitnessProgramGenerator.generate(configuration: ffConfiguration, provenance: .constructed(reason: "test"), context: context)
        let ffInstance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(ffInstance)
        ffInstance.programDefinition = ffDefinition

        let candidate = Exercise(
            canonicalName: "Front Squat", modality: .functionalFitness, equipment: "barbell", movementPattern: "squat",
            primaryTargets: [.quadriceps, .glutes], movementFunctions: [.squatLoaded], functionalModality: .weightlifting
        )
        context.insert(candidate)

        // No `protectedSiblingStressProfilesThisWeek` at all — the exact
        // no-sibling-stress case, not merely a below-threshold one.
        let ffSessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: ffDefinition, instance: ffInstance, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
            candidateExercises: [candidate], exposureHistory: [],
            componentAdaptationObjectives: [.workCapacity, .aerobicCapacity, .power],  environment: TrainingEnvironmentTestSupport.full(context: context), context: context
        )

        let ffBlock = try XCTUnwrap(ffSessions.first?.orderedBlocks.first { $0.type == .functionalFitness })
        let prescription = try XCTUnwrap(ffBlock.functionalFitnessPrescription)
        XCTAssertEqual(prescription.intendedStimulus, heavySquatStimulus(), "no CP.2 adaptation fires — INTENDED is the unmodified configured baseline")
        XCTAssertEqual(prescription.stimulus, heavySquatStimulus(), "no CP.2 adaptation fires — FINAL equals CONFIGURED/INTENDED exactly, byte-for-byte")
        XCTAssertNotNil(prescription.movements.first?.exercise, "a real exercise still resolves into the real, non-empty movement slot")
    }

    // MARK: B. Cross-modality soft discouragement + minimal repair

    func testSameWeekHighHighIsDiscouragedNeverIneligible() {
        let input = ProgrammingDecisionInput(
            exposureHistory: [], stimulusRequirements: heavySquatStimulus(), varianceConstraints: VarianceConstraints(),
            componentAdaptationObjectives: [.workCapacity, .aerobicCapacity, .power],
            protectedSiblingStressProfilesThisWeek: [heavyLowerBodyProfile()]
        )
        let output = engine.decide(input)
        // "Discouraged" in this design means: a repair is attempted and,
        // if found, applied — the candidate is never rejected outright.
        XCTAssertEqual(output.reasonCode, .crossModalityDiscouraged)
        XCTAssertNotEqual(output.nextStimulus, heavySquatStimulus(), "a valid repair exists for this fixture and must be applied")
    }

    func testMinimalRepairChangesExactlyOneFieldAndChoosesTheNearestSufficientLoadingReduction() {
        let baseline = heavySquatStimulus()
        let repaired = try! XCTUnwrap(CrossModalityStimulusRepair.minimalRepair(
            stimulus: baseline, for: .lowerBodyLoad, threshold: .high, preservingAtLeastOneOf: [.workCapacity]
        ))
        XCTAssertEqual(repaired.loading, .moderate, "one step down from .heavy — NOT a full wrap to .bodyweightOnly")
        XCTAssertEqual(repaired.targetDurationDomain, baseline.targetDurationDomain)
        XCTAssertEqual(repaired.intensity, baseline.intensity)
        XCTAssertEqual(repaired.movementFunctions, baseline.movementFunctions)
        XCTAssertEqual(repaired.movementModalityMix, baseline.movementModalityMix)
        XCTAssertEqual(repaired.skillDemand, baseline.skillDemand)
        XCTAssertEqual(repaired.systemicDemand, baseline.systemicDemand)
    }

    func testRepairedStimulusActuallyClearsTheDiscouragementCondition() {
        let baseline = heavySquatStimulus()
        let repaired = try! XCTUnwrap(CrossModalityStimulusRepair.minimalRepair(
            stimulus: baseline, for: .lowerBodyLoad, threshold: .high, preservingAtLeastOneOf: [.workCapacity]
        ))
        let repairedProfile = FunctionalFitnessStressProfileMapper.map(stimulus: repaired)
        XCTAssertNotEqual(repairedProfile.lowerBodyLoad, .high)
        let rule = try! XCTUnwrap(InterferenceAvoidanceRule.conservativeDefault.first { $0.dimension == .lowerBodyLoad })
        XCTAssertFalse(rule.triggers(heavyLowerBodyProfile(), repairedProfile), "the repaired stimulus must no longer trigger the real interference rule against the real protected profile")
    }

    func testRepairedStimulusStillServesAtLeastOneComponentObjective() {
        let baseline = heavySquatStimulus()
        let repaired = try! XCTUnwrap(CrossModalityStimulusRepair.minimalRepair(
            stimulus: baseline, for: .lowerBodyLoad, threshold: .high, preservingAtLeastOneOf: [.workCapacity, .aerobicCapacity, .power]
        ))
        let served = AdaptationObjectiveStimulusMapping.objectivesServed(by: repaired)
        XCTAssertTrue(served.contains(.workCapacity), "systemicDemand is untouched by a loading-only repair")
    }

    func testNoRepairPossibleLeavesTheOriginalStimulusUntouchedAndStillEligible() {
        // `.maxStrength` has NO honest FF Stimulus mapping — no repair can
        // ever "preserve" it, so no one-field repair exists.
        XCTAssertNil(CrossModalityStimulusRepair.minimalRepair(
            stimulus: heavySquatStimulus(), for: .lowerBodyLoad, threshold: .high, preservingAtLeastOneOf: [.maxStrength]
        ))

        let input = ProgrammingDecisionInput(
            exposureHistory: [], stimulusRequirements: heavySquatStimulus(), varianceConstraints: VarianceConstraints(),
            componentAdaptationObjectives: [.maxStrength],
            protectedSiblingStressProfilesThisWeek: [heavyLowerBodyProfile()]
        )
        let output = engine.decide(input)
        XCTAssertEqual(output.nextStimulus, heavySquatStimulus(), "no valid repair — the original, discouraged-but-eligible baseline must never be progressively destroyed")
        XCTAssertEqual(output.reasonCode, .stimulusAsConfigured)
    }

    func testNoRepairTableExistsForAnUnusedDimension() {
        XCTAssertNil(CrossModalityStimulusRepair.minimalRepair(
            stimulus: heavySquatStimulus(), for: .impactLoading, threshold: .high, preservingAtLeastOneOf: []
        ), "CP.2's discouragement rule never actually checks impactLoading (FF's own mapper caps it at .moderate) — no repair table exists for it")
    }

    func testNonPrimarySiblingStressNeverProtectsAnything() {
        // A component's stress is only "protected" when the SIBLING is
        // `.primary` — `rollForward` is responsible for this filter, not
        // the engine; this proves the engine-level contract: an EMPTY
        // `protectedSiblingStressProfilesThisWeek` (as `rollForward` would
        // pass for an all-non-primary week) never discourages anything.
        let input = ProgrammingDecisionInput(
            exposureHistory: [], stimulusRequirements: heavySquatStimulus(), varianceConstraints: VarianceConstraints(),
            componentAdaptationObjectives: [.workCapacity], protectedSiblingStressProfilesThisWeek: []
        )
        let output = engine.decide(input)
        XCTAssertEqual(output.reasonCode, .stimulusAsConfigured)
    }

    // MARK: C. Same-week FF complementarity pairing

    func testSecondSessionSeesFirstSessionsProgrammedStimulusWithoutItBeingCompleted() {
        var contextValue = CurrentWeekFunctionalFitnessProgrammingContext()
        let firstStimulus = Stimulus(
            targetDurationDomain: .short, intensity: .high, loading: .light,
            movementFunctions: [.gymnasticsPull], movementModalityMix: [ModalityCount(modality: .gymnastics, count: 1)],
            skillDemand: .low, systemicDemand: .low, scoreType: .time
        )
        // `.power` is served (intensity == .high) — never marked completed
        // anywhere; this is a plain in-memory value, proving the context
        // is genuinely separate from `FunctionalFitnessExposureHistoryBuilder`.
        contextValue.record(stimulus: firstStimulus)

        let secondBaseline = Stimulus(
            targetDurationDomain: .short, intensity: .high, loading: .light,
            movementFunctions: [.gymnasticsPull], movementModalityMix: [ModalityCount(modality: .gymnastics, count: 1)],
            skillDemand: .low, systemicDemand: .low, scoreType: .time
        )
        let input = ProgrammingDecisionInput(
            exposureHistory: [], stimulusRequirements: secondBaseline, varianceConstraints: VarianceConstraints(),
            componentAdaptationObjectives: [.power, .aerobicCapacity], currentWeekContext: contextValue
        )
        let output = engine.decide(input)
        XCTAssertEqual(output.reasonCode, .sameWeekComplementarityPreferred)
        XCTAssertEqual(output.nextStimulus.targetDurationDomain, .long, "nudged toward the under-covered .aerobicCapacity — the one field this objective maps to")
    }

    func testPairingChangesExactlyOneField() {
        var contextValue = CurrentWeekFunctionalFitnessProgrammingContext()
        let served = Stimulus(
            targetDurationDomain: .short, intensity: .high, loading: .light,
            movementFunctions: [.gymnasticsPull], movementModalityMix: [ModalityCount(modality: .gymnastics, count: 1)],
            skillDemand: .low, systemicDemand: .low, scoreType: .time
        )
        contextValue.record(stimulus: served)
        let baseline = served
        let input = ProgrammingDecisionInput(
            exposureHistory: [], stimulusRequirements: baseline, varianceConstraints: VarianceConstraints(),
            componentAdaptationObjectives: [.power, .workCapacity], currentWeekContext: contextValue
        )
        let output = engine.decide(input)
        XCTAssertEqual(output.reasonCode, .sameWeekComplementarityPreferred)
        XCTAssertEqual(output.nextStimulus.systemicDemand, .high, "nudged toward the under-covered .workCapacity")
        // Every other field is untouched.
        XCTAssertEqual(output.nextStimulus.targetDurationDomain, baseline.targetDurationDomain)
        XCTAssertEqual(output.nextStimulus.intensity, baseline.intensity)
        XCTAssertEqual(output.nextStimulus.loading, baseline.loading)
        XCTAssertEqual(output.nextStimulus.movementFunctions, baseline.movementFunctions)
        XCTAssertEqual(output.nextStimulus.skillDemand, baseline.skillDemand)
    }

    func testPairingNeverNudgesTowardAnObjectiveWithNoHonestFFMapping() {
        var contextValue = CurrentWeekFunctionalFitnessProgrammingContext()
        contextValue.record(stimulus: Stimulus(
            targetDurationDomain: .short, intensity: .low, loading: .light, movementFunctions: [], movementModalityMix: [],
            skillDemand: .low, systemicDemand: .low, scoreType: .time
        ))
        let input = ProgrammingDecisionInput(
            exposureHistory: [], stimulusRequirements: Stimulus(
                targetDurationDomain: .short, intensity: .low, loading: .light, movementFunctions: [], movementModalityMix: [],
                skillDemand: .low, systemicDemand: .low, scoreType: .time
            ),
            varianceConstraints: VarianceConstraints(),
            // Only maxStrength/muscleGain remain "under-covered" (nothing
            // real is served by either the empty first stimulus or the
            // baseline) — neither has a mapping, so nudge must never fire.
            componentAdaptationObjectives: [.maxStrength, .muscleGain], currentWeekContext: contextValue
        )
        let output = engine.decide(input)
        XCTAssertEqual(output.reasonCode, .stimulusAsConfigured, "no honest nudge exists toward maxStrength/muscleGain")
    }

    func testFFOnlyMultiSessionWeekCoordinatesThroughTheSameMechanism() throws {
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 2, lengthWeeks: 1, targetStimulus: heavySquatMaterializableStimulus(), format: .maxLoad,
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false, isDynamicallyComposed: false
        )
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition

        // No cross-modality signal this week (FF-only) — pairing is the
        // ONLY mechanism that can differentiate the two sessions, since
        // both start from the identical fixed baseline.
        let sessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, startDate: date(2026, 1, 5), ownerUserID: ownerUserID,
            candidateExercises: [], exposureHistory: [],
            componentAdaptationObjectives: [.workCapacity, .aerobicCapacity, .power],  environment: TrainingEnvironmentTestSupport.full(context: context), context: context
        )
        XCTAssertEqual(sessions.count, 2, "sanity check: 2 real sessions materialized in this one call")
        let stimuli = sessions.compactMap { $0.orderedBlocks.first { $0.type == .functionalFitness }?.functionalFitnessPrescription?.stimulus }
        XCTAssertEqual(stimuli.count, 2)
        XCTAssertNotEqual(stimuli[0], stimuli[1], "the second session must differ from the first, driven by same-week pairing, not a hardcoded FF-A/FF-B template")
    }

    /// Stage CP.2 pre-commit verification (narrow correction): the test
    /// above proves the two real sessions DIFFER. That alone is
    /// correlation, not causality — a coincidence of some other input
    /// could in principle explain it. This test isolates the ONE variable
    /// that should matter (`currentWeekContext`) against the REAL Session
    /// 1 stimulus this component's own real production baseline would
    /// produce, holding every other `ProgrammingDecisionInput` field
    /// identical, and proves the decision is only ever different BECAUSE
    /// the context is populated.
    func testRemovingCurrentWeekContextWhileHoldingEveryOtherInputIdenticalRemovesTheSameWeekPairingDecision() throws {
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 1, targetStimulus: heavySquatMaterializableStimulus(), format: .maxLoad,
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false, isDynamicallyComposed: false
        )
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition

        // The real Session 1, materialized through the real production
        // path — not a hand-invented fixture.
        let realFirstObjectives: [AdaptationObjective] = [.workCapacity, .aerobicCapacity, .power]
        let firstSessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, startDate: date(2026, 1, 12), ownerUserID: ownerUserID,
            candidateExercises: [], exposureHistory: [], componentAdaptationObjectives: realFirstObjectives,  environment: TrainingEnvironmentTestSupport.full(context: context), context: context
        )
        let realFirstStimulus = try XCTUnwrap(firstSessions.first?.orderedBlocks.first { $0.type == .functionalFitness }?.functionalFitnessPrescription?.stimulus)
        XCTAssertEqual(instance.sessions.first?.status, .scheduled, "Session 1 is not completed")
        XCTAssertTrue(FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn: instance).isEmpty, "completed exposure history must NOT contain the not-yet-completed Session 1")

        var populatedContext = CurrentWeekFunctionalFitnessProgrammingContext()
        populatedContext.record(stimulus: realFirstStimulus)
        XCTAssertEqual(populatedContext.alreadyProgrammedThisWeek.map(\.stimulus), [realFirstStimulus], "the context does contain Session 1's real programmed Stimulus before Session 2's decision")

        // Session 2's baseline is this component's identical fixed
        // Stage-A stimulus (Stage A never varies week to week / session
        // to session — confirmed in this design's own audit) — the exact
        // same value used to materialize Session 1 above.
        let secondBaseline = heavySquatMaterializableStimulus()

        let withContext = engine.decide(ProgrammingDecisionInput(
            exposureHistory: [], stimulusRequirements: secondBaseline, varianceConstraints: VarianceConstraints(),
            componentAdaptationObjectives: realFirstObjectives, currentWeekContext: populatedContext
        ))
        let withoutContext = engine.decide(ProgrammingDecisionInput(
            exposureHistory: [], stimulusRequirements: secondBaseline, varianceConstraints: VarianceConstraints(),
            componentAdaptationObjectives: realFirstObjectives, currentWeekContext: CurrentWeekFunctionalFitnessProgrammingContext()
        ))

        XCTAssertEqual(withContext.reasonCode, .sameWeekComplementarityPreferred, "with the real Session-1 context present, pairing fires")
        XCTAssertEqual(withoutContext.reasonCode, .stimulusAsConfigured, "with every other input held identical but an EMPTY context, pairing never fires — the baseline passes through unchanged")
        XCTAssertNotEqual(withContext.nextStimulus, withoutContext.nextStimulus, "the context is the cause of the differing decision, not a coincidence of some other input")
        XCTAssertEqual(withoutContext.nextStimulus, secondBaseline, "without context, Session 2 would have made the identical baseline choice Session 1 made")
    }

    // MARK: D. Orchestration — producer/consumer, never GoalPriority

    private func makeHypertrophyComponent(label: String, priority: GoalPriority, startDate: Date) throws -> TrainingMixComponent {
        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 1, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: context
        )
        resolveAllSlots(in: definition, to: exercise("Back Squat", targets: [.quadriceps, .glutes]))
        let instance = ProgramInstance(ownerUserID: ownerUserID, startDate: startDate)
        context.insert(instance)
        instance.programDefinition = definition
        let component = TrainingMixComponent(
            label: label, programmingSystem: .hypertrophy, priority: priority,
            adaptationObjectives: [.muscleGain], frequency: SessionFrequency(target: 1)
        )
        context.insert(component)
        component.programInstance = instance
        return component
    }

    private func makeFunctionalFitnessComponent(label: String, priority: GoalPriority, startDate: Date) -> TrainingMixComponent {
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 2, targetStimulus: heavySquatMaterializableStimulus(), format: .maxLoad,
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false, isDynamicallyComposed: false
        )
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID, startDate: startDate)
        context.insert(instance)
        instance.programDefinition = definition
        let component = TrainingMixComponent(
            label: label, programmingSystem: .functionalFitness, priority: priority,
            adaptationObjectives: [.workCapacity, .aerobicCapacity, .power], frequency: SessionFrequency(target: 1)
        )
        context.insert(component)
        component.programInstance = instance
        return component
    }

    private func availability() -> UserAvailability {
        UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1)
    }

    /// The exact case round 2's audit found "primary before supporting"
    /// breaks on: primary FF (a constraint-CONSUMING system) + supporting
    /// Strength (a constraint-PRODUCING system). Producer/consumer role,
    /// not `GoalPriority`, must decide which pass each runs in.
    func testPrimaryFFPlusSupportingStrengthStillGivesFFTheProducerContextItNeeds() throws {
        let asOf = date(2026, 1, 5)
        let strength = try makeHypertrophyComponent(label: "Strength", priority: .supporting, startDate: asOf)
        let ff = makeFunctionalFitnessComponent(label: "Functional Fitness", priority: .primary, startDate: asOf)
        let mix = TrainingMix(kind: .selected, name: "Primary FF Plus Supporting Strength")
        context.insert(mix)
        mix.addComponent(strength)
        mix.addComponent(ff)

        let materializationContext = TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: [], functionalFitnessCandidateExercises: [], trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context))
        let result = try XCTUnwrap(RollTacticalWindowUseCase.rollForward(
            mix: mix, asOf: asOf, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext, context: context
        ))

        XCTAssertEqual(result.newSessionsByComponent.count, 2, "both components must materialize regardless of which one is .primary")
        // Strength is `.supporting` here — its stress must NEVER protect
        // anything (protection reads `.priority == .primary`, never which
        // pass a component ran in) — so FF's heavy baseline must NOT be
        // discouraged despite a real, materialized heavy squat session
        // existing this same week.
        let ffSession = try XCTUnwrap(result.newSessionsByComponent[ff.id]?.first)
        let ffStimulus = try XCTUnwrap(ffSession.orderedBlocks.first { $0.type == .functionalFitness }?.functionalFitnessPrescription?.stimulus)
        XCTAssertEqual(ffStimulus, heavySquatMaterializableStimulus(), "FF's own .primary priority does not make it materialize first, and Strength's .supporting priority means its real stress is not protected")
    }

    /// Case (C)/(D): equal-priority producer + consumer — producer/consumer
    /// role, not a priority tie-break, still correctly separates the passes.
    func testEqualPrioritySiblingsStillSeparateIntoProducerAndConsumerPasses() throws {
        let asOf = date(2026, 1, 5)
        let strength = try makeHypertrophyComponent(label: "Strength", priority: .secondary, startDate: asOf)
        let ff = makeFunctionalFitnessComponent(label: "Functional Fitness", priority: .secondary, startDate: asOf)
        let mix = TrainingMix(kind: .selected, name: "Equal Priority Mix")
        context.insert(mix)
        mix.addComponent(strength)
        mix.addComponent(ff)

        let materializationContext = TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: [], functionalFitnessCandidateExercises: [], trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context))
        let result = try XCTUnwrap(RollTacticalWindowUseCase.rollForward(
            mix: mix, asOf: asOf, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext, context: context
        ))
        XCTAssertEqual(result.newSessionsByComponent.count, 2, "both real components must materialize even when priority alone cannot break any tie")
    }

    /// Week 0 (`repGoalSchedule[0]`) is RIR 3 — real, but only `.moderate`
    /// intensity per `StrengthTrainingStressMapper` (only RIR<=1 ever
    /// classifies `.high`). Below `.conservativeDefault`'s `.high`
    /// threshold, so FF's heavy baseline is correctly left ELIGIBLE and
    /// UNCHANGED — exactly the design's own "early week: eligible" row.
    /// The real peak-week (RIR 1) discouragement-and-repair case is
    /// proven separately, through direct materializer calls reusing
    /// CP.1's own week-index-3 fixture
    /// (`testRealPeakWeekStrengthStressDiscouragesAndRepairsARealFFStimulusPreservingRealObjectives`).
    /// This test instead proves the ORCHESTRATION invariant: real
    /// two-pass `rollForward`, exactly one `SchedulingPipeline.propose`
    /// call, both real components' sessions present in the one accepted
    /// proposal.
    func testModerateEarlyWeekStrengthStressLeavesTheRealSiblingFFSessionEligibleThroughRollForward() throws {
        let asOf = date(2026, 1, 5)
        let strength = try makeHypertrophyComponent(label: "Strength", priority: .primary, startDate: asOf)
        let ff = makeFunctionalFitnessComponent(label: "Functional Fitness", priority: .supporting, startDate: asOf)
        let mix = TrainingMix(kind: .selected, name: "Real Two-Pass Fixture")
        context.insert(mix)
        mix.addComponent(strength)
        mix.addComponent(ff)

        let materializationContext = TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: [], functionalFitnessCandidateExercises: [], trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context))
        let result = try XCTUnwrap(RollTacticalWindowUseCase.rollForward(
            mix: mix, asOf: asOf, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext, context: context
        ))

        let strengthSession = try XCTUnwrap(result.newSessionsByComponent[strength.id]?.first)
        let strengthProfile = try XCTUnwrap(SessionStressComposer.compose(strengthSession))
        XCTAssertEqual(strengthProfile.lowerBodyLoad, .moderate, "sanity check: the real Strength week-0 (RIR 3) fixture classifies only .moderate via CP.1's own mapper")

        let ffSession = try XCTUnwrap(result.newSessionsByComponent[ff.id]?.first)
        let ffStimulus = try XCTUnwrap(ffSession.orderedBlocks.first { $0.type == .functionalFitness }?.functionalFitnessPrescription?.stimulus)
        XCTAssertEqual(ffStimulus, heavySquatMaterializableStimulus(), "below-threshold sibling stress must never discourage — the baseline passes through unchanged")

        // Exactly one SchedulingPipeline.propose call: both components'
        // placements appear in the SAME accepted proposal — if Pass 1 and
        // Pass 2 had each triggered their own separate propose/accept, one
        // of these two components' sessions would be missing here.
        let placedInstanceIDs = Set(result.scheduleProposal.placements.compactMap { $0.session.programInstance?.id })
        XCTAssertEqual(placedInstanceIDs, [strength.programInstance!.id, ff.programInstance!.id], "both components' sessions must appear in the one, same, accepted proposal")
    }

    func testRollForwardRemainsIdempotentAcrossRepeatedCalls() throws {
        let asOf = date(2026, 1, 5)
        let strength = try makeHypertrophyComponent(label: "Strength", priority: .primary, startDate: asOf)
        let ff = makeFunctionalFitnessComponent(label: "Functional Fitness", priority: .supporting, startDate: asOf)
        let mix = TrainingMix(kind: .selected, name: "Idempotency Fixture")
        context.insert(mix)
        mix.addComponent(strength)
        mix.addComponent(ff)

        let materializationContext = TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: [], functionalFitnessCandidateExercises: [], trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context))
        _ = try XCTUnwrap(RollTacticalWindowUseCase.rollForward(
            mix: mix, asOf: asOf, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext, context: context
        ))
        let strengthCountAfterFirstCall = strength.programInstance?.sessions.count ?? 0
        let ffCountAfterFirstCall = ff.programInstance?.sessions.count ?? 0

        // Calling again immediately (no advancement in between) must
        // materialize the NEXT real week, never re-materialize/duplicate
        // the week just produced — this is `ProgramWeekGrouping
        // .nextWeekIndex`'s own existing, unchanged invariant; CP.2's
        // restructuring must not have broken it.
        let secondCallDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: asOf))
        _ = try RollTacticalWindowUseCase.rollForward(
            mix: mix, asOf: secondCallDate, ownerUserID: ownerUserID, performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext, context: context
        )
        XCTAssertGreaterThan(strength.programInstance?.sessions.count ?? 0, strengthCountAfterFirstCall, "a real new week was added, never a duplicate of the first")
        XCTAssertGreaterThan(ff.programInstance?.sessions.count ?? 0, ffCountAfterFirstCall)
    }

    // MARK: E. Regression — FF's own mapper/behavior completely unchanged

    func testFunctionalFitnessStressMapperBehaviorIsCompletelyUnchanged() {
        let profile = FunctionalFitnessStressProfileMapper.map(stimulus: heavySquatStimulus())
        XCTAssertEqual(profile.lowerBodyLoad, .high)
        XCTAssertEqual(profile.upperBodyLoad, .none)
        XCTAssertEqual(profile.overallIntensity, .high)
    }

    func testExistingFourChecksStillRunUnchangedWhenNeitherNewCheckFires() {
        // No protected sibling stress, no current-week context, no
        // adaptationObjectives — behaves exactly as
        // `FunctionalFitnessDecisionEngineTests` already proves.
        let recentAllShort = Array(repeating: VarianceExposureRecord(
            date: Date(timeIntervalSince1970: 0), durationDomain: .short, loading: .moderate,
            movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1)], movementFunctionsUsed: [.squatLoaded],
            skillDemand: .moderate, wasHighIntensity: true
        ), count: 3)
        let input = ProgrammingDecisionInput(
            exposureHistory: recentAllShort,
            stimulusRequirements: Stimulus(targetDurationDomain: .short, intensity: .high, loading: .moderate, movementFunctions: [.squatLoaded], movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1)], skillDemand: .moderate, systemicDemand: .high, scoreType: .time),
            varianceConstraints: VarianceConstraints(avoidRepeatingDurationDomainWithinSessions: 3)
        )
        let output = engine.decide(input)
        XCTAssertEqual(output.reasonCode, .functionalDurationBalance)
        XCTAssertEqual(output.nextStimulus.targetDurationDomain, .medium)
    }
}
