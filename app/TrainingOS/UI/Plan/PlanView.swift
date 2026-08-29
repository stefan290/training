import SwiftUI
import SwiftData

/// Shows Goal -> Phase -> Program as distinct, labelled concepts per
/// handoff section 2 ("do not visually or technically blur these
/// concepts"). Programs library / import UI is out of scope for this pass.
struct PlanView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = PlanViewModel()
    /// Stage 10R.7B: PlanView is the primary strategic lifecycle surface
    /// (D-10R7B-4) — this is the one place `StrategicPhaseTransitionSheet`
    /// is presented from as the phase list's own primary action.
    @State private var transitionPhase: TrainingPhase?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let goal = viewModel.goal {
                        GoalCard(goal: goal)
                    }
                    if let phase = viewModel.phaseAwaitingStrategicTransition {
                        StrategicTransitionBanner(phase: phase) { transitionPhase = phase }
                    }
                    Text("ANNUAL PLAN")
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                    ForEach(viewModel.phases) { phase in
                        NavigationLink {
                            PhaseDetailView(phase: phase)
                        } label: {
                            PhaseCard(phase: phase)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Theme.ground)
            .navigationTitle("Plan")
        }
        .task { viewModel.load(modelContext: modelContext) }
        .sheet(item: $transitionPhase) { phase in
            StrategicPhaseTransitionSheet(currentPhase: phase) {
                viewModel.load(modelContext: modelContext)
            }
        }
    }
}

/// Stage 10R.7B (D-10R7B-1/D-10R7B-3): deliberately NOT styled like
/// `PhaseCard` below — this is a strategic action, not another entry in
/// the annual-plan list, and must never be visually mistaken for a
/// tactical/mesocycle action either.
private struct StrategicTransitionBanner: View {
    let phase: TrainingPhase
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CURRENT PHASE COMPLETE")
                        .font(Theme.label)
                        .foregroundStyle(.white.opacity(0.85))
                    Text("Start Next Phase")
                        .font(Theme.heading)
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.white)
                    .font(.title2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.primary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct GoalCard: View {
    let goal: Goal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GOAL").font(Theme.label).foregroundStyle(Theme.primary)
            Text(PlanPresentation.goalTypeLabel(goal.primaryType))
                .font(Theme.heading)
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PhaseCard: View {
    let phase: TrainingPhase

    private var dateRangeLabel: String {
        let start = phase.startDate.formatted(.dateTime.month(.abbreviated).day())
        guard let end = phase.endDate else { return "From \(start)" }
        return "\(start) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// The mix actually driving (or that drove) execution — selected
    /// always wins over recommended, mirroring `TrainingMix`'s own rule.
    private var mixSummary: String? {
        guard let mix = phase.selectedTrainingMix ?? phase.recommendedTrainingMix, !mix.orderedComponents.isEmpty else { return nil }
        return PlanPresentation.mixSummary(mix)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(PlanPresentation.phaseTypeLabel(phase.type))
                    .font(Theme.heading)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(PlanPresentation.annualPlanStatusLabel(phase.status))
                    .font(Theme.label)
                    .foregroundStyle(phase.status == .active ? Theme.primary : Theme.textSecondary)
            }
            Text(dateRangeLabel)
                .font(Theme.numeric)
                .foregroundStyle(Theme.textSecondary)

            if let mixSummary {
                HStack {
                    Text(mixSummary)
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
        // A custom NavigationLink label with .buttonStyle(.plain) only
        // reliably registers taps on rendered content (text glyphs), not
        // on the background/padding around it (same Stage 6E finding as
        // TodayView's SessionCard). An unconfigured phase renders fewer
        // lines (no mixSummary row), shrinking its real hit-testable area
        // well below the card's visible bounds — this guarantees the
        // entire card is one uniform tap target regardless of how much
        // content a given phase happens to render.
        .contentShape(Rectangle())
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    SeedDataProvider.seedAll(in: container.mainContext)
    return PlanView()
        .modelContainer(container)
}
