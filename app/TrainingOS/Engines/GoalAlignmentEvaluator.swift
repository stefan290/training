import Foundation

/// Scores how well a `ScheduleProposal` actually satisfies its
/// `TrainingMix` — a deterministic, fully transparent factor list plus a
/// qualitative rating, never a fabricated numeric percentage.
///
/// **Hardening-pass invariant:** every factor here is computed from
/// `ScheduleProposal.issues` (typed `ScheduleIssueCode`s) and
/// `.placements` (typed session/component data) only. This type must
/// never read `ScheduleProposal.warnings` — that property is pure
/// display copy computed FROM `issues`, and parsing it back here would
/// silently reintroduce exactly the string-matching coupling this pass
/// removes. `ConcurrentSchedulerTests.testGoalAlignmentNeverReadsWarningsText`/
/// `.testChangingIssueDisplayCopyNeverChangesGoalAlignment` prove this
/// holds.
enum GoalAlignmentEvaluator {
    static func evaluate(mix: TrainingMix, proposal: ScheduleProposal) -> GoalAlignment {
        let components = mix.orderedComponents
        let placedCounts = Dictionary(grouping: proposal.placements, by: \.componentLabel).mapValues(\.count)

        // `.infeasible` is its own tier — an unschedulable mix is a
        // different kind of outcome than one that scored badly, and the
        // per-factor detail below wouldn't be meaningful anyway (most
        // factors would trivially fail together).
        guard proposal.feasibility != .infeasible else {
            return GoalAlignment(rating: .infeasible, factors: [])
        }

        var factors: [GoalAlignmentFactor] = []

        let primaryCovered = !proposal.issues.contains { $0.code == .primaryGoalCompromise }
        factors.append(GoalAlignmentFactor(
            kind: .primaryStimulusCoverage,
            satisfied: primaryCovered,
            note: primaryCovered
                ? "The mix's primary-priority component has no primary-goal compromise."
                : "The mix's primary-priority component could not be fully scheduled."
        ))

        let requiredSatisfied = !proposal.issues.contains { $0.code == .requiredFrequencyUnsatisfied }
        factors.append(GoalAlignmentFactor(
            kind: .requiredComponentSatisfaction,
            satisfied: requiredSatisfied,
            note: requiredSatisfied
                ? "Every required-flexibility component reached its required minimum."
                : "At least one required-flexibility component fell short of its required minimum."
        ))

        let targetSatisfied = components.allSatisfy { component in
            let required = component.frequency.minimum ?? component.frequency.target
            return (placedCounts[component.label] ?? 0) >= required
        }
        factors.append(GoalAlignmentFactor(
            kind: .targetFrequencySatisfaction,
            satisfied: targetSatisfied,
            note: targetSatisfied
                ? "Every component reached at least its minimum (or target, when no minimum was set) frequency."
                : "At least one component fell short of its minimum-or-target frequency."
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

        let preferenceSatisfied = !proposal.issues.contains { $0.code == .preferenceCompromise }
        factors.append(GoalAlignmentFactor(
            kind: .userSelectedPreferenceSatisfaction,
            satisfied: preferenceSatisfied,
            note: preferenceSatisfied
                ? "No component was fully denied all of its preferred days."
                : "At least one component could not use any of its preferred days."
        ))

        factors.append(GoalAlignmentFactor(
            kind: .schedulingFeasibility,
            satisfied: true,
            note: "The mix could be scheduled within the given availability."
        ))

        let interferenceClean = !proposal.issues.contains { $0.code == .interferenceConflict || $0.code == .recoverySpacingCompromise }
        factors.append(GoalAlignmentFactor(
            kind: .interferenceAndRecoveryCompromise,
            satisfied: interferenceClean,
            note: interferenceClean
                ? "No interference-avoidance or recovery-spacing rule had to be compromised."
                : "At least one interference or recovery-spacing rule had to be compromised to fit the window."
        ))

        let satisfiedCount = factors.filter(\.satisfied).count
        let rating: GoalAlignmentRating
        switch satisfiedCount {
        case factors.count: rating = .excellent
        case factors.count - 1: rating = .good
        case (factors.count - 3)...(factors.count - 2): rating = .acceptable
        default: rating = .poor
        }

        return GoalAlignment(rating: rating, factors: factors)
    }
}
