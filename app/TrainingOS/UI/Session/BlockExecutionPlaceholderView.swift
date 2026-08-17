import SwiftUI
import SwiftData

/// Stage 6B Slice 5 placeholder — shared by every `WorkoutBlockType`
/// until Slice 6 (Strength), Slice 7 (Steady State/Interval) and Slice 8
/// (Functional Fitness) replace it with a real modality-specific screen
/// (set logging, rest/AMRAP/EMOM timers, etc.). Its purpose is to make
/// the Today -> Session -> Block navigation shell fully wired and
/// end-to-end testable in the Simulator before those richer screens
/// land — this view itself is never the intended final execution UI for
/// any modality.
struct BlockExecutionPlaceholderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let block: WorkoutBlock

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(BlockPresentation.summary(for: block))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)

                if block.status != .completed && block.status != .skipped {
                    Button("Mark Complete") {
                        try? CompleteBlockUseCase.complete(block, context: .full, modelContext: modelContext)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)

                    Button("Skip", role: .destructive) {
                        try? CompleteBlockUseCase.skip(block, modelContext: modelContext)
                        dismiss()
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.ground)
        .navigationTitle(block.type.rawValue.capitalized)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            try? CompleteBlockUseCase.start(block, modelContext: modelContext)
        }
    }
}
