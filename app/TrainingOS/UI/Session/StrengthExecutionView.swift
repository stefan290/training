import SwiftUI
import SwiftData

/// Strength/Hypertrophy/Accessory/Powerlifting execution
/// (`STRENGTH_EXECUTION_FLOW.md`, Part D/G — reused unmodified for
/// Powerlifting, since nothing here branches on programming methodology).
/// Continuous progression through the block's complete ordered exercise
/// list (Stage 6C Part F/G): target sets-reps/RIR/suggested load, previous
/// performance, current-set logging, a rest timer, Previous/Next Exercise
/// navigation, and Change Exercise. Editing the weight/reps fields before
/// logging changes only what gets recorded as this set's actual result —
/// it never writes back to the set's own prescription (CLAUDE.md rule 3).
struct StrengthExecutionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: StrengthExecutionViewModel
    let session: Session
    let executionState: SessionExecutionState

    @State private var weightText: String = ""
    /// Stage 10R.1D UX correction: `nil` means the athlete has not yet
    /// entered an actual rep count for this set — displayed as an
    /// explicit placeholder ("—"), never as a visually-meaningful `0`,
    /// which previously looked indistinguishable from a genuine
    /// zero-rep prescription for an RIR-only set. Prefilled from
    /// `repRangeHigh` (non-nil only for a genuine fixed-rep prescription)
    /// in `resetInputsForCurrentSet` — never fabricated for an RIR-only
    /// or unresolved-deload set.
    @State private var reps: Int?
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
                progressHeader

                if viewModel.isBlockComplete {
                    blockCompleteContent
                } else if let movement = viewModel.currentMovement, let exercise = movement.exercise {
                    header(exercise: exercise)

                    if !viewModel.previousResults.isEmpty {
                        previousPerformance
                    }

                    if let highlight = lastHighlight {
                        highlightBanner(highlight)
                    }

                    if viewModel.isMovementComplete {
                        exerciseCompleteContent
                    } else {
                        currentSetCard

                        RestTimerView(block: viewModel.block)
                    }

                    navigationBar
                    changeExerciseControl(for: movement)
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

    /// Part H: position + lightweight overall progress — never a
    /// dashboard, just the two numbers the kickoff's own example shows.
    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !viewModel.isBlockComplete {
                Text("Exercise \(viewModel.movementIndex + 1) of \(viewModel.movementCount)")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text("\(viewModel.completedMovementCount) / \(viewModel.movementCount) exercises completed")
                .font(Theme.label)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Part J: every prescribed movement is satisfied, so the block has
    /// already auto-transitioned to `.completed`
    /// (`StrengthExecutionViewModel.logCurrentSet`) — this just reflects
    /// that back and returns the user to Session Detail, where "Finish
    /// Session" is now the correct normal action, never "Finish as
    /// Partial" for genuinely full work (Part L).
    private var blockCompleteContent: some View {
        VStack(spacing: 14) {
            ContentUnavailableView("Strength block complete", systemImage: "checkmark.seal.fill")
            Button("Return to Session") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
                .frame(maxWidth: .infinity)
        }
    }

    /// Part F: shown the instant the current exercise's last set is
    /// logged — names the next exercise so the forward path is obvious,
    /// without requiring the user to back out to Session Detail first.
    private var exerciseCompleteContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ContentUnavailableView("Exercise Complete", systemImage: "checkmark.circle")
            if let nextName = viewModel.nextMovementName {
                Text("Next: \(nextName)")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    /// Part G: Previous/Next Exercise, always available, ordering always
    /// from `WorkoutBlock.orderedPrescriptions` — inspecting an earlier or
    /// later exercise never mutates completion state. The forward button
    /// becomes the prominent action once the current exercise is done, so
    /// the natural next step is always obvious.
    private var navigationBar: some View {
        HStack {
            if viewModel.hasPreviousMovement {
                Button("Previous Exercise") { advance(.previous) }
                    .buttonStyle(.bordered)
            }
            Spacer()
            if viewModel.hasNextMovement {
                if viewModel.isMovementComplete {
                    Button("Next Exercise") { advance(.next) }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.primary)
                } else {
                    Button("Next Exercise") { advance(.next) }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    /// Part M: Change Exercise is only ever presented as available when
    /// there's a real `ExerciseSlot` to validate alternatives against —
    /// never an enabled button that leads to a dead end.
    @ViewBuilder
    private func changeExerciseControl(for movement: ExercisePrescription) -> some View {
        if movement.sourceExerciseSlot != nil {
            Button("Change Exercise") { showingChangeExercise = true }
                .buttonStyle(.bordered)
        } else {
            Text("Change Exercise unavailable — this movement wasn't materialized from a slot.")
                .font(Theme.label)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private enum NavigationDirection { case next, previous }

    private func advance(_ direction: NavigationDirection) {
        switch direction {
        case .next: viewModel.goToNextMovement(modelContext: modelContext)
        case .previous: viewModel.goToPreviousMovement(modelContext: modelContext)
        }
        lastHighlight = nil
        resetInputsForCurrentSet()
    }

    private func header(exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.canonicalName)
                .font(Theme.heading)
                .foregroundStyle(Theme.textPrimary)
            if let setPrescription = viewModel.currentSetPrescription {
                // Stage 10R.1D: a fixed rep count and an RIR/effort target
                // are never both fabricated — see `StrengthSetPresentation`
                // for the pure (independently tested) formatting rules.
                let repsText = StrengthSetPresentation.repsText(repRangeLow: setPrescription.repRangeLow, repRangeHigh: setPrescription.repRangeHigh)
                let targetText = StrengthSetPresentation.targetText(
                    repRangeLow: setPrescription.repRangeLow, repRangeHigh: setPrescription.repRangeHigh, targetRir: setPrescription.targetRir
                )
                Text("Set \(viewModel.currentSetIndex + 1) of \(viewModel.currentMovement?.orderedSetPrescriptions.count ?? 0)"
                    + (targetText.isEmpty ? "" : " · \(targetText)"))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
                if let target = setPrescription.targetWeight {
                    Text("Suggested load: \(target.formattedWeight) kg")
                        .font(Theme.numeric)
                        .foregroundStyle(Theme.primary)
                }
                // Stage 10R.1D UX correction: plain-language guidance for
                // a genuinely RIR-only prescription (no fixed rep count
                // at all — `repsText == nil`) — explains the existing RIR
                // target, never a fabricated rep range. Never shown for a
                // fixed-rep prescription (including Hypertrophy V2's
                // rep-range + explicit-RIR hybrid, which already has its
                // own rep range on screen).
                if repsText == nil, let targetRir = setPrescription.targetRir {
                    Text(StrengthSetPresentation.rirGuidance(for: targetRir))
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
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

            // Stage 10R.1D UX correction: "Actual reps" (not plain "Reps")
            // — this is what the athlete performed, never the
            // prescription — and an explicit "—" placeholder rather than
            // a visually-meaningful `0` before anything has been entered
            // (a real, previously-reported UX confusion for RIR-only
            // sets, which have no fixed rep count to show instead).
            Stepper(value: repsStepperBinding, in: 0...50) {
                Text(StrengthSetPresentation.actualRepsLabel(reps))
            }
            .font(Theme.body)

            VStack(alignment: .leading, spacing: 6) {
                // "Actual RIR" (not plain "RIR") — this selector records
                // what the athlete actually achieved, never the
                // prescription's target RIR (shown separately, above, in
                // the header).
                Text(StrengthSetPresentation.actualRirSelectorLabel)
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

    /// The Stepper widget itself needs a concrete `Int` to increment/
    /// decrement from — `reps ?? 0` supplies that starting point without
    /// ever being displayed as a number (the label above renders "—"
    /// while `reps` is `nil`); the first tap sets a real, user-entered
    /// value, at which point the label switches to showing it.
    private var repsStepperBinding: Binding<Int> {
        Binding(get: { reps ?? 0 }, set: { reps = $0 })
    }

    private func logSet() {
        guard let weight = Double(weightText) else { return }
        lastHighlight = viewModel.logCurrentSet(weight: weight, reps: reps ?? 0, actualRir: actualRir, modelContext: modelContext)
        executionState.record(lastHighlight)
        resetInputsForCurrentSet()
    }

    private func resetInputsForCurrentSet() {
        guard let setPrescription = viewModel.currentSetPrescription else { return }
        weightText = setPrescription.targetWeight.map { $0.formattedWeight } ?? ""
        // Stage 10R.1D: never prefill the actual-reps input with a
        // fabricated number for an RIR-only (or unresolved-deload)
        // prescription — `repRangeHigh` is only ever non-nil for a
        // genuine fixed-rep target, in which case it's a reasonable
        // starting-point prefill (unchanged from before); otherwise the
        // input starts genuinely unset ("—"), never a visually-meaningful
        // `0`.
        reps = setPrescription.repRangeHigh
        actualRir = setPrescription.targetRir
    }
}
