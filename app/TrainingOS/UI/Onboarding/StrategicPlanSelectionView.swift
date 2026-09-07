import SwiftUI
import SwiftData

/// Stage V1.Checkpoint 2: the real "ready for plan" journey — replaces the
/// Checkpoint-1 placeholder. Shows the athlete's real Goal, the real
/// `LongTermPlanner`-recommended `TrainingMix`, and the real proposed
/// strategic phases, then commits acceptance + first-phase start through
/// the existing production use cases. Never shows internal terms
/// (ProgramInstance, generator config, tactical materialization) — only
/// athlete-facing modality/frequency language (`PlanPresentation`).
///
/// V1 R6 (Onboarding + Plan Selection reconciliation): rebuilt on the R1
/// design foundation (`Theme`/`.trainingOSCard()`/`SectionHeader`) — the
/// interaction model (recommendation vs. selected, Build My Own Mix,
/// alternatives) is unchanged, only its visual language now matches
/// Today/Plan/Progress. Adds the real DATED OBJECTIVES, TRAINING
/// AVAILABILITY, and START DATE sections this checkpoint's locked Review
/// requirement calls for — all read directly from existing, real state
/// (`goal.datedObjectives`, `goal.preferences`, `resolvedStartDate`),
/// never fabricated.
struct StrategicPlanSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = StrategicPlanSelectionViewModel()
    @State private var showingTrainingEnvironmentSettings = false
    @State private var showingCompositionEditor = false
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if viewModel.hasObjectivesConflict {
                        InfoSection(title: "Recommendation") {
                            Text("Two of your dated goals fall on the same date and call for different training focus — they can't both be true on that single day. Please move one of the dates.")
                                .font(Theme.body)
                                .foregroundStyle(Theme.attention)
                        }
                    } else if viewModel.isInfeasible {
                        InfoSection(title: "Recommendation") {
                            Text("TrainingOS couldn't build a strategic plan from your current goal and target date. Try a later target date or a different goal.")
                                .font(Theme.body)
                                .foregroundStyle(Theme.attention)
                        }
                    } else if viewModel.hasNoCompatibleMix {
                        InfoSection(title: "Recommendation") {
                            Text("TrainingOS couldn't find a training mix it can currently run for this goal.")
                                .font(Theme.body)
                                .foregroundStyle(Theme.attention)
                        }
                    } else if let mixSummary = viewModel.recommendedMixSummary {
                        // V1 "Explicit Weekly Composition" checkpoint (PLAN
                        // SCREEN requirement): once the athlete has built a
                        // custom composition, "YOUR SELECTED MIX" is what
                        // will actually start — "TrainingOS recommends"
                        // stays visible as its own, separate, non-
                        // authoritative section, never silently displayed
                        // as though it were about to start instead.
                        if viewModel.isCustomMixSelected {
                            selectedMixCard(mixSummary)
                            if let systemRecommendation = viewModel.systemRecommendationSummary {
                                recommendationCard(systemRecommendation, emphasized: false)
                            }
                        } else {
                            recommendationCard(mixSummary, emphasized: true)
                        }

                        datedObjectivesSection
                        trainingAvailabilitySection

                        if !viewModel.phaseTypeLabels.isEmpty {
                            InfoSection(title: "Strategic Route") {
                                ForEach(Array(viewModel.phaseTypeLabels.enumerated()), id: \.offset) { index, label in
                                    Text("\(index + 1). \(label)")
                                        .font(Theme.body)
                                        .foregroundStyle(Theme.textPrimary)
                                }
                                if viewModel.hasCompressedObjectivePrep {
                                    Text("One of your dated goals has less lead time than TrainingOS would normally want — this plan is a best effort within the time you actually have.")
                                        .font(Theme.label)
                                        .foregroundStyle(Theme.textSecondary)
                                        .padding(.top, 4)
                                }
                            }
                        }

                        startDateSection

                        if !viewModel.alternatives.isEmpty {
                            InfoSection(title: "Other Compatible Options") {
                                ForEach(Array(viewModel.alternatives.enumerated()), id: \.element.mix.id) { index, candidate in
                                    Button {
                                        viewModel.selectAlternative(candidate)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(PlanPresentation.mixSummary(candidate.mix))
                                                .font(Theme.body)
                                                .foregroundStyle(Theme.textPrimary)
                                            Text(alternativeReason(candidate))
                                                .font(Theme.label)
                                                .foregroundStyle(Theme.textSecondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.vertical, index == 0 ? 0 : 4)
                                }
                            }
                        }

                        // V1 "Explicit Weekly Composition" checkpoint: the
                        // athlete is never restricted to the
                        // `CandidateTrainingMix` preset catalog — "no
                        // planner prison."
                        Button("Build My Own Mix") { showingCompositionEditor = true }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                        if viewModel.isCustomMixSelected {
                            Button("Use TrainingOS's Recommendation Instead") {
                                viewModel.selectRecommended()
                            }
                            .font(Theme.label)
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        ProgressView("Building your recommendation…")
                            .padding(.top, 40)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(Theme.label)
                            .foregroundStyle(Theme.attention)
                    }

                    if viewModel.needsTrainingEnvironment {
                        Button("Configure Training Environment") {
                            showingTrainingEnvironmentSettings = true
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    }

                    if viewModel.recommendedMixSummary != nil {
                        Button(viewModel.isAccepting ? "Starting…" : "Accept & Start Training") {
                            if viewModel.acceptAndStart(modelContext: modelContext) {
                                onComplete()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.primary)
                        .frame(maxWidth: .infinity)
                        .disabled(viewModel.isAccepting || viewModel.didSucceed)
                    }
                }
                .padding(Theme.screenPadding)
            }
            .background(Theme.ground)
            .navigationTitle("Your Plan")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { viewModel.load(modelContext: modelContext) }
        .sheet(isPresented: $showingTrainingEnvironmentSettings) {
            TrainingEnvironmentSettingsView()
        }
        .sheet(isPresented: $showingCompositionEditor) {
            WeeklyCompositionEditorView(
                capacity: viewModel.weeklyCapacity,
                cyclingAvailable: viewModel.cyclingSupported,
                onCancel: { showingCompositionEditor = false },
                onUse: { selections in
                    let succeeded = viewModel.buildCustomMix(selections: selections)
                    if succeeded { showingCompositionEditor = false }
                    return succeeded
                }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your Plan").font(Theme.headingXL).foregroundStyle(Theme.textPrimary)
            if let goalTypeLabel = viewModel.goalTypeLabel {
                Text(goalTypeLabel).font(Theme.body).foregroundStyle(Theme.textMuted)
            }
        }
    }

    private func recommendationCard(_ summary: String, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(emphasized ? "TrainingOS Recommends" : "TrainingOS Recommends")
                .font(Theme.eyebrow)
                .tracking(1.2)
                .foregroundStyle(emphasized ? Theme.primary : Theme.textSecondary)
            Text(summary)
                .font(Theme.heading)
                .foregroundStyle(emphasized ? Theme.textPrimary : Theme.textSecondary)
            Text(viewModel.recommendationExplanation ?? "Chosen for your goal, training availability, and preferences.")
                .font(Theme.label)
                .foregroundStyle(Theme.textSecondary)
        }
        .trainingOSCard(emphasized: emphasized)
    }

    private func selectedMixCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Selected Mix")
                .font(Theme.eyebrow)
                .tracking(1.2)
                .foregroundStyle(Theme.primary)
            Text(summary)
                .font(Theme.heading)
                .foregroundStyle(Theme.textPrimary)
            Text("This is the exact mix TrainingOS will build and schedule for you.")
                .font(Theme.label)
                .foregroundStyle(Theme.textSecondary)
        }
        .trainingOSCard(emphasized: true)
    }

    /// V1 R6: real `Goal.datedObjectives`, still-`.planned`, chronologically
    /// sorted — the same real athlete-facing vocabulary already
    /// established in onboarding/Plan (`PlanPresentation.datedObjectiveLabel`).
    /// A milestone-only "Summer Shape" (no paired running event) is a real,
    /// disclosed architectural characteristic: `OnboardingViewModel
    /// .createOrUpdateGoal` only ever projects the milestone into
    /// `Goal.datedObjectives` WHEN a running event also exists — a
    /// milestone-only goal's real intent lives solely in
    /// `Goal.milestoneDate`/`.bodyCompositionDirection`. Shown here too,
    /// mirroring exactly the label `OnboardingFlowView`'s own Review
    /// already uses for it, never a fabricated `DatedObjective` instance.
    /// Omitted entirely (never a fabricated "none") when the athlete has
    /// no real dated objective of either kind.
    @ViewBuilder private var datedObjectivesSection: some View {
        let objectives = (viewModel.goal?.datedObjectives ?? [])
            .filter { $0.status == .planned }
            .sorted { $0.date < $1.date }
        let milestoneOnly = objectives.isEmpty ? viewModel.goal?.milestoneDate : nil
        if !objectives.isEmpty || milestoneOnly != nil {
            InfoSection(title: "Dated Objectives") {
                if let milestoneOnly {
                    objectiveRow(label: "Summer Shape", date: milestoneOnly, isFirst: true)
                }
                ForEach(Array(objectives.enumerated()), id: \.element.id) { index, objective in
                    objectiveRow(label: PlanPresentation.datedObjectiveLabel(objective), date: objective.date, isFirst: index == 0)
                }
            }
        }
    }

    private func objectiveRow(label: String, date: Date, isFirst: Bool) -> some View {
        HStack {
            Text(label).font(Theme.body).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(Theme.numeric)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, isFirst ? 0 : 4)
    }

    /// V1 R6: real `GoalPreferences.availableTrainingDaysPerWeek`/
    /// `.allowsDoubleSessions` — training DAYS, never exact modality
    /// allocation (that's the Weekly Composition section above).
    @ViewBuilder private var trainingAvailabilitySection: some View {
        if let preferences = viewModel.goal?.preferences {
            InfoSection(title: "Training Availability") {
                Text("\(preferences.availableTrainingDaysPerWeek ?? 4) days a week")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                if preferences.allowsDoubleSessions == true {
                    Text("Open to two sessions in one day")
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    /// V1 R6 (R0 START DATE requirement): the real, truthful start —
    /// never "Starts today" for a Tuesday-Sunday acceptance when R0
    /// resolves the first source-backed week to the following Monday.
    @ViewBuilder private var startDateSection: some View {
        if let startDate = viewModel.resolvedStartDate {
            let isToday = Calendar.current.isDateInToday(startDate)
            InfoSection(title: "Start Date") {
                Text(isToday ? "Starts Today" : "Starts \(startDate.formatted(.dateTime.weekday(.wide)))")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                Text(startDate.formatted(date: .long, time: .omitted))
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
                if !isToday {
                    Text("Your plan is accepted now; your first real training week begins then.")
                        .font(Theme.label)
                        .foregroundStyle(Theme.textMuted)
                        .padding(.top, 2)
                }
            }
        }
    }

    /// Stage V1 dogfooding fix (Part 4): athlete-facing "why this fits,"
    /// derived only from the real `CandidateMixRole`s the planner itself
    /// assigned — never invented copy per mix.
    private func alternativeReason(_ candidate: CandidateTrainingMix) -> String {
        if candidate.roles.contains(.bestGoalAlignment) { return "The closest match to your goal." }
        if candidate.roles.contains(.bestVarietyAlternative) { return "More variety across training types." }
        if candidate.roles.contains(.userPreferenceAlternative) { return "Matches your stated preferences." }
        return "Also fits your goal and availability."
    }
}

private struct InfoSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title)
            VStack(alignment: .leading, spacing: 4) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .trainingOSCard()
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    return StrategicPlanSelectionView(onComplete: {})
        .modelContainer(container)
}
