import SwiftUI

/// Stage 6E: the read-only "what actually happened" view for a
/// completed/skipped/missed/abandoned Session — reached from Today,
/// Week, or Plan, always via `SessionDetailView`'s `SessionDisplayMode`,
/// never a parallel navigation path. Every value here comes from the
/// real persisted `SetResult`/`SteadyStateResult`/`IntervalResult`/
/// `FunctionalFitnessResult` rows — never reconstructed from the current
/// `ProgramDefinition`, which may have changed since this Session ran.
/// This view (and everything it routes to) reads only; there is no
/// `modelContext`, no use-case call, no mutable state anywhere in this
/// tree, by construction.
struct CompletedSessionDetail: View {
    let session: Session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                ForEach(session.orderedBlocks) { block in
                    NavigationLink {
                        destination(for: block)
                    } label: {
                        CompletedBlockRow(block: block)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StatusPill(status: session.status)
                if session.completionContext == .partial {
                    Text("PARTIAL")
                        .font(Theme.label)
                        .foregroundStyle(Theme.attention)
                }
            }
            if let date = session.day?.date {
                Text(date, style: .date)
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
            if let role = session.role {
                Text(SessionPresentation.roleLabel(role))
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func destination(for block: WorkoutBlock) -> some View {
        switch block.blockPrescription {
        case .exercise:
            CompletedStrengthBlockDetail(block: block, session: session)
        case .steadyState:
            CompletedSteadyStateDetail(block: block)
        case .intervals:
            CompletedIntervalDetail(block: block)
        case .functionalFitness:
            CompletedFunctionalFitnessDetail(block: block)
        case nil:
            CompletedBlockPlaceholder(block: block)
        }
    }
}

private struct CompletedBlockRow: View {
    let block: WorkoutBlock

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(block.type.rawValue.uppercased())
                    .font(Theme.label)
                    .foregroundStyle(Theme.primary)
                Text(summary)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            Label(BlockPresentation.statusLabel(block), systemImage: BlockPresentation.statusIcon(block))
                .font(Theme.label)
                .foregroundStyle(BlockPresentation.statusColor(block))
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var summary: String {
        guard case .exercise(let prescriptions) = block.blockPrescription else {
            return BlockPresentation.summary(for: block)
        }
        let completedCount = prescriptions.filter { !$0.loggedSetResults.isEmpty }.count
        if completedCount == prescriptions.count {
            return "\(completedCount) exercise\(completedCount == 1 ? "" : "s") completed"
        }
        return "\(completedCount) of \(prescriptions.count) exercises completed"
    }
}

/// A completed block whose type never populated a typed prescription
/// (the legacy AMRAP/EMOM/For Time path) — shown plainly rather than
/// crashing, mirroring `BlockExecutionPlaceholderView`'s own minimalism.
private struct CompletedBlockPlaceholder: View {
    let block: WorkoutBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(BlockPresentation.statusLabel(block), systemImage: BlockPresentation.statusIcon(block))
                .font(Theme.label)
                .foregroundStyle(BlockPresentation.statusColor(block))
        }
        .padding(16)
        .background(Theme.ground)
        .navigationTitle(block.type.rawValue.uppercased())
        .navigationBarTitleDisplayMode(.inline)
    }
}
