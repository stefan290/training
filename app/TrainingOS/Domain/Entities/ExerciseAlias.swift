import Foundation
import SwiftData

/// A known alternate name that resolves to a canonical Exercise, e.g.
/// "DB Incline Press" -> Incline Dumbbell Press. This pass only stores the
/// shape used by the future import pipeline (handoff section 10); no
/// resolution algorithm (alias table -> string match -> movement-pattern
/// heuristics) is implemented yet.
@Model
final class ExerciseAlias {
    @Attribute(.unique) var id: UUID
    var exercise: Exercise?
    var sourceName: String
    /// 0...1. High confidence would resolve silently once the import
    /// pipeline exists; below-threshold cases would go to Ambiguity Review.
    var confidence: Double

    init(id: UUID = UUID(), sourceName: String, confidence: Double = 1.0) {
        self.id = id
        self.sourceName = sourceName
        self.confidence = confidence
    }
}
