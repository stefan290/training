import SwiftUI
import SwiftData

/// Stage 8B/9B: the view-layer gate shown before the existing Start
/// transition fires — `READINESS_ADAPTATION_PIPELINE.md` §0/§1. Owns the
/// step sequence (check-in → evaluate → optional recommendation screen
/// → Stage 9B warm-up) and calls `onFinished` exactly once, after which
/// the caller runs the existing, unchanged `StartSessionUseCase`
/// transition. Never itself starts the Session — that stays the
/// caller's job.
///
/// Stage 9B ordering requirement: warm-up generation runs strictly
/// AFTER the adaptation step resolves (whether accepted, rejected, or
/// never needed), reading `session` at that point — which already IS
/// the final executable workout, since Stage 8B mutates prescriptions in
/// place rather than producing a separate copy
/// (`STAGE9_WARMUP_DESIGN.md` §2 Q5).
struct ReadinessGateFlow: View {
    let session: Session
    let onFinished: () -> Void
    /// Dogfood Round 2 (Finding G): this whole gate is presented via a
    /// `fullScreenCover`, which — unlike a `.sheet` — has no free system
    /// swipe-to-dismiss gesture. Every one of the 3 steps below used to
    /// have no way out at all: the athlete could only ever move forward,
    /// never back out of a workout they hadn't started yet. `onCancel`
    /// leaves the Session exactly as it was (still `.scheduled` —
    /// `StartSessionUseCase` never having run), never a partial/aborted
    /// state, since nothing here has mutated the Session itself yet.
    let onCancel: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var proposal: ReadinessAdaptationProposal?
    @State private var recordedCheckIn: ReadinessCheckIn?
    @State private var warmupSequence: WarmupSequence?

    var body: some View {
        NavigationStack {
            Group {
                if let warmupSequence {
                    WarmupView(sequence: warmupSequence, onDone: onFinished)
                } else if let proposal, let recordedCheckIn, !proposal.isEmpty {
                    ReadinessAdaptationProposalView(
                        session: session, checkIn: recordedCheckIn, proposal: proposal,
                        onDone: { proceedToWarmup(checkIn: recordedCheckIn) }
                    )
                } else {
                    ReadinessCheckInView(session: session, onSubmit: handleSubmit)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    private func handleSubmit(_ checkIn: ReadinessCheckIn?) {
        guard let checkIn else {
            proceedToWarmup(checkIn: nil)
            return
        }
        try? RecordReadinessCheckInUseCase.record(checkIn, for: session, modelContext: modelContext)
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        let environment = users.first?.profile?.defaultTrainingEnvironment
        let result = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn, environment: environment, modelContext: modelContext)
        if result.isEmpty {
            proceedToWarmup(checkIn: checkIn)
        } else {
            recordedCheckIn = checkIn
            proposal = result
        }
    }

    /// Generates the warm-up from the session as it stands right now —
    /// the final executable workout, whether or not readiness was
    /// answered or an adaptation was accepted/rejected. `nil` (no
    /// in-scope modality, or nothing safe/relevant survives) skips
    /// straight to `onFinished` without ever showing a warm-up screen.
    private func proceedToWarmup(checkIn: ReadinessCheckIn?) {
        let context = WarmupGenerationContext(executableWorkout: session, readiness: checkIn)
        if let sequence = GenerateWarmupSequenceUseCase.generate(context: context, modelContext: modelContext) {
            try? RecordWarmupSequenceUseCase.record(sequence, for: session, modelContext: modelContext)
            warmupSequence = sequence
        } else {
            onFinished()
        }
    }
}
