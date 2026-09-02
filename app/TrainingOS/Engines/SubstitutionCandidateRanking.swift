import Foundation

/// Deterministic ranking for the live Change Exercise flow's candidate
/// list (`STRENGTH_EXECUTION_FLOW.md` §7, Part E's "exact / related /
/// calibration-required history tiers") — reuses `SubstitutionValidator`
/// for eligibility and `SubstitutionAwareRecommendation` for tiering
/// exactly as Stage 4C already built them, rather than a second scoring
/// mechanism. No AI, no probabilistic scoring — ties broken by
/// `canonicalName` so the same inputs always produce the same order.
enum SubstitutionCandidateRanking {
    struct Candidate: Equatable, Identifiable {
        var id: UUID { exercise.id }
        let exercise: Exercise
        let tier: ProgressionReasonCode
        let inputsSummary: String
    }

    /// `allExercises` is the pool to filter/rank from; `profileLookup`
    /// answers "does the user have permanent history with this exercise,"
    /// reused both for this candidate's own tier and as
    /// `SubstitutionAwareRecommendation`'s related-exercise fallback
    /// search among the other eligible candidates.
    static func rank(
        slot: ExerciseSlot,
        excluding currentExercise: Exercise,
        allExercises: [Exercise],
        curatedRelationships: [ExerciseRelationship],
        profileLookup: @escaping (Exercise) -> ExercisePerformanceProfile?,
        environment: TrainingEnvironment?
    ) -> [Candidate] {
        let eligible = allExercises.filter {
            $0.id != currentExercise.id && SubstitutionValidator.isValid(candidate: $0, for: slot, environment: environment)
        }

        let tierRank: (ProgressionReasonCode) -> Int = { code in
            switch code {
            case .percentageOfEstimate: 0
            case .substitutionEstimate: 1
            default: 2
            }
        }

        return eligible.map { candidate -> Candidate in
            let output = SubstitutionAwareRecommendation.resolve(SubstitutionAwareRecommendation.Input(
                selectedExercise: candidate,
                selectedExerciseProfile: profileLookup(candidate),
                candidatesForEstimate: eligible.filter { $0.id != candidate.id },
                curatedRelationships: curatedRelationships,
                relatedProfileLookup: profileLookup
            ))
            return Candidate(exercise: candidate, tier: output.reasonCode, inputsSummary: output.inputsSummary)
        }.sorted { lhs, rhs in
            let lr = tierRank(lhs.tier)
            let rr = tierRank(rhs.tier)
            if lr != rr { return lr < rr }
            return lhs.exercise.canonicalName < rhs.exercise.canonicalName
        }
    }
}
