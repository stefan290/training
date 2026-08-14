import Foundation
import SwiftData

/// A persisted record of an engine output. The engine itself (see
/// Engines/ProgressionEngine.swift) is pure and returns a plain
/// `ProgressionOutput` value; the application layer decides whether and
/// when to persist one as a Recommendation, e.g. to show in the Why sheet
/// or to audit later. A Recommendation without a reason code is a bug —
/// there is deliberately no way to construct one without it.
@Model
final class Recommendation {
    @Attribute(.unique) var id: UUID
    var exercisePrescription: ExercisePrescription?

    var value: Double
    var reasonCode: ProgressionReasonCode
    /// Plain-language summary of the inputs that produced this value, so
    /// it can back a Why sheet without re-running the engine.
    var inputsSummary: String
    var confidence: Double
    var generatedAt: Date

    init(
        id: UUID = UUID(),
        value: Double,
        reasonCode: ProgressionReasonCode,
        inputsSummary: String,
        confidence: Double,
        generatedAt: Date = Date()
    ) {
        self.id = id
        self.value = value
        self.reasonCode = reasonCode
        self.inputsSummary = inputsSummary
        self.confidence = confidence
        self.generatedAt = generatedAt
    }
}
