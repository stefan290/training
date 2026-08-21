import Foundation
import SwiftData

/// Stage 8B: persists the readiness check-in immediately on submit —
/// before the recommendation screen or the Start transition even
/// fires (CLAUDE.md rule 20). Mirrors `RecordAutoregulationFeedbackUseCase`'s
/// own "persist immediately, single save()" discipline exactly.
enum RecordReadinessCheckInUseCase {
    @discardableResult
    static func record(_ checkIn: ReadinessCheckIn, for session: Session, modelContext: ModelContext) throws -> ReadinessCheckIn {
        modelContext.insert(checkIn)
        session.attachReadinessCheckIn(checkIn)
        try modelContext.save()
        return checkIn
    }
}
