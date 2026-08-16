import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 5B: create -> save -> fresh ModelContext -> fetch -> semantic
/// equality, for every new persisted type/field this stage introduces —
/// written before trusting any of them, per this project's own standing
/// "verify persistence assumptions before trusting them" discipline
/// (Stage 4A's Bug 2/3, re-confirmed every stage since).
@MainActor
final class LongTermPlannerPersistenceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func freshContext() -> ModelContext {
        ModelContext(container)
    }

    // MARK: - Goal objective composition (§47)

    func testGoalSecondaryObjectivesSurviveRoundTrip() throws {
        let goalID = UUID()
        let goal = Goal(
            id: goalID,
            ownerUserID: UUID(),
            primaryType: .muscleGain,
            secondaryObjectives: [
                SecondaryObjective(type: .enduranceEvent, role: .protected),
                SecondaryObjective(type: .functionalFitness, role: .supporting),
            ]
        )
        context.insert(goal)
        try context.save()

        let reloaded = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.id == goalID })).first
        )
        XCTAssertEqual(reloaded.secondaryObjectives.count, 2)
        XCTAssertEqual(reloaded.secondaryObjectives[0], SecondaryObjective(type: .enduranceEvent, role: .protected))
        XCTAssertEqual(reloaded.secondaryObjectives[1], SecondaryObjective(type: .functionalFitness, role: .supporting))
    }

    func testGoalMilestoneDateAndBodyCompositionDirectionSurviveRoundTrip() throws {
        let goalID = UUID()
        let milestone = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let goal = Goal(
            id: goalID,
            ownerUserID: UUID(),
            primaryType: .muscleGain,
            milestoneDate: milestone,
            bodyCompositionDirection: .gainMuscle
        )
        context.insert(goal)
        try context.save()

        let reloaded = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.id == goalID })).first
        )
        XCTAssertEqual(reloaded.milestoneDate, milestone)
        XCTAssertEqual(reloaded.bodyCompositionDirection, .gainMuscle)
    }

    /// The critical Bug-3-style diagnostic: two sibling `Goal` rows with
    /// *different* `GoalPreferences` shapes must each decode correctly,
    /// not silently collapse the second row's nested arrays/optionals to
    /// empty/nil.
    func testTwoSiblingGoalsWithDifferentPreferencesBothSurviveRoundTrip() throws {
        let sparseID = UUID()
        let richID = UUID()

        let sparseGoal = Goal(id: sparseID, ownerUserID: UUID(), primaryType: .generalStrength)
        context.insert(sparseGoal)

        let richGoal = Goal(
            id: richID,
            ownerUserID: UUID(),
            primaryType: .muscleGain,
            preferences: GoalPreferences(
                preferredModalities: [
                    ModalityPreference(system: .functionalFitness),
                    ModalityPreference(system: .steadyState, activityType: .cycling),
                ],
                dislikedModalities: [ModalityPreference(system: .steadyState, activityType: .running)],
                varietyPreference: .high,
                priorityMuscleGroups: [.chest, .back],
                performanceGoals: ["Sub-20 5K"],
                availableTrainingDaysPerWeek: 6,
                typicalSessionDurationMinutes: 60,
                allowsDoubleSessions: true
            )
        )
        context.insert(richGoal)
        try context.save()

        let fetchContext = freshContext()
        let reloadedSparse = try XCTUnwrap(
            fetchContext.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.id == sparseID })).first
        )
        let reloadedRich = try XCTUnwrap(
            fetchContext.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.id == richID })).first
        )

        XCTAssertNil(reloadedSparse.preferences)

        let prefs = try XCTUnwrap(reloadedRich.preferences)
        XCTAssertEqual(prefs.preferredModalities, [
            ModalityPreference(system: .functionalFitness),
            ModalityPreference(system: .steadyState, activityType: .cycling),
        ])
        XCTAssertEqual(prefs.dislikedModalities, [ModalityPreference(system: .steadyState, activityType: .running)])
        XCTAssertEqual(prefs.varietyPreference, .high)
        XCTAssertEqual(prefs.priorityMuscleGroups, [.chest, .back])
        XCTAssertEqual(prefs.performanceGoals, ["Sub-20 5K"])
        XCTAssertEqual(prefs.availableTrainingDaysPerWeek, 6)
        XCTAssertEqual(prefs.typicalSessionDurationMinutes, 60)
        XCTAssertEqual(prefs.allowsDoubleSessions, true)
    }

    func testGoalWithNoPreferencesDegradesGracefully() throws {
        let goalID = UUID()
        let goal = Goal(id: goalID, ownerUserID: UUID(), primaryType: .fatLoss)
        context.insert(goal)
        try context.save()

        let reloaded = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.id == goalID })).first
        )
        XCTAssertNil(reloaded.preferences)
        XCTAssertNil(reloaded.milestoneDate)
        XCTAssertNil(reloaded.bodyCompositionDirection)
        XCTAssertTrue(reloaded.secondaryObjectives.isEmpty)
    }

    // MARK: - Plan revision lineage (§47)

    func testTrainingPlanSupersedesAndLineageIDSurviveRoundTrip() throws {
        let goal = Goal(ownerUserID: UUID(), primaryType: .muscleGain)
        context.insert(goal)

        let revision1ID = UUID()
        let revision1 = TrainingPlan(id: revision1ID, status: .superseded)
        context.insert(revision1)
        goal.addPlan(revision1)

        let revision2ID = UUID()
        let revision2 = TrainingPlan(id: revision2ID, status: .active, supersedes: revision1, lineageID: revision1.lineageID)
        context.insert(revision2)
        goal.addPlan(revision2)
        try context.save()

        let fetchContext = freshContext()
        let reloaded1 = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<TrainingPlan>(predicate: #Predicate { $0.id == revision1ID })).first)
        let reloaded2 = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<TrainingPlan>(predicate: #Predicate { $0.id == revision2ID })).first)

        XCTAssertEqual(reloaded2.supersedes?.id, revision1ID)
        XCTAssertEqual(reloaded2.lineageID, reloaded1.lineageID)
        XCTAssertNil(reloaded1.supersedes)
    }

    func testTwoIndependentLineagesHaveDifferentLineageIDsByDefault() throws {
        let planA = TrainingPlan()
        let planB = TrainingPlan()
        XCTAssertNotEqual(planA.lineageID, planB.lineageID)
    }

    // MARK: - Temporary preference state (§47) — TrainingMix.validFrom/.validUntil

    func testTemporaryTrainingMixWindowSurvivesRoundTrip() throws {
        let phase = TrainingPhase(type: .muscleGain, startDate: Date(), priorityRule: .strength)
        context.insert(phase)

        let validFrom = Date(timeIntervalSince1970: 1_800_000_000)
        let validUntil = Date(timeIntervalSince1970: 1_802_000_000)
        let mixID = UUID()
        let mix = TrainingMix(id: mixID, kind: .selected, name: "Temporary Functional Fitness", validFrom: validFrom, validUntil: validUntil)
        context.insert(mix)
        phase.addTrainingMix(mix)
        try context.save()

        let fetchContext = freshContext()
        let reloaded = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<TrainingMix>(predicate: #Predicate { $0.id == mixID })).first)

        XCTAssertEqual(reloaded.validFrom, validFrom)
        XCTAssertEqual(reloaded.validUntil, validUntil)
        XCTAssertEqual(reloaded.kind, .selected)
        XCTAssertNotNil(reloaded.phase)
    }

    // MARK: - Revision-driven phase status mutation (§47) — capability/plan state

    func testAbandonedPhaseStatusSurvivesRoundTripAfterASupersedingRevision() throws {
        let goal = Goal(ownerUserID: UUID(), primaryType: .muscleGain)
        context.insert(goal)
        let planID = UUID()
        let plan = TrainingPlan(id: planID, status: .active)
        context.insert(plan)
        goal.addPlan(plan)

        let phaseID = UUID()
        let phase = TrainingPhase(id: phaseID, type: .fatLoss, startDate: Date(), priorityRule: .strength, status: .planned)
        context.insert(phase)
        plan.addPhase(phase)
        try context.save()

        // Simulate what AcceptStrategicPlanUseCase does to a superseded
        // plan's still-.planned phases.
        phase.status = .abandoned
        plan.status = .superseded
        try context.save()

        let fetchContext = freshContext()
        let reloadedPhase = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<TrainingPhase>(predicate: #Predicate { $0.id == phaseID })).first)
        let reloadedPlan = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<TrainingPlan>(predicate: #Predicate { $0.id == planID })).first)

        XCTAssertEqual(reloadedPhase.status, .abandoned)
        XCTAssertEqual(reloadedPlan.status, .superseded)
    }

    // MARK: - PlannerDecision (§47)

    func testPlannerDecisionSurvivesRoundTripWithAlternativesConsidered() throws {
        let phase = TrainingPhase(type: .muscleGain, startDate: Date(), priorityRule: .strength)
        context.insert(phase)

        let decisionID = UUID()
        let decision = PlannerDecision(
            id: decisionID,
            decidedAt: Date(),
            decisionType: .programOrMixSelected,
            source: .userOverride,
            reasonCode: .adherencePreferencePromotedAlternative,
            factors: ["tierGap": "1"],
            alternativesConsidered: [
                ConsideredAlternative(label: "5-Day Hypertrophy + 2 Zone 2", ratingSummary: .excellent, rejectionReasonCode: nil),
            ],
            explanation: "Promoted for variety while still supporting the muscle-gain objective.",
            phase: phase
        )
        context.insert(decision)
        try context.save()

        let reloaded = try XCTUnwrap(
            freshContext().fetch(FetchDescriptor<PlannerDecision>(predicate: #Predicate { $0.id == decisionID })).first
        )
        XCTAssertEqual(reloaded.decisionType, .programOrMixSelected)
        XCTAssertEqual(reloaded.source, .userOverride)
        XCTAssertEqual(reloaded.reasonCode, .adherencePreferencePromotedAlternative)
        XCTAssertEqual(reloaded.factors["tierGap"], "1")
        XCTAssertEqual(reloaded.alternativesConsidered.count, 1)
        XCTAssertEqual(reloaded.alternativesConsidered.first?.label, "5-Day Hypertrophy + 2 Zone 2")
        XCTAssertEqual(reloaded.alternativesConsidered.first?.ratingSummary, .excellent)
        XCTAssertEqual(reloaded.phase?.type, .muscleGain)
    }

    /// The critical Bug-3-style diagnostic: two sibling `PlannerDecision`
    /// rows with different `decisionType`/back-reference combinations
    /// must each decode correctly.
    func testTwoSiblingPlannerDecisionsWithDifferentBackReferencesBothSurviveRoundTrip() throws {
        let goal = Goal(ownerUserID: UUID(), primaryType: .muscleGain)
        context.insert(goal)
        let plan = TrainingPlan(status: .active)
        context.insert(plan)

        let phaseDecisionID = UUID()
        let phaseDecision = PlannerDecision(
            id: phaseDecisionID, decidedAt: Date(), decisionType: .phaseSelected,
            source: .systemRecommended, reasonCode: .phaseSelectedForGoal,
            explanation: "Muscle Gain selected as the primary objective.", goal: goal
        )
        context.insert(phaseDecision)

        let revisionDecisionID = UUID()
        let revisionDecision = PlannerDecision(
            id: revisionDecisionID, decidedAt: Date(), decisionType: .roadmapRevised,
            source: .planRevision, reasonCode: .planRevised,
            explanation: "Roadmap revised after milestone change.", planRevision: plan
        )
        context.insert(revisionDecision)
        try context.save()

        let fetchContext = freshContext()
        let reloadedPhaseDecision = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<PlannerDecision>(predicate: #Predicate { $0.id == phaseDecisionID })).first)
        let reloadedRevisionDecision = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<PlannerDecision>(predicate: #Predicate { $0.id == revisionDecisionID })).first)

        XCTAssertNotNil(reloadedPhaseDecision.goal)
        XCTAssertNil(reloadedPhaseDecision.planRevision)
        XCTAssertNil(reloadedRevisionDecision.goal)
        XCTAssertNotNil(reloadedRevisionDecision.planRevision)
    }
}
