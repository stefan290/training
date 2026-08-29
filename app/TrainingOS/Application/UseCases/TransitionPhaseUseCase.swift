import Foundation
import SwiftData

enum PhaseTransitionError: Error, Equatable {
    /// Mirrors `StartPhaseError.phaseNotPlanned`'s discipline — a
    /// transition only ever runs from a genuinely running phase, never
    /// re-runs on one already ended.
    case outgoingPhaseNotActive
    /// `TrainingPlan.orderedPhases` has nothing after `outgoingPhase` —
    /// never fabricated; the caller must extend the plan first
    /// (`LongTermPlanner.reviseStrategicPlan`, out of this use case's scope).
    case noNextPhaseInPlan
    /// `outgoingPhase`/`nextPhase` could not be re-fetched by ID inside
    /// the isolated scratch context — this means the caller invoked
    /// `transition` before saving state the scratch context's own
    /// committed-store-only view needs to see (Stage 10R.7A's atomic
    /// transaction boundary only ever sees already-persisted state, same
    /// discipline `AdvanceTacticalWeekUseCase` already requires).
    case outgoingOrNextPhaseNotYetPersisted
}

/// Stage 7 (Tactical Planning Orchestration), Slice 3 — closes the
/// runtime gap `RollTacticalWindowUseCase`'s own doc comment already
/// named: "extending a Steady State component beyond its own generated
/// ProgramDefinition... would mean generating a new ProgramInstance,
/// which is a phase-transition-shaped event... not built this pass."
///
/// Orchestration only, no new mechanism, no new domain rule: ends the
/// outgoing phase exactly the way `PhaseStatus`'s own documented
/// PLANNED -> ACTIVE -> COMPLETED lifecycle already describes, finds the
/// next phase via `TrainingPlan.orderedPhases`
/// (`TrainingPhaseCompletion.nextStrategicPhase` — already well-defined —
/// `TrainingPhase.swift`'s own doc comment: "the phase *sequencing*
/// concept... needed no new entity — `TrainingPlan.orderedPhases` already
/// provides it"), and starts it through the exact same
/// `StartPhaseUseCase.start` entry point every phase start already uses
/// — never a second phase-start mechanism. **Never generates a
/// replacement phase** (D-10R7-1) — the next phase must already exist,
/// pre-planned by `AcceptStrategicPlanUseCase`; this is corrective, not
/// new, behavior (it already threw `.noNextPhaseInPlan` rather than
/// fabricating one, even before Stage 10R.7A).
///
/// **Never touches history.** Only `TrainingPhase.status`/`ProgramInstance.status`
/// are mutated on the OUTGOING phase — never its Sessions, SetResults,
/// PersonalRecords, PerformanceProfiles, or PlannerDecisions (CLAUDE.md
/// rule 1). `ProgramInstance.sessions` relates back with `.nullify`
/// precisely so this is safe.
///
/// **Never carries instance-specific state forward.** The next phase's
/// components are always not-yet-instantiated (fresh `TrainingMixComponent`s
/// from whichever `TrainingMix` the caller selected for the new phase),
/// so `StartPhaseUseCase.start` always creates brand-new `ProgramInstance`s
/// for it — `SlotSelectionOverride`/`ActivitySelectionOverride` are
/// `ProgramInstance`-scoped by construction and never referenced by the
/// new instances. The one thing that IS carried forward is real,
/// legitimately global user history — the same `PerformanceProfile`
/// object is simply passed through unchanged, exactly as it would be for
/// any other `StartPhaseUseCase.start` call; it was never phase-scoped to
/// begin with, so there is nothing to specially transfer.
///
/// **Stage 10R.7A — atomic strategic transition
/// (`STAGE10R7_STRATEGIC_PHASE_LIFECYCLE_DESIGN.md`, D-10R7-7/D-10R7-8).**
/// Before this fix, `outgoingPhase`/its instances were marked `.completed`
/// directly on the caller's own context BEFORE the one call
/// (`StartPhaseUseCase.start`) that can fail — a genuine, live partial-
/// state risk (old phase permanently completed, no new active phase, no
/// executable Sessions, if that call threw). The whole attempt now runs
/// against an isolated scratch `ModelContext` (autosave disabled),
/// exactly the proven Stage 10R.6 pattern
/// (`AdvanceTacticalWeekUseCase`'s own doc comment has the full empirical
/// justification): on any failure the scratch context is simply never
/// saved and discarded, so the caller's own context — and the
/// still-`.active` outgoing phase within it — is never touched at all.
/// On success, one `save()` commits the whole transition (completed
/// outgoing phase + active next phase + every immediately-materializable
/// component's ProgramInstance/Sessions + the coordinated schedule)
/// atomically, and the caller's own context is refreshed by re-fetching
/// every phase/instance the transition touched, by ID — the same
/// bounded, mechanical fix Stage 10R.6 established (a `ProgramInstance`'s
/// `.sessions`/`.status` is a direct, one-level relationship on the
/// refetched object itself, which reliably refreshes on a direct
/// refetch).
///
/// **D-10R7-9 — calibration remains a valid, non-failing intermediate
/// state, unchanged:** `StartPhaseUseCase.start` already never throws
/// merely because a `.rmBased` component still needs fresh
/// `SourceRMCalibration` — it returns `componentsAwaitingCalibration`
/// with that component's `ProgramInstance` already created but zero
/// Sessions materialized for it. This atomicity fix does not change that
/// contract at all: "phase active, some component awaiting calibration,
/// no fabricated tactical content for it" is still a fully coherent,
/// successfully-committed transition, not a transaction failure.
enum TransitionPhaseUseCase {
    struct Result {
        var completedPhase: TrainingPhase
        var nextPhase: TrainingPhase
        var startResult: StartPhaseUseCase.Result
    }

    @discardableResult
    static func transition(
        from outgoingPhase: TrainingPhase,
        toNextPhaseWithMix nextMix: TrainingMix,
        asOf: Date,
        ownerUserID: UUID,
        performanceProfile: PerformanceProfile?,
        availability: UserAvailability,
        materializationContext: TacticalMaterializationContext,
        context: ModelContext
    ) throws -> Result {
        // Cheap, read-only preflight on the caller's own context — nothing
        // has been touched yet.
        guard outgoingPhase.status == .active else { throw PhaseTransitionError.outgoingPhaseNotActive }
        guard let nextPhase = TrainingPhaseCompletion.nextStrategicPhase(for: outgoingPhase) else {
            throw PhaseTransitionError.noNextPhaseInPlan
        }

        let outgoingPhaseID = outgoingPhase.persistentModelID
        let nextPhaseID = nextPhase.persistentModelID
        let nextMixID = nextMix.persistentModelID

        // The isolated scratch context this entire attempt runs against —
        // see this type's own top-level doc comment for the full
        // reasoning (mirrors `AdvanceTacticalWeekUseCase`, Stage 10R.6).
        let scratchContext = ModelContext(context.container)
        scratchContext.autosaveEnabled = false

        guard
            let scratchOutgoing = try scratchContext.fetch(FetchDescriptor<TrainingPhase>(predicate: #Predicate { $0.persistentModelID == outgoingPhaseID })).first,
            let scratchNext = try scratchContext.fetch(FetchDescriptor<TrainingPhase>(predicate: #Predicate { $0.persistentModelID == nextPhaseID })).first
        else { throw PhaseTransitionError.outgoingOrNextPhaseNotYetPersisted }
        // `nextMix` is very often a freshly-proposed candidate from
        // `LongTermPlanner.proposeTrainingMix` (`mix.phase == nil`) that
        // the caller never explicitly inserted/saved anywhere — that is
        // the normal, expected shape of a caller-selected "next phase
        // mix," not a caller bug. Such an object has no existing
        // `ModelContext` association yet, so it is safe to insert
        // directly into the scratch context here. If it DOES already
        // exist in the store (a mix some earlier step already persisted),
        // the fetch finds and reuses that real row instead of double-
        // inserting it.
        let scratchMix: TrainingMix
        if let existing = try scratchContext.fetch(FetchDescriptor<TrainingMix>(predicate: #Predicate { $0.persistentModelID == nextMixID })).first {
            scratchMix = existing
        } else {
            scratchContext.insert(nextMix)
            scratchMix = nextMix
        }
        // Re-verify eligibility fresh inside the scratch context too —
        // belt and suspenders, matching `AdvanceTacticalWeekUseCase`'s own
        // "never trust anything computed earlier" discipline.
        guard scratchOutgoing.status == .active else { throw PhaseTransitionError.outgoingPhaseNotActive }

        scratchOutgoing.status = .completed
        for instance in scratchOutgoing.programInstances {
            instance.status = .completed
        }

        let decision = PlannerDecision(
            decidedAt: asOf, decisionType: .phaseSelected, source: .systemRecommended,
            reasonCode: .phaseSelectedForGoal,
            factors: ["outgoingPhaseID": scratchOutgoing.id.uuidString, "outgoingPhaseType": scratchOutgoing.type.rawValue, "nextPhaseType": scratchNext.type.rawValue],
            explanation: "\(scratchOutgoing.type.rawValue) phase completed; transitioning to \(scratchNext.type.rawValue) with \(scratchMix.name).",
            phase: scratchNext, trainingMix: scratchMix
        )
        scratchContext.insert(decision)

        // `materializationContext`'s candidate `Exercise` arrays are bound
        // to the CALLER's context — `StartPhaseUseCase.start` (below)
        // assigns them onto freshly-created `ExerciseSlot`s that belong to
        // the SCRATCH context, and SwiftData fatals immediately on any
        // relationship spanning two different contexts ("attempting to
        // relate model ... to destination model ... from destination's
        // model context" — discovered empirically while implementing this
        // fix). Every candidate `Exercise` is expected to already be a
        // real, persisted row (every real caller fetches its candidate
        // pool from the store), so re-fetching each by ID directly into
        // the scratch context is the same bounded, mechanical fix already
        // used for `outgoingPhase`/`nextPhase`/`nextMix` above — never a
        // second candidate-selection mechanism.
        let scratchMaterializationContext = TacticalMaterializationContext(
            equipmentProfile: materializationContext.equipmentProfile,
            strengthCandidateExercises: try materializationContext.strengthCandidateExercises.compactMap { exercise in
                let exerciseID = exercise.persistentModelID
                return try scratchContext.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.persistentModelID == exerciseID })).first
            },
            functionalFitnessCandidateExercises: try materializationContext.functionalFitnessCandidateExercises.compactMap { exercise in
                let exerciseID = exercise.persistentModelID
                return try scratchContext.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.persistentModelID == exerciseID })).first
            }
        )

        // Step 6: invoke the real phase start exactly once, entirely
        // against the scratch context. Any throw here leaves
        // `scratchContext` un-saved — it is simply discarded, and the
        // caller's own context (outgoing phase still `.active`) was never
        // touched.
        let scratchStartResult = try StartPhaseUseCase.start(
            phase: scratchNext, mix: scratchMix, asOf: asOf, ownerUserID: ownerUserID,
            performanceProfile: performanceProfile, availability: availability,
            materializationContext: scratchMaterializationContext, context: scratchContext
        )

        // Persist — one call, the entire strategic transition together,
        // atomically.
        try scratchContext.save()

        // `scratchMix` may have just transitioned from a temporary,
        // never-inserted identifier to a real, permanent one as a direct
        // effect of the insert+save above (confirmed empirically: a
        // pre-insertion `persistentModelID` capture does NOT match what
        // the same object resolves to in the store after being inserted
        // and saved for the first time) — re-capture it now, after the
        // save, rather than reusing the possibly-stale `nextMixID`
        // captured before `nextMix` had ever been inserted anywhere.
        let finalNextMixID = scratchMix.persistentModelID

        // Refresh the caller's own context: re-fetch, by ID, every
        // TrainingPhase/ProgramInstance the transition touched, directly
        // on `context` — see this type's own doc comment for why the
        // root objects alone are not enough for every reader.
        guard
            let refreshedOutgoing = try context.fetch(FetchDescriptor<TrainingPhase>(predicate: #Predicate { $0.persistentModelID == outgoingPhaseID })).first,
            let refreshedNext = try context.fetch(FetchDescriptor<TrainingPhase>(predicate: #Predicate { $0.persistentModelID == nextPhaseID })).first,
            let refreshedMix = try context.fetch(FetchDescriptor<TrainingMix>(predicate: #Predicate { $0.persistentModelID == finalNextMixID })).first
        else { throw PhaseTransitionError.outgoingOrNextPhaseNotYetPersisted }
        for instance in refreshedOutgoing.programInstances {
            let instanceID = instance.persistentModelID
            _ = try? context.fetch(FetchDescriptor<ProgramInstance>(predicate: #Predicate { $0.persistentModelID == instanceID }))
        }
        var refreshedInstancesByComponent: [UUID: ProgramInstance] = [:]
        for (componentID, scratchInstance) in scratchStartResult.instancesByComponent {
            let instanceID = scratchInstance.persistentModelID
            if let refreshed = try? context.fetch(FetchDescriptor<ProgramInstance>(predicate: #Predicate { $0.persistentModelID == instanceID })).first {
                refreshedInstancesByComponent[componentID] = refreshed
            }
        }
        // `scheduleProposal`'s own embedded `Session` references are left
        // exactly as `StartPhaseUseCase.start` produced them (scratch-
        // context-bound) — every field the rest of this Result exposes is
        // refreshed onto the caller's context; this one is read-only-safe
        // (its data is already durably committed by the save above) but
        // not refreshed onto the caller's context, since doing so would
        // require rebuilding placements rather than a plain by-ID refetch.
        let refreshedStartResult = StartPhaseUseCase.Result(
            phase: refreshedNext, mix: refreshedMix, instancesByComponent: refreshedInstancesByComponent,
            scheduleProposal: scratchStartResult.scheduleProposal,
            componentsAwaitingCalibration: scratchStartResult.componentsAwaitingCalibration
        )

        return Result(completedPhase: refreshedOutgoing, nextPhase: refreshedNext, startResult: refreshedStartResult)
    }
}
