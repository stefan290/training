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
    var repRangeLow: Int
    var repRangeHigh: Int
    var targetWeight: Double?
    var targetRir: Int?
    var isWarmup: Bool

    /// Nullify, not cascade: a SetResult must outlive the prescription that
    /// produced it (e.g. if a program is later edited or removed).
    @Relationship(deleteRule: .nullify, inverse: \SetResult.setPrescription)
    var results: [SetResult] = []

    init(
        id: UUID = UUID(),
        repRangeLow: Int,
        repRangeHigh: Int,
        targetWeight: Double? = nil,
        targetRir: Int? = nil,
        isWarmup: Bool = false
    ) {
        self.id = id
        self.sortIndex = 0
        self.repRangeLow = repRangeLow
        self.repRangeHigh = repRangeHigh
        self.targetWeight = targetWeight
        self.targetRir = targetRir
        self.isWarmup = isWarmup
    }

    /// The only way application code should attach a SetResult (the
    /// actual outcome) to the target it fulfilled. Mutates exactly one
    /// side; SwiftData maintains `result.setPrescription` from the
    /// declared inverse.
    func addResult(_ result: SetResult) {
        results.append(result)
    }
}
