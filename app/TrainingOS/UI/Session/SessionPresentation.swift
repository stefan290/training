import SwiftUI

/// Pure display-string/icon/color mapping for a Session's status — never
/// a business decision, just what the Today card and Session Detail
/// header print for a given `SessionStatus`/`SessionRole`. Status is
/// always paired with an icon, never color alone (Part O accessibility
/// requirement).
enum SessionPresentation {
    static func statusLabel(_ status: SessionStatus) -> String {
        switch status {
        case .scheduled: "Ready"
        case .inProgress: "In Progress"
        case .completed: "Completed"
        case .skipped: "Skipped"
        case .missed: "Missed"
        case .abandoned: "Abandoned"
        }
    }

    static func statusIcon(_ status: SessionStatus) -> String {
        switch status {
        case .scheduled: "circle"
        case .inProgress: "play.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .skipped: "forward.circle"
        case .missed: "exclamationmark.circle"
        case .abandoned: "xmark.circle"
        }
    }

    static func statusColor(_ status: SessionStatus) -> Color {
        switch status {
        case .scheduled: Theme.textSecondary
        case .inProgress: Theme.primary
        case .completed: Theme.positive
        case .skipped: Theme.textSecondary
        case .missed: Theme.attention
        case .abandoned: Theme.textSecondary
        }
    }

    static func roleLabel(_ role: SessionRole) -> String {
        switch role {
        case .strength: "Strength"
        case .hypertrophy: "Hypertrophy"
        case .easy: "Easy"
        case .recovery: "Recovery"
        case .long: "Long"
        case .tempo: "Tempo"
        case .threshold: "Threshold"
        case .interval: "Interval"
        case .aerobicBase: "Aerobic Base"
        case .functionalFitness: "Functional Fitness"
        case .skill: "Skill"
        case .mixed: "Mixed"
        }
    }
}
