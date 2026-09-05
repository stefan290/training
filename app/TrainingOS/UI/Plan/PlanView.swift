import SwiftUI
import SwiftData

/// V1 R3 "Plan/Strategic Spine Reconciliation" checkpoint: the approved
/// design's "Twelve months as one spine" (`Training OS.dc.html` screen
/// 02, the only Plan mockup in the artifact — never superseded by a
/// later pass) expressed through CURRENT production truth — Goal ->
/// TrainingPlan -> TrainingPhase -> TrainingMix -> ProgramInstances, plus
/// real `DatedObjective`s — never the design's own obsolete Program +
/// Module vocabulary. Zero domain/engine changes: every node here reads
/// already-real, already-persisted state through `PlanViewModel`'s own
/// (also new, but purely derived/read-only) properties.
struct PlanView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = PlanViewModel()
    /// Stage 10R.7B: PlanView is the primary strategic lifecycle surface
    /// (D-10R7B-4) — this is the one place `StrategicPhaseTransitionSheet`
    /// is presented from as the phase list's own primary action.
    @State private var transitionPhase: TrainingPhase?

    /// The real, chronologically sorted sequence of spine items — every
    /// real `TrainingPhase` plus every real, still-`.planned`
    /// `DatedObjective`, ordered by each item's own real anchor date
    /// (`phase.startDate` / `objective.date`). No geometric/proportional
    /// date scaling — the approved design's spine communicates order,
    /// not a literal calendar ruler, so simple chronological list order
    /// is the truthful, non-fabricated representation.
    private var spineItems: [SpineItem] {
        let phaseItems = viewModel.phases.map { SpineItem.phase($0) }
        let objectiveItems = viewModel.datedObjectives.map { SpineItem.objective($0) }
        return (phaseItems + objectiveItems).sorted { $0.anchorDate < $1.anchorDate }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let phase = viewModel.phaseAwaitingStrategicTransition {
                        StrategicTransitionBanner(phase: phase) { transitionPhase = phase }
                    }
                    spine
                    tacticalEntryPoint
                }
                .padding(Theme.screenPadding)
            }
            .background(Theme.ground)
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { viewModel.load(modelContext: modelContext) }
        .sheet(item: $transitionPhase) { phase in
            StrategicPhaseTransitionSheet(currentPhase: phase) {
                viewModel.load(modelContext: modelContext)
            }
        }
    }

    // MARK: Header — the one place the plan states its own overall answer

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let dateRange = planDateRangeLabel {
                Text(dateRange.uppercased())
                    .font(Theme.eyebrow)
                    .tracking(1.4)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text("My Plan")
                .font(Theme.headingXL)
                .foregroundStyle(Theme.textPrimary)
            if let goal = viewModel.goal {
                Text(PlanPresentation.mainGoalLabel(goal.primaryType))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    /// From the first real phase's own start through the last real
    /// phase's own end, when known — never a fabricated horizon. `nil`
    /// (omitted) rather than approximated when no phases exist yet.
    private var planDateRangeLabel: String? {
        guard let first = viewModel.phases.first else { return nil }
        let start = first.startDate.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        guard let lastEnd = viewModel.phases.last?.endDate else { return start }
        return "\(start) → \(lastEnd.formatted(.dateTime.month(.abbreviated).year(.twoDigits)))"
    }

    // MARK: The strategic spine itself

    @ViewBuilder private var spine: some View {
        SectionHeader(title: "Your Journey")
        HStack(alignment: .top, spacing: 14) {
            SpineLine(count: spineItems.count, currentIndex: spineItems.firstIndex { $0.isCurrentPhase(viewModel.currentPhase) })
            VStack(alignment: .leading, spacing: 10) {
                ForEach(spineItems) { item in
                    spineRow(for: item)
                }
                if viewModel.isFinalPhase {
                    Text("No later phase is planned yet.")
                        .font(Theme.label)
                        .foregroundStyle(Theme.textMuted)
                        .padding(.top, 2)
                }
            }
        }
    }

    @ViewBuilder
    private func spineRow(for item: SpineItem) -> some View {
        switch item {
        case .phase(let phase):
            if phase.id == viewModel.currentPhase?.id {
                NavigationLink { PhaseDetailView(phase: phase) } label: {
                    CurrentPhaseCard(
                        phase: phase, upcomingStartDate: viewModel.upcomingStartDate, weekPosition: viewModel.currentWeekPosition
                    )
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink { PhaseDetailView(phase: phase) } label: {
                    FuturePhaseCard(phase: phase)
                }
                .buttonStyle(.plain)
            }
        case .objective(let objective):
            ObjectiveCard(objective: objective)
        }
    }

    // MARK: Tactical entry point — Plan's own route to the real scheduled week

    private var tacticalEntryPoint: some View {
        NavigationLink {
            WeekView()
        } label: {
            Label("View Tactical Week", systemImage: "calendar")
                .font(Theme.body)
                .foregroundStyle(Theme.primary)
        }
        .padding(.top, 4)
    }
}

/// A real spine entry — either an actual `TrainingPhase` or an actual,
/// still-`.planned` `DatedObjective`. Never a third, fabricated kind.
private enum SpineItem: Identifiable {
    case phase(TrainingPhase)
    case objective(DatedObjective)

    var id: String {
        switch self {
        case .phase(let phase): "phase-\(phase.id.uuidString)"
        case .objective(let objective): "objective-\(objective.id.uuidString)"
        }
    }

    var anchorDate: Date {
        switch self {
        case .phase(let phase): phase.startDate
        case .objective(let objective): objective.date
        }
    }

    func isCurrentPhase(_ currentPhase: TrainingPhase?) -> Bool {
        guard case .phase(let phase) = self, let currentPhase else { return false }
        return phase.id == currentPhase.id
    }
}

/// The persistent left-hand connecting line — a plain visual device
/// (chronology only), never a proportional calendar ruler.
private struct SpineLine: View {
    let count: Int
    let currentIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<max(count, 1), id: \.self) { index in
                Rectangle()
                    .fill(isBeforeOrAtCurrent(index) ? Theme.primary : Color.primary.opacity(0.12))
                    .frame(width: 2)
            }
        }
        .frame(width: 12)
    }

    private func isBeforeOrAtCurrent(_ index: Int) -> Bool {
        guard let currentIndex else { return false }
        return index <= currentIndex
    }
}

/// The strongest hierarchy on the screen — answers "what phase am I in /
/// why / what does my normal week look like / how far through it am I."
/// Two truthful sub-states: the R0 upcoming-start state (never implies
/// Week 1 before the real resolved start date) and the genuinely-active
/// state (real week position when materialized, composition always
/// shown from the real selected/recommended `TrainingMix`).
private struct CurrentPhaseCard: View {
    let phase: TrainingPhase
    let upcomingStartDate: Date?
    let weekPosition: (index: Int, total: Int)?

    private var mix: TrainingMix? { phase.selectedTrainingMix ?? phase.recommendedTrainingMix }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("NOW")
                    .font(Theme.eyebrow)
                    .tracking(1.6)
                    .foregroundStyle(Theme.primary)
                Spacer()
                Text(dateRangeLabel(phase))
                    .font(Theme.numeric)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(PlanPresentation.phaseTypeLabel(phase.type))
                .font(Theme.heading)
                .foregroundStyle(Theme.textPrimary)

            if let upcomingStartDate {
                Text("Your plan starts \(upcomingStartDate.formatted(.dateTime.weekday(.wide).day().month(.wide))) — nothing to do before it starts.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textMuted)
            } else {
                if let weekPosition {
                    ProgressView(value: Double(weekPosition.index), total: Double(weekPosition.total))
                        .tint(Theme.primary)
                    Text("Week \(weekPosition.index) of \(weekPosition.total)")
                        .font(Theme.label)
                        .foregroundStyle(Theme.textMuted)
                }
                if let mix {
                    compositionTags(mix)
                }
            }
        }
        .trainingOSCard(emphasized: true)
    }

    private func compositionTags(_ mix: TrainingMix) -> some View {
        HStack(spacing: 6) {
            ForEach(mix.orderedComponents) { component in
                Text(PlanPresentation.componentSummary(component))
                    .font(Theme.label)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Theme.ground, in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func dateRangeLabel(_ phase: TrainingPhase) -> String {
        let start = phase.startDate.formatted(.dateTime.month(.abbreviated).day())
        guard let end = phase.endDate else { return "From \(start)" }
        return "\(start) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

/// A plain future (or past/completed) phase node — real dates, real
/// composition, deliberately lower visual weight than `CurrentPhaseCard`.
private struct FuturePhaseCard: View {
    let phase: TrainingPhase

    private var mixSummary: String? {
        guard let mix = phase.selectedTrainingMix ?? phase.recommendedTrainingMix, !mix.orderedComponents.isEmpty else { return nil }
        return PlanPresentation.mixSummary(mix)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(PlanPresentation.phaseTypeLabel(phase.type))
                    .font(Theme.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(dateRangeLabel(phase))
                    .font(Theme.numeric)
                    .foregroundStyle(Theme.textSecondary)
            }
            if let mixSummary {
                Text(mixSummary)
                    .font(Theme.label)
                    .foregroundStyle(Theme.textMuted)
            } else {
                Text(PlanPresentation.annualPlanStatusLabel(phase.status))
                    .font(Theme.label)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .trainingOSCard()
        .contentShape(Rectangle())
    }

    private func dateRangeLabel(_ phase: TrainingPhase) -> String {
        let start = phase.startDate.formatted(.dateTime.month(.abbreviated).day())
        guard let end = phase.endDate else { return "From \(start)" }
        return "\(start) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

/// A real `DatedObjective`'s own spine position — the approved design's
/// dashed "Target" milestone treatment, applied to whichever real
/// objective actually falls here chronologically (never only the last
/// one — multiple real objectives each get their own node).
private struct ObjectiveCard: View {
    let objective: DatedObjective

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(PlanPresentation.datedObjectiveLabel(objective).uppercased())
                .font(Theme.label)
                .foregroundStyle(Theme.attention)
            Spacer()
            Text(objective.date.formatted(.dateTime.day().month(.abbreviated)))
                .font(Theme.numeric)
                .foregroundStyle(Theme.attention)
        }
        .padding(12)
        .background(Theme.attention.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                .strokeBorder(Theme.attention.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }
}

/// Stage 10R.7B (D-10R7B-1/D-10R7B-3): deliberately NOT styled like the
/// phase nodes above — this is a strategic action, not another entry in
/// the spine, and must never be visually mistaken for a tactical/
/// mesocycle action either.
private struct StrategicTransitionBanner: View {
    let phase: TrainingPhase
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CURRENT PHASE COMPLETE")
                        .font(Theme.label)
                        .foregroundStyle(.white.opacity(0.85))
                    Text("Start Next Phase")
                        .font(Theme.heading)
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.white)
                    .font(.title2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.primary, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    SeedDataProvider.seedAll(in: container.mainContext)
    return PlanView()
        .modelContainer(container)
}
