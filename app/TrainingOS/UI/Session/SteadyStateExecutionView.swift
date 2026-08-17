import SwiftUI
import SwiftData

/// Steady State execution (Part H): activity/target duration-distance/
/// intensity, a plain elapsed-time clock, and a completion form covering
/// whichever metrics this modality can actually supply — never blocked on
/// a missing sensor/HealthKit permission (CLAUDE.md rule 13/14).
struct SteadyStateExecutionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SteadyStateExecutionViewModel
    let session: Session

    @State private var showingCompletion = false
    @State private var showingChangeActivity = false
    @State private var lastHighlight: LoggedResultHighlight?

    init(block: WorkoutBlock, session: Session) {
        _viewModel = State(initialValue: SteadyStateExecutionViewModel(block: block))
        self.session = session
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let prescription = viewModel.prescription {
                    header(prescription)

                    if let highlight = lastHighlight {
                        Text(highlight.isFirstEverEntry ? "Baseline established: \(highlight.value)" : "Logged: \(highlight.value)")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if viewModel.block.status != .completed {
                        clock

                        Button("Finish Activity") { showingCompletion = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.primary)
                            .frame(maxWidth: .infinity)

                        Button("Change Activity") { showingChangeActivity = true }
                            .buttonStyle(.bordered)
                    } else {
                        ContentUnavailableView("Activity logged", systemImage: "checkmark.circle")
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.ground)
        .navigationTitle(viewModel.prescription.map { IntensityPresentation.activityLabel($0.activityType) } ?? "Steady State")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCompletion) {
            SteadyStateCompletionForm(viewModel: viewModel) { highlight in
                lastHighlight = highlight
                try? CompleteBlockUseCase.complete(viewModel.block, context: .full, modelContext: modelContext)
            }
        }
        .sheet(isPresented: $showingChangeActivity) {
            if let prescription = viewModel.prescription {
                ChangeActivityView(reference: .steadyState(prescription), session: session)
            }
        }
        .task {
            try? CompleteBlockUseCase.start(viewModel.block, modelContext: modelContext)
            if viewModel.block.timerState == nil {
                try? UpdateBlockTimerUseCase.start(viewModel.block, asOf: Date(), targetDurationSeconds: nil, modelContext: modelContext)
            }
        }
    }

    private func header(_ prescription: SteadyStatePrescription) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(IntensityPresentation.activityLabel(prescription.activityType))
                .font(Theme.heading)
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 12) {
                if let duration = prescription.durationSeconds {
                    Text("Target: \(duration / 60) min")
                }
                if let distance = prescription.distanceMeters {
                    Text("\(Int(distance)) m")
                }
            }
            .font(Theme.body)
            .foregroundStyle(Theme.textSecondary)
            if let label = IntensityPresentation.label(prescription.primaryIntensity) {
                Text(label)
                    .font(Theme.numeric)
                    .foregroundStyle(Theme.primary)
            }
        }
    }

    private var clock: some View {
        Group {
            if let state = viewModel.block.timerState {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = max(0, WorkoutTimer.elapsedSeconds(state, asOf: context.date))
                    let isPaused = state.pausedAt != nil
                    VStack(spacing: 10) {
                        Text(formatted(elapsed))
                            .font(.system(.largeTitle, design: .monospaced)).bold()
                            .foregroundStyle(Theme.textPrimary)
                        HStack(spacing: 12) {
                            Button(isPaused ? "Resume" : "Pause") {
                                if isPaused {
                                    try? UpdateBlockTimerUseCase.resume(viewModel.block, asOf: Date(), modelContext: modelContext)
                                } else {
                                    try? UpdateBlockTimerUseCase.pause(viewModel.block, asOf: Date(), modelContext: modelContext)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }
}

private struct SteadyStateCompletionForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let viewModel: SteadyStateExecutionViewModel
    let onLogged: (LoggedResultHighlight?) -> Void

    @State private var durationMinutes: Int
    @State private var distanceMeters: String = ""
    @State private var averageHeartRate: String = ""
    @State private var averagePower: String = ""
    @State private var rpe: Int = 5

    init(viewModel: SteadyStateExecutionViewModel, onLogged: @escaping (LoggedResultHighlight?) -> Void) {
        self.viewModel = viewModel
        self.onLogged = onLogged
        let elapsed = viewModel.block.timerState.map { WorkoutTimer.elapsedSeconds($0, asOf: Date()) } ?? 0
        _durationMinutes = State(initialValue: max(1, Int(elapsed) / 60))
    }

    var body: some View {
        NavigationStack {
            Form {
                Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 1...600)
                TextField("Distance (m)", text: $distanceMeters).keyboardType(.numberPad)
                TextField("Avg heart rate", text: $averageHeartRate).keyboardType(.numberPad)
                TextField("Avg power (W)", text: $averagePower).keyboardType(.numberPad)
                Stepper("RPE: \(rpe)", value: $rpe, in: 1...10)
            }
            .navigationTitle("Finish Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let highlight = viewModel.logResult(
                            actualDurationSeconds: durationMinutes * 60,
                            actualDistanceMeters: Double(distanceMeters),
                            averageHeartRate: Int(averageHeartRate),
                            averagePower: Int(averagePower),
                            averagePaceSecondsPerKilometer: nil,
                            rpe: rpe,
                            modelContext: modelContext
                        )
                        onLogged(highlight)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
