import SwiftUI

/// Pure display-string/icon/color mapping for a WorkoutBlock — never a
/// business decision, just what to print for whichever typed
/// prescription is populated. Reused by Today's compact block line and
/// Session Detail's block row so both stay in sync automatically.
enum BlockPresentation {
    static func summary(for block: WorkoutBlock) -> String {
        switch block.blockPrescription {
        case .exercise(let prescriptions):
            let names = prescriptions.compactMap { $0.exercise?.canonicalName }
            return names.isEmpty ? "No exercises" : names.joined(separator: " · ")
        case .steadyState(let prescription):
            let target = durationOrDistance(seconds: prescription.durationSeconds, meters: prescription.distanceMeters)
            return "\(activityLabel(prescription.activityType)) · \(target)"
        case .intervals(let prescription):
            return "\(prescription.intervalCount) x \(activityLabel(prescription.activityType)) intervals"
        case .functionalFitness(let prescription):
            let names = prescription.orderedMovements.compactMap { $0.exercise?.canonicalName }
            let format = formatLabel(prescription.format)
            return names.isEmpty ? format : "\(format) · \(names.joined(separator: ", "))"
        case nil:
            return "—"
        }
    }

    static func statusLabel(_ block: WorkoutBlock) -> String {
        switch block.status {
        case .pending: "Pending"
        case .active: "In Progress"
        case .completed: block.completionContext == .partial ? "Partial" : "Completed"
        case .skipped: "Skipped"
        }
    }

    static func statusIcon(_ block: WorkoutBlock) -> String {
        switch block.status {
        case .pending: "circle"
        case .active: "play.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .skipped: "forward.circle"
        }
    }

    static func statusColor(_ block: WorkoutBlock) -> Color {
        switch block.status {
        case .pending: Theme.textSecondary
        case .active: Theme.primary
        case .completed: Theme.positive
        case .skipped: Theme.textSecondary
        }
    }

    private static func activityLabel(_ type: ActivityType) -> String {
        switch type {
        case .running: "Running"
        case .cycling: "Cycling"
        case .rowing: "Rowing"
        case .skiErg: "SkiErg"
        case .other: "Activity"
        }
    }

    private static func durationOrDistance(seconds: Int?, meters: Double?) -> String {
        if let seconds { return "\(seconds / 60) min" }
        if let meters { return "\(Int(meters)) m" }
        return "—"
    }

    static func formatLabel(_ format: WorkoutFormat) -> String {
        switch format {
        case .amrap(let capSeconds): "AMRAP \(capSeconds / 60)min"
        case .emom(_, let totalSeconds): "EMOM \(totalSeconds / 60)min"
        case .forTime(let capSeconds): capSeconds.map { "For Time (cap \($0 / 60)min)" } ?? "For Time"
        case .roundsForTime(let rounds, _): "\(rounds) Rounds For Time"
        case .chipper: "Chipper"
        case .ladder(let direction, _): "Ladder (\(direction.rawValue))"
        case .maxLoad: "Max Load"
        case .maxReps: "Max Reps"
        case .intervals(let count, _, _): "\(count) Intervals"
        }
    }
}
