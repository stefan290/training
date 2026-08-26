import Foundation
import SwiftData

enum StartNextHypertrophyPhaseError: Error, Equatable {
    case previousPhaseHasNoPlan
    case previousInstanceHasNoDefinition
    /// `previousInstance`'s `HypertrophyPhaseType` has no next phase in
    /// `HypertrophyProgramJourney.orderedPhaseTypes` (i.e. it was already
    /// `.resensitization`).
    case noNextPhase
}

/// Stage 10R.2B: the real production entry point for the explicit,
/// user-initiated Mesocycle-to-Mesocycle transition
/// (`STAGE3_DECISION_MEMO.md` Decision A1 — `transitionTrigger:
/// .userInitiated`, never automatic; `PROGRAMMING_SYSTEM_MODEL.md` §5.1).
/// A new mesocycle is represented exactly like Decision A1 already
/// specifies — a new `ProgramDefinition` + new `ProgramInstance` + next
/// `TrainingPhase`, never a new "mesocycle" entity, and never a mutation
/// of the previous (now-historical, immutable) phase/instance.
///
/// **Reuses, never duplicates, existing orchestration:** the per-phase
/// `ProgramDefinition`/`TrainingPhase`/`ProgramInstance` construction
/// shape is the same one `HypertrophyProgramJourney.build`'s own loop
/// body already establishes (that type's own doc comment: "No new
/// 'ProgramJourney' entity exists — `TrainingPlan.orderedPhases`...
/// already provides the sequencing"); calibration gating and
/// materialization reuse `RequiredSourceCalibrationsUseCase`/
/// `StartPhaseUseCase.materializeOnceCalibrationComplete` exactly as
/// Stage 10R.1C already built them — this use case adds only what
/// neither of those already does: building the next phase from an
/// existing predecessor (rather than all phases up front), exercise
/// carry-forward, and wiring a `TrainingMix`/`TrainingMixComponent` so
/// the existing "Set your starting weights" screen picks the new
/// instance up automatically.
enum StartNextHypertrophyPhaseUseCase {
    struct Result {
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
        guard let plan = previousPhase.plan else { throw StartNextHypertrophyPhaseError.previousPhaseHasNoPlan }
        guard
            let previousDefinition = previousInstance.programDefinition,
            let previousConfiguration = previousDefinition.hypertrophyConfiguration
        else { throw StartNextHypertrophyPhaseError.previousInstanceHasNoDefinition }

        guard
            let currentIndex = HypertrophyProgramJourney.orderedPhaseTypes.firstIndex(of: previousConfiguration.phaseType),
            HypertrophyProgramJourney.orderedPhaseTypes.indices.contains(currentIndex + 1)
        else { throw StartNextHypertrophyPhaseError.noNextPhase }
        let nextPhaseType = HypertrophyProgramJourney.orderedPhaseTypes[currentIndex + 1]

        // Idempotency: a repeated tap / repeated SwiftUI lifecycle
        // evaluation must never create a second next-phase for the same
        // predecessor — return the already-created phase/instance
        // instead of duplicating `TrainingPhase`/`ProgramInstance`/
        // sessions/calibration requirements.
        if let existing = existingNextPhase(in: plan, matching: nextPhaseType, configuration: previousConfiguration) {
            let stillRequired = existing.instance.programDefinition.map {
                RequiredSourceCalibrationsUseCase.stillRequired(for: $0, instance: existing.instance)
            } ?? []
            return Result(phase: existing.phase, instance: existing.instance, awaitingCalibration: !stillRequired.isEmpty)
        }

        let nextConfiguration = HypertrophyProgramConfiguration(
            dayCount: previousConfiguration.dayCount, split: previousConfiguration.split, phaseType: nextPhaseType
        )
        let nextDefinition = try HypertrophyProgramGenerator.generate(
            configuration: nextConfiguration,
            provenance: .sourced(
                file: "3 day full body_Novice.xlsx", sheet: "Mesocycle 2 Metabolite Focus",
                cell: "rows 11-19, 23-31, 35-43"
            ),
            context: context
        )

        let nextPhase = TrainingPhase(type: previousPhase.type, startDate: asOf, priorityRule: previousPhase.priorityRule, status: .active)
        context.insert(nextPhase)
        plan.addPhase(nextPhase)

        let nextInstance = ProgramInstance(ownerUserID: ownerUserID, startDate: asOf, status: .active, priority: previousInstance.priority)
        nextInstance.programDefinition = nextDefinition
        context.insert(nextInstance)
        nextPhase.addProgramInstance(nextInstance)

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
        carryForwardExerciseSelections(from: previousInstance, to: nextDefinition)
        ResolveProgramInstanceExerciseSlotsUseCase.resolve(
            definition: nextDefinition, candidateExercises: materializationContext.strengthCandidateExercises
        )

        // Mirror the previous phase's own TrainingMix/Component shape —
        // never guessed values; this is the same cadence/day-count
        // program continuing under a new mesocycle, so its scheduling
        // metadata should too. `nextComponent.programInstance` is set
        // immediately (never left dangling) so `SourceRMCalibrationViewModel
        // .attemptMaterialization`'s existing `instance.trainingMixComponents.first`
        // lookup finds it with zero changes to that already-shipped code.
        if let previousComponent = previousInstance.trainingMixComponents.first {
            let nextMix = TrainingMix(kind: .selected, name: previousComponent.trainingMix?.name ?? nextDefinition.name)
            context.insert(nextMix)
            nextPhase.addTrainingMix(nextMix)
            let nextComponent = TrainingMixComponent(
                label: previousComponent.label, programmingSystem: .hypertrophy, priority: previousComponent.priority,
                frequency: previousComponent.frequency, flexibility: previousComponent.flexibility,
                allowsDoubleSessionPairing: previousComponent.allowsDoubleSessionPairing,
                preferredDays: previousComponent.preferredDays, requiredSpacingDays: previousComponent.requiredSpacingDays
            )
            context.insert(nextComponent)
            nextMix.addComponent(nextComponent)
            nextComponent.programInstance = nextInstance
        }

        guard RequiredSourceCalibrationsUseCase.stillRequired(for: nextDefinition, instance: nextInstance).isEmpty else {
            return Result(phase: nextPhase, instance: nextInstance, awaitingCalibration: true)
        }

        // Reachable only if calibration somehow already existed (e.g. a
        // defensive re-run) — the ordinary path always defers to
        // `StartPhaseUseCase.materializeOnceCalibrationComplete` via the
        // "Set your starting weights" screen instead, exactly like a
        // first phase start already does.
        if let component = nextInstance.trainingMixComponents.first, let mix = component.trainingMix {
            _ = try StartPhaseUseCase.materializeOnceCalibrationComplete(
                component: component, instance: nextInstance, phase: nextPhase, mix: mix, asOf: asOf,
                ownerUserID: ownerUserID, performanceProfile: nil, availability: availability,
                materializationContext: materializationContext, context: context
            )
        }
        return Result(phase: nextPhase, instance: nextInstance, awaitingCalibration: false)
    }

    /// Idempotency guard's lookup — a phase in `plan` whose primary
    /// instance's definition already matches `phaseType`/the same
    /// day-count and split as the phase being started.
    private static func existingNextPhase(
        in plan: TrainingPlan, matching phaseType: HypertrophyPhaseType, configuration: HypertrophyProgramConfiguration
    ) -> (phase: TrainingPhase, instance: ProgramInstance)? {
        for phase in plan.orderedPhases {
            guard
                let instance = phase.primaryInstance,
                let config = instance.programDefinition?.hypertrophyConfiguration,
                config.phaseType == phaseType, config.dayCount == configuration.dayCount, config.split == configuration.split
            else { continue }
            return (phase, instance)
        }
        return nil
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

    private static func carryForwardExerciseSelections(from previousInstance: ProgramInstance, to nextDefinition: ProgramDefinition) {
        guard let previousDefinition = previousInstance.programDefinition else { return }
        let previousSlotsByDay = previousDefinition.orderedTemplateSessions.map { session in
            session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).compactMap(\.exerciseSlot)
        }
        let nextSlotsByDay = nextDefinition.orderedTemplateSessions.map { session in
            session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).compactMap(\.exerciseSlot)
        }

        for mapping in threeDayFullBodyMesocycle1ToMesocycle2 {
            guard
                previousSlotsByDay.indices.contains(mapping.fromDayIndex),
                previousSlotsByDay[mapping.fromDayIndex].indices.contains(mapping.fromSlotIndex),
                nextSlotsByDay.indices.contains(mapping.toDayIndex),
                nextSlotsByDay[mapping.toDayIndex].indices.contains(mapping.toSlotIndex)
            else { continue }

            let previousSlot = previousSlotsByDay[mapping.fromDayIndex][mapping.fromSlotIndex]
            let nextSlot = nextSlotsByDay[mapping.toDayIndex][mapping.toSlotIndex]

            guard let carriedExercise = SubstituteExerciseUseCase.resolvedExercise(for: previousSlot, in: previousInstance) else { continue }
            guard SubstitutionValidator.isValid(candidate: carriedExercise, for: nextSlot) else { continue }
            nextSlot.resolvedExercise = carriedExercise
        }
    }
}
