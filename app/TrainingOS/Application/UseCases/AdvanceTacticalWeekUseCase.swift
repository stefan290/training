import Foundation
import SwiftData

/// Stage 10R.4B: the ONLY production-safe entry point to
/// `RollTacticalWindowUseCase.rollForward`
/// (`STAGE10R4_TACTICAL_ROLLFORWARD_DESIGN.md` §6/§17 — "CRITICAL — SAFE
/// ROLLFORWARD WRAPPER"). `rollForward` itself has no idempotency guard
/// (proven by the Stage 10R.4 audit: calling it twice in a row silently
/// advances Week N -> N+1 -> N+2 with no intervening real week trained).
/// This use case re-derives eligibility from persisted state at
/// invocation time, every time — it never trusts a stale ViewModel
/// boolean, and a repeated immediate call is a safe no-op because the
/// newly-materialized week's Sessions are freshly `.scheduled` (not
/// terminal), so `TacticalWeekCompletion.canAdvanceTacticalWeek`
/// immediately re-evaluates to `false`.
///
/// Never starts a new mesocycle, never mutates `TrainingPhase`/
/// `ProgramInstance.status` (Locked Decision 4 — that remains
/// `StartNextHypertrophyPhaseUseCase`'s job, triggered separately, by
/// the user, once `TacticalWeekCompletion.isInstanceExhausted`), never
/// invokes `LongTermPlanner` or regenerates the strategic plan.
///
/// **Stage 10R.6A — atomic mixed-modality advancement.** Every eligible,
/// non-exhausted, rollForward-managed component of the mix must advance
/// its tactical week together, or none may (D-10R6-1). The whole attempt
/// — preflight excepted, which is read-only — runs against a throwaway
/// `ModelContext` constructed from the caller's own `context.container`,
/// never the caller's shared, long-lived context directly:
///
/// - **Why not `context.rollback()` on the caller's context (rejected,
///   D-10R6-2/D-10R6-3):** `ModelContext.rollback()` has no selective or
///   scoped form — it discards every uncommitted change in that context,
///   not just this operation's own. Calling it on the app's shared main
///   context would also discard any unrelated pending mutation a caller
///   had in flight, unconditionally failing the mandatory "unrelated
///   pending mutation U survives" guarantee (D-10R6-4) by construction.
/// - **Why a scratch context (chosen):** a freshly constructed
///   `ModelContext(container)` starts with nothing pending in it but this
///   operation's own work — proven by direct empirical probing of
///   SwiftData's real cross-context behavior (see the Stage 10R.6
///   implementation report). On any failure — a thrown materializer
///   error, an ineligible preflight result, anything — this method simply
///   never calls `save()` on the scratch context and lets it fall out of
///   scope; nothing it inserted ever reaches the store, and the caller's
///   own context (and anything pending in it) was never touched at all.
///   On success, exactly one `save()` call commits the entire batch —
///   every component's new week, together — as a single atomic store
///   transaction.
/// - **Autosave (D-10R6-5):** the scratch context has
///   `autosaveEnabled = false` set explicitly, so no scene-phase change,
///   backgrounding, or other SwiftData-internal trigger can persist a
///   partial attempt through it — only this method's own single, final
///   `save()` call can ever commit anything through this context. The
///   caller's own shared context is never mutated during the attempt at
///   all (every insert happens against the scratch context), so whatever
///   autosave policy the shared context has is irrelevant to this
///   operation's atomicity — there is nothing of this attempt in it to
///   autosave, successful or not.
/// - **Caller-side freshness:** a successful advance mutates a
///   `ProgramInstance` (its `sessions`) that the caller's own context may
///   already have cached from an earlier read. Re-fetching only the root
///   `TrainingPhase` does not cascade freshness to an already-cached
///   nested `ProgramInstance.sessions` (proven empirically — nested
///   relationship staleness survives even a root refetch, and even
///   `ModelContext.processPendingChanges()`). So this method explicitly
///   re-fetches, by ID, every `ProgramInstance` that actually rolled,
///   directly on the caller's own `context` — a bounded, mechanical fix
///   (this is a *direct*, one-level fetch of each affected instance
///   itself, which reliably refreshes its own `.sessions`), not a
///   sprawling re-fetch of the whole object graph.
enum AdvanceTacticalWeekUseCase {
    enum Outcome: Equatable {
        /// The mix genuinely was not eligible at invocation time — no
        /// component was in a state where an advance was safe/possible.
        /// Not an error: this is the expected, safe result of a repeated
        /// or premature call.
        case notEligible
        /// `rollForward` ran and produced no new sessions for any
        /// component (e.g. every eligible component turned out already
        /// exhausted once actually checked against the definition's real
        /// week count) — distinct from `.notEligible` only in that the
        /// pre-check passed but `rollForward` itself still found nothing
        /// to roll; reported separately so a caller can tell the two
        /// apart if it ever matters, though both mean "nothing changed."
        case nothingRolled
        case advanced
    }

    /// Re-derives eligibility fresh from `context`, then — only if still
    /// eligible — invokes `RollTacticalWindowUseCase.rollForward` exactly
    /// once, atomically, against an isolated scratch context, and saves.
    /// `phase` supplies the `TrainingMix` to advance (its
    /// `selectedTrainingMix`, falling back to `recommendedTrainingMix` —
    /// the same "selected wins once it exists" precedent
    /// `PhaseDetailViewModel.activeComponents` already uses).
    ///
    /// Rethrows `TacticalAdvancementPreflightError` (D-10R6-6 — a
    /// predictable, deterministic missing prerequisite, detected before
    /// any component is touched) and whatever `RollTacticalWindowUseCase
    /// .rollForward` itself throws (an unexpected materializer failure,
    /// caught mid-attempt) — in both cases nothing is ever partially
    /// persisted; see this type's own doc comment.
    @discardableResult
    static func advance(
        phase: TrainingPhase,
        asOf: Date,
        ownerUserID: UUID,
        performanceProfile: PerformanceProfile?,
        availability: UserAvailability,
        userProfile: UserProfile? = nil,
        materializationContext: TacticalMaterializationContext,
        context: ModelContext
    ) throws -> Outcome {
        guard let mix = phase.selectedTrainingMix ?? phase.recommendedTrainingMix else { return .notEligible }

        // Step 1-5 of the conceptual sequence: re-read authoritative
        // persisted state and verify every affected component's current
        // week is terminal, a next source-defined week exists for it,
        // and none of them is exhausted — never trust anything computed
        // earlier (e.g. by a ViewModel's own `load()`), since state may
        // have changed since then.
        guard TacticalWeekCompletion.canAdvanceTacticalWeek(for: mix) else { return .notEligible }

        // D-10R6-6: cheap, read-only preflight on the caller's own
        // context — nothing has been touched yet, so throwing here is
        // exactly as safe as `.notEligible`, just distinguishable by the
        // caller if it cares which specific prerequisite was missing.
        if let preflightError = TacticalAdvancementPreflight.check(mix: mix) {
            throw preflightError
        }

        // D-10R6-3: the isolated scratch context this entire attempt runs
        // against — see this type's own top-level doc comment for the
        // full reasoning.
        let scratchContext = ModelContext(context.container)
        scratchContext.autosaveEnabled = false

        let phaseID = phase.persistentModelID
        guard let scratchPhase = try scratchContext.fetch(
            FetchDescriptor<TrainingPhase>(predicate: #Predicate { $0.persistentModelID == phaseID })
        ).first else { return .notEligible }
        guard let scratchMix = scratchPhase.selectedTrainingMix ?? scratchPhase.recommendedTrainingMix else { return .notEligible }
        // Re-verify eligibility fresh inside the scratch context too —
        // belt and suspenders, matching this method's own "never trust
        // anything computed earlier" discipline one level deeper.
        guard TacticalWeekCompletion.canAdvanceTacticalWeek(for: scratchMix) else { return .notEligible }

        // Stage TE.1: `TrainingEnvironment` is a `@Model`, bound to the
        // CALLER's context — assigning it (via `Session
        // .materializedInEnvironment`) onto a Session inserted into
        // `scratchContext` and then saving would otherwise corrupt that
        // Session (an unfaulted cross-context reference), exactly the
        // failure mode `TransitionPhaseUseCase`'s own candidate-Exercise
        // re-fetch already guards against. Same bounded, mechanical fix,
        // scoped to only the field TE.1 itself introduces.
        let scratchMaterializationContext: TacticalMaterializationContext
        if let environment = materializationContext.trainingEnvironment {
            let environmentID = environment.persistentModelID
            let scratchEnvironment = try scratchContext.fetch(
                FetchDescriptor<TrainingEnvironment>(predicate: #Predicate { $0.persistentModelID == environmentID })
            ).first
            scratchMaterializationContext = TacticalMaterializationContext(
                equipmentProfile: materializationContext.equipmentProfile,
                strengthCandidateExercises: materializationContext.strengthCandidateExercises,
                functionalFitnessCandidateExercises: materializationContext.functionalFitnessCandidateExercises,
                trainingEnvironment: scratchEnvironment
            )
        } else {
            scratchMaterializationContext = materializationContext
        }

        // Step 6: invoke rollForward exactly once, entirely against the
        // scratch context. Any throw here leaves `scratchContext`
        // un-saved — it is simply discarded, and the caller's own
        // context was never touched.
        guard let result = try RollTacticalWindowUseCase.rollForward(
            mix: scratchMix, asOf: asOf, ownerUserID: ownerUserID, performanceProfile: performanceProfile,
            availability: availability, userProfile: userProfile,
            materializationContext: scratchMaterializationContext, context: scratchContext
        ) else {
            return .nothingRolled
        }
        guard !result.newSessionsByComponent.isEmpty else { return .nothingRolled }

        // Step 7: persist — one call, the entire mixed-modality batch
        // together, atomically.
        try scratchContext.save()

        // Refresh the caller's own context: re-fetch, by ID, every
        // ProgramInstance that actually rolled, directly on `context` —
        // see this type's own doc comment for why the root `phase` alone
        // is not enough.
        let affectedInstanceIDs = scratchMix.orderedComponents.compactMap { $0.programInstance?.persistentModelID }
        for instanceID in affectedInstanceIDs {
            _ = try? context.fetch(FetchDescriptor<ProgramInstance>(predicate: #Predicate { $0.persistentModelID == instanceID }))
        }

        // Step 8 (reload UI state) is the caller's responsibility —
        // mirrors `StartNextHypertrophyPhaseUseCase`'s own precedent of
        // returning a plain result and leaving `load(...)` re-invocation
        // to the ViewModel/View layer.
        return .advanced
    }
}
