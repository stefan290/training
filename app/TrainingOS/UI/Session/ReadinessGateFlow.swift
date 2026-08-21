import SwiftUI
import SwiftData

/// Stage 8B: the view-layer gate shown before the existing Start
/// transition fires — `READINESS_ADAPTATION_PIPELINE.md` §0/§1. Owns the
/// step sequence (check-in → evaluate → optional recommendation screen)
/// and calls `onFinished` exactly once, after which the caller runs the
/// existing, unchanged `StartSessionUseCase` transition. Never itself
/// starts the Session — that stays the caller's job.
struct ReadinessGateFlow: View {
    let session: Session
    let onFinished: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var proposal: ReadinessAdaptationProposal?
    @State private var recordedCheckIn: ReadinessCheckIn?

    var body: some View {
        Group {
            if let proposal, let recordedCheckIn, !proposal.isEmpty {
                ReadinessAdaptationProposalView(session: session, checkIn: recordedCheckIn, proposal: proposal, onDone: onFinished)
            } else {
                ReadinessCheckInView(session: session, onSubmit: handleSubmit)
            }
        }
    }

    private func handleSubmit(_ checkIn: ReadinessCheckIn?) {
        guard let checkIn else {
            onFinished()
            return
        }
        try? RecordReadinessCheckInUseCase.record(checkIn, for: session, modelContext: modelContext)
        let result = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn, modelContext: modelContext)
        if result.isEmpty {
            onFinished()
        } else {
            recordedCheckIn = checkIn
            proposal = result
        }
    }
}
