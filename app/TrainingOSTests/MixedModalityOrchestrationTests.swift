import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 7 (Tactical Planning Orchestration), Slice 3: proves Tactical
/// Planning can orchestrate a genuinely mixed-modality phase — 3 Strength
/// + 2 Functional Fitness + 1 Run ("Strength Plus Variety",
/// `LongTermPlanner.muscleGainVariedMix`, `ADHERENCE_AWARE_PLANNING.md`
/// §5d's own worked example) — through the REAL production path:
/// `LongTermPlanner.proposeTrainingMix`/`proposeProgram` -> `StartPhaseUseCase`
/// -> real per-system materializers -> `SchedulingPipeline`. No hand-authored
/// `ProgramDefinition`; Functional Fitness in particular had never once
/// been exercised through `StartPhaseUseCase` before this file (confirmed
/// by this stage's own architecture audit).
@MainActor
final class MixedModalityOrchestrationTests: XCTestCase {
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

    private func makeAcceptedPlan(asOf: Date) throws -> (goal: Goal, phase: TrainingPhase) {
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .muscleGain, targetDate: Calendar.current.date(byAdding: .year, value: 1, to: asOf), createdAt: asOf)
        context.insert(goal)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: asOf)
        let phase = try XCTUnwrap(plan.orderedPhases.first)
        return (goal, phase)
    }

    private func availability() -> UserAvailability {
        UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1)
    }

    /// Hypertrophy candidates (same disjoint-tag discipline as Slice 2's
    /// centerpiece test) plus a real Functional Fitness pool matching
    /// `muscleGainVariedMix`'s FF component's actual generated stimulus
    /// (`LongTermPlanner.functionalFitnessParameterCandidates`: a triplet
    /// of weightlifting/`squatLoaded`, gymnastics/`gymnasticsPull`,
    /// metabolicConditioning/`monostructural` — never guessed, read
    /// directly from the generator's own fixed candidate before writing
    /// this pool).
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
            exercise("Aaa Mixed Primary Shoulders", [.shoulders]),
            exercise("Aaa Mixed Primary Quads", [.quadriceps], [.squatLoaded]),
            exercise("Aaa Mixed Primary Back", [.back]),
            // Stage 10B: "Strength Plus Variety"'s Hypertrophy component
            // (frequency target 3) now resolves to the 3-Day Full Body
            // day-focus-driven configuration, which has more distinct
            // slot target-sets than the old single-pair-per-day shape —
            // in particular a hamstrings+glutes hinge-pattern slot, a
            // chest+shoulders press-pattern slot, and a calves accessory
            // slot, none of which the original candidates above are
            // tagged for. `.pressLoaded`/`.hingeLoaded` movement-function
            // tags (Blocker 2) are required for these to actually satisfy
            // "Horizontal Push"/"Hinge Pattern" — muscle-group overlap
            // alone is no longer sufficient.
            exercise("Zzz Mixed Paired Accessory", [.chest, .triceps], [.pressLoaded]),
            exercise("Aaa Mixed Primary Hamstrings Glutes", [.hamstrings, .glutes], [.hingeLoaded]),
            exercise("Zzz Mixed Accessory Biceps", [.biceps]),
            exercise("Zzz Mixed Accessory Calves", [.calves]),
        ]
        let ff = [
            exercise("Mixed FF Squat Lift", [], [.squatLoaded], .weightlifting),
            exercise("Mixed FF Pull-up", [], [.gymnasticsPull], .gymnastics),
            exercise("Mixed FF Bike", [], [.monostructural], .metabolicConditioning),
        ]
        return AllCandidates(strength: strength, functionalFitness: ff)
    }

    private func startVariedMix(asOf: Date) throws -> (goal: Goal, phase: TrainingPhase, mix: TrainingMix, result: StartPhaseUseCase.Result, candidates: AllCandidates) {
        let fixture = try makeAcceptedPlan(asOf: asOf)
        let mixCandidates = LongTermPlanner.proposeTrainingMix(phase: fixture.phase, goal: fixture.goal)
        let variedMix = try XCTUnwrap(mixCandidates.first { $0.mix.name == "Strength Plus Variety" }, "the real 3-Strength/2-FF/1-Run worked example must be one of the real candidates for a muscleGain phase")
        XCTAssertEqual(variedMix.mix.orderedComponents.count, 3, "sanity check on the real candidate's own shape")

        let candidates = makeCandidates()
        let materializationContext = TacticalMaterializationContext(
            equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness
        )
        let result = try StartPhaseUseCase.start(
            phase: fixture.phase, mix: variedMix.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext, context: context
        )
        return (fixture.goal, fixture.phase, variedMix.mix, result, candidates)
    }

    // MARK: 1 & 2 — a mixed-modality phase starts for real, each component keeps its own system/definition/instance

    func testMixedModalityPhaseStartInstantiatesEveryComponentWithItsOwnSystemAndProgramInstance() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try startVariedMix(asOf: asOf)

        XCTAssertEqual(fixture.result.instancesByComponent.count, 3, "all 3 components (Strength/Functional Fitness/Running) must have instantiated — none silently dropped")

        var seenDefinitionIDs = Set<UUID>()
        var seenSystems = Set<ProgrammingSystemKind>()
        for component in fixture.mix.orderedComponents {
            let instance = try XCTUnwrap(component.programInstance, "\(component.label) must have its own real ProgramInstance")
            let definition = try XCTUnwrap(instance.programDefinition)
            XCTAssertEqual(definition.programmingSystem, component.programmingSystem, "\(component.label)'s instance must be running its own component's programming system, never a different one")
            XCTAssertTrue(seenDefinitionIDs.insert(definition.id).inserted, "each component must get its OWN ProgramDefinition — never sharing one across systems")
            seenSystems.insert(component.programmingSystem!)
        }
        XCTAssertEqual(seenSystems, [.hypertrophy, .functionalFitness, .steadyState], "the real, distinct set of systems this worked example actually mixes")
    }

    // MARK: 3 — every modality actually materializes real executable sessions, none silently dropped

    func testEveryModalityProducesRealExecutableSessionsNotJustThePrimary() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try startVariedMix(asOf: asOf)

        let byLabel = Dictionary(uniqueKeysWithValues: fixture.mix.orderedComponents.map { ($0.label, $0) })

        let strengthInstance = try XCTUnwrap(byLabel["Strength"]?.programInstance)
        XCTAssertFalse(strengthInstance.sessions.isEmpty)
        let strengthPrescriptions = strengthInstance.sessions.flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions)
        XCTAssertFalse(strengthPrescriptions.isEmpty)
        XCTAssertTrue(strengthPrescriptions.allSatisfy { $0.exercise != nil }, "every real Strength prescription must have resolved a concrete exercise")

        let ffInstance = try XCTUnwrap(byLabel["Functional Fitness"]?.programInstance)
        XCTAssertFalse(ffInstance.sessions.isEmpty)
        let ffBlocks = ffInstance.sessions.flatMap(\.orderedBlocks)
        XCTAssertTrue(ffBlocks.contains { $0.type == .functionalFitness }, "a real Functional Fitness block must exist, not silently skipped")
        let ffMovements = ffBlocks.compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements)
        XCTAssertFalse(ffMovements.isEmpty, "the FF prescription must have real movements, not an empty shell")
        XCTAssertTrue(ffMovements.allSatisfy { $0.exercise != nil }, "every FF movement slot must have resolved a concrete exercise from the real candidate pool — this is the exact path that always threw before Slice 3, since nothing ever supplied real FF candidates through StartPhaseUseCase")

        let runningInstance = try XCTUnwrap(byLabel["Running"]?.programInstance)
        XCTAssertFalse(runningInstance.sessions.isEmpty, "SteadyState materializes its whole natural block up front — must not be silently empty")

        // Nothing silently dropped from the merged schedule either.
        let placedInstanceIDs = Set(fixture.result.scheduleProposal.placements.compactMap { $0.session.programInstance?.id })
        XCTAssertEqual(placedInstanceIDs, [strengthInstance.id, ffInstance.id, runningInstance.id], "the merged schedule must include real placements from all 3 components, never silently dropping one")
    }

    // MARK: 4 — progression/history state never crosses modalities

    func testProgressionStateNeverCrossesModalityBoundaries() throws {
        let asOf = date(2026, 1, 5)
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)

        let fixture0 = try makeAcceptedPlan(asOf: asOf)
        let mixCandidates = LongTermPlanner.proposeTrainingMix(phase: fixture0.phase, goal: fixture0.goal)
        let variedMix = try XCTUnwrap(mixCandidates.first { $0.mix.name == "Strength Plus Variety" })
        let candidates = makeCandidates()
        let materializationContext = TacticalMaterializationContext(
            equipmentProfile: equipment, strengthCandidateExercises: candidates.strength, functionalFitnessCandidateExercises: candidates.functionalFitness
        )
        try StartPhaseUseCase.start(
            phase: fixture0.phase, mix: variedMix.mix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: performanceProfile, availability: availability(),
            materializationContext: materializationContext, context: context
        )

        // Materializing all 3 systems together must never itself write
        // ANY performance history — only actually logging a result does.
        XCTAssertTrue(performanceProfile.exerciseProfiles.isEmpty)
        XCTAssertTrue(performanceProfile.activityProfiles.isEmpty)
        XCTAssertTrue(performanceProfile.benchmarkProfiles.isEmpty)

        let strengthInstance = try XCTUnwrap(variedMix.mix.orderedComponents.first { $0.label == "Strength" }?.programInstance)
        let prescription = try XCTUnwrap(strengthInstance.sessions.first?.orderedBlocks.first?.orderedPrescriptions.first)
        let exercise = try XCTUnwrap(prescription.exercise)
        let setPrescription = try XCTUnwrap(prescription.orderedSetPrescriptions.first)

        RecordSetResultUseCase.recordSet(
            setIndex: 0, weight: 60, reps: 8, targetRir: nil, actualRir: nil, prBand: nil, scoringDirection: .higherIsBetter,
            context: .rx, setPrescription: setPrescription, exercisePrescription: prescription, exercise: exercise,
            performanceProfile: performanceProfile, completedAt: asOf, modelContext: context
        )

        // A real Strength result was logged — it must land ONLY in
        // exerciseProfiles, never in activityProfiles/benchmarkProfiles,
        // proving Functional Fitness/endurance progression state is
        // structurally untouched by Strength activity, and vice versa.
        XCTAssertEqual(performanceProfile.exerciseProfiles.count, 1)
        XCTAssertTrue(performanceProfile.activityProfiles.isEmpty, "logging a Strength result must never create/touch an ActivityPerformanceProfile")
        XCTAssertTrue(performanceProfile.benchmarkProfiles.isEmpty, "logging a Strength result must never create/touch a BenchmarkPerformanceProfile")
    }

    // MARK: 5 — rolling the window preserves the accepted mix, never silently re-recommends

    func testRollingTacticalWindowPreservesTheAcceptedMixAcrossEveryComponent() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try startVariedMix(asOf: asOf)
        let originalMixID = fixture.mix.id
        let instancesBefore = Dictionary(uniqueKeysWithValues: fixture.mix.orderedComponents.map { ($0.label, $0.programInstance?.id) })

        // Complete week 0 for every non-SteadyState component so rollForward has real inputs to work from.
        for component in fixture.mix.orderedComponents {
            guard let instance = component.programInstance, component.programmingSystem != .steadyState else { continue }
            for session in instance.sessions {
                for block in session.orderedBlocks {
                    for prescription in block.orderedPrescriptions {
                        for setPrescription in prescription.orderedSetPrescriptions {
                            RecordSetResultUseCase.recordSet(
                                setIndex: 0, weight: setPrescription.targetWeight ?? 40, reps: 8, targetRir: nil, actualRir: nil, prBand: nil,
                                scoringDirection: .higherIsBetter, context: .rx, setPrescription: setPrescription, exercisePrescription: prescription,
                                exercise: prescription.exercise ?? fixture.candidates.strength[0], performanceProfile: PerformanceProfile(), completedAt: asOf, modelContext: context
                            )
                        }
                    }
                    try CompleteBlockUseCase.complete(block, context: .full, modelContext: context)
                }
                try CompleteSessionUseCase.complete(session, context: .full, asOf: asOf, modelContext: context)
            }
        }

        let rollForwardDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: asOf))
        let materializationContext = TacticalMaterializationContext(
            equipmentProfile: equipment, strengthCandidateExercises: fixture.candidates.strength, functionalFitnessCandidateExercises: fixture.candidates.functionalFitness
        )
        let rollResult = try XCTUnwrap(RollTacticalWindowUseCase.rollForward(
            mix: fixture.mix, asOf: rollForwardDate, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext, context: context
        ))

        // The mix itself was never silently replaced by a fresh recommendation.
        XCTAssertEqual(fixture.phase.selectedTrainingMix?.id, originalMixID)
        XCTAssertEqual(fixture.mix.id, originalMixID)

        // Every component still points at the SAME ProgramInstance it did
        // before rolling forward — rollForward adds a week to existing
        // instances, it never creates fresh ones (that's StartPhaseUseCase's
        // job, only ever for a brand-new phase).
        for component in fixture.mix.orderedComponents {
            XCTAssertEqual(component.programInstance?.id, instancesBefore[component.label] ?? nil, "\(component.label)'s instance identity must survive rolling the window forward")
        }

        // SteadyState materialized its whole block up front and has
        // nothing left to roll — it must be absent from this call's
        // results, never silently re-triggered.
        let rolledLabels = Set(fixture.mix.orderedComponents.filter { component in
            rollResult.newSessionsByComponent.keys.contains(component.id)
        }.map(\.label))
        XCTAssertEqual(rolledLabels, ["Strength", "Functional Fitness"])
    }

    // MARK: 6 — GOING FORWARD override respected for a Functional Fitness slot too

    func testGoingForwardOverrideRespectedForAFunctionalFitnessSlotAcrossRoll() throws {
        let asOf = date(2026, 1, 5)
        let fixture = try startVariedMix(asOf: asOf)
        let ffInstance = try XCTUnwrap(fixture.mix.orderedComponents.first { $0.label == "Functional Fitness" }?.programInstance)
        let ffMovement = try XCTUnwrap(ffInstance.sessions.first?.orderedBlocks.first { $0.type == .functionalFitness }?.functionalFitnessPrescription?.orderedMovements.first { $0.exercise?.canonicalName == "Mixed FF Bike" })
        let ffSlot = try XCTUnwrap(ffMovement.exercise.flatMap { exercise in
            fixture.candidates.functionalFitness.first { $0.id == exercise.id }
        })
        _ = ffSlot // the candidate itself; the real slot lives on the template graph:
        let ffSlotTemplate = try XCTUnwrap(ffInstance.programDefinition?.orderedTemplateSessions.first?.orderedBlockTemplates
            .first { $0.type == .functionalFitness }?.functionalFitnessPrescriptionTemplate?.orderedMovementSlots
            .first { $0.exerciseSlot?.allowedModalities.contains(.metabolicConditioning) == true }?.exerciseSlot)
        let realSlot = try XCTUnwrap(ffSlotTemplate)

        let alternativeBike = Exercise(canonicalName: "Zzz Alt Metcon Machine", modality: .functionalFitness, equipment: "rower", movementPattern: "test", movementFunctions: [.monostructural], functionalModality: .metabolicConditioning)
        context.insert(alternativeBike)
        try SubstituteExerciseUseCase.substituteGoingForward(instance: ffInstance, slot: realSlot, with: alternativeBike, context: context)

        for session in ffInstance.sessions {
            for block in session.orderedBlocks { try CompleteBlockUseCase.complete(block, context: .full, modelContext: context) }
            try CompleteSessionUseCase.complete(session, context: .full, asOf: asOf, modelContext: context)
        }
        for component in fixture.mix.orderedComponents where component.programmingSystem == .hypertrophy {
            guard let instance = component.programInstance else { continue }
            for session in instance.sessions {
                for block in session.orderedBlocks { try CompleteBlockUseCase.complete(block, context: .full, modelContext: context) }
                try CompleteSessionUseCase.complete(session, context: .full, asOf: asOf, modelContext: context)
            }
        }

        let rollForwardDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: asOf))
        let materializationContext = TacticalMaterializationContext(
            equipmentProfile: equipment, strengthCandidateExercises: fixture.candidates.strength, functionalFitnessCandidateExercises: fixture.candidates.functionalFitness
        )
        let rollResult = try XCTUnwrap(RollTacticalWindowUseCase.rollForward(
            mix: fixture.mix, asOf: rollForwardDate, ownerUserID: ownerUserID,
            performanceProfile: nil, availability: availability(),
            materializationContext: materializationContext, context: context
        ))

        let ffComponentID = try XCTUnwrap(fixture.mix.orderedComponents.first { $0.label == "Functional Fitness" }?.id)
        let newFFSessions = try XCTUnwrap(rollResult.newSessionsByComponent[ffComponentID])
        let newMovements = newFFSessions.flatMap(\.orderedBlocks).compactMap(\.functionalFitnessPrescription).flatMap(\.orderedMovements)
        XCTAssertTrue(newMovements.contains { $0.exercise?.id == alternativeBike.id }, "the GOING FORWARD override for the metcon slot must still win on the rolled-forward week")
    }
}
