import SwiftUI

/// The approved tab navigation (handoff section 4 / "Locked decisions"):
/// Today / Plan / Progress, plus Profile (Dogfood Round 2, Findings B/C) —
/// the athlete's discoverable configuration entry point, no longer a
/// Today-toolbar-only sheet.
///
/// Stage 10R.1C addition, revised by Dogfood Round 1 (Finding 1): "Set
/// your starting weights" (`SourceRMCalibrationViewModel`) is no longer a
/// blocking gate in front of the tabs — a source-dependent Session
/// materializes immediately regardless of outstanding calibration
/// (`StartPhaseUseCase`), leaving any affected exercise's weight honestly
/// unresolved until the athlete either uses this OPTIONAL screen or
/// reaches that exercise in a real session (`StrengthExecutionView`'s own
/// in-session prompt). A dismissible banner surfaces the option without
/// ever blocking Today/Plan/Progress.
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
///
/// Dogfood Round 2 (Finding H): the starting-weight calibration banner
/// used to live here, as a `.safeAreaInset(edge: .top)` on the whole
/// `TabView`. That made it a persistent geometric inset for the ENTIRE
/// region — every screen PUSHED inside any tab's own `NavigationStack`
/// (Week, Session, workout execution) still had to render its own nav bar
/// squeezed under it, which is exactly why it collided with the back/close
/// control on those screens. It's moved to `TodayView`'s own root content
/// (inside Today's `NavigationStack`, not wrapping it) — a `safeAreaInset`
/// scoped to one specific view in a stack only affects that view, so it
/// now shows only on Today's own top-level screen and is gone the instant
/// anything is pushed, without needing any padding hack here.
struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var runningCalibrationViewModel = RunningThresholdCalibrationViewModel()

    var body: some View {
        Group {
            // Running's own gate is unchanged/untouched by Dogfood Round 1
            // — a separate, pre-existing, deliberate design choice (its
            // own doc comment: it never blocks materialization, only
            // navigation) that this checkpoint's Finding 1 never asked to
            // revisit.
            if runningCalibrationViewModel.hasPendingCalibration {
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

                    // Dogfood Round 2 (Findings B/C): Profile is now a real,
                    // discoverable root tab — the athlete's one configuration
                    // entry point — replacing the former Today-toolbar-only
                    // sheet presentation.
                    ProfileView()
                        .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                }
                .tint(Theme.primary)
            }
        }
        .onAppear {
            runningCalibrationViewModel.load(modelContext: modelContext)
        }
        // Stage 10R.7B (D-10R7B-7): a successful strategic transition can
        // legitimately leave a component awaiting fresh source RM
        // calibration — this re-runs the exact same, already-existing
        // check rather than building a second routing mechanism. Cheap
        // and idempotent (`SourceRMCalibrationViewModel.load`'s own doc
        // comment) — safe to call again even when nothing changed.
        .onReceive(NotificationCenter.default.publisher(for: .strategicPhaseTransitionCompleted)) { _ in
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
