import Foundation

/// Stage 8B: one proposed readiness adaptation — plain, non-persisted, the
/// same "propose-never-mutate" shape already used by `CandidateTrainingMix`/
/// `ScheduleProposal`. Nothing here is written to the model graph until
/// `ReadinessAdaptationDecisionUseCase.accept` is called.
struct ReadinessAdaptationProposalItem {
    var triggeringSignals: [ReadinessSignalSource]
    var actionKind: ReadinessActionKind
    var explanation: String

    // Exactly one of these identifies what this item concerns.
    var workoutBlock: WorkoutBlock?
    var exercisePrescription: ExercisePrescription?
    var functionalFitnessMovement: FunctionalFitnessMovement?

    // Typed original/proposed values — only the pair relevant to
    // `actionKind` is populated (Stage 8A decision D10).
    var originalSetCount: Int?
    var proposedSetCount: Int?
    var originalExercise: Exercise?
    var proposedExercise: Exercise?
}

/// The full result of one `EvaluateReadinessAdaptationUseCase.evaluate`
/// call. An empty proposal means Level 0 — no recommendation screen is
/// shown at all (`READINESS_ADAPTATION_PIPELINE.md` §1 step 5).
struct ReadinessAdaptationProposal {
    var items: [ReadinessAdaptationProposalItem] = []
    var isEmpty: Bool { items.isEmpty }
}
