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
                        whatItNeedsSection

                        // R6 Visual Correction Pass: only ever a full card
                        // when the route actually carries information —
                        // `proposeForwardOnlyPhases`'s own open-ended,
                        // no-target-date case (the common Build Muscle
                        // path) returns exactly ONE phase, and a single-
                        // entry "route" added nothing but visual weight
                        // ("1. Muscle Gain" as its own card). Real,
                        // multi-phase routes (a dated objective, a stated
                        // target date) still show in full.
                        if viewModel.phaseTypeLabels.count > 1 {
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

                        // R6 First-Run Journey Design Completion: the prior
                        // round's low-emphasis alternative-mix link STILL
                        // recreated a second, competing path alongside
                        // "Build My Own Mix" — two ways to deviate from the
                        // recommendation on the same screen. Screen 24's
                        // real hierarchy is exactly two actions: "Use
                        // recommended" (primary) and "Choose another
                        // program" (ONE secondary path) — never a specific
                        // passive candidate highlighted on the primary
                        // recommendation screen itself. Real candidate
                        // data + `selectAlternative` are UNCHANGED (still
                        // real, still reachable — just not surfaced here);
                        // "Build My Own Mix" is now the one, unambiguous
                        // secondary action ("no planner prison").
                        //
                        // V1 "Explicit Weekly Composition" checkpoint: the
                        // athlete is never restricted to the
                        // `CandidateTrainingMix` preset catalog — "no
                        // planner prison."
                        Button("Build My Own Mix") { showingCompositionEditor = true }
                            .buttonStyle(.trainingOSSecondary)
                            .frame(maxWidth: .infinity)
                        if viewModel.isCustomMixSelected {
                            Button("Use TrainingOS's Recommendation Instead") {
                                viewModel.selectRecommended()
                            }
                            .font(Theme.label)
                            .foregroundStyle(Theme.textSecondary)
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
                        .buttonStyle(.trainingOSSecondary)
                        .frame(maxWidth: .infinity)
                    }

                    if viewModel.recommendedMixSummary != nil {
                        Button(viewModel.isAccepting ? "Starting…" : "Accept & Start Training") {
                            if viewModel.acceptAndStart(modelContext: modelContext) {
                                onComplete()
                            }
                        }
                        .buttonStyle(.trainingOSPrimary)
                        .frame(maxWidth: .infinity)
                        .disabled(viewModel.isAccepting || viewModel.didSucceed)
                    }
                }
                .padding(Theme.screenPadding)
            }
            .background(Theme.ground)
            // R6 Visual Correction Pass — FINAL TRUTHFULNESS GATE: removed
            // the redundant native centered "Your Plan" nav-title bar —
            // the real editorial "Your Plan" heading already renders
            // inside `header`, and this screen is presented as a root
            // state by `AppRootView` (a `switch` over `AppRootState`,
            // never pushed onto a stack), so there is no back
            // button/back-swipe behavior to preserve. Matches the same
            // `.toolbar(.hidden, for: .navigationBar)` treatment already
            // applied to every `OnboardingFlowView` step.
            .toolbar(.hidden, for: .navigationBar)
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

    /// R6 Visual Correction Pass: reproduces Screen 24's ("Program ·
    /// recommended," Design Pass 04) own "Recommended for this phase" →
    /// big headline → divider → "Why this one" hierarchy, all inside ONE
    /// card — the exact shape this pass's own brief asks for
    /// ("the recommendation must dominate"). `PlanPresentation
    /// .mixSummary` already gives the real current TrainingMix
    /// composition (e.g. "4× Hypertrophy + 1× Zone 2 Conditioning") —
    /// this never collapses it back to the old Program-only concept.
    private func recommendationCard(_ summary: String, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recommended For This Phase")
                .font(Theme.eyebrow)
                .tracking(1.2)
                .foregroundStyle(emphasized ? Theme.primary : Theme.textSecondary)
            Text(summary)
                .font(Theme.heading.weight(.heavy))
                .foregroundStyle(emphasized ? Theme.textPrimary : Theme.textSecondary)
            if emphasized {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WHY THIS ONE")
                        .font(Theme.eyebrow)
                        .tracking(1.2)
                        .foregroundStyle(Theme.primary)
                    Text(viewModel.recommendationExplanation ?? "Chosen for your goal, training availability, and preferences.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(.top, 6)
            }
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
                .font(Theme.heading.weight(.heavy))
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

    /// R6 Visual Correction Pass: Screen 24's "What it needs from you"
    /// card — replaces the two separate settings-style "Training
    /// Availability"/"Start Date" cards with ONE compact summary. The
    /// artifact's own example row (Exercises/Already known/To calibrate)
    /// isn't reproduced verbatim — `componentsAwaitingCalibrationCount`
    /// only becomes real AFTER acceptance (`acceptAndStart`), so showing
    /// it here pre-commit would be fabricated. Uses only fields already
    /// real and available at this point: `weeklyCapacity`, the real
    /// default environment (name low-emphasis when `isBuiltIn`, per R5
    /// zero-config), whether the reviewed mix's total sessions exceed
    /// capacity (so doubles are genuinely required to fit it), and the
    /// real R0-resolved start date.
    /// R6 First-Run Journey Design Completion: replaces the previous
    /// label/value table (Training days / Environment / Doubles / Start —
    /// exactly the "settings-style key/value" shape this round's brief
    /// flags) with ONE real sentence, matching the same "sentences, not
    /// fields" treatment Review already uses for its own Training
    /// Availability card. "Doubles: Not required" is gone entirely — it
    /// told the athlete about scheduling mechanics that don't change
    /// their decision (`reviewedMixRequiresDoubles` itself is untouched,
    /// still real, just no longer surfaced here). A default, un-
    /// customized Full Gym environment is omitted completely (R5 zero-
    /// config — it changed nothing the athlete decided, same precedent
    /// Review already sets); a genuine custom/restricted environment
    /// still appears, as a real requirement. The truthful, not-yet-
    /// accepted start-date disclosure is UNCHANGED — still real, still
    /// subordinate (a quiet line below the summary sentence, never
    /// competing with the recommendation above it).
    @ViewBuilder private var whatItNeedsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "What It Needs")
            Text(whatItNeedsSummary)
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            if !viewModel.hasCompressedObjectivePrep, let startDate = viewModel.resolvedStartDate, !Calendar.current.isDateInToday(startDate) {
                Text("Your first real training week begins then.")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainingOSCard()
    }

    private var whatItNeedsSummary: String {
        let days = viewModel.weeklyCapacity
        let dayWord = days == 1 ? "day" : "days"
        let environmentClause = viewModel.goal?.user?.profile?.defaultTrainingEnvironment
            .flatMap { $0.isBuiltIn ? nil : ", using your \($0.name)" } ?? ""
        guard let startDate = viewModel.resolvedStartDate else {
            return "\(days) training \(dayWord) a week\(environmentClause)."
        }
        let isToday = Calendar.current.isDateInToday(startDate)
        let startPhrase = isToday ? "starting today" : "starting \(startDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))"
        return "\(days) training \(dayWord) a week\(environmentClause), \(startPhrase)."
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
