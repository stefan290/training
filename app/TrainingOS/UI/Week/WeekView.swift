import SwiftUI
import SwiftData

/// "What does my training look like?" — the whole current training week,
/// every day, every Session, read from the real scheduled/materialized
/// `Day`/`Session` graph (Part O, Part AH.7). Complements Today ("what do
/// I train now?"); never a second scheduler, never a duplicate status
/// system, never a fabricated exact prescription beyond what's actually
/// materialized (Part T).
struct WeekView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = WeekViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                weekNavigationBar

                if viewModel.weekHasNoMaterializedData {
                    ContentUnavailableView(
                        "Not yet planned",
                        systemImage: "calendar.badge.clock",
                        description: Text("This week hasn't been scheduled yet. Check back closer to the date.")
                    )
                } else {
                    ForEach(viewModel.days) { day in
                        dayCard(day)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.ground)
        .navigationTitle("Week")
        .navigationBarTitleDisplayMode(.inline)
        .task { viewModel.load(modelContext: modelContext) }
    }

    /// Part S: at minimum Previous/Current/Next Week, current week always
    /// obvious. Compact icon + center-label layout — guaranteed to fit on
    /// any device width/Dynamic Type size, unlike three full-text bordered
    /// buttons sharing one row. "This Week"/"Current Week" stays a single
    /// button (disabled, not hidden, when already on the current week) so
    /// its width never shifts between states.
    private var weekNavigationBar: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.goToPreviousWeek(modelContext: modelContext)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous Week")

            Button {
                viewModel.goToCurrentWeek(modelContext: modelContext)
            } label: {
                Text(viewModel.weekNavigationLabel)
                    .frame(maxWidth: .infinity)
            }
            .disabled(viewModel.isCurrentWeek)

            Button {
                viewModel.goToNextWeek(modelContext: modelContext)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next Week")
        }
        .buttonStyle(.bordered)
        .font(Theme.label)
    }

    @ViewBuilder
    private func dayCard(_ day: WeekViewModel.WeekDay) -> some View {
        let isToday = Calendar.current.isDateInToday(day.date)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(weekdayLabel(day.date))
                    .font(Theme.heading)
                    .foregroundStyle(Theme.textPrimary)
                if isToday {
                    Text("TODAY")
                        .font(Theme.label)
                        .foregroundStyle(Theme.primary)
                }
            }

            if day.sessions.isEmpty {
                // Part V: presentation only — no fake Rest Session entity.
                Text("Rest Day")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(day.sessions) { session in
                    NavigationLink {
                        SessionDetailView(session: session, readOnly: !isToday)
                    } label: {
                        sessionRow(session, isToday: isToday)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func sessionRow(_ session: Session, isToday: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.name)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Label(SessionPresentation.weekStatusLabel(for: session.status, isToday: isToday), systemImage: SessionPresentation.statusIcon(session.status))
                    .font(Theme.label)
                    .foregroundStyle(SessionPresentation.statusColor(session.status))
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(session.orderedBlocks) { block in
                HStack(spacing: 6) {
                    Text(block.type.rawValue.uppercased())
                        .font(Theme.label)
                        .foregroundStyle(Theme.primary)
                    if let detail = BlockPresentation.compactDetail(for: block) {
                        Text(detail)
                            .font(Theme.label)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 10))
        // Stage 6E fix: guarantees the whole row — not just its rendered
        // text glyphs — is one tap target, matching the same fix applied
        // to Today's SessionCard.
        .contentShape(Rectangle())
    }

    private func weekdayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date).uppercased()
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    SeedDataProvider.seedAll(in: container.mainContext)
    return NavigationStack {
        WeekView()
    }
    .modelContainer(container)
}
