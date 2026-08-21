import SwiftUI
import SwiftData

/// Stage 9B: the pre-workout warm-up checklist — Stage 9 design decision
/// D-W1 (plain, self-paced list, no second persisted timer system).
/// Warm-up is always a recommendation, never a requirement: "Start
/// Workout" is available immediately and at every point, and "Skip
/// Warm-up" is explicit. No video/illustration this slice.
struct WarmupView: View {
    let sequence: WarmupSequence
    let onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var completedItemIDs: Set<UUID> = []

    private var items: [WarmupSequenceItem] { sequence.orderedItems }

    private var estimatedTotalSeconds: Int {
        items.reduce(0) { $0 + ($1.movement?.estimatedSeconds ?? 0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Warm-up")
                            .font(Theme.heading)
                            .foregroundStyle(Theme.textPrimary)
                        Text("~\(estimatedMinutesLabel) · recommended, not required")
                            .font(Theme.label)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    VStack(spacing: 10) {
                        ForEach(items) { item in
                            itemRow(item)
                        }
                    }

                    VStack(spacing: 10) {
                        Button("Start Workout", action: onDone)
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.primary)
                            .frame(maxWidth: .infinity)
                        Button("Skip Warm-up") {
                            try? RecordWarmupSequenceUseCase.skipEntirely(sequence, modelContext: modelContext)
                            onDone()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
            }
            .background(Theme.ground)
            .navigationTitle("Warm-up")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var estimatedMinutesLabel: String {
        let minutes = max(1, Int((Double(estimatedTotalSeconds) / 60).rounded()))
        return "\(minutes) min"
    }

    private func itemRow(_ item: WarmupSequenceItem) -> some View {
        let isDone = completedItemIDs.contains(item.id) || item.wasCompleted
        return Button {
            markDone(item)
        } label: {
            HStack {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isDone ? Theme.primary : Theme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.movement?.name ?? "Movement")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textPrimary)
                    if let instruction = item.movement?.instructionText {
                        Text(instruction)
                            .font(Theme.label)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Text(prescriptionLabel(item))
                    .font(Theme.numeric)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(10)
            .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func prescriptionLabel(_ item: WarmupSequenceItem) -> String {
        if let seconds = item.prescribedDurationSeconds {
            return "\(seconds) sec"
        }
        if let reps = item.prescribedReps {
            return (item.movement?.hasSides ?? false) ? "\(reps) reps/side" : "\(reps) reps"
        }
        return ""
    }

    private func markDone(_ item: WarmupSequenceItem) {
        completedItemIDs.insert(item.id)
        try? RecordWarmupSequenceUseCase.markItemCompleted(item, modelContext: modelContext)
    }
}
