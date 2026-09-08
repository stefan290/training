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

/// V1 R5 (Training Environment product reconciliation): rebuilt on the R1
/// design foundation. "Full Gym" (`TrainingEnvironment.isBuiltIn`) is
/// always shown first, clearly labeled built-in, and can never be
/// deleted — it is the zero-config default every athlete already has.
/// Custom environments (Home Gym, Garage Gym, ...) appear below, each
/// with its own real, persisted equipment selection, default toggle, and
/// delete action. Deliberately minimal (CLAUDE.md rule 11): no per-
/// session override here (that lives on the workout itself, R5 Part 1),
/// no facility modeling, no equipment quantities — exactly what the
/// domain model itself supports.
struct TrainingEnvironmentSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var profile: UserProfile?
    @State private var isAddingEnvironment = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SectionHeader(title: "Training Environments")
                    if let profile {
                        VStack(spacing: 10) {
                            ForEach(sortedEnvironments(profile)) { environment in
                                NavigationLink {
                                    TrainingEnvironmentDetailView(environment: environment, profile: profile)
                                } label: {
                                    environmentRow(environment, profile: profile)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Button {
                        isAddingEnvironment = true
                    } label: {
                        Label("Add Environment", systemImage: "plus.circle")
                            .font(Theme.body)
                            .foregroundStyle(Theme.primary)
                    }
                    .padding(.top, 4)
                }
                .padding(Theme.screenPadding)
            }
            .background(Theme.ground)
            .navigationTitle("Training Environment")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: loadProfile)
        .sheet(isPresented: $isAddingEnvironment) {
            if let profile {
                AddTrainingEnvironmentView(profile: profile) { isAddingEnvironment = false }
            }
        }
    }

    /// Full Gym (built-in) always leads, regardless of insertion order —
    /// the athlete should never have to look for it among custom rows.
    private func sortedEnvironments(_ profile: UserProfile) -> [TrainingEnvironment] {
        profile.trainingEnvironments.sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn }
            return lhs.name < rhs.name
        }
    }

    private func loadProfile() {
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        profile = users.first?.profile
    }

    @ViewBuilder
    private func environmentRow(_ environment: TrainingEnvironment, profile: UserProfile) -> some View {
        let isDefault = profile.defaultTrainingEnvironment?.id == environment.id
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(environment.name)
                        .font(Theme.body.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    if environment.isBuiltIn {
                        Text("BUILT-IN")
                            .font(Theme.eyebrow)
                            .tracking(1.0)
                            .foregroundStyle(Theme.textInactive)
                    }
                }
                Text(isDefault ? "Default" : "Tap to view")
                    .font(Theme.label)
                    .foregroundStyle(isDefault ? Theme.primary : Theme.textSecondary)
            }
            Spacer()
            if isDefault {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.primary)
            } else {
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.textInactive)
            }
        }
        .trainingOSCard(emphasized: isDefault)
    }
}

/// Detail/edit surface for one real environment — set as default, edit
/// equipment (custom only; Full Gym's equipment is fixed/built-in and
/// shown read-only), delete (custom only).
private struct TrainingEnvironmentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let environment: TrainingEnvironment
    let profile: UserProfile

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !environment.isBuiltIn, !isDefault {
                    Button("Make Default") {
                        profile.defaultTrainingEnvironment = environment
                        try? modelContext.save()
                        NotificationCenter.default.post(name: .trainingEnvironmentDefaultChanged, object: nil)
                    }
                    .buttonStyle(.trainingOSPrimary)
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: environment.isBuiltIn ? "Included Equipment" : "Available Equipment")
                        .padding(.bottom, 10)
                    ForEach(Array(EquipmentRequirement.allCases.enumerated()), id: \.element) { index, equipment in
                        equipmentRow(equipment)
                        if index < EquipmentRequirement.allCases.count - 1 { Divider().opacity(0.4) }
                    }
                }
                .trainingOSCard()

                if !environment.isBuiltIn {
                    Button("Delete Environment", role: .destructive) {
                        if isDefault { profile.defaultTrainingEnvironment = nil }
                        modelContext.delete(environment)
                        try? modelContext.save()
                        NotificationCenter.default.post(name: .trainingEnvironmentDefaultChanged, object: nil)
                        dismiss()
                    }
                    .font(Theme.body)
                    .foregroundStyle(.red)
                }
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.ground)
        .navigationTitle(environment.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isDefault: Bool { profile.defaultTrainingEnvironment?.id == environment.id }

    @ViewBuilder
    private func equipmentRow(_ equipment: EquipmentRequirement) -> some View {
        if environment.isBuiltIn {
            HStack {
                Text(equipment.displayName)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "checkmark")
                    .foregroundStyle(Theme.positive)
            }
            .padding(.vertical, 8)
        } else {
            Toggle(isOn: Binding(
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
            )) {
                Text(equipment.displayName)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.primary)
            .padding(.vertical, 4)
        }
    }
}

/// Creating a custom environment (Home Gym, Garage Gym, Hotel Gym, ...) —
/// deliberately simple: a name and which of the existing
/// `EquipmentRequirement` categories are actually available. No weight
/// ranges, no inventory, no spatial constraints (explicitly out of R5's
/// scope — a separate equipment-fidelity checkpoint).
private struct AddTrainingEnvironmentView: View {
    @Environment(\.modelContext) private var modelContext
    let profile: UserProfile
    let onDone: () -> Void

    @State private var name = ""
    @State private var selectedEquipment: Set<EquipmentRequirement> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Name")
                        TextField("e.g. Home Gym", text: $name)
                            .font(Theme.body)
                            .padding(12)
                            .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(title: "What do you have available?")
                            .padding(.bottom, 10)
                        ForEach(Array(EquipmentRequirement.allCases.enumerated()), id: \.element) { index, equipment in
                            Toggle(isOn: Binding(
                                get: { selectedEquipment.contains(equipment) },
                                set: { isOn in
                                    if isOn { selectedEquipment.insert(equipment) } else { selectedEquipment.remove(equipment) }
                                }
                            )) {
                                Text(equipment.displayName)
                                    .font(Theme.body)
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .tint(Theme.primary)
                            .padding(.vertical, 4)
                            if index < EquipmentRequirement.allCases.count - 1 { Divider().opacity(0.4) }
                        }
                    }
                    .trainingOSCard()
                }
                .padding(Theme.screenPadding)
            }
            .background(Theme.ground)
            .navigationTitle("Add Environment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDone)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: addEnvironment)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addEnvironment() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let environment = TrainingEnvironment(name: trimmed, availableEquipment: Array(selectedEquipment), isBuiltIn: false)
        modelContext.insert(environment)
        profile.trainingEnvironments.append(environment)
        try? modelContext.save()
        NotificationCenter.default.post(name: .trainingEnvironmentDefaultChanged, object: nil)
        onDone()
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    SeedDataProvider.seedAll(in: container.mainContext)
    return TrainingEnvironmentSettingsView()
        .modelContainer(container)
}
