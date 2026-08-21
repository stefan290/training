import Foundation
import SwiftData

/// Stage 9B: persists a generated `WarmupSequence` immediately — mirrors
/// `RecordReadinessCheckInUseCase`'s own "persist immediately, single
/// save()" discipline (CLAUDE.md rule 20). Also the single place a user
/// action (marking an item done, or skipping the whole sequence) is
/// saved.
enum RecordWarmupSequenceUseCase {
    @discardableResult
    static func record(_ sequence: WarmupSequence, for session: Session, modelContext: ModelContext) throws -> WarmupSequence {
        modelContext.insert(sequence)
        for item in sequence.items {
            modelContext.insert(item)
        }
        session.attachWarmupSequence(sequence)
        try modelContext.save()
        return sequence
    }

    static func markItemCompleted(_ item: WarmupSequenceItem, modelContext: ModelContext) throws {
        item.wasCompleted = true
        try modelContext.save()
    }

    static func skipEntirely(_ sequence: WarmupSequence, modelContext: ModelContext) throws {
        sequence.wasSkippedEntirely = true
        try modelContext.save()
    }
}
