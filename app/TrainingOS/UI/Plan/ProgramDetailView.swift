import SwiftUI
import SwiftData

/// Level 2 of Plan's hierarchy (Part 4): the program's week-by-week
/// structure. A week with real materialized Sessions (within the
/// tactical window) shows them, tappable into a real, read-only preview;
/// a week with none yet shows the template's own known structure
/// (`TemplateSessionPreviewView`) — never a fabricated exact future
/// prescription. Reads the real `ProgramInstance.sessions`/
/// `ProgramDefinition.orderedTemplateSessions` graph directly; no
/// parallel dataset.
struct ProgramDetailView: View {
    /// `nil` only for a not-yet-started phase's strategic preview (see
    /// `PhaseDetailViewModel.upcomingComponentPreviews`) — every week then
    /// falls through to the template-only branch below, exactly as an
    /// active program's own not-yet-materialized future week already does.
    let instance: ProgramInstance?
    let definition: ProgramDefinition

    init(instance: ProgramInstance, definition: ProgramDefinition) {
        self.instance = instance
        self.definition = definition
    }

    /// A not-yet-started phase's recommended program — real,
    /// already-known template structure, never a fabricated schedule.
    init(previewDefinition definition: ProgramDefinition) {
        self.instance = nil
        self.definition = definition
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if instance == nil {
                    Text("RECOMMENDED — NOT YET STARTED")
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(0..<max(definition.lengthWeeks, 1), id: \.self) { weekIndex in
                    weekSection(weekIndex)
                }
            }
            .padding(16)
        }
        .background(Theme.ground)
        .navigationTitle(definition.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func weekSection(_ weekIndex: Int) -> some View {
        let sessionsThisWeek = realSessions(forWeek: weekIndex)
        VStack(alignment: .leading, spacing: 10) {
            Text("WEEK \(weekIndex + 1)")
                .font(Theme.label)
                .foregroundStyle(Theme.primary)

            if !sessionsThisWeek.isEmpty {
                ForEach(sessionsThisWeek) { session in
                    NavigationLink {
                        SessionDetailView(session: session, readOnly: true)
                    } label: {
                        realSessionRow(session)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ForEach(definition.orderedTemplateSessions) { templateSession in
                    NavigationLink {
                        TemplateSessionPreviewView(templateSession: templateSession)
                    } label: {
                        templateSessionRow(templateSession)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func realSessions(forWeek weekIndex: Int) -> [Session] {
        guard let instance else { return [] }
        return ProgramWeekGrouping.realSessions(in: instance, forWeek: weekIndex)
    }

    private func realSessionRow(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let date = session.day?.date {
                    Text(weekdayLabel(date))
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(session.name)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(SessionPresentation.statusLabel(session.status))
                    .font(Theme.label)
                    .foregroundStyle(SessionPresentation.statusColor(session.status))
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(session.orderedBlocks) { block in
                if let detail = BlockPresentation.compactDetail(for: block) {
                    Text("\(block.type.rawValue.uppercased()) · \(detail)")
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
        // Stage 6E fix: guarantees the whole row is one tap target.
        .contentShape(Rectangle())
    }

    private func templateSessionRow(_ templateSession: TemplateSession) -> some View {
        HStack {
            Text(templateSession.name)
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("Planned")
                .font(Theme.label)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func weekdayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }
}
