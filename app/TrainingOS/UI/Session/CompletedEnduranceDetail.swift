import SwiftUI

/// Stage 6E: read-only completed detail for a `.steadyState` block —
/// prescribed target alongside the actual logged `SteadyStateResult`.
struct CompletedSteadyStateDetail: View {
    let block: WorkoutBlock

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let prescription = block.steadyStatePrescription {
                    prescribedSection(prescription)
                }
                performedSection
            }
            .padding(16)
        }
        .background(Theme.ground)
        .navigationTitle("Steady State")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func prescribedSection(_ prescription: SteadyStatePrescription) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PRESCRIBED")
                .font(Theme.label)
                .foregroundStyle(Theme.primary)
            Text(IntensityPresentation.activityLabel(prescription.activityType))
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 10) {
                if let duration = prescription.durationSeconds { Text("\(duration / 60) min") }
                if let distance = prescription.distanceMeters { Text("\(Int(distance)) m") }
                if let label = IntensityPresentation.label(prescription.primaryIntensity) { Text(label) }
            }
            .font(Theme.label)
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var performedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PERFORMED")
                .font(Theme.label)
                .foregroundStyle(Theme.primary)
            if let result = block.steadyStateResult {
                Text(durationLabel(result.actualDurationSeconds))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                if let distance = result.actualDistanceMeters {
                    metricRow("Distance", "\(Int(distance)) m")
                }
                if let hr = result.averageHeartRate {
                    metricRow("Avg HR", "\(hr) bpm")
                }
                if let power = result.averagePower {
                    metricRow("Avg Power", "\(power) W")
                }
                if let pace = result.averagePaceSecondsPerKilometer {
                    metricRow("Avg Pace", "\(IntensityPresentation.paceLabel(secondsPerKilometer: pace))/km")
                }
                if let rpe = result.rpe {
                    metricRow("RPE", "\(rpe)")
                }
                if result.personalRecord != nil {
                    Text("Personal record!")
                        .font(Theme.label)
                        .foregroundStyle(Theme.attention)
                }
            } else {
                Text("Not completed")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Theme.label).foregroundStyle(Theme.textSecondary)
            Text(value).font(Theme.body).foregroundStyle(Theme.textPrimary)
        }
    }

    private func durationLabel(_ seconds: Int) -> String {
        "\(seconds / 60) min \(seconds % 60)s"
    }
}

/// Stage 6E: read-only completed detail for an `.intervals` block —
/// prescribed work/recovery structure alongside every actual per-interval
/// result (never collapsed into a session-average-only view — the
/// per-rep detail is exactly what `IntervalRepResult` exists to preserve).
struct CompletedIntervalDetail: View {
    let block: WorkoutBlock

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let prescription = block.intervalPrescription {
                    prescribedSection(prescription)
                }
                performedSection
            }
            .padding(16)
        }
        .background(Theme.ground)
        .navigationTitle("Intervals")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func prescribedSection(_ prescription: IntervalPrescription) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PRESCRIBED")
                .font(Theme.label)
                .foregroundStyle(Theme.primary)
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var performedSection: some View {
        if let result = block.intervalResult {
            VStack(alignment: .leading, spacing: 10) {
                Text("PERFORMED")
                    .font(Theme.label)
                    .foregroundStyle(Theme.primary)

                ForEach(Array(result.orderedRepResults.enumerated()), id: \.offset) { index, rep in
                    repRow(index: index, rep: rep)
                }

                summaryRow(result)

                if result.personalRecord != nil {
                    Text("Personal record!")
                        .font(Theme.label)
                        .foregroundStyle(Theme.attention)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
        } else {
            Text("Not completed")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func repRow(index: Int, rep: IntervalRepResult) -> some View {
        HStack {
            Text("\(index + 1).")
                .font(Theme.numeric)
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    if let duration = rep.actualWorkDurationSeconds { Text("\(duration)s") }
                    if let distance = rep.actualWorkDistanceMeters { Text("\(Int(distance)) m") }
                    if let pace = rep.averagePaceSecondsPerKilometer { Text("\(IntensityPresentation.paceLabel(secondsPerKilometer: pace))/km") }
                    if let power = rep.averagePower { Text("\(power) W") }
                    if let hr = rep.averageHeartRate { Text("\(hr) bpm") }
                }
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
                if !rep.wasCompletedAsPrescribed {
                    Text("Incomplete")
                        .font(Theme.label)
                        .foregroundStyle(Theme.attention)
                }
            }
        }
    }

    private func summaryRow(_ result: IntervalResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let duration = result.sessionDurationSeconds {
                Text("Total: \(duration / 60) min").font(Theme.label).foregroundStyle(Theme.textSecondary)
            }
            if let distance = result.sessionDistanceMeters {
                Text("Distance: \(Int(distance)) m").font(Theme.label).foregroundStyle(Theme.textSecondary)
            }
            if let pace = result.averagePaceSecondsPerKilometer {
                Text("Avg Pace: \(IntensityPresentation.paceLabel(secondsPerKilometer: pace))/km").font(Theme.label).foregroundStyle(Theme.textSecondary)
            }
            if let hr = result.averageHeartRate {
                Text("Avg HR: \(hr) bpm").font(Theme.label).foregroundStyle(Theme.textSecondary)
            }
            if let rpe = result.rpe {
                Text("RPE: \(rpe)").font(Theme.label).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
