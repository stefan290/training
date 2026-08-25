import Foundation
import SwiftData

/// Stage 6B: the final Session-completion bookkeeping —
/// `WORKOUT_COMPLETION_PIPELINE.md` §1. Its own `save()` is the **final
/// consistency/commit point, not the first durability point**: every
/// `SetResult`/`SteadyStateResult`/`IntervalResult`/`FunctionalFitnessResult`
/// logged during the session is already durable (via `LogSetUseCase`/
/// `LogEnduranceResultUseCase`/`LogFunctionalFitnessResultUseCase`) by
/// the time this runs. This use case never re-records a result — it only
/// finalizes status/completion-context and computes a read-only
/// progression preview.
enum CompleteSessionUseCase {
    /// **Idempotent** (§52): calling this twice (e.g. a double-tapped
    /// Finish button) never re-marks blocks, never re-stamps
    /// `completedAt`, and never duplicates a `PersonalRecord` — nothing
    /// here creates one in the first place. A second call simply
    /// recomputes and returns the same summary from the now-unchanged
    /// state.
    @discardableResult
    static func complete(
        _ session: Session,
        context: SessionCompletionContext,
        asOf: Date,
        highlights: [LoggedResultHighlight] = [],
        userProfile: UserProfile? = nil,
        modelContext: ModelContext
    ) throws -> CompletionSummary {
        if session.status != .completed {
            for block in session.orderedBlocks where block.status == .pending || block.status == .active {
                block.status = .skipped
            }
            session.status = .completed
            session.completionContext = context
            session.completedAt = asOf
            try modelContext.save()
        }

        // Stage 10B.6: the same real, exercise-scoped history
        // `HypertrophyV2ProgressionEngine`'s real materialization reads —
        // fetched here (never fabricated) so the live preview and the
        // real next-week decision can never diverge ("one authoritative
        // decision path"). A single local `PerformanceProfile` matches
        // this app's offline-first, single-user architecture; `nil` if
        // none exists yet degrades to the pre-Stage-10B6 preview-only
        // behavior (no REGRESS lookback), never a crash.
        let performanceProfile = try? modelContext.fetch(FetchDescriptor<PerformanceProfile>()).first

        return CompletionSummary(
            session: session,
            completionContext: session.completionContext ?? context,
            highlights: highlights,
            progressionPreview: progressionPreview(for: session, userProfile: userProfile, performanceProfile: performanceProfile)
        )
    }

    /// Read-only — calls the existing `ProgressionEngine` exactly as
    /// `STRENGTH_EXECUTION_FLOW.md` §2 does for the suggested-load
    /// display, fed this session's own just-logged results. Never writes
    /// a `SetPrescription`; the next tactical window's real prescriptions
    /// are computed later, by the existing Stage 5 materializer path
    /// (`WORKOUT_COMPLETION_PIPELINE.md` §3). Only covers exercises that
    /// actually have a logged result this session — a block left
    /// `.skipped` entirely has nothing to preview, never a fabricated
    /// "no change" row.
    // Stage 6E: exposed (was `private`) so completed-history views can
    // recompute this same, purely-derived preview on demand — it reads
    // only session.orderedBlocks...loggedSetResults, mutates nothing, and
    // is idempotent, so calling it again later for a completed Session is
    // exactly as safe as the original call at completion time.
    static func progressionPreview(
        for session: Session, userProfile: UserProfile?, performanceProfile: PerformanceProfile? = nil
    ) -> [ProgressionPreviewItem] {
        let engine = DoubleProgressionEngine()
        var items: [ProgressionPreviewItem] = []

        for block in session.orderedBlocks {
            for prescription in block.orderedPrescriptions {
                guard let exercise = prescription.exercise, !prescription.loggedSetResults.isEmpty else { continue }

                // Stage 8B (D9 fix): today's EXECUTABLE targets, not the
                // full original prescription — excludes any set a Level 2
                // readiness adaptation marked `isAdaptedAway` so the
                // target count naturally lines up with what was actually
                // asked of the athlete today.
                let executable = prescription.executableSetPrescriptions
                // Stage 10R.1D: an RIR-only prescription (or an
                // unresolved deload rep target) has no fixed rep range to
                // feed `DoubleProgressionEngine`'s "was this an increase
                // over the target range" comparison — skipped from this
                // preview entirely, the same "never fabricate a row"
                // discipline this function already applies to blocks with
                // no logged result at all.
                let targets: [SetTarget] = executable.compactMap { set in
                    guard let low = set.repRangeLow, let high = set.repRangeHigh else { return nil }
                    return SetTarget(repRangeLow: low, repRangeHigh: high, targetRir: set.targetRir)
                }
                guard targets.count == executable.count, !targets.isEmpty else { continue }

                let loggedResults = prescription.loggedSetResults.sorted { $0.setIndex < $1.setIndex }
                guard let lastWeight = loggedResults.last?.weight else { continue }
                let outcomes = loggedResults.map { SetOutcome(reps: $0.reps, actualRir: $0.actualRir) }

                // TRAININGOS_DESIGNED fallback (2.5 kg) when no per-user
                // equipment increment is on file for this exercise's
                // equipment — never blocks the preview on missing settings.
                let increment = userProfile?.equipmentIncrements[exercise.equipment] ?? 2.5

                // Stage 10B.6: the exposure immediately before this one,
                // via the same authoritative history resolver real
                // materialization uses — so this preview's REGRESS
                // lookback (if any) matches exactly what week N+1's real
                // materialization would compute, never a display-only
                // approximation.
                let previousExposure = DoubleProgressionHistoryResolver.lookup(
                    for: exercise, performanceProfile: performanceProfile, excluding: prescription.id
                ).mostRecentNormal

                let output = engine.recommend(ProgressionInput(
                    targets: targets, latestResults: outcomes, hasUsableHistory: true,
                    equipmentIncrement: increment, lastKnownWeight: lastWeight,
                    previousTargets: previousExposure?.targets, previousResults: previousExposure?.outcomes
                ))

                // Stage 8B (D9 fix): an accepted readiness adaptation makes
                // today's completed result NEUTRAL evidence about the
                // unperformed original prescription — never a failed
                // attempt at it, and never proof the adapted number should
                // become the new anchor (READINESS_PROGRESSION_CONTRACT.md
                // §3). Only overrides the engine's own verdict when it
                // would otherwise read as a load increase; a genuine miss
                // against the adapted targets (`.hold`/etc.) still reports
                // normally — "existing methodology may react conservatively
                // as appropriate" is exactly the unmodified engine output.
                if output.reasonCode == .loadIncrease,
                   let adaptation = prescription.readinessAdaptationDecisions.first(where: { $0.userResponse == .accepted }) {
                    items.append(ProgressionPreviewItem(
                        exerciseName: exercise.canonicalName,
                        reasonCode: .readinessAdaptedHold,
                        recommendedWeight: adaptation.originalWeight ?? lastWeight,
                        inputsSummary: "Today's prescription was reduced by an accepted readiness adaptation (\(adaptation.actionKind.rawValue)). Completing the adapted session neither counts as failing nor as progressing the original prescription — holding at the pre-adaptation state."
                    ))
                    continue
                }

                items.append(ProgressionPreviewItem(
                    exerciseName: exercise.canonicalName, reasonCode: output.reasonCode,
                    recommendedWeight: output.recommendedWeight, inputsSummary: output.inputsSummary
                ))
            }
        }

        return items
    }
}
