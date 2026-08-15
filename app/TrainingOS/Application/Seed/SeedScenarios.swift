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

        let result = FunctionalFitnessResult(
            scoreType: .time, scoreValue: .time(seconds: 245), scoreDirection: .lowerIsBetter,
            resultContext: .rx, completedAt: day.date
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
    @discardableResult
    static func twoSessionsSameDay(
        day: Day,
        catalog: ExerciseCatalog,
        modelContext: ModelContext
    ) -> (morning: Session, evening: Session) {
        let morning = Session(
            scheduledTime: Calendar.current.date(byAdding: .hour, value: 7, to: day.date),
            name: "Lower A",
            modality: .strength,
            status: .scheduled
        )
        modelContext.insert(morning)
        day.addSession(morning)

        let strengthBlock = WorkoutBlock(type: .strength, status: .pending)
        modelContext.insert(strengthBlock)
        morning.addBlock(strengthBlock)

        let squatMovement = ExercisePrescription(exercise: catalog.backSquat)
        modelContext.insert(squatMovement)
        strengthBlock.addPrescription(squatMovement)

        for _ in 0..<3 {
            let prescription = SetPrescription(repRangeLow: 5, repRangeHigh: 6, targetWeight: 102.5, targetRir: 2)
            modelContext.insert(prescription)
            squatMovement.addSetPrescription(prescription)
        }

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

        return (morning, evening)
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
