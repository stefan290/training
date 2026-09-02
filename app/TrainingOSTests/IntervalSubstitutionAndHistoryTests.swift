import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 4D Part B/C: interval activity substitution (§24-26/§39),
/// interval history integration with `ActivityPerformanceProfile`
/// (§27-29/§38), and the SteadyState+Interval `ProgramJourney`
/// composition proof (§23).
@MainActor
final class IntervalSubstitutionAndHistoryTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func buildIntervalFixture(
        activityType: ActivityType, allowed: [ActivityType], workIntensity: IntensityTarget?
    ) -> (definition: ProgramDefinition, templateBlock: WorkoutBlockTemplate, template: IntervalPrescriptionTemplate) {
        let configuration = IntervalProgramConfiguration(
            activityType: activityType, allowedActivityTypes: allowed,
            daysPerWeek: 1, lengthWeeks: 2, sessionRole: .interval, workBasis: .duration,
            includeWarmUp: false, includeCoolDown: false
        )
        let definition = IntervalProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let templateBlock = definition.orderedTemplateSessions[0].orderedBlockTemplates[0]
        let template = templateBlock.intervalPrescriptionTemplate!
        if let workIntensity {
            template.workIntensity = workIntensity
        }
        return (definition, templateBlock, template)
    }

    // MARK: - §39.28-30/§26: THIS SESSION ONLY

    func testThisSessionOnlyIntervalSubstitutionDoesNotAffectFutureMaterialization() throws {
        let (definition, _, template) = buildIntervalFixture(activityType: .cycling, allowed: [.cycling, .rowing], workIntensity: nil)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition

        let week0 = try IntervalMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0),
            ownerUserID: instance.ownerUserID, weekContext: { _ in .init() },  environment: TrainingEnvironmentTestSupport.full(context: context), context: context
        )
        let week0Prescription = try XCTUnwrap(week0.first?.orderedBlocks.first?.intervalPrescription)
        XCTAssertEqual(week0Prescription.activityType, .cycling)

        try SubstituteActivityUseCase.substituteThisSessionOnly(prescription: week0Prescription, template: template, with: .rowing, reason: .equipmentUnavailable)
        XCTAssertEqual(week0Prescription.activityType, .rowing)
        XCTAssertTrue(week0Prescription.substitutionUsed)

        // §30: the next materialized week returns to Bike (the template default).
        let week1 = try IntervalMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 1, startDate: Date(timeIntervalSince1970: 0),
            ownerUserID: instance.ownerUserID,
            weekContext: { _ in IntervalMaterializer.WeekContext(previousActualIntervalCount: 4, previousOutcome: .progress) },  environment: TrainingEnvironmentTestSupport.full(context: context),
            context: context
        )
        let week1Prescription = try XCTUnwrap(week1.first?.orderedBlocks.first?.intervalPrescription)
        XCTAssertEqual(week1Prescription.activityType, .cycling, "THIS SESSION ONLY must not leak into future materialization")
    }

    /// §29: the actual result must go to Rowing's history, not Cycling's.
    func testThisSessionOnlySubstitutionResultEntersTheNewActivitysHistory() throws {
        let (definition, _, template) = buildIntervalFixture(activityType: .cycling, allowed: [.cycling, .rowing], workIntensity: nil)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition
        let week0 = try IntervalMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0),
            ownerUserID: instance.ownerUserID, weekContext: { _ in .init() },  environment: TrainingEnvironmentTestSupport.full(context: context), context: context
        )
        let prescription = try XCTUnwrap(week0.first?.orderedBlocks.first?.intervalPrescription)
        try SubstituteActivityUseCase.substituteThisSessionOnly(prescription: prescription, template: template, with: .rowing)

        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        let rowingProfile = PerformanceProfileStore.activityProfile(for: .rowing, in: performanceProfile, context: context)
        let result = IntervalResult(sessionDurationSeconds: 1200)
        context.insert(result)
        rowingProfile.addIntervalResult(result)
        result.activityPerformanceProfile = rowingProfile

        XCTAssertEqual(rowingProfile.intervalResults.count, 1)
        let cyclingProfile = PerformanceProfileStore.activityProfile(for: .cycling, in: performanceProfile, context: context)
        XCTAssertEqual(cyclingProfile.intervalResults.count, 0, "the substituted result must not also appear under Cycling")
    }

    // MARK: - §39.31/§26: GOING FORWARD

    func testGoingForwardIntervalSubstitutionAffectsOnlyFutureMaterialization() throws {
        let (definition, templateBlock, template) = buildIntervalFixture(activityType: .cycling, allowed: [.cycling, .rowing], workIntensity: nil)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition

        let week0 = try IntervalMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, startDate: Date(timeIntervalSince1970: 0),
            ownerUserID: instance.ownerUserID, weekContext: { _ in .init() },  environment: TrainingEnvironmentTestSupport.full(context: context), context: context
        )
        let alreadyMaterialized = try XCTUnwrap(week0.first?.orderedBlocks.first?.intervalPrescription)
        alreadyMaterialized.workoutBlock?.session?.status = .completed

        try SubstituteActivityUseCase.substituteGoingForward(instance: instance, templateBlock: templateBlock, eligibilityTemplate: template, with: .rowing, context: context)

        // §39.35: the completed historical Session remains unchanged.
        XCTAssertEqual(alreadyMaterialized.activityType, .cycling)

        let week1 = try IntervalMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 1, startDate: Date(timeIntervalSince1970: 0),
            ownerUserID: instance.ownerUserID,
            weekContext: { _ in IntervalMaterializer.WeekContext(previousActualIntervalCount: 4, previousOutcome: .progress) },  environment: TrainingEnvironmentTestSupport.full(context: context),
            context: context
        )
        let week1Prescription = try XCTUnwrap(week1.first?.orderedBlocks.first?.intervalPrescription)
        XCTAssertEqual(week1Prescription.activityType, .rowing)

        // §39.34: ProgramDefinition/template remains unchanged.
        XCTAssertEqual(template.preferredActivityType, .cycling)
    }

    // MARK: - §39.32-33: running-specific rejection + no blind metric transfer

    func testRunningSpecificIntervalPrescriptionRejectsCyclingSubstitution() {
        let (_, _, template) = buildIntervalFixture(activityType: .running, allowed: [.running], workIntensity: .pace(PaceRange(lower: Pace(secondsPerKilometer: 260), upper: Pace(secondsPerKilometer: 280))))
        XCTAssertFalse(SubstituteActivityUseCase.isValid(candidate: .cycling, for: template))
        XCTAssertThrowsError(try SubstituteActivityUseCase.substituteThisSessionOnly(
            prescription: IntervalPrescription(activityType: .running, intervalCount: 5), template: template, with: .cycling
        )) { error in
            XCTAssertEqual(error as? SubstitutionError, .invalidForSlot)
        }
    }

    /// §25/§39.33: a Bike watt target must not be blindly copied onto Row.
    func testBikeWattsAreNotCopiedIntoRowTarget() throws {
        let bikePower = IntensityTarget.powerRange(PowerRange(lower: Power(watts: 280), upper: Power(watts: 320)))
        let (_, _, template) = buildIntervalFixture(activityType: .cycling, allowed: [.cycling, .rowing], workIntensity: bikePower)
        let prescription = IntervalPrescription(activityType: .cycling, intervalCount: 4, workIntensity: bikePower)
        context.insert(prescription)

        try SubstituteActivityUseCase.substituteThisSessionOnly(prescription: prescription, template: template, with: .rowing)
        XCTAssertEqual(prescription.activityType, .rowing)
        XCTAssertNil(prescription.workIntensity, "a Bike power target must never be silently reused as a Row target — calibration is required instead")
    }

    // MARK: - §23/§38.23-27: history survival + coexistence

    func testIntervalHistorySurvivesReplacingOneProgramInstanceWithAnother() throws {
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        let runningProfile = PerformanceProfileStore.activityProfile(for: .running, in: performanceProfile, context: context)

        let (definitionA, _, _) = buildIntervalFixture(activityType: .running, allowed: [.running], workIntensity: nil)
        let instanceA = ProgramInstance(ownerUserID: UUID())
        context.insert(instanceA)
        instanceA.programDefinition = definitionA
        let resultA = IntervalResult(sessionDurationSeconds: 1600)
        context.insert(resultA)
        runningProfile.addIntervalResult(resultA)
        resultA.activityPerformanceProfile = runningProfile
        context.delete(instanceA)
        try context.save()

        let (definitionB, _, _) = buildIntervalFixture(activityType: .running, allowed: [.running], workIntensity: nil)
        let instanceB = ProgramInstance(ownerUserID: UUID())
        context.insert(instanceB)
        instanceB.programDefinition = definitionB

        let runningProfileAfter = PerformanceProfileStore.activityProfile(for: .running, in: performanceProfile, context: context)
        XCTAssertEqual(runningProfileAfter.id, runningProfile.id)
        XCTAssertEqual(runningProfileAfter.intervalResults.count, 1, "the result logged under Program A must still be reachable")
    }

    func testRowingIntervalHistoryRemainsDistinctFromCycling() {
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        let rowingProfile = PerformanceProfileStore.activityProfile(for: .rowing, in: performanceProfile, context: context)
        let cyclingProfile = PerformanceProfileStore.activityProfile(for: .cycling, in: performanceProfile, context: context)

        let rowingResult = IntervalResult(sessionDurationSeconds: 1200)
        context.insert(rowingResult)
        rowingProfile.addIntervalResult(rowingResult)
        rowingResult.activityPerformanceProfile = rowingProfile

        XCTAssertEqual(rowingProfile.intervalResults.count, 1)
        XCTAssertEqual(cyclingProfile.intervalResults.count, 0)
    }

    /// §27: SteadyState history and Interval history coexist for the same
    /// Activity without overwriting one another — both hang off the same
    /// `ActivityPerformanceProfile`, in two separate arrays.
    func testSteadyStateAndIntervalHistoryCoexistForTheSameActivityWithoutOverwriting() {
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        let runningProfile = PerformanceProfileStore.activityProfile(for: .running, in: performanceProfile, context: context)

        let steadyResult = SteadyStateResult(actualDurationSeconds: 2700)
        context.insert(steadyResult)
        runningProfile.addSteadyStateResult(steadyResult)
        steadyResult.activityPerformanceProfile = runningProfile

        let intervalResult = IntervalResult(sessionDurationSeconds: 1600)
        context.insert(intervalResult)
        runningProfile.addIntervalResult(intervalResult)
        intervalResult.activityPerformanceProfile = runningProfile

        XCTAssertEqual(runningProfile.steadyStateResults.count, 1)
        XCTAssertEqual(runningProfile.intervalResults.count, 1, "adding the interval result must not overwrite or evict the steady-state one")
    }

    /// §28: distinct performance contexts (e.g. Threshold vs. VO2 interval
    /// history) stay separate, exactly like Stage 4C's "5K" example.
    func testDistinctIntervalPerformanceContextsRemainSeparate() {
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        let thresholdProfile = PerformanceProfileStore.activityProfile(for: .running, performanceContext: "Threshold", in: performanceProfile, context: context)
        let vo2Profile = PerformanceProfileStore.activityProfile(for: .running, performanceContext: "VO2", in: performanceProfile, context: context)
        XCTAssertNotEqual(thresholdProfile.id, vo2Profile.id)
    }

    // MARK: - §23: SteadyState + Interval composition, no new entity type

    /// Proves a `TrainingPlan` can sequence a SteadyState phase and an
    /// Interval phase together (e.g. "Easy Run" -> "Threshold Intervals")
    /// using only the existing `TrainingPlan`/`TrainingPhase`/
    /// `ProgramInstance` types — no new composition entity was needed,
    /// exactly as `ENDURANCE_PROGRAMMING_MODEL.md` §10 already predicted.
    func testSteadyStateAndIntervalPhasesComposeInOneTrainingPlanWithNoNewEntityType() throws {
        let plan = TrainingPlan(status: .active)
        context.insert(plan)

        let steadyConfiguration = SteadyStateProgramConfiguration(activityType: .running, allowedActivityTypes: [.running], daysPerWeek: 2, lengthWeeks: 3, progressionDimension: .none)
        let steadyDefinition = SteadyStateProgramGenerator.generate(configuration: steadyConfiguration, provenance: .constructed(reason: "test"), context: context)
        let easyRunPhase = TrainingPhase(type: .enduranceEvent, startDate: Date(timeIntervalSince1970: 0), priorityRule: .endurance)
        context.insert(easyRunPhase)
        plan.addPhase(easyRunPhase)
        let steadyInstance = ProgramInstance(ownerUserID: UUID())
        context.insert(steadyInstance)
        steadyInstance.programDefinition = steadyDefinition
        easyRunPhase.addProgramInstance(steadyInstance)

        let intervalConfiguration = IntervalProgramConfiguration(activityType: .running, allowedActivityTypes: [.running], daysPerWeek: 1, lengthWeeks: 3, sessionRole: .threshold, workBasis: .duration, includeWarmUp: true, includeCoolDown: true)
        let intervalDefinition = IntervalProgramGenerator.generate(configuration: intervalConfiguration, provenance: .constructed(reason: "test"), context: context)
        let thresholdPhase = TrainingPhase(type: .enduranceEvent, startDate: Date(timeIntervalSince1970: 3 * 7 * 86400), priorityRule: .endurance)
        context.insert(thresholdPhase)
        plan.addPhase(thresholdPhase)
        let intervalInstance = ProgramInstance(ownerUserID: UUID())
        context.insert(intervalInstance)
        intervalInstance.programDefinition = intervalDefinition
        thresholdPhase.addProgramInstance(intervalInstance)

        XCTAssertEqual(plan.orderedPhases.count, 2)
        XCTAssertEqual(plan.orderedPhases[0].primaryInstance?.programDefinition?.programmingSystem, .steadyState)
        XCTAssertEqual(plan.orderedPhases[1].primaryInstance?.programDefinition?.programmingSystem, .interval)
    }
}
