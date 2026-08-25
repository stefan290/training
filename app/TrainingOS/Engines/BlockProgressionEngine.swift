import Foundation

/// What a `BlockProgressionEngine` recommends changing, as a plain value —
/// never a materialized `@Model` prescription. Constructing the next
/// persisted `BlockPrescription` from a recommendation is Application-layer
/// responsibility, exactly as it already is for strength today
/// (`ARCHITECTURE.md`'s "How the engines interact" diagram: the engine
/// returns a plain `ProgressionOutput`; the application layer decides
/// whether/how to persist anything from it). Cases are additive, mirroring
/// `IntensityTarget`'s own growth pattern — adding one for a new modality's
/// dimension never requires touching an existing case.
enum ProgressionRecommendation: Equatable {
    case weight(Double)
    case none
}

/// The generalized progression contract validated in Stage 3B
/// (`MODALITY_ARCHITECTURE_VALIDATION.md` §5) and implemented here. Mirrors
/// `ProgressionInput`/`ProgressionOutput`'s existing shape — current
/// prescription + relevant history + a usability flag, in; a
/// recommendation + reason code, out — generalized to carry
/// `BlockPrescription`/`BlockResult` instead of strength-only
/// `SetTarget`/`SetOutcome`.
struct BlockProgressionInput {
    let currentPrescription: BlockPrescription
    let relevantHistory: [BlockResult]
    /// False when there is no usable prior history — forces
    /// `.calibrationRequired` rather than guessing, exactly as
    /// `ProgressionInput.hasUsableHistory` already does for strength.
    let hasUsableHistory: Bool
}

struct BlockProgressionOutput {
    let recommendation: ProgressionRecommendation
    let reasonCode: ProgressionReasonCode
    let confidence: Double
    let inputsSummary: String
}

/// Pure, deterministic, side-effect-free — same discipline as
/// `ProgressionEngine`. **Do not** try to force every `ProgrammingSystem`
/// through one conforming type: specific engines decide what dimensions
/// change (Stage 3C §23/§25). This protocol only fixes the *shape* of the
/// conversation, not the algorithm.
protocol BlockProgressionEngine {
    func recommend(_ input: BlockProgressionInput) -> BlockProgressionOutput
}

/// A thin adapter proving the generalized contract is satisfiable by the
/// existing, already-tested strength logic **without rewriting it**.
/// `DoubleProgressionEngine` itself is untouched — this type only unwraps
/// `BlockPrescription.exercise`/`BlockResult.strength`, delegates, and
/// re-wraps the result. `equipmentIncrement`/`lastKnownWeight` are
/// strength-specific configuration, supplied at construction time rather
/// than added to the shared `BlockProgressionInput` — exactly the "specific
/// engines decide what dimensions change" principle, applied to the
/// engine's own configuration surface, not just its output.
///
/// Scoped, like `DoubleProgressionEngine` itself, to a single-movement
/// block: if `currentPrescription` carries more than one
/// `ExercisePrescription`, only the first is evaluated.
struct StrengthBlockProgressionEngine: BlockProgressionEngine {
    let underlying: ProgressionEngine
    let equipmentIncrement: Double
    let lastKnownWeight: Double?

    init(
        underlying: ProgressionEngine = DoubleProgressionEngine(),
        equipmentIncrement: Double,
        lastKnownWeight: Double?
    ) {
        self.underlying = underlying
        self.equipmentIncrement = equipmentIncrement
        self.lastKnownWeight = lastKnownWeight
    }

    func recommend(_ input: BlockProgressionInput) -> BlockProgressionOutput {
        guard
            case .exercise(let prescriptions) = input.currentPrescription,
            let exercisePrescription = prescriptions.first
        else {
            return BlockProgressionOutput(
                recommendation: .none,
                reasonCode: .hold,
                confidence: 0,
                inputsSummary: "StrengthBlockProgressionEngine received a non-exercise prescription; holding rather than guessing."
            )
        }

        // Stage 10R.1D: an RIR-only prescription (or an unresolved deload
        // rep target) has no fixed rep range for `SetTarget` to represent
        // — `DoubleProgressionEngine`'s "did this clear the target range"
        // comparison does not apply. Held, not guessed, exactly like the
        // "no usable history" case below.
        guard exercisePrescription.orderedSetPrescriptions.allSatisfy({ $0.repRangeLow != nil && $0.repRangeHigh != nil }) else {
            return BlockProgressionOutput(
                recommendation: .none,
                reasonCode: .calibrationRequired,
                confidence: 0,
                inputsSummary: "This prescription has no fixed rep range (an RIR/effort target, or an unresolved deload rep target) — holding rather than guessing a range-based progression."
            )
        }
        let targets = exercisePrescription.orderedSetPrescriptions.map {
            SetTarget(repRangeLow: $0.repRangeLow!, repRangeHigh: $0.repRangeHigh!, targetRir: $0.targetRir)
        }

        let latestStrengthResult: StrengthBlockResult? = input.relevantHistory.compactMap {
            if case .strength(let result) = $0 { return result }
            return nil
        }.last

        let latestResults = (latestStrengthResult?.setResults ?? [])
            .sorted { $0.setIndex < $1.setIndex }
            .map { SetOutcome(reps: $0.reps, actualRir: $0.actualRir) }

        let engineOutput = underlying.recommend(
            ProgressionInput(
                targets: targets,
                latestResults: latestResults,
                hasUsableHistory: input.hasUsableHistory,
                equipmentIncrement: equipmentIncrement,
                lastKnownWeight: lastKnownWeight
            )
        )

        let recommendation: ProgressionRecommendation
        if let recommendedWeight = engineOutput.recommendedWeight {
            recommendation = .weight(recommendedWeight)
        } else {
            recommendation = ProgressionRecommendation.none
        }

        return BlockProgressionOutput(
            recommendation: recommendation,
            reasonCode: engineOutput.reasonCode,
            confidence: engineOutput.confidence,
            inputsSummary: engineOutput.inputsSummary
        )
    }
}
