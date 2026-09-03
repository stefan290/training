import SwiftUI

/// Stage V1.Checkpoint 1: the app's real root — routes between onboarding,
/// the "ready for plan" placeholder (Checkpoint 2's entry point), and the
/// existing `RootTabView` (unchanged), based only on
/// `AppRootStateResolver.resolve` — never a separately-persisted "onboarded"
/// flag.
struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var state: AppRootState = .needsOnboarding

    var body: some View {
        Group {
            switch state {
            case .needsOnboarding:
                OnboardingFlowView(onComplete: refresh)
            case .readyForPlan:
                ReadyForPlanView()
            case .activeTraining:
                RootTabView()
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        state = AppRootStateResolver.resolve(context: modelContext)
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    return AppRootView()
        .modelContainer(container)
}
