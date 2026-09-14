import SwiftUI
import SwiftData

/// Running Athlete Journey Completion (Vertical Completion V1): "Set your
/// running pace" — presented instead of Today whenever a real Running
/// program instance has an outstanding Threshold Pace requirement
/// (`RunningThresholdCalibrationViewModel`). Mirrors
/// `SourceRMCalibrationView`'s exact editorial grammar (Theme.headingXL
/// heading, real body-weight prose, `.trainingOSCard()` context framing,
/// shared button styles) — this is the same "one last step" moment for a
/// different modality, never a generic Settings-style form. Athlete-facing
/// copy avoids "Threshold Pace" jargon in favor of what it actually means
/// to a runner: a comfortably-hard, sustainable pace.
struct RunningThresholdCalibrationView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var viewModel: RunningThresholdCalibrationViewModel
    var onCompleted: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Set your running pace")
                            .font(Theme.headingXL)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Some of your Running workouts are prescribed relative to your current threshold pace — the pace you could sustain hard, but steadily, for about 20-30 minutes. Enter your best estimate below; you can always adjust it later.")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    contextCard

                    paceEntryRow

                    Button("Continue") {
                        viewModel.completeCalibration(modelContext: modelContext)
                        onCompleted()
                    }
                    .buttonStyle(.trainingOSPrimary)
                    .frame(maxWidth: .infinity)
                    .disabled(!viewModel.isSatisfied)
                }
                .padding(Theme.screenPadding)
            }
            .background(Theme.ground)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Same reassurance framing as `SourceRMCalibrationView.contextCard` —
    /// zero engine terminology, explains why this one number is needed.
    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ONE LAST STEP")
                .font(Theme.eyebrow)
                .tracking(1.2)
                .foregroundStyle(Theme.primary)
            Text("This is the one real number TrainingOS needs from you to turn your Running workouts into actual paces to run — never a guess it makes for you.")
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainingOSCard(emphasized: true)
    }

    private var paceEntryRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pace per kilometer")
                .font(Theme.body.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 10) {
                TextField("min", text: $viewModel.enteredMinutesText)
                    .keyboardType(.numberPad)
                    .font(Theme.numeric)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.ground, in: RoundedRectangle(cornerRadius: 10))
                    .frame(width: 70)
                Text(":")
                    .font(Theme.numeric)
                    .foregroundStyle(Theme.textSecondary)
                TextField("sec", text: $viewModel.enteredSecondsText)
                    .keyboardType(.numberPad)
                    .font(Theme.numeric)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.ground, in: RoundedRectangle(cornerRadius: 10))
                    .frame(width: 70)
                Text("/ km")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainingOSCard()
    }
}
