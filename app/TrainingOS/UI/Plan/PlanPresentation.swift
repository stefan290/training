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
}
