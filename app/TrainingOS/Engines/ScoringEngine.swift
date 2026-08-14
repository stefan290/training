import Foundation

/// Pure PR-comparison rules (handoff section 2.2 scoring directions).
/// Deliberately has no dependency on SwiftData or any persisted type so it
/// stays trivially testable. The application layer is responsible for
/// reading/writing `PersonalRecord` around calls to this engine.
enum ScoringEngine {
    /// Whether `a` beats `b` under the given direction. NONE and
    /// completion-based results are never comparable — they can't produce
    /// a PR.
    static func isBetter(_ a: Double, than b: Double, direction: ScoringDirection) -> Bool {
        switch direction {
        case .higherIsBetter: return a > b
        case .lowerIsBetter: return a < b
        case .none, .completionBased: return false
        }
    }

    /// The current best record among candidates sharing the same
    /// Rx/Scaled `context` and `repBand` — Rx and Scaled never compete for
    /// the same record, matching the handoff's "stored distinctly" rule.
    static func bestRecord(
        among records: [PersonalRecord],
        context: ResultContext,
        repBand: String?
    ) -> PersonalRecord? {
        let candidates = records.filter { $0.context == context && $0.repBand == repBand }
        guard var best = candidates.first else { return nil }
        for record in candidates.dropFirst()
        where isBetter(record.value, than: best.value, direction: record.scoringDirection) {
            best = record
        }
        return best
    }

    /// Whether logging `candidateValue` right now would set a new PR,
    /// given the current best record (if any) in the same context/band.
    static func isNewPersonalRecord(
        candidateValue: Double,
        direction: ScoringDirection,
        existingBest: PersonalRecord?
    ) -> Bool {
        guard direction == .higherIsBetter || direction == .lowerIsBetter else { return false }
        guard let existingBest else { return true }
        return isBetter(candidateValue, than: existingBest.value, direction: direction)
    }
}
