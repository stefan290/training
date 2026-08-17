import Foundation

/// Deterministic, definitional mapping from a `WorkoutFormat` shape to its
/// `ScoreDirection` — an AMRAP's rounds+reps is, by definition, higher-is-
/// better; a For Time's elapsed seconds is, by definition, lower-is-
/// better. This is not a training-methodology guess (CLAUDE.md rule 10);
/// it mirrors the same closed, source-derived vocabulary
/// `ScoreTypes.swift` already documents.
///
/// `ScoreType` itself is never re-derived here — `Stimulus.scoreType`
/// (set at prescription-authoring time, whether generated or curated) is
/// the one authoritative source, exactly matching `ScoreDirection`'s own
/// doc comment ("never inferred from a ScoreType or a workout's name").
/// `ScoreDirection` has no equivalent authored field on a non-benchmark
/// `FunctionalFitnessPrescription` (only `BenchmarkDefinition` carries
/// one), so live execution needs this one deterministic fallback to
/// construct a `FunctionalFitnessResult` for a generated workout.
enum FunctionalFitnessScoring {
    static func scoreDirection(for format: WorkoutFormat) -> ScoreDirection {
        switch format {
        case .amrap: .higherIsBetter
        case .emom: .higherIsBetter
        case .forTime, .chipper, .ladder: .lowerIsBetter
        case .roundsForTime: .lowerIsBetter
        case .maxLoad: .higherIsBetter
        case .maxReps: .higherIsBetter
        case .intervals: .higherIsBetter
        }
    }
}
