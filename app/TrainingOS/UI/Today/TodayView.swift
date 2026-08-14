import SwiftUI
import SwiftData

/// Renders whatever the ViewModel loaded. No querying, sorting or
/// filtering happens here — that is TodayViewModel's job.
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = TodayViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.sessions.isEmpty {
                    ContentUnavailableView("No sessions today", systemImage: "calendar")
                        .padding(.top, 60)
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(viewModel.sessions) { session in
                            SessionCard(session: session)
                        }
                    }
                    .padding(16)
                }
            }
            .background(Theme.ground)
            .navigationTitle("Today")
        }
        .task { viewModel.load(modelContext: modelContext) }
    }
}

private struct SessionCard: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(session.name)
                    .font(Theme.heading)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let time = session.scheduledTime {
                    Text(time, style: .time)
                        .font(Theme.numeric)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            ForEach(session.orderedBlocks) { block in
                HStack {
                    Text(block.type.rawValue.uppercased())
                        .font(Theme.label)
                        .foregroundStyle(Theme.primary)
                    Text(block.orderedPrescriptions.compactMap { $0.exercise?.canonicalName }.joined(separator: " · "))
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    SeedDataProvider.seedAll(in: container.mainContext)
    return TodayView()
        .modelContainer(container)
}
