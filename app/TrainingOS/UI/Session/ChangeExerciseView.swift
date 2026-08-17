import SwiftUI
import SwiftData

/// Part E: Change Exercise. Shows only alternatives the originating
/// `ExerciseSlot` actually allows, ranked by history tier (your own
/// history / a related exercise's estimate / calibration required) —
/// never an AI suggestion, never an arbitrary list. `Today Only` edits
/// just this occasion's already-materialized movement; `Going Forward`
/// writes the `ProgramInstance`-level override future materialization
/// will read — the `ProgramDefinition`/template graph itself is never
/// touched by either (`SUBSTITUTION_MODEL.md`).
struct ChangeExerciseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let prescription: ExercisePrescription
    let session: Session

    @State private var candidates: [SubstitutionCandidateRanking.Candidate] = []
    @State private var pendingCandidate: SubstitutionCandidateRanking.Candidate?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if prescription.sourceExerciseSlot == nil {
                    ContentUnavailableView(
                        "Change Exercise isn't available",
                        systemImage: "arrow.triangle.2.circlepath",
                        description: Text("This movement wasn't materialized from a slot, so there's nothing to validate an alternative against.")
                    )
                } else if candidates.isEmpty {
                    ContentUnavailableView("No valid alternatives", systemImage: "questionmark.circle")
                } else {
                    List(candidates) { candidate in
                        Button {
                            pendingCandidate = candidate
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.exercise.canonicalName)
                                    .font(Theme.body)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(tierLabel(candidate.tier))
                                    .font(Theme.label)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Change Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                pendingCandidate.map { "Switch to \($0.exercise.canonicalName)" } ?? "",
                isPresented: Binding(get: { pendingCandidate != nil }, set: { if !$0 { pendingCandidate = nil } }),
                titleVisibility: .visible
            ) {
                Button("Today Only") { apply(scope: .todayOnly) }
                if session.programInstance != nil {
                    Button("Going Forward") { apply(scope: .goingForward) }
                }
                Button("Cancel", role: .cancel) { pendingCandidate = nil }
            }
            .alert("Couldn't change exercise", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .task { loadCandidates() }
    }

    private enum Scope { case todayOnly, goingForward }

    private func loadCandidates() {
        guard let slot = prescription.sourceExerciseSlot, let current = prescription.exercise else {
            candidates = []
            return
        }
        let allExercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        let relationships = (try? modelContext.fetch(FetchDescriptor<ExerciseRelationship>())) ?? []
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        let performanceProfile = users.first?.performanceProfile

        candidates = SubstitutionCandidateRanking.rank(
            slot: slot,
            excluding: current,
            allExercises: allExercises,
            curatedRelationships: relationships,
            profileLookup: { performanceProfile?.profile(for: $0) }
        )
    }

    private func apply(scope: Scope) {
        guard let candidate = pendingCandidate, let slot = prescription.sourceExerciseSlot else { return }
        do {
            switch scope {
            case .todayOnly:
                try ApplySubstitutionUseCase.substituteExerciseThisSessionOnly(
                    prescription: prescription, slot: slot, with: candidate.exercise,
                    reason: .userExerciseSubstitution, modelContext: modelContext
                )
            case .goingForward:
                guard let instance = session.programInstance else { return }
                try ApplySubstitutionUseCase.substituteExerciseGoingForward(
                    instance: instance, slot: slot, with: candidate.exercise,
                    reason: .userExerciseSubstitution, modelContext: modelContext
                )
            }
            pendingCandidate = nil
            dismiss()
        } catch {
            errorMessage = "\(error)"
            pendingCandidate = nil
        }
    }

    private func tierLabel(_ tier: ProgressionReasonCode) -> String {
        switch tier {
        case .percentageOfEstimate: "Your history"
        case .substitutionEstimate: "Estimated from a related exercise"
        default: "Calibration required — no usable history yet"
        }
    }
}
