import SwiftUI
import SwiftData

/// Interval execution (Part I): current/total interval, Work/Recovery
/// state, targets, and next step. Time-based intervals auto-progress
/// Work -> Recovery -> Work from elapsed wall-clock time; distance-based
/// intervals (no clock to derive progress from) are logged by hand, one
/// interval at a time.
struct IntervalExecutionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: IntervalExecutionViewModel
    let session: Session

    @State private var showingFinish = false
    @State private var showingChangeActivity = false
    @State private var manualDistanceText = ""
    @State private var manualCompleted = true
    @State private var lastHighlight: LoggedResultHighlight?

    init(block: WorkoutBlock, session: Session) {
        _viewModel = State(initialValue: IntervalExecutionViewModel(block: block))
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

                    if viewModel.block.status == .completed {
                        ContentUnavailableView("Intervals logged", systemImage: "checkmark.circle")
                    } else if viewModel.isTimeBased {
                        timeBasedBody(prescription)
                    } else {
                        distanceBasedBody(prescription)
                    }

                    if viewModel.block.status != .completed {
                        Button("Change Activity") { showingChangeActivity = true }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.ground)
        .navigationTitle(viewModel.prescription.map { IntensityPresentation.activityLabel($0.activityType) } ?? "Intervals")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingFinish) {
            IntervalFinishForm(viewModel: viewModel) { highlight in
                lastHighlight = highlight
                try? CompleteBlockUseCase.complete(viewModel.block, context: .full, modelContext: modelContext)
            }
        }
        .sheet(isPresented: $showingChangeActivity) {
            if let prescription = viewModel.prescription {
                ChangeActivityView(reference: .intervals(prescription), session: session)
            }
        }
        .task {
            try? CompleteBlockUseCase.start(viewModel.block, modelContext: modelContext)
            if viewModel.isTimeBased, viewModel.block.timerState == nil {
                try? UpdateBlockTimerUseCase.start(viewModel.block, asOf: Date(), targetDurationSeconds: nil, modelContext: modelContext)
            }
        }
    }

    private func header(_ prescription: IntervalPrescription) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(IntensityPresentation.activityLabel(prescription.activityType))
                .font(Theme.heading)
                .foregroundStyle(Theme.textPrimary)
            Text("\(prescription.intervalCount) intervals")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
            if let label = IntensityPresentation.label(prescription.workIntensity) {
                Text(label)
                    .font(Theme.numeric)
                    .foregroundStyle(Theme.primary)
            }
        }
    }

    @ViewBuilder
    private func timeBasedBody(_ prescription: IntervalPrescription) -> some View {
        if viewModel.block.timerState != nil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                intervalClock(prescription: prescription, now: context.date)
            }
        }
    }

    private func intervalClock(prescription: IntervalPrescription, now: Date) -> some View {
        viewModel.syncCompletedLegs(asOf: now, modelContext: modelContext)
        guard let position = viewModel.position(asOf: now), let state = viewModel.block.timerState else {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(spacing: 12) {
                Text(position.isWork ? "WORK" : "RECOVERY")
                    .font(Theme.label)
                    .foregroundStyle(position.isWork ? Theme.primary : Theme.positive)
                Text("Interval \(position.intervalNumber) of \(prescription.intervalCount)")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                Text(formatted(position.remainingInLegSeconds))
                    .font(.system(.largeTitle, design: .monospaced)).bold()
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: 12) {
                    Button(state.pausedAt == nil ? "Pause" : "Resume") {
                        if state.pausedAt == nil {
                            try? UpdateBlockTimerUseCase.pause(viewModel.block, asOf: Date(), modelContext: modelContext)
                        } else {
                            try? UpdateBlockTimerUseCase.resume(viewModel.block, asOf: Date(), modelContext: modelContext)
                        }
                    }
                    if position.isWork {
                        Button("Mark Incomplete") { viewModel.markCurrentLegIncomplete(asOf: Date()) }
                    }
                }
                .buttonStyle(.bordered)

                if position.isSessionComplete {
                    Button("Finish") { showingFinish = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.primary)
                        .frame(maxWidth: .infinity)
                } else {
                    Button("Finish Early") { showingFinish = true }
                        .buttonStyle(.bordered)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 12))
        )
    }

    private func distanceBasedBody(_ prescription: IntervalPrescription) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Interval \(min(viewModel.loggedIntervalCount + 1, prescription.intervalCount)) of \(prescription.intervalCount)")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)

            if viewModel.loggedIntervalCount < prescription.intervalCount {
                TextField("Distance (m)", text: $manualDistanceText)
                    .keyboardType(.numberPad)
                Toggle("Completed as prescribed", isOn: $manualCompleted)
                Button("Log Interval") {
                    viewModel.logManualInterval(
                        actualWorkDistanceMeters: Double(manualDistanceText),
                        wasCompletedAsPrescribed: manualCompleted,
                        modelContext: modelContext
                    )
                    manualDistanceText = ""
                    manualCompleted = true
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
            } else {
                Button("Finish") { showingFinish = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct IntervalFinishForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let viewModel: IntervalExecutionViewModel
    let onFinished: (LoggedResultHighlight?) -> Void

    @State private var averageHeartRate = ""
    @State private var sessionDistanceMeters = ""
    @State private var rpe = 6

    var body: some View {
        NavigationStack {
            Form {
                TextField("Avg heart rate", text: $averageHeartRate).keyboardType(.numberPad)
                TextField("Total distance (m)", text: $sessionDistanceMeters).keyboardType(.numberPad)
                Stepper("RPE: \(rpe)", value: $rpe, in: 1...10)
            }
            .navigationTitle("Finish Intervals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let highlight = viewModel.finish(
                            sessionDurationSeconds: nil,
                            sessionDistanceMeters: Double(sessionDistanceMeters),
                            averageHeartRate: Int(averageHeartRate),
                            rpe: rpe,
                            modelContext: modelContext
                        )
                        onFinished(highlight)
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
