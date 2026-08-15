import XCTest
import SwiftData
@testable import TrainingOS

@MainActor
final class SteadyStateProgramGeneratorTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    // MARK: - §1/§46: one system, four modalities

    func testGeneratorProducesAZone2FortyFiveMinuteTemplateForEachRequiredModality() throws {
        for activityType in [ActivityType.cycling, .running, .rowing, .skiErg] {
            let configuration = SteadyStateProgramConfiguration(
                activityType: activityType, allowedActivityTypes: [activityType],
                daysPerWeek: 3, lengthWeeks: 4, progressionDimension: .none
            )
            let definition = SteadyStateProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)

            XCTAssertEqual(definition.programmingSystem, .steadyState)
            XCTAssertEqual(definition.orderedTemplateSessions.count, 3, "\(activityType) should produce 3 sessions/week")
            let firstSession = try XCTUnwrap(definition.orderedTemplateSessions.first)
            let firstBlock = try XCTUnwrap(firstSession.orderedBlockTemplates.first)
            let steadyStateTemplate = try XCTUnwrap(firstBlock.steadyStatePrescriptionTemplate)

            XCTAssertEqual(steadyStateTemplate.preferredActivityType, activityType)
            XCTAssertEqual(steadyStateTemplate.progressionRules?.weekOneDurationSeconds, 2700, "\(activityType) should default to 45 minutes")
            XCTAssertEqual(steadyStateTemplate.primaryIntensity, .heartRateZone(.two), "\(activityType) should default to Zone 2")
            // §3: no strength-only fields required or present.
            XCTAssertNil(firstBlock.prescriptionTemplates.first)
        }
    }

    func testGeneratorAddsATrailingRecoveryWeek() {
        let configuration = SteadyStateProgramConfiguration(activityType: .cycling, allowedActivityTypes: [.cycling], daysPerWeek: 3, lengthWeeks: 4, progressionDimension: .duration)
        let definition = SteadyStateProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        XCTAssertEqual(definition.orderedWeeks.count, 5)
        XCTAssertEqual(definition.orderedWeeks.last?.isDeload, true)
        XCTAssertTrue(definition.orderedWeeks.dropLast().allSatisfy { !$0.isDeload })
    }

    func testGeneratorDoesNotMutateProgramDefinitionAcrossTwoIndependentGenerations() {
        let configuration = SteadyStateProgramConfiguration(activityType: .running, allowedActivityTypes: [.running], daysPerWeek: 3, lengthWeeks: 4, progressionDimension: .none)
        let first = SteadyStateProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let second = SteadyStateProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        XCTAssertNotEqual(first.id, second.id, "each generation produces its own independent ProgramDefinition")
    }

    // MARK: - Substitution eligibility carried onto the template graph

    func testRunningSpecificConfigurationOnlyAllowsRunning() throws {
        let configuration = SteadyStateProgramConfiguration(activityType: .running, allowedActivityTypes: [.running], daysPerWeek: 3, lengthWeeks: 4, progressionDimension: .none)
        let definition = SteadyStateProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let template = try XCTUnwrap(definition.orderedTemplateSessions.first?.orderedBlockTemplates.first?.steadyStatePrescriptionTemplate)
        XCTAssertEqual(template.allowedActivityTypes, [.running])
        XCTAssertFalse(SubstituteActivityUseCase.isValid(candidate: .cycling, for: template))
    }

    func testGenericAerobicConfigurationAllowsConfiguredAlternatives() throws {
        let configuration = SteadyStateProgramConfiguration(activityType: .cycling, allowedActivityTypes: [.cycling, .rowing, .skiErg], daysPerWeek: 3, lengthWeeks: 4, progressionDimension: .none)
        let definition = SteadyStateProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let template = try XCTUnwrap(definition.orderedTemplateSessions.first?.orderedBlockTemplates.first?.steadyStatePrescriptionTemplate)
        XCTAssertTrue(SubstituteActivityUseCase.isValid(candidate: .rowing, for: template))
        XCTAssertTrue(SubstituteActivityUseCase.isValid(candidate: .skiErg, for: template))
        XCTAssertFalse(SubstituteActivityUseCase.isValid(candidate: .running, for: template))
    }

    // MARK: - §7-8/§47.11: frequency progression at the correct architecture level

    /// Proven directly at the `TemplateSession.activeFromWeek`/materializer
    /// level — deliberately not fabricated into the generator's own
    /// built-in numbers (see `SteadyStateProgramGenerator`'s own doc
    /// comment on why).
    func testTemplateSessionActiveFromWeekControlsWhichWeeksAMaterializedSessionAppearsIn() {
        let definition = ProgramDefinition(name: "Frequency Progression Test", lengthWeeks: 4, programmingSystem: .steadyState, generatorVersion: 1, provenance: .constructed(reason: "test"))
        context.insert(definition)
        for _ in 0..<4 {
            let week = TrainingWeek(isDeload: false)
            context.insert(week)
            definition.addWeek(week)
        }

        let alwaysOnSession = TemplateSession(name: "Always On", role: .aerobicBase, activeFromWeek: 0)
        context.insert(alwaysOnSession)
        definition.addTemplateSession(alwaysOnSession)
        attachSteadyStateBlock(to: alwaysOnSession, activityType: .cycling)

        let addedLaterSession = TemplateSession(name: "Added Week 3", role: .aerobicBase, activeFromWeek: 2)
        context.insert(addedLaterSession)
        definition.addTemplateSession(addedLaterSession)
        attachSteadyStateBlock(to: addedLaterSession, activityType: .cycling)

        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)

        let sessions = SteadyStateMaterializer.materializeAllWeeks(
            definition: definition, instance: instance, startDate: Date(timeIntervalSince1970: 0),
            ownerUserID: instance.ownerUserID, context: context
        )

        let sessionsByWeek: [Int: [Session]] = Dictionary(grouping: sessions) { session in
            let daysSinceEpoch = Int((session.day?.date.timeIntervalSince1970 ?? 0) / 86400)
            return daysSinceEpoch / 7
        }
        XCTAssertEqual(sessionsByWeek[0]?.count, 1, "week 1 should only have the always-on session")
        XCTAssertEqual(sessionsByWeek[1]?.count, 1, "week 2 should still only have the always-on session")
        XCTAssertEqual(sessionsByWeek[2]?.count, 2, "week 3 onward should include the added session")
        XCTAssertEqual(sessionsByWeek[3]?.count, 2)
    }

    private func attachSteadyStateBlock(to session: TemplateSession, activityType: ActivityType) {
        let block = WorkoutBlockTemplate(type: .steadyState)
        context.insert(block)
        session.addBlockTemplate(block)
        let template = SteadyStatePrescriptionTemplate(
            preferredActivityType: activityType,
            primaryIntensity: .heartRateZone(.two),
            progressionRules: SteadyStateProgressionRules(progressionDimension: .none, weekOneDurationSeconds: 2700)
        )
        context.insert(template)
        block.attachSteadyStatePrescriptionTemplate(template)
    }

    // MARK: - Materializer: all weeks resolvable immediately (no partial-materialization limitation)

    func testMaterializerResolvesEveryWeekIncludingRecoveryInOneCall() {
        let configuration = SteadyStateProgramConfiguration(activityType: .cycling, allowedActivityTypes: [.cycling], daysPerWeek: 2, lengthWeeks: 4, progressionDimension: .duration)
        let definition = SteadyStateProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)

        let sessions = SteadyStateMaterializer.materializeAllWeeks(
            definition: definition, instance: instance, startDate: Date(timeIntervalSince1970: 0),
            ownerUserID: instance.ownerUserID, context: context
        )

        XCTAssertEqual(sessions.count, 5 * 2, "4 regular weeks + 1 recovery week, 2 sessions each")
        let durations = sessions.compactMap { $0.orderedBlocks.first?.steadyStatePrescription?.durationSeconds }
        XCTAssertEqual(Set(durations).count > 1, true, "durations should actually vary week to week, not be a flat repeated value")
    }
}
