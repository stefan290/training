import SwiftUI
import SwiftData

/// Lists permanent exercise history. Deliberately plain — exercise and
/// benchmark detail screens (handoff screens 15, 16) are not built in this
/// pass, only proof that the data survives and is queryable.
struct TrainingProgressView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ProgressViewModel()

    var body: some View {
        NavigationStack {
            List(viewModel.exerciseProfiles) { profile in
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.exercise?.canonicalName ?? "Unknown exercise")
                        .font(Theme.body.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)

                    HStack(spacing: 12) {
                        Text("\(profile.setResults.count) sets logged")
                            .font(Theme.numeric)
                            .foregroundStyle(Theme.textSecondary)
                        if let best = profile.personalRecords.first {
                            Text("PR \(best.value, specifier: "%.1f")")
                                .font(Theme.numeric)
                                .foregroundStyle(Theme.positive)
                        }
                    }
                }
                .listRowBackground(Theme.surfacePrimary)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
            .navigationTitle("Progress")
        }
        .task { viewModel.load(modelContext: modelContext) }
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    SeedDataProvider.seedAll(in: container.mainContext)
    return TrainingProgressView()
        .modelContainer(container)
}
