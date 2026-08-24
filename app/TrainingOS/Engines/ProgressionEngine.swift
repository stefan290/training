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
    /// Stage 10B.6 additions — the exposure immediately before the one
    /// this input's `targets`/`latestResults` describe, used only for the
    /// two-consecutive-miss REGRESS check
    /// (`STAGE10B6_HYPERTROPHY_PRESCRIPTION_REDESIGN.md` §6a step 5).
    /// `nil`-safe: absent, or a count mismatch between the two, simply
    /// makes REGRESS unreachable for this call — a miss is never
    /// downgraded to a regression without real evidence of a repeat.
    let previousTargets: [SetTarget]?
    let previousResults: [SetOutcome]?

    init(
        targets: [SetTarget], latestResults: [SetOutcome], hasUsableHistory: Bool,
        equipmentIncrement: Double, lastKnownWeight: Double?,
        previousTargets: [SetTarget]? = nil, previousResults: [SetOutcome]? = nil
    ) {
        self.targets = targets
        self.latestResults = latestResults
        self.hasUsableHistory = hasUsableHistory
        self.equipmentIncrement = equipmentIncrement
        self.lastKnownWeight = lastKnownWeight
        self.previousTargets = previousTargets
        self.previousResults = previousResults
    }
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
