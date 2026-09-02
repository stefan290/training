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
    /// TE.1 closure: `SubstitutionCandidateRanking.rank` already excludes
    /// every candidate `TrainingEnvironmentCompatibilityRule` can't prove
    /// `.compatible` — with no environment configured, `.environmentUnknown`
    /// excludes everything, so `candidates.isEmpty` alone reads as a plain
    /// "nothing fits," not "you haven't told us what you have." Tracked
    /// separately so the empty state can offer the real recovery path
    /// instead of a generic dead end.
    @State private var hasNoTrainingEnvironmentConfigured = false
    /// TE.1 final UX closure: `true` only when a real environment IS
    /// configured, `candidates` is still empty, AND at least one real
    /// candidate satisfies every OTHER (non-equipment) constraint on this
    /// slot — i.e. the reason nothing shows is specifically a missing-
    /// equipment conflict, not "no candidate exists for this slot at
    /// all." Computed via the same `SubstitutionValidator
    /// .matchesSemanticConstraints` probe `ResolveProgramInstanceExerciseSlotsUseCase`
    /// uses to attribute the identical distinction — never a second,
    /// divergent definition of "semantically eligible." When this is
    /// `false` and `candidates` is empty with a real environment
    /// configured, the existing plain "No valid alternatives" empty state
    /// is correct and must not be relabeled as an environment problem.
    @State private var hasOnlyEquipmentIncompatibleCandidates = false
    @State private var showingTrainingEnvironmentSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if prescription.sourceExerciseSlot == nil {
                    ContentUnavailableView(
                        "Change Exercise isn't available",
                        systemImage: "arrow.triangle.2.circlepath",
                        description: Text("This movement wasn't materialized from a slot, so there's nothing to validate an alternative against.")
                    )
                } else if candidates.isEmpty && hasNoTrainingEnvironmentConfigured {
                    ContentUnavailableView {
                        Label("No Training Environment Configured", systemImage: "questionmark.circle")
                    } description: {
                        Text("Alternatives can't be checked against your available equipment yet.")
                    } actions: {
                        Button("Configure Training Environment") {
                            showingTrainingEnvironmentSettings = true
                        }
                    }
                } else if candidates.isEmpty && hasOnlyEquipmentIncompatibleCandidates {
                    ContentUnavailableView {
                        Label("Missing Equipment", systemImage: "questionmark.circle")
                    } description: {
                        Text("A valid alternative exists but isn't available in your configured Training Environment.")
                    } actions: {
                        Button("Configure Training Environment") {
                            showingTrainingEnvironmentSettings = true
                        }
                    }
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
            .sheet(isPresented: $showingTrainingEnvironmentSettings, onDismiss: loadCandidates) {
                TrainingEnvironmentSettingsView()
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

        let environment = currentTrainingEnvironment()
        hasNoTrainingEnvironmentConfigured = (environment == nil)
        candidates = SubstitutionCandidateRanking.rank(
            slot: slot,
            excluding: current,
            allExercises: allExercises,
            curatedRelationships: relationships,
            profileLookup: { performanceProfile?.profile(for: $0) },
            environment: environment
        )

        // TE.1 final UX closure: only probed when a real environment
        // exists and the equipment-aware pool above came back empty —
        // this never runs merely to double-check a non-empty result, and
        // never changes what `candidates` itself contains.
        if environment != nil, candidates.isEmpty {
            let semanticallyEligible = allExercises.filter {
                $0.id != current.id && SubstitutionValidator.matchesSemanticConstraints(candidate: $0, for: slot)
            }
            hasOnlyEquipmentIncompatibleCandidates = !semanticallyEligible.isEmpty
        } else {
            hasOnlyEquipmentIncompatibleCandidates = false
        }
    }

    private func currentTrainingEnvironment() -> TrainingEnvironment? {
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        return users.first?.profile?.defaultTrainingEnvironment
    }

    private func apply(scope: Scope) {
        guard let candidate = pendingCandidate, let slot = prescription.sourceExerciseSlot else { return }
        do {
            let environment = currentTrainingEnvironment()
            switch scope {
            case .todayOnly:
                try ApplySubstitutionUseCase.substituteExerciseThisSessionOnly(
                    prescription: prescription, slot: slot, with: candidate.exercise,
                    reason: .userExerciseSubstitution, environment: environment, modelContext: modelContext
                )
            case .goingForward:
                guard let instance = session.programInstance else { return }
                try ApplySubstitutionUseCase.substituteExerciseGoingForward(
                    instance: instance, slot: slot, with: candidate.exercise,
                    reason: .userExerciseSubstitution, environment: environment, modelContext: modelContext
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
