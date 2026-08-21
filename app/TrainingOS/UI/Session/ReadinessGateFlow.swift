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

    @Environment(\.modelContext) private var modelContext
    @State private var proposal: ReadinessAdaptationProposal?
    @State private var recordedCheckIn: ReadinessCheckIn?
    @State private var warmupSequence: WarmupSequence?

    var body: some View {
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
    }

    private func handleSubmit(_ checkIn: ReadinessCheckIn?) {
        guard let checkIn else {
            proceedToWarmup(checkIn: nil)
            return
        }
        try? RecordReadinessCheckInUseCase.record(checkIn, for: session, modelContext: modelContext)
        let result = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn, modelContext: modelContext)
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
