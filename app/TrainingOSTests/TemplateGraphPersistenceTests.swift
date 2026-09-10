import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 4: create -> save -> fresh ModelContext -> fetch -> semantic
/// equality, for the new persisted template graph
/// (`ProgramDefinition -> TrainingWeek -> TemplateSession ->
/// WorkoutBlockTemplate -> PrescriptionTemplate -> ExerciseSlot`) and
/// every new `Codable` value type stored on it. Written before any
/// generator/rule-engine logic, per the explicit Stage 4 instruction not
/// to assume a Codable type is persistence-safe — the Stage 3C
/// `ClosedRange` crash is exactly the failure mode this file exists to
/// catch early.
@MainActor
final class TemplateGraphPersistenceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func freshContext() -> ModelContext {
        ModelContext(container)
    }

    /// Builds one representative template graph exercising every rule
    /// variant at once: a "Horizontal Push" slot with `rmBased` load +
    /// `autoregulated` sets, paired to a "Chest Isolation or Triceps" slot
    /// whose load is `linkedToPairedSlot` back to the first — the exact
    /// authoring-time self-reference shape decision A5 requires.
    private func buildTemplateGraph() -> (definition: ProgramDefinition, primarySlotID: UUID, pairedSlotID: UUID) {
        let definition = ProgramDefinition(
            name: "4-Day Full Body Hypertrophy — Basic Hypertrophy",
            lengthWeeks: 5,
            intent: "Basic Hypertrophy, 4-day full body",
            programmingSystem: .hypertrophy,
            generatorVersion: 1,
            provenance: .constructed(reason: "No source workbook exists in this repository; rules transcribed from PROGRAM_LOGIC_SPEC.md."),
            hypertrophyConfiguration: HypertrophyProgramConfiguration(dayCount: 4, split: .fullBody, phaseType: .basicHypertrophy)
        )
        context.insert(definition)

        let week1 = TrainingWeek(isDeload: false)
        context.insert(week1)
        definition.addWeek(week1)

        let session = TemplateSession(name: "Push Day", role: .hypertrophy)
        context.insert(session)
        definition.addTemplateSession(session)

        let block = WorkoutBlockTemplate(type: .hypertrophy)
        context.insert(block)
        session.addBlockTemplate(block)

        let primaryID = UUID()
        let primary = PrescriptionTemplate(
            id: primaryID,
            rules: StrengthProgressionRules(
                loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.85, laterWeekMultipliers: [1.05, 1.075, 1.1])),
                setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 3)),
                repGoalSchedule: [
                    RepGoal.rir(3),
                    RepGoal.rir(3),
                    RepGoal.rir(2),
                    RepGoal.rir(1)
                ],
                deloadWeightAction: .standard,
                deloadRepAction: .standard
            )
        )
        context.insert(primary)
        block.addPrescriptionTemplate(primary)

        let primarySlot = ExerciseSlot(name: "Horizontal Push", allowedTargets: [.chest, .shoulders])
        context.insert(primarySlot)
        primary.attachExerciseSlot(primarySlot)

        let pairedID = UUID()
        let paired = PrescriptionTemplate(
            id: pairedID,
            rules: StrengthProgressionRules(
                loadRule: .linkedToPairedSlot(fractionOfSourceResult: 0.6),
                setCountRule: .fixed(setsByWeek: [2, 2, 2, 2]),
                repGoalSchedule: [
                    RepGoal.fixedReps(12),
                    RepGoal.fixedReps(12),
                    RepGoal.fixedReps(12),
                    RepGoal.fixedReps(12)
                ],
                deloadWeightAction: .omit,
                deloadRepAction: .omit
            )
        )
        context.insert(paired)
        block.addPrescriptionTemplate(paired)
        paired.pairedSlot = primary

        let pairedSlot = ExerciseSlot(name: "Chest Isolation or Triceps", allowedTargets: [.chest, .triceps])
        context.insert(pairedSlot)
        paired.attachExerciseSlot(pairedSlot)

        return (definition, primaryID, pairedID)
    }

    func testFullTemplateGraphSurvivesRoundTrip() throws {
        let (definition, primaryID, pairedID) = buildTemplateGraph()
        let definitionID = definition.id
        try context.save()

        let reloadedDefinition = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<ProgramDefinition>(predicate: #Predicate { $0.id == definitionID })).first
        )
        XCTAssertEqual(reloadedDefinition.programmingSystem, .hypertrophy)
        XCTAssertEqual(reloadedDefinition.generatorVersion, 1)
        XCTAssertEqual(reloadedDefinition.provenance, .constructed(reason: "No source workbook exists in this repository; rules transcribed from PROGRAM_LOGIC_SPEC.md."))
        XCTAssertEqual(reloadedDefinition.hypertrophyConfiguration, HypertrophyProgramConfiguration(dayCount: 4, split: .fullBody, phaseType: .basicHypertrophy))

        let week = try XCTUnwrap(reloadedDefinition.orderedWeeks.first)
        XCTAssertFalse(week.isDeload)
        let session = try XCTUnwrap(reloadedDefinition.orderedTemplateSessions.first)
        XCTAssertEqual(session.name, "Push Day")
        XCTAssertEqual(session.role, .hypertrophy)
        let block = try XCTUnwrap(session.orderedBlockTemplates.first)
        XCTAssertEqual(block.type, .hypertrophy)
        XCTAssertEqual(block.orderedPrescriptionTemplates.count, 2)

        let reloadedPrimary = try XCTUnwrap(block.orderedPrescriptionTemplates.first { $0.id == primaryID })
        XCTAssertEqual(reloadedPrimary.rules?.loadRule, .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.85, laterWeekMultipliers: [1.05, 1.075, 1.1])))
        XCTAssertEqual(reloadedPrimary.rules?.setCountRule, .autoregulated(AutoregulatedSetCount(baselineSets: 3)))
        XCTAssertEqual(reloadedPrimary.rules?.repGoalSchedule, [
            RepGoal.rir(3), RepGoal.rir(3),
            RepGoal.rir(2), RepGoal.rir(1)
        ])
        XCTAssertEqual(reloadedPrimary.exerciseSlot?.name, "Horizontal Push")
        XCTAssertEqual(reloadedPrimary.exerciseSlot?.allowedTargets, [.chest, .shoulders])

        let reloadedPaired = try XCTUnwrap(block.orderedPrescriptionTemplates.first { $0.id == pairedID })
        XCTAssertEqual(reloadedPaired.rules?.loadRule, .linkedToPairedSlot(fractionOfSourceResult: 0.6))
        XCTAssertEqual(reloadedPaired.rules?.deloadWeightAction, .omit)
        XCTAssertEqual(reloadedPaired.pairedSlot?.id, primaryID)
        XCTAssertEqual(reloadedPaired.exerciseSlot?.name, "Chest Isolation or Triceps")
        XCTAssertEqual(reloadedPaired.exerciseSlot?.allowedTargets, [.chest, .triceps])
    }

    /// The `sourced` provenance case, specifically — proves the
    /// associated-String enum case round-trips distinctly from
    /// `.constructed`, not just that *a* provenance survives.
    func testSourcedProvenanceSurvivesRoundTrip() throws {
        let definitionID = UUID()
        let definition = ProgramDefinition(
            id: definitionID,
            name: "Sourced fixture",
            lengthWeeks: 1,
            provenance: .sourced(file: "e1f8fb19-RPHypertrophy4Day.xlsx", sheet: "Week 1", cell: "J11")
        )
        context.insert(definition)
        try context.save()

        let reloaded = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<ProgramDefinition>(predicate: #Predicate { $0.id == definitionID })).first
        )
        XCTAssertEqual(reloaded.provenance, .sourced(file: "e1f8fb19-RPHypertrophy4Day.xlsx", sheet: "Week 1", cell: "J11"))
    }

    /// `LoadRule.none` and a deload `TrainingWeek` marker — the "no
    /// progression" and "isDeload" legal states, not exercised by the main
    /// graph test. The deload week is a marker only (see `TrainingWeek`'s
    /// doc comment) — it doesn't hold its own copy of the session
    /// structure, so this test attaches the session to the
    /// `ProgramDefinition` directly and checks the deload marker
    /// separately.
    func testNoLoadRuleAndDeloadWeekSurviveRoundTrip() throws {
        let definitionID = UUID()
        let definition = ProgramDefinition(id: definitionID, name: "Minimal", lengthWeeks: 1)
        context.insert(definition)
        let deloadWeek = TrainingWeek(isDeload: true)
        context.insert(deloadWeek)
        definition.addWeek(deloadWeek)

        let templateID = UUID()
        let template = PrescriptionTemplate(
            id: templateID,
            rules: StrengthProgressionRules(loadRule: .none, setCountRule: .fixed(setsByWeek: [2]), repGoalSchedule: [RepGoal.fixedReps(15)])
        )
        context.insert(template)
        let session = TemplateSession(name: "Day 1")
        context.insert(session)
        definition.addTemplateSession(session)
        let block = WorkoutBlockTemplate(type: .accessory)
        context.insert(block)
        session.addBlockTemplate(block)
        block.addPrescriptionTemplate(template)
        try context.save()

        let reloaded = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<PrescriptionTemplate>(predicate: #Predicate { $0.id == templateID })).first
        )
        // `LoadRule.none` explicitly, not bare `.none` — against a
        // `LoadRule?` expected type, `.none` resolves to `Optional.none`
        // (nil), not `Optional(LoadRule.none)`, and would silently assert
        // the wrong thing.
        XCTAssertEqual(reloaded.rules?.loadRule, LoadRule.none)

        let reloadedDefinition = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<ProgramDefinition>(predicate: #Predicate { $0.id == definitionID })).first
        )
        XCTAssertTrue(reloadedDefinition.orderedWeeks.first?.isDeload ?? false)
    }

    /// `ExerciseSlot.resolvedExercise` and `allowedExercises` — the
    /// concrete-exercise-selection half of decision A6.
    func testExerciseSlotResolutionSurvivesRoundTrip() throws {
        let benchPress = Exercise(canonicalName: "Barbell Bench Press", modality: .strength, equipment: "barbell", movementPattern: "horizontal push")
        let dbPress = Exercise(canonicalName: "Dumbbell Bench Press", modality: .strength, equipment: "dumbbell", movementPattern: "horizontal push")
        context.insert(benchPress)
        context.insert(dbPress)

        let slotID = UUID()
        let slot = ExerciseSlot(
            id: slotID,
            name: "Horizontal Push",
            allowedTargets: [.chest],
            allowedExercises: [benchPress, dbPress],
            resolvedExercise: benchPress
        )
        context.insert(slot)
        try context.save()

        let reloaded = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<ExerciseSlot>(predicate: #Predicate { $0.id == slotID })).first
        )
        XCTAssertEqual(reloaded.resolvedExercise?.canonicalName, "Barbell Bench Press")
        XCTAssertEqual(Set(reloaded.allowedExercises.map(\.canonicalName)), ["Barbell Bench Press", "Dumbbell Bench Press"])
    }

    /// Deleting a `PrescriptionTemplate` referenced by another as
    /// `pairedSlot` must nullify cleanly, not crash — this is exactly the
    /// un-inversed-to-one failure mode Stage 2 found (see
    /// `referencedAsPairedSlotBy`'s doc comment). Exercised directly since
    /// nothing else in this file deletes a paired slot.
    func testDeletingPairedSlotNullifiesRatherThanCrashing() throws {
        let (definition, primaryID, pairedID) = buildTemplateGraph()
        try context.save()

        let primary = try XCTUnwrap(
            context.fetch(FetchDescriptor<PrescriptionTemplate>(predicate: #Predicate { $0.id == primaryID })).first
        )
        context.delete(primary)
        try context.save()

        let survivingPaired = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<PrescriptionTemplate>(predicate: #Predicate { $0.id == pairedID })).first
        )
        XCTAssertNil(survivingPaired.pairedSlot, "Deleting the referenced slot should nullify the pointer, not crash and not delete the referencing slot.")
        XCTAssertNotNil(survivingPaired.rules, "The referencing PrescriptionTemplate itself must survive.")

        // The rest of the graph (definition, week, session, block) is
        // untouched by deleting one of its two prescription templates.
        _ = definition
    }

    /// DIAGNOSTIC — isolates whether the trigger is "two
    /// `PrescriptionTemplate` rows in the same store with *different*
    /// `LoadRule` cases" versus something about the `pairedSlot`
    /// relationship itself. Minimal: two rows, no `pairedSlot`, no
    /// `setCountRule`/`repGoalSchedule` variation, differing only in
    /// `loadRule`'s case.
    func testDiagnosticTwoSiblingRowsWithDifferentLoadRuleCases() throws {
        let firstID = UUID()
        let first = PrescriptionTemplate(id: firstID, rules: StrengthProgressionRules(
            loadRule: .none, setCountRule: .fixed(setsByWeek: [3]), repGoalSchedule: [RepGoal.fixedReps(10)]
        ))
        context.insert(first)

        let secondID = UUID()
        let second = PrescriptionTemplate(id: secondID, rules: StrengthProgressionRules(
            loadRule: .linkedToPairedSlot(fractionOfSourceResult: 0.6), setCountRule: .fixed(setsByWeek: [3]), repGoalSchedule: [RepGoal.fixedReps(10)]
        ))
        context.insert(second)
        try context.save()

        let reloadedFirst = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<PrescriptionTemplate>(predicate: #Predicate { $0.id == firstID })).first
        )
        let reloadedSecond = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<PrescriptionTemplate>(predicate: #Predicate { $0.id == secondID })).first
        )
        XCTAssertEqual(reloadedFirst.rules?.loadRule, LoadRule.none)
        XCTAssertEqual(reloadedSecond.rules?.loadRule, .linkedToPairedSlot(fractionOfSourceResult: 0.6))
    }

    /// DIAGNOSTIC — checks whether the same "second sibling row's
    /// enum-with-payload case decodes as nil" bug affects *pre-existing,
    /// already-Xcode-validated* Stage 3C code (`SteadyStatePrescription.
    /// primaryIntensity: IntensityTarget?`), not just this file's new
    /// types. Stage 3C's round-trip test only ever created ONE row with a
    /// non-trivial `IntensityTarget` case per container, so it could not
    /// have caught this.
    func testDiagnosticTwoSiblingSteadyStatePrescriptionsWithDifferentIntensityTargetCases() throws {
        let firstID = UUID()
        let first = SteadyStatePrescription(id: firstID, activityType: .running, primaryIntensity: .heartRateZone(.two))
        context.insert(first)

        let secondID = UUID()
        let second = SteadyStatePrescription(id: secondID, activityType: .cycling, primaryIntensity: .powerZone(.three))
        context.insert(second)
        try context.save()

        let reloadedFirst = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<SteadyStatePrescription>(predicate: #Predicate { $0.id == firstID })).first
        )
        let reloadedSecond = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<SteadyStatePrescription>(predicate: #Predicate { $0.id == secondID })).first
        )
        XCTAssertEqual(reloadedFirst.primaryIntensity, .heartRateZone(.two))
        XCTAssertEqual(reloadedSecond.primaryIntensity, .powerZone(.three))
    }

    /// DIAGNOSTIC — isolates whether the trigger is specifically a
    /// zero-associated-value case (`.none`) sharing a store with a
    /// non-empty case of the same enum, versus "any two different cases."
    /// Both rows here use a non-empty `LoadRule` case.
    func testDiagnosticTwoSiblingRowsWithDifferentNonEmptyLoadRuleCases() throws {
        let firstID = UUID()
        let first = PrescriptionTemplate(id: firstID, rules: StrengthProgressionRules(
            loadRule: .linkedToPairedSlot(fractionOfSourceResult: 0.5), setCountRule: .fixed(setsByWeek: [3]), repGoalSchedule: [RepGoal.fixedReps(10)]
        ))
        context.insert(first)

        let secondID = UUID()
        let second = PrescriptionTemplate(id: secondID, rules: StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.85, laterWeekMultipliers: [1.05])), setCountRule: .fixed(setsByWeek: [3]), repGoalSchedule: [RepGoal.fixedReps(10)]
        ))
        context.insert(second)
        try context.save()

        let reloadedFirst = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<PrescriptionTemplate>(predicate: #Predicate { $0.id == firstID })).first
        )
        let reloadedSecond = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<PrescriptionTemplate>(predicate: #Predicate { $0.id == secondID })).first
        )
        XCTAssertEqual(reloadedFirst.rules?.loadRule, .linkedToPairedSlot(fractionOfSourceResult: 0.5))
        XCTAssertEqual(reloadedSecond.rules?.loadRule, .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.85, laterWeekMultipliers: [1.05])))
    }

    /// Stage 4B additions: `AutoregulatedSetCount`'s 2 new fields
    /// (`applyRatingOnFinalWeek`/`freezeAfterWeek`) and the 2 new
    /// `DeloadPositionOverride?` struct fields — none of these are
    /// exercised by any Stage 4A fixture (all default/nil there), so this
    /// is the first round-trip proof they persist correctly before
    /// `PowerliftingProgramGenerator` relies on them. Two sibling rows
    /// with *different* override values, per this file's own established
    /// diagnostic discipline for anything added to `PrescriptionTemplate`.
    func testStageFourBDeloadOverridesAndAutoregulationExtensionsSurviveRoundTrip() throws {
        let familyBID = UUID()
        let familyBTemplate = PrescriptionTemplate(id: familyBID, rules: StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm5, weekOneFactor: 0.7, laterWeekMultipliers: [1.05, 1.075, 1.1])),
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 3, applyRatingOnFinalWeek: false)),
            repGoalSchedule: [RepGoal.rir(3)],
            deloadRepPositionOverride: DeloadPositionOverride(boundaryDayIndex: 2, fullPositionFactor: 2.0 / 3.0, halfPositionFactor: 0.5),
            deloadWeightPositionOverride: DeloadPositionOverride(boundaryDayIndex: 2, fullPositionFactor: 0.7, halfPositionFactor: 0.5)
        ))
        context.insert(familyBTemplate)

        let familyCID = UUID()
        let familyCTemplate = PrescriptionTemplate(id: familyCID, rules: StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.95, laterWeekMultipliers: [1.05, 1.075, 1.1])),
            setCountRule: .autoregulated(AutoregulatedSetCount(baselineSets: 2, freezeAfterWeek: 2)),
            repGoalSchedule: [RepGoal.rir(8)],
            deloadWeightPositionOverride: DeloadPositionOverride(boundaryDayIndex: 2, fullPositionFactor: 1.0, halfPositionFactor: 0.5)
        ))
        context.insert(familyCTemplate)
        try context.save()

        let reloadedB = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<PrescriptionTemplate>(predicate: #Predicate { $0.id == familyBID })).first
        )
        guard case .autoregulated(let bConfig) = try XCTUnwrap(reloadedB.rules?.setCountRule) else {
            return XCTFail("expected .autoregulated")
        }
        XCTAssertEqual(bConfig.applyRatingOnFinalWeek, false)
        XCTAssertNil(bConfig.freezeAfterWeek)
        XCTAssertEqual(reloadedB.rules?.deloadRepPositionOverride, DeloadPositionOverride(boundaryDayIndex: 2, fullPositionFactor: 2.0 / 3.0, halfPositionFactor: 0.5))
        XCTAssertEqual(reloadedB.rules?.deloadWeightPositionOverride, DeloadPositionOverride(boundaryDayIndex: 2, fullPositionFactor: 0.7, halfPositionFactor: 0.5))

        let reloadedC = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<PrescriptionTemplate>(predicate: #Predicate { $0.id == familyCID })).first
        )
        guard case .autoregulated(let cConfig) = try XCTUnwrap(reloadedC.rules?.setCountRule) else {
            return XCTFail("expected .autoregulated")
        }
        XCTAssertEqual(cConfig.applyRatingOnFinalWeek, true)
        XCTAssertEqual(cConfig.freezeAfterWeek, 2)
        XCTAssertNil(reloadedC.rules?.deloadRepPositionOverride)
        XCTAssertEqual(reloadedC.rules?.deloadWeightPositionOverride, DeloadPositionOverride(boundaryDayIndex: 2, fullPositionFactor: 1.0, halfPositionFactor: 0.5))
    }

    /// FF Multi-Week V1: `FunctionalFitnessProgramConfiguration.weeklyPlan`
    /// is a NEW persistence shape — an array of `FunctionalFitnessSessionIntent`,
    /// each itself containing a `Stimulus` (which contains
    /// `[MovementFunction]`/`[ModalityCount]`) and a `VarianceConstraints`.
    /// Not assumed safe merely because `Stimulus`/`VarianceConstraints`
    /// individually already round-trip as direct top-level properties —
    /// wrapping them inside another struct, inside an array, is a
    /// genuinely different shape, exactly the discipline this file's own
    /// doc comment requires testing before relying on it.
    func testFunctionalFitnessWeeklyPlanSurvivesRoundTrip() throws {
        let definitionID = UUID()
        let intents = FunctionalFitnessAuthoredProgramLibrary.twoSessionsPerWeek
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 2, lengthWeeks: 4,
            targetStimulus: intents[0].stimulus, format: intents[0].format, sessionRole: .functionalFitness,
            varianceConstraints: VarianceConstraints(), requiresRecentExposureToProgress: false,
            includeStrengthBlock: false, weeklyPlan: intents
        )
        let definition = ProgramDefinition(
            id: definitionID, name: "FF Weekly Plan Round Trip", lengthWeeks: 4, intent: "test",
            programmingSystem: .functionalFitness, provenance: .constructed(reason: "test"),
            functionalFitnessConfiguration: configuration
        )
        context.insert(definition)
        try context.save()

        let reloaded = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<ProgramDefinition>(predicate: #Predicate { $0.id == definitionID })).first
        )
        let reloadedPlan = try XCTUnwrap(reloaded.functionalFitnessConfiguration?.weeklyPlan)
        XCTAssertEqual(reloadedPlan.count, intents.count)
        XCTAssertEqual(reloadedPlan, intents, "every field of every intent — including nested Stimulus/VarianceConstraints — must survive exactly")
    }

    /// Minimal reproduction: TWO sibling `FunctionalFitnessPrescriptionTemplate`
    /// rows in the SAME store, holding two DIFFERENT `WorkoutFormat` cases
    /// (`.amrap` vs `.maxLoad`) — isolates whether multiple distinct
    /// `WorkoutFormat` enum cases coexisting as sibling rows is itself
    /// the crash trigger, independent of `weeklyPlan`/`FunctionalFitnessSessionIntent`.
    func testTwoSiblingFunctionalFitnessTemplatesWithDifferentWorkoutFormatCasesSurviveRoundTrip() throws {
        let idA = UUID()
        let idB = UUID()
        let templateA = FunctionalFitnessPrescriptionTemplate(
            id: idA,
            stimulus: Stimulus(targetDurationDomain: .short, intensity: .high, loading: .light, movementFunctions: [.monostructural], movementModalityMix: [ModalityCount(modality: .metabolicConditioning, count: 1)], skillDemand: .low, systemicDemand: .high, scoreType: .roundsAndReps),
            format: .amrap(capSeconds: 240)
        )
        context.insert(templateA)
        let templateB = FunctionalFitnessPrescriptionTemplate(
            id: idB,
            stimulus: Stimulus(targetDurationDomain: .medium, intensity: .moderate, loading: .heavy, movementFunctions: [.squatLoaded], movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1)], skillDemand: .low, systemicDemand: .low, scoreType: .load),
            format: .maxLoad
        )
        context.insert(templateB)
        let idC = UUID()
        let templateC = FunctionalFitnessPrescriptionTemplate(
            id: idC,
            stimulus: Stimulus(targetDurationDomain: .medium, intensity: .moderate, loading: .moderate, movementFunctions: [.monostructural], movementModalityMix: [ModalityCount(modality: .metabolicConditioning, count: 1)], skillDemand: .moderate, systemicDemand: .moderate, scoreType: .completedIntervals),
            format: .intervals(count: 4, workSeconds: 120, restSeconds: 60)
        )
        context.insert(templateC)
        try context.save()

        let fresh = freshContext()
        let reloadedA = try XCTUnwrap(fresh.fetch(FetchDescriptor<FunctionalFitnessPrescriptionTemplate>(predicate: #Predicate { $0.id == idA })).first)
        let reloadedB = try XCTUnwrap(fresh.fetch(FetchDescriptor<FunctionalFitnessPrescriptionTemplate>(predicate: #Predicate { $0.id == idB })).first)
        let reloadedC = try XCTUnwrap(fresh.fetch(FetchDescriptor<FunctionalFitnessPrescriptionTemplate>(predicate: #Predicate { $0.id == idC })).first)
        XCTAssertEqual(reloadedA.format, .amrap(capSeconds: 240))
        XCTAssertEqual(reloadedB.format, .maxLoad)
        XCTAssertEqual(reloadedC.format, .intervals(count: 4, workSeconds: 120, restSeconds: 60))
    }

    /// Real-scenario reproduction: run the ACTUAL
    /// `FunctionalFitnessProgramGenerator.generate` against the real
    /// `threeSessionsPerWeek` authored plan (12 sibling
    /// `FunctionalFitnessPrescriptionTemplate` rows, 9 distinct
    /// `WorkoutFormat` cases), save, and fetch from a FRESH context —
    /// isolating whether the crash needs the full real generator/graph
    /// shape (`ProgramDefinition` -> `TrainingWeek`/`TemplateSession` ->
    /// `WorkoutBlockTemplate` -> `FunctionalFitnessPrescriptionTemplate`),
    /// not just bare sibling rows.
    func testRealGeneratedThreeSessionsPerWeekPlanSurvivesRoundTrip() throws {
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 2, lengthWeeks: 4,
            targetStimulus: FunctionalFitnessAuthoredProgramLibrary.twoSessionsPerWeek[0].stimulus,
            format: FunctionalFitnessAuthoredProgramLibrary.twoSessionsPerWeek[0].format,
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false,
            weeklyPlan: FunctionalFitnessAuthoredProgramLibrary.twoSessionsPerWeek
        )
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let definitionID = definition.id
        try context.save()

        let fresh = freshContext()
        let reloaded = try XCTUnwrap(fresh.fetch(FetchDescriptor<ProgramDefinition>(predicate: #Predicate { $0.id == definitionID })).first)
        var formatsRead = 0
        for session in reloaded.orderedTemplateSessions {
            for block in session.orderedBlockTemplates {
                if let ffTemplate = block.functionalFitnessPrescriptionTemplate {
                    _ = ffTemplate.format
                    formatsRead += 1
                }
            }
        }
        XCTAssertEqual(formatsRead, 8)
    }

    // MARK: - FF WorkoutFormat SwiftData fix: Step 1 reproduction
    //
    // `ModalityPersistenceRoundTripTests.testBenchmarkDefinitionAndPerformanceProfileSurviveRoundTrip`
    // already proves `.forTime(capSeconds: nil)` round-trips safely in
    // ISOLATION (one row, one case, already in the pre-existing passing
    // suite). The two pre-existing sibling tests above already prove
    // MULTIPLE DIFFERENT cases coexist safely — but neither one includes
    // a `nil`-payload case. This is the one combination never yet tested:
    // multiple sibling rows, differing cases, AT LEAST ONE carrying a
    // `nil` optional payload.

    func testReproduction_SiblingRowsWithOneNilOptionalPayloadCase() throws {
        let idNil = UUID()
        let templateNil = FunctionalFitnessPrescriptionTemplate(
            id: idNil,
            stimulus: Stimulus(targetDurationDomain: .medium, intensity: .moderate, loading: .moderate, movementFunctions: [.squatLoaded], movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1)], skillDemand: .moderate, systemicDemand: .moderate, scoreType: .time),
            format: .roundsForTime(rounds: 5, capSeconds: nil)
        )
        context.insert(templateNil)
        let idOther = UUID()
        let templateOther = FunctionalFitnessPrescriptionTemplate(
            id: idOther,
            stimulus: Stimulus(targetDurationDomain: .short, intensity: .high, loading: .light, movementFunctions: [.monostructural], movementModalityMix: [ModalityCount(modality: .metabolicConditioning, count: 1)], skillDemand: .low, systemicDemand: .high, scoreType: .roundsAndReps),
            format: .amrap(capSeconds: 240)
        )
        context.insert(templateOther)
        let idMaxLoad = UUID()
        let templateMaxLoad = FunctionalFitnessPrescriptionTemplate(
            id: idMaxLoad,
            stimulus: Stimulus(targetDurationDomain: .medium, intensity: .moderate, loading: .heavy, movementFunctions: [.squatLoaded], movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1)], skillDemand: .low, systemicDemand: .low, scoreType: .load),
            format: .maxLoad
        )
        context.insert(templateMaxLoad)
        try context.save()

        let fresh = freshContext()
        let reloadedNil = try XCTUnwrap(fresh.fetch(FetchDescriptor<FunctionalFitnessPrescriptionTemplate>(predicate: #Predicate { $0.id == idNil })).first)
        let reloadedOther = try XCTUnwrap(fresh.fetch(FetchDescriptor<FunctionalFitnessPrescriptionTemplate>(predicate: #Predicate { $0.id == idOther })).first)
        let reloadedMaxLoad = try XCTUnwrap(fresh.fetch(FetchDescriptor<FunctionalFitnessPrescriptionTemplate>(predicate: #Predicate { $0.id == idMaxLoad })).first)
        XCTAssertEqual(reloadedNil.format, .roundsForTime(rounds: 5, capSeconds: nil), "REPRODUCTION TARGET: nil-payload case as a sibling of differing cases")
        XCTAssertEqual(reloadedOther.format, .amrap(capSeconds: 240))
        XCTAssertEqual(reloadedMaxLoad.format, .maxLoad)
    }

    /// Isolates WHICH of the two `@Model` types storing `format` directly
    /// is actually implicated: bare sibling `FunctionalFitnessPrescription`
    /// rows (never `FunctionalFitnessPrescriptionTemplate`, which the test
    /// above already proved safe with the identical mixed+nil shape),
    /// with no `Session`/`Day`/`WorkoutBlock` graph at all.
    func testReproduction_BareSiblingFunctionalFitnessPrescriptionsWithMixedFormatsIncludingNil() throws {
        let stimulus = Stimulus(targetDurationDomain: .medium, intensity: .moderate, loading: .moderate, movementFunctions: [.squatLoaded], movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1)], skillDemand: .low, systemicDemand: .low, scoreType: .time)
        let idNil = UUID()
        let prescriptionNil = FunctionalFitnessPrescription(id: idNil, stimulus: stimulus, format: .roundsForTime(rounds: 5, capSeconds: nil))
        context.insert(prescriptionNil)
        let idOther = UUID()
        let prescriptionOther = FunctionalFitnessPrescription(id: idOther, stimulus: stimulus, format: .amrap(capSeconds: 240))
        context.insert(prescriptionOther)
        try context.save()

        let fresh = freshContext()
        let reloadedNil = try XCTUnwrap(fresh.fetch(FetchDescriptor<FunctionalFitnessPrescription>(predicate: #Predicate { $0.id == idNil })).first)
        let reloadedOther = try XCTUnwrap(fresh.fetch(FetchDescriptor<FunctionalFitnessPrescription>(predicate: #Predicate { $0.id == idOther })).first)
        XCTAssertEqual(reloadedNil.format, .roundsForTime(rounds: 5, capSeconds: nil), "ISOLATION: bare FunctionalFitnessPrescription (not Template) siblings, mixed + nil")
        XCTAssertEqual(reloadedOther.format, .amrap(capSeconds: 240))
    }

    /// Escalation: the previous pass's own appendix specifically says the
    /// crash needed the FULL real materialized multi-week graph, and was
    /// NOT reproduced by isolated round-trips. The two reproductions
    /// above did not crash. The one thing neither tries yet: materializing
    /// several REAL weeks (via `FunctionalFitnessMaterializer.materializeWeek`,
    /// the same call the real dogfood tests use) with GENUINELY DIFFERENT
    /// `WorkoutFormat` cases per week — INCLUDING one `nil`-payload case —
    /// then reading the MATERIALIZED `FunctionalFitnessPrescription.format`
    /// (not the template's) from a FRESH context. The existing
    /// `FunctionalFitnessMultiWeekV1Tests` dogfood/materialization tests
    /// never re-fetch from a fresh context at all — they inspect
    /// `sessions` in the SAME context immediately after materializing —
    /// so they would not catch a decode-boundary bug even if one exists.
    func testReproduction_MultiWeekMaterializedPrescriptionsWithMixedFormatsIncludingNilSurviveFreshFetch() throws {
        let intents: [FunctionalFitnessSessionIntent] = [
            FunctionalFitnessSessionIntent(
                relativeWeek: 0, sessionIndexInWeek: 0,
                stimulus: Stimulus(targetDurationDomain: .medium, intensity: .moderate, loading: .moderate, movementFunctions: [.squatLoaded, .gymnasticsPull, .monostructural], movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1), ModalityCount(modality: .gymnastics, count: 1), ModalityCount(modality: .metabolicConditioning, count: 1)], skillDemand: .moderate, systemicDemand: .moderate, scoreType: .time),
                format: .roundsForTime(rounds: 5, capSeconds: nil), // REPRODUCTION TARGET
                includeStrengthBlock: false, varianceConstraints: VarianceConstraints(), sessionRole: .functionalFitness
            ),
            FunctionalFitnessSessionIntent(
                relativeWeek: 1, sessionIndexInWeek: 0,
                stimulus: Stimulus(targetDurationDomain: .short, intensity: .high, loading: .light, movementFunctions: [.gymnasticsPush, .monostructural], movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1), ModalityCount(modality: .gymnastics, count: 1), ModalityCount(modality: .metabolicConditioning, count: 1)], skillDemand: .moderate, systemicDemand: .high, scoreType: .roundsAndReps),
                format: .amrap(capSeconds: 240),
                includeStrengthBlock: true, varianceConstraints: VarianceConstraints(), sessionRole: .mixed
            ),
            FunctionalFitnessSessionIntent(
                relativeWeek: 2, sessionIndexInWeek: 0,
                stimulus: Stimulus(targetDurationDomain: .long, intensity: .low, loading: .bodyweightOnly, movementFunctions: [.monostructural, .gymnasticsPull], movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1), ModalityCount(modality: .gymnastics, count: 1), ModalityCount(modality: .metabolicConditioning, count: 1)], skillDemand: .low, systemicDemand: .moderate, scoreType: .time),
                format: .forTime(capSeconds: nil), // REPRODUCTION TARGET, second nil case
                includeStrengthBlock: false, varianceConstraints: VarianceConstraints(), sessionRole: .functionalFitness
            ),
            FunctionalFitnessSessionIntent(
                relativeWeek: 3, sessionIndexInWeek: 0,
                stimulus: Stimulus(targetDurationDomain: .medium, intensity: .moderate, loading: .moderate, movementFunctions: [.hingeLoaded, .monostructural], movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1), ModalityCount(modality: .gymnastics, count: 1), ModalityCount(modality: .metabolicConditioning, count: 1)], skillDemand: .moderate, systemicDemand: .moderate, scoreType: .completedIntervals),
                format: .intervals(count: 4, workSeconds: 120, restSeconds: 60),
                includeStrengthBlock: true, varianceConstraints: VarianceConstraints(), sessionRole: .mixed
            ),
        ]
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 4, targetStimulus: intents[0].stimulus, format: intents[0].format,
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false, weeklyPlan: intents
        )
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition
        let instanceID = instance.id
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let candidates = reproductionCandidateExercises()

        for weekIndex in 0..<4 {
            _ = try FunctionalFitnessMaterializer.materializeWeek(
                definition: definition, instance: instance, weekIndex: weekIndex,
                startDate: Calendar.current.date(byAdding: .day, value: weekIndex * 7, to: Date())!,
                ownerUserID: instance.ownerUserID, candidateExercises: candidates, exposureHistory: [],
                environment: environment, context: context
            )
        }
        try context.save()

        let fresh = freshContext()
        let reloadedInstance = try XCTUnwrap(fresh.fetch(FetchDescriptor<ProgramInstance>(predicate: #Predicate { $0.id == instanceID })).first)
        var formatsByWeek: [WorkoutFormat] = []
        for session in reloadedInstance.sessions.sorted(by: { ($0.day?.date ?? .distantPast) < ($1.day?.date ?? .distantPast) }) {
            for block in session.orderedBlocks {
                if let prescription = block.functionalFitnessPrescription {
                    formatsByWeek.append(prescription.format)
                }
            }
        }
        XCTAssertEqual(formatsByWeek.count, 4, "all 4 materialized weeks' prescriptions must be fetchable")
        XCTAssertEqual(formatsByWeek[0], .roundsForTime(rounds: 5, capSeconds: nil), "REPRODUCTION TARGET 1")
        XCTAssertEqual(formatsByWeek[1], .amrap(capSeconds: 240))
        XCTAssertEqual(formatsByWeek[2], .forTime(capSeconds: nil), "REPRODUCTION TARGET 2")
        XCTAssertEqual(formatsByWeek[3], .intervals(count: 4, workSeconds: 120, restSeconds: 60))
    }

    /// Regression matrix: every `WorkoutFormat` case, including both
    /// `nil` and non-`nil` variants of every optional-payload case, and a
    /// representative domain-valid edge value (`capSeconds: 0` — a real,
    /// legitimate value per `FunctionalFitnessStimulusValidator`'s own
    /// range checks, not an arbitrary edge case invented for this test),
    /// all as real materialized `FunctionalFitnessPrescription` rows
    /// across real distinct weeks, read back from a fresh context.
    func testWorkoutFormatFixRegressionMatrixAllCasesAcrossRealMaterializedWeeks() throws {
        func stimulus(_ domain: DurationDomain, _ format: WorkoutFormat) -> Stimulus {
            Stimulus(targetDurationDomain: domain, intensity: .moderate, loading: .moderate, movementFunctions: [.squatLoaded], movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1)], skillDemand: .low, systemicDemand: .low, scoreType: FunctionalFitnessStimulusValidator.defaultScoreType(for: format))
        }
        let matrix: [(WorkoutFormat, DurationDomain)] = [
            (.amrap(capSeconds: 240), .short),
            (.emom(intervalSeconds: 60, totalSeconds: 600), .medium),
            (.forTime(capSeconds: nil), .long),
            (.forTime(capSeconds: 1200), .long),
            (.forTime(capSeconds: 0), .short), // domain-valid edge value
            (.roundsForTime(rounds: 5, capSeconds: nil), .medium),
            (.roundsForTime(rounds: 5, capSeconds: 600), .medium),
            (.chipper(capSeconds: nil), .long),
            (.chipper(capSeconds: 1500), .long),
            (.ladder(direction: .ascending, capSeconds: nil), .medium),
            (.ladder(direction: .descending, capSeconds: 600), .medium),
            (.maxLoad, .short),
            (.maxReps(capSeconds: 120), .short),
            (.intervals(count: 4, workSeconds: 120, restSeconds: 60), .medium),
        ]
        let intents: [FunctionalFitnessSessionIntent] = matrix.enumerated().map { index, entry in
            FunctionalFitnessSessionIntent(
                relativeWeek: index, sessionIndexInWeek: 0, stimulus: stimulus(entry.1, entry.0), format: entry.0,
                includeStrengthBlock: false, varianceConstraints: VarianceConstraints(), sessionRole: .functionalFitness
            )
        }
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: matrix.count, targetStimulus: intents[0].stimulus, format: intents[0].format,
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false, weeklyPlan: intents
        )
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition
        let instanceID = instance.id
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let candidates = reproductionCandidateExercises()

        for weekIndex in 0..<matrix.count {
            _ = try FunctionalFitnessMaterializer.materializeWeek(
                definition: definition, instance: instance, weekIndex: weekIndex,
                startDate: Calendar.current.date(byAdding: .day, value: weekIndex * 7, to: Date())!,
                ownerUserID: instance.ownerUserID, candidateExercises: candidates, exposureHistory: [],
                environment: environment, context: context
            )
        }
        try context.save()

        let fresh = freshContext()
        let reloadedInstance = try XCTUnwrap(fresh.fetch(FetchDescriptor<ProgramInstance>(predicate: #Predicate { $0.id == instanceID })).first)
        let sortedSessions = reloadedInstance.sessions.sorted { ($0.day?.date ?? .distantPast) < ($1.day?.date ?? .distantPast) }
        XCTAssertEqual(sortedSessions.count, matrix.count)
        for (index, session) in sortedSessions.enumerated() {
            let prescriptions = session.orderedBlocks.compactMap(\.functionalFitnessPrescription)
            XCTAssertEqual(prescriptions.count, 1, "week \(index)")
            XCTAssertEqual(prescriptions[0].format, matrix[index].0, "week \(index) format mismatch")
        }
    }

    private func reproductionExercise(_ name: String, _ functions: [MovementFunction], _ modality: FunctionalModality) -> Exercise {
        let ex = Exercise(canonicalName: name, modality: .functionalFitness, equipment: "barbell", movementPattern: "test", movementFunctions: functions, functionalModality: modality)
        context.insert(ex)
        return ex
    }

    private func reproductionCandidateExercises() -> [Exercise] {
        [
            reproductionExercise("Squat Lift", [.squatLoaded], .weightlifting),
            reproductionExercise("Hinge Lift", [.hingeLoaded], .weightlifting),
            reproductionExercise("Press Lift", [.pressLoaded], .weightlifting),
            reproductionExercise("Gymnastics Pull", [.gymnasticsPull], .gymnastics),
            reproductionExercise("Gymnastics Push", [.gymnasticsPush], .gymnastics),
            reproductionExercise("Conditioning Bike", [.monostructural], .metabolicConditioning),
        ]
    }

    /// Same reproduction shape, but through the REAL production path this
    /// bug was actually found in: `FunctionalFitnessProgramGenerator.generate`
    /// → `RollTacticalWindowUseCase.materializeFirstWindow` → fresh-context
    /// fetch, using the exact UNCHANGED legacy fallback candidate
    /// (`LongTermPlanner.functionalFitnessParameterCandidates`'s pre-V1
    /// branch: `.roundsForTime(rounds: 5, capSeconds: nil)`, `daysPerWeek`
    /// sessions, single recurring `TemplateSession` per day — the real
    /// >3-frequency shape, never sanitized for this test).
    func testReproduction_RealLegacyFallbackThroughRollTacticalWindowUseCase() throws {
        let stimulus = Stimulus(
            targetDurationDomain: .medium, intensity: .moderate, loading: .moderate,
            movementFunctions: [.squatLoaded, .gymnasticsPull, .monostructural],
            movementModalityMix: [
                ModalityCount(modality: .weightlifting, count: 1),
                ModalityCount(modality: .gymnastics, count: 1),
                ModalityCount(modality: .metabolicConditioning, count: 1),
            ],
            skillDemand: .moderate, systemicDemand: .moderate, scoreType: .time
        )
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 5, lengthWeeks: 4, targetStimulus: stimulus,
            format: .roundsForTime(rounds: 5, capSeconds: nil), sessionRole: .functionalFitness,
            varianceConstraints: VarianceConstraints(), requiresRecentExposureToProgress: false,
            includeStrengthBlock: false
        )
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let definitionID = definition.id
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition
        let instanceID = instance.id
        try context.save()

        let environment = TrainingEnvironmentTestSupport.full(context: context)
        _ = try RollTacticalWindowUseCase.materializeFirstWindow(
            system: .functionalFitness, definition: definition, instance: instance,
            startDate: Date(), ownerUserID: instance.ownerUserID, performanceProfile: nil,
            materializationContext: TacticalMaterializationContext(
                equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
                functionalFitnessCandidateExercises: reproductionCandidateExercises(),
                trainingEnvironment: environment
            ),
            context: context
        )
        try context.save()

        let fresh = freshContext()
        let reloadedDefinition = try XCTUnwrap(fresh.fetch(FetchDescriptor<ProgramDefinition>(predicate: #Predicate { $0.id == definitionID })).first)
        var formatsRead = 0
        for session in reloadedDefinition.orderedTemplateSessions {
            for block in session.orderedBlockTemplates {
                if let ffTemplate = block.functionalFitnessPrescriptionTemplate {
                    XCTAssertEqual(ffTemplate.format, .roundsForTime(rounds: 5, capSeconds: nil))
                    formatsRead += 1
                }
            }
        }
        XCTAssertEqual(formatsRead, 5, "REPRODUCTION TARGET: real >3-frequency legacy fallback, reached the real production materialization path")

        let reloadedInstance = try XCTUnwrap(fresh.fetch(FetchDescriptor<ProgramInstance>(predicate: #Predicate { $0.id == instanceID })).first)
        let sessions = reloadedInstance.sessions
        XCTAssertEqual(sessions.count, 5)
        for session in sessions {
            for block in session.orderedBlocks {
                if let prescription = block.functionalFitnessPrescription {
                    XCTAssertEqual(prescription.stimulus.targetDurationDomain, .medium)
                    XCTAssertNotNil(prescription.format)
                }
            }
        }
    }
}
