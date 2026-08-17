import SwiftUI
import SwiftData

/// The Session-level execution shell (Part C/O): this Session's ordered
/// blocks, their status, and its own Start/Finish/Can't-train-today
/// actions — routed here from Today, never a dense dashboard. Each block
/// routes to a modality-specific execution screen; Slice 6/7/8 replace
/// `BlockExecutionPlaceholderView` per `WorkoutBlockType` without this
/// shell's own navigation changing.
struct SessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let session: Session
    /// Lets Today reload immediately after this Session's own status
    /// changes, so a finished morning Session shows "Completed" while an
    /// evening Session still shows "Ready" — never a whole-Day rollup.
    var onChange: () -> Void = {}
    /// Part R: a future Session opened from Week is READ-ONLY —
    /// inspecting it must never start it, create a result, alter its
    /// status, or touch a PerformanceProfile. `false` (the default) is
    /// Today's own actionable Session.
    var readOnly: Bool = false

    @State private var executionState = SessionExecutionState()
    @State private var completionSummary: CompletionSummary?
    @State private var pendingFinishContext: SessionCompletionContext?
    @State private var pendingFeedbackPrompts: [ExercisePrescription] = []

    /// Stage 6E: a completed/skipped/missed/abandoned Session is ALWAYS
    /// history, regardless of the caller's `readOnly` flag — that flag
    /// only disambiguates a `.scheduled` Session (Today's own actionable
    /// one vs. a future one inspected from Week/Plan). Computed from the
    /// same pure, independently-tested `SessionDisplayMode.mode` every
    /// caller already relies on implicitly.
    ///
    /// Internal (not `private`) so a test can construct this exact type
    /// the same way `TodayView`/`WeekView`/`ProgramDetailView` do and
    /// inspect the real decision — never re-implement the routing logic
    /// in the test instead of exercising the actual call site.
    var displayMode: SessionDisplayMode {
        SessionDisplayMode.mode(for: session.status, readOnly: readOnly)
    }

    var body: some View {
        Group {
            if displayMode == .completedHistory {
                CompletedSessionDetail(session: session)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header

                        if displayMode == .futurePreview {
                            // Part E/R: the complete workout, read-only,
                            // before any block can be entered — never the
                            // compact per-block row list a scheduled
                            // Session used to jump straight into execution
                            // from.
                            SessionPreviewContent(session: session)
                        } else {
                            ForEach(session.orderedBlocks) { block in
                                NavigationLink {
                                    destination(for: block)
                                } label: {
                                    BlockRow(block: block)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if displayMode == .execution {
                            actions
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Theme.ground)
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $completionSummary) { summary in
            NavigationStack {
                CompletionSummaryView(summary: summary) {
                    completionSummary = nil
                    onChange()
                    dismiss()
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { pendingFinishContext != nil },
            set: { if !$0 { pendingFinishContext = nil } }
        )) {
            HypertrophyFeedbackView(prescriptions: pendingFeedbackPrompts) {
                let context = pendingFinishContext
                pendingFinishContext = nil
                if let context { finish(context: context) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatusPill(status: session.status)
            if let role = session.role {
                Text(SessionPresentation.roleLabel(role))
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch session.status {
        case .scheduled:
            Button("Start Workout") {
                try? StartSessionUseCase.start(session, asOf: Date(), modelContext: modelContext)
                onChange()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.primary)

            Button("Can't train today", role: .destructive) {
                try? ChangeSessionStatusUseCase.skip(session, modelContext: modelContext)
                onChange()
                dismiss()
            }
        case .inProgress:
            let allCompleted = !session.orderedBlocks.isEmpty
                && session.orderedBlocks.allSatisfy { $0.status == .completed }

            if allCompleted {
                Button("Finish Session") { beginFinish(context: .full) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)
            } else {
                Button("Finish as Partial") { beginFinish(context: .partial) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)

                Button("Resume Later") { dismiss() }
                    .buttonStyle(.bordered)
            }
        case .completed, .skipped, .missed, .abandoned:
            EmptyView()
        }
    }

    /// Every modality's execution screen shares this Session's one
    /// `SessionExecutionState`, so a PR/first-entry logged anywhere in
    /// the Session survives to the completion screen at Finish time.
    @ViewBuilder
    private func destination(for block: WorkoutBlock) -> some View {
        switch block.blockPrescription {
        case .exercise:
            StrengthExecutionView(block: block, session: session, executionState: executionState)
        case .steadyState:
            SteadyStateExecutionView(block: block, session: session, executionState: executionState)
        case .intervals:
            IntervalExecutionView(block: block, session: session, executionState: executionState)
        case .functionalFitness:
            FunctionalFitnessExecutionView(block: block, session: session, executionState: executionState)
        default:
            BlockExecutionPlaceholderView(block: block)
        }
    }

    /// Part 6: before finalizing, collect the one lightweight rating any
    /// completed exercise needs (only those some other slot's next-week
    /// set count actually depends on — never every exercise). Skips
    /// straight to `finish` when nothing is pending.
    private func beginFinish(context: SessionCompletionContext) {
        let prompts = HypertrophyFeedbackPrompts.pending(for: session)
        guard !prompts.isEmpty else {
            finish(context: context)
            return
        }
        pendingFeedbackPrompts = prompts
        pendingFinishContext = context
    }

    /// `CompleteSessionUseCase` is the final consistency point — every
    /// result behind `executionState.highlights` is already durable by
    /// now. Presents the completion screen rather than dismissing
    /// straight back to Today, so the user sees what just happened
    /// before returning (Part N).
    private func finish(context: SessionCompletionContext) {
        guard let summary = try? CompleteSessionUseCase.complete(
            session, context: context, asOf: Date(), highlights: executionState.highlights, modelContext: modelContext
        ) else { return }
        completionSummary = summary
    }
}

private struct BlockRow: View {
    let block: WorkoutBlock

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(block.type.rawValue.uppercased())
                    .font(Theme.label)
                    .foregroundStyle(Theme.primary)
                Text(BlockPresentation.summary(for: block))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            Label(BlockPresentation.statusLabel(block), systemImage: BlockPresentation.statusIcon(block))
                .font(Theme.label)
                .foregroundStyle(BlockPresentation.statusColor(block))
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    SeedDataProvider.seedAll(in: container.mainContext)
    let context = container.mainContext
    let day = (try? context.fetch(FetchDescriptor<Day>()))?.first
    let session = day?.orderedSessions.first ?? Session(name: "Preview", modality: .strength)
    return NavigationStack {
        SessionDetailView(session: session)
    }
    .modelContainer(container)
}
