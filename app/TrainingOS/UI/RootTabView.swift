import SwiftUI

/// The approved three-tab navigation (handoff section 4 / "Locked
/// decisions"): Today / Plan / Progress. Programs lives inside Plan and
/// Profile hangs off the Today header — neither exists yet in this pass.
struct RootTabView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }

            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }

            TrainingProgressView()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
        }
        .tint(Theme.primary)
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    SeedDataProvider.seedAll(in: container.mainContext)
    return RootTabView()
        .modelContainer(container)
}
