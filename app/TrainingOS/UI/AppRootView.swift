import SwiftUI

/// Stage V1.Checkpoint 1/2: the app's real root — routes between
/// onboarding, real strategic-plan selection (Checkpoint 2), and the
/// existing `RootTabView` (unchanged), based only on
/// `AppRootStateResolver.resolve` — never a separately-persisted "onboarded"
/// flag. `refresh` is passed down as `onComplete` to whichever step is
/// showing, so a successful write (onboarding finishing, or Checkpoint 2
/// accepting + starting the first phase) always re-resolves from real
/// persisted state rather than manually forcing a transition.
struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var state: AppRootState = .needsOnboarding

    var body: some View {
        Group {
            switch state {
            case .needsOnboarding:
                OnboardingFlowView(onComplete: refresh)
            case .readyForPlan:
                StrategicPlanSelectionView(onComplete: refresh)
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
