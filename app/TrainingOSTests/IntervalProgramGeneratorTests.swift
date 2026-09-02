import XCTest
import SwiftData
@testable import TrainingOS

@MainActor
final class IntervalProgramGeneratorTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    // MARK: - §1/§36: one system, four modalities, both work bases

    func testGeneratorProducesADurationBasedIntervalTemplateForEachRequiredModality() throws {
        for activityType in [ActivityType.cycling, .running, .rowing, .skiErg] {
            let configuration = IntervalProgramConfiguration(
                activityType: activityType, allowedActivityTypes: [activityType],
                daysPerWeek: 2, lengthWeeks: 4, sessionRole: .interval, workBasis: .duration,
                includeWarmUp: true, includeCoolDown: true
            )
            let definition = IntervalProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)

            XCTAssertEqual(definition.programmingSystem, .interval)
            XCTAssertEqual(definition.orderedTemplateSessions.count, 2, "\(activityType)")
            let session = try XCTUnwrap(definition.orderedTemplateSessions.first)
            XCTAssertEqual(session.role, .interval)

            // §7: warm-up -> interval -> cool-down, as separate ordered blocks.
            let blocks = session.orderedBlockTemplates
            XCTAssertEqual(blocks.map(\.type), [.warmup, .intervals, .cooldown], "\(activityType)")

            let intervalTemplate = try XCTUnwrap(blocks[1].intervalPrescriptionTemplate)
            XCTAssertEqual(intervalTemplate.preferredActivityType, activityType)
            XCTAssertEqual(intervalTemplate.progressionRules?.weekOneWorkDurationSeconds, 240, "\(activityType)")
            XCTAssertNil(intervalTemplate.progressionRules?.weekOneWorkDistanceMeters, "\(activityType) duration-basis must not also carry a distance")
        }
    }

    func testGeneratorProducesADistanceBasedIntervalTemplate() throws {
        let configuration = IntervalProgramConfiguration(
            activityType: .running, allowedActivityTypes: [.running],
            daysPerWeek: 1, lengthWeeks: 4, sessionRole: .interval, workBasis: .distance,
            includeWarmUp: false, includeCoolDown: false
        )
        let definition = IntervalProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let session = try XCTUnwrap(definition.orderedTemplateSessions.first)
        // No warm-up/cool-down requested — the interval block is the only one.
        XCTAssertEqual(session.orderedBlockTemplates.map(\.type), [.intervals])
        let intervalTemplate = try XCTUnwrap(session.orderedBlockTemplates.first?.intervalPrescriptionTemplate)
        XCTAssertEqual(intervalTemplate.progressionRules?.weekOneWorkDistanceMeters, 1000)
        XCTAssertNil(intervalTemplate.progressionRules?.weekOneWorkDurationSeconds)
        XCTAssertEqual(intervalTemplate.workIntensity, .pace(PaceRange(lower: Pace(secondsPerKilometer: 270), upper: Pace(secondsPerKilometer: 280))))
    }

    /// §7: warm-up/cool-down use ordinary steady-state blocks, not an
    /// opaque field on the interval prescription itself.
    func testWarmUpAndCoolDownAreOrdinarySteadyStateBlocksNotBuriedInTheIntervalPrescription() throws {
        let configuration = IntervalProgramConfiguration(
            activityType: .rowing, allowedActivityTypes: [.rowing],
            daysPerWeek: 1, lengthWeeks: 2, sessionRole: .interval, workBasis: .duration,
            includeWarmUp: true, includeCoolDown: true
        )
        let definition = IntervalProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let blocks = try XCTUnwrap(definition.orderedTemplateSessions.first).orderedBlockTemplates
        let warmUp = try XCTUnwrap(blocks.first { $0.type == .warmup }?.steadyStatePrescriptionTemplate)
        let coolDown = try XCTUnwrap(blocks.first { $0.type == .cooldown }?.steadyStatePrescriptionTemplate)
        XCTAssertEqual(warmUp.progressionRules?.weekOneDurationSeconds, 600)
        XCTAssertEqual(coolDown.progressionRules?.weekOneDurationSeconds, 300)
        XCTAssertNil(blocks.first { $0.type == .intervals }?.steadyStatePrescriptionTemplate, "the interval block itself must not also carry a steady-state prescription")
    }

    /// No trailing recovery/taper week is fabricated (this file's own
    /// generator doc comment) — unlike Strength/SteadyState.
    func testGeneratorDoesNotFabricateATrailingRecoveryWeek() {
        let configuration = IntervalProgramConfiguration(
            activityType: .cycling, allowedActivityTypes: [.cycling],
            daysPerWeek: 2, lengthWeeks: 4, sessionRole: .interval, workBasis: .duration,
            includeWarmUp: false, includeCoolDown: false
        )
        let definition = IntervalProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        XCTAssertEqual(definition.orderedWeeks.count, 4, "no extra week beyond configuration.lengthWeeks")
        XCTAssertTrue(definition.orderedWeeks.allSatisfy { !$0.isDeload })
    }

    // MARK: - Substitution eligibility carried onto the template graph

    func testRunningSpecificConfigurationOnlyAllowsRunning() throws {
        let configuration = IntervalProgramConfiguration(
            activityType: .running, allowedActivityTypes: [.running],
            daysPerWeek: 1, lengthWeeks: 2, sessionRole: .interval, workBasis: .distance,
            includeWarmUp: false, includeCoolDown: false
        )
        let definition = IntervalProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let template = try XCTUnwrap(definition.orderedTemplateSessions.first?.orderedBlockTemplates.first?.intervalPrescriptionTemplate)
        XCTAssertEqual(template.allowedActivityTypes, [.running])
        XCTAssertFalse(SubstituteActivityUseCase.isValid(candidate: .cycling, for: template))
    }

    // MARK: - Materializer

    func testMaterializerResolvesOneWeekAtATimeAndAppliesProgression() throws {
        let configuration = IntervalProgramConfiguration(
            activityType: .cycling, allowedActivityTypes: [.cycling],
            daysPerWeek: 1, lengthWeeks: 4, sessionRole: .interval, workBasis: .duration,
            includeWarmUp: false, includeCoolDown: false
        )
        let definition = IntervalProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)

        let week0 = try IntervalMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0),
            ownerUserID: instance.ownerUserID, weekContext: { _ in .init() },  environment: TrainingEnvironmentTestSupport.full(context: context), context: context
        )
        let week0Prescription = try XCTUnwrap(week0.first?.orderedBlocks.first?.intervalPrescription)
        XCTAssertEqual(week0Prescription.intervalCount, 4)
        XCTAssertEqual(week0Prescription.workDurationSeconds, 240)

        let week1 = try IntervalMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 1, startDate: Date(timeIntervalSince1970: 0),
            ownerUserID: instance.ownerUserID,
            weekContext: { _ in IntervalMaterializer.WeekContext(previousActualIntervalCount: 4, previousOutcome: .progress) },  environment: TrainingEnvironmentTestSupport.full(context: context),
            context: context
        )
        let week1Prescription = try XCTUnwrap(week1.first?.orderedBlocks.first?.intervalPrescription)
        XCTAssertEqual(week1Prescription.intervalCount, 5, "count should progress week over week per the generator's own priority")
    }

    /// §15/§33: a performance-gated template must refuse to materialize a
    /// future week without the previous week's actual outcome.
    func testMaterializerThrowsWhenAPerformanceGatedTemplateIsMissingThePreviousOutcome() {
        let definition = ProgramDefinition(name: "Gated Test", lengthWeeks: 2, programmingSystem: .interval, generatorVersion: 1, provenance: .constructed(reason: "test"))
        context.insert(definition)
        for _ in 0..<2 {
            let week = TrainingWeek(isDeload: false)
            context.insert(week)
            definition.addWeek(week)
        }
        let session = TemplateSession(name: "Day 1", role: .interval)
        context.insert(session)
        definition.addTemplateSession(session)
        let block = WorkoutBlockTemplate(type: .intervals)
        context.insert(block)
        session.addBlockTemplate(block)
        let template = IntervalPrescriptionTemplate(
            preferredActivityType: .running,
            progressionRules: IntervalProgressionRules(weekOneIntervalCount: 4, weekOneWorkDurationSeconds: 240, requiresSuccessfulCompletionToProgress: true)
        )
        context.insert(template)
        block.attachIntervalPrescriptionTemplate(template)

        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)

        XCTAssertThrowsError(try IntervalMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 1, startDate: Date(timeIntervalSince1970: 0),
            ownerUserID: instance.ownerUserID, weekContext: { _ in .init() },  environment: TrainingEnvironmentTestSupport.full(context: context), context: context
        )) { error in
            XCTAssertEqual(error as? IntervalMaterializationError, .previousOutcomeRequired)
        }
    }
}
