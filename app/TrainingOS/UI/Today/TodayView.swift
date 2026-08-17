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
                            NavigationLink {
                                SessionDetailView(session: session, onChange: {
                                    viewModel.load(modelContext: modelContext)
                                })
                            } label: {
                                SessionCard(
                                    session: session,
                                    onStart: { viewModel.start(session, modelContext: modelContext) },
                                    onMarkMissed: { viewModel.markMissed(session, modelContext: modelContext) }
                                )
                            }
                            .buttonStyle(.plain)
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

/// A Session's Today card: role/duration/purpose/status/major blocks and
/// its own start-resume-complete state — never the engine internals
/// behind that state (Part C). Multiple sessions on one Day each get
/// their own independent card and status; nothing here implies "the Day"
/// has an aggregate state.
private struct SessionCard: View {
    let session: Session
    let onStart: () -> Void
    let onMarkMissed: () -> Void

    /// Purely a display check — a scheduled Session whose time has
    /// passed is *shown* as possibly missed, but nothing is written until
    /// the user actually taps a button (SESSION_STATE_MACHINE.md §7).
    private var isPastDueUnstarted: Bool {
        session.status == .scheduled && (session.scheduledTime.map { $0 < Date() } ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name)
                        .font(Theme.heading)
                        .foregroundStyle(Theme.textPrimary)
                    if let role = session.role {
                        Text(SessionPresentation.roleLabel(role))
                            .font(Theme.label)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                if let time = session.scheduledTime {
                    Text(time, style: .time)
                        .font(Theme.numeric)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            StatusPill(status: session.status)

            ForEach(session.orderedBlocks) { block in
                HStack {
                    Text(block.type.rawValue.uppercased())
                        .font(Theme.label)
                        .foregroundStyle(Theme.primary)
                    Text(BlockPresentation.summary(for: block))
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer()
                }
            }

            if isPastDueUnstarted {
                Text("This was scheduled earlier today — still want to do it?")
                    .font(Theme.label)
                    .foregroundStyle(Theme.attention)
                HStack {
                    Button("Start Anyway", action: onStart)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.primary)
                    Button("Mark Missed", action: onMarkMissed)
                        .buttonStyle(.bordered)
                }
            } else if session.status == .scheduled {
                Button("Start", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)
            }
        }
        .padding(14)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Small, non-color-only status indicator (an icon + word, never color
/// alone) reused by both the Today card and Session detail header.
struct StatusPill: View {
    let status: SessionStatus

    var body: some View {
        Label(SessionPresentation.statusLabel(status), systemImage: SessionPresentation.statusIcon(status))
            .font(Theme.label)
            .foregroundStyle(SessionPresentation.statusColor(status))
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    SeedDataProvider.seedAll(in: container.mainContext)
    return TodayView()
        .modelContainer(container)
}
