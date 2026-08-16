import Foundation

/// The clean, planner-facing contract this pass exists to set up:
///
/// ```
/// TrainingPhaseGoal
///   + RecommendedTrainingMix OR UserSelectedTrainingMix   (TrainingMix.kind)
///   + Availability                                        (UserAvailability)
///   + Program-generated Sessions                          (ScheduledProgramInput)
///   -> ConcurrentScheduler.schedule(_:constraints:)
///   -> ScheduleProposal
///   -> GoalAlignmentEvaluator.evaluate(mix:proposal:)
///   -> GoalAlignment
///   -> user approval (AcceptScheduleProposalUseCase, a separate, explicit step)
/// ```
///
/// A future Long-Term Planner calls exactly this — `propose(mix:inputs:constraints:)`
/// — for each candidate `TrainingMix` it wants to compare, and reads only
/// the returned `ScheduleProposal`/`GoalAlignment`. It never needs to
/// know how `ConcurrentScheduler` resolves a conflict internally, and it
/// never inspects `ScheduleProposal.warnings` — every fact it could need
/// is already typed on `proposal.issues`/`alignment.factors`.
enum SchedulingPipeline {
    struct Result {
        var proposal: ScheduleProposal
        var alignment: GoalAlignment
    }

    static func propose(
        mix: TrainingMix,
        inputs: [ScheduledProgramInput],
        constraints: SchedulingConstraints
    ) -> Result {
        let proposal = ConcurrentScheduler.schedule(inputs, constraints: constraints)
        let alignment = GoalAlignmentEvaluator.evaluate(mix: mix, proposal: proposal)
        return Result(proposal: proposal, alignment: alignment)
    }
}
