import Foundation

/// Stage 10R.1D UX correction: the pure text-formatting decisions behind
/// `StrengthExecutionView`'s set-target/input display — extracted from
/// the View so the actual presentation rule (never fabricate a rep count
/// for an RIR-only prescription; never let a prescription target be
/// mistaken for a logged actual) is independently testable, mirroring
/// `SessionDisplayMode`'s own precedent (`CompletedHistoryPresentation.swift`).
enum StrengthSetPresentation {
    /// The "Set N of M · ..." trailing target text — a fixed rep count
    /// (`"5 reps"`/`"5-10 reps"`), an RIR target (`"RIR 3"`), both
    /// (Hypertrophy V2's rep-range + explicit-RIR hybrid), or neither (an
    /// unresolved deload set, `StrengthReasonCode.deloadRepsRequireLoggedPerformanceData`).
    /// Never both a rep count and an implied RIR fabricated from each
    /// other — each half is only ever present when the underlying
    /// `SetPrescription` field actually carries it.
    static func targetText(repRangeLow: Int?, repRangeHigh: Int?, targetRir: Int?) -> String {
        let repsText = repsText(repRangeLow: repRangeLow, repRangeHigh: repRangeHigh)
        let rirText = targetRir.map { "RIR \($0)" }
        return [repsText, rirText].compactMap { $0 }.joined(separator: " · ")
    }

    /// The fixed-rep-count portion alone (`"5 reps"`/`"5-10 reps"`), or
    /// `nil` when there is none — honest range display when the bounds
    /// genuinely differ (Stage 10B.6), one plain number when they match.
    static func repsText(repRangeLow: Int?, repRangeHigh: Int?) -> String? {
        guard let low = repRangeLow else { return nil }
        guard let high = repRangeHigh, high != low else { return "\(low) reps" }
        return "\(low)-\(high) reps"
    }

    /// Plain-language explanation of an RIR target — describes the
    /// existing source prescription, never invents a new one (no
    /// fabricated rep range such as 8-12/5-10/10-20). `rir <= 0` reads as
    /// "to failure," never "0 reps in reserve" phrased as if 0 were an
    /// arbitrary count. Callers must only show this alongside a `nil`
    /// `repRangeLow` (a genuinely RIR-only prescription) — never
    /// alongside a real fixed rep count, including Hypertrophy V2's
    /// rep-range + explicit-RIR hybrid, which already shows its own
    /// range and needs no additional explanation.
    static func rirGuidance(for rir: Int) -> String {
        guard rir > 0 else {
            return "Perform reps to failure — no reps in reserve."
        }
        let repWord = rir == 1 ? "rep" : "reps"
        return "Perform reps until you have about \(rir) \(repWord) in reserve."
    }

    /// The actual-reps input's label — an explicit "—" placeholder
    /// (never a visually-meaningful `0`) until the athlete has actually
    /// entered a value, so an RIR-only prescription (no fixed rep count
    /// to prefill) never looks like it was prescribed zero reps.
    static func actualRepsLabel(_ reps: Int?) -> String {
        reps.map { "Actual reps: \($0)" } ?? "Actual reps: —"
    }

    /// The actual-RIR selector's label — distinct wording from the
    /// prescription's own "RIR N" target text (shown separately, in the
    /// header) so the two are never mistaken for one another.
    static let actualRirSelectorLabel = "Actual RIR"
}
