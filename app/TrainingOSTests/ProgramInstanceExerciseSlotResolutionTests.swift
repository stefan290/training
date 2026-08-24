import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 7 (Tactical Planning Orchestration), GAP A: before this pass,
/// nothing ever resolved a Hypertrophy/Powerlifting `ExerciseSlot` to a
/// concrete `Exercise` for a real (non-seed) generated program —
/// `SubstituteExerciseUseCase.resolvedExercise` always returned `nil`.
/// `ResolveProgramInstanceExerciseSlotsUseCase` closes that gap by picking
/// the deterministic first-eligible candidate (by `canonicalName`) from a
/// caller-supplied pool, once, at `ProgramInstance` creation — exactly
/// mirroring `FunctionalFitnessMaterializer`'s already-established
/// "first candidate satisfying the slot's typed constraints" rule, reusing
/// the same `SubstitutionValidator.isValid` eligibility check everywhere
/// else in the codebase already uses.
@MainActor
final class ProgramInstanceExerciseSlotResolutionTests: XCTestCase {
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

    /// 5 disjoint-tagged candidates: exactly one is eligible for any given
    /// `HypertrophyProgramGenerator` primary slot (whichever split wins —
    /// `fullBody`/`armsShoulders` both use `.shoulders`, `legs` uses
    /// `.quadriceps`, `backChest` uses `.back`) and exactly two
    /// (`pairedAccessory`/`pairedAccessoryAlt`) are eligible for the
    /// paired/accessory slot (`[.chest, .triceps]`, constant across every
    /// split) — deliberately non-overlapping tag sets so which exercise
    /// resolves is never ambiguous regardless of which built-in candidate
    /// `LongTermPlanner.proposeProgram` ranks first.
    private struct SlotCandidates {
        let primaryShoulders: Exercise
        let primaryQuads: Exercise
        let primaryBack: Exercise
        let pairedAccessory: Exercise
        let pairedAccessoryAlt: Exercise
        var all: [Exercise] { [primaryShoulders, primaryQuads, primaryBack, pairedAccessory, pairedAccessoryAlt] }
    }

    private func makeCandidates() -> SlotCandidates {
        func exercise(_ name: String, _ targets: [MuscleGroup]) -> Exercise {
            let ex = Exercise(canonicalName: name, modality: .hypertrophy, equipment: "barbell", movementPattern: "test", primaryTargets: targets)
            context.insert(ex)
            return ex
        }
        return SlotCandidates(
            primaryShoulders: exercise("Zzz Test Primary Shoulders", [.shoulders]),
            primaryQuads: exercise("Zzz Test Primary Quads", [.quadriceps]),
            primaryBack: exercise("Zzz Test Primary Back", [.back]),
            pairedAccessory: exercise("Zzz Test Paired Accessory", [.chest, .triceps]),
            pairedAccessoryAlt: exercise("Zzz Test Paired Accessory Alt", [.chest, .triceps])
        )
    }

    private func makeAcceptedPlan(asOf: Date) throws -> (goal: Goal, phase: TrainingPhase) {
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .generalStrength, targetDate: Calendar.current.date(byAdding: .year, value: 1, to: asOf), createdAt: asOf)
        context.insert(goal)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: asOf)
        let phase = try XCTUnwrap(plan.orderedPhases.first)
        return (goal, phase)
    }

    private func availability() -> UserAvailability {
        UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1)
    }

    // MARK: Regression — distinct slots in the same session never collapse to the same concrete Exercise

    /// Stage 7 Slice 4 acceptance finding: a `.fullBody` split's primary
    /// slot (targets `[.chest, .shoulders]`) and its paired accessory
    /// slot (targets `[.chest, .triceps]`) both validated for
    /// `ExerciseCatalog`'s real "Barbell Bench Press"/"Incline Dumbbell
    /// Press" (both tagged `[.chest, .triceps]`) — with no
    /// already-used-exercise tracking, both slots independently picked
    /// the alphabetically-first eligible candidate, "Barbell Bench
    /// Press," for BOTH the compound press and the "isolation" accessory
    /// in the same session. `ResolveProgramInstanceExerciseSlotsUseCase`
    /// must prefer a distinct eligible alternative within one session.
    func testDistinctSlotsInTheSameSessionResolveToDifferentExercisesWhenAnAlternativeExists() throws {
        let benchPress = Exercise(canonicalName: "Barbell Bench Press", modality: .hypertrophy, equipment: "barbell", movementPattern: "horizontalPush", primaryTargets: [.chest, .triceps])
        let inclineDumbbellPress = Exercise(canonicalName: "Incline Dumbbell Press", modality: .hypertrophy, equipment: "dumbbell", movementPattern: "horizontalPush", primaryTargets: [.chest, .triceps])
        context.insert(benchPress)
        context.insert(inclineDumbbellPress)

        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 1, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test"), context: context
        )
        ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: [benchPress, inclineDumbbellPress])

        let templates = try XCTUnwrap(definition.orderedTemplateSessions.first).orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates)
        let primary = try XCTUnwrap(templates.first { $0.exerciseSlot?.name != "Chest Isolation or Triceps" })
        let paired = try XCTUnwrap(templates.first { $0.exerciseSlot?.name == "Chest Isolation or Triceps" })

        XCTAssertNotNil(primary.exerciseSlot?.resolvedExercise)
        XCTAssertNotNil(paired.exerciseSlot?.resolvedExercise)
        XCTAssertNotEqual(
            primary.exerciseSlot?.resolvedExercise?.id, paired.exerciseSlot?.resolvedExercise?.id,
            "a compound press slot and its own accessory slot must not both silently resolve to the same concrete exercise when a distinct eligible alternative exists"
        )
    }

    /// The distinctness preference must never leave a slot unresolved —
    /// when NO alternative exists, reusing the sole eligible candidate is
    /// still strictly better than a `.calibrationRequired` slot that
    /// could have been filled.
    func testDuplicateResolutionFallsBackToReuseOnlyWhenNoDistinctAlternativeExists() throws {
        let onlyCandidate = Exercise(canonicalName: "Barbell Bench Press", modality: .hypertrophy, equipment: "barbell", movementPattern: "horizontalPush", primaryTargets: [.chest, .triceps])
        context.insert(onlyCandidate)

        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 1, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test"), context: context
        )
        ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: [onlyCandidate])

        let templates = try XCTUnwrap(definition.orderedTemplateSessions.first).orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates)
        for template in templates {
            XCTAssertEqual(template.exerciseSlot?.resolvedExercise?.id, onlyCandidate.id, "resolving something is strictly better than leaving a slot nil merely to enforce distinctness")
        }
    }

    // MARK: A — a real generated ProgramInstance resolves every required slot

    func testRealGeneratedProgramInstanceResolvesEverySlotToAValidConcreteExercise() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        let candidates = makeCandidates()
        let mixCandidates = LongTermPlanner.proposeTrainingMix(phase: fixture.phase, goal: fixture.goal)
        let recommended = try XCTUnwrap(mixCandidates.first { $0.roles.contains(.recommended) })

        try StartPhaseUseCase.start(
            phase: fixture.phase, mix: recommended.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.all),
            context: context
        )

        let instance = try XCTUnwrap(fixture.phase.primaryInstance)
        let prescriptions = instance.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions)
        XCTAssertFalse(prescriptions.isEmpty)

        for prescription in prescriptions {
            let exercise = try XCTUnwrap(prescription.exercise, "every real prescription must have resolved a concrete Exercise")
            let slot = try XCTUnwrap(prescription.sourceExerciseSlot)
            XCTAssertTrue(SubstitutionValidator.isValid(candidate: exercise, for: slot), "\(exercise.canonicalName) must actually be eligible for slot \(slot.name)")
        }
    }

    // MARK: B — deterministic for identical inputs

    func testSlotResolutionIsDeterministicForIdenticalInputs() throws {
        let candidates = makeCandidates()
        // dayCount: 1 — every slot name is unique within the definition
        // (a multi-day fullBody config repeats "Horizontal Push"/"Chest
        // Isolation or Triceps" once per day, which isn't what this test
        // is comparing).
        let configuration = HypertrophyProgramConfiguration(dayCount: 1, split: .fullBody, phaseType: .basicHypertrophy)

        let definitionA = try HypertrophyProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test A"), context: context)
        let definitionB = try HypertrophyProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test B"), context: context)

        ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definitionA, candidateExercises: candidates.all)
        ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definitionB, candidateExercises: candidates.all)

        func resolvedNamesBySlotName(_ definition: ProgramDefinition) -> [String: String] {
            let slots = definition.orderedTemplateSessions.flatMap(\.orderedBlockTemplates).flatMap(\.orderedPrescriptionTemplates).compactMap(\.exerciseSlot)
            return Dictionary(uniqueKeysWithValues: slots.map { ($0.name, $0.resolvedExercise?.canonicalName ?? "") })
        }

        XCTAssertEqual(resolvedNamesBySlotName(definitionA), resolvedNamesBySlotName(definitionB))
        XCTAssertTrue(resolvedNamesBySlotName(definitionA).values.allSatisfy { !$0.isEmpty }, "every slot in this fixture has an eligible candidate")
    }

    // MARK: C — idempotent, and an already-resolved slot is never overwritten

    func testResolutionNeverOverwritesAnAlreadyResolvedSlot() throws {
        let candidates = makeCandidates()
        let configuration = HypertrophyProgramConfiguration(dayCount: 3, split: .legs, phaseType: .basicHypertrophy)
        let definition = try HypertrophyProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)

        let firstSlot = try XCTUnwrap(definition.orderedTemplateSessions.first?.orderedBlockTemplates.first?.orderedPrescriptionTemplates.first?.exerciseSlot)
        firstSlot.resolvedExercise = candidates.primaryBack // deliberately NOT a valid quads candidate — proves it's left alone, not "corrected"

        ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: candidates.all)

        XCTAssertEqual(firstSlot.resolvedExercise?.id, candidates.primaryBack.id, "an already-resolved slot must never be overwritten, even if a caller's pre-existing choice looks stale")
    }

    // MARK: D — deletion invariants: resolving a slot never puts real history at risk

    func testDeletingTheProgramDefinitionAfterSlotResolutionNeverDeletesLoggedHistoryOrTheExercise() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        let candidates = makeCandidates()
        let mixCandidates = LongTermPlanner.proposeTrainingMix(phase: fixture.phase, goal: fixture.goal)
        let recommended = try XCTUnwrap(mixCandidates.first { $0.roles.contains(.recommended) })
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)

        try StartPhaseUseCase.start(
            phase: fixture.phase, mix: recommended.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: performanceProfile, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.all),
            context: context
        )

        let instance = try XCTUnwrap(fixture.phase.primaryInstance)
        let prescription = try XCTUnwrap(instance.sessions.first?.orderedBlocks.first?.orderedPrescriptions.first)
        let exercise = try XCTUnwrap(prescription.exercise)
        let exerciseID = exercise.id
        let setPrescription = try XCTUnwrap(prescription.orderedSetPrescriptions.first)

        RecordSetResultUseCase.recordSet(
            setIndex: 0, weight: 60, reps: 8, targetRir: 2, actualRir: 2, prBand: nil, scoringDirection: .higherIsBetter,
            context: .rx, setPrescription: setPrescription, exercisePrescription: prescription, exercise: exercise,
            performanceProfile: performanceProfile, completedAt: asOf, modelContext: context
        )
        let exerciseProfile = try XCTUnwrap(performanceProfile.profile(for: exercise))
        let exerciseProfileID = exerciseProfile.id
        XCTAssertEqual(exerciseProfile.setResults.count, 1)

        let definition = try XCTUnwrap(instance.programDefinition)
        context.delete(definition)
        context.delete(instance)
        try context.save()

        let survivingProfiles = try context.fetch(FetchDescriptor<ExercisePerformanceProfile>())
        let survivingProfile = try XCTUnwrap(survivingProfiles.first { $0.id == exerciseProfileID })
        XCTAssertEqual(survivingProfile.setResults.count, 1, "deleting the ProgramDefinition/ProgramInstance must never delete logged history, even for a slot-resolved (not seed-authored) exercise")

        let survivingExercises = try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == exerciseID }))
        XCTAssertEqual(survivingExercises.count, 1, "the resolved Exercise itself must never be deleted as a side effect of deleting the slot that once referenced it")
    }

    // MARK: E — missing history never blocks materialization; slot resolution is independent of PerformanceProfile

    func testMissingHistoryFallsThroughToCalibrationRequiredButNeverBlocksSlotResolutionOrMaterialization() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try makeAcceptedPlan(asOf: asOf)
        let candidates = makeCandidates()
        let mixCandidates = LongTermPlanner.proposeTrainingMix(phase: fixture.phase, goal: fixture.goal)
        let recommended = try XCTUnwrap(mixCandidates.first { $0.roles.contains(.recommended) })

        try StartPhaseUseCase.start(
            phase: fixture.phase, mix: recommended.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: TacticalMaterializationContext(equipmentProfile: equipment, strengthCandidateExercises: candidates.all),
            context: context
        )

        let instance = try XCTUnwrap(fixture.phase.primaryInstance)
        let prescriptions = instance.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions)
        XCTAssertFalse(prescriptions.isEmpty, "materialization must still succeed with no PerformanceProfile at all")

        let primary = try XCTUnwrap(prescriptions.first { $0.appliedSetCountReasonCode == .fixedSetSchedule && $0.orderedSetPrescriptions.count == 3 })
        XCTAssertNotNil(primary.exercise, "the slot must still resolve to a concrete exercise even though no history exists for it")
        XCTAssertEqual(primary.appliedLoadReasonCode, .calibrationRequired, "no history -> calibrationRequired, never a fabricated weight")
    }
}
