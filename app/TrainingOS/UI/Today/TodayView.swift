import SwiftUI
import SwiftData

/// Renders whatever the ViewModel loaded. No querying, sorting or
/// filtering happens here — that is TodayViewModel's job.
///
/// V1 R2 "Today reconciliation" checkpoint: rebuilt on the R1 design
/// foundation (`Theme`/`TrainingOSCard`/`SectionHeader`) to answer the
/// approved product's one locked question — "what am I doing today?" —
/// truthfully across every real domain state, including the R0 "a
/// brand-new plan's first tactical week begins on a genuine calendar
/// week" upcoming-start state. No ViewModel/domain behavior changed;
/// only presentation.
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = TodayViewModel()
    /// Stage 8B: the Session currently going through the readiness gate —
    /// presented before `viewModel.start` ever fires
    /// (`READINESS_ADAPTATION_PIPELINE.md` §0).
    @State private var readinessGateSession: Session?
    /// The reported gap this closes: finishing the readiness/warm-up gate
    /// (`ReadinessGateFlow`'s `onFinished`, fired by both WarmupView's
    /// "Start Workout" and "Skip Warm-up") used to only dismiss the
    /// full-screen cover and mark the Session `.inProgress` in place —
    /// leaving the user back on this plain list with no indication where
    /// to go next, never inside the actual workout. Setting this
    /// immediately after starting pushes the SAME Session (identity
    /// unchanged — Stage 8B mutates in place, never copies) straight into
    /// `SessionDetailView`, which itself auto-advances into the sole
    /// block for a single-block Session (`SessionDetailView.autoOpenedBlock`).
    /// Independent of the existing per-card `NavigationLink`s below —
    /// tapping a card manually is completely unaffected.
    @State private var justStartedSession: Session?
    /// Stage TE.1 closure: the handoff's own locked navigation
    /// ("Profile from the avatar in the Today header" —
    /// `Training OS Handoff.dc.html` line 27/141/144) is the real,
    /// already-designated production entry point for Training
    /// Environment configuration — not a new tab, not new Settings
    /// architecture. `Profile → Integrations · Settings · Advanced` is a
    /// full hub out of this stage's scope; this presents Training
    /// Environment configuration directly, the only piece TE.1 needs.
    @State private var showingTrainingEnvironmentSettings = false

    /// The one session this screen treats as primary — the first not-yet-
    /// finished Session if any exist, otherwise the first Session (every
    /// Session for today already completed/terminal). Never reorders
    /// `viewModel.sessions` itself; only picks which one leads.
    private var primarySession: Session? {
        viewModel.sessions.first { $0.status == .scheduled || $0.status == .inProgress } ?? viewModel.sessions.first
    }

    private var secondarySessions: [Session] {
        guard let primarySession else { return [] }
        return viewModel.sessions.filter { $0.id != primarySession.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if let primarySession {
                        if viewModel.sessions.count > 1 {
                            SectionHeader(title: sessionEyebrow(for: primarySession, isPrimary: true))
                        }
                        NavigationLink {
                            SessionDetailView(session: primarySession, onChange: {
                                viewModel.load(modelContext: modelContext)
                            })
                        } label: {
                            SessionHeroCard(
                                session: primarySession,
                                onStart: { readinessGateSession = primarySession },
                                onMarkMissed: { viewModel.markMissed(primarySession, modelContext: modelContext) }
                            )
                        }
                        .buttonStyle(.plain)

                        ForEach(secondarySessions) { session in
                            SectionHeader(title: sessionEyebrow(for: session, isPrimary: false))
                            NavigationLink {
                                SessionDetailView(session: session, onChange: {
                                    viewModel.load(modelContext: modelContext)
                                })
                            } label: {
                                SessionSecondaryCard(
                                    session: session,
                                    onStart: { readinessGateSession = session },
                                    onMarkMissed: { viewModel.markMissed(session, modelContext: modelContext) }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    } else if let upcoming = viewModel.upcomingPlanStart {
                        UpcomingPlanStartCard(upcoming: upcoming)
                    } else {
                        RestDayCard(phaseType: viewModel.currentPhaseType)
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
                    // Stage V1 dogfooding fix (Part 5): the Stage 8B
                    // manual-acceptance debug button removed. Even
                    // `#if DEBUG`-gated, it inserted real, ad-hoc
                    // Session rows directly into the same real store an
                    // athlete's own real Sessions live in — reachable
                    // during exactly the kind of Debug-configuration
                    // build real-device dogfooding uses. The underlying
                    // `DebugAcceptanceFixturesUseCase` and its own
                    // dedicated test coverage
                    // (`DebugAcceptanceFixturesUseCaseTests`) are
                    // untouched — only this athlete-facing trigger is
                    // removed.
                }
                .padding(Theme.screenPadding)
            }
            .background(Theme.ground)
            // Accessibility: kept as a real (if visually secondary)
            // navigation title so VoiceOver/screen-name context is never
            // lost even though the screen's own large header carries the
            // primary visual answer — the artifact's own header design
            // never shows a system nav bar title at all, but removing it
            // outright would be an accessibility regression this
            // checkpoint's own "preserve or improve accessibility"
            // instruction forbids trading away for pixel fidelity.
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingTrainingEnvironmentSettings = true
                    } label: {
                        ProfileAvatarGlyph()
                    }
                    .accessibilityLabel("Profile")
                }
            }
            .navigationDestination(item: $justStartedSession) { session in
                SessionDetailView(session: session, onChange: {
                    viewModel.load(modelContext: modelContext)
                })
            }
        }
        .task { viewModel.load(modelContext: modelContext) }
        .fullScreenCover(item: $readinessGateSession) { session in
            ReadinessGateFlow(session: session) {
                readinessGateSession = nil
                viewModel.start(session, modelContext: modelContext)
                justStartedSession = session
            }
        }
        .sheet(isPresented: $showingTrainingEnvironmentSettings) {
            TrainingEnvironmentSettingsView()
        }
    }

    /// The date/title header answering "what am I doing today" at a
    /// glance — the artifact's own recurring "uppercase date eyebrow +
    /// large direct-answer title" pattern (screen 06). The title itself
    /// is the one place this screen states its own overall answer before
    /// any card detail.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                .font(Theme.eyebrow)
                .tracking(1.4)
                .foregroundStyle(Theme.textSecondary)
            Text(headerTitle)
                .font(Theme.headingXL)
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var headerTitle: String {
        if viewModel.sessions.count > 1 { return "\(viewModel.sessions.count) sessions" }
        if let session = primarySession { return session.name }
        if viewModel.upcomingPlanStart != nil { return "Not started yet" }
        return "Rest day"
    }

    private func sessionEyebrow(for session: Session, isPrimary: Bool) -> String {
        let timeLabel = session.scheduledTime.map(SessionPresentation.scheduledTimeLabel) ?? "Anytime"
        return isPrimary ? "\(timeLabel) · up next" : timeLabel
    }
}

/// V1 R2: the primary, emphasized session — full ordered-block preview,
/// the screen's one clear "Start Session" primary action. Multiple
/// Sessions today (Part B) are never merged into this one card; a second
/// real Session gets its own `SessionSecondaryCard` below, never folded
/// into this card's own block list.
private struct SessionHeroCard: View {
    let session: Session
    let onStart: () -> Void
    let onMarkMissed: () -> Void

    private var isPastDueUnstarted: Bool {
        SessionPresentation.isPastDueUnstarted(status: session.status, scheduledTime: session.scheduledTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
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
                StatusPill(status: session.status)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(session.orderedBlocks.enumerated()), id: \.element.id) { index, block in
                    BlockRow(index: index + 1, block: block)
                    if index < session.orderedBlocks.count - 1 {
                        Divider().opacity(0.5)
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
                Button(action: onStart) {
                    Text("Start \(session.name)")
                        .font(Theme.heading)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
                .controlSize(.large)
            } else {
                // Stage 6E fix: every other status (in progress/
                // completed/skipped/missed/abandoned) has no button of
                // its own, so it must never rely on incidental "the
                // background happens to be tappable" behavior — an
                // explicit, unmissable affordance instead (Part C: never
                // keep presenting Start as the primary action once a
                // Session is no longer startable).
                HStack {
                    Spacer()
                    Text(navigationAffordanceLabel(for: session.status))
                    Image(systemName: "chevron.right")
                }
                .font(Theme.label)
                .foregroundStyle(Theme.primary)
            }
        }
        .trainingOSCard(emphasized: session.status == .scheduled || session.status == .inProgress)
        // Stage 6E fix: a custom NavigationLink label with .buttonStyle(.plain)
        // otherwise only reliably registers taps on rendered content
        // (text/icon glyphs), not on the background/padding around it —
        // this guarantees the entire card, including empty space, is
        // one tap target, never dependent on where a finger happens to land.
        .contentShape(Rectangle())
    }
}

/// V1 R2: a genuinely second (or later) real Session today — lower
/// visual priority than the hero, but never hidden or merged into it
/// (Part B: legitimate multiple sessions must be represented truthfully).
private struct SessionSecondaryCard: View {
    let session: Session
    let onStart: () -> Void
    let onMarkMissed: () -> Void

    private var isPastDueUnstarted: Bool {
        SessionPresentation.isPastDueUnstarted(status: session.status, scheduledTime: session.scheduledTime)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.name)
                    .font(Theme.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                if let detail = session.orderedBlocks.first.flatMap(BlockPresentation.compactDetail) {
                    Text(detail)
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            if isPastDueUnstarted {
                Button("Start Anyway", action: onStart)
                    .buttonStyle(.bordered)
                    .tint(Theme.attention)
            } else if session.status == .scheduled {
                Button("Start", action: onStart)
                    .buttonStyle(.bordered)
                    .tint(Theme.primary)
            } else {
                StatusPill(status: session.status)
            }
        }
        .trainingOSCard()
        .contentShape(Rectangle())
    }
}

/// V1 R2: one numbered, ordered `WorkoutBlock` row — the artifact's own
/// numbered-list Today block preview, restyled onto R1 tokens. Enough to
/// understand the upcoming session's shape without becoming full
/// execution UI (never the full per-set logging surface).
private struct BlockRow: View {
    let index: Int
    let block: WorkoutBlock

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(format: "%02d", index))
                .font(Theme.label)
                .foregroundStyle(Theme.textInactive)
                .frame(width: 20, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(BlockPresentation.blockTypeLabel(block.type))
                    .font(Theme.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                if let detail = BlockPresentation.compactDetail(for: block) {
                    Text(detail)
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
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
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func compactList(_ names: [String]) -> String {
        let shown = names.prefix(3)
        let remaining = names.count - shown.count
        let base = shown.joined(separator: ", ")
        return remaining > 0 ? "\(base), +\(remaining) more" : base
    }
}

/// V1 R2 (Part D): a legitimate rest day should feel intentional, never
/// like missing data — no error/empty-state iconography, just a plain,
/// calm restatement of real phase context when it's available.
private struct RestDayCard: View {
    let phaseType: PhaseType?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No training planned today")
                .font(Theme.heading)
                .foregroundStyle(Theme.textPrimary)
            if let phaseType {
                Text("Part of your \(PlanPresentation.phaseTypeLabel(phaseType)) phase.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textMuted)
            } else {
                Text("Enjoy the recovery.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .trainingOSCard()
    }
}

/// V1 R2 (Part E, the new R0 state): a brand-new plan whose first
/// tactical week hasn't genuinely begun yet — never a fake workout, never
/// a fabricated bridge session, just a truthful, restrained statement of
/// when real training starts (`TodayViewModel.upcomingPlanStart`, itself
/// only ever reading R0's own already-resolved `TrainingPhase.startDate`).
private struct UpcomingPlanStartCard: View {
    let upcoming: TodayViewModel.UpcomingPlanStart

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your plan starts \(upcoming.startDate.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
                .font(Theme.heading)
                .foregroundStyle(Theme.textPrimary)
            Text("Your \(PlanPresentation.phaseTypeLabel(upcoming.phaseType)) phase begins then — nothing to do before it starts.")
                .font(Theme.body)
                .foregroundStyle(Theme.textMuted)
        }
        .trainingOSCard(emphasized: true)
    }
}

/// V1 R1: a restrained circular avatar glyph in place of the bare SF
/// Symbol toolbar icon — the artifact's own Today-header profile
/// affordance treatment (a plain tinted circle, screen 06), without
/// building the still-missing full Profile hub this checkpoint
/// deliberately leaves out of scope.
private struct ProfileAvatarGlyph: View {
    var body: some View {
        Circle()
            .fill(Theme.surfaceSecondary)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.12)))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            )
            .frame(width: 32, height: 32)
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

private func navigationAffordanceLabel(for status: SessionStatus) -> String {
    switch status {
    case .inProgress: "Resume"
    case .completed, .skipped, .missed, .abandoned: "View Workout"
    case .scheduled: ""
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    SeedDataProvider.seedAll(in: container.mainContext)
    return TodayView()
        .modelContainer(container)
}
