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
///
/// Visual Design checkpoint: restyled onto the R1 foundation to match the
/// approved artifact's "Strength workout" screen (large exercise display,
/// dot-segment progress, an accent-tinted Suggested Load card with a real
/// "Why?" disclosure of `LoadOverlayReasonCode`, and pill-style kg/reps/RIR
/// controls) — zero ViewModel/domain behavior changed, only presentation.
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
    @State private var showingWhy = false
    /// Stage 10R.5: the effective (possibly overlay-adjusted) load for
    /// the current exposure — computed once per movement in
    /// `resetInputsForCurrentSet`, never inside `body`, since computing
    /// it has a real side effect (freezing the recommendation onto
    /// `ExercisePrescription` the first time, D-10R5-19).
    @State private var effectiveTargetWeight: Double?

    init(block: WorkoutBlock, session: Session, executionState: SessionExecutionState) {
        _viewModel = State(initialValue: StrengthExecutionViewModel(block: block))
        self.session = session
        self.executionState = executionState
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                progressHeader

                if viewModel.isBlockComplete {
                    blockCompleteContent
                } else if let movement = viewModel.currentMovement, let exercise = movement.exercise {
                    header(exercise: exercise)

                    if effectiveTargetWeight != nil || !viewModel.previousResults.isEmpty {
                        suggestedLoadCard(movement: movement)
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
            .padding(Theme.screenPadding)
        }
        .background(Theme.ground)
        // Stage V1 R1 nav-bar correction: the exercise name already
        // carries its own huge display treatment in the body — the
        // native nav bar title only needs the block-type context
        // ("Strength"/"Hypertrophy"/"Accessory"), never a duplicate of
        // the exact same string the body already shows prominently.
        .navigationTitle(BlockPresentation.blockTypeLabel(viewModel.block.type))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingChangeExercise, onDismiss: { viewModel.loadPreviousPerformance(modelContext: modelContext) }) {
            if let movement = viewModel.currentMovement {
                ChangeExerciseView(prescription: movement, session: session)
            }
        }
        .sheet(isPresented: $showingWhy) {
            if let movement = viewModel.currentMovement {
                whySheet(movement: movement)
            }
        }
        .task {
            try? CompleteBlockUseCase.start(viewModel.block, modelContext: modelContext)
            viewModel.loadPreviousPerformance(modelContext: modelContext)
            resetInputsForCurrentSet()
        }
    }

    /// Part H: position + lightweight overall progress — a dot-segment
    /// bar (the artifact's own recurring block-position treatment)
    /// alongside the same two real numbers the kickoff's own example
    /// shows, never a dashboard.
    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.movementCount > 1 {
                HStack(spacing: 4) {
                    ForEach(0..<viewModel.movementCount, id: \.self) { index in
                        Capsule()
                            .fill(segmentColor(for: index))
                            .frame(height: 3)
                    }
                }
            }
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

    private func segmentColor(for index: Int) -> Color {
        if index < viewModel.movementIndex { return Theme.positive }
        if index == viewModel.movementIndex { return Theme.primary }
        return Theme.textInactive.opacity(0.3)
    }

    /// Part J: every prescribed movement is satisfied, so the block has
    /// already auto-transitioned to `.completed`
    /// (`StrengthExecutionViewModel.logCurrentSet`) — this just reflects
    /// that back and returns the user to Session Detail, where "Finish
    /// Session" is now the correct normal action, never "Finish as
    /// Partial" for genuinely full work (Part L).
    private var blockCompleteContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Strength block complete")
                .font(Theme.heading)
                .foregroundStyle(Theme.textPrimary)
            Button("Return to Session") { dismiss() }
                .buttonStyle(.trainingOSPrimary)
                .frame(maxWidth: .infinity)
        }
        .trainingOSCard(emphasized: true)
    }

    /// Part F: shown the instant the current exercise's last set is
    /// logged — names the next exercise so the forward path is obvious,
    /// without requiring the user to back out to Session Detail first.
    private var exerciseCompleteContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exercise complete")
                .font(Theme.heading)
                .foregroundStyle(Theme.positive)
            if let nextName = viewModel.nextMovementName {
                Text("Next: \(nextName)")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .trainingOSCard()
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
                    .buttonStyle(.trainingOSSecondary)
            }
            Spacer()
            if viewModel.hasNextMovement {
                if viewModel.isMovementComplete {
                    Button("Next Exercise") { advance(.next) }
                        .buttonStyle(.trainingOSPrimary)
                } else {
                    Button("Next Exercise") { advance(.next) }
                        .buttonStyle(.trainingOSSecondary)
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
            Button("Substitute") { showingChangeExercise = true }
                .font(Theme.label)
                .foregroundStyle(Theme.primary)
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
                .font(Theme.headingXL)
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
                    .font(Theme.numeric)
                    .foregroundStyle(Theme.textSecondary)
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

    /// The artifact's own accent-tinted "Suggested" callout, paired with
    /// real "Last time" history and a real "Why?" disclosure of the
    /// engine's own already-computed `LoadOverlayReasonCode` — never a
    /// second recommendation surface, purely a restyle of the same real
    /// `effectiveTargetWeight`/`previousResults` this screen already had.
    private func suggestedLoadCard(movement: ExercisePrescription) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if let target = effectiveTargetWeight {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SUGGESTED")
                        .font(Theme.eyebrow)
                        .tracking(1.2)
                        .foregroundStyle(Theme.primary)
                    Text("\(target.formattedWeight) kg")
                        .font(Theme.numeric.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            if effectiveTargetWeight != nil && !viewModel.previousResults.isEmpty {
                Divider()
            }
            if !viewModel.previousResults.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LAST TIME")
                        .font(Theme.eyebrow)
                        .tracking(1.2)
                        .foregroundStyle(Theme.textSecondary)
                    Text(previousResultsSummary)
                        .font(Theme.label)
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if movement.appliedLoadOverlayReasonCode != nil {
                Button {
                    showingWhy = true
                } label: {
                    Text("Why?")
                        .font(Theme.label)
                        .foregroundStyle(Theme.primary)
                }
            }
        }
        .trainingOSCard(emphasized: true)
    }

    private var previousResultsSummary: String {
        viewModel.previousResults.map { "\($0.weight.formattedWeight)×\($0.reps)" }.joined(separator: " · ")
    }

    /// A real disclosure of why today's suggested load is what it is —
    /// translates the engine's own already-computed, already-persisted
    /// `LoadOverlayReasonCode` (`SessionPresentation.loadOverlayReasonLabel`)
    /// alongside the real prescription/previous-performance data already
    /// on screen. Never a new recommendation, never new business logic —
    /// purely a readable restatement of a real, existing decision.
    private func whySheet(movement: ExercisePrescription) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(Theme.textInactive.opacity(0.5)).frame(width: 38, height: 4).frame(maxWidth: .infinity)
            Text("WHY THIS LOAD")
                .font(Theme.eyebrow)
                .tracking(1.4)
                .foregroundStyle(Theme.textSecondary)
            if let code = movement.appliedLoadOverlayReasonCode {
                Text(SessionPresentation.loadOverlayReasonLabel(code))
                    .font(Theme.heading)
                    .foregroundStyle(Theme.textPrimary)
            }
            Divider()
            if let setPrescription = viewModel.currentSetPrescription {
                dataRow("Prescription", StrengthSetPresentation.targetText(
                    repRangeLow: setPrescription.repRangeLow, repRangeHigh: setPrescription.repRangeHigh, targetRir: setPrescription.targetRir
                ))
            }
            if !viewModel.previousResults.isEmpty {
                dataRow("Previous", previousResultsSummary)
            }
            Spacer()
        }
        .padding(Theme.screenPadding)
        .presentationDetents([.medium])
        .background(Theme.surfaceSecondary)
    }

    private func dataRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Theme.label).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(Theme.numeric).foregroundStyle(Theme.textPrimary)
        }
    }

    /// The artifact's own kg/reps/RIR pill-stepper layout — same real
    /// bindings/logging as before (`weightText`/`repsStepperBinding`/
    /// `actualRir`/`logSet()`), only the presentation is new.
    private var currentSetCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SET \(viewModel.currentSetIndex + 1)")
                .font(Theme.eyebrow)
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 8) {
                statField(label: "kg") {
                    TextField("Weight", text: $weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(Theme.numeric.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                statField(label: "reps") {
                    Stepper(value: repsStepperBinding, in: 0...50) { EmptyView() }
                        .labelsHidden()
                        .overlay(
                            Text(reps.map { "\($0)" } ?? "—")
                                .font(Theme.numeric.weight(.bold))
                                .foregroundStyle(Theme.textPrimary)
                                .allowsHitTesting(false)
                                .accessibilityLabel(StrengthSetPresentation.actualRepsLabel(reps))
                        )
                }
                VStack(spacing: 7) {
                    Text("RIR")
                        .font(Theme.label)
                        .tracking(1.0)
                        .foregroundStyle(Theme.textSecondary)
                    Menu {
                        ForEach(0...4, id: \.self) { value in
                            Button(value == 4 ? "4+" : "\(value)") { actualRir = value }
                        }
                    } label: {
                        Text(actualRir.map { $0 == 4 ? "4+" : "\($0)" } ?? "—")
                            .font(Theme.numeric.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                .frame(width: 62)
                .padding(.vertical, 8)
                .background(Theme.ground, in: RoundedRectangle(cornerRadius: 10))
            }

            Button("Log Set") { logSet() }
                .buttonStyle(.trainingOSPrimary)
                .frame(maxWidth: .infinity)
                .disabled(Double(weightText) == nil)
        }
        .trainingOSCard()
    }

    private func statField<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 7) {
            Text(label)
                .font(Theme.label)
                .tracking(1.0)
                .foregroundStyle(Theme.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 10))
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
        effectiveTargetWeight = viewModel.effectiveTargetWeight(modelContext: modelContext)
        weightText = (effectiveTargetWeight ?? setPrescription.targetWeight).map { $0.formattedWeight } ?? ""
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
