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
            .toolbar {
                if viewModel.step != .goal {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { viewModel.goBack(from: viewModel.step) }
                    }
                }
            }
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

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("What's your main training goal?")
                .font(Theme.heading)
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 24)

            ScrollView {
                VStack(spacing: 12) {
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

            // Stage V1 "Milestone Onboarding UX correction": the former
            // generic "Plan through a specific end date" control is removed
            // from normal onboarding entirely — it exposed an internal
            // planning-horizon concept (`Goal.targetDate`) athletes don't
            // need to understand. `Goal.targetDate` itself is NOT removed
            // from the domain and `LongTermPlanner` is untouched: for a
            // brand-new athlete `hasTargetDate` simply stays `false` (its
            // declared default) since no UI here ever sets it, so
            // `createOrUpdateGoal` continues writing `targetDate: nil` —
            // the same real, valid, already-tested "open-ended plan" state
            // this app has always supported. An athlete with a PRE-EXISTING
            // `targetDate` (set via the old UI before this correction) has
            // it re-seeded into `hasTargetDate`/`targetDate` by `start()`
            // unchanged — removing this control never silently clears that
            // athlete's real persisted value, it simply stops offering a
            // way to set a NEW one from this screen.
            workingTowardSection

            Button("Continue") { viewModel.advance(from: .goal, modelContext: modelContext) }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .navigationTitle("Your Goal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func goalOptionRow(_ type: GoalType) -> some View {
        Button {
            viewModel.selectedGoalType = type
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(PlanPresentation.mainGoalLabel(type))
                        .font(Theme.body)
                        .foregroundStyle(Theme.textPrimary)
                    Text(goalTypeDescription(type))
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: viewModel.selectedGoalType == type ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(viewModel.selectedGoalType == type ? Theme.primary : Theme.textSecondary)
            }
            .padding(14)
            .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
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
            Button("Remove", role: .destructive) { viewModel.hasRunningEvent = false }
                .font(Theme.label)
        }
        .padding(14)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
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
                Spacer()
                Button(viewModel.hasRunningEvent ? "Save" : "Add to my plan") {
                    viewModel.hasRunningEvent = true
                    isAddingRunningEvent = false
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
                .disabled(!viewModel.isRunningEventDateValid)
            }
        }
        .padding(14)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
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
            Button("Remove", role: .destructive) { viewModel.hasMilestone = false }
                .font(Theme.label)
        }
        .padding(14)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
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
                Spacer()
                Button(viewModel.hasMilestone ? "Save" : "Add to my plan") {
                    viewModel.hasMilestone = true
                    isAddingWorkingToward = false
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
                .disabled(!viewModel.isMilestoneDateValid)
            }
        }
        .padding(14)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
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
    private var preferencesStep: some View {
        Form {
            Section("Weekly training") {
                Stepper("Training days per week: \(viewModel.availableTrainingDaysPerWeek)", value: $viewModel.availableTrainingDaysPerWeek, in: 1...7)
                Toggle("I'm open to two sessions in one day", isOn: $viewModel.allowsDoubleSessions)
            }
            Section {
                Button("Continue") { viewModel.advance(from: .preferences, modelContext: modelContext) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Training Preferences")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var environmentStep: some View {
        VStack(spacing: 0) {
            Text("Set up where you'll train — this controls what TrainingOS can prescribe you.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .padding()
            TrainingEnvironmentSettingsView()
            Button("Continue") { viewModel.advance(from: .environment, modelContext: modelContext) }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
                .disabled(!viewModel.hasDefaultTrainingEnvironment)
                .padding()
        }
        .navigationTitle("Training Environment")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// V1 "Explicit Weekly Composition" checkpoint: TRAINING STYLES
    /// (Especially want/Rather avoid) and Variety are REMOVED from Review
    /// — neither is collected by this primary flow anymore. The athlete's
    /// actual WEEKLY TRAINING composition is chosen next, on the Plan
    /// screen (where a real `TrainingPhase` exists to build a real
    /// `TrainingMix` against — see `StrategicPlanSelectionView`'s "Build
    /// My Own Mix"), so this Review intentionally shows only what IS
    /// already decided at this point: MAIN GOAL, weekly TRAINING capacity,
    /// WORKING TOWARD (when present), and TRAINING ENVIRONMENT — never a
    /// fabricated composition summary for a choice not made yet.
    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Review")
                .font(Theme.heading)
                .foregroundStyle(Theme.textPrimary)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    reviewSection("MAIN GOAL") {
                        reviewRow("Goal", PlanPresentation.mainGoalLabel(viewModel.selectedGoalType))
                    }

                    reviewSection("TRAINING") {
                        reviewRow("Days/week", "\(viewModel.availableTrainingDaysPerWeek)")
                    }

                    if viewModel.hasMilestone || viewModel.hasRunningEvent {
                        reviewSection("WORKING TOWARD") {
                            if viewModel.hasMilestone {
                                reviewRow("Summer Shape", viewModel.milestoneDate.formatted(date: .abbreviated, time: .omitted))
                            }
                            if viewModel.hasRunningEvent {
                                reviewRow("10K Race", viewModel.runningEventDate.formatted(date: .abbreviated, time: .omitted))
                            }
                        }
                    }

                    reviewSection("TRAINING ENVIRONMENT") {
                        reviewRow("Environment", viewModel.user?.profile?.defaultTrainingEnvironment?.name ?? "Not set")
                    }
                }
            }

            Button("Start Training with TrainingOS") { onComplete() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func reviewSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.label)
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    /// V1 "Goal ≠ Training Method" checkpoint UX fix (real-device
    /// truncation bug): `.fixedSize(horizontal: false, vertical: true)`
    /// forces the value to wrap onto additional lines instead of being
    /// compressed/truncated when it's long (e.g. several joined Training
    /// Style names) — the standard SwiftUI fix for a trailing `Text` in an
    /// `HStack` that would otherwise clip.
    private func reviewRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(Theme.label)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Text(value)
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    return OnboardingFlowView(onComplete: {})
        .modelContainer(container)
}
