import Foundation

/// Stage 6B: one logged result worth calling out on the completion
/// screen — built incrementally by the caller as it logs results
/// throughout the session (each `LogXResultUseCase` call already returns
/// `isFirstEverEntry`), never re-derived from stored data after the fact
/// (`WORKOUT_COMPLETION_PIPELINE.md` §4). Plain, non-persisted display
/// data — the underlying `PersonalRecord`/`isPersonalRecord` rows are the
/// real source of truth; this is a cache of what to show, not a second
/// copy of it.
struct LoggedResultHighlight: Equatable {
    var label: String
    var value: String
    var isPersonalRecord: Bool
    var isFirstEverEntry: Bool

    init(label: String, value: String, isPersonalRecord: Bool, isFirstEverEntry: Bool) {
        self.label = label
        self.value = value
        self.isPersonalRecord = isPersonalRecord
        self.isFirstEverEntry = isFirstEverEntry
    }
}

/// One exercise's read-only "what changes next time" preview —
/// `WORKOUT_COMPLETION_PIPELINE.md` §3, computed from the existing
/// `ProgressionEngine`, never written back to any `SetPrescription`.
struct ProgressionPreviewItem: Equatable {
    var exerciseName: String
    var reasonCode: ProgressionReasonCode
    var recommendedWeight: Double?
    var inputsSummary: String

    init(exerciseName: String, reasonCode: ProgressionReasonCode, recommendedWeight: Double?, inputsSummary: String) {
        self.exerciseName = exerciseName
        self.reasonCode = reasonCode
        self.recommendedWeight = recommendedWeight
        self.inputsSummary = inputsSummary
    }
}

/// `CompleteSessionUseCase.complete`'s return value — everything the
/// completion screen needs from one call, rather than re-querying five
/// different places (`WORKOUT_COMPLETION_PIPELINE.md` §1/§4). Plain,
/// non-persisted.
struct CompletionSummary {
    var session: Session
    var completionContext: SessionCompletionContext
    var highlights: [LoggedResultHighlight]
    var progressionPreview: [ProgressionPreviewItem]

    init(
        session: Session,
        completionContext: SessionCompletionContext,
        highlights: [LoggedResultHighlight],
        progressionPreview: [ProgressionPreviewItem]
    ) {
        self.session = session
        self.completionContext = completionContext
        self.highlights = highlights
        self.progressionPreview = progressionPreview
    }
}
