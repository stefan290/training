import XCTest
import SwiftData
@testable import TrainingOS

/// TRAININGOS — C1: PRESERVE ATHLETE CAPABILITY ON TACTICAL ADVANCEMENT.
/// Proves the real, previously-broken journey end to end: the real
/// `PhaseDetailViewModel.advanceTacticalWeek` production call must use
/// `primaryInstance.ownerUserID`'s own persisted `PerformanceProfile` —
/// never `nil`, never `users.first`, never another user's evidence.
/// Exercises the exact real production entry point (never the
/// materializer directly), the real 5FF Muscle programming path, and the
/// real `MovementCapabilityCollectionViewModel` save flow.
@MainActor
final class AdvanceTacticalWeekCapabilityWiringTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

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

    // MARK: - Real production path helpers (same established pattern as
    // GeneralProgrammingAllocationArchitectureTests/DogfoodRound2CompletionTests)

    @discardableResult
    private func makeOnboardedAthlete(trainingDays: Int = 5) throws -> (user: User, goal: Goal) {
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        user.profile?.trainingEnvironments = [environment]
        user.profile?.defaultTrainingEnvironment = environment
        let goal = Goal(
            ownerUserID: user.id, primaryType: .muscleGain,
            preferences: GoalPreferences(availableTrainingDaysPerWeek: trainingDays, allowsDoubleSessions: false)
        )
        context.insert(goal)
        user.addGoal(goal)
        try context.save()
        return (user, goal)
    }

    private func loadedViewModel(referenceDate: Date) -> StrategicPlanSelectionViewModel {
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context, referenceDate: referenceDate)
        return viewModel
    }

    private func completeAnyCalibration(goal: Goal, trainingDays: Int, asOf: Date) throws {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let environment = goal.user?.profile?.defaultTrainingEnvironment
        guard let phase = goal.plans.first?.orderedPhases.first else { return }
        try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: phase, performanceProfile: goal.user?.performanceProfile,
            availability: UserAvailability(trainingDaysPerWeek: trainingDays, allowsDoubleSessions: false, maxSessionsPerDay: 1),
            materializationContext: TacticalMaterializationContext(
                equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
                strengthCandidateExercises: exercises, functionalFitnessCandidateExercises: exercises,
                trainingEnvironment: environment
            ),
            asOf: asOf, context: context
        )
    }

    /// Through the real `MovementCapabilityCollectionViewModel` — never a
    /// direct `RecordMovementCapabilityUseCase` call as a substitute.
    private func saveCapabilityThroughRealViewModel(name: String, reps: Int) throws {
        let viewModel = MovementCapabilityCollectionViewModel()
        viewModel.load(modelContext: context)
        let row = try XCTUnwrap(viewModel.rows.first { $0.exercise.canonicalName == name }, "expected \(name) among the real gated movements")
        viewModel.setWorkoutReady(true, for: row.id)
        viewModel.setMaxUnbrokenReps(reps, for: row.id)
        XCTAssertTrue(viewModel.save(modelContext: context), "real capability save must succeed")
    }

    private func makeWeekTerminal(mix: TrainingMix) throws {
        for component in mix.orderedComponents {
            for session in component.programInstance?.sessions ?? [] {
                try ChangeSessionStatusUseCase.skip(session, modelContext: context)
            }
        }
        try context.save()
    }

    // MARK: - The real, end-to-end journey

    /// Builds the real 5FF Muscle programming path, saves real capability
    /// evidence (TTB7/Pull-up5/HSPU3) through the real collection
    /// ViewModel, makes the current week terminal, then invokes the real
    /// `PhaseDetailViewModel.advanceTacticalWeek` production call and
    /// inspects the newly materialized week.
    ///
    /// **Before the C1 fix, this test fails** — `advanceTacticalWeek`
    /// passed `performanceProfile: nil`, so Toes-to-Bar's Trunk-role
    /// prescription materializes with its raw, unclamped authored target
    /// (15 reps) instead of the real capacity-7 ceiling (3).
    func testAdvanceTacticalWeekUsesOwnersPersistedCapabilityEvidence() throws {
        let monday = date(2026, 1, 5)
        let (user, goal) = try makeOnboardedAthlete(trainingDays: 5)
        let viewModel = loadedViewModel(referenceDate: monday)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.functionalFitness, 5)]))
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))
        try completeAnyCalibration(goal: goal, trainingDays: 5, asOf: monday)

        try saveCapabilityThroughRealViewModel(name: "Toes-to-Bar", reps: 7)
        try saveCapabilityThroughRealViewModel(name: "Pull-up", reps: 5)
        try saveCapabilityThroughRealViewModel(name: "Handstand Push-up", reps: 3)

        guard let phase = goal.plans.first?.orderedPhases.first else { return XCTFail("no phase") }
        let mix = try XCTUnwrap(phase.selectedTrainingMix ?? phase.recommendedTrainingMix)

        let oldSessionIDs = Set(mix.orderedComponents.flatMap { $0.programInstance?.sessions.map(\.id) ?? [] })
        XCTAssertFalse(oldSessionIDs.isEmpty, "precondition: week 0 must already be real, materialized sessions")

        // Requirement 4 (C1 review follow-up): record a REAL, persisted
        // training result on one of the terminal week's sessions, through
        // the real production logging path (`LogSetUseCase` — "the only
        // entry point the set logging UI should call," never
        // `RecordSetResultUseCase` directly, never a hand-constructed
        // `SetResult` bypassing it) — then prove it, and every earlier
        // session's own prescription data, survives advancement
        // byte-for-byte/field-for-field unchanged.
        let oldSessionsBeforeAdvancement = mix.orderedComponents.flatMap { $0.programInstance?.sessions ?? [] }
        let loggedPrescription = try XCTUnwrap(
            oldSessionsBeforeAdvancement.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).first { $0.exercise != nil },
            "precondition: week 0 must contain a real, resolved resistance prescription to log a result against"
        )
        let loggedExercise = try XCTUnwrap(loggedPrescription.exercise)
        let performanceProfileForLogging = try XCTUnwrap(user.performanceProfile)
        let loggedCompletedAt = try XCTUnwrap(Calendar.current.date(byAdding: .hour, value: 1, to: monday))
        let (loggedResult, _) = try LogSetUseCase.logSet(
            setIndex: 0, weight: 42.5, reps: 8, targetRir: 2, actualRir: 1, prBand: nil,
            scoringDirection: .higherIsBetter, context: .rx,
            setPrescription: loggedPrescription.orderedSetPrescriptions.first,
            exercisePrescription: loggedPrescription, exercise: loggedExercise,
            performanceProfile: performanceProfileForLogging, completedAt: loggedCompletedAt, modelContext: context
        )
        let loggedResultID = loggedResult.id
        // Snapshot of the PRESCRIPTION data itself, independent of the
        // logged result — every earlier session's authored content must
        // also survive untouched.
        let oldPrescriptionSnapshot: [(sessionID: UUID, exerciseID: UUID?, setCount: Int, repLows: [Int?], repHighs: [Int?])] = oldSessionsBeforeAdvancement.map { session in
            let allSets = session.orderedBlocks.flatMap(\.orderedPrescriptions)
            return (
                sessionID: session.id,
                exerciseID: allSets.first?.exercise?.id,
                setCount: allSets.reduce(0) { $0 + $1.orderedSetPrescriptions.count },
                repLows: allSets.flatMap(\.orderedSetPrescriptions).map(\.repRangeLow),
                repHighs: allSets.flatMap(\.orderedSetPrescriptions).map(\.repRangeHigh)
            )
        }

        try makeWeekTerminal(mix: mix)

        let phaseDetailViewModel = PhaseDetailViewModel()
        phaseDetailViewModel.load(phase: phase, modelContext: context)
        let advanceAsOf = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: monday))
        let advanced = phaseDetailViewModel.advanceTacticalWeek(modelContext: context, asOf: advanceAsOf)

        // 1. Advancement actually succeeded.
        XCTAssertTrue(advanced, "tactical advancement must succeed for a legitimately terminal week")

        let newSessionIDs = Set(mix.orderedComponents.flatMap { $0.programInstance?.sessions.map(\.id) ?? [] })
        let addedSessionIDs = newSessionIDs.subtracting(oldSessionIDs)

        // 2. Newly created session IDs and week differ from the previous week.
        XCTAssertFalse(addedSessionIDs.isEmpty, "a real new week must have materialized new sessions with new IDs")

        let newSessions = mix.orderedComponents.flatMap { component in
            (component.programInstance?.sessions ?? []).filter { addedSessionIDs.contains($0.id) }
        }
        XCTAssertFalse(newSessions.isEmpty)

        // 3. The real TTB resistance prescription is present and its
        // prescribed rep bounds do not exceed 3 (capacity 7 -> ceiling 3).
        // Toes-to-Bar is the ONLY real catalog exercise carrying `.trunk`,
        // so the lowerFatigueComplementary session's Trunk accessory role
        // deterministically resolves to it.
        let ttbPrescriptions = newSessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions)
            .filter { $0.exercise?.canonicalName == "Toes-to-Bar" }
        XCTAssertFalse(ttbPrescriptions.isEmpty, "Toes-to-Bar must materialize as a real resistance-role prescription this week (never omitted, never vacuously passing this assertion)")
        // Requirement 2 (C1 review follow-up): mandatory, never-vacuous
        // dosing proof. A missing rep bound, an empty set list, or a
        // non-positive value must all FAIL this test — never silently
        // skip the real assertion the way `if let` did before.
        for prescription in ttbPrescriptions {
            XCTAssertFalse(prescription.orderedSetPrescriptions.isEmpty, "TTB must carry real, non-empty set prescriptions")
            for setPrescription in prescription.orderedSetPrescriptions {
                let low = try XCTUnwrap(setPrescription.repRangeLow, "TTB's set prescription must carry a real repRangeLow — a missing value must fail this test, never silently pass")
                let high = try XCTUnwrap(setPrescription.repRangeHigh, "TTB's set prescription must carry a real repRangeHigh — a missing value must fail this test, never silently pass")
                XCTAssertGreaterThan(low, 0, "a real, non-degenerate rep target must be positive")
                XCTAssertGreaterThan(high, 0, "a real, non-degenerate rep target must be positive")
                XCTAssertLessThanOrEqual(low, 3, "TTB's prescribed rep bound must be clamped to the real capacity-7 ceiling (3) — the raw authored target is 15, unclamped only when performanceProfile is nil")
                XCTAssertLessThanOrEqual(high, 3, "TTB's prescribed rep bound must be clamped to the real capacity-7 ceiling (3)")
            }
        }

        // 4. Pull-up does not become a conditioning dependency with
        // capacity 5 (existing, unchanged TechnicalCapacityDoseAuthority
        // table: capacity 5 -> no approved ceiling -> not conditioning-eligible).
        let conditioningMovements = newSessions.flatMap(\.orderedBlocks).compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements)
        XCTAssertFalse(conditioningMovements.contains { $0.exercise?.canonicalName == "Pull-up" }, "capacity 5 maps to no approved repeated-dose ceiling — Pull-up must never become a real conditioning dependency this week")

        // 5. Saved capability remains unchanged.
        let performanceProfile = try XCTUnwrap(user.performanceProfile)
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let ttbCapability = try XCTUnwrap(performanceProfile.movementCapability(for: catalog.toesToBar))
        XCTAssertEqual(ttbCapability.proficiency, .workoutReady)
        XCTAssertEqual(ttbCapability.capacityValue, 7)
        let pullUpCapability = try XCTUnwrap(performanceProfile.movementCapability(for: catalog.pullUp))
        XCTAssertEqual(pullUpCapability.proficiency, .workoutReady)
        XCTAssertEqual(pullUpCapability.capacityValue, 5)
        let hspuCapability = try XCTUnwrap(performanceProfile.movementCapability(for: catalog.handstandPushUp))
        XCTAssertEqual(hspuCapability.proficiency, .workoutReady)
        XCTAssertEqual(hspuCapability.capacityValue, 3)

        // 6. Earlier sessions and actual results remain unchanged.
        let oldSessions = mix.orderedComponents.flatMap { component in
            (component.programInstance?.sessions ?? []).filter { oldSessionIDs.contains($0.id) }
        }
        XCTAssertEqual(oldSessions.count, oldSessionIDs.count, "no earlier session may be deleted/replaced by advancement")
        XCTAssertTrue(oldSessions.allSatisfy { $0.status == .skipped }, "earlier sessions' own status must remain exactly what this test set it to — never silently reset by advancement")

        // Requirement 4 (C1 review follow-up): the real, persisted
        // training result logged above through `LogSetUseCase` must
        // survive advancement byte-for-byte/field-for-field — and every
        // earlier session's own authored prescription data (exercise, set
        // count, rep ranges) must remain exactly what it was before.
        let reloadedResult = try XCTUnwrap(
            context.fetch(FetchDescriptor<SetResult>(predicate: #Predicate { $0.id == loggedResultID })).first,
            "the real logged result must still exist, unchanged, after advancement"
        )
        XCTAssertEqual(reloadedResult.setIndex, 0)
        XCTAssertEqual(reloadedResult.weight, 42.5)
        XCTAssertEqual(reloadedResult.reps, 8)
        XCTAssertEqual(reloadedResult.targetRir, 2)
        XCTAssertEqual(reloadedResult.actualRir, 1)
        XCTAssertEqual(reloadedResult.completedAt, loggedCompletedAt)
        XCTAssertEqual(reloadedResult.exercisePrescription?.id, loggedPrescription.id, "the logged result's own prescription linkage must remain exactly what it was")

        let newPrescriptionSnapshot: [(sessionID: UUID, exerciseID: UUID?, setCount: Int, repLows: [Int?], repHighs: [Int?])] = oldSessions.map { session in
            let allSets = session.orderedBlocks.flatMap(\.orderedPrescriptions)
            return (
                sessionID: session.id,
                exerciseID: allSets.first?.exercise?.id,
                setCount: allSets.reduce(0) { $0 + $1.orderedSetPrescriptions.count },
                repLows: allSets.flatMap(\.orderedSetPrescriptions).map(\.repRangeLow),
                repHighs: allSets.flatMap(\.orderedSetPrescriptions).map(\.repRangeHigh)
            )
        }
        XCTAssertEqual(oldPrescriptionSnapshot.count, newPrescriptionSnapshot.count)
        for old in oldPrescriptionSnapshot {
            let new = try XCTUnwrap(newPrescriptionSnapshot.first { $0.sessionID == old.sessionID }, "every earlier session must still be present")
            XCTAssertEqual(new.exerciseID, old.exerciseID, "session \(old.sessionID): prescribed exercise must not change")
            XCTAssertEqual(new.setCount, old.setCount, "session \(old.sessionID): prescribed set count must not change")
            XCTAssertEqual(new.repLows, old.repLows, "session \(old.sessionID): prescribed rep-range-low values must not change")
            XCTAssertEqual(new.repHighs, old.repHighs, "session \(old.sessionID): prescribed rep-range-high values must not change")
        }

        // Small trace: owner, capability, old/new session IDs, newly prescribed TTB reps.
        print("C1 TRACE: owner=\(user.id) ttbCapacity=7 pullUpCapacity=5 hspuCapacity=3")
        print("C1 TRACE: oldSessionIDs=\(oldSessionIDs.map(\.uuidString).sorted())")
        print("C1 TRACE: newSessionIDs=\(addedSessionIDs.map(\.uuidString).sorted())")
        print("C1 TRACE: ttbPrescribedReps=\(ttbPrescriptions.flatMap(\.orderedSetPrescriptions).map { ($0.repRangeLow, $0.repRangeHigh) })")
    }

    // MARK: - Additional verification 1: fresh context reload

    func testAdvanceTacticalWeekUsesOwnersCapabilityAfterReloadingInAFreshContext() throws {
        let monday = date(2026, 1, 5)
        let (_, goal) = try makeOnboardedAthlete(trainingDays: 5)
        let viewModel = loadedViewModel(referenceDate: monday)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.functionalFitness, 5)]))
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))
        try completeAnyCalibration(goal: goal, trainingDays: 5, asOf: monday)
        try saveCapabilityThroughRealViewModel(name: "Toes-to-Bar", reps: 7)

        guard let phase = goal.plans.first?.orderedPhases.first else { return XCTFail("no phase") }
        let mix = try XCTUnwrap(phase.selectedTrainingMix ?? phase.recommendedTrainingMix)
        // Week 0 materialized BEFORE capability was saved above — its own
        // TTB prescription (if any) is legitimately unclamped at the time
        // it was authored; only the NEWLY materialized week must be
        // checked here, exactly like the primary journey test.
        let oldSessionIDs = Set(mix.orderedComponents.flatMap { $0.programInstance?.sessions.map(\.id) ?? [] })
        try makeWeekTerminal(mix: mix)
        try context.save()

        // Requirement 1 (C1 review follow-up): a GENUINELY separate
        // `ModelContext` — `container.mainContext` returns the SAME
        // shared main-actor context every time, which would not actually
        // prove anything about a fresh reload. `ModelContext(container)`
        // is a real, distinct context instance over the same persisted
        // store — a brand-new identity map, exactly like a real app
        // relaunch would construct. Proven below via object identity
        // (`!==`), not merely asserted in a comment.
        let freshContext = ModelContext(container)
        XCTAssertFalse(freshContext === context, "the fresh context must be a genuinely different ModelContext instance from the original setup context")
        let freshGoalID = goal.id
        let freshGoal = try XCTUnwrap(freshContext.fetch(FetchDescriptor<Goal>(predicate: #Predicate { $0.id == freshGoalID })).first)
        let freshPhase = try XCTUnwrap(freshGoal.plans.first?.orderedPhases.first)

        let freshViewModel = PhaseDetailViewModel()
        freshViewModel.load(phase: freshPhase, modelContext: freshContext)
        let advanceAsOf = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: monday))
        let advanced = freshViewModel.advanceTacticalWeek(modelContext: freshContext, asOf: advanceAsOf)
        XCTAssertTrue(advanced)

        let freshMix = try XCTUnwrap(freshPhase.selectedTrainingMix ?? freshPhase.recommendedTrainingMix)
        let newSessionIDs = Set(freshMix.orderedComponents.flatMap { $0.programInstance?.sessions.map(\.id) ?? [] }).subtracting(oldSessionIDs)
        let newSessions = freshMix.orderedComponents.flatMap { component in
            (component.programInstance?.sessions ?? []).filter { newSessionIDs.contains($0.id) }
        }
        let ttbPrescriptions = newSessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).filter { $0.exercise?.canonicalName == "Toes-to-Bar" }
        XCTAssertFalse(ttbPrescriptions.isEmpty)
        for prescription in ttbPrescriptions {
            XCTAssertFalse(prescription.orderedSetPrescriptions.isEmpty, "TTB must carry real, non-empty set prescriptions")
            for setPrescription in prescription.orderedSetPrescriptions {
                let low = try XCTUnwrap(setPrescription.repRangeLow, "a missing rep bound must fail this test, never silently pass")
                XCTAssertGreaterThan(low, 0, "a real, non-degenerate rep target must be positive")
                XCTAssertLessThanOrEqual(low, 3, "capability evidence must still reach materialization after a fresh ModelContext/ViewModel reload")
            }
        }
    }

    // MARK: - Additional verification 2: a second user's evidence must never be used

    func testAdvancementUsesTheProgramOwnersEvidenceNeverASecondUsersEvidence() throws {
        let monday = date(2026, 1, 5)
        let (owner, goal) = try makeOnboardedAthlete(trainingDays: 5)
        let viewModel = loadedViewModel(referenceDate: monday)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.functionalFitness, 5)]))
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))
        try completeAnyCalibration(goal: goal, trainingDays: 5, asOf: monday)

        // The real owner's own real evidence — capacity 7.
        try saveCapabilityThroughRealViewModel(name: "Toes-to-Bar", reps: 7)

        // A second, unrelated user with DIFFERENT capability evidence —
        // if `advanceTacticalWeek` ever fell back to `users.first` (or
        // any user other than the real program owner), this is what
        // would leak through.
        let otherUser = User(displayName: "Other Athlete")
        context.insert(otherUser)
        let otherUserProfile = UserProfile()
        context.insert(otherUserProfile)
        otherUser.attachProfile(otherUserProfile)
        let otherEnvironment = TrainingEnvironment.fullGym()
        context.insert(otherEnvironment)
        otherUserProfile.trainingEnvironments = [otherEnvironment]
        otherUserProfile.defaultTrainingEnvironment = otherEnvironment
        let otherProfile = PerformanceProfile()
        context.insert(otherProfile)
        otherUser.attachPerformanceProfile(otherProfile)
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let otherCapability = MovementCapabilityProfile(
            exercise: catalog.toesToBar, proficiency: .workoutReady, capacityType: .maxUnbrokenReps, capacityValue: 20,
            evidenceSource: .selfReported
        )
        context.insert(otherCapability)
        otherProfile.addMovementCapability(otherCapability)
        try context.save()

        guard let phase = goal.plans.first?.orderedPhases.first else { return XCTFail("no phase") }
        let mix = try XCTUnwrap(phase.selectedTrainingMix ?? phase.recommendedTrainingMix)
        // Week 0 materialized BEFORE capability was saved above — only the
        // NEWLY materialized week must be checked, exactly like the
        // primary journey test.
        let oldSessionIDs = Set(mix.orderedComponents.flatMap { $0.programInstance?.sessions.map(\.id) ?? [] })
        try makeWeekTerminal(mix: mix)

        let phaseDetailViewModel = PhaseDetailViewModel()
        phaseDetailViewModel.load(phase: phase, modelContext: context)
        let advanceAsOf = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: monday))
        XCTAssertTrue(phaseDetailViewModel.advanceTacticalWeek(modelContext: context, asOf: advanceAsOf))

        let newSessionIDs = Set(mix.orderedComponents.flatMap { $0.programInstance?.sessions.map(\.id) ?? [] }).subtracting(oldSessionIDs)
        let newSessions = mix.orderedComponents.flatMap { component in
            (component.programInstance?.sessions ?? []).filter { newSessionIDs.contains($0.id) }
        }
        let ttbPrescriptions = newSessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions).filter { $0.exercise?.canonicalName == "Toes-to-Bar" }
        XCTAssertFalse(ttbPrescriptions.isEmpty)
        // Requirement 2 (C1 review follow-up, applied consistently here
        // too): mandatory, never-vacuous dosing proof — a missing rep
        // bound, an empty set list, or a non-positive value must all FAIL
        // this test, never silently pass.
        for prescription in ttbPrescriptions {
            XCTAssertFalse(prescription.orderedSetPrescriptions.isEmpty, "TTB must carry real, non-empty set prescriptions")
            for setPrescription in prescription.orderedSetPrescriptions {
                let low = try XCTUnwrap(setPrescription.repRangeLow, "TTB's set prescription must carry a real repRangeLow — a missing value must fail this test, never silently pass")
                let high = try XCTUnwrap(setPrescription.repRangeHigh, "TTB's set prescription must carry a real repRangeHigh — a missing value must fail this test, never silently pass")
                XCTAssertGreaterThan(low, 0, "a real, non-degenerate rep target must be positive")
                XCTAssertGreaterThan(high, 0, "a real, non-degenerate rep target must be positive")
                XCTAssertLessThanOrEqual(low, 3, "must use the real program owner's capacity-7 ceiling (3), never the other user's capacity-20 ceiling (8)")
                XCTAssertLessThanOrEqual(high, 3, "must use the real program owner's capacity-7 ceiling (3), never the other user's capacity-20 ceiling (8)")
            }
        }
        XCTAssertEqual(try XCTUnwrap(owner.performanceProfile).movementCapability(for: catalog.toesToBar)?.capacityValue, 7, "the real owner's own evidence must remain exactly what was saved")
    }

    // MARK: - Additional verification 3: repeated immediate advancement creates no additional week

    func testRepeatedImmediateAdvancementCreatesNoAdditionalWeek() throws {
        let monday = date(2026, 1, 5)
        let (_, goal) = try makeOnboardedAthlete(trainingDays: 5)
        let viewModel = loadedViewModel(referenceDate: monday)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.functionalFitness, 5)]))
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))
        try completeAnyCalibration(goal: goal, trainingDays: 5, asOf: monday)
        try saveCapabilityThroughRealViewModel(name: "Toes-to-Bar", reps: 7)

        guard let phase = goal.plans.first?.orderedPhases.first else { return XCTFail("no phase") }
        let mix = try XCTUnwrap(phase.selectedTrainingMix ?? phase.recommendedTrainingMix)
        try makeWeekTerminal(mix: mix)

        let phaseDetailViewModel = PhaseDetailViewModel()
        phaseDetailViewModel.load(phase: phase, modelContext: context)
        let advanceAsOf = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: monday))
        XCTAssertTrue(phaseDetailViewModel.advanceTacticalWeek(modelContext: context, asOf: advanceAsOf))

        let sessionIDsAfterFirstAdvance = Set(mix.orderedComponents.flatMap { $0.programInstance?.sessions.map(\.id) ?? [] })

        // Repeated, immediate advancement — the new week is NOT terminal
        // yet (nothing skipped/completed) — must be a genuine no-op,
        // never a second materialization.
        phaseDetailViewModel.load(phase: phase, modelContext: context)
        let secondAdvanced = phaseDetailViewModel.advanceTacticalWeek(modelContext: context, asOf: advanceAsOf)
        XCTAssertFalse(secondAdvanced, "a second immediate advancement, with the new week not yet terminal, must not succeed")

        let sessionIDsAfterSecondAttempt = Set(mix.orderedComponents.flatMap { $0.programInstance?.sessions.map(\.id) ?? [] })
        XCTAssertEqual(sessionIDsAfterFirstAdvance, sessionIDsAfterSecondAttempt, "repeated immediate advancement must create no additional week — existing atomicity/idempotency guarantees preserved")
    }
}
