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
struct SourceRMCalibrationView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var viewModel: SourceRMCalibrationViewModel
    var onCompleted: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Set your starting weights")
                            .font(Theme.heading)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Enter your current weight for each exercise below. If you don't know the exact value, do your best to estimate it — you can always adjust it later.")
                            .font(Theme.label)
                            .foregroundStyle(Theme.textSecondary)
                    }

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
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.primary)
                    .frame(maxWidth: .infinity)
                    .disabled(!viewModel.allSatisfied)
                }
                .padding(16)
            }
            .background(Theme.ground)
            .navigationTitle("Starting Weights")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func rowView(row: Binding<SourceRMCalibrationViewModel.Row>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.wrappedValue.exercise.canonicalName)
                .font(Theme.body.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(rmTypeLabel(row.wrappedValue.rmType))
                .font(Theme.label)
                .foregroundStyle(Theme.textSecondary)
            if let previous = row.wrappedValue.previousValueKilograms {
                Text("Previous: \(previous, specifier: "%.1f") kg")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack {
                TextField("Enter value", text: row.enteredText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: row.wrappedValue.enteredText) { _, _ in
                        row.wrappedValue.needsTesting = false
                    }
                Text("kg")
                    .foregroundStyle(Theme.textSecondary)
            }
            Button("I'd rather test this properly first") {
                viewModel.markNeedsTesting(row.wrappedValue)
            }
            .font(Theme.label)
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            if row.wrappedValue.needsTesting {
                Text("Come back and enter your \(rmTypeLabel(row.wrappedValue.rmType)) once you have it — an estimate is fine if you'd rather not test it formally.")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .background(Theme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func rmTypeLabel(_ rmType: RMType) -> String {
        switch rmType {
        case .rm10: return "10RM"
        case .rm8: return "8RM"
        case .rm5: return "5RM"
        }
    }
}
