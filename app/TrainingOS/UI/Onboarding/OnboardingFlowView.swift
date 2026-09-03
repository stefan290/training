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

            Toggle("I have a target date", isOn: $viewModel.hasTargetDate)
                .font(Theme.body)
            if viewModel.hasTargetDate {
                DatePicker("Target date", selection: $viewModel.targetDate, displayedComponents: .date)
                    .font(Theme.body)
            }

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
                reviewRow("Goal", PlanPresentation.goalTypeLabel(viewModel.selectedGoalType))
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
