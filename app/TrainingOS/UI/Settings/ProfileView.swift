import SwiftUI
import SwiftData

/// Dogfood Round 2 (Findings B/C): the athlete's discoverable
/// configuration entry point — now a real root tab (`RootTabView`), not a
/// sheet buried behind Today's toolbar. `TrainingPreferencesSettingsView`
/// is pushed directly (it declares no `NavigationStack` of its own, so it
/// correctly inherits this one's native back button). `TrainingEnvironmentSettingsView`
/// stays a `.sheet` here, matching every other place in the app that
/// presents it (`PhaseDetailView`, `StrategicPhaseTransitionSheet`,
/// `OnboardingFlowView`, `StrategicPlanSelectionView`, `ChangeExerciseView`)
/// — it declares its own internal `NavigationStack`, which is correct for
/// a sheet's own presentation context, so it is left untouched rather than
/// pushed (pushing it would recreate the exact nested-`NavigationStack`
/// defect this checkpoint fixes elsewhere). Training Mix reuses the real,
/// existing recommendation → consequence → approval review surface
/// (`PhaseDetailView`, already shown from `PlanView`) for the athlete's
/// current active phase — never a second, invented mix editor.
struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showingTrainingEnvironmentSettings = false
    @State private var activePhase: TrainingPhase?

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Training Preferences") { TrainingPreferencesSettingsView() }
                NavigationLink("Movement Capability") { MovementCapabilityCollectionView() }
                Button {
                    showingTrainingEnvironmentSettings = true
                } label: {
                    Text("Training Environment").foregroundStyle(.primary)
                }
                if let activePhase {
                    NavigationLink("Training Mix") { PhaseDetailView(phase: activePhase) }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: loadActivePhase)
        .sheet(isPresented: $showingTrainingEnvironmentSettings) {
            TrainingEnvironmentSettingsView()
        }
    }

    private func loadActivePhase() {
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        guard let activeGoal = users.first?.goals.first(where: { $0.status == .active }) else {
            activePhase = nil
            return
        }
        activePhase = activeGoal.plans.first { $0.status == .active }?.orderedPhases.first { $0.status == .active }
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    SeedDataProvider.seedAll(in: container.mainContext)
    return ProfileView()
        .modelContainer(container)
}
