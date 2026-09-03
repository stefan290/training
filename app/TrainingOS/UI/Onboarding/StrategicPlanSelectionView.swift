import SwiftUI
import SwiftData

/// Stage V1.Checkpoint 2: the real "ready for plan" journey — replaces the
/// Checkpoint-1 placeholder. Shows the athlete's real Goal, the real
/// `LongTermPlanner`-recommended `TrainingMix`, and the real proposed
/// strategic phases, then commits acceptance + first-phase start through
/// the existing production use cases. Never shows internal terms
/// (ProgramInstance, generator config, tactical materialization) — only
/// athlete-facing modality/frequency language (`PlanPresentation`).
struct StrategicPlanSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = StrategicPlanSelectionViewModel()
    @State private var showingTrainingEnvironmentSettings = false
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let goalTypeLabel = viewModel.goalTypeLabel {
                        InfoSection(title: "YOUR GOAL") {
                            Text(goalTypeLabel)
                                .font(Theme.body)
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }

                    if viewModel.isInfeasible {
                        InfoSection(title: "RECOMMENDATION") {
                            Text("TrainingOS couldn't build a strategic plan from your current goal and target date. Try a later target date or a different goal.")
                                .font(Theme.body)
                                .foregroundStyle(Theme.attention)
                        }
                    } else if viewModel.hasNoCompatibleMix {
                        InfoSection(title: "RECOMMENDATION") {
                            Text("TrainingOS couldn't find a training mix it can currently run for this goal.")
                                .font(Theme.body)
                                .foregroundStyle(Theme.attention)
                        }
                    } else if let mixSummary = viewModel.recommendedMixSummary {
                        InfoSection(title: "RECOMMENDED TRAINING") {
                            Text(mixSummary)
                                .font(Theme.body)
                                .foregroundStyle(Theme.textPrimary)
                            Text("Chosen for your goal, training availability, and preferences.")
                                .font(Theme.label)
                                .foregroundStyle(Theme.textSecondary)
                        }

                        if !viewModel.phaseTypeLabels.isEmpty {
                            InfoSection(title: "YOUR STRATEGIC PLAN") {
                                ForEach(Array(viewModel.phaseTypeLabels.enumerated()), id: \.offset) { index, label in
                                    Text("\(index + 1). \(label)")
                                        .font(Theme.body)
                                        .foregroundStyle(Theme.textPrimary)
                                }
                            }
                        }
                    } else {
                        ProgressView("Building your recommendation…")
                            .padding(.top, 40)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(Theme.label)
                            .foregroundStyle(Theme.attention)
                    }

                    if viewModel.needsTrainingEnvironment {
                        Button("Configure Training Environment") {
                            showingTrainingEnvironmentSettings = true
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }

                    if viewModel.recommendedMixSummary != nil {
                        Button(viewModel.isAccepting ? "Starting…" : "Accept & Start Training") {
                            if viewModel.acceptAndStart(modelContext: modelContext) {
                                onComplete()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.primary)
                        .frame(maxWidth: .infinity)
                        .disabled(viewModel.isAccepting || viewModel.didSucceed)
                    }
                }
                .padding(20)
            }
            .background(Theme.ground)
            .navigationTitle("Your Plan")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { viewModel.load(modelContext: modelContext) }
        .sheet(isPresented: $showingTrainingEnvironmentSettings) {
            TrainingEnvironmentSettingsView()
        }
    }
}

private struct InfoSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.label)
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 4) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    return StrategicPlanSelectionView(onComplete: {})
        .modelContainer(container)
}
