import SwiftUI
import SwiftData

/// Stage 8B: the recommendation screen — shown only when
/// `EvaluateReadinessAdaptationUseCase` produced a non-empty proposal
/// (`READINESS_UX_FLOW.md` §3). Every item always shows original vs.
/// proposed side by side; nothing is applied until the user has answered
/// every item (no partial auto-apply while still on this screen).
struct ReadinessAdaptationProposalView: View {
    let session: Session
    let checkIn: ReadinessCheckIn
    let proposal: ReadinessAdaptationProposal
    let onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var index = 0

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                if let item = currentItem {
                    Text("\(index + 1) of \(proposal.items.count)")
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)

                    Text(item.explanation)
                        .font(Theme.body)
                        .foregroundStyle(Theme.textPrimary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Original")
                            .font(Theme.label)
                            .foregroundStyle(Theme.textSecondary)
                        Text(originalDescription(item))
                            .font(Theme.body)
                        Text("Proposed")
                            .font(Theme.label)
                            .foregroundStyle(Theme.textSecondary)
                        Text(proposedDescription(item))
                            .font(Theme.body)
                            .foregroundStyle(Theme.primary)
                    }
                    .padding(12)
                    .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))

                    VStack(spacing: 10) {
                        Button("Accept") { respond(item, accept: true) }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.primary)
                            .frame(maxWidth: .infinity)
                        Button("Keep original") { respond(item, accept: false) }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                    }
                }
                Spacer()
            }
            .padding(16)
            .background(Theme.ground)
            .navigationTitle("Today's Adjustments")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var currentItem: ReadinessAdaptationProposalItem? {
        proposal.items.indices.contains(index) ? proposal.items[index] : nil
    }

    private func originalDescription(_ item: ReadinessAdaptationProposalItem) -> String {
        if let count = item.originalSetCount { return "\(count) sets" }
        if let exercise = item.originalExercise { return exercise.canonicalName }
        if item.actionKind == .blockRemoved { return "As scheduled" }
        if item.actionKind == .postponeRecommended { return "Train today" }
        return "As prescribed"
    }

    private func proposedDescription(_ item: ReadinessAdaptationProposalItem) -> String {
        if let count = item.proposedSetCount { return "\(count) sets" }
        if let exercise = item.proposedExercise { return exercise.canonicalName }
        if item.actionKind == .blockRemoved { return "Remove this block today" }
        if item.actionKind == .postponeRecommended { return "Postpone / skip today" }
        return "No change"
    }

    private func respond(_ item: ReadinessAdaptationProposalItem, accept: Bool) {
        try? accept
            ? ReadinessAdaptationDecisionUseCase.accept(item, session: session, checkIn: checkIn, decidedAt: Date(), modelContext: modelContext)
            : ReadinessAdaptationDecisionUseCase.reject(item, checkIn: checkIn, decidedAt: Date(), modelContext: modelContext)

        if index + 1 < proposal.items.count {
            index += 1
        } else {
            onDone()
        }
    }
}
