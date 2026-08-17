import SwiftUI

/// The completion screen (Part N): concise completed-work/highlights/
/// progression-preview summary — never overloaded with analytics, never
/// fabricating a progression preview when the engine had nothing valid
/// to say (`CompleteSessionUseCase` already omits an item in that case).
struct CompletionSummaryView: View {
    let summary: CompletionSummary
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.session.name)
                        .font(Theme.heading)
                        .foregroundStyle(Theme.textPrimary)
                    Text(summary.completionContext == .full ? "Session complete" : "Finished as partial — remaining blocks marked skipped")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                }

                if !summary.highlights.isEmpty {
                    section("Highlights") {
                        ForEach(Array(summary.highlights.enumerated()), id: \.offset) { _, highlight in
                            HStack {
                                Image(systemName: highlight.isPersonalRecord ? "star.fill" : "checkmark.circle")
                                    .foregroundStyle(highlight.isPersonalRecord ? Theme.positive : Theme.primary)
                                Text("\(highlight.label): \(highlight.value)")
                                    .font(Theme.body)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(highlight.isPersonalRecord ? "New PR" : "Baseline established")
                                    .font(Theme.label)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }

                if !summary.progressionPreview.isEmpty {
                    section("Next Time") {
                        ForEach(Array(summary.progressionPreview.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.exerciseName)
                                    .font(Theme.body)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(item.inputsSummary)
                                    .font(Theme.label)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }

                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .background(Theme.ground)
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(Theme.label)
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
