import SwiftUI

/// The complete, read-only breakdown of a Session's prescribed work —
/// every block, every exercise/activity/format, using the real persisted
/// prescriptions (never a second, presentation-only workout
/// representation). Shared by Session Detail's before-starting preview
/// (Part E) and Week's future-Session inspection (Part R) — rendering
/// this view never mutates anything: no status change, no result, no
/// PerformanceProfile effect, regardless of which Session is passed in.
struct SessionPreviewContent: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(session.orderedBlocks) { block in
                blockSection(block)
            }
        }
    }

    @ViewBuilder
    private func blockSection(_ block: WorkoutBlock) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(block.type.rawValue.uppercased())
                    .font(Theme.label)
                    .foregroundStyle(Theme.primary)
                if let detail = BlockPresentation.compactDetail(for: block) {
                    Text(detail)
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            switch block.blockPrescription {
            case .exercise(let prescriptions):
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(prescriptions.enumerated()), id: \.offset) { index, prescription in
                        exerciseRow(index: index, prescription: prescription)
                    }
                }
            case .steadyState(let prescription):
                steadyStateRow(prescription)
            case .intervals(let prescription):
                intervalsRow(prescription)
            case .functionalFitness(let prescription):
                functionalFitnessRow(prescription)
            case nil:
                Text("No prescription")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func exerciseRow(index: Int, prescription: ExercisePrescription) -> some View {
        let sets = prescription.orderedSetPrescriptions
        let first = sets.first
        let repsLabel = first.map { $0.repRangeLow == $0.repRangeHigh ? "\($0.repRangeLow)" : "\($0.repRangeLow)-\($0.repRangeHigh)" }
        let rirLabel = first?.targetRir.map { " @ \($0) RIR" } ?? ""

        return HStack(alignment: .top, spacing: 8) {
            Text("\(index + 1).")
                .font(Theme.numeric)
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(prescription.exercise?.canonicalName ?? "Exercise")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                if let repsLabel {
                    Text("\(sets.count) \u{d7} \(repsLabel)\(rirLabel)")
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func steadyStateRow(_ prescription: SteadyStatePrescription) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(IntensityPresentation.activityLabel(prescription.activityType))
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 10) {
                if let duration = prescription.durationSeconds {
                    Text("\(duration / 60) min")
                }
                if let distance = prescription.distanceMeters {
                    Text("\(Int(distance)) m")
                }
                if let label = IntensityPresentation.label(prescription.primaryIntensity) {
                    Text(label)
                }
            }
            .font(Theme.label)
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private func intervalsRow(_ prescription: IntervalPrescription) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(prescription.intervalCount) \u{d7} \(IntensityPresentation.activityLabel(prescription.activityType))")
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 10) {
                Text("Work:")
                if let duration = prescription.workDurationSeconds { Text("\(duration)s") }
                if let distance = prescription.workDistanceMeters { Text("\(Int(distance)) m") }
                if let label = IntensityPresentation.label(prescription.workIntensity) { Text(label) }
            }
            .font(Theme.label)
            .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 10) {
                Text("Recovery:")
                if let duration = prescription.recoveryDurationSeconds { Text("\(duration)s") }
                if let distance = prescription.recoveryDistanceMeters { Text("\(Int(distance)) m") }
                if let label = IntensityPresentation.label(prescription.recoveryIntensity) { Text(label) }
            }
            .font(Theme.label)
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private func functionalFitnessRow(_ prescription: FunctionalFitnessPrescription) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(BlockPresentation.formatLabel(prescription.format))
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            ForEach(Array(prescription.orderedMovements.enumerated()), id: \.offset) { _, movement in
                Text(movementLine(movement))
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func movementLine(_ movement: FunctionalFitnessMovement) -> String {
        var parts: [String] = [movement.exercise?.canonicalName ?? "Movement"]
        if let reps = movement.reps { parts.append("\(reps) reps") }
        if let calories = movement.calories { parts.append("\(calories) cal") }
        if let distance = movement.distanceMeters { parts.append("\(Int(distance)) m") }
        if let load = movement.loadKilograms { parts.append("\(load.formattedWeight) kg") }
        return parts.joined(separator: " \u{b7} ")
    }
}
