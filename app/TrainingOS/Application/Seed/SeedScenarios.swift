import Foundation
import SwiftData

/// One builder function per required proof case (handoff-adjacent scenarios
/// A-H from the implementation brief), plus the Program A -> Program B
/// continuity case. Every function does the minimum to be a faithful,
/// distinct example of its block type — not a realistic full program.
///
/// Every relationship is established from exactly one side, via the owning
/// model's `addX` method (`day.addSession`, `session.addBlock`,
/// `block.addPrescription`, `prescription.addSetPrescription`) — never by
/// setting both sides manually. See CLAUDE.md and DELETE_RULE_MATRIX.md.
enum SeedScenarios {
    /// A. Traditional hypertrophy session: Bench Press + accessory work,
    /// per-set RIR logged with the target preselected.
    @discardableResult
    static func hypertrophySession(
        day: Day,
        catalog: ExerciseCatalog,
        performanceProfile: PerformanceProfile,
        programInstance: ProgramInstance?,
        modelContext: ModelContext
    ) -> Session {
        let session = Session(name: "Push Day", modality: .hypertrophy, status: .completed)
        session.completedAt = day.date
        modelContext.insert(session)
        day.addSession(session)
        programInstance?.addSession(session)

        let block = WorkoutBlock(type: .hypertrophy, status: .completed)
        modelContext.insert(block)
        session.addBlock(block)

        let movement = ExercisePrescription(exercise: catalog.benchPress)
        modelContext.insert(movement)
        block.addPrescription(movement)

        let setPlans: [(low: Int, high: Int, rir: Int, actualReps: Int, actualRir: Int)] = [
            (8, 12, 2, 12, 2),
            (8, 12, 2, 12, 2),
            (8, 12, 2, 12, 1),
        ]
        for (index, plan) in setPlans.enumerated() {
            let prescription = SetPrescription(
                repRangeLow: plan.low,
                repRangeHigh: plan.high,
                targetWeight: 60,
                targetRir: plan.rir
            )
            modelContext.insert(prescription)
            movement.addSetPrescription(prescription)

            RecordSetResultUseCase.recordSet(
                setIndex: index,
                weight: 60,
                reps: plan.actualReps,
                targetRir: plan.rir,
                actualRir: plan.actualRir,
                prBand: "8-12",
                scoringDirection: .higherIsBetter,
                context: .rx,
                setPrescription: prescription,
                exercisePrescription: movement,
                exercise: catalog.benchPress,
                performanceProfile: performanceProfile,
                completedAt: day.date,
                modelContext: modelContext
            )
        }

        let accessoryBlock = WorkoutBlock(type: .accessory, status: .completed)
        modelContext.insert(accessoryBlock)
        session.addBlock(accessoryBlock)

        let accessoryMovement = ExercisePrescription(exercise: catalog.inclineDumbbellPress)
        modelContext.insert(accessoryMovement)
        accessoryBlock.addPrescription(accessoryMovement)

        for index in 0..<3 {
            let prescription = SetPrescription(repRangeLow: 10, repRangeHigh: 15, targetWeight: 24, targetRir: 2)
            modelContext.insert(prescription)
            accessoryMovement.addSetPrescription(prescription)

            RecordSetResultUseCase.recordSet(
                setIndex: index,
                weight: 24,
                reps: 13,
                targetRir: 2,
                actualRir: 2,
                prBand: "10-15",
                scoringDirection: .higherIsBetter,
                context: .rx,
                setPrescription: prescription,
                exercisePrescription: accessoryMovement,
                exercise: catalog.inclineDumbbellPress,
                performanceProfile: performanceProfile,
                completedAt: day.date,
                modelContext: modelContext
            )
        }

        return session
    }

    /// B. Zone 2 steady-state session.
    @discardableResult
    static func zone2Session(
        day: Day,
        catalog: ExerciseCatalog,
        programInstance: ProgramInstance?,
        modelContext: ModelContext,
        status: SessionStatus = .completed
    ) -> Session {
        let session = Session(name: "Zone 2 Run", modality: .conditioning, status: status)
        if status == .completed { session.completedAt = day.date }
        modelContext.insert(session)
        day.addSession(session)
        programInstance?.addSession(session)

        let block = WorkoutBlock(type: .steadyState, status: status == .completed ? .completed : .pending)
        modelContext.insert(block)
        session.addBlock(block)

        let movement = ExercisePrescription(exercise: catalog.easyRun, targetDurationSeconds: 2400)
        modelContext.insert(movement)
        block.addPrescription(movement)

        guard status == .completed else { return session }

        // DURATION_AT_HR is not a simple higher/lower comparison; this pass
        // stores the result without attempting PR scoring for it. See
        // ARCHITECTURE.md for the gap.
        let result = WorkoutResult(
            type: .steadyState,
            scoringDirection: .none,
            completedAt: day.date,
            durationSeconds: 2400,
            averageHeartRate: 138
        )
        RecordWorkoutResultUseCase.recordResult(
            result,
            for: block,
            modelContext: modelContext
        )
        return session
    }

    /// C. Interval session.
    @discardableResult
    static func intervalSession(
        day: Day,
        catalog: ExerciseCatalog,
        programInstance: ProgramInstance?,
        modelContext: ModelContext
    ) -> Session {
        let session = Session(name: "Track Intervals", modality: .conditioning, status: .completed)
        session.completedAt = day.date
        modelContext.insert(session)
        day.addSession(session)
        programInstance?.addSession(session)

        let block = WorkoutBlock(type: .intervals, status: .completed)
        modelContext.insert(block)
        session.addBlock(block)

        let movement = ExercisePrescription(exercise: catalog.trackIntervalRun, targetDurationSeconds: 90)
        modelContext.insert(movement)
        block.addPrescription(movement)

        // PACE_AT_HR_DESC is a compound metric, same gap as DURATION_AT_HR.
        let result = WorkoutResult(
            type: .intervals,
            scoringDirection: .none,
            completedAt: day.date,
            averageHeartRate: 165,
            splitSeconds: [90, 92, 89, 91, 90, 93]
        )
        RecordWorkoutResultUseCase.recordResult(
            result,
            for: block,
            modelContext: modelContext
        )
        return session
    }

    /// D. AMRAP.
    @discardableResult
    static func amrapSession(
        day: Day,
        catalog: ExerciseCatalog,
        programInstance: ProgramInstance?,
        modelContext: ModelContext
    ) -> Session {
        let session = Session(name: "12-Minute Metcon", modality: .functionalFitness, status: .completed)
        session.completedAt = day.date
        modelContext.insert(session)
        day.addSession(session)
        programInstance?.addSession(session)

        let block = WorkoutBlock(type: .amrap, status: .completed, timeCapSeconds: 720)
        modelContext.insert(block)
        session.addBlock(block)

        let movements: [(Exercise, Int)] = [(catalog.wallBall, 15), (catalog.pullUp, 10), (catalog.burpee, 20)]
        for pair in movements {
            let movement = ExercisePrescription(exercise: pair.0, repsPerRound: pair.1)
            modelContext.insert(movement)
            block.addPrescription(movement)
        }

        // Ad hoc AMRAPs are not tied to a repeatable benchmark identity in
        // this pass, so no PersonalRecord is generated here — only named
        // benchmarks (see Fran, below) carry one.
        let result = WorkoutResult(
            type: .amrap,
            scoringDirection: .higherIsBetter,
            completedAt: day.date,
            rounds: 5,
            extraReps: 14
        )
        RecordWorkoutResultUseCase.recordResult(
            result,
            for: block,
            modelContext: modelContext
        )
        return session
    }

    /// E. EMOM.
    @discardableResult
    static func emomSession(
        day: Day,
        catalog: ExerciseCatalog,
        programInstance: ProgramInstance?,
        modelContext: ModelContext
    ) -> Session {
        let session = Session(name: "EMOM Conditioning", modality: .functionalFitness, status: .completed)
        session.completedAt = day.date
        modelContext.insert(session)
        day.addSession(session)
        programInstance?.addSession(session)

        let block = WorkoutBlock(
            type: .emom,
            status: .completed,
            emomIntervalSeconds: 60,
            emomTotalMinutes: 10
        )
        modelContext.insert(block)
        session.addBlock(block)

        let movement = ExercisePrescription(exercise: catalog.kettlebellSwing, repsPerRound: 15)
        modelContext.insert(movement)
        block.addPrescription(movement)

        // Completion-based: never PR-eligible.
        let result = WorkoutResult(
            type: .emom,
            scoringDirection: .completionBased,
            completedAt: day.date,
            minutesCompleted: 10,
            incompleteMinuteIndexes: [6]
        )
        RecordWorkoutResultUseCase.recordResult(
            result,
            for: block,
            modelContext: modelContext
        )
        return session
    }

    /// F. For Time benchmark ("Fran") — 21-15-9 Thrusters/Pull-ups.
    ///
    /// **Stage 4E consolidation:** previously modelled "Fran" as a
    /// canonical `Exercise` scored through the legacy `WorkoutResult`
    /// path (see `RecordWorkoutResultUseCase`'s own doc comment on why
    /// that was the exact duplicate-canonical-identity problem Stage 3C
    /// deferred). Now built exclusively through the typed
    /// `FunctionalFitnessPrescription`/`FunctionalFitnessResult`/
    /// `BenchmarkDefinition`/`BenchmarkPerformanceProfile` path — the sole
    /// canonical benchmark representation as of this stage. The real
    /// 21-15-9 descending ladder is still simplified to one total-reps
    /// figure per movement at the execution layer (45 = 21+15+9) — the
    /// explicit rep-scheme array now lives on the template graph
    /// (`FunctionalFitnessMovementSlotTemplate.repScheme`), not
    /// duplicated here.
    @discardableResult
    static func forTimeBenchmarkSession(
        day: Day,
        catalog: ExerciseCatalog,
        performanceProfile: PerformanceProfile,
        programInstance: ProgramInstance?,
        modelContext: ModelContext
    ) -> Session {
        let session = Session(name: "Fran", modality: .functionalFitness, status: .completed)
        session.completedAt = day.date
        modelContext.insert(session)
        day.addSession(session)
        programInstance?.addSession(session)

        let block = WorkoutBlock(type: .functionalFitness, status: .completed)
        modelContext.insert(block)
        session.addBlock(block)

        let stimulus = Stimulus(
            targetDurationDomain: .short, intensity: .high, loading: .moderate,
            movementFunctions: [.squatLoaded, .gymnasticsPull],
            movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1), ModalityCount(modality: .gymnastics, count: 1)],
            skillDemand: .moderate, systemicDemand: .high, scoreType: .time
        )
        let format = WorkoutFormat.forTime(capSeconds: 600)

        let prescription = FunctionalFitnessPrescription(stimulus: stimulus, format: format)
        modelContext.insert(prescription)
        block.attachFunctionalFitnessPrescription(prescription)

        for pair in [(catalog.thruster, 45), (catalog.pullUp, 45)] {
            let movement = FunctionalFitnessMovement(exercise: pair.0, reps: pair.1)
            modelContext.insert(movement)
            prescription.addMovement(movement)
        }

        let benchmark = BenchmarkDefinition(
            canonicalID: "benchmark.fran", name: "Fran",
            stimulus: stimulus, format: format, scoreType: .time, scoreDirection: .lowerIsBetter
        )
        modelContext.insert(benchmark)

        // Stage FF.E1: this seeded demo attempt is meant to illustrate a
        // real, confirmed Personal Record — `.asPrescribed` is the honest
        // choice for what this fixture represents, not a workaround.
        let result = FunctionalFitnessResult(
            scoreType: .time, scoreValue: .time(seconds: 245), scoreDirection: .lowerIsBetter,
            resultContext: .rx, adherence: .asPrescribed, completedAt: day.date
        )
        RecordFunctionalFitnessResultUseCase.recordResult(
            result, for: block, benchmark: benchmark, performanceProfile: performanceProfile, modelContext: modelContext
        )
        return session
    }

    /// G. Hybrid Strength + Metcon: one Session, two ordered WorkoutBlocks
    /// of different types/modalities. Proves a Session is not modelled per
    /// modality — it is an ordered chain of blocks.
    @discardableResult
    static func hybridStrengthAndMetconSession(
        day: Day,
        catalog: ExerciseCatalog,
        performanceProfile: PerformanceProfile,
        programInstance: ProgramInstance?,
        modelContext: ModelContext
    ) -> Session {
        let session = Session(name: "Strength + Metcon", modality: .hybrid, status: .completed)
        session.completedAt = day.date
        modelContext.insert(session)
        day.addSession(session)
        programInstance?.addSession(session)

        let strengthBlock = WorkoutBlock(type: .strength, status: .completed)
        modelContext.insert(strengthBlock)
        session.addBlock(strengthBlock)

        let squatMovement = ExercisePrescription(exercise: catalog.backSquat)
        modelContext.insert(squatMovement)
        strengthBlock.addPrescription(squatMovement)

        for index in 0..<3 {
            let prescription = SetPrescription(repRangeLow: 5, repRangeHigh: 6, targetWeight: 100, targetRir: 2)
            modelContext.insert(prescription)
            squatMovement.addSetPrescription(prescription)

            RecordSetResultUseCase.recordSet(
                setIndex: index,
                weight: 100,
                reps: 6,
                targetRir: 2,
                actualRir: 2,
                prBand: "5-6",
                scoringDirection: .higherIsBetter,
                context: .rx,
                setPrescription: prescription,
                exercisePrescription: squatMovement,
                exercise: catalog.backSquat,
                performanceProfile: performanceProfile,
                completedAt: day.date,
                modelContext: modelContext
            )
        }

        let metconBlock = WorkoutBlock(type: .amrap, status: .completed, timeCapSeconds: 480)
        modelContext.insert(metconBlock)
        session.addBlock(metconBlock)

        for pair in [(catalog.wallBall, 12), (catalog.burpee, 12)] {
            let movement = ExercisePrescription(exercise: pair.0, repsPerRound: pair.1)
            modelContext.insert(movement)
            metconBlock.addPrescription(movement)
        }

        let metconResult = WorkoutResult(
            type: .amrap,
            scoringDirection: .higherIsBetter,
            completedAt: day.date,
            rounds: 6,
            extraReps: 5
        )
        RecordWorkoutResultUseCase.recordResult(
            metconResult,
            for: metconBlock,
            modelContext: modelContext
        )

        return session
    }

    /// H. Two separate Sessions on the same Day: a morning strength
    /// session and an evening Zone 2 run, both scheduled (not yet
    /// performed) so Today can render prescriptions with no results.
    ///
    /// Stage 6C: the morning Session ("Lower A") is now built through the
    /// real `ProgramDefinition -> TemplateSession -> WorkoutBlockTemplate ->
    /// PrescriptionTemplate -> ExerciseSlot -> StrengthProgressionEngine ->
    /// ExercisePrescription/SetPrescription` path (`materializedLowerASession`
    /// below) rather than hand-assembled as a single bare
    /// `ExercisePrescription` — see `STAGE6C_ACCEPTANCE_REPORT.md` for why
    /// the original one-exercise seed Session could never exercise
    /// multi-exercise navigation or slot-based Change Exercise.
    @discardableResult
    static func twoSessionsSameDay(
        day: Day,
        catalog: ExerciseCatalog,
        ownerUserID: UUID,
        modelContext: ModelContext
    ) -> (morning: Session, evening: Session, programInstance: ProgramInstance, multiAlternativeSlot: ExerciseSlot) {
        let (morning, programInstance, multiAlternativeSlot) = materializedLowerASession(
            day: day, catalog: catalog, ownerUserID: ownerUserID, modelContext: modelContext
        )

        let evening = Session(
            scheduledTime: Calendar.current.date(byAdding: .hour, value: 18, to: day.date),
            name: "Evening Zone 2",
            modality: .conditioning,
            status: .scheduled
        )
        modelContext.insert(evening)
        day.addSession(evening)

        let steadyBlock = WorkoutBlock(type: .steadyState, status: .pending)
        modelContext.insert(steadyBlock)
        evening.addBlock(steadyBlock)

        let runMovement = ExercisePrescription(exercise: catalog.easyRun, targetDurationSeconds: 1800)
        modelContext.insert(runMovement)
        steadyBlock.addPrescription(runMovement)

        return (morning, evening, programInstance, multiAlternativeSlot)
    }

    /// Builds a realistic 5-exercise Lower Body Strength Session through
    /// the real production materialization path — `ProgramDefinition`'s
    /// own template graph (`TemplateSession`/`WorkoutBlockTemplate`/
    /// `PrescriptionTemplate`/`ExerciseSlot`), a real `ProgramInstance`,
    /// and `StrengthProgressionEngine`'s own resolve functions — never a
    /// bare hand-assembled `ExercisePrescription` array. Deliberately does
    /// NOT call `StrengthMaterializer.materializeWeek` itself: that
    /// function creates its own `Day` per `TemplateSession` (one Day per
    /// calendar date is a documented invariant, `Day.swift`'s own doc
    /// comment), which would collide with the already-existing "today"
    /// `Day` this fixture must attach to alongside the evening Session —
    /// so this reuses the exact same engine calls
    /// (`StrengthProgressionEngine.resolveWeight`/`.resolveRepGoal`/
    /// `.resolveSetCount`, `SubstituteExerciseUseCase.resolvedExercise`)
    /// inline, attached to the caller-supplied `day` instead.
    ///
    /// Stage 6D: every slot now allows a real second exercise (Stage 6C
    /// left only one slot substitutable, which manual testing correctly
    /// flagged as reading like a hard "no history, no substitution" block
    /// on the other four) — `multiAlternativeSlot` returns the last one
    /// found (currently Calf's), kept only because existing acceptance
    /// tests/manual QA already reference *a* known-multi-alternative slot
    /// directly; any slot in this fixture now qualifies equally.
    ///
    /// **Known architectural fact, not a Stage 6C bug:** `RepGoal` has no
    /// low/high range (only a single `reps` count), and
    /// `StrengthMaterializer`'s own `SetPrescription` construction never
    /// sets `targetRir` — both true for every materializer-produced
    /// prescription in the app today, Family A included. This fixture
    /// reflects that honestly (a single rep number, no RIR) rather than
    /// hand-patching a nicer-looking range/RIR after the fact, which
    /// would misrepresent what the real pipeline actually produces.
    @discardableResult
    static func materializedLowerASession(
        day: Day,
        catalog: ExerciseCatalog,
        ownerUserID: UUID,
        modelContext: ModelContext
    ) -> (session: Session, programInstance: ProgramInstance, multiAlternativeSlot: ExerciseSlot) {
        struct SlotSpec {
            let name: String
            let allowedTargets: [MuscleGroup]
            let allowedExercises: [Exercise]
            let defaultExercise: Exercise
            let rmKilograms: Double
            let weekOneFactor: Double
            let sets: Int
            let reps: Int
            /// Mirrors `HypertrophyProgramGenerator`'s own primary-vs-
            /// paired-accessory split (`repGoalSchedule` all `toFailure`,
            /// `pairedRepGoalSchedule` never): a primary compound
            /// materializes with a real RIR target (0 — "to failure" is
            /// the only intensity-target concept the approved family
            /// specs define, `STAGE6D` audit); an accessory materializes
            /// with none, exactly like real Family A data.
            let toFailure: Bool
            /// Stage 6D: at least one real `.autoregulated` slot, so the
            /// hypertrophy feedback loop (Part 6) has a genuine engine
            /// input to feed, exactly like real Family A primary slots.
            let isAutoregulated: Bool
        }

        let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)
        let laterWeekMultipliers = HypertrophyProgramGenerator.laterWeekMultipliers

        let specs: [SlotSpec] = [
            SlotSpec(
                name: "Squat Pattern", allowedTargets: [.quadriceps, .glutes],
                allowedExercises: [catalog.backSquat, catalog.frontSquat], defaultExercise: catalog.backSquat,
                rmKilograms: 140, weekOneFactor: 0.85, sets: 3, reps: 6, toFailure: true, isAutoregulated: true
            ),
            SlotSpec(
                name: "Hip Hinge", allowedTargets: [.hamstrings, .glutes],
                allowedExercises: [catalog.romanianDeadlift, catalog.conventionalDeadlift], defaultExercise: catalog.romanianDeadlift,
                rmKilograms: 120, weekOneFactor: 0.7, sets: 3, reps: 9, toFailure: true, isAutoregulated: false
            ),
            SlotSpec(
                name: "Unilateral/Machine Squat", allowedTargets: [.quadriceps, .glutes],
                allowedExercises: [catalog.legPress, catalog.bulgarianSplitSquat], defaultExercise: catalog.legPress,
                rmKilograms: 180, weekOneFactor: 0.75, sets: 3, reps: 11, toFailure: false, isAutoregulated: false
            ),
            SlotSpec(
                name: "Hamstring Isolation", allowedTargets: [.hamstrings],
                allowedExercises: [catalog.legCurl, catalog.seatedLegCurl], defaultExercise: catalog.legCurl,
                rmKilograms: 60, weekOneFactor: 0.7, sets: 3, reps: 12, toFailure: false, isAutoregulated: false
            ),
            SlotSpec(
                name: "Calf", allowedTargets: [.calves],
                allowedExercises: [catalog.calfRaise, catalog.seatedCalfRaise], defaultExercise: catalog.calfRaise,
                rmKilograms: 80, weekOneFactor: 0.7, sets: 4, reps: 12, toFailure: false, isAutoregulated: false
            ),
        ]

        let definition = ProgramDefinition(
            name: "Lower Body Strength — Acceptance Fixture",
            lengthWeeks: 5,
            intent: "Stage 6C manual acceptance: a realistic 5-exercise Lower Body Strength session"
        )
        modelContext.insert(definition)

        let templateSession = TemplateSession(name: "Lower A", role: .strength)
        modelContext.insert(templateSession)
        definition.addTemplateSession(templateSession)

        let blockTemplate = WorkoutBlockTemplate(type: .strength)
        modelContext.insert(blockTemplate)
        templateSession.addBlockTemplate(blockTemplate)

        let instance = ProgramInstance(ownerUserID: ownerUserID, startDate: day.date)
        instance.programDefinition = definition
        modelContext.insert(instance)

        let session = Session(
            scheduledTime: Calendar.current.date(byAdding: .hour, value: 7, to: day.date),
            name: "Lower A",
            modality: .strength,
            status: .scheduled
        )
        modelContext.insert(session)
        day.addSession(session)
        instance.addSession(session)

        let block = WorkoutBlock(type: .strength, status: .pending)
        modelContext.insert(block)
        session.addBlock(block)

        var multiAlternativeSlot: ExerciseSlot?
        var templatesByName: [String: PrescriptionTemplate] = [:]

        for spec in specs {
            let setCountRule: SetCountRule = spec.isAutoregulated
                ? .autoregulated(AutoregulatedSetCount(baselineSets: spec.sets))
                : .fixed(setsByWeek: [spec.sets, spec.sets, spec.sets, spec.sets])
            let template = PrescriptionTemplate(rules: StrengthProgressionRules(
                loadRule: .rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: spec.weekOneFactor, laterWeekMultipliers: laterWeekMultipliers)),
                setCountRule: setCountRule,
                repGoalSchedule: Array(repeating: spec.toFailure ? RepGoal.rir(spec.reps) : RepGoal.fixedReps(spec.reps), count: 4)
            ))
            modelContext.insert(template)
            templatesByName[spec.name] = template

            let slot = ExerciseSlot(
                name: spec.name, allowedTargets: spec.allowedTargets,
                allowedExercises: spec.allowedExercises, resolvedExercise: spec.defaultExercise
            )
            modelContext.insert(slot)
            template.attachExerciseSlot(slot)
            blockTemplate.addPrescriptionTemplate(template)

            if spec.allowedExercises.count > 1 { multiAlternativeSlot = slot }

            guard let rules = template.rules else { continue }
            let weightResult = StrengthProgressionEngine.resolveWeight(
                rules: rules, weekIndex: 0, rmKilograms: spec.rmKilograms,
                weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: nil, equipmentProfile: equipment
            )
            let repResult = StrengthProgressionEngine.resolveRepGoal(rules: rules, weekIndex: 0)
            let setResult = StrengthProgressionEngine.resolveSetCount(
                rules: rules, weekIndex: 0, previousWeekSetCount: nil, autoregulationRating: nil
            )

            let prescription = ExercisePrescription(exercise: SubstituteExerciseUseCase.resolvedExercise(for: slot, in: instance))
            prescription.sourceExerciseSlot = slot
            prescription.sourcePrescriptionTemplate = template
            // Mirrors StrengthMaterializer's own reason-code capture
            // exactly (Stage 6D Part 7).
            prescription.appliedLoadReasonCode = weightResult.reasonCode
            prescription.appliedSetCountReasonCode = setResult.reasonCode
            prescription.appliedRepGoalReasonCode = repResult.reasonCode
            modelContext.insert(prescription)
            block.addPrescription(prescription)

            let setCount = setResult.sets ?? 0
            // Mirrors StrengthMaterializer's own resolution exactly
            // (Stage 10R.1D) — a fixed rep count and an RIR/effort target
            // are never both fabricated from one another.
            let resolvedRepRangeLow: Int?
            let resolvedRepRangeHigh: Int?
            let resolvedTargetRir: Int?
            switch repResult.repGoal?.prescription {
            case .fixedReps(let n):
                resolvedRepRangeLow = n
                resolvedRepRangeHigh = repResult.repGoal?.repRangeHigh ?? n
                resolvedTargetRir = repResult.repGoal?.targetRir
            case .rir(let n):
                resolvedRepRangeLow = nil
                resolvedRepRangeHigh = nil
                resolvedTargetRir = n
            case nil:
                resolvedRepRangeLow = nil
                resolvedRepRangeHigh = nil
                resolvedTargetRir = nil
            }
            for _ in 0..<setCount {
                let setPrescription = SetPrescription(
                    repRangeLow: resolvedRepRangeLow,
                    repRangeHigh: resolvedRepRangeHigh,
                    targetWeight: weightResult.weightKg,
                    targetRir: resolvedTargetRir
                )
                modelContext.insert(setPrescription)
                prescription.addSetPrescription(setPrescription)
            }
        }

        // Squat Pattern's (Back Squat's) set count autoregulates off
        // Unilateral/Machine Squat's (Leg Press's) own completion rating —
        // mirroring Family A's real primary/paired-accessory shape
        // exactly (`PROGRAM_LOGIC_SPEC.md` §FAMILY_A_SET_AUTOREGULATION).
        templatesByName["Squat Pattern"]?.pairedSlot = templatesByName["Unilateral/Machine Squat"]

        guard let multiAlternativeSlot else {
            fatalError("materializedLowerASession's own fixed spec list always includes one multi-exercise slot")
        }

        return (session, instance, multiAlternativeSlot)
    }

    /// Proves the Performance Profile invariant: logging Bench Press under
    /// a second, unrelated ProgramInstance still lands in the same
    /// ExercisePerformanceProfile as the first.
    @discardableResult
    static func benchPressContinuitySession(
        day: Day,
        catalog: ExerciseCatalog,
        performanceProfile: PerformanceProfile,
        programInstance: ProgramInstance?,
        modelContext: ModelContext
    ) -> Session {
        let session = Session(name: "Full Body A", modality: .strength, status: .completed)
        session.completedAt = day.date
        modelContext.insert(session)
        day.addSession(session)
        programInstance?.addSession(session)

        let block = WorkoutBlock(type: .strength, status: .completed)
        modelContext.insert(block)
        session.addBlock(block)

        let movement = ExercisePrescription(exercise: catalog.benchPress)
        modelContext.insert(movement)
        block.addPrescription(movement)

        for index in 0..<3 {
            let prescription = SetPrescription(repRangeLow: 4, repRangeHigh: 6, targetWeight: 65, targetRir: 2)
            modelContext.insert(prescription)
            movement.addSetPrescription(prescription)

            RecordSetResultUseCase.recordSet(
                setIndex: index,
                weight: 65,
                reps: 5,
                targetRir: 2,
                actualRir: 2,
                prBand: "4-6",
                scoringDirection: .higherIsBetter,
                context: .rx,
                setPrescription: prescription,
                exercisePrescription: movement,
                exercise: catalog.benchPress,
                performanceProfile: performanceProfile,
                completedAt: day.date,
                modelContext: modelContext
            )
        }

        return session
    }
}
