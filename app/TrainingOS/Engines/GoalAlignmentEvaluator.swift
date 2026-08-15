import Foundation

/// Scores how well a `ScheduleProposal` actually satisfies its
/// `TrainingMix` — a deterministic, fully transparent factor list plus a
/// qualitative rating, never a fabricated numeric percentage. Every
/// factor here is a plain boolean check against the proposal's own
/// placements/warnings, so the same `(mix, proposal)` pair always
/// produces the same `GoalAlignment`.
enum GoalAlignmentEvaluator {
    static func evaluate(mix: TrainingMix, proposal: ScheduleProposal) -> GoalAlignment {
        let components = mix.orderedComponents
        let placedCounts = Dictionary(grouping: proposal.placements, by: \.componentLabel).mapValues(\.count)

        var factors: [GoalAlignmentFactor] = []

        let primaryComponents = components.filter { $0.priority == .primary }
        let primaryCovered = primaryComponents.isEmpty
            || primaryComponents.contains { (placedCounts[$0.label] ?? 0) > 0 }
        factors.append(GoalAlignmentFactor(
            kind: .primaryStimulusCoverage,
            satisfied: primaryCovered,
            note: primaryCovered
                ? "The mix's primary-priority component has at least one placed session."
                : "No primary-priority component session could be placed."
        ))

        let minimumsSatisfied = components.allSatisfy { component in
            let required = component.frequency.minimum ?? component.frequency.target
            return (placedCounts[component.label] ?? 0) >= required
        }
        factors.append(GoalAlignmentFactor(
            kind: .minimumFrequencySatisfaction,
            satisfied: minimumsSatisfied,
            note: minimumsSatisfied
                ? "Every component reached at least its minimum (or target, when no minimum was set) frequency."
                : "At least one component fell short of its minimum required frequency."
        ))

        let supportingComponents = components.filter { $0.priority != .primary }
        let supportingCovered = supportingComponents.isEmpty
            || supportingComponents.allSatisfy { (placedCounts[$0.label] ?? 0) > 0 }
        factors.append(GoalAlignmentFactor(
            kind: .supportingGoalCoverage,
            satisfied: supportingCovered,
            note: supportingCovered
                ? "Every secondary/supporting component received at least one session."
                : "At least one secondary/supporting component received no sessions at all."
        ))

        let feasible = proposal.feasibility != .infeasible
        factors.append(GoalAlignmentFactor(
            kind: .schedulingFeasibility,
            satisfied: feasible,
            note: feasible
                ? "The mix could be scheduled within the given availability."
                : "The mix could not be fully scheduled — see the proposal's conflicts."
        ))

        // Detected via the scheduler's own warning text — the current,
        // deliberately simple implementation of this factor. See
        // `CONCURRENT_SCHEDULER.md` for the known limitation this implies.
        let interferenceClean = !proposal.warnings.contains { $0.contains("interference rule") }
        factors.append(GoalAlignmentFactor(
            kind: .interferenceCost,
            satisfied: interferenceClean,
            note: interferenceClean
                ? "No interference-avoidance rule had to be violated."
                : "At least one interference-avoidance rule had to be violated to fit the window."
        ))

        let preferenceSatisfied = !proposal.warnings.contains { $0.contains("preferred day available") }
        factors.append(GoalAlignmentFactor(
            kind: .userPreferenceSatisfaction,
            satisfied: preferenceSatisfied,
            note: preferenceSatisfied
                ? "No component was fully denied all of its preferred days."
                : "At least one component could not use any of its preferred days."
        ))

        let rating: GoalAlignmentRating
        if !feasible {
            rating = .poor
        } else {
            switch factors.filter(\.satisfied).count {
            case factors.count: rating = .excellent
            case factors.count - 1: rating = .good
            default: rating = .acceptable
            }
        }

        return GoalAlignment(rating: rating, factors: factors)
    }
}
