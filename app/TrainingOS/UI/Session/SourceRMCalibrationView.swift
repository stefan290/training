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
                        // Dogfood Round 1 (Finding 1): this is now
                        // genuinely optional — skipping it (or leaving
                        // some rows blank) never blocks training. Any
                        // exercise left unresolved here simply asks once
                        // more, in its own first real session, before its
                        // working sets.
                        Text("Enter your current weight for each exercise below, or skip any of them — we'll ask again the first time you reach that exercise in a real session. If you don't know the exact value, do your best to estimate it.")
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

                    // Dogfood Round 1 (Finding 1): never gated on every
                    // row being filled — this is the optional "estimate
                    // now" path. Whatever's filled in gets recorded now;
                    // anything left blank (or marked "test this properly
                    // first") is simply resolved later, in the first real
                    // session that reaches it.
                    Button("Continue") {
                        viewModel.completeCalibrationAndStart(modelContext: modelContext)
                        onCompleted()
                    }
                    .buttonStyle(.trainingOSPrimary)
                    .frame(maxWidth: .infinity)
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
            Text("OPTIONAL")
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
                Text(PlanPresentation.rmTypeLabel(row.wrappedValue.rmType))
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
                Text("Come back and enter your \(PlanPresentation.rmTypeLabel(row.wrappedValue.rmType)) once you have it — an estimate is fine if you'd rather not test it formally.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .trainingOSCard()
    }
}
