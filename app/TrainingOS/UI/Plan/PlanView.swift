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
                        PhaseCard(phase: phase)
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
            Text(goal.primaryType.rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PHASE").font(Theme.label).foregroundStyle(Theme.primary)
                Spacer()
                Text(phase.status.rawValue.uppercased())
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(phase.type.rawValue)
                .font(Theme.heading)
                .foregroundStyle(Theme.textPrimary)

            if let instance = phase.programInstances.first, let definition = instance.programDefinition {
                Text("PROGRAM · \(definition.name)")
                    .font(Theme.numeric)
                    .foregroundStyle(Theme.textSecondary)
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
