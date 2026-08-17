import Foundation
import Observation

/// Accumulates this visit's completion-worthy highlights across however
/// many blocks a Session contains, so `CompleteSessionUseCase`'s
/// `highlights` parameter can be filled at Finish time.
/// `isFirstEverEntry`/PR flags are intentionally never persisted
/// (`STAGE6A_DECISION_MEMO.md` §1b — re-deriving them after the fact
/// isn't reliably possible), so the only way to carry them to the
/// completion screen is to accumulate them in memory as they happen, for
/// the lifetime of this Session's own navigation stack entry. Shared by
/// every modality's execution view for one Session.
@Observable
final class SessionExecutionState {
    private(set) var highlights: [LoggedResultHighlight] = []

    /// Only a PR or a first-ever entry is worth surfacing on the
    /// completion screen — an ordinary logged set isn't a "highlight."
    func record(_ highlight: LoggedResultHighlight?) {
        guard let highlight, highlight.isPersonalRecord || highlight.isFirstEverEntry else { return }
        highlights.append(highlight)
    }
}
