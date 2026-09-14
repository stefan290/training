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
///
/// Running Athlete Journey Completion (Vertical Completion V1): a second,
/// analogous gate for Running's own Threshold Pace requirement
/// (`RunningThresholdCalibrationViewModel`). Checked AFTER the Strength/
/// Hypertrophy gate — an athlete with both outstanding simultaneously
/// (a genuinely rare concurrent-mix edge case) resolves the RM gate
/// first, matching the pre-existing precedence this file already had for
/// its one gate; Running's own gate then naturally appears on the very
/// next `load()` once the first is satisfied, never skipped. Unlike the
/// RM gate, this one never blocks materialization — Running's own
/// `RunningProgramMaterializer.materializeAllWeeks` already runs
/// regardless of calibration (nothing in that program depends on a live
/// per-week result); this gate exists purely so the athlete never reaches
/// Today staring at an unresolved percentage.
struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var calibrationViewModel = SourceRMCalibrationViewModel()
    @State private var runningCalibrationViewModel = RunningThresholdCalibrationViewModel()

    var body: some View {
        Group {
            if calibrationViewModel.hasPendingCalibration {
                SourceRMCalibrationView(viewModel: calibrationViewModel) {
                    calibrationViewModel.load(modelContext: modelContext)
                }
            } else if runningCalibrationViewModel.hasPendingCalibration {
                RunningThresholdCalibrationView(viewModel: runningCalibrationViewModel) {
                    runningCalibrationViewModel.load(modelContext: modelContext)
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
        .onAppear {
            calibrationViewModel.load(modelContext: modelContext)
            runningCalibrationViewModel.load(modelContext: modelContext)
        }
        // Stage 10R.7B (D-10R7B-7): a successful strategic transition can
        // legitimately leave a component awaiting fresh source RM
        // calibration — this re-runs the exact same, already-existing
        // check rather than building a second routing mechanism. Cheap
        // and idempotent (`SourceRMCalibrationViewModel.load`'s own doc
        // comment) — safe to call again even when nothing changed.
        .onReceive(NotificationCenter.default.publisher(for: .strategicPhaseTransitionCompleted)) { _ in
            calibrationViewModel.load(modelContext: modelContext)
            runningCalibrationViewModel.load(modelContext: modelContext)
        }
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    SeedDataProvider.seedAll(in: container.mainContext)
    return RootTabView()
        .modelContainer(container)
}
