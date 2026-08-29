import SwiftUI
import SwiftData

/// Stage 10R.7B: the compact summary + explicit "Start Next Phase" action
/// (D-10R7B-3/D-10R7B-5) — never a full plan review/editor screen. Always
/// invokes `TransitionPhaseUseCase` through `StrategicTransitionViewModel`;
/// never mutates phase/instance/mix state directly here (D-10R7B-6).
struct StrategicPhaseTransitionSheet: View {
    let currentPhase: TrainingPhase
    /// Called once, only after a successful transition — the presenter
    /// reloads its own data and the app-wide calibration gate re-checks
    /// itself via `.strategicPhaseTransitionCompleted`.
    var onTransitionSucceeded: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = StrategicTransitionViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if viewModel.didSucceed {
                        successContent
                    } else {
                        summaryContent
                    }
                }
                .padding(16)
            }
            .background(Theme.ground)
            .navigationTitle("Next Phase")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(viewModel.didSucceed ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
        .task { viewModel.load(currentPhase: currentPhase, modelContext: modelContext) }
        .onDisappear {
            if viewModel.didSucceed { onTransitionSucceeded() }
        }
    }

    @ViewBuilder private var summaryContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CURRENT PHASE COMPLETE").font(Theme.label).foregroundStyle(Theme.textSecondary)
            Text(PlanPresentation.phaseTypeLabel(currentPhase.type))
                .font(Theme.heading)
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))

        if let nextPhase = viewModel.nextPhase {
            VStack(alignment: .leading, spacing: 8) {
                Text("NEXT").font(Theme.label).foregroundStyle(Theme.primary)
                Text(PlanPresentation.phaseTypeLabel(nextPhase.type))
                    .font(Theme.heading)
                    .foregroundStyle(Theme.textPrimary)
                Text(dateRangeLabel(nextPhase))
                    .font(Theme.numeric)
                    .foregroundStyle(Theme.textSecondary)
                if let mixSummary = viewModel.previewMixSummary {
                    // Deliberately labeled "Recommended mix," never
                    // presented as already selected/accepted — it only
                    // actually becomes the phase's `.selected` mix the
                    // moment "Start Next Phase" below is tapped (mirrors
                    // `TrainingPhase.recommendedTrainingMix`/
                    // `.selectedTrainingMix`'s own existing distinction).
                    Text("RECOMMENDED MIX")
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 4)
                    Text(mixSummary)
                        .font(Theme.body)
                        .foregroundStyle(Theme.textPrimary)
                }
                if viewModel.previewIncludesCalibrationRequiredSystem {
                    Text("You'll enter fresh starting weights before this phase's training becomes executable — nothing carries over automatically.")
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(Theme.label)
                    .foregroundStyle(.red)
            }

            Button {
                viewModel.startTransition(modelContext: modelContext)
            } label: {
                Group {
                    if viewModel.isTransitioning {
                        ProgressView()
                    } else {
                        Text("Start Next Phase")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.primary)
            .disabled(viewModel.isTransitioning)
        } else {
            Text("No next phase is available to start.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder private var successContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PHASE STARTED").font(Theme.label).foregroundStyle(Theme.primary)
            if let nextPhase = viewModel.nextPhase {
                Text(PlanPresentation.phaseTypeLabel(nextPhase.type))
                    .font(Theme.heading)
                    .foregroundStyle(Theme.textPrimary)
            }
            if (viewModel.componentsAwaitingCalibrationCount ?? 0) > 0 {
                Text("Set your starting weights to begin this phase's training — you'll be routed there next.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 4)
            } else {
                Text("Your training for this phase is ready.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func dateRangeLabel(_ phase: TrainingPhase) -> String {
        let start = phase.startDate.formatted(.dateTime.month(.abbreviated).day())
        guard let end = phase.endDate else { return "From \(start)" }
        return "\(start) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }
}
