import SwiftUI
import SwiftData

/// Stage 10R.1C: "Set your starting weights" — presented instead of
/// Today whenever a real `.rmBased` program instance has outstanding
/// required source RM calibration (`SourceRMCalibrationViewModel`).
/// **Stage 10R.1D correction:** the source's own instructions explicitly
/// tell the athlete to estimate if they don't know the exact value
/// ("if you don't know the exact values, do your best to estimate them" —
/// `STAGE10R1D_SOURCE_SEMANTICS_CORRECTION.md` §12) — this screen must
/// never imply a formal tested attempt is required. Still never
/// pre-filled or auto-estimated by TrainingOS itself (CLAUDE.md rule 10):
/// the value always comes from the user, whether it's exact or their own
/// best estimate.
///
/// R6 First-Run Journey Design Completion: restyled onto the same
/// editorial grammar as Goal/Availability/Review/Your Plan (Theme.headingXL
/// heading, real body-weight prose, `.trainingOSCard()` rows, shared
/// button styles) — no more native `.navigationTitle` bar, no more
/// monospace-as-default-body-copy. The design artifact (`Training OS.dc.html`)
/// has no literal one-to-one "enter your working weight" screen — its own
/// Screen 21 ("First week — Step 4 · weights already known," Design Pass 01)
/// is the closest real reference, and it frames calibration as a
/// REASSURANCE ("Nothing resets... the four unknown exercises open with a
/// calibration set instead of a guess") rather than a bare form, which is
/// exactly what `contextCard` below borrows. Screen 21's own segmented
/// 4-of-4 progress bar is deliberately NOT reproduced here: that bar
/// belongs to `OnboardingViewModel.Step`'s one-time first-run sequence,
/// while this screen is gated by `RootTabView` and can legitimately
/// reappear on ANY later relaunch with a fresh source-backed program — a
/// returning athlete is not "in onboarding step 4," so showing that bar
/// here would misrepresent real app state.
struct SourceRMCalibrationView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var viewModel: SourceRMCalibrationViewModel
    var onCompleted: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Set your starting weights")
                            .font(Theme.headingXL)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Enter your current weight for each exercise below. If you don't know the exact value, do your best to estimate it — you can always adjust it later.")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    contextCard

                    // Stage 10R.1C crash fix: a manual-acceptance crash
                    // traced to `Start Program` clearing `viewModel.rows`
                    // to `[]` while `TextField`s were still bound via raw
                    // integer indices (`$viewModel.rows[index]`) into that
                    // same array — a classic SwiftUI hazard where the
                    // array can shrink out from under an in-flight index
                    // binding and trap with "Index out of range." Binding
                    // through `ForEach($viewModel.rows)` instead resolves
                    // each row's `Binding` by stable `Identifiable` id at
                    // render time, never a captured raw index, so clearing
                    // the array (success) or leaving it unchanged (retry)
                    // is always safe regardless of timing.
                    VStack(spacing: 12) {
                        ForEach($viewModel.rows) { $row in
                            rowView(row: $row)
                        }
                    }

                    Button("Start Program") {
                        viewModel.completeCalibrationAndStart(modelContext: modelContext)
                        onCompleted()
                    }
                    .buttonStyle(.trainingOSPrimary)
                    .frame(maxWidth: .infinity)
                    .disabled(!viewModel.allSatisfied)
                }
                .padding(Theme.screenPadding)
            }
            .background(Theme.ground)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// Borrows Screen 21's own "Nothing resets" reassurance framing
    /// (accent-tinted card, athlete-facing prose, zero engine terminology)
    /// rather than dropping the athlete straight into a bare form — this
    /// answers items 5A/5B (context + purpose) in one place.
    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ONE LAST STEP")
                .font(Theme.eyebrow)
                .tracking(1.2)
                .foregroundStyle(Theme.primary)
            Text("TrainingOS already knows what it can from your history. For anything it hasn't seen you do yet, it just needs one real number to start from — never a guess it makes for you.")
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainingOSCard(emphasized: true)
    }

    @ViewBuilder
    private func rowView(row: Binding<SourceRMCalibrationViewModel.Row>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.wrappedValue.exercise.canonicalName)
                    .font(Theme.body.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(rmTypeLabel(row.wrappedValue.rmType))
                    .font(Theme.eyebrow)
                    .foregroundStyle(Theme.textSecondary)
            }
            if let previous = row.wrappedValue.previousValueKilograms {
                Text("Previously \(previous, specifier: "%.1f") kg")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 10) {
                TextField("Enter value", text: row.enteredText)
                    .keyboardType(.decimalPad)
                    .font(Theme.numeric)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Theme.ground, in: RoundedRectangle(cornerRadius: 10))
                    .onChange(of: row.wrappedValue.enteredText) { _, _ in
                        row.wrappedValue.needsTesting = false
                    }
                Text("kg")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
            }
            // Item 5D: an intentional secondary action (accent-colored,
            // same visual role as Review's "Add a goal or event" or Your
            // Plan's "Choose another program"), never muted debug/helper
            // text.
            Button("I'd rather test this properly first") {
                viewModel.markNeedsTesting(row.wrappedValue)
            }
            .font(Theme.label)
            .buttonStyle(.plain)
            .foregroundStyle(Theme.primary)
            if row.wrappedValue.needsTesting {
                Text("Come back and enter your \(rmTypeLabel(row.wrappedValue.rmType)) once you have it — an estimate is fine if you'd rather not test it formally.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainingOSCard()
    }

    private func rmTypeLabel(_ rmType: RMType) -> String {
        switch rmType {
        case .rm10: return "10RM"
        case .rm8: return "8RM"
        case .rm5: return "5RM"
        }
    }
}
