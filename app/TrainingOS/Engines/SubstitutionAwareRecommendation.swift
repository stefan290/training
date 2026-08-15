import Foundation

/// Resolves a starting-point recommendation for whichever `Exercise` is
/// currently selected for a slot — strictly following Stage 4C §25's
/// escalation order and §29's "recompute for the new exercise, never
/// reuse the old exercise's absolute progression state" requirement.
/// Pure and deterministic, same discipline as every other engine in this
/// codebase: given the same inputs, always the same output.
///
/// **Deliberately not a full recommendation engine.** This answers one
/// narrow question — "is there a number to start from, and how
/// confident/sourced is it" — using `ExercisePerformanceProfile.estimatedOneRepMax`
/// as the one number this pass has to work with. Turning that into an
/// actual working-set weight is `StrengthProgressionEngine`'s/
/// `DoubleProgressionEngine`'s job, unchanged; this type only decides
/// *which* profile's estimate (if any) is trustworthy enough to feed them.
enum SubstitutionAwareRecommendation {
    struct Input {
        let selectedExercise: Exercise
        let selectedExerciseProfile: ExercisePerformanceProfile?
        /// Every other exercise eligible for the same slot — the
        /// candidate pool `ExerciseRelationshipResolver` searches for a
        /// fallback estimate source. Never includes exercises outside
        /// what the slot itself permits (§27's validity constraint still
        /// governs which exercises are even in play).
        let candidatesForEstimate: [Exercise]
        let curatedRelationships: [ExerciseRelationship]
        let relatedProfileLookup: (Exercise) -> ExercisePerformanceProfile?
    }

    struct Output: Equatable {
        let referenceOneRepMax: Double?
        let reasonCode: ProgressionReasonCode
        let confidence: Double
        let inputsSummary: String
    }

    /// A flat, explicitly TrainingOS-designed discount applied to a
    /// related-exercise estimate — not a biomechanical transfer
    /// coefficient (CLAUDE.md rule 10: no invented ambiguous training
    /// rule). Deliberately conservative and deliberately simple: halving
    /// confidence rather than modeling how much a movement pattern/target/
    /// equipment relationship should actually be trusted, which no
    /// surviving source material specifies.
    static let relatedExerciseConfidenceDiscount = 0.5

    static func resolve(_ input: Input) -> Output {
        if let profile = input.selectedExerciseProfile,
           let oneRepMax = profile.estimatedOneRepMax,
           profile.confidence > 0 {
            return Output(
                referenceOneRepMax: oneRepMax,
                reasonCode: .percentageOfEstimate,
                confidence: profile.confidence,
                inputsSummary: "Using \(input.selectedExercise.canonicalName)'s own performance history (estimated 1RM \(oneRepMax))."
            )
        }

        if let match = ExerciseRelationshipResolver.bestEstimateSource(
            from: input.selectedExercise,
            candidates: input.candidatesForEstimate,
            curated: input.curatedRelationships
        ),
           let relatedProfile = input.relatedProfileLookup(match.relatedExercise),
           let relatedOneRepMax = relatedProfile.estimatedOneRepMax,
           relatedProfile.confidence > 0 {
            let discountedConfidence = relatedProfile.confidence * relatedExerciseConfidenceDiscount
            return Output(
                referenceOneRepMax: relatedOneRepMax,
                reasonCode: .substitutionEstimate,
                confidence: discountedConfidence,
                inputsSummary: "No history yet for \(input.selectedExercise.canonicalName); estimating from \(match.relatedExercise.canonicalName) (\(match.type.rawValue)) at reduced confidence."
            )
        }

        return Output(
            referenceOneRepMax: nil,
            reasonCode: .calibrationRequired,
            confidence: 0,
            inputsSummary: "No usable history for \(input.selectedExercise.canonicalName) or any related exercise. Requesting a calibration set instead of inventing a load."
        )
    }
}
