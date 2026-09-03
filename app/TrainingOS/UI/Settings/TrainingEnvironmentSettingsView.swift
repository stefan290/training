import SwiftUI
import SwiftData

/// Stage V1 dogfooding fix: `TrainingEnvironmentSettingsView` loads/mutates
/// its own independently-fetched `profile` reference — a SwiftData to-one
/// relationship write (`defaultTrainingEnvironment`) made here does not
/// reliably re-trigger a SwiftUI Observation re-render in a SIBLING view
/// (`OnboardingFlowView`) that reads the same fact via a different object
/// graph traversal. Posting this notification and having the sibling
/// explicitly refresh its own directly-`@Observable`-owned state is the
/// same established pattern `RootTabView`/`StrategicTransitionViewModel`'s
/// `.strategicPhaseTransitionCompleted` already uses for exactly this
/// "a write happened elsewhere, this view must notice" problem — not a new
/// mechanism.
extension Notification.Name {
    static let trainingEnvironmentDefaultChanged = Notification.Name("trainingEnvironmentDefaultChanged")
}

/// Stage TE.1: minimum settings UX for `TrainingEnvironment` — create a
/// named environment, toggle which `EquipmentRequirement`s it has, and
/// choose the single default (`UserProfile.defaultTrainingEnvironment`).
/// Deliberately minimal (CLAUDE.md rule 11): no per-session override, no
/// facility modeling, no equipment quantities — exactly the same scope
/// the domain model itself supports, nothing more.
///
/// TE.1 closure pass: wired to a production entry point — the avatar
/// button in `TodayView`'s header, matching the handoff's own locked
/// navigation ("Profile from the avatar in the Today header",
/// `Training OS Handoff.dc.html`). The full `Profile → Integrations ·
/// Settings · Advanced` hub is out of TE.1's scope; this presents
/// Training Environment configuration directly rather than building
/// that broader hierarchy merely to reach it.
struct TrainingEnvironmentSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var profile: UserProfile?
    @State private var newEnvironmentName = ""

    var body: some View {
        NavigationStack {
            List {
                if let profile {
                    ForEach(profile.trainingEnvironments) { environment in
                        Section {
                            environmentRow(environment, profile: profile)
                        }
                    }
                }

                Section("Add environment") {
                    HStack {
                        TextField("Name (e.g. Home Gym)", text: $newEnvironmentName)
                        Button("Add") { addEnvironment(to: profile) }
                            .disabled(newEnvironmentName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Training Environment")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: loadProfile)
    }

    private func loadProfile() {
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        profile = users.first?.profile
    }

    private func addEnvironment(to profile: UserProfile?) {
        guard let profile else { return }
        let trimmed = newEnvironmentName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let environment = TrainingEnvironment(name: trimmed)
        modelContext.insert(environment)
        profile.trainingEnvironments.append(environment)
        if profile.defaultTrainingEnvironment == nil {
            profile.defaultTrainingEnvironment = environment
        }
        newEnvironmentName = ""
        try? modelContext.save()
        NotificationCenter.default.post(name: .trainingEnvironmentDefaultChanged, object: nil)
    }

    @ViewBuilder
    private func environmentRow(_ environment: TrainingEnvironment, profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(environment.name)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    profile.defaultTrainingEnvironment = environment
                    try? modelContext.save()
                    NotificationCenter.default.post(name: .trainingEnvironmentDefaultChanged, object: nil)
                } label: {
                    Image(systemName: profile.defaultTrainingEnvironment?.id == environment.id ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(profile.defaultTrainingEnvironment?.id == environment.id ? Theme.primary : Theme.textSecondary)
            }
            Text(profile.defaultTrainingEnvironment?.id == environment.id ? "Default" : "Tap to make default")
                .font(Theme.label)
                .foregroundStyle(Theme.textSecondary)

            ForEach(EquipmentRequirement.allCases, id: \.self) { equipment in
                Toggle(equipment.displayName, isOn: Binding(
                    get: { environment.availableEquipment.contains(equipment) },
                    set: { isOn in
                        if isOn {
                            if !environment.availableEquipment.contains(equipment) {
                                environment.availableEquipment.append(equipment)
                            }
                        } else {
                            environment.availableEquipment.removeAll { $0 == equipment }
                        }
                        try? modelContext.save()
                    }
                ))
                .font(Theme.label)
            }

            // TE.1 closure: a real production path to exercise the
            // nullify-on-delete relationship (`Session.materializedInEnvironment`
            // / `UserProfile.defaultTrainingEnvironment`) — not just a test
            // constructing the deletion directly.
            Button("Delete Environment", role: .destructive) {
                modelContext.delete(environment)
                try? modelContext.save()
            }
            .font(Theme.label)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    SeedDataProvider.seedAll(in: container.mainContext)
    return TrainingEnvironmentSettingsView()
        .modelContainer(container)
}
