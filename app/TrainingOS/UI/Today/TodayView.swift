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

                        // Part D/U: Today's simple route to the full
                        // training week — never itself becoming the
                        // planner.
                        NavigationLink {
                            WeekView()
                        } label: {
                            Label("View Week", systemImage: "calendar")
                                .font(Theme.body)
                                .foregroundStyle(Theme.primary)
                        }
                        .padding(.top, 4)
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
    /// the user actually taps a button (SESSION_STATE_MACHINE.md §7). See
    /// `SessionPresentation.isPastDueUnstarted` for the actual decision.
    private var isPastDueUnstarted: Bool {
        SessionPresentation.isPastDueUnstarted(status: session.status, scheduledTime: session.scheduledTime)
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
                    Text(SessionPresentation.scheduledTimeLabel(time))
                        .font(Theme.numeric)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            StatusPill(status: session.status)

            ForEach(session.orderedBlocks) { block in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(block.type.rawValue.uppercased())
                            .font(Theme.label)
                            .foregroundStyle(Theme.primary)
                        if let detail = BlockPresentation.compactDetail(for: block) {
                            Text(detail)
                                .font(Theme.body)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                    }
                    // Part D: a compact preview of which exercises, never
                    // the full workout — a multi-exercise Strength block
                    // must never read as if its first exercise were the
                    // entire session.
                    if let names = BlockPresentation.exerciseNames(for: block), !names.isEmpty {
                        Text(compactList(names))
                            .font(Theme.label)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
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
            } else {
                // Stage 6E fix: every other status (in progress/
                // completed/skipped/missed/abandoned) has no button of
                // its own, so it must never rely on incidental "the
                // background happens to be tappable" behavior — an
                // explicit, unmissable affordance instead.
                HStack {
                    Spacer()
                    Text(navigationAffordanceLabel)
                    Image(systemName: "chevron.right")
                }
                .font(Theme.label)
                .foregroundStyle(Theme.primary)
            }
        }
        .padding(14)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
        // Stage 6E fix: a custom NavigationLink label with .buttonStyle(.plain)
        // otherwise only reliably registers taps on rendered content
        // (text/icon glyphs), not on the background/padding around it —
        // this guarantees the entire card, including empty space, is
        // one tap target, never dependent on where a finger happens to land.
        .contentShape(Rectangle())
    }

    private var navigationAffordanceLabel: String {
        switch session.status {
        case .inProgress: "Resume"
        case .completed, .skipped, .missed, .abandoned: "View Workout"
        case .scheduled: ""
        }
    }

    private func compactList(_ names: [String]) -> String {
        let shown = names.prefix(3)
        let remaining = names.count - shown.count
        let base = shown.joined(separator: ", ")
        return remaining > 0 ? "\(base), +\(remaining) more" : base
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
