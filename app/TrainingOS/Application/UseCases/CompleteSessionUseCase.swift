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

        return CompletionSummary(
            session: session,
            completionContext: session.completionContext ?? context,
            highlights: highlights,
            progressionPreview: progressionPreview(for: session, userProfile: userProfile)
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
    private static func progressionPreview(for session: Session, userProfile: UserProfile?) -> [ProgressionPreviewItem] {
        let engine = DoubleProgressionEngine()
        var items: [ProgressionPreviewItem] = []

        for block in session.orderedBlocks {
            for prescription in block.orderedPrescriptions {
                guard let exercise = prescription.exercise, !prescription.loggedSetResults.isEmpty else { continue }

                let targets = prescription.orderedSetPrescriptions.map {
                    SetTarget(repRangeLow: $0.repRangeLow, repRangeHigh: $0.repRangeHigh, targetRir: $0.targetRir)
                }
                guard !targets.isEmpty else { continue }

                let loggedResults = prescription.loggedSetResults.sorted { $0.setIndex < $1.setIndex }
                guard let lastWeight = loggedResults.last?.weight else { continue }
                let outcomes = loggedResults.map { SetOutcome(reps: $0.reps, actualRir: $0.actualRir) }

                // TRAININGOS_DESIGNED fallback (2.5 kg) when no per-user
                // equipment increment is on file for this exercise's
                // equipment — never blocks the preview on missing settings.
                let increment = userProfile?.equipmentIncrements[exercise.equipment] ?? 2.5

                let output = engine.recommend(ProgressionInput(
                    targets: targets, latestResults: outcomes, hasUsableHistory: true,
                    equipmentIncrement: increment, lastKnownWeight: lastWeight
                ))
                items.append(ProgressionPreviewItem(
                    exerciseName: exercise.canonicalName, reasonCode: output.reasonCode,
                    recommendedWeight: output.recommendedWeight, inputsSummary: output.inputsSummary
                ))
            }
        }

        return items
    }
}
