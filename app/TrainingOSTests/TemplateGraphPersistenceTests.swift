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
                setCountRule: .autoregulated(baselineSets: 3),
                repGoalSchedule: [
                    RepGoal(reps: 3, toFailure: true),
                    RepGoal(reps: 3, toFailure: true),
                    RepGoal(reps: 2, toFailure: true),
                    RepGoal(reps: 1, toFailure: true)
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
                    RepGoal(reps: 12, toFailure: false),
                    RepGoal(reps: 12, toFailure: false),
                    RepGoal(reps: 12, toFailure: false),
                    RepGoal(reps: 12, toFailure: false)
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
        XCTAssertEqual(reloadedPrimary.rules?.setCountRule, .autoregulated(baselineSets: 3))
        XCTAssertEqual(reloadedPrimary.rules?.repGoalSchedule, [
            RepGoal(reps: 3, toFailure: true), RepGoal(reps: 3, toFailure: true),
            RepGoal(reps: 2, toFailure: true), RepGoal(reps: 1, toFailure: true)
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
            rules: StrengthProgressionRules(loadRule: .none, setCountRule: .fixed(setsByWeek: [2]), repGoalSchedule: [RepGoal(reps: 15)])
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
            loadRule: .none, setCountRule: .fixed(setsByWeek: [3]), repGoalSchedule: [RepGoal(reps: 10)]
        ))
        context.insert(first)

        let secondID = UUID()
        let second = PrescriptionTemplate(id: secondID, rules: StrengthProgressionRules(
            loadRule: .linkedToPairedSlot(fractionOfSourceResult: 0.6), setCountRule: .fixed(setsByWeek: [3]), repGoalSchedule: [RepGoal(reps: 10)]
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
            loadRule: .linkedToPairedSlot(fractionOfSourceResult: 0.5), setCountRule: .fixed(setsByWeek: [3]), repGoalSchedule: [RepGoal(reps: 10)]
        ))
        context.insert(first)

        let secondID = UUID()
        let second = PrescriptionTemplate(id: secondID, rules: StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.85, laterWeekMultipliers: [1.05])), setCountRule: .fixed(setsByWeek: [3]), repGoalSchedule: [RepGoal(reps: 10)]
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
}
