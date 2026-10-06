import SwiftUI
import SwiftData

/// Dogfood Round 2 (Finding 1): the narrow, athlete-facing surface for
/// reviewing and changing training decisions made during onboarding —
/// reached from the same Profile entry point as
/// `TrainingEnvironmentSettingsView`, never a new Settings redesign.
/// Editing days/week or double sessions previews the real consequence for
/// the active mix (`TrainingPreferencesViewModel.previewConsequence`)
/// before it's saved; every other field just saves directly, since it
/// carries no scheduling-feasibility consequence of its own.
struct TrainingPreferencesSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = TrainingPreferencesViewModel()
    @State private var pendingConsequence: TrainingPreferencesConsequence?

    private static let durationOptions = [45, 60, 75, 90]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let currentMixSummary = viewModel.currentMixSummary {
                    currentMixCard(currentMixSummary)
                }

                weekdaySection

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

                durationSection
                varietySection
                trainingStyleSection(title: "Especially enjoy", selection: $viewModel.preferredTrainingStyles, opposite: $viewModel.dislikedTrainingStyles)
                trainingStyleSection(title: "Rather avoid", selection: $viewModel.dislikedTrainingStyles, opposite: $viewModel.preferredTrainingStyles)

                Button("Save Changes") { attemptSave() }
                    .buttonStyle(.trainingOSPrimary)
                    .frame(maxWidth: .infinity)
                    .disabled(viewModel.selectedWeekdays.isEmpty)
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.ground)
        .navigationTitle("Training Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.load(modelContext: modelContext) }
        .alert("Effect on your schedule", isPresented: Binding(
            get: { pendingConsequence != nil }, set: { if !$0 { pendingConsequence = nil } }
        ), presenting: pendingConsequence) { _ in
            Button("Apply Anyway", role: .destructive) {
                pendingConsequence = nil
                _ = viewModel.save(modelContext: modelContext)
                dismiss()
            }
            Button("Cancel", role: .cancel) { pendingConsequence = nil }
        } message: { consequence in
            Text(message(for: consequence))
        }
    }

    private func attemptSave() {
        let consequence = viewModel.previewConsequence()
        switch consequence {
        case .fitsAsIs:
            _ = viewModel.save(modelContext: modelContext)
            dismiss()
        case .requiresDoubleSessions, .exceedsCapacityEvenWithDoubles:
            pendingConsequence = consequence
        }
    }

    private func message(for consequence: TrainingPreferencesConsequence) -> String {
        switch consequence {
        case .fitsAsIs:
            return ""
        case .requiresDoubleSessions:
            return "Your current training mix will need a double-session day to fit inside \(viewModel.availableTrainingDaysPerWeek) day\(viewModel.availableTrainingDaysPerWeek == 1 ? "" : "s") a week, starting with your next tactical week. This week is not affected."
        case .exceedsCapacityEvenWithDoubles(let shortfall):
            return "Your current training mix needs \(shortfall) more session\(shortfall == 1 ? "" : "s") a week than this configuration can fit, even with double sessions. TrainingOS will not silently drop a required session — consider allowing double sessions, adding a day, or reducing your training mix. This week is not affected."
        }
    }

    @ViewBuilder
    private func currentMixCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CURRENT TRAINING MIX")
                .font(Theme.eyebrow)
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
            Text(summary)
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            Text("Changing your weekly composition happens on your Plan phase — this screen only reviews it.")
                .font(Theme.label)
                .foregroundStyle(Theme.textMuted)
        }
        .trainingOSCard()
    }

    /// Dogfood Round 2 (Finding 1) — Independent Review Correction 1: the
    /// real weekly-availability editor — replaces the previous "days per
    /// week" capacity bar, which edited a count with no real per-weekday
    /// meaning. The number of days selected here IS the athlete-facing
    /// capacity (`viewModel.availableTrainingDaysPerWeek`, now a read-only
    /// derived count) — never a second, independently-set truth.
    private var weekdaySection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                SectionHeader(title: "Training days")
                Spacer()
                Text("\(viewModel.availableTrainingDaysPerWeek) day\(viewModel.availableTrainingDaysPerWeek == 1 ? "" : "s")/week")
                    .font(Theme.label)
                    .foregroundStyle(Theme.primary)
            }
            ForEach(Array(Weekday.allCases.enumerated()), id: \.element) { index, day in
                Toggle(isOn: Binding(
                    get: { viewModel.selectedWeekdays.contains(day) },
                    set: { isOn in
                        if isOn { viewModel.selectedWeekdays.insert(day) } else { viewModel.selectedWeekdays.remove(day) }
                    }
                )) {
                    Text(PlanPresentation.weekdayLabel(day))
                        .font(Theme.body)
                        .foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.primary)
                .padding(.vertical, 2)
                if index < Weekday.allCases.count - 1 { Divider().opacity(0.4) }
            }
            if viewModel.selectedWeekdays.isEmpty {
                Text("Select at least one day.")
                    .font(Theme.label)
                    .foregroundStyle(Theme.attention)
            }
        }
        .trainingOSCard()
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Time available per training day")
            HStack(spacing: 8) {
                ForEach(Self.durationOptions, id: \.self) { minutes in
                    let isSelected = viewModel.typicalSessionDurationMinutes == minutes
                    Button {
                        viewModel.typicalSessionDurationMinutes = isSelected ? nil : minutes
                    } label: {
                        Text("\(minutes)+")
                            .font(Theme.label)
                            .foregroundStyle(isSelected ? Color.white : Theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isSelected ? Theme.primary : Theme.surfaceSecondary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .trainingOSCard()
    }

    private var varietySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Variety")
            Picker("Variety", selection: $viewModel.varietyPreference) {
                ForEach(VarietyPreference.allCases, id: \.self) { preference in
                    Text(preference.rawValue.capitalized).tag(preference)
                }
            }
            .pickerStyle(.segmented)
        }
        .trainingOSCard()
    }

    @ViewBuilder
    private func trainingStyleSection(title: String, selection: Binding<Set<TrainingStyle>>, opposite: Binding<Set<TrainingStyle>>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: title).padding(.bottom, 10)
            ForEach(Array(TrainingStyle.selectableCases.enumerated()), id: \.element) { index, style in
                Toggle(isOn: Binding(
                    get: { selection.wrappedValue.contains(style) },
                    set: { isOn in
                        if isOn {
                            selection.wrappedValue.insert(style)
                            opposite.wrappedValue.remove(style)
                        } else {
                            selection.wrappedValue.remove(style)
                        }
                    }
                )) {
                    Text(PlanPresentation.trainingStyleLabel(style))
                        .font(Theme.body)
                        .foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.primary)
                .padding(.vertical, 4)
                if index < TrainingStyle.selectableCases.count - 1 { Divider().opacity(0.4) }
            }
        }
        .trainingOSCard()
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    SeedDataProvider.seedAll(in: container.mainContext)
    return NavigationStack {
        TrainingPreferencesSettingsView()
    }
    .modelContainer(container)
}
