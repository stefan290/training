import Foundation
import SwiftData

/// The target for one set: what the engine prescribes, before anything is
/// performed. Kept strictly separate from SetResult (the actual). RIR is
/// owned here as a target; the user owns the actual RIR on SetResult.
@Model
final class SetPrescription {
    @Attribute(.unique) var id: UUID
    var exercisePrescription: ExercisePrescription?
    /// Stable position among a movement's sets, assigned by
    /// `ExercisePrescription.addSetPrescription(_:)`. This is what "set 1,
    /// set 2, set 3" means — never the raw collection order.
    var sortIndex: Int
    /// Stage 10R.1D: `nil` for an RIR-only prescription (`targetRir`
    /// carries the effort target instead) or for a deload set whose rep
    /// target could not be resolved from primary source evidence — see
    /// `StrengthReasonCode.deloadRepsRequireLoggedPerformanceData`. Never
    /// fabricated to avoid a `nil` — the pre-Stage-10R.1D defect this
    /// corrects.
    var repRangeLow: Int?
    var repRangeHigh: Int?
    var targetWeight: Double?
    var targetRir: Int?
    var isWarmup: Bool
    /// Stage 8B addition: `true` when a Level 2 readiness adaptation
    /// removed this set from TODAY's executable prescription
    /// (`ReadinessAdaptationDecision`, `actionKind == .setCountReduced`).
    /// **Never delete the row instead** — the historical model must still
    /// answer "originally 4 sets were prescribed" even after an adaptation
    /// reduces today's executable count to 3
    /// (`READINESS_PROGRESSION_CONTRACT.md` §4). `false` is the default and
    /// the only value for every set prescribed outside a readiness
    /// adaptation — this is a distinct state from "skipped/missed," never
    /// overloaded onto an existing skip concept, so future progression
    /// logic never mistakes an intentional adaptation for a failed or
    /// forgotten set.
    var isAdaptedAway: Bool

    /// Nullify, not cascade: a SetResult must outlive the prescription that
    /// produced it (e.g. if a program is later edited or removed).
    @Relationship(deleteRule: .nullify, inverse: \SetResult.setPrescription)
    var results: [SetResult] = []

    init(
        id: UUID = UUID(),
        repRangeLow: Int? = nil,
        repRangeHigh: Int? = nil,
        targetWeight: Double? = nil,
        targetRir: Int? = nil,
        isWarmup: Bool = false,
        isAdaptedAway: Bool = false
    ) {
        self.id = id
        self.sortIndex = 0
        self.repRangeLow = repRangeLow
        self.repRangeHigh = repRangeHigh
        self.targetWeight = targetWeight
        self.targetRir = targetRir
        self.isWarmup = isWarmup
        self.isAdaptedAway = isAdaptedAway
    }

    /// The only way application code should attach a SetResult (the
    /// actual outcome) to the target it fulfilled. Mutates exactly one
    /// side; SwiftData maintains `result.setPrescription` from the
    /// declared inverse.
    func addResult(_ result: SetResult) {
        results.append(result)
    }
}
