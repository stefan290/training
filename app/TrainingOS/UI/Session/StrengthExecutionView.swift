import SwiftUI
import SwiftData

/// Strength/Hypertrophy/Accessory/Powerlifting execution
/// (`STRENGTH_EXECUTION_FLOW.md`, Part D/G — reused unmodified for
/// Powerlifting, since nothing here branches on programming methodology).
/// One movement at a time: target sets-reps/RIR/suggested load, previous
/// performance, current-set logging, a rest timer, and Change Exercise.
/// Editing the weight/reps fields before logging changes only what gets
/// recorded as this set's actual result — it never writes back to the
/// set's own prescription (CLAUDE.md rule 3).
struct StrengthExecutionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: StrengthExecutionViewModel
    let session: Session
    let executionState: SessionExecutionState

    @State private var weightText: String = ""
    @State private var reps: Int = 0
    @State private var actualRir: Int?
    @State private var lastHighlight: LoggedResultHighlight?
    @State private var showingChangeExercise = false

    init(block: WorkoutBlock, session: Session, executionState: SessionExecutionState) {
        _viewModel = State(initialValue: StrengthExecutionViewModel(block: block))
        self.session = session
        self.executionState = executionState
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.movements.count > 1 {
                    Picker("Movement", selection: Binding(
                        get: { viewModel.movementIndex },
                        set: { viewModel.selectMovement($0, modelContext: modelContext); resetInputsForCurrentSet() }
                    )) {
                        ForEach(Array(viewModel.movements.enumerated()), id: \.offset) { index, movement in
                            Text(movement.exercise?.canonicalName ?? "Exercise").tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let movement = viewModel.currentMovement, let exercise = movement.exercise {
                    header(exercise: exercise)

                    if !viewModel.previousResults.isEmpty {
                        previousPerformance
                    }

                    if let highlight = lastHighlight {
                        highlightBanner(highlight)
                    }

                    if viewModel.isMovementComplete {
                        ContentUnavailableView("All sets logged", systemImage: "checkmark.circle")
                    } else {
                        currentSetCard

                        RestTimerView(block: viewModel.block)
                    }

                    Button("Change Exercise") { showingChangeExercise = true }
                        .buttonStyle(.bordered)
                }
            }
            .padding(16)
        }
        .background(Theme.ground)
        .navigationTitle(viewModel.currentMovement?.exercise?.canonicalName ?? "Strength")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingChangeExercise, onDismiss: { viewModel.loadPreviousPerformance(modelContext: modelContext) }) {
            if let movement = viewModel.currentMovement {
                ChangeExerciseView(prescription: movement, session: session)
            }
        }
        .task {
            try? CompleteBlockUseCase.start(viewModel.block, modelContext: modelContext)
            viewModel.loadPreviousPerformance(modelContext: modelContext)
            resetInputsForCurrentSet()
        }
    }

    private func header(exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.canonicalName)
                .font(Theme.heading)
                .foregroundStyle(Theme.textPrimary)
            if let setPrescription = viewModel.currentSetPrescription {
                Text("Set \(viewModel.currentSetIndex + 1) of \(viewModel.currentMovement?.orderedSetPrescriptions.count ?? 0) · \(setPrescription.repRangeLow)-\(setPrescription.repRangeHigh) reps"
                    + (setPrescription.targetRir.map { " · \($0) RIR" } ?? ""))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                if let target = setPrescription.targetWeight {
                    Text("Suggested load: \(target.formattedWeight) kg")
                        .font(Theme.numeric)
                        .foregroundStyle(Theme.primary)
                }
            }
        }
    }

    private var previousPerformance: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PREVIOUS")
                .font(Theme.label)
                .foregroundStyle(Theme.textSecondary)
            ForEach(viewModel.previousResults, id: \.id) { result in
                Text("\(result.weight.formattedWeight) kg x \(result.reps)"
                     + (result.actualRir.map { " @ \($0) RIR" } ?? ""))
                    .font(Theme.numeric)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var currentSetCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Load (kg)")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                TextField("Weight", text: $weightText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(Theme.numeric)
                    .frame(width: 90)
            }

            Stepper("Reps: \(reps)", value: $reps, in: 0...50)
                .font(Theme.body)

            VStack(alignment: .leading, spacing: 6) {
                Text("RIR")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 8) {
                    ForEach(0...4, id: \.self) { value in
                        let label = value == 4 ? "4+" : "\(value)"
                        Button(label) { actualRir = value }
                            .buttonStyle(.borderedProminent)
                            .tint(actualRir == value ? Theme.primary : Theme.surfaceSecondary)
                            .foregroundStyle(actualRir == value ? .white : Theme.textPrimary)
                    }
                }
            }

            Button("Log Set") { logSet() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
                .frame(maxWidth: .infinity)
                .disabled(Double(weightText) == nil)
        }
        .padding(14)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func highlightBanner(_ highlight: LoggedResultHighlight) -> some View {
        Text(highlight.isPersonalRecord ? "New personal record: \(highlight.value)"
             : highlight.isFirstEverEntry ? "Baseline established: \(highlight.value)"
             : "Logged: \(highlight.value)")
            .font(Theme.body)
            .foregroundStyle(highlight.isPersonalRecord ? Theme.positive : Theme.textSecondary)
    }

    private func logSet() {
        guard let weight = Double(weightText) else { return }
        lastHighlight = viewModel.logCurrentSet(weight: weight, reps: reps, actualRir: actualRir, modelContext: modelContext)
        executionState.record(lastHighlight)
        resetInputsForCurrentSet()
    }

    private func resetInputsForCurrentSet() {
        guard let setPrescription = viewModel.currentSetPrescription else { return }
        weightText = setPrescription.targetWeight.map { $0.formattedWeight } ?? ""
        reps = setPrescription.repRangeHigh
        actualRir = setPrescription.targetRir
    }
}
