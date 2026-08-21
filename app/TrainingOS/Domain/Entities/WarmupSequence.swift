import Foundation
import SwiftData

/// Stage 9B: the generated pre-workout warm-up for one Session — mirrors
/// `ReadinessCheckIn`'s exact persistence shape (one-to-zero-or-one from
/// `Session`, cascade). Persisted immediately upon generation (CLAUDE.md
/// rule 20 — the recommendation itself is a meaningful fact worth
/// keeping), before the user acts on any item, so completed-history can
/// always answer both "what was recommended" and "what was actually
/// done" as two distinguishable facts (Stage 8B's own two-truths
/// discipline, reused here).
///
/// **This is a pure side-channel — Stage 9A decision D-W6.** Nothing
/// here is ever read by `CompleteSessionUseCase`/`SessionStatus`/
/// `SessionCompletionContext`/any progression engine.
@Model
final class WarmupSequence {
    @Attribute(.unique) var id: UUID
    var generatedAt: Date
    /// `true` only when the user explicitly skipped the whole sequence
    /// without marking any item done — distinct from a sequence where
    /// some/all items were individually completed.
    var wasSkippedEntirely: Bool

    /// Plain inverse — the owning `@Relationship` is declared on
    /// `Session.warmupSequence` (mirrors `ReadinessCheckIn.session`
    /// exactly).
    var session: Session?

    @Relationship(deleteRule: .cascade, inverse: \WarmupSequenceItem.sequence)
    var items: [WarmupSequenceItem] = []

    init(id: UUID = UUID(), generatedAt: Date, wasSkippedEntirely: Bool = false) {
        self.id = id
        self.generatedAt = generatedAt
        self.wasSkippedEntirely = wasSkippedEntirely
    }

    /// The only way application code should attach a WarmupSequenceItem.
    /// Mutates exactly one side (this array); SwiftData maintains
    /// `item.sequence` from the declared inverse.
    func addItem(_ item: WarmupSequenceItem) {
        item.sortIndex = items.count
        items.append(item)
    }

    var orderedItems: [WarmupSequenceItem] {
        items.sorted { $0.sortIndex < $1.sortIndex }
    }
}

/// Stage 9B: one prescribed item within a `WarmupSequence` — movement
/// reference plus the prescribed duration/reps, and whether the user
/// marked it done. `wasCompleted` is purely informational history; it
/// never feeds any completion/progression logic (D-W6).
@Model
final class WarmupSequenceItem {
    @Attribute(.unique) var id: UUID
    var sortIndex: Int
    var movement: WarmupMovement?
    var prescribedDurationSeconds: Int?
    var prescribedReps: Int?
    var wasCompleted: Bool

    /// Plain inverse — the owning `@Relationship` is declared on
    /// `WarmupSequence.items`.
    var sequence: WarmupSequence?

    init(
        id: UUID = UUID(),
        movement: WarmupMovement?,
        prescribedDurationSeconds: Int? = nil,
        prescribedReps: Int? = nil,
        wasCompleted: Bool = false
    ) {
        self.id = id
        self.sortIndex = 0
        self.movement = movement
        self.prescribedDurationSeconds = prescribedDurationSeconds
        self.prescribedReps = prescribedReps
        self.wasCompleted = wasCompleted
    }
}
