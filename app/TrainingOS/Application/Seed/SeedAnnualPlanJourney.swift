import Foundation
import SwiftData

enum SeedAnnualPlanJourneyError: Error {
    /// Never fabricated — if the real planner doesn't produce what this
    /// fixture expects, that's surfaced as a loud seed-time failure, not
    /// papered over with an invented mix/phase.
    case insufficientPhases
    case noMixCandidates
    /// `fillForwardPhases` always sets a forward-filled phase's `endDate`
    /// — if it's somehow nil, that's a real, surprising planner change
    /// worth a loud failure, never a guessed transition date.
    case phaseHasNoEndDate
}

/// Stage 7 (Tactical Planning Orchestration), Slice 4 §14: a Simulator-
/// acceptance fixture rich enough to demonstrate Annual Plan / Current
/// Phase — built entirely through the same real use cases the app itself
/// uses (`AcceptStrategicPlanUseCase` -> `StartPhaseUseCase` ->
/// `TransitionPhaseUseCase`), never hand-constructed rows. The UI itself
/// has no idea this is seed data — it reads the exact same
/// `TrainingPlan`/`TrainingPhase`/`TrainingMix`/`ProgramInstance`/
/// `PlannerDecision` types `PlanView`/`PhaseDetailView` already read for
/// real, use-case-created data.
///
/// Produces: a completed phase (Focused Hypertrophy, real logged
/// history), an active phase with a genuinely mixed modality (Strength +
/// Functional Fitness + Running) and a real recommended-vs-selected
/// distinction, and an upcoming phase left exactly `.planned` — nothing
/// materialized for it, matching §10's "no future fabrication" rule.
enum SeedAnnualPlanJourney {
    struct Result {
        let goal: Goal
        let plan: TrainingPlan
        let completedPhase: TrainingPhase
        let activePhase: TrainingPhase
        /// At least 2 — every one of them still exactly `.planned`,
        /// nothing materialized for any of them.
        let upcomingPhases: [TrainingPhase]
    }

    @discardableResult
    static func seed(
        user: User,
        performanceProfile: PerformanceProfile,
        catalog: ExerciseCatalog,
        context: ModelContext
    ) throws -> Result {
        // `.muscleGain`'s own real planning duration is 12 weeks
        // (`PhaseDurationDefaults`) — never guessed here. Anchoring the
        // plan's own creation 12 weeks (84 days) before "now" means
        // `fillForwardPhases`'s own real, unmodified math places phase
        // 1's `endDate` exactly at "today," so the transition below
        // lands phase 2's `startDate` — and therefore its whole first
        // materialized week — on and after today, never weeks in the
        // future or the past. This is deliberately re-derived from the
        // planner's own output, not a second hardcoded offset that could
        // drift out of sync with `PhaseDurationDefaults` again.
        let planAcceptedAt = SeedDataProvider.dayStart(offset: -84)
        let goal = Goal(
            ownerUserID: user.id, primaryType: .muscleGain,
            targetDate: Calendar.current.date(byAdding: .year, value: 1, to: planAcceptedAt), createdAt: planAcceptedAt
        )
        context.insert(goal)
        user.addGoal(goal)

        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: planAcceptedAt)
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: planAcceptedAt)
        guard plan.orderedPhases.count >= 4 else { throw SeedAnnualPlanJourneyError.insufficientPhases }
        let phase1 = plan.orderedPhases[0]
        let phase2 = plan.orderedPhases[1]
        let upcomingPhases = Array(plan.orderedPhases[2...])

        let availability = UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1)
        let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)
        let strengthCandidates = [
            catalog.backSquat, catalog.benchPress, catalog.inclineDumbbellPress, catalog.romanianDeadlift,
            catalog.legPress, catalog.frontSquat, catalog.legCurl, catalog.calfRaise,
            // Stage 10B additions — the 3-Day Full Body Hypertrophy
            // reference program's accessory slots (biceps/triceps) need
            // real candidates to resolve to; this pool already backs
            // phase 2 ("Strength Plus Variety"), whose Hypertrophy
            // component's `SessionFrequency(target: 3)` already selects
            // the exact 3-Day Full Body configuration.
            catalog.barbellCurl, catalog.cableTricepsPushdown, catalog.dumbbellLateralRaise, catalog.barbellRow,
        ]
        let functionalFitnessCandidates = [
            catalog.wallBall, catalog.pullUp, catalog.bike, catalog.row, catalog.toesToBar,
            catalog.kettlebellSwing, catalog.thruster, catalog.deadlift, catalog.dumbbellSnatch,
        ]
        let materializationContext = TacticalMaterializationContext(
            equipmentProfile: equipment, strengthCandidateExercises: strengthCandidates,
            functionalFitnessCandidateExercises: functionalFitnessCandidates
        )

        // Phase 1: "Focused Hypertrophy" — real generated program, real week 0.
        let phase1Candidates = LongTermPlanner.proposeTrainingMix(phase: phase1, goal: goal)
        guard let mix1 = phase1Candidates.first(where: { $0.mix.name == "Focused Hypertrophy" }) ?? phase1Candidates.first else {
            throw SeedAnnualPlanJourneyError.noMixCandidates
        }
        try StartPhaseUseCase.start(
            phase: phase1, mix: mix1.mix, asOf: planAcceptedAt, ownerUserID: user.id,
            performanceProfile: performanceProfile, availability: availability,
            materializationContext: materializationContext, context: context
        )

        // A little real logged history, so the completed phase has
        // genuine PersonalRecords/SetResults to show, not an empty shell.
        if let instance = phase1.primaryInstance,
           let prescription = instance.sessions.first?.orderedBlocks.first?.orderedPrescriptions.first,
           let exercise = prescription.exercise {
            for setPrescription in prescription.orderedSetPrescriptions {
                RecordSetResultUseCase.recordSet(
                    setIndex: setPrescription.sortIndex, weight: setPrescription.targetWeight ?? 60, reps: 8,
                    targetRir: setPrescription.targetRir, actualRir: setPrescription.targetRir, prBand: nil,
                    scoringDirection: .higherIsBetter, context: .rx, setPrescription: setPrescription,
                    exercisePrescription: prescription, exercise: exercise,
                    performanceProfile: performanceProfile, completedAt: planAcceptedAt, modelContext: context
                )
            }
        }

        // Phase 2: transition to a genuinely different, mixed-modality
        // mix — "Strength Plus Variety" (Strength + Functional Fitness +
        // Running) — while also persisting the OTHER real candidate
        // ("Focused Hypertrophy" again) as this phase's own `.recommended`
        // comparison mix, never instantiated/scheduled, purely for the
        // Recommended-vs-Selected display.
        //
        // The transition happens at phase 1's OWN real, planner-computed
        // `endDate` — never a second, independently-chosen offset that
        // could silently drift out of sync with it (exactly the bug this
        // fixture had before: transitioning 5 days ago while the real
        // plan still thought phase 1 had ~44 days left, leaving phase 2's
        // materialized Sessions dated weeks in the future, invisible in
        // Today/Week).
        guard let transitionAsOf = phase1.endDate else { throw SeedAnnualPlanJourneyError.phaseHasNoEndDate }
        let phase2Candidates = LongTermPlanner.proposeTrainingMix(phase: phase2, goal: goal)
        guard let recommended = phase2Candidates.first(where: { $0.roles.contains(.recommended) }),
              let selected = phase2Candidates.first(where: { $0.mix.id != recommended.mix.id }) else {
            throw SeedAnnualPlanJourneyError.noMixCandidates
        }
        context.insert(recommended.mix)
        phase2.addTrainingMix(recommended.mix)
        selected.mix.kind = .selected

        let transitionResult = try TransitionPhaseUseCase.transition(
            from: phase1, toNextPhaseWithMix: selected.mix, asOf: transitionAsOf, ownerUserID: user.id,
            performanceProfile: performanceProfile, availability: availability,
            materializationContext: materializationContext, context: context
        )

        return Result(
            goal: goal, plan: plan, completedPhase: transitionResult.completedPhase,
            activePhase: transitionResult.nextPhase, upcomingPhases: upcomingPhases
        )
    }
}
