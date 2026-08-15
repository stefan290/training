import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 4D: create -> save -> fresh ModelContext -> fetch -> semantic
/// equality, for every new persisted type this stage introduces
/// (`IntervalPrescriptionTemplate`, and the re-keyed
/// `ActivitySelectionOverride.templateBlock`). Written before trusting
/// either in generator/materializer/substitution logic, per the standing
/// discipline — a Codable type (or a new flattened-array storage shape)
/// is never assumed persistence-safe by analogy alone.
@MainActor
final class IntervalPersistenceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func freshContext() -> ModelContext {
        ModelContext(container)
    }

    // MARK: - IntervalPrescriptionTemplate

    func testIntervalPrescriptionTemplateWithPriorityProgressionSurvivesRoundTrip() throws {
        let templateID = UUID()
        let rules = IntervalProgressionRules(
            priority: [
                IntervalProgressionStep(variable: .intervalCount, incrementPerWeek: 1, weeksToCeiling: 3),
                IntervalProgressionStep(variable: .workDuration, incrementPerWeek: 60, weeksToCeiling: 4)
            ],
            weekOneIntervalCount: 4,
            weekOneWorkDurationSeconds: 240,
            weekOneRecoveryDurationSeconds: 180,
            recoveryDurationFloorSeconds: 120,
            completionCriteria: IntervalCompletionCriteria(maxRpeAllowed: 9)
        )
        let template = IntervalPrescriptionTemplate(
            id: templateID,
            preferredActivityType: .running,
            allowedActivityTypes: [.running, .cycling],
            workIntensity: .heartRatePercent(BoundedRange(lower: 0.90, upper: 0.95)),
            recoveryIntensity: .heartRatePercent(BoundedRange(lower: 0.70, upper: 0.70)),
            recoveryType: .active,
            progressionRules: rules
        )
        context.insert(template)
        try context.save()

        let fetchContext = freshContext()
        let descriptor = FetchDescriptor<IntervalPrescriptionTemplate>(predicate: #Predicate { $0.id == templateID })
        let fetched = try XCTUnwrap(try fetchContext.fetch(descriptor).first)

        XCTAssertEqual(fetched.preferredActivityType, .running)
        XCTAssertEqual(fetched.allowedActivityTypes, [.running, .cycling])
        XCTAssertEqual(fetched.workIntensity, .heartRatePercent(BoundedRange(lower: 0.90, upper: 0.95)))
        XCTAssertEqual(fetched.recoveryIntensity, .heartRatePercent(BoundedRange(lower: 0.70, upper: 0.70)))
        XCTAssertEqual(fetched.recoveryType, .active)
        XCTAssertEqual(fetched.progressionRules, rules)
    }

    /// The critical Bug-3-style regression check, repeated for the new
    /// flattened priority-array storage: two sibling rows with
    /// heterogeneous `priority`/intensity-progression shapes must each
    /// decode correctly.
    func testTwoSiblingRowsWithDifferentPriorityListsBothSurviveRoundTrip() throws {
        let countOnlyID = UUID()
        let intensityID = UUID()

        let countOnlyTemplate = IntervalPrescriptionTemplate(
            id: countOnlyID, preferredActivityType: .rowing,
            progressionRules: IntervalProgressionRules(
                priority: [IntervalProgressionStep(variable: .intervalCount, incrementPerWeek: 1, weeksToCeiling: 3)],
                weekOneIntervalCount: 5, weekOneWorkDistanceMeters: 1000
            )
        )
        context.insert(countOnlyTemplate)

        let intensityTemplate = IntervalPrescriptionTemplate(
            id: intensityID, preferredActivityType: .rowing,
            progressionRules: IntervalProgressionRules(
                priority: [IntervalProgressionStep(variable: .intensity, incrementPerWeek: 1, weeksToCeiling: 2)],
                weekOneIntervalCount: 4, weekOneWorkDurationSeconds: 240,
                intensityZoneProgression: IntensityZoneProgression(startZone: .two, stepPerWeek: 1, maxZone: .four)
            )
        )
        context.insert(intensityTemplate)
        try context.save()

        let fetchContext = freshContext()
        let countDescriptor = FetchDescriptor<IntervalPrescriptionTemplate>(predicate: #Predicate { $0.id == countOnlyID })
        let intensityDescriptor = FetchDescriptor<IntervalPrescriptionTemplate>(predicate: #Predicate { $0.id == intensityID })

        let fetchedCount = try XCTUnwrap(try fetchContext.fetch(countDescriptor).first)
        let fetchedIntensity = try XCTUnwrap(try fetchContext.fetch(intensityDescriptor).first)

        XCTAssertEqual(fetchedCount.progressionRules?.priority, [IntervalProgressionStep(variable: .intervalCount, incrementPerWeek: 1, weeksToCeiling: 3)])
        XCTAssertNil(fetchedCount.progressionRules?.intensityZoneProgression)
        XCTAssertEqual(fetchedCount.progressionRules?.weekOneWorkDistanceMeters, 1000)

        XCTAssertEqual(fetchedIntensity.progressionRules?.priority, [IntervalProgressionStep(variable: .intensity, incrementPerWeek: 1, weeksToCeiling: 2)])
        XCTAssertEqual(fetchedIntensity.progressionRules?.intensityZoneProgression, IntensityZoneProgression(startZone: .two, stepPerWeek: 1, maxZone: .four))
        XCTAssertNil(fetchedIntensity.progressionRules?.weekOneWorkDistanceMeters)
    }

    func testWorkoutBlockTemplateIntervalRelationshipSurvivesRoundTrip() throws {
        let sessionID = UUID()
        let session = TemplateSession(id: sessionID, name: "Interval Day", role: .interval)
        context.insert(session)
        let block = WorkoutBlockTemplate(type: .intervals)
        context.insert(block)
        session.addBlockTemplate(block)
        let template = IntervalPrescriptionTemplate(
            preferredActivityType: .skiErg,
            progressionRules: IntervalProgressionRules(weekOneIntervalCount: 4, weekOneWorkDurationSeconds: 240)
        )
        context.insert(template)
        block.attachIntervalPrescriptionTemplate(template)
        try context.save()

        let fetchContext = freshContext()
        let descriptor = FetchDescriptor<TemplateSession>(predicate: #Predicate { $0.id == sessionID })
        let fetchedSession = try XCTUnwrap(try fetchContext.fetch(descriptor).first)
        let fetchedBlock = try XCTUnwrap(fetchedSession.orderedBlockTemplates.first)
        XCTAssertEqual(fetchedBlock.intervalPrescriptionTemplate?.preferredActivityType, .skiErg)
    }

    // MARK: - ActivitySelectionOverride, re-keyed to WorkoutBlockTemplate (Stage 4D correction)

    /// Proves the override mechanism now works identically for an
    /// interval block template, not just steady-state — the entire point
    /// of the Stage 4D re-key.
    func testActivitySelectionOverrideWorksForAnIntervalBlockTemplate() throws {
        let templateBlock = WorkoutBlockTemplate(type: .intervals)
        context.insert(templateBlock)
        let intervalTemplate = IntervalPrescriptionTemplate(
            preferredActivityType: .cycling, allowedActivityTypes: [.cycling, .rowing],
            progressionRules: IntervalProgressionRules(weekOneIntervalCount: 4, weekOneWorkDurationSeconds: 240)
        )
        context.insert(intervalTemplate)
        templateBlock.attachIntervalPrescriptionTemplate(intervalTemplate)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)

        let overrideID = UUID()
        let override = ActivitySelectionOverride(id: overrideID, selectedActivityType: .rowing)
        override.templateBlock = templateBlock
        context.insert(override)
        instance.addActivitySelectionOverride(override)
        try context.save()

        let fetchContext = freshContext()
        let descriptor = FetchDescriptor<ActivitySelectionOverride>(predicate: #Predicate { $0.id == overrideID })
        let fetched = try XCTUnwrap(try fetchContext.fetch(descriptor).first)
        XCTAssertEqual(fetched.selectedActivityType, .rowing)
        XCTAssertEqual(fetched.templateBlock?.intervalPrescriptionTemplate?.preferredActivityType, .cycling)
    }

    /// Deleting the `WorkoutBlockTemplate` (as happens when its
    /// `ProgramDefinition` cascades away) must nullify `templateBlock`
    /// cleanly rather than crash — the required-inverse fix moved from
    /// `SteadyStatePrescriptionTemplate` to `WorkoutBlockTemplate` in
    /// Stage 4D, re-proven directly at its new location.
    func testDeletingWorkoutBlockTemplateNullifiesRatherThanCrashingActivitySelectionOverride() throws {
        let templateBlock = WorkoutBlockTemplate(type: .steadyState)
        context.insert(templateBlock)
        let steadyStateTemplate = SteadyStatePrescriptionTemplate(preferredActivityType: .cycling, allowedActivityTypes: [.cycling, .rowing])
        context.insert(steadyStateTemplate)
        templateBlock.attachSteadyStatePrescriptionTemplate(steadyStateTemplate)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        let override = ActivitySelectionOverride(selectedActivityType: .rowing)
        override.templateBlock = templateBlock
        context.insert(override)
        instance.addActivitySelectionOverride(override)
        try context.save()

        context.delete(templateBlock)
        XCTAssertNoThrow(try context.save())

        XCTAssertNil(override.templateBlock)
        XCTAssertNotNil(override.programInstance, "the override itself must survive — only the dangling template reference nullifies")
    }
}
