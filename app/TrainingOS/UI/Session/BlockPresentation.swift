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

    /// Stage 6C: a short "what kind of work, how much" line — "5
    /// exercises," "40 min," "6 intervals," "20 min AMRAP" — never the
    /// full exercise-name list `summary(for:)` returns, so a multi-
    /// exercise Strength block never reads as if its first exercise were
    /// the entire workout (Part D). `nil` only when nothing is
    /// derivable at all (an empty/unprescribed block).
    ///
    /// Duration is shown only when it's a real prescribed value (Steady
    /// State's own `durationSeconds`, a Functional Fitness format's own
    /// cap) or a direct arithmetic derivation from prescribed values
    /// (Interval's work+recovery × count) — never invented for Strength,
    /// which has no per-set duration model anywhere in this app
    /// (Part W; see `STAGE6C_ACCEPTANCE_REPORT.md`).
    static func compactDetail(for block: WorkoutBlock) -> String? {
        switch block.blockPrescription {
        case .exercise(let prescriptions):
            guard !prescriptions.isEmpty else { return nil }
            return "\(prescriptions.count) exercise\(prescriptions.count == 1 ? "" : "s")"
        case .steadyState(let prescription):
            if let seconds = prescription.durationSeconds { return "\(seconds / 60) min" }
            if let meters = prescription.distanceMeters { return "\(Int(meters)) m" }
            return activityLabel(prescription.activityType)
        case .intervals(let prescription):
            if let work = prescription.workDurationSeconds, let recovery = prescription.recoveryDurationSeconds {
                let totalMinutes = (work + recovery) * prescription.intervalCount / 60
                return "\(prescription.intervalCount) x \(activityLabel(prescription.activityType)) · ~\(totalMinutes) min"
            }
            return "\(prescription.intervalCount) intervals"
        case .functionalFitness(let prescription):
            return formatLabel(prescription.format)
        case nil:
            return nil
        }
    }

    /// The first few exercise names in canonical order, for Today's
    /// compact "Back Squat, Romanian Deadlift, +3 more" preview line —
    /// `nil` for any block whose prescription isn't exercise-based.
    static func exerciseNames(for block: WorkoutBlock) -> [String]? {
        guard case .exercise(let prescriptions) = block.blockPrescription else { return nil }
        return prescriptions.compactMap { $0.exercise?.canonicalName }
    }

    /// V1 R2 (Today reconciliation): a human label for `WorkoutBlockType`
    /// — Today's block-type eyebrow previously rendered the raw enum case
    /// (`block.type.rawValue.uppercased()`), which reads correctly for
    /// most cases but produces "STEADYSTATE"/"FORTIME"/"AMROP"-style
    /// concatenated internal terminology for the camelCase cases. Never a
    /// business decision, purely a display string, same purpose as every
    /// other function in this file.
    static func blockTypeLabel(_ type: WorkoutBlockType) -> String {
        switch type {
        case .warmup: "Warm-up"
        case .strength: "Strength"
        case .hypertrophy: "Hypertrophy"
        case .accessory: "Accessory"
        case .steadyState: "Steady State"
        case .intervals: "Intervals"
        case .amrap: "AMRAP"
        case .emom: "EMOM"
        case .forTime: "For Time"
        case .cooldown: "Cooldown"
        case .mobility: "Mobility"
        case .functionalFitness: "Functional Fitness"
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

    /// Stage FF.P1: shared by `FunctionalFitnessExecutionView`'s live
    /// header and `CompletedFunctionalFitnessDetail`'s prescribed-section
    /// rendering, so both stay in sync automatically, mirroring this
    /// type's own established purpose. A movement's `reps`/`distanceMeters`
    /// are a real, non-nil concrete target once generated (or explicitly
    /// authored) — never fabricated here; a movement with neither set
    /// (e.g. Assault Bike, which FF.P1 deliberately leaves untargeted)
    /// shows only its exercise name, exactly as truthfully as before
    /// FF.P1 existed.
    static func prescribedMovementLine(_ movement: FunctionalFitnessMovement) -> String {
        var parts: [String] = [movement.exercise?.canonicalName ?? "Movement"]
        if let reps = movement.reps { parts.append("\(reps) reps") }
        if let calories = movement.calories { parts.append("\(calories) cal") }
        if let distance = movement.distanceMeters { parts.append("\(Int(distance)) m") }
        if let load = movement.loadKilograms { parts.append("\(load.formattedWeight) kg") }
        return parts.joined(separator: " \u{b7} ")
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
