import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 7 (Tactical Planning Orchestration), Slice 3: `TransitionPhaseUseCase`
/// — closing the gap `RollTacticalWindowUseCase`'s own doc comment already
/// named as "a phase-transition-shaped event... not built this pass."
/// Every test here goes through the real production chain: accepted
/// Strategic Plan -> `StartPhaseUseCase` for phase 1 -> real logged
/// results/feedback -> `TransitionPhaseUseCase.transition` -> phase 2
/// started through the exact same `StartPhaseUseCase.start` entry point.
@MainActor
final class PhaseTransitionOrchestrationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()
    let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)

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

    private func makeAcceptedPlan(asOf: Date) throws -> (goal: Goal, plan: TrainingPlan) {
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .muscleGain, targetDate: Calendar.current.date(byAdding: .year, value: 1, to: asOf), createdAt: asOf)
        context.insert(goal)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: asOf)
        return (goal, plan)
    }

    private func availability() -> UserAvailability {
        UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1)
    }

    private struct AllCandidates {
        let strength: [Exercise]
        let functionalFitness: [Exercise]
    }

    private func makeCandidates() -> AllCandidates {
        func exercise(
            _ name: String, _ targets: [MuscleGroup] = [], _ movementFunctions: [MovementFunction] = [], _ functionalModality: FunctionalModality? = nil
        ) -> Exercise {
            let ex = Exercise(canonicalName: name, modality: .hypertrophy, equipment: "barbell", movementPattern: "test", primaryTargets: targets, movementFunctions: movementFunctions, functionalModality: functionalModality)
            context.insert(ex)
            return ex
        }
        let strength = [
            exercise("Aaa Transition Primary Shoulders", [.shoulders]),
            exercise("Aaa Transition Primary Quads", [.quadriceps]),
            exercise("Aaa Transition Primary Back", [.back]),
            exercise("Zzz Transition Paired Accessory", [.chest, .triceps]),
        ]
        let ff = [
            exercise("Transition FF Squat Lift", [], [.squatLoaded], .weightlifting),
            exercise("Transition FF Pull-up", [], [.gymnasticsPull], .gymnastics),
            exercise("Transition FF Bike", [], [.monostructural], .metabolicConditioning),
        ]
        return AllCandidates(strength: strength, functionalFitness: ff)
    }

    private func completeAllSessions(in instance: ProgramInstance, performanceProfile: PerformanceProfile, asOf: Date) throws {
        for session in instance.sessions {
            for block in session.orderedBlocks {
                for prescription in block.orderedPrescriptions {
                    for setPrescription in prescription.orderedSetPrescriptions {
                        RecordSetResultUseCase.recordSet(
                            setIndex: 0, weight: setPrescription.targetWeight ?? 40, reps: 8, targetRir: nil, actualRir: nil, prBand: nil,
                            scoringDirection: .higherIsBetter, context: .rx, setPrescription: setPrescription, exercisePrescription: prescription,
                            exercise: prescription.exercise ?? Exercise(canonicalName: "fallback-\(UUID())", modality: .hypertrophy, equipment: "none", movementPattern: "none"),
                            performanceProfile: performanceProfile, completedAt: asOf, modelContext: context
                        )
                    }
                }
                try CompleteBlockUseCase.complete(block, context: .full, modelContext: context)
            }
            try CompleteSessionUseCase.complete(session, context: .full, asOf: asOf, modelContext: context)
        }
    }

    // MARK: 7, 8, 9, 12, 13, 14 — the full transition, with a genuine modality-mix change (point 11)

    func testPhaseTransitionCompletesOldPhaseStartsNextWithChangedModalityMixAndNeverMutatesHistory() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        XCTAssertGreaterThanOrEqual(fixture.plan.orderedPhases.count, 2, "a full-year muscleGain plan must forward-fill at least 2 phases")
        let phase1 = fixture.plan.orderedPhases[0]
        let phase2 = fixture.plan.orderedPhases[1]

        let candidates = makeCandidates()
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        let materializationContext = TacticalMaterializationContext(
            equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness
        )

        // Phase 1: the simple "Focused Hypertrophy" candidate (Hypertrophy + SteadyState only — no Functional Fitness yet).
        let phase1Candidates = LongTermPlanner.proposeTrainingMix(phase: phase1, goal: fixture.goal)
        let mix1 = try XCTUnwrap(phase1Candidates.first { $0.mix.name == "Focused Hypertrophy" })
        try StartPhaseUseCase.start(
            phase: phase1, mix: mix1.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: performanceProfile, availability: availability(),
            materializationContext: materializationContext, context: context
        )
        XCTAssertEqual(phase1.status, .active)
        let phase1HypertrophyInstance = try XCTUnwrap(phase1.primaryInstance)
        XCTAssertTrue(phase1.programInstances.contains { $0.programDefinition?.programmingSystem == .steadyState }, "Focused Hypertrophy's Zone 2 Conditioning component must also have instantiated")
        let phase1InstanceIDs = Set(phase1.programInstances.map(\.id))

        // Real logged history against phase 1's Hypertrophy instance —
        // captured before transitioning so we can prove it's untouched after.
        try completeAllSessions(in: phase1HypertrophyInstance, performanceProfile: performanceProfile, asOf: asOf)

        let historyExercise = try XCTUnwrap(phase1HypertrophyInstance.sessions.first?.orderedBlocks.first?.orderedPrescriptions.first?.exercise)
        let exerciseProfileIDBefore = try XCTUnwrap(performanceProfile.profile(for: historyExercise)?.id)
        let setResultCountBefore = try XCTUnwrap(performanceProfile.profile(for: historyExercise)?.setResults.count)
        let personalRecordCountBefore = try XCTUnwrap(performanceProfile.profile(for: historyExercise)?.personalRecords.count)
        XCTAssertGreaterThan(setResultCountBefore, 0)
        XCTAssertGreaterThan(personalRecordCountBefore, 0, "a first-ever logged entry always creates a PersonalRecord (RecordSetResultUseCase's own existing behavior)")

        let phase1SessionIDsBefore = Set(phase1.programInstances.flatMap(\.sessions).map(\.id))
        let phase1SessionDatesBefore = Dictionary(uniqueKeysWithValues: phase1.programInstances.flatMap(\.sessions).map { ($0.id, $0.day?.date) })
        let phase1DecisionIDsBefore = Set(try context.fetch(FetchDescriptor<PlannerDecision>()).filter { $0.phase?.id == phase1.id }.map(\.id))
        XCTAssertFalse(phase1DecisionIDsBefore.isEmpty, "phase 1's own start already created real PlannerDecisions — must still be queryable after transition")

        let transitionAsOf = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 30, to: asOf))

        // Phase 2 gets a GENUINELY DIFFERENT mix — "Strength Plus Variety"
        // adds Functional Fitness where phase 1 had none (point 11).
        let phase2Candidates = LongTermPlanner.proposeTrainingMix(phase: phase2, goal: fixture.goal)
        let mix2 = try XCTUnwrap(phase2Candidates.first { $0.mix.name == "Strength Plus Variety" })
        XCTAssertNotEqual(mix1.mix.name, mix2.mix.name)

        let transitionResult = try TransitionPhaseUseCase.transition(
            from: phase1, toNextPhaseWithMix: mix2.mix, asOf: transitionAsOf, ownerUserID: ownerUserID,
            performanceProfile: performanceProfile, availability: availability(),
            materializationContext: materializationContext, context: context
        )

        // --- Point 7/9: the outgoing phase is genuinely completed, the new one genuinely active with its OWN instances.
        XCTAssertEqual(transitionResult.completedPhase.id, phase1.id)
        XCTAssertEqual(phase1.status, .completed)
        for instance in phase1.programInstances {
            XCTAssertEqual(instance.status, .completed, "every one of phase 1's own instances must be completed too, not just the phase")
        }
        XCTAssertEqual(transitionResult.nextPhase.id, phase2.id)
        XCTAssertEqual(phase2.status, .active)
        XCTAssertEqual(transitionResult.startResult.instancesByComponent.count, 3, "phase 2's varied mix must instantiate all 3 of its own components")
        let phase2InstanceIDs = Set(phase2.programInstances.map(\.id))
        XCTAssertTrue(phase2InstanceIDs.isDisjoint(with: phase1InstanceIDs), "phase 2 must get brand-new ProgramInstances, never continuing phase 1's own")

        // --- Point 13: no instance-specific state leaks into the new instances.
        for instance in phase2.programInstances {
            XCTAssertTrue(instance.slotSelectionOverrides.isEmpty, "a fresh ProgramInstance must never inherit slot overrides from a different phase's instance")
        }

        // --- Point 8: phase 1's history is byte-for-byte unchanged after the transition.
        XCTAssertEqual(phase1.status, .completed)
        let survivingProfile = try XCTUnwrap(performanceProfile.profile(for: historyExercise))
        XCTAssertEqual(survivingProfile.id, exerciseProfileIDBefore)
        XCTAssertEqual(survivingProfile.setResults.count, setResultCountBefore, "logged history must be exactly unchanged by the transition")
        XCTAssertEqual(survivingProfile.personalRecords.count, personalRecordCountBefore)
        let phase1SessionIDsAfter = Set(phase1.programInstances.flatMap(\.sessions).map(\.id))
        XCTAssertEqual(phase1SessionIDsAfter, phase1SessionIDsBefore, "phase 1's own Sessions must survive exactly, never deleted/replaced")
        for (sessionID, dateBefore) in phase1SessionDatesBefore {
            let sessionAfter = phase1.programInstances.flatMap(\.sessions).first { $0.id == sessionID }
            XCTAssertEqual(sessionAfter?.day?.date, dateBefore, "a historical session's date must never be rewritten by a later transition")
        }

        // --- Point 12: real, legitimately-global history remains available to the NEW phase's own materialization/PerformanceProfile lookups.
        XCTAssertEqual(performanceProfile.profile(for: historyExercise)?.id, exerciseProfileIDBefore, "the same global PerformanceProfile — never reset merely because the phase changed")

        // --- Point 14: PlannerDecision lineage explains the whole story.
        let allDecisions = try context.fetch(FetchDescriptor<PlannerDecision>())
        XCTAssertTrue(allDecisions.contains { $0.id == phase1DecisionIDsBefore.first }, "phase 1's own original 'why this phase/program' decisions must still be queryable — explains why phase 1 existed")
        let transitionDecision = try XCTUnwrap(allDecisions.first { $0.factors["outgoingPhaseID"] == phase1.id.uuidString })
        XCTAssertEqual(transitionDecision.factors["nextPhaseType"], phase2.type.rawValue, "explains why the transition occurred and to what")
        let phase2StartDecisions = allDecisions.filter { $0.phase?.id == phase2.id && $0.trainingMix?.id == mix2.mix.id }
        XCTAssertFalse(phase2StartDecisions.isEmpty, "explains which mix was accepted for the new phase")
        let phase2InstanceDecisions = allDecisions.filter { decision in phase2InstanceIDs.contains(decision.programInstance?.id ?? UUID()) }
        XCTAssertEqual(Set(phase2InstanceDecisions.map { $0.programInstance?.id }).count, 3, "explains which ProgramInstances were materialized for the new phase — one decision per component")
    }

    // MARK: 10 — tactical windows never materialize beyond their own phase's boundary

    func testTacticalWindowNeverMaterializesSessionsBeyondItsPhaseBoundary() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        let phase1 = fixture.plan.orderedPhases[0]
        guard let phaseEndDate = phase1.endDate else {
            throw XCTSkip("this plan's first phase has no bounded endDate to test against")
        }

        let candidates = makeCandidates()
        let mixCandidates = LongTermPlanner.proposeTrainingMix(phase: phase1, goal: fixture.goal)
        let mix1 = try XCTUnwrap(mixCandidates.first { $0.mix.name == "Focused Hypertrophy" })
        try StartPhaseUseCase.start(
            phase: phase1, mix: mix1.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.strength),
            context: context
        )

        for instance in phase1.programInstances {
            for session in instance.sessions {
                let sessionDate = try XCTUnwrap(session.day?.date)
                XCTAssertLessThanOrEqual(sessionDate, phaseEndDate, "no session belonging to phase 1 may be dated beyond phase 1's own endDate")
            }
        }
    }

    // MARK: Error paths — mirrors StartPhaseError's own discipline

    func testTransitionThrowsWhenOutgoingPhaseIsNotActive() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        let phase1 = fixture.plan.orderedPhases[0]
        let mix2Candidates = LongTermPlanner.proposeTrainingMix(phase: fixture.plan.orderedPhases[1], goal: fixture.goal)
        let mix2 = try XCTUnwrap(mix2Candidates.first)

        XCTAssertThrowsError(try TransitionPhaseUseCase.transition(
            from: phase1, toNextPhaseWithMix: mix2.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment), context: context
        )) { error in
            XCTAssertEqual(error as? PhaseTransitionError, .outgoingPhaseNotActive, "phase 1 is still .planned — was never started")
        }
    }

    func testTransitionThrowsWhenThereIsNoNextPhaseInThePlan() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        let lastPhase = try XCTUnwrap(fixture.plan.orderedPhases.last)
        let candidates = LongTermPlanner.proposeTrainingMix(phase: lastPhase, goal: fixture.goal)
        let mix = try XCTUnwrap(candidates.first)
        try StartPhaseUseCase.start(
            phase: lastPhase, mix: mix.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: makeCandidates().strength, functionalFitnessCandidateExercises: makeCandidates().functionalFitness),
            context: context
        )

        XCTAssertThrowsError(try TransitionPhaseUseCase.transition(
            from: lastPhase, toNextPhaseWithMix: mix.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment), context: context
        )) { error in
            XCTAssertEqual(error as? PhaseTransitionError, .noNextPhaseInPlan, "the last phase in the plan has nothing after it")
        }
    }
}
