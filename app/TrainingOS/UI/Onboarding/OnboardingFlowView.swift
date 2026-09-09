import SwiftUI
import SwiftData

/// Stage V1.Checkpoint 1: the athlete's first-run flow, replacing the
/// former automatic demo seed. Never shows internal terms (ProgramInstance,
/// generator config, tactical materialization) — only Goal/preferences/
/// Training Environment, the same concepts `AppRootStateResolver` uses to
/// decide this athlete is ready for Checkpoint 2 (plan recommendation).
struct OnboardingFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = OnboardingViewModel()
    /// Stage V1 "Milestone Onboarding UX correction": transient, View-local
    /// navigation state for the "working toward" add/edit panel — never
    /// persisted, never read by any other screen. Deliberately NOT on
    /// `OnboardingViewModel`: this is purely "is the add/edit sub-panel
    /// open," not athlete data.
    @State private var isAddingWorkingToward = false
    /// Dated Objectives + 10K Strategic Reconciliation V1: the second
    /// real "working toward" item's own add/edit panel state — kept
    /// separate from `isAddingWorkingToward` (Summer Shape's) so the two
    /// items can be added/edited independently, exactly like two entries
    /// in the same list.
    @State private var isAddingRunningEvent = false
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.step {
                case .goal: goalStep
                case .preferences: preferencesStep
                case .environment: environmentStep
                case .review: reviewStep
                }
            }
            .background(Theme.ground)
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { viewModel.start(modelContext: modelContext) }
        // Stage V1 dogfooding fix: `TrainingEnvironmentSettingsView` is a
        // sibling view with its own independently-fetched `profile`
        // reference — mutating `defaultTrainingEnvironment` there does not
        // reliably re-render this view on its own. Explicitly refresh the
        // directly-observed `hasDefaultTrainingEnvironment` flag instead.
        .onReceive(NotificationCenter.default.publisher(for: .trainingEnvironmentDefaultChanged)) { _ in
            viewModel.refreshEnvironmentState(modelContext: modelContext)
        }
    }

    /// Design Fidelity Correction 01: reproduces Screen 17 ("Goal — Step 1
    /// of 4") from `project/Training OS.dc.html` directly — no centered
    /// `.navigationTitle`, a segmented step tracker below the status area,
    /// then progress → title → supporting copy → compact rows → CTA, all
    /// in the artifact's own scrollable content region. Domain/binding
    /// contract is unchanged: still `PlanPresentation.mainGoalOptions`/
    /// `viewModel.selectedGoalType`/`viewModel.advance(from: .goal,...)`.
    /// The Dated Objective interaction (Summer Shape/10K Race) that used
    /// to render inline here has moved to the END of `preferencesStep`
    /// (Availability) — off the primary goal-selection screen per this
    /// checkpoint's explicit instruction, without adding a new
    /// `OnboardingViewModel.Step` case (which would change the progress
    /// indicator from the artifact's stated 4 segments to 5). See
    /// `workingTowardSection`'s own doc comment for the full reasoning.
    ///
    /// R6 Visual Correction Pass: now shares `topChrome` with every other
    /// step (previously Goal alone rendered its own inline progress
    /// indicator, while Availability/Environment/Review kept a native
    /// `.navigationTitle` bar and a generic toolbar "Back" button — the
    /// exact "doesn't feel like one journey" gap this pass corrects).
    private var goalStep: some View {
        VStack(spacing: 0) {
            topChrome

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("What are you training for?")
                        .font(Theme.headingXL)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.bottom, 8)

                    Text("One primary goal. It decides which quality gets scheduling priority all year.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.bottom, 22)

                    VStack(spacing: 9) {
                        // V1 "Goal ≠ Training Method" checkpoint: Main Goal is
                        // the OUTCOME the athlete wants — `PlanPresentation
                        // .mainGoalOptions` deliberately excludes
                        // `.functionalFitness` (a Training Style, chosen on its
                        // own step below) and `.enduranceEvent` is relabeled
                        // "Improve Fitness & Endurance" here, never "Endurance
                        // Event" (that phrase still names the internal
                        // `PhaseType`/`GoalType`, just not what the athlete
                        // reads on this screen).
                        ForEach(PlanPresentation.mainGoalOptions, id: \.self) { type in
                            goalOptionRow(type)
                        }
                    }
                }
                .padding(.horizontal, 22)
            }

            Button("Continue") { viewModel.advance(from: .goal, modelContext: modelContext) }
                .buttonStyle(.trainingOSPrimary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
                .padding(.bottom, 26)
        }
        .background(Theme.ground)
    }

    /// R6 Visual Correction Pass: the chrome every onboarding step now
    /// shares — the segmented progress indicator (never a native
    /// `.navigationTitle`), plus a small back chevron once there's
    /// somewhere real to go back to (never shown on Goal, the first
    /// step). Replaces the previous per-step
    /// `.navigationTitle`/`.navigationBarTitleDisplayMode(.inline)` calls
    /// and the generic toolbar "Back" button — the exact "large native-
    /// looking Back pill... no visual continuity with Goal progress" gap
    /// this pass corrects. `viewModel.step.rawValue` against
    /// `OnboardingViewModel.Step.allCases.count` (4) matches the
    /// artifact's own "Step N of 4" labeling exactly, with zero new
    /// `Step` case.
    private var topChrome: some View {
        HStack(spacing: 14) {
            if viewModel.step != .goal {
                Button {
                    viewModel.goBack(from: viewModel.step)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }
            OnboardingProgressIndicator(currentStepIndex: viewModel.step.rawValue, totalSteps: OnboardingViewModel.Step.allCases.count)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 18)
    }

    /// Screen 17's compact dark selection row — no radio circle on the
    /// unselected state; the artifact marks selection purely through
    /// background/border/weight, with a trailing checkmark appearing
    /// only once something IS selected.
    private func goalOptionRow(_ type: GoalType) -> some View {
        let isSelected = viewModel.selectedGoalType == type
        return Button {
            viewModel.selectedGoalType = type
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(PlanPresentation.mainGoalLabel(type))
                        .font(Theme.body.weight(isSelected ? .bold : .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(goalTypeDescription(type))
                        .font(.system(size: 12.5, weight: .light, design: .default))
                        .foregroundStyle(isSelected ? Theme.textMuted : Theme.textSecondary)
                }
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 17)
            .background(isSelected ? Theme.primary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 13))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(isSelected ? Theme.primary : Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Stage V1 "Milestone Onboarding UX correction": the athlete-facing
    /// "MAIN GOAL + THINGS I AM WORKING TOWARD" mental model. Structured so
    /// a FUTURE second addable type (e.g. a dated Event) would slot in as
    /// another row inside the same add-panel/list shape — never
    /// implemented here, this checkpoint only ever adds the single real
    /// "Get leaner / Summer shape" option, which maps to the EXISTING
    /// `Goal.milestoneDate`/`.bodyCompositionDirection = .loseFat` fields,
    /// never a new persisted model.
    /// V1 "Goal ≠ Training Method" checkpoint UX fix: two real, reported
    /// bugs, both rooted in the same cause — the two objective types'
    /// "add" affordances and edit panels were each gated independently,
    /// with no shared "is something already being edited" state. Fixed by
    /// (1) a single add affordance (`addObjectiveMenu`) whose LABEL alone
    /// depends on whether any objective already exists (never two buttons
    /// visible at once), and (2) gating every row/panel on `isEditingAnyObjective`
    /// so only one editor can ever be open — tapping "Edit" on one
    /// objective is impossible while the other's panel is open (its row,
    /// including its own Edit button, is simply not shown until the
    /// in-progress edit finishes).
    private var isEditingAnyObjective: Bool { isAddingWorkingToward || isAddingRunningEvent }

    /// Design Fidelity Correction 01: relocated from the Goal screen
    /// (`goalStep`) to render at the end of `preferencesStep`
    /// (Availability) instead — Screen 17 in the approved artifact does
    /// not place this interaction inside the primary goal-selection
    /// composition, and this checkpoint's own explicit instruction was to
    /// move it off that screen without deleting the feature. This is a
    /// pure View-composition/call-site move: zero change to
    /// `OnboardingViewModel.Step` (still 4 cases, matching the artifact's
    /// own "Step 1 of 4" progress indicator, so no new step was added
    /// purely to give this its own dedicated screen), zero change to any
    /// binding/validation logic below, zero change to `Goal
    /// .datedObjectives` domain semantics.
    private var workingTowardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Anything you're working toward?")
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)

            if viewModel.hasMilestone, !isEditingAnyObjective {
                workingTowardRow
            }
            if isAddingWorkingToward {
                addWorkingTowardPanel
            }

            if viewModel.hasRunningEvent, !isEditingAnyObjective {
                runningEventRow
            }
            if isAddingRunningEvent {
                addRunningEventPanel
            }

            if !isEditingAnyObjective, !viewModel.hasMilestone || !viewModel.hasRunningEvent {
                addObjectiveMenu
            }
        }
    }

    /// A single add affordance for both dated-objective types — never two
    /// simultaneous "Add a goal/event" buttons. The label alone reflects
    /// whether an objective already exists; which concrete type gets added
    /// is chosen from the menu (only the not-yet-added type(s) appear).
    private var addObjectiveMenu: some View {
        let label = (viewModel.hasMilestone || viewModel.hasRunningEvent) ? "Add another goal or event" : "Add a goal or event"
        return Menu {
            if !viewModel.hasMilestone {
                Button("Get leaner / Summer shape") {
                    viewModel.milestoneDate = Date().addingTimeInterval(90 * 86400)
                    isAddingWorkingToward = true
                }
            }
            if !viewModel.hasRunningEvent {
                Button("10K Race") {
                    viewModel.runningEventDate = Date().addingTimeInterval(120 * 86400)
                    isAddingRunningEvent = true
                }
            }
        } label: {
            Label(label, systemImage: "plus.circle")
                .font(Theme.body)
                .foregroundStyle(Theme.primary)
        }
    }

    /// Dated Objectives + 10K Strategic Reconciliation V1's second real
    /// "working toward" item — mirrors `workingTowardRow` exactly.
    private var runningEventRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("10K Race")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                Text(viewModel.runningEventDate.formatted(date: .abbreviated, time: .omitted))
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button("Edit") { isAddingRunningEvent = true }
                .font(Theme.label)
                .foregroundStyle(Theme.primary)
            Button("Remove", role: .destructive) { viewModel.hasRunningEvent = false }
                .font(Theme.label)
        }
        .trainingOSCard()
    }

    /// Mirrors `addWorkingTowardPanel` exactly, plus the locked 3-option
    /// running-state question — never exposes "lead-time weeks,"
    /// `DatedObjective`, or any other internal vocabulary.
    private var addRunningEventPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("10K Race")
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            Text("Train toward a 10K on a specific date, alongside your main goal.")
                .font(Theme.label)
                .foregroundStyle(Theme.textSecondary)
            DatePicker("Race day", selection: $viewModel.runningEventDate, in: Date()..., displayedComponents: .date)
                .font(Theme.body)
            Text("Where are you starting from?")
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 4)
            // V1 "Goal ≠ Training Method" checkpoint UX fix (real-device
            // bug): `.pickerStyle(.inline)` renders reliably inside a
            // `List`/`Form` — this panel is a plain `VStack`, where an
            // inline `Picker` is not guaranteed to render its options as
            // visible, selectable rows at all. Replaced with the same
            // explicit tappable-row pattern `goalOptionRow` already uses
            // elsewhere in this same flow, which has no such dependency.
            runningStartingStateOptions
            HStack {
                Button("Cancel") { isAddingRunningEvent = false }
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button(viewModel.hasRunningEvent ? "Save" : "Add to my plan") {
                    viewModel.hasRunningEvent = true
                    isAddingRunningEvent = false
                }
                .buttonStyle(.trainingOSPrimary)
                .disabled(!viewModel.isRunningEventDateValid)
            }
        }
        .trainingOSCard()
    }

    /// Explicit, always-visible/tappable rows for `RunningStartingState` —
    /// see the UX-fix note at its call site in `addRunningEventPanel`.
    private var runningStartingStateOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(RunningStartingState.allCases, id: \.self) { state in
                Button {
                    viewModel.runningStartingState = state
                } label: {
                    HStack {
                        Text(runningStartingStateLabel(state))
                            .font(Theme.body)
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Image(systemName: viewModel.runningStartingState == state ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(viewModel.runningStartingState == state ? Theme.primary : Theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func runningStartingStateLabel(_ state: RunningStartingState) -> String {
        switch state {
        case .notCurrentlyRunning: "Not currently running"
        case .occasionalShorterDistances: "I run occasionally / shorter distances"
        case .comfortably10K: "I can comfortably run 10K"
        }
    }

    /// Shows the athlete's own already-chosen intent directly — never an
    /// abstract enabled/disabled toggle — so at a glance they see "my main
    /// goal is X, and I also want Summer Shape by June 15."
    private var workingTowardRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Summer Shape")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                Text(viewModel.milestoneDate.formatted(date: .abbreviated, time: .omitted))
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button("Edit") { isAddingWorkingToward = true }
                .font(Theme.label)
                .foregroundStyle(Theme.primary)
            Button("Remove", role: .destructive) { viewModel.hasMilestone = false }
                .font(Theme.label)
        }
        .trainingOSCard()
    }

    /// The only real supported "working toward" item this checkpoint
    /// exposes. `viewModel.milestoneDate` is bound directly (no separate
    /// draft state) so `isMilestoneDateValid` — the same predicate a
    /// production-path test exercises — gates the confirm action; cancelling
    /// never commits `hasMilestone`, so an in-progress edit can't corrupt an
    /// already-added milestone.
    private var addWorkingTowardPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Get leaner / Summer shape")
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            Text("Look leaner by a specific date while protecting the progress you've made.")
                .font(Theme.label)
                .foregroundStyle(Theme.textSecondary)
            DatePicker("Ready by", selection: $viewModel.milestoneDate, in: Date()..., displayedComponents: .date)
                .font(Theme.body)
            HStack {
                Button("Cancel") { isAddingWorkingToward = false }
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button(viewModel.hasMilestone ? "Save" : "Add to my plan") {
                    viewModel.hasMilestone = true
                    isAddingWorkingToward = false
                }
                .buttonStyle(.trainingOSPrimary)
                .disabled(!viewModel.isMilestoneDateValid)
            }
        }
        .trainingOSCard()
    }

    private func goalTypeDescription(_ type: GoalType) -> String {
        switch type {
        case .muscleGain: "Build muscle with a structured resistance program."
        case .fatLoss: "Lose fat while protecting the muscle you have."
        case .generalStrength: "Get stronger on the fundamental lifts."
        case .enduranceEvent: "Train toward a running or endurance goal."
        case .functionalFitness: "Varied, conditioning-focused training."
        case .maintenance: "Maintain your current fitness with less structure."
        }
    }

    /// V1 "Explicit Weekly Composition" checkpoint: the former "Variety"
    /// picker is REMOVED — explicit weekly composition (chosen on the
    /// Plan screen's "Build My Own Mix") supersedes it as the one
    /// athlete-facing authority for desired training composition.
    /// `VarietyPreference` itself is not deleted (still read by
    /// `rankCandidateMixes`'s preset-ranking path), simply no longer
    /// athlete-editable from this primary flow.
    /// R6 Visual Correction Pass: rebuilt against Screen 23 ("Availability
    /// · revised — Days and opportunities," Design Pass 04, the file's
    /// own explicitly-labeled FINAL pass — supersedes the earlier Screen
    /// 18 this step was previously modeled on) — "AVAILABILITY = TRAINING
    /// DAYS, NOT SESSIONS" is that pass's own stated thesis, word for
    /// word. Same `$viewModel.availableTrainingDaysPerWeek`/
    /// `$viewModel.allowsDoubleSessions` bindings as before.
    ///
    /// R6 Final User-Visual Correction: the artifact's own literal
    /// supporting-copy sentence ("Describe the opportunities. The
    /// planner decides how many sessions fit inside them.") read as
    /// internal planner terminology to an athlete — replaced with a
    /// plainer athlete-facing sentence conveying the same real thesis,
    /// per explicit product feedback. Same underlying meaning, no new
    /// promise about fields this screen doesn't collect.
    ///
    /// R6 Visual Correction Pass — FINAL TRUTHFULNESS GATE: a "Time
    /// available per training day" duration control (backed by the real,
    /// pre-existing `GoalPreferences.typicalSessionDurationMinutes`) was
    /// added to this screen in the prior round of this same pass, then
    /// REMOVED here after independent verification confirmed zero
    /// scheduling/planning engine reads that field (confirmed fresh by
    /// direct search of `TrainingOS/Engines/`/`TrainingOS/Application/
    /// UseCases/` — no hits outside this ViewModel/View pair and the
    /// domain declaration itself). Presenting it on this planning-
    /// critical screen, next to "Training days per week" (which DOES
    /// drive real scheduling), would have implied session length shapes
    /// the plan today — it doesn't. The field itself, its ViewModel
    /// property, and its persistence round-trip are UNTOUCHED (not
    /// deleted); this is a presentation-only removal.
    ///
    /// DESIGN CAPABILITY GAP (follow-up, not fixed here): the approved
    /// design expects time-per-day to matter to planning; the current
    /// planner does not yet consume it. Re-introduce the control once a
    /// real planner/scheduler consumer exists — never before.
    ///
    /// Two further Screen-23 fields remain DELIBERATELY NOT implemented —
    /// reported per this checkpoint's own STOP conditions rather than
    /// faked:
    /// - "Preferred days": the artifact shows one grid of 7 weekdays at
    ///   Availability time, but the current domain has no such athlete-
    ///   level field — `preferredDays` exists only on
    ///   `TrainingMixComponent` (`TrainingMixComponent.swift`), set PER
    ///   COMPONENT once a real `TrainingMix` exists (i.e. after
    ///   recommendation, an architecturally later moment), never as a
    ///   single top-level preference collectible here.
    /// - "Occasional longer session": zero real persisted concept
    ///   anywhere in the domain (confirmed by direct search across
    ///   `TrainingOS/Domain/`/`Application/`) — nothing to expose.
    private var preferencesStep: some View {
        VStack(spacing: 0) {
            topChrome

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("When can you train?")
                            .font(Theme.headingXL)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Tell us how many days you can train. TrainingOS will build your week around them.")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 13) {
                        HStack {
                            SectionHeader(title: "Training days per week")
                            Spacer()
                            Text("\(viewModel.availableTrainingDaysPerWeek)")
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.primary)
                        }
                        TrainingOSCapacityBar(value: viewModel.availableTrainingDaysPerWeek, range: 1...7) { newValue in
                            viewModel.availableTrainingDaysPerWeek = newValue
                        }
                    }
                    .trainingOSCard()

                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Two sessions in a day")
                                .font(Theme.body)
                                .foregroundStyle(Theme.textPrimary)
                            Text("Lets more sessions fit into fewer days")
                                .font(Theme.label)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $viewModel.allowsDoubleSessions)
                            .labelsHidden()
                            .tint(Theme.primary)
                    }
                    .trainingOSCard()

                    Button("Continue") { viewModel.advance(from: .preferences, modelContext: modelContext) }
                        .buttonStyle(.trainingOSPrimary)
                        .frame(maxWidth: .infinity)
                }
                .padding(Theme.screenPadding)
            }
        }
        .background(Theme.ground)
    }

    private var environmentStep: some View {
        VStack(spacing: 0) {
            topChrome

            Text("Set up where you'll train — this controls what TrainingOS can prescribe you.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 12)
            TrainingEnvironmentSettingsView()
            Button("Continue") { viewModel.advance(from: .environment, modelContext: modelContext) }
                .buttonStyle(.trainingOSPrimary)
                .frame(maxWidth: .infinity)
                .disabled(!viewModel.hasDefaultTrainingEnvironment)
                .padding()
        }
        .background(Theme.ground)
    }

    /// R6 Visual Correction Pass: RECOMPOSED, not restyled — the previous
    /// hierarchy (MAIN GOAL/TRAINING/WORKING TOWARD/TRAINING ENVIRONMENT,
    /// each a label-over-field-value settings row) read as an account
    /// summary. The artifact itself has no dedicated "Review" screen —
    /// Path A's own 5-step list (Screen 22, Design Pass 04) goes straight
    /// from Availability to the proposed route/recommendation — so this
    /// screen is composed from the SAME established visual grammar
    /// (the goal screen's own selected-row treatment for the primary
    /// outcome; Screen 23/24's plain card-with-sentence shape for
    /// everything else) rather than copying a literal artifact surface
    /// that doesn't exist. Purpose stated in-screen, per this pass's own
    /// brief: "Here's what TrainingOS understood," not a field grid.
    ///
    /// TRAINING STYLES (Especially want/Rather avoid) and Variety remain
    /// excluded — unchanged reasoning from the prior checkpoint (explicit
    /// Weekly Composition, chosen later, is the one authority for
    /// composition). WORKING TOWARD's editable interaction
    /// (`workingTowardSection`) has moved here from Availability — see
    /// its own doc comment for why; this is where the current 4-step
    /// `OnboardingViewModel.Step` model already places the "everything
    /// I've told you" checkpoint, and no new Step/domain model was added
    /// to give it a separate screen.
    private var reviewStep: some View {
        VStack(spacing: 0) {
            topChrome

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Here's what we understood")
                            .font(Theme.headingXL)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Before TrainingOS proposes how you should train, confirm these are right.")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    // Primary outcome — the one decision everything else
                    // is subordinate to, given the same emphasized
                    // treatment the Goal screen itself gives a selection.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PRIMARY OUTCOME")
                            .font(Theme.eyebrow)
                            .tracking(1.2)
                            .foregroundStyle(Theme.primary)
                        Text(PlanPresentation.mainGoalLabel(viewModel.selectedGoalType))
                            .font(Theme.heading.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .trainingOSCard(emphasized: true)

                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Training availability")
                        Text(availabilitySummary)
                            .font(Theme.body)
                            .foregroundStyle(Theme.textPrimary)
                        if viewModel.allowsDoubleSessions {
                            Text("Open to two sessions in one day.")
                                .font(Theme.label)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .trainingOSCard()

                    // WORKING TOWARD's real add/edit interaction, relocated
                    // here from Availability (see its own doc comment).
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Dated objectives")
                        workingTowardSection
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .trainingOSCard()

                    // R5 Full Gym zero-config: a default, un-customized
                    // environment changed nothing the athlete decided, so
                    // it is OMITTED from the Review summary entirely
                    // (R6 Final User-Visual Correction — a muted
                    // "Training in: Full Gym" line read as implementation/
                    // debug text and broke the "real decisions only"
                    // hierarchy every other row here follows). A real
                    // custom/restricted environment IS a real decision —
                    // it can gate what the recommendation can prescribe —
                    // so it keeps the same card treatment as everything
                    // else here.
                    if let environment = viewModel.user?.profile?.defaultTrainingEnvironment, !environment.isBuiltIn {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionHeader(title: "Training environment")
                            Text(environment.name)
                                .font(Theme.body)
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .trainingOSCard()
                    }

                    Button("See My Recommended Plan") { onComplete() }
                        .buttonStyle(.trainingOSPrimary)
                        .frame(maxWidth: .infinity)
                }
                .padding(Theme.screenPadding)
            }
        }
        .background(Theme.ground)
    }

    /// One real sentence from `availableTrainingDaysPerWeek`/
    /// `typicalSessionDurationMinutes` — replaces the previous bare
    /// "Days/week: 5" settings row. Omits the duration clause entirely
    /// when unset (`nil` is a real, valid state — never defaulted to a
    /// fabricated number here).
    private var availabilitySummary: String {
        let days = viewModel.availableTrainingDaysPerWeek
        let dayWord = days == 1 ? "day" : "days"
        guard let minutes = viewModel.typicalSessionDurationMinutes else {
            return "\(days) \(dayWord) a week"
        }
        return "\(days) \(dayWord) a week, about \(minutes) minutes each"
    }

}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    return OnboardingFlowView(onComplete: {})
        .modelContainer(container)
}
