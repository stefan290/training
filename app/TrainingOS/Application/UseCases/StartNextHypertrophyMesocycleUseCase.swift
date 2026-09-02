import Foundation
import SwiftData

enum StartNextHypertrophyMesocycleError: Error, Equatable {
    case previousInstanceHasNoDefinition
    /// No `TrainingMixComponent` exists to attach the next mesocycle's
    /// `ProgramInstance` to — `previousInstance` was never really wired
    /// into a mix (a caller bug, since every real instantiation path
    /// already sets this).
    case previousInstanceHasNoComponent
    /// `previousInstance`'s `HypertrophyPhaseType` has no next mesocycle
    /// in `HypertrophyProgramJourney.orderedPhaseTypes` (i.e. it was
    /// already `.resensitization`).
    case noNextMesocycle
}

/// Stage 10R.2B, corrected by Stage 10R.7A
/// (`STAGE10R7_STRATEGIC_PHASE_LIFECYCLE_DESIGN.md`, D-10R7-1/D-10R7-3):
/// the real production entry point for the explicit, user-initiated
/// Hypertrophy Mesocycle-to-Mesocycle transition
/// (`STAGE3_DECISION_MEMO.md` Decision A1 — `transitionTrigger:
/// .userInitiated`, never automatic).
///
/// **Locked hierarchy correction:** a `TrainingPhase` is a strategic
/// period in the accepted annual plan — `TrainingPlan.orderedPhases`
/// alone owns the strategic sequence, pre-planned up front by
/// `AcceptStrategicPlanUseCase`. A Hypertrophy mesocycle succession is
/// program-level progression INSIDE that same strategic phase, never
/// strategic phase creation. Before this correction, this use case
/// incorrectly created a brand-new `TrainingPhase` (and a brand-new
/// `TrainingMix`/`TrainingMixComponent`) per mesocycle, silently
/// appending it to `TrainingPlan.orderedPhases` — which both taught the
/// wrong hierarchy and could scramble a plan's own pre-planned phase
/// sequence the moment a real multi-phase strategic plan existed. Now:
/// the SAME `previousPhase`/`TrainingMix`/`TrainingMixComponent` are
/// reused unchanged; only a fresh `ProgramInstance` (new
/// `ProgramDefinition`, fresh calibration, carried-forward exercise
/// selections, its own provenance) is created and the existing
/// component's `.programInstance` pointer is reassigned to it. The
/// mesocycle this succeeds is never mutated or deleted — it remains
/// reachable, historical, forever, via `TrainingPhase.programInstances`
/// (`.nullify`, never `.cascade`) — only no longer the component's
/// *current* pointer. `TrainingPhase.primaryInstance`/`.secondaryInstances`
/// already read the mix component's current pointer first for exactly
/// this reason (Stage 10R.7A).
///
/// **Reuses, never duplicates, existing orchestration:** calibration
/// gating and materialization still reuse
/// `RequiredSourceCalibrationsUseCase`/`StartPhaseUseCase
/// .materializeOnceCalibrationComplete` exactly as Stage 10R.1C built
/// them. Provenance, exercise carry-forward, and the Mesocycle 1->2/
/// 2->3 mapping tables below are UNCHANGED — this correction touches only
/// the incorrect phase/mix/component-creation responsibility, never the
/// source-program-progression behavior itself (D-10R7-12).
enum StartNextHypertrophyMesocycleUseCase {
    struct Result {
        /// The strategic phase this mesocycle runs inside — always the
        /// SAME `TrainingPhase` passed in as `previousPhase`; a mesocycle
        /// succession never changes which strategic phase is active.
        var phase: TrainingPhase
        var instance: ProgramInstance
        /// Matches `StartPhaseUseCase.Result.componentsAwaitingCalibration`'s
        /// exact meaning, one level down — `true` whenever fresh
        /// `SourceRMCalibration` is still required (which, per the
        /// source archaeology, is every time for a `.rmBased` family:
        /// nothing ever carries an RM forward across mesocycles).
        var awaitingCalibration: Bool
    }

    @discardableResult
    static func start(
        previousPhase: TrainingPhase,
        previousInstance: ProgramInstance,
        asOf: Date,
        ownerUserID: UUID,
        availability: UserAvailability,
        materializationContext: TacticalMaterializationContext,
        context: ModelContext
    ) throws -> Result {
        guard
            let previousDefinition = previousInstance.programDefinition,
            let previousConfiguration = previousDefinition.hypertrophyConfiguration
        else { throw StartNextHypertrophyMesocycleError.previousInstanceHasNoDefinition }

        // Found via the phase's own mix, never via `previousInstance
        // .trainingMixComponents` — the latter goes stale the instant a
        // succession reassigns the component's pointer away from
        // `previousInstance` (SwiftData maintains the declared inverse
        // immediately), which would make a repeated/idempotent call with
        // a now-stale `previousInstance` argument unable to find the
        // component at all. The phase's mix component is the stable
        // handle regardless of which instance it currently points to.
        guard let component = (previousPhase.selectedTrainingMix ?? previousPhase.recommendedTrainingMix)?
            .orderedComponents.first(where: { $0.programmingSystem == .hypertrophy })
        else { throw StartNextHypertrophyMesocycleError.previousInstanceHasNoComponent }

        // Idempotency: a repeated tap / repeated SwiftUI lifecycle
        // evaluation must never create a second next-mesocycle
        // `ProgramInstance` for the same predecessor. Since succession
        // reassigns the SAME component's `.programInstance` pointer (never
        // creates a new component), a call whose `previousInstance` is no
        // longer that pointer's current value means this exact succession
        // already happened — return the existing successor instead of
        // creating a duplicate.
        if let current = component.programInstance, current.id != previousInstance.id {
            let stillRequired = current.programDefinition.map {
                RequiredSourceCalibrationsUseCase.stillRequired(for: $0, instance: current)
            } ?? []
            return Result(phase: previousPhase, instance: current, awaitingCalibration: !stillRequired.isEmpty)
        }

        guard
            let currentIndex = HypertrophyProgramJourney.orderedPhaseTypes.firstIndex(of: previousConfiguration.phaseType),
            HypertrophyProgramJourney.orderedPhaseTypes.indices.contains(currentIndex + 1)
        else { throw StartNextHypertrophyMesocycleError.noNextMesocycle }
        let nextPhaseType = HypertrophyProgramJourney.orderedPhaseTypes[currentIndex + 1]

        let nextConfiguration = HypertrophyProgramConfiguration(
            dayCount: previousConfiguration.dayCount, split: previousConfiguration.split, phaseType: nextPhaseType
        )
        let nextDefinition = try HypertrophyProgramGenerator.generate(
            configuration: nextConfiguration,
            provenance: sourceProvenance(for: nextPhaseType),
            context: context
        )

        let nextInstance = ProgramInstance(ownerUserID: ownerUserID, startDate: asOf, status: .active, priority: previousInstance.priority)
        nextInstance.programDefinition = nextDefinition
        context.insert(nextInstance)
        // Attached to the SAME strategic phase — never a new one.
        previousPhase.addProgramInstance(nextInstance)

        // Stage 10R.2B, Locked Decision 1 — exercise carry-forward: a
        // TrainingOS UX convenience, never claimed as source behavior
        // (the source is silent on exercise continuity across
        // mesocycles — `STAGE10R2_MESOCYCLE2_SOURCE_RECOVERY_DESIGN.md`
        // §4). Runs BEFORE the generic resolver so a valid carried-
        // forward choice is never overwritten; a slot with no valid
        // carry-forward (every superset-partner slot, which has no
        // Mesocycle-1 equivalent at all, plus any slot whose carried
        // exercise turns out incompatible) simply falls through to the
        // exact same deterministic resolution a brand-new instance
        // already uses — never a TrainingOS-invented substitute
        // presented as source content.
        carryForwardExerciseSelections(
            from: previousInstance, to: nextDefinition, previousPhaseType: previousConfiguration.phaseType,
            environment: materializationContext.trainingEnvironment
        )
        try ResolveProgramInstanceExerciseSlotsUseCase.resolve(
            definition: nextDefinition, candidateExercises: materializationContext.strengthCandidateExercises,
            environment: materializationContext.trainingEnvironment
        )

        // Reassign the SAME component's current pointer — never a new
        // `TrainingMix`/`TrainingMixComponent`. The previous instance is
        // left exactly as it is: still attached to `previousPhase
        // .programInstances`, still fully queryable, just no longer this
        // component's *current* instance.
        component.programInstance = nextInstance

        guard RequiredSourceCalibrationsUseCase.stillRequired(for: nextDefinition, instance: nextInstance).isEmpty else {
            return Result(phase: previousPhase, instance: nextInstance, awaitingCalibration: true)
        }

        // Reachable only if calibration somehow already existed (e.g. a
        // defensive re-run) — the ordinary path always defers to
        // `StartPhaseUseCase.materializeOnceCalibrationComplete` via the
        // "Set your starting weights" screen instead, exactly like a
        // first phase start already does.
        if let mix = component.trainingMix {
            _ = try StartPhaseUseCase.materializeOnceCalibrationComplete(
                component: component, instance: nextInstance, phase: previousPhase, mix: mix, asOf: asOf,
                ownerUserID: ownerUserID, performanceProfile: nil, availability: availability,
                materializationContext: materializationContext, context: context
            )
        }
        return Result(phase: previousPhase, instance: nextInstance, awaitingCalibration: false)
    }

    /// Stage 10R.3B: the correct source citation for whichever mesocycle
    /// `phaseType` names — corrects the Stage 10R.2B version, which
    /// hardcoded Mesocycle 2's own sheet name here regardless of which
    /// phase was actually being started (harmless while Mesocycle 2 was
    /// the only reachable next phase, but wrong in principle, and a real
    /// bug once Mesocycle 3 became reachable —
    /// `STAGE10R3_MESOCYCLE3_SOURCE_RECOVERY_DESIGN.md` §12/§17).
    /// `.basicHypertrophy` is unreachable in practice (Mesocycle 1 is
    /// always the plan's first phase, built by `HypertrophyProgramJourney
    /// .build`, never by this use case) but included for switch
    /// exhaustiveness and future-proofing rather than a `fatalError`.
    private static func sourceProvenance(for phaseType: HypertrophyPhaseType) -> ProgramProvenance {
        switch phaseType {
        case .basicHypertrophy:
            return .sourced(file: "3 day full body_Novice.xlsx", sheet: "Mesocycle 1 Basic Hypertrophy", cell: "rows 10-40")
        case .metaboliteFocus:
            return .sourced(file: "3 day full body_Novice.xlsx", sheet: "Mesocycle 2 Metabolite Focus", cell: "rows 11-19, 23-31, 35-43")
        case .resensitization:
            return .sourced(file: "3 day full body_Novice.xlsx", sheet: "Mesocycle 3 Resensitization", cell: "rows 11-17, 21-27, 31-38")
        }
    }

    /// Stage 10R.2A/B: the literal, authored `(previous slot) -> (next
    /// slot)` correspondence for 3-Day Full Body Mesocycle 1 -> Mesocycle
    /// 2 — every one of Mesocycle 1's 24 real slots maps to its
    /// same-category counterpart in Mesocycle 2 (which has 27: the same
    /// 24 plus 3 new superset-partner rows with no Mesocycle-1
    /// equivalent, intentionally left unmapped here). `(dayIndex,
    /// slotIndex)` uses the exact same 0-based, workbook-row-order
    /// convention as `HypertrophyProgramGenerator.SourceRatingPairing` —
    /// indices into each mesocycle's own `orderedTemplateSessions`/
    /// `orderedPrescriptionTemplates`, in the exact order
    /// `HypertrophyProgramGenerator` builds them. A literal table, not a
    /// runtime name-matching heuristic, because matching purely by
    /// "nth occurrence of this category in this day" is provably
    /// ambiguous once a new superset row shifts later occurrences'
    /// positions (e.g. Mesocycle 2's Push day has "Incline Push or Front
    /// Delts" twice — once as the new superset partner, once as the
    /// original standalone row Mesocycle 1 already had — an occurrence-
    /// counting rule cannot tell them apart without this authored table).
    private struct CarryForwardMapping {
        var fromDayIndex: Int
        var fromSlotIndex: Int
        var toDayIndex: Int
        var toSlotIndex: Int
    }

    private static let threeDayFullBodyMesocycle1ToMesocycle2: [CarryForwardMapping] = [
        // Push Emphasis
        CarryForwardMapping(fromDayIndex: 0, fromSlotIndex: 0, toDayIndex: 0, toSlotIndex: 0), // Horizontal Push
        CarryForwardMapping(fromDayIndex: 0, fromSlotIndex: 1, toDayIndex: 0, toSlotIndex: 1), // Chest Isolation or Triceps
        CarryForwardMapping(fromDayIndex: 0, fromSlotIndex: 2, toDayIndex: 0, toSlotIndex: 3), // Incline Push or Front Delts (standalone, not the new partner)
        CarryForwardMapping(fromDayIndex: 0, fromSlotIndex: 3, toDayIndex: 0, toSlotIndex: 4), // Side Delts
        CarryForwardMapping(fromDayIndex: 0, fromSlotIndex: 4, toDayIndex: 0, toSlotIndex: 5), // Vertical Pull
        CarryForwardMapping(fromDayIndex: 0, fromSlotIndex: 5, toDayIndex: 0, toSlotIndex: 6), // Horizontal Pull
        CarryForwardMapping(fromDayIndex: 0, fromSlotIndex: 6, toDayIndex: 0, toSlotIndex: 7), // Hamstrings Isolation
        CarryForwardMapping(fromDayIndex: 0, fromSlotIndex: 7, toDayIndex: 0, toSlotIndex: 8), // Quads

        // Legs Emphasis
        CarryForwardMapping(fromDayIndex: 1, fromSlotIndex: 0, toDayIndex: 1, toSlotIndex: 0), // Quads (1st)
        CarryForwardMapping(fromDayIndex: 1, fromSlotIndex: 1, toDayIndex: 1, toSlotIndex: 1), // Quads (2nd)
        CarryForwardMapping(fromDayIndex: 1, fromSlotIndex: 2, toDayIndex: 1, toSlotIndex: 2), // Hamstrings Hip Hinge
        CarryForwardMapping(fromDayIndex: 1, fromSlotIndex: 3, toDayIndex: 1, toSlotIndex: 3), // Side Delts (standalone/primary)
        CarryForwardMapping(fromDayIndex: 1, fromSlotIndex: 4, toDayIndex: 1, toSlotIndex: 5), // Vertical Pull
        CarryForwardMapping(fromDayIndex: 1, fromSlotIndex: 5, toDayIndex: 1, toSlotIndex: 6), // Horizontal Pull
        CarryForwardMapping(fromDayIndex: 1, fromSlotIndex: 6, toDayIndex: 1, toSlotIndex: 7), // Incline Push or Front Delts
        CarryForwardMapping(fromDayIndex: 1, fromSlotIndex: 7, toDayIndex: 1, toSlotIndex: 8), // Horizontal Push

        // Pull Emphasis
        CarryForwardMapping(fromDayIndex: 2, fromSlotIndex: 0, toDayIndex: 2, toSlotIndex: 0), // Vertical Pull
        CarryForwardMapping(fromDayIndex: 2, fromSlotIndex: 1, toDayIndex: 2, toSlotIndex: 1), // Horizontal Pull
        CarryForwardMapping(fromDayIndex: 2, fromSlotIndex: 2, toDayIndex: 2, toSlotIndex: 2), // Rear Delts or Side Delts
        CarryForwardMapping(fromDayIndex: 2, fromSlotIndex: 3, toDayIndex: 2, toSlotIndex: 3), // Biceps (standalone/primary)
        CarryForwardMapping(fromDayIndex: 2, fromSlotIndex: 4, toDayIndex: 2, toSlotIndex: 5), // Horizontal Push
        CarryForwardMapping(fromDayIndex: 2, fromSlotIndex: 5, toDayIndex: 2, toSlotIndex: 6), // Incline Push
        CarryForwardMapping(fromDayIndex: 2, fromSlotIndex: 6, toDayIndex: 2, toSlotIndex: 7), // Glutes
        CarryForwardMapping(fromDayIndex: 2, fromSlotIndex: 7, toDayIndex: 2, toSlotIndex: 8), // Hamstrings Isolation
    ]

    /// Stage 10R.3B: the literal, authored `(previous slot) -> (next
    /// slot)` correspondence for 3-Day Full Body Mesocycle 2 -> Mesocycle
    /// 3 — a genuinely NEW table, not `threeDayFullBodyMesocycle1ToMesocycle2`
    /// reused, because Mesocycle 3 has a different slot count/shape (22,
    /// not 24 or 27) and drops "Chest Isolation or Triceps" entirely
    /// (`STAGE10R3_MESOCYCLE3_SOURCE_RECOVERY_DESIGN.md` §10/§14). Every
    /// Mesocycle-2-only row — the 3 superset partners, "Chest Isolation or
    /// Triceps," and the 2nd Legs-day Quads occurrence (Mesocycle 3 has
    /// only 1) — has no Mesocycle-3 equivalent and is intentionally left
    /// unmapped here, falling through to the same deterministic
    /// resolution a fresh instance already uses, exactly like
    /// Mesocycle 1 -> 2's own unmapped rows already do.
    private static let threeDayFullBodyMesocycle2ToMesocycle3: [CarryForwardMapping] = [
        // Push Emphasis
        CarryForwardMapping(fromDayIndex: 0, fromSlotIndex: 0, toDayIndex: 0, toSlotIndex: 0), // Horizontal Push
        CarryForwardMapping(fromDayIndex: 0, fromSlotIndex: 3, toDayIndex: 0, toSlotIndex: 1), // Incline Push or Front Delts (standalone, not the M2 superset partner)
        CarryForwardMapping(fromDayIndex: 0, fromSlotIndex: 4, toDayIndex: 0, toSlotIndex: 2), // Side Delts
        CarryForwardMapping(fromDayIndex: 0, fromSlotIndex: 5, toDayIndex: 0, toSlotIndex: 3), // Vertical Pull
        CarryForwardMapping(fromDayIndex: 0, fromSlotIndex: 6, toDayIndex: 0, toSlotIndex: 4), // Horizontal Pull
        CarryForwardMapping(fromDayIndex: 0, fromSlotIndex: 7, toDayIndex: 0, toSlotIndex: 5), // Hamstrings Isolation
        CarryForwardMapping(fromDayIndex: 0, fromSlotIndex: 8, toDayIndex: 0, toSlotIndex: 6), // Quads

        // Legs Emphasis
        CarryForwardMapping(fromDayIndex: 1, fromSlotIndex: 0, toDayIndex: 1, toSlotIndex: 0), // Quads (1st occurrence — M3 has only 1)
        CarryForwardMapping(fromDayIndex: 1, fromSlotIndex: 2, toDayIndex: 1, toSlotIndex: 1), // Hamstrings Hip Hinge
        CarryForwardMapping(fromDayIndex: 1, fromSlotIndex: 3, toDayIndex: 1, toSlotIndex: 2), // Side Delts (standalone/primary, not the M2 superset partner)
        CarryForwardMapping(fromDayIndex: 1, fromSlotIndex: 5, toDayIndex: 1, toSlotIndex: 3), // Vertical Pull
        CarryForwardMapping(fromDayIndex: 1, fromSlotIndex: 6, toDayIndex: 1, toSlotIndex: 4), // Horizontal Pull
        CarryForwardMapping(fromDayIndex: 1, fromSlotIndex: 7, toDayIndex: 1, toSlotIndex: 5), // Incline Push or Front Delts
        CarryForwardMapping(fromDayIndex: 1, fromSlotIndex: 8, toDayIndex: 1, toSlotIndex: 6), // Horizontal Push

        // Pull Emphasis
        CarryForwardMapping(fromDayIndex: 2, fromSlotIndex: 0, toDayIndex: 2, toSlotIndex: 0), // Vertical Pull
        CarryForwardMapping(fromDayIndex: 2, fromSlotIndex: 1, toDayIndex: 2, toSlotIndex: 1), // Horizontal Pull
        CarryForwardMapping(fromDayIndex: 2, fromSlotIndex: 2, toDayIndex: 2, toSlotIndex: 2), // Rear Delts or Side Delts
        CarryForwardMapping(fromDayIndex: 2, fromSlotIndex: 3, toDayIndex: 2, toSlotIndex: 3), // Biceps (standalone/primary, not the M2 superset partner)
        CarryForwardMapping(fromDayIndex: 2, fromSlotIndex: 5, toDayIndex: 2, toSlotIndex: 4), // Horizontal Push
        CarryForwardMapping(fromDayIndex: 2, fromSlotIndex: 6, toDayIndex: 2, toSlotIndex: 5), // Incline Push
        CarryForwardMapping(fromDayIndex: 2, fromSlotIndex: 7, toDayIndex: 2, toSlotIndex: 6), // Glutes
        CarryForwardMapping(fromDayIndex: 2, fromSlotIndex: 8, toDayIndex: 2, toSlotIndex: 7), // Hamstrings Isolation
    ]

    /// Stage 10R.3B: which authored table applies to a `previous ->
    /// next` transition — selected by the PREVIOUS phase's type, since
    /// that's whose slot layout the `fromDayIndex`/`fromSlotIndex` side of
    /// each mapping indexes into. `.resensitization` returns `[]`
    /// (unreachable in practice — `start()` already throws `.noNextPhase`
    /// before this point once Mesocycle 3 has no successor — included for
    /// exhaustiveness, not a silent guess at a 4th mesocycle's mapping).
    private static func carryForwardMapping(fromPreviousPhaseType phaseType: HypertrophyPhaseType) -> [CarryForwardMapping] {
        switch phaseType {
        case .basicHypertrophy: return threeDayFullBodyMesocycle1ToMesocycle2
        case .metaboliteFocus: return threeDayFullBodyMesocycle2ToMesocycle3
        case .resensitization: return []
        }
    }

    private static func carryForwardExerciseSelections(
        from previousInstance: ProgramInstance, to nextDefinition: ProgramDefinition, previousPhaseType: HypertrophyPhaseType,
        environment: TrainingEnvironment?
    ) {
        guard let previousDefinition = previousInstance.programDefinition else { return }
        let previousSlotsByDay = previousDefinition.orderedTemplateSessions.map { session in
            session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).compactMap(\.exerciseSlot)
        }
        let nextSlotsByDay = nextDefinition.orderedTemplateSessions.map { session in
            session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).compactMap(\.exerciseSlot)
        }

        for mapping in carryForwardMapping(fromPreviousPhaseType: previousPhaseType) {
            guard
                previousSlotsByDay.indices.contains(mapping.fromDayIndex),
                previousSlotsByDay[mapping.fromDayIndex].indices.contains(mapping.fromSlotIndex),
                nextSlotsByDay.indices.contains(mapping.toDayIndex),
                nextSlotsByDay[mapping.toDayIndex].indices.contains(mapping.toSlotIndex)
            else { continue }

            let previousSlot = previousSlotsByDay[mapping.fromDayIndex][mapping.fromSlotIndex]
            let nextSlot = nextSlotsByDay[mapping.toDayIndex][mapping.toSlotIndex]

            guard let carriedExercise = SubstituteExerciseUseCase.resolvedExercise(for: previousSlot, in: previousInstance) else { continue }
            guard SubstitutionValidator.isValid(candidate: carriedExercise, for: nextSlot, environment: environment) else { continue }
            nextSlot.resolvedExercise = carriedExercise
        }
    }
}
