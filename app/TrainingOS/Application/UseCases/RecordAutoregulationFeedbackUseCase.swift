import Foundation
import SwiftData

/// Stage 6D: the orchestrating, save-owning use case behind the one
/// lightweight hypertrophy-feedback prompt (Part 6) — persists the
/// -1/0/+1 rating `StrengthProgressionEngine.resolveSetCount`'s
/// `.autoregulated` case has always accepted, immediately, the moment
/// the user answers.
enum RecordAutoregulationFeedbackUseCase {
    static func recordRating(_ rating: Int, for prescription: ExercisePrescription, modelContext: ModelContext) throws {
        prescription.autoregulationRating = rating
        try modelContext.save()
    }
}
