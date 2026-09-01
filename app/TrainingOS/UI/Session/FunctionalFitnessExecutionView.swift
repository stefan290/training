import SwiftUI
import SwiftData

/// Functional Fitness execution shells for every typed `WorkoutFormat`
/// (Part J) — AMRAP/EMOM/For Time/Rounds For Time/Chipper/Ladder/Max
/// Load/Max Reps/Intervals — using the existing typed prescription/result
/// shapes, never rebuilding `FunctionalFitnessProgrammingSystem` or
/// parsing a workout string. Large tap targets/readable numbers/minimal
/// keyboard use throughout, per Part O's gym-usability deviation rule.
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
            VStack(alignment: .leading, spacing: 16) {
                if let prescription = viewModel.prescription {
                    header(prescription)

                    if let highlight = lastHighlight {
                        highlightBanner(highlight)
                    }

                    if viewModel.block.status == .completed {
                        ContentUnavailableView("Result logged", systemImage: "checkmark.circle")
                    } else {
                        content(for: prescription.format)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.ground)
        .navigationTitle(viewModel.prescription.map { BlockPresentation.formatLabel($0.format) } ?? "Functional Fitness")
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
                .font(Theme.heading)
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
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func highlightBanner(_ highlight: LoggedResultHighlight) -> some View {
        Text(highlight.isPersonalRecord ? "New personal record: \(highlight.value)"
             : highlight.isFirstEverEntry ? "Baseline established: \(highlight.value)"
             : "Logged: \(highlight.value)")
            .font(Theme.body)
            .foregroundStyle(highlight.isPersonalRecord ? Theme.positive : Theme.textSecondary)
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
                    VStack(spacing: 14) {
                        Text(formattedClock(remaining))
                            .font(.system(size: 56, design: .monospaced)).bold()
                            .foregroundStyle(expired ? Theme.attention : Theme.textPrimary)
                        Text("\(viewModel.roundsCompleted) rounds")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)

                        if enteringFinalScore || expired {
                            partialRepsEntryView(onSave: {
                                pendingFinish = PendingFinish(
                                    scoreValue: .roundsAndReps(rounds: viewModel.roundsCompleted, partialReps: partialRepsEntry),
                                    completionContext: .full
                                )
                            })
                        } else {
                            Button("+ ROUND") { viewModel.incrementRound() }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.primary)
                                .font(.title2)
                                .frame(maxWidth: .infinity, minHeight: 64)

                            Button("Finish") { enteringFinalScore = true }
                                .buttonStyle(.bordered)
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

                        VStack(spacing: 12) {
                            Text("Minute \(position.minuteIndex + 1) of \(position.totalMinutes)")
                                .font(Theme.label)
                                .foregroundStyle(Theme.textSecondary)
                            if let currentName {
                                Text("Now: \(currentName)")
                                    .font(Theme.heading)
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            Text(formattedClock(position.remaining))
                                .font(.system(size: 48, design: .monospaced)).bold()
                                .foregroundStyle(Theme.textPrimary)
                            if let nextName {
                                Text("Next: \(nextName)")
                                    .font(Theme.body)
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            HStack(spacing: 12) {
                                Button("Mark Minute Incomplete") { viewModel.markMinuteIncomplete(asOf: Date()) }
                                Button("Finish") {
                                    let completed = min(position.minuteIndex + 1, position.totalMinutes)
                                    pendingFinish = PendingFinish(
                                        scoreValue: .completedIntervals(completed),
                                        completionContext: completed >= position.totalMinutes ? .full : .partial
                                    )
                                }
                            }
                            .buttonStyle(.bordered)
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

                    VStack(spacing: 14) {
                        Text(formattedClock(elapsed))
                            .font(.system(size: 48, design: .monospaced)).bold()
                            .foregroundStyle(timeCapped ? Theme.attention : Theme.textPrimary)

                        if let targetRounds {
                            Text("\(viewModel.roundsCompleted) of \(targetRounds) rounds")
                                .font(Theme.body)
                                .foregroundStyle(Theme.textSecondary)
                            if !enteringFinalScore {
                                Button("+ ROUND") { viewModel.incrementRound() }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Theme.primary)
                                    .font(.title2)
                                    .frame(maxWidth: .infinity, minHeight: 64)
                            }
                        }

                        if enteringFinalScore {
                            partialRepsEntryView(onSave: {
                                pendingFinish = PendingFinish(
                                    scoreValue: .roundsAndReps(rounds: viewModel.roundsCompleted, partialReps: partialRepsEntry),
                                    completionContext: .partial
                                )
                            })
                        } else if let targetRounds, viewModel.roundsCompleted >= targetRounds {
                            Button("Finish") {
                                pendingFinish = PendingFinish(scoreValue: .time(seconds: Int(elapsed)), completionContext: .full)
                            }
                            .buttonStyle(.borderedProminent).tint(Theme.primary).frame(maxWidth: .infinity)
                        } else if targetRounds == nil {
                            Button("Finish") {
                                pendingFinish = PendingFinish(
                                    scoreValue: .time(seconds: Int(elapsed)), completionContext: timeCapped ? .partial : .full
                                )
                            }
                            .buttonStyle(.borderedProminent).tint(Theme.primary).frame(maxWidth: .infinity)
                        } else if timeCapped {
                            Button("Time Cap Reached") { enteringFinalScore = true }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    // MARK: Max Load / Max Reps

    private func maxLoadBody() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Load (kg)", text: $loadEntry)
                .keyboardType(.decimalPad)
                .font(Theme.numeric)
            Button("Save") {
                guard let kg = Double(loadEntry) else { return }
                pendingFinish = PendingFinish(scoreValue: .load(kilograms: kg), completionContext: .full)
            }
            .buttonStyle(.borderedProminent).tint(Theme.primary)
        }
        .padding(14)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func maxRepsBody(capSeconds: Int) -> some View {
        Group {
            if let state = viewModel.block.timerState {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, WorkoutTimer.remainingSeconds(state, asOf: context.date) ?? 0)
                    let expired = WorkoutTimer.isExpired(state, asOf: context.date)
                    VStack(spacing: 14) {
                        Text(formattedClock(remaining))
                            .font(.system(size: 56, design: .monospaced)).bold()
                            .foregroundStyle(expired ? Theme.attention : Theme.textPrimary)

                        if enteringFinalScore || expired {
                            Stepper("Reps: \(repsEntry)", value: $repsEntry, in: 0...500)
                            Button("Save") {
                                pendingFinish = PendingFinish(scoreValue: .repetitions(repsEntry), completionContext: .full)
                            }
                            .buttonStyle(.borderedProminent).tint(Theme.primary)
                        } else {
                            Button("Finish") { enteringFinalScore = true }
                                .buttonStyle(.bordered)
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
                        VStack(spacing: 12) {
                            Text(position.isWork ? "WORK" : "RECOVERY")
                                .font(Theme.label)
                                .foregroundStyle(position.isWork ? Theme.primary : Theme.positive)
                            Text("Interval \(position.intervalNumber) of \(count)")
                                .font(Theme.body)
                                .foregroundStyle(Theme.textSecondary)
                            Text(formattedClock(position.remainingInLegSeconds))
                                .font(.system(size: 48, design: .monospaced)).bold()
                                .foregroundStyle(Theme.textPrimary)

                            Button("Finish") {
                                let completed = position.isSessionComplete ? count : position.legIndex / 2
                                pendingFinish = PendingFinish(
                                    scoreValue: .completedIntervals(completed),
                                    completionContext: position.isSessionComplete ? .full : .partial
                                )
                            }
                            .buttonStyle(.borderedProminent).tint(Theme.primary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Shared

    private func partialRepsEntryView(onSave: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Stepper("Extra reps: \(partialRepsEntry)", value: $partialRepsEntry, in: 0...200)
            Button("Save") { onSave() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
                .frame(maxWidth: .infinity)
        }
    }

    private func formattedClock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
