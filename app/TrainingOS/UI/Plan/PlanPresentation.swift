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
}
