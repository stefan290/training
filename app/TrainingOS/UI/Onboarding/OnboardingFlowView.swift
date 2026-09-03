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
                case .modalityPreferences: modalityPreferencesStep
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
                    ForEach(GoalType.allCases, id: \.self) { type in
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
                    Text(PlanPresentation.goalTypeLabel(type))
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
    private var workingTowardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Anything you're working toward?")
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)

            if viewModel.hasMilestone, !isAddingWorkingToward {
                workingTowardRow
            }

            if isAddingWorkingToward {
                addWorkingTowardPanel
            } else if !viewModel.hasMilestone {
                Button {
                    viewModel.milestoneDate = Date().addingTimeInterval(90 * 86400)
                    isAddingWorkingToward = true
                } label: {
                    Label("Add a goal or event", systemImage: "plus.circle")
                        .font(Theme.body)
                }
            }

            if viewModel.hasRunningEvent, !isAddingRunningEvent {
                runningEventRow
            }

            if isAddingRunningEvent {
                addRunningEventPanel
            } else if !viewModel.hasRunningEvent {
                Button {
                    viewModel.runningEventDate = Date().addingTimeInterval(120 * 86400)
                    isAddingRunningEvent = true
                } label: {
                    Label("Add another goal or event", systemImage: "plus.circle")
                        .font(Theme.body)
                }
            }
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
            Picker("Where are you starting from?", selection: $viewModel.runningStartingState) {
                Text("Not currently running").tag(RunningStartingState.notCurrentlyRunning)
                Text("I run occasionally / shorter distances").tag(RunningStartingState.occasionalShorterDistances)
                Text("I can comfortably run 10K").tag(RunningStartingState.comfortably10K)
            }
            .pickerStyle(.inline)
            .labelsHidden()
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

    private var preferencesStep: some View {
        Form {
            Section("Weekly training") {
                Stepper("Training days per week: \(viewModel.availableTrainingDaysPerWeek)", value: $viewModel.availableTrainingDaysPerWeek, in: 1...7)
                Toggle("I'm open to two sessions in one day", isOn: $viewModel.allowsDoubleSessions)
            }
            Section("Variety") {
                Picker("How much variety do you want?", selection: $viewModel.varietyPreference) {
                    Text("Low — keep it consistent").tag(VarietyPreference.low)
                    Text("Moderate").tag(VarietyPreference.moderate)
                    Text("High — keep it fresh").tag(VarietyPreference.high)
                }
                .pickerStyle(.inline)
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

    /// Stage V1 dogfooding fix (Part 3): `preferredModalities`/
    /// `dislikedModalities` are real, already-planner-consumed fields
    /// (`LongTermPlanner.isPreferenceAligned`) — this is only the
    /// previously-deferred onboarding surface for them, using the real
    /// `ProgrammingSystemKind` vocabulary and existing `PlanPresentation`
    /// labels, never internal enum names.
    private var modalityPreferencesStep: some View {
        Form {
            Section {
                Text("Optional — TrainingOS already recommends training for your goal. Tell it more if you have strong preferences.")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
            Section("I especially want") {
                ForEach(ProgrammingSystemKind.allCases, id: \.self) { system in
                    Toggle(PlanPresentation.programmingSystemLabel(system), isOn: preferredBinding(system))
                }
            }
            Section("I'd rather avoid") {
                ForEach(ProgrammingSystemKind.allCases, id: \.self) { system in
                    Toggle(PlanPresentation.programmingSystemLabel(system), isOn: dislikedBinding(system))
                }
                if viewModel.dislikedSystems.contains(.steadyState) {
                    Toggle("Just running — other conditioning is fine", isOn: $viewModel.dislikesRunningSpecifically)
                }
            }
            Section {
                Button("Continue") { viewModel.advance(from: .modalityPreferences, modelContext: modelContext) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Training Preferences")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func preferredBinding(_ system: ProgrammingSystemKind) -> Binding<Bool> {
        Binding(
            get: { viewModel.preferredSystems.contains(system) },
            set: { isOn in
                if isOn { viewModel.preferredSystems.insert(system) } else { viewModel.preferredSystems.remove(system) }
            }
        )
    }

    private func dislikedBinding(_ system: ProgrammingSystemKind) -> Binding<Bool> {
        Binding(
            get: { viewModel.dislikedSystems.contains(system) },
            set: { isOn in
                if isOn { viewModel.dislikedSystems.insert(system) } else { viewModel.dislikedSystems.remove(system) }
            }
        )
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

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Review")
                .font(Theme.heading)
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 12) {
                reviewRow("Main Goal", PlanPresentation.goalTypeLabel(viewModel.selectedGoalType))
                if viewModel.hasMilestone {
                    reviewRow("Working Toward", "Summer Shape — \(viewModel.milestoneDate.formatted(date: .abbreviated, time: .omitted))")
                }
                if viewModel.hasRunningEvent {
                    reviewRow("Working Toward", "10K Race — \(viewModel.runningEventDate.formatted(date: .abbreviated, time: .omitted))")
                }
                reviewRow("Training days/week", "\(viewModel.availableTrainingDaysPerWeek)")
                reviewRow("Variety", viewModel.varietyPreference.rawValue.capitalized)
                if !viewModel.preferredSystems.isEmpty {
                    reviewRow("Especially want", viewModel.preferredSystems.map(PlanPresentation.programmingSystemLabel).sorted().joined(separator: ", "))
                }
                if !viewModel.dislikedSystems.isEmpty {
                    reviewRow("Rather avoid", viewModel.dislikedSystems.map(PlanPresentation.programmingSystemLabel).sorted().joined(separator: ", "))
                }
                reviewRow("Training Environment", viewModel.user?.profile?.defaultTrainingEnvironment?.name ?? "Not set")
            }
            .padding(14)
            .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))

            Spacer()

            Button("Start Training with TrainingOS") { onComplete() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Theme.label).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(Theme.body).foregroundStyle(Theme.textPrimary)
        }
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    return OnboardingFlowView(onComplete: {})
        .modelContainer(container)
}
