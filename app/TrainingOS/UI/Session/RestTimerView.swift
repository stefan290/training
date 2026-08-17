import SwiftUI
import SwiftData

/// A block's rest timer — shared UI shell for the one `TimerState`
/// foundation every execution timer uses (`TIMER_ARCHITECTURE.md`).
/// Configurable duration before starting; pause/resume/skip once running.
/// The countdown itself is a pure function of the persisted `TimerState`
/// and the current moment via `TimelineView`, recomputed every tick —
/// never an accumulated counter (CLAUDE.md rule 21), so backgrounding and
/// relaunching mid-rest shows exactly the time a continuously-running
/// clock would.
struct RestTimerView: View {
    @Environment(\.modelContext) private var modelContext
    let block: WorkoutBlock

    private static let presets = [60, 90, 120, 180]
    @State private var selectedPreset = 90

    var body: some View {
        if let state = block.timerState {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, WorkoutTimer.remainingSeconds(state, asOf: context.date) ?? 0)
                let expired = WorkoutTimer.isExpired(state, asOf: context.date)
                let isPaused = state.pausedAt != nil

                VStack(spacing: 10) {
                    Text(formatted(remaining))
                        .font(.system(.largeTitle, design: .monospaced)).bold()
                        .foregroundStyle(expired ? Theme.attention : Theme.textPrimary)
                        .accessibilityLabel(expired ? "Rest complete" : "\(Int(remaining)) seconds remaining")

                    HStack(spacing: 12) {
                        Button(isPaused ? "Resume" : "Pause") {
                            if isPaused {
                                try? UpdateBlockTimerUseCase.resume(block, asOf: Date(), modelContext: modelContext)
                            } else {
                                try? UpdateBlockTimerUseCase.pause(block, asOf: Date(), modelContext: modelContext)
                            }
                        }
                        Button("Reset") {
                            try? UpdateBlockTimerUseCase.start(
                                block, asOf: Date(), targetDurationSeconds: state.targetDurationSeconds, modelContext: modelContext
                            )
                        }
                        Button("Skip", role: .destructive) {
                            try? UpdateBlockTimerUseCase.clear(block, modelContext: modelContext)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12))
            }
        } else {
            VStack(spacing: 10) {
                Picker("Rest duration", selection: $selectedPreset) {
                    ForEach(Self.presets, id: \.self) { seconds in
                        Text("\(seconds)s").tag(seconds)
                    }
                }
                .pickerStyle(.segmented)

                Button("Start Rest Timer") {
                    try? UpdateBlockTimerUseCase.start(
                        block, asOf: Date(), targetDurationSeconds: selectedPreset, modelContext: modelContext
                    )
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
