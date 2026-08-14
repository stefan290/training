import Foundation

enum ScoreType: String, Codable, CaseIterable {
    case time
    case roundsAndReps
    case repetitions
    case calories
    case distance
    case load
    case completedIntervals
}

/// Never inferred from a `ScoreType` or a workout's name — always set
/// explicitly at stimulus-definition time. See
/// `FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md` §4 for why even an
/// implicit-default lookup table (e.g. "`.time` always means
/// `lowerIsBetter`") is deliberately not provided.
enum ScoreDirection: String, Codable, CaseIterable {
    case lowerIsBetter
    case higherIsBetter
}

/// A typed union rather than a single scalar, because some score shapes
/// (`.roundsAndReps`) are genuinely two numbers, not one — see
/// `PRESCRIPTION_RESULT_MODEL_REVIEW.md` §4.
enum ScoreValue: Codable, Equatable {
    case time(seconds: Int)
    case roundsAndReps(rounds: Int, partialReps: Int)
    case repetitions(Int)
    case calories(Int)
    case distance(meters: Double)
    case load(kilograms: Double)
    case completedIntervals(Int)
}
