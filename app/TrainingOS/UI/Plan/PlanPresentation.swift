import Foundation

/// Pure display-string mapping for Plan's Goal/Phase/ProgramDefinition
/// concepts — user-facing names instead of raw enum-like strings (Part 4).
enum PlanPresentation {
    static func goalTypeLabel(_ type: GoalType) -> String {
        switch type {
        case .muscleGain: "Muscle Gain"
        case .fatLoss: "Fat Loss"
        case .generalStrength: "General Strength"
        case .enduranceEvent: "Endurance Event"
        case .functionalFitness: "Functional Fitness"
        case .maintenance: "Maintenance"
        }
    }

    /// V1 "Goal ≠ Training Method" checkpoint: the curated, athlete-facing
    /// Main Goal (OUTCOME) options — deliberately excludes
    /// `.functionalFitness` (a Training Style, `trainingStyleLabel` below)
    /// from ever being iterated/selected as a Main Goal. Existing
    /// persisted `Goal.primaryType == .functionalFitness` data (if any)
    /// is never migrated or blocked by this — this is only which options
    /// the picker itself offers going forward.
    static let mainGoalOptions: [GoalType] = [.muscleGain, .generalStrength, .fatLoss, .enduranceEvent, .maintenance]

    /// Athlete-facing OUTCOME phrasing for the Main Goal screen —
    /// deliberately distinct from `goalTypeLabel` above (which stays the
    /// more literal/internal-adjacent label used elsewhere, e.g. Plan
    /// review surfaces predating this checkpoint). `.functionalFitness` is
    /// never offered via `mainGoalOptions`, but the switch stays exhaustive
    /// for the rare case a pre-existing Goal still carries it.
    static func mainGoalLabel(_ type: GoalType) -> String {
        switch type {
        case .muscleGain: "Build Muscle"
        case .generalStrength: "Get Stronger"
        case .fatLoss: "Lose Fat"
        case .enduranceEvent: "Improve Fitness & Endurance"
        case .maintenance: "Maintain My Fitness"
        case .functionalFitness: "Functional Fitness"
        }
    }

    /// V1 "Goal ≠ Training Method" checkpoint: athlete-facing Training
    /// Style labels — never "Powerlifting"/"Steady State"/"Intervals"/any
    /// raw `ProgrammingSystemKind` name.
    static func trainingStyleLabel(_ style: TrainingStyle) -> String {
        switch style {
        case .hypertrophy: "Hypertrophy"
        case .strengthTraining: "Strength Training"
        case .functionalFitness: "Functional Fitness"
        case .running: "Running"
        case .cycling: "Cycling"
        }
    }

    static func phaseTypeLabel(_ type: PhaseType) -> String {
        switch type {
        case .muscleGain: "Muscle Gain"
        case .fatLoss: "Fat Loss"
        case .strength: "Strength"
        case .enduranceEvent: "Endurance Event"
        case .functionalFitness: "Functional Fitness"
        case .recovery: "Recovery"
        case .transition: "Transition"
        case .maintenance: "Maintenance"
        }
    }

    static func phaseStatusLabel(_ status: PhaseStatus) -> String {
        switch status {
        case .planned: "Planned"
        case .active: "Active"
        case .completed: "Completed"
        case .paused: "Paused"
        case .abandoned: "Abandoned"
        }
    }

    /// Stage 7 (Slice 4) addition: `.planned` is deliberately relabelled
    /// "Upcoming" specifically for Annual Plan's own status chip — every
    /// other Plan/Program surface keeps `phaseStatusLabel` above
    /// unchanged (a `.planned` `TrainingPhase` elsewhere in the app is
    /// not necessarily "upcoming" in the annual-plan-timeline sense).
    static func annualPlanStatusLabel(_ status: PhaseStatus) -> String {
        switch status {
        case .planned: "Upcoming"
        default: phaseStatusLabel(status)
        }
    }

    static func programmingSystemLabel(_ system: ProgrammingSystemKind?) -> String {
        switch system {
        case .hypertrophy: "Hypertrophy"
        case .powerlifting: "Powerlifting"
        case .steadyState: "Steady State"
        case .interval: "Intervals"
        case .functionalFitness: "Functional Fitness"
        case nil: "Unresolved"
        }
    }

    static func priorityLabel(_ priority: GoalPriority) -> String {
        switch priority {
        case .primary: "Primary"
        case .secondary: "Secondary"
        case .supporting: "Supporting"
        }
    }

    /// e.g. "4× Hypertrophy" — the compact per-component summary used
    /// throughout Annual Plan/Current Phase, never a raw
    /// `programmingSystem` case name.
    static func componentSummary(_ component: TrainingMixComponent) -> String {
        "\(component.frequency.target)× \(component.label)"
    }

    /// e.g. "3× Strength + 2× Functional Fitness + 1× Run" — a whole
    /// mix's components in their stable `sortIndex` order.
    static func mixSummary(_ mix: TrainingMix) -> String {
        mix.orderedComponents.map(componentSummary).joined(separator: " + ")
    }

    /// V1 R3 (Plan/strategic spine reconciliation): the same athlete-
    /// facing objective vocabulary already established during onboarding
    /// (`OnboardingFlowView`'s own "Summer Shape"/"10K Race" rows) — reused
    /// here, never a second/renamed label for the same real concept.
    static func datedObjectiveLabel(_ objective: DatedObjective) -> String {
        switch objective.kind {
        case .bodyCompositionMilestone: "Summer Shape"
        case .runningEvent: "10K Race"
        }
    }
}
