import SwiftUI
import SwiftData

/// Shows Goal -> Phase -> Program as distinct, labelled concepts per
/// handoff section 2 ("do not visually or technically blur these
/// concepts"). Programs library / import UI is out of scope for this pass.
struct PlanView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = PlanViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let goal = viewModel.goal {
                        GoalCard(goal: goal)
                    }
                    ForEach(viewModel.phases) { phase in
                        if let instance = phase.programInstances.first, let definition = instance.programDefinition {
                            NavigationLink {
                                ProgramDetailView(instance: instance, definition: definition)
                            } label: {
                                PhaseCard(phase: phase, programName: definition.name)
                            }
                            .buttonStyle(.plain)
                        } else {
                            PhaseCard(phase: phase, programName: nil)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.ground)
            .navigationTitle("Plan")
        }
        .task { viewModel.load(modelContext: modelContext) }
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
    /// `nil` when this Phase has no `ProgramInstance` yet — shown plainly,
    /// never a tappable dead end.
    let programName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(phase.status == .active ? "ACTIVE PHASE" : phase.status == .completed ? "COMPLETED PHASE" : "PHASE")
                    .font(Theme.label)
                    .foregroundStyle(Theme.primary)
                Spacer()
                Text(PlanPresentation.phaseStatusLabel(phase.status))
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(PlanPresentation.phaseTypeLabel(phase.type))
                .font(Theme.heading)
                .foregroundStyle(Theme.textPrimary)

            if let programName {
                HStack {
                    Text("PROGRAM · \(programName)")
                        .font(Theme.numeric)
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
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    SeedDataProvider.seedAll(in: container.mainContext)
    return PlanView()
        .modelContainer(container)
}
