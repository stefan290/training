import SwiftUI
import SwiftData

/// Functional Fitness execution shells for every typed `WorkoutFormat`
/// (Part J) — AMRAP/EMOM/For Time/Rounds For Time/Chipper/Ladder/Max
/// Load/Max Reps/Intervals — using the existing typed prescription/result
/// shapes, never rebuilding `FunctionalFitnessProgrammingSystem` or
/// parsing a workout string. Large tap targets/readable numbers/minimal
/// keyboard use throughout, per Part O's gym-usability deviation rule.
///
/// Visual Design checkpoint: restyled onto the R1 foundation to match the
/// approved artifact's "Functional fitness" screen (a massive centered
/// monospace timer, an "Each round" movements card, and a Rounds/+reps
/// two-up stat-stepper row) — zero ViewModel/scoring/persistence
/// behavior changed, only presentation. The artifact's Rx-vs-Scaled
/// amber distinction inside the movements card is NOT reproduced here:
/// no scaled/substitution flag is currently exposed to this ViewModel
/// (only the plain prescribed movement line is), so adding that color
/// distinction now would require inventing display data this screen
/// doesn't actually have — flagged as a disclosed gap, not silently
/// skipped.
struct FunctionalFitnessExecutionView: View {
    @Environment(\.modelContext) private var modelContext
    let session: Session
    @State private var viewModel: FunctionalFitnessExecutionViewModel

    @State private var enteringFinalScore = false
    @State private var partialRepsEntry = 0
    @State private var loadEntry = ""
    @State private var repsEntry = 0
    @State private var lastHighlight: LoggedResultHighlight?

    /// Stage FF.E1: every format body's own Finish action produces one of
    /// these instead of calling `viewModel.finish` directly — the single
    /// shared confirmation below is what actually calls `finish`, so there
    /// is exactly one adherence-decision flow and one persistence path
    /// regardless of which of the 8 typed bodies produced the score.
    private struct PendingFinish {
        let scoreValue: ScoreValue
        let completionContext: BlockCompletionContext
    }
    @State private var pendingFinish: PendingFinish?

    init(block: WorkoutBlock, session: Session, executionState: SessionExecutionState) {
        self.session = session
        _viewModel = State(initialValue: FunctionalFitnessExecutionViewModel(block: block, executionState: executionState))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let prescription = viewModel.prescription {
                    header(prescription)

                    if let highlight = lastHighlight {
                        highlightBanner(highlight)
                    }

                    if viewModel.block.status == .completed {
                        completedContent
                    } else {
                        content(for: prescription.format)

                        if !prescription.orderedMovements.isEmpty {
                            movementsCard(prescription)
                        }
                    }
                }
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.ground)
        // Stage V1 R1 nav-bar correction: the format ("AMRAP 12min") is
        // already the huge display headline in the body — the native
        // nav bar title only needs the block-type context, never a
        // duplicate of the exact same string shown prominently below.
        .navigationTitle(BlockPresentation.blockTypeLabel(viewModel.block.type))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            try? CompleteBlockUseCase.start(viewModel.block, modelContext: modelContext)
            if viewModel.block.timerState == nil, let format = viewModel.format {
                startClock(for: format)
            }
        }
        // Stage FF.E1: the ONE shared adherence confirmation, regardless
        // of which typed body produced the pending score. Nothing is
        // persisted until the athlete makes this explicit choice —
        // confirm-then-persist, a single `finish()` call either way.
        // `.unknown` is deliberately not offered here — it is the safe
        // default for legacy/interrupted records, never a normal choice
        // for a newly logged workout.
        .confirmationDialog(
            "Did you follow the workout as prescribed?",
            isPresented: Binding(get: { pendingFinish != nil }, set: { if !$0 { pendingFinish = nil } }),
            titleVisibility: .visible
        ) {
            Button("As Prescribed") { completeFinish(adherence: .asPrescribed) }
            Button("Modified") { completeFinish(adherence: .modified) }
            Button("Cancel", role: .cancel) { pendingFinish = nil }
        }
    }

    /// Cancelling leaves `pendingFinish` cleared and nothing persisted —
    /// the block remains not-yet-completed, exactly as if Finish had never
    /// been tapped, so no completed work can be lost to a dismissed prompt.
    private func completeFinish(adherence: PrescriptionAdherence) {
        guard let pending = pendingFinish else { return }
        let highlight = viewModel.finish(
            scoreValue: pending.scoreValue, completionContext: pending.completionContext,
            benchmark: nil, adherence: adherence, modelContext: modelContext
        )
        lastHighlight = highlight
        pendingFinish = nil
    }

    private func header(_ prescription: FunctionalFitnessPrescription) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(BlockPresentation.formatLabel(prescription.format))
                .font(Theme.headingXL)
                .foregroundStyle(Theme.textPrimary)
            // Stage FF.P1: the athlete-visible concrete prescription
            // (e.g. "12 Wall Ball · 8 Pull-ups · 200 m Row Erg") — the
            // same, already-tested formatting `CompletedFunctionalFitnessDetail`
            // already used, shared rather than duplicated. Display-only;
            // a movement with no FF.P1 target (e.g. Assault Bike) shows
            // only its exercise name, never a fabricated one.
            let lines = prescription.orderedMovements.map(BlockPresentation.prescribedMovementLine)
            if !lines.isEmpty {
                Text(lines.joined(separator: " · "))
                    .font(Theme.numeric)
                    .foregroundStyle(Theme.textMuted)
            }
        }
    }

    private var completedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Result logged")
                .font(Theme.heading)
                .foregroundStyle(Theme.positive)
        }
        .trainingOSCard()
    }

    private func highlightBanner(_ highlight: LoggedResultHighlight) -> some View {
        Text(highlight.isPersonalRecord ? "New personal record: \(highlight.value)"
             : highlight.isFirstEverEntry ? "Baseline established: \(highlight.value)"
             : "Logged: \(highlight.value)")
            .font(Theme.body)
            .foregroundStyle(highlight.isPersonalRecord ? Theme.positive : Theme.textSecondary)
    }

    /// The artifact's own "Each round" movements card — same real
    /// `prescribedMovementLine` data Today/Session Detail already show,
    /// just restyled into the design's bordered surface card.
    private func movementsCard(_ prescription: FunctionalFitnessPrescription) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Each round")
            ForEach(Array(prescription.orderedMovements.enumerated()), id: \.offset) { _, movement in
                Text(BlockPresentation.prescribedMovementLine(movement))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .trainingOSCard()
    }

    private func startClock(for format: WorkoutFormat) {
        switch format {
        case .amrap(let cap):
            try? UpdateBlockTimerUseCase.start(viewModel.block, asOf: Date(), targetDurationSeconds: cap, modelContext: modelContext)
        case .emom, .intervals, .forTime, .chipper, .ladder, .roundsForTime, .maxReps:
            try? UpdateBlockTimerUseCase.start(viewModel.block, asOf: Date(), targetDurationSeconds: capSeconds(for: format), modelContext: modelContext)
        case .maxLoad:
            break
        }
    }

    private func capSeconds(for format: WorkoutFormat) -> Int? {
        switch format {
        case .amrap(let cap): cap
        case .emom(_, let total): total
        case .forTime(let cap): cap
        case .chipper(let cap): cap
        case .ladder(_, let cap): cap
        case .roundsForTime(_, let cap): cap
        case .maxReps(let cap): cap
        case .maxLoad, .intervals: nil
        }
    }

    @ViewBuilder
    private func content(for format: WorkoutFormat) -> some View {
        switch format {
        case .amrap(let cap): amrapBody(capSeconds: cap)
        case .emom: emomBody()
        case .forTime(let cap), .chipper(let cap): runningClockBody(capSeconds: cap, targetRounds: nil)
        case .ladder(_, let cap): runningClockBody(capSeconds: cap, targetRounds: nil)
        case .roundsForTime(let rounds, let cap): runningClockBody(capSeconds: cap, targetRounds: rounds)
        case .maxLoad: maxLoadBody()
        case .maxReps(let cap): maxRepsBody(capSeconds: cap)
        case .intervals(let count, let work, let rest): intervalsBody(count: count, work: work, rest: rest)
        }
    }

    // MARK: AMRAP

    private func amrapBody(capSeconds: Int) -> some View {
        Group {
            if let state = viewModel.block.timerState {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, WorkoutTimer.remainingSeconds(state, asOf: context.date) ?? 0)
                    let expired = WorkoutTimer.isExpired(state, asOf: context.date)
                    VStack(spacing: 18) {
                        timerBlock(phaseLabel: "AMRAP", value: formattedClock(remaining), caption: "\(capSeconds / 60) min AMRAP", expired: expired)

                        TrainingOSStatStepper(
                            label: "Rounds", value: viewModel.roundsCompleted, emphasizePlus: true,
                            onDecrement: { viewModel.decrementRound() }, onIncrement: { viewModel.incrementRound() }
                        )

                        if enteringFinalScore || expired {
                            partialRepsEntryView(onSave: {
                                pendingFinish = PendingFinish(
                                    scoreValue: .roundsAndReps(rounds: viewModel.roundsCompleted, partialReps: partialRepsEntry),
                                    completionContext: .full
                                )
                            })
                        } else {
                            neutralButton("Finish") { enteringFinalScore = true }
                        }
                    }
                }
            }
        }
    }

    // MARK: EMOM

    private func emomBody() -> some View {
        Group {
            if viewModel.block.timerState != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let position = viewModel.emomPosition(asOf: context.date) {
                        let movements = viewModel.prescription?.orderedMovements ?? []
                        let currentName = movements.isEmpty ? nil : movements[position.minuteIndex % movements.count].exercise?.canonicalName
                        let nextName = movements.isEmpty ? nil : movements[(position.minuteIndex + 1) % movements.count].exercise?.canonicalName

                        VStack(spacing: 14) {
                            timerBlock(
                                phaseLabel: "Minute \(position.minuteIndex + 1) of \(position.totalMinutes)",
                                value: formattedClock(position.remaining), caption: currentName.map { "Now: \($0)" } ?? "", expired: false
                            )
                            if let nextName {
                                Text("Next: \(nextName)")
                                    .font(Theme.label)
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            HStack(spacing: 12) {
                                Button("Mark Minute Incomplete") { viewModel.markMinuteIncomplete(asOf: Date()) }
                                    .buttonStyle(.trainingOSSecondary)
                                Spacer()
                                neutralButton("Finish") {
                                    let completed = min(position.minuteIndex + 1, position.totalMinutes)
                                    pendingFinish = PendingFinish(
                                        scoreValue: .completedIntervals(completed),
                                        completionContext: completed >= position.totalMinutes ? .full : .partial
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: For Time / Chipper / Ladder / Rounds For Time

    private func runningClockBody(capSeconds: Int?, targetRounds: Int?) -> some View {
        Group {
            if let state = viewModel.block.timerState {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = WorkoutTimer.elapsedSeconds(state, asOf: context.date)
                    let timeCapped = capSeconds.map { elapsed >= Double($0) } ?? false

                    VStack(spacing: 18) {
                        timerBlock(
                            phaseLabel: "For Time",
                            value: formattedClock(elapsed),
                            caption: capSeconds.map { "cap \(formattedClock(Double($0)))" } ?? "",
                            expired: timeCapped
                        )

                        if let targetRounds {
                            TrainingOSStatStepper(
                                label: "Rounds", value: viewModel.roundsCompleted, emphasizePlus: true,
                                displayValue: { "\($0) / \(targetRounds)" },
                                onDecrement: { viewModel.decrementRound() }, onIncrement: { viewModel.incrementRound() }
                            )
                        }

                        if enteringFinalScore {
                            partialRepsEntryView(onSave: {
                                pendingFinish = PendingFinish(
                                    scoreValue: .roundsAndReps(rounds: viewModel.roundsCompleted, partialReps: partialRepsEntry),
                                    completionContext: .partial
                                )
                            })
                        } else if let targetRounds, viewModel.roundsCompleted >= targetRounds {
                            neutralButton("Finish") {
                                pendingFinish = PendingFinish(scoreValue: .time(seconds: Int(elapsed)), completionContext: .full)
                            }
                        } else if targetRounds == nil {
                            neutralButton("Finish") {
                                pendingFinish = PendingFinish(
                                    scoreValue: .time(seconds: Int(elapsed)), completionContext: timeCapped ? .partial : .full
                                )
                            }
                        } else if timeCapped {
                            neutralButton("Time Cap Reached") { enteringFinalScore = true }
                        }
                    }
                }
            }
        }
    }

    // MARK: Max Load / Max Reps

    private func maxLoadBody() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Load")
            HStack {
                TextField("Load (kg)", text: $loadEntry)
                    .keyboardType(.decimalPad)
                    .font(Theme.numeric.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Save") {
                    guard let kg = Double(loadEntry) else { return }
                    pendingFinish = PendingFinish(scoreValue: .load(kilograms: kg), completionContext: .full)
                }
                .buttonStyle(.trainingOSPrimary)
            }
        }
        .trainingOSCard()
    }

    private func maxRepsBody(capSeconds: Int) -> some View {
        Group {
            if let state = viewModel.block.timerState {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, WorkoutTimer.remainingSeconds(state, asOf: context.date) ?? 0)
                    let expired = WorkoutTimer.isExpired(state, asOf: context.date)
                    VStack(spacing: 18) {
                        timerBlock(phaseLabel: "Max Reps", value: formattedClock(remaining), caption: "cap \(capSeconds / 60) min", expired: expired)

                        if enteringFinalScore || expired {
                            TrainingOSStatStepper(
                                label: "Reps", value: repsEntry,
                                onDecrement: { repsEntry = max(0, repsEntry - 1) }, onIncrement: { repsEntry += 1 }
                            )
                            neutralButton("Save") {
                                pendingFinish = PendingFinish(scoreValue: .repetitions(repsEntry), completionContext: .full)
                            }
                        } else {
                            neutralButton("Finish") { enteringFinalScore = true }
                        }
                    }
                }
            }
        }
    }

    // MARK: FF Intervals

    private func intervalsBody(count: Int, work: Int, rest: Int) -> some View {
        Group {
            if viewModel.block.timerState != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let position = viewModel.intervalsPosition(asOf: context.date) {
                        VStack(spacing: 14) {
                            timerBlock(
                                phaseLabel: position.isWork ? "WORK" : "RECOVERY",
                                value: formattedClock(position.remainingInLegSeconds),
                                caption: "Interval \(position.intervalNumber) of \(count)",
                                expired: false,
                                phaseColor: position.isWork ? Theme.primary : Theme.positive
                            )

                            neutralButton("Finish") {
                                let completed = position.isSessionComplete ? count : position.legIndex / 2
                                pendingFinish = PendingFinish(
                                    scoreValue: .completedIntervals(completed),
                                    completionContext: position.isSessionComplete ? .full : .partial
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Shared presentation

    /// The artifact's own centered phase-label + massive monospace timer
    /// + caption stack — reused by every timed format body. `expired`
    /// drives the same attention-color treatment as the artifact's
    /// `{{ timerColor }}` binding.
    private func timerBlock(phaseLabel: String, value: String, caption: String, expired: Bool, phaseColor: Color = Theme.textSecondary) -> some View {
        VStack(spacing: 6) {
            if !phaseLabel.isEmpty {
                Text(phaseLabel.uppercased())
                    .font(Theme.eyebrow)
                    .tracking(1.4)
                    .foregroundStyle(phaseColor)
            }
            Text(value)
                .font(.system(size: 72, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(expired ? Theme.attention : Theme.textPrimary)
            if !caption.isEmpty {
                Text(caption)
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// The artifact's own "Finish" treatment — a neutral/outlined
    /// full-width button, deliberately distinct from Strength's
    /// accent-filled forward-progress button, since finishing a workout
    /// ends it rather than advancing it. Now the same shared
    /// `TrainingOSSecondaryButtonStyle` every other screen's secondary
    /// action uses, rather than a bespoke local shape.
    private func neutralButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.trainingOSSecondary)
            .frame(maxWidth: .infinity)
    }

    private func partialRepsEntryView(onSave: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            TrainingOSStatStepper(
                label: "+ reps", value: partialRepsEntry,
                onDecrement: { partialRepsEntry = max(0, partialRepsEntry - 1) }, onIncrement: { partialRepsEntry += 1 }
            )
            neutralButton("Save") { onSave() }
        }
    }

    private func formattedClock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
