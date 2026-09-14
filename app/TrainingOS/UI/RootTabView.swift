import SwiftUI

/// The approved three-tab navigation (handoff section 4 / "Locked
/// decisions"): Today / Plan / Progress. Programs lives inside Plan and
/// Profile hangs off the Today header — neither exists yet in this pass.
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
struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var calibrationViewModel = SourceRMCalibrationViewModel()
    @State private var runningCalibrationViewModel = RunningThresholdCalibrationViewModel()
    @State private var showingCalibrationSheet = false

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
                }
                .tint(Theme.primary)
                // Dogfood Round 1 (Finding 1): a dismissible, non-blocking
                // opportunity to estimate starting weights now — never
                // gating the tabs behind it.
                .safeAreaInset(edge: .top) {
                    if calibrationViewModel.hasPendingCalibration {
                        calibrationBanner
                    }
                }
                .sheet(isPresented: $showingCalibrationSheet) {
                    SourceRMCalibrationView(viewModel: calibrationViewModel) {
                        calibrationViewModel.load(modelContext: modelContext)
                        showingCalibrationSheet = false
                    }
                }
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

    /// Dogfood Round 1 (Finding 1): purely an invitation, never a
    /// requirement — tapping it opens the same optional "estimate now"
    /// screen; ignoring it changes nothing about whether the athlete can
    /// train today.
    private var calibrationBanner: some View {
        Button {
            showingCalibrationSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "scalemass")
                Text("Some exercises still need a starting weight — set it now, or we'll ask before your first set.")
                    .font(Theme.label)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(12)
            .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .buttonStyle(.plain)
        .background(Theme.ground)
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    SeedDataProvider.seedAll(in: container.mainContext)
    return RootTabView()
        .modelContainer(container)
}
