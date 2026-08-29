import SwiftUI

/// The approved three-tab navigation (handoff section 4 / "Locked
/// decisions"): Today / Plan / Progress. Programs lives inside Plan and
/// Profile hangs off the Today header — neither exists yet in this pass.
///
/// Stage 10R.1C addition: before showing the tabs at all, checks whether
/// any real `.rmBased` program instance still has outstanding required
/// source RM calibration (`SourceRMCalibrationViewModel`) and, if so,
/// presents "Set your starting weights" instead — the user cannot reach
/// Today with a source-dependent Session materialized-but-blank; it
/// simply isn't materialized yet (`STAGE10R1C_SOURCE_RM_CALIBRATION_DESIGN.md`).
struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var calibrationViewModel = SourceRMCalibrationViewModel()

    var body: some View {
        Group {
            if calibrationViewModel.hasPendingCalibration {
                SourceRMCalibrationView(viewModel: calibrationViewModel) {
                    calibrationViewModel.load(modelContext: modelContext)
                }
            } else {
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
        .onAppear { calibrationViewModel.load(modelContext: modelContext) }
        // Stage 10R.7B (D-10R7B-7): a successful strategic transition can
        // legitimately leave a component awaiting fresh source RM
        // calibration — this re-runs the exact same, already-existing
        // check rather than building a second routing mechanism. Cheap
        // and idempotent (`SourceRMCalibrationViewModel.load`'s own doc
        // comment) — safe to call again even when nothing changed.
        .onReceive(NotificationCenter.default.publisher(for: .strategicPhaseTransitionCompleted)) { _ in
            calibrationViewModel.load(modelContext: modelContext)
        }
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    SeedDataProvider.seedAll(in: container.mainContext)
    return RootTabView()
        .modelContainer(container)
}
