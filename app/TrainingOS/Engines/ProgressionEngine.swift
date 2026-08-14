import Foundation

/// One prescribed set, independent of any persisted model — the input the
/// engine reasons over.
struct SetTarget: Equatable {
    let repRangeLow: Int
    let repRangeHigh: Int
    let targetRir: Int?
}

/// What actually happened for one set.
struct SetOutcome: Equatable {
    let reps: Int
    let actualRir: Int?
}

/// Everything a ProgressionEngine needs to produce one recommendation.
/// Matches the handoff's `recommend(input) -> Recommendation` contract
/// (section 7): prescription, performance record, recent results,
/// equipment increment and adherence mode all reduce to plain values here
/// so the engine has zero dependency on persistence.
struct ProgressionInput: Equatable {
    let targets: [SetTarget]
    let latestResults: [SetOutcome]
    /// False when there is no usable prior history for this exercise —
    /// forces CALIBRATION_REQUIRED rather than guessing a load.
    let hasUsableHistory: Bool
    let equipmentIncrement: Double
    let lastKnownWeight: Double?
}

/// The engine's output. Confidence and `inputsSummary` exist so a
/// Recommendation is always explainable — per handoff section 6, "a
/// recommendation without inputs to display is a bug."
struct ProgressionOutput: Equatable {
    let recommendedWeight: Double?
    let reasonCode: ProgressionReasonCode
    let confidence: Double
    let inputsSummary: String
}

/// Pure, deterministic and side-effect free per handoff section 7: same
/// inputs must always yield the same output. No AI in V1; rules live in
/// engine code/configuration, never in a View.
protocol ProgressionEngine {
    func recommend(_ input: ProgressionInput) -> ProgressionOutput
}
