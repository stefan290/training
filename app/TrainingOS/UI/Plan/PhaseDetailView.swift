import SwiftUI
import SwiftData

/// One `TrainingPhase`'s detail — branches purely on `phase.status`
/// (never a parallel view type per status), reading only the domain
/// model already accepted/materialized by Slices 1-3's real orchestration.
/// Fully read-only: opening this view never creates, materializes, or
/// mutates anything (§12/§15 I,J,K,L).
struct PhaseDetailView: View {
    let phase: TrainingPhase
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = PhaseDetailViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                switch phase.status {
                case .active:
                    activeContent
                case .completed:
                    completedContent
                default:
                    upcomingContent
                }
            }
            .padding(16)
        }
        .background(Theme.ground)
        .navigationTitle(PlanPresentation.phaseTypeLabel(phase.type))
        .task { viewModel.load(phase: phase, modelContext: modelContext) }
    }

    // MARK: Header — shared across every status

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(PlanPresentation.annualPlanStatusLabel(phase.status).uppercased())
                    .font(Theme.label)
                    .foregroundStyle(Theme.primary)
                Spacer()
            }
            Text(dateRangeLabel(phase))
                .font(Theme.numeric)
                .foregroundStyle(Theme.textSecondary)
            if let explanation = viewModel.phaseExplanation {
                Text(explanation)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Active — the full "Current Phase" detail

    @ViewBuilder private var activeContent: some View {
        if let currentWeekIndex = viewModel.currentWeekIndex, let totalWindowWeeks = viewModel.totalWindowWeeks {
            InfoCard(title: "CURRENT TACTICAL WINDOW") {
                Text("Week \(min(currentWeekIndex, totalWindowWeeks - 1) + 1) of \(totalWindowWeeks)")
                    .font(Theme.heading)
                    .foregroundStyle(Theme.textPrimary)
                Text("The next tactical window is generated automatically as this one completes — never before.")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
        }

        if let recommended = viewModel.recommendedMix, let selected = viewModel.selectedMix, recommended.id != selected.id {
            InfoCard(title: "RECOMMENDED") {
                Text(PlanPresentation.mixSummary(recommended))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
            }
            InfoCard(title: "YOUR PLAN") {
                Text(PlanPresentation.mixSummary(selected))
                    .font(Theme.heading)
                    .foregroundStyle(Theme.textPrimary)
            }
        } else if let selected = viewModel.selectedMix {
            InfoCard(title: "TRAINING MIX") {
                Text(PlanPresentation.mixSummary(selected))
                    .font(Theme.heading)
                    .foregroundStyle(Theme.textPrimary)
            }
        }

        componentList
        advanceTacticalWeekCard
        startNextHypertrophyPhaseCard
        nextPhaseCard
    }

    /// Stage 10R.4B: the smallest clear tactical-week-advancement action
    /// — a single explicit button, never automatic
    /// (`STAGE10R4_TACTICAL_ROLLFORWARD_DESIGN.md` Locked Decision 2).
    /// Tapping it re-derives eligibility and rolls exactly once via
    /// `AdvanceTacticalWeekUseCase` — never wired directly to
    /// `RollTacticalWindowUseCase.rollForward`. No new screen: Today
    /// naturally picks up the newly-scheduled Sessions once this view
    /// reloads.
    @ViewBuilder private var advanceTacticalWeekCard: some View {
        if viewModel.canAdvanceTacticalWeek, let nextWeekNumber = viewModel.nextTacticalWeekNumber {
            InfoCard(title: "NEXT WEEK") {
                Text("Week \(nextWeekNumber - 1) complete.")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
                Button("Start Week \(nextWeekNumber)") {
                    if viewModel.advanceTacticalWeek(modelContext: modelContext) {
                        viewModel.load(phase: phase, modelContext: modelContext)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
        }
    }

    /// Stage 10R.2B: the smallest clear transition action — a single
    /// explicit button, never an automatic advance
    /// (`STAGE3_DECISION_MEMO.md` Decision A1). Tapping it starts the
    /// real next mesocycle; the already-existing "Set your starting
    /// weights" calibration gate (`RootTabView`/`SourceRMCalibrationView`)
    /// picks up its fresh calibration requirement automatically — no
    /// separate review/calibration screen is built here.
    @ViewBuilder private var startNextHypertrophyPhaseCard: some View {
        if viewModel.canStartNextHypertrophyPhase, let label = viewModel.nextHypertrophyPhaseTypeLabel {
            InfoCard(title: "NEXT MESOCYCLE") {
                Text("Start \(label) when you're ready to move on from this mesocycle. You'll enter fresh starting weights — nothing carries over automatically.")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
                Button("Start \(label)") {
                    if viewModel.startNextHypertrophyPhase(modelContext: modelContext) {
                        viewModel.load(phase: phase, modelContext: modelContext)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
        }
    }

    // MARK: Completed — historical, read-only

    @ViewBuilder private var completedContent: some View {
        if let selected = viewModel.selectedMix {
            InfoCard(title: "TRAINING MIX (AS COMPLETED)") {
                Text(PlanPresentation.mixSummary(selected))
                    .font(Theme.heading)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        componentList
    }

    // MARK: Upcoming — strategic intent only; never a materialized tactical window

    @ViewBuilder private var upcomingContent: some View {
        InfoCard(title: "PURPOSE") {
            Text(PlanPresentation.phaseTypeLabel(phase.type))
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            if viewModel.upcomingPreviewMix == nil {
                Text("This phase has not started — no training mix or program has been selected for it yet.")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
        }

        if let previewMix = viewModel.upcomingPreviewMix {
            InfoCard(title: "RECOMMENDED TRAINING MIX") {
                Text(PlanPresentation.mixSummary(previewMix))
                    .font(Theme.heading)
                    .foregroundStyle(Theme.textPrimary)
                // Deliberately no claim about *why* this could change
                // (no "readiness" concept exists anywhere in this app,
                // and nothing here yet reads training history) — only
                // the one thing that's actually true today: this is a
                // preview, not the real schedule.
                Text("The exact tactical schedule is generated when this phase becomes active.")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 2)
            }

            if !viewModel.upcomingComponentPreviews.isEmpty {
                InfoCard(title: "PROGRAMS (RECOMMENDED)") {
                    ForEach(viewModel.upcomingComponentPreviews) { preview in
                        upcomingComponentRow(preview)
                    }
                }
            }
        }

        nextPhaseCard
    }

    @ViewBuilder private var nextPhaseCard: some View {
        if let nextPhase = viewModel.nextPhase {
            InfoCard(title: "NEXT") {
                Text(PlanPresentation.phaseTypeLabel(nextPhase.type))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                Text("Starts \(nextPhase.startDate.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func upcomingComponentRow(_ preview: PhaseDetailViewModel.UpcomingComponentPreview) -> some View {
        if let definition = preview.previewProgramDefinition {
            NavigationLink {
                ProgramDetailView(previewDefinition: definition)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PlanPresentation.componentSummary(preview.component))
                            .font(Theme.body)
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(PlanPresentation.programmingSystemLabel(preview.component.programmingSystem)) · \(definition.name)")
                            .font(Theme.label)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        } else {
            HStack {
                Text(PlanPresentation.componentSummary(preview.component))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("No specific program known yet")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: Shared component list — every accepted TrainingMixComponent, mixed modality never collapsed

    @ViewBuilder private var componentList: some View {
        if !viewModel.activeComponents.isEmpty {
            InfoCard(title: "PROGRAMS") {
                ForEach(groupedByPriority, id: \.priority) { group in
                    Text(PlanPresentation.priorityLabel(group.priority).uppercased())
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, group.priority == groupedByPriority.first?.priority ? 0 : 8)
                    ForEach(group.components) { component in
                        componentRow(component)
                    }
                }
            }
        }
    }

    private var groupedByPriority: [(priority: GoalPriority, components: [TrainingMixComponent])] {
        let order: [GoalPriority] = [.primary, .secondary, .supporting]
        return order.compactMap { priority in
            let matches = viewModel.activeComponents.filter { $0.priority == priority }
            return matches.isEmpty ? nil : (priority, matches)
        }
    }

    @ViewBuilder
    private func componentRow(_ component: TrainingMixComponent) -> some View {
        if let instance = component.programInstance, let definition = instance.programDefinition {
            NavigationLink {
                ProgramDetailView(instance: instance, definition: definition)
            } label: {
                HStack {
                    // Three distinct layers, never blurred together
                    // (§5/§6): the component's own modality label ("3×
                    // Strength"), then its real methodology + the
                    // specific program implementing it ("Hypertrophy ·
                    // 3-Day Full Body — Basic Hypertrophy").
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PlanPresentation.componentSummary(component))
                            .font(Theme.body)
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(PlanPresentation.programmingSystemLabel(component.programmingSystem)) · \(definition.name)")
                            .font(Theme.label)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        } else {
            HStack {
                Text(PlanPresentation.componentSummary(component))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("Not yet instantiated")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 6)
        }
    }

    private func dateRangeLabel(_ phase: TrainingPhase) -> String {
        let start = phase.startDate.formatted(.dateTime.month(.abbreviated).day())
        guard let end = phase.endDate else { return "From \(start)" }
        return "\(start) – \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }
}

private struct InfoCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.label)
                .foregroundStyle(Theme.primary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
    }
}
