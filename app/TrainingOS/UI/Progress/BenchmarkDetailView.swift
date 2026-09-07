import SwiftUI

/// V1 R4 (Progress reconciliation): the approved design's "benchmark
/// detail" depth screen (`Training OS.dc.html` screen 16, "lower is
/// better, stated") — real `BenchmarkPerformanceProfile`/
/// `FunctionalFitnessResult`/`PersonalRecord` data only, no new benchmark
/// engine. Explicitly preserves the two locked principles: the
/// direction (lower/higher-is-better) is always stated, never implied,
/// and Rx/Scaled results are shown honestly labeled and are never
/// presented as directly comparable performance.
struct BenchmarkDetailView: View {
    let profile: BenchmarkPerformanceProfile

    private var history: [FunctionalFitnessResult] {
        profile.results.sorted { $0.completedAt > $1.completedAt }
    }

    private var rxRecord: PersonalRecord? {
        profile.personalRecords.first { $0.context == .rx }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let rxRecord {
                    prCard(rxRecord)
                }
                if !history.isEmpty {
                    historyCard
                }
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.ground)
        .navigationTitle(profile.benchmark?.name ?? "Benchmark")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(profile.benchmark?.name ?? "Benchmark")
                .font(Theme.headingXL)
                .foregroundStyle(Theme.textPrimary)
            if let direction = profile.benchmark?.scoreDirection {
                Text(ProgressPresentation.scoreDirectionLabel(direction))
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func prCard(_ record: PersonalRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PERSONAL RECORD")
                .font(Theme.eyebrow)
                .tracking(1.4)
                .foregroundStyle(Theme.attention)
            HStack(alignment: .firstTextBaseline) {
                if let result = record.sourceFunctionalFitnessResult {
                    Text(ProgressPresentation.scoreValueLabel(result.scoreValue))
                        .font(Theme.numeric.weight(.bold))
                        .foregroundStyle(Theme.attention)
                }
                Spacer()
                Text(ProgressPresentation.resultContextLabel(record.context))
                    .font(Theme.label)
                    .foregroundStyle(Theme.attention)
                Text(record.achievedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .trainingOSCard(emphasized: true)
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "History").padding(.bottom, 10)
            ForEach(Array(history.enumerated()), id: \.element.id) { index, result in
                HStack {
                    Text(result.completedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 74, alignment: .leading)
                    Spacer()
                    Text(ProgressPresentation.scoreValueLabel(result.scoreValue))
                        .font(Theme.numeric.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    // Rx/Scaled always shown side-by-side with the value,
                    // never merged/hidden — a Scaled attempt must never
                    // read as directly comparable to an Rx one.
                    Text(ProgressPresentation.resultContextLabel(result.resultContext))
                        .font(Theme.label)
                        .foregroundStyle(result.resultContext == .rx ? Theme.positive : Theme.attention)
                        .frame(width: 54, alignment: .trailing)
                }
                .padding(.vertical, 8)
                if index < history.count - 1 { Divider().opacity(0.4) }
            }
            Text("Scaled attempts are kept but never compared against Rx results.")
                .font(Theme.label)
                .foregroundStyle(Theme.textMuted)
                .padding(.top, 10)
        }
        .trainingOSCard()
    }
}
