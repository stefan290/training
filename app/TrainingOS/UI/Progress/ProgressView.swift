import SwiftUI
import SwiftData

/// V1 R4 "Progress reconciliation" checkpoint: rebuilt on the R1 design
/// foundation to answer the approved product's question — "am I actually
/// progressing?" — via the approved "four numbers, then depth" hierarchy
/// (new-this-week PRs, ranked Estimated 1RM, Consistency, Body Weight),
/// using only real domain truth. No ViewModel/domain behavior changed
/// beyond new read-only derived state; Progress performs zero writes.
struct TrainingProgressView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ProgressViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if viewModel.hasAnyHistory {
                        content
                    } else {
                        EmptyProgressCard()
                    }
                }
                .padding(Theme.screenPadding)
            }
            .background(Theme.ground)
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { viewModel.load(modelContext: modelContext) }
    }

    private var header: some View {
        Text("Progress")
            .font(Theme.headingXL)
            .foregroundStyle(Theme.textPrimary)
    }

    @ViewBuilder private var content: some View {
        if !viewModel.recentRecords.isEmpty {
            NewThisWeekCard(records: viewModel.recentRecords)
        }

        let e1RMProfiles = viewModel.exerciseProfiles.filter { $0.estimatedOneRepMax != nil }
        if !e1RMProfiles.isEmpty {
            SectionHeader(title: "Estimated 1RM")
            EstimatedOneRepMaxList(profiles: e1RMProfiles)
        }

        HStack(spacing: 12) {
            ConsistencyTile(consistency: viewModel.consistency)
            BodyWeightTile()
        }

        if !viewModel.benchmarkProfiles.isEmpty {
            SectionHeader(title: "Functional Fitness")
            BenchmarkSummaryList(profiles: viewModel.benchmarkProfiles)
        }

        let otherProfiles = viewModel.exerciseProfiles.filter { $0.estimatedOneRepMax == nil }
        if !otherProfiles.isEmpty {
            SectionHeader(title: "Other Exercises")
            OtherExercisesList(profiles: otherProfiles)
        }
    }
}

// MARK: - "New this week" — the approved design's PR callout

private struct NewThisWeekCard: View {
    let records: [ProgressViewModel.RecordSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("NEW THIS WEEK")
                    .font(Theme.eyebrow)
                    .tracking(1.4)
                    .foregroundStyle(Theme.attention)
                Spacer()
                Text("\(records.count) PR\(records.count == 1 ? "" : "s")")
                    .font(Theme.numeric)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(records) { record in
                HStack(alignment: .firstTextBaseline) {
                    Text(record.label)
                        .font(Theme.body.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(record.valueLabel)
                        .font(Theme.numeric)
                        .foregroundStyle(Theme.attention)
                }
            }
        }
        .padding(14)
        .background(Theme.attention.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardCornerRadius).strokeBorder(Theme.attention.opacity(0.3)))
    }
}

// MARK: - Estimated 1RM — ranked, with real recency/confidence

private struct EstimatedOneRepMaxList: View {
    let profiles: [ExercisePerformanceProfile]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                NavigationLink { ExerciseDetailView(profile: profile) } label: {
                    row(for: profile)
                }
                .buttonStyle(.plain)
                if index < profiles.count - 1 { Divider().opacity(0.5) }
            }
        }
        .trainingOSCard(padding: 0)
    }

    private func row(for profile: ExercisePerformanceProfile) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.exercise?.canonicalName ?? "Exercise")
                    .font(Theme.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(recencyConfidenceLabel(profile))
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if let estimate = profile.estimatedOneRepMax {
                Text(formattedWeight(estimate))
                    .font(Theme.numeric.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    private func recencyConfidenceLabel(_ profile: ExercisePerformanceProfile) -> String {
        guard let lastPerformedAt = profile.lastPerformedAt else { return ProgressPresentation.confidenceLabel(profile.confidence) }
        let recency = ProgressPresentation.recencyLabel(lastPerformedAt, asOf: Date())
        // A stale estimate is disclosed explicitly rather than presented
        // with the same confidence tier a recent one would get — the
        // approved design's own "never imply a stale estimate is equally
        // current" requirement.
        if ProgressPresentation.isStale(lastPerformedAt: lastPerformedAt, asOf: Date()) {
            return "\(recency) · stale"
        }
        return "\(recency) · \(ProgressPresentation.confidenceLabel(profile.confidence))"
    }

    private func formattedWeight(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

// MARK: - Consistency / Body Weight tiles

private struct ConsistencyTile: View {
    let consistency: (completed: Int, eligible: Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONSISTENCY")
                .font(Theme.eyebrow)
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
            if let consistency, consistency.eligible > 0 {
                Text("\(Int((Double(consistency.completed) / Double(consistency.eligible) * 100).rounded()))%")
                    .font(Theme.numeric.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(consistency.completed) of \(consistency.eligible) sessions")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("Not enough data yet")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainingOSCard()
    }
}

/// No body-weight domain data source exists yet in this app (no
/// persistence, no HealthKit wiring) — the approved empty-state
/// treatment, never a fabricated `0` or a claimed-but-unwired HealthKit
/// read. Adding that source is explicitly out of this checkpoint's scope.
private struct BodyWeightTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BODY WEIGHT")
                .font(Theme.eyebrow)
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
            Text("Not available yet")
                .font(Theme.label)
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainingOSCard()
    }
}

// MARK: - Functional Fitness / benchmark summary

private struct BenchmarkSummaryList: View {
    let profiles: [BenchmarkPerformanceProfile]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                NavigationLink { BenchmarkDetailView(profile: profile) } label: {
                    row(for: profile)
                }
                .buttonStyle(.plain)
                if index < profiles.count - 1 { Divider().opacity(0.5) }
            }
        }
        .trainingOSCard(padding: 0)
    }

    private func row(for profile: BenchmarkPerformanceProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.benchmark?.name ?? "Benchmark")
                    .font(Theme.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                if let lastPerformedAt = profile.lastPerformedAt {
                    Text(ProgressPresentation.recencyLabel(lastPerformedAt, asOf: Date()))
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            if let best = bestRecord(profile) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ProgressPresentation.scoreValueLabel(best.sourceFunctionalFitnessResult?.scoreValue ?? .time(seconds: 0)))
                        .font(Theme.numeric.weight(.bold))
                        .foregroundStyle(Theme.attention)
                    Text(ProgressPresentation.resultContextLabel(best.context))
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    /// Real Rx best only — never a Scaled result shown as if it competed
    /// with Rx (the approved design's explicit "never compared" rule),
    /// falling back to the best Scaled record only when no Rx record
    /// exists at all.
    private func bestRecord(_ profile: BenchmarkPerformanceProfile) -> PersonalRecord? {
        profile.personalRecords.first { $0.context == .rx } ?? profile.personalRecords.first
    }
}

// MARK: - Exercises with real history but no e1RM (e.g. bodyweight-only work)

private struct OtherExercisesList: View {
    let profiles: [ExercisePerformanceProfile]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                NavigationLink { ExerciseDetailView(profile: profile) } label: {
                    HStack {
                        Text(profile.exercise?.canonicalName ?? "Exercise")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(profile.setResults.count) sets logged")
                            .font(Theme.label)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < profiles.count - 1 { Divider().opacity(0.5) }
            }
        }
        .trainingOSCard(padding: 0)
    }
}

// MARK: - Empty state — a brand-new athlete

private struct EmptyProgressCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing logged yet")
                .font(Theme.heading)
                .foregroundStyle(Theme.textPrimary)
            Text("Progress fills in as you complete real training — personal records, estimated 1RM, and consistency will all appear here.")
                .font(Theme.body)
                .foregroundStyle(Theme.textMuted)
        }
        .trainingOSCard()
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    SeedDataProvider.seedAll(in: container.mainContext)
    return TrainingProgressView()
        .modelContainer(container)
}
