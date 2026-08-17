import SwiftUI

/// Stage 6E: the completed-history list of exercises inside one Strength
/// block — read-only, no Log Set/Start/Resume anywhere in this tree.
struct CompletedStrengthBlockDetail: View {
    let block: WorkoutBlock
    let session: Session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(block.orderedPrescriptions) { prescription in
                    NavigationLink {
                        CompletedExerciseDetail(prescription: prescription, session: session)
                    } label: {
                        row(prescription)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Theme.ground)
        .navigationTitle("Strength")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ prescription: ExercisePrescription) -> some View {
        let results = prescription.loggedSetResults.sorted { $0.setIndex < $1.setIndex }
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(prescription.exercise?.canonicalName ?? "Exercise")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                Text(results.isEmpty ? "Not completed" : "\(results.count) set\(results.count == 1 ? "" : "s") logged")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if results.contains(where: { $0.isPersonalRecord }) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(Theme.attention)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Stage 6E: one completed exercise's PRESCRIBED-vs-PERFORMED detail —
/// the load-bearing screen this whole pass exists for. Read-only: no
/// `modelContext`, no Log Set button, no Start/Resume button.
struct CompletedExerciseDetail: View {
    let prescription: ExercisePrescription
    let session: Session

    private var results: [SetResult] {
        prescription.loggedSetResults.sorted { $0.setIndex < $1.setIndex }
    }

    /// The slot's own authoring-time default — reliable as "what was
    /// originally prescribed" in the common single-substitution case.
    /// Known, disclosed narrow gap: if a GOING FORWARD override was
    /// active at materialization time *and* a THIS-SESSION-ONLY
    /// substitution happened on top of it, this shows the template's
    /// default rather than that specific override — an edge case, not the
    /// common path, and not something this pass invents new schema to
    /// close (`STAGE6E_ACCEPTANCE_REPORT.md`).
    private var originallyPrescribedExercise: Exercise? {
        prescription.sourceExerciseSlot?.resolvedExercise
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if prescription.substitutionUsed,
                   let original = originallyPrescribedExercise,
                   original.id != prescription.exercise?.id {
                    substitutionNotice(original: original)
                }

                prescribedSection
                performedSection
                feedbackSection
                nextTimeSection
            }
            .padding(16)
        }
        .background(Theme.ground)
        .navigationTitle(prescription.exercise?.canonicalName ?? "Exercise")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func substitutionNotice(original: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SUBSTITUTED")
                .font(Theme.label)
                .foregroundStyle(Theme.attention)
            Text("Prescribed: \(original.canonicalName)")
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            Text("Performed: \(prescription.exercise?.canonicalName ?? "—")")
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var prescribedSection: some View {
        let sets = prescription.orderedSetPrescriptions
        let first = sets.first
        let repsLabel = first.map { $0.repRangeLow == $0.repRangeHigh ? "\($0.repRangeLow)" : "\($0.repRangeLow)-\($0.repRangeHigh)" }
        let rirLabel = first?.targetRir.map { " @ \($0) RIR" } ?? ""

        return VStack(alignment: .leading, spacing: 4) {
            Text("PRESCRIBED")
                .font(Theme.label)
                .foregroundStyle(Theme.primary)
            if let repsLabel {
                Text("\(sets.count) \u{d7} \(repsLabel)\(rirLabel)")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
            }
            if let weight = first?.targetWeight {
                Text("Suggested load \(weight.formattedWeight) kg")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var performedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PERFORMED")
                .font(Theme.label)
                .foregroundStyle(Theme.primary)
            if results.isEmpty {
                Text("Not completed")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(results, id: \.id) { result in
                    resultRow(result)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func resultRow(_ result: SetResult) -> some View {
        HStack {
            Text("Set \(result.setIndex + 1)")
                .font(Theme.label)
                .foregroundStyle(Theme.textSecondary)
            Text("\(result.weight.formattedWeight) \u{d7} \(result.reps)\(result.actualRir.map { " @ \($0)" } ?? "")")
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            if result.isPersonalRecord {
                Spacer()
                Text(prBadgeText(for: result))
                    .font(Theme.label)
                    .foregroundStyle(Theme.attention)
            }
        }
    }

    private func prBadgeText(for result: SetResult) -> String {
        guard let record = result.personalRecord, let profile = result.exercisePerformanceProfile,
              !CompletedResultPresentation.isFirstEverEntry(record, in: profile) else {
            return "First recorded"
        }
        return "Personal record!"
    }

    /// Point 5/6: the recorded autoregulation rating for THIS exercise
    /// (if it's the one some other slot's set count depends on), plus —
    /// derivable without fabricating an exact future number — which
    /// *other* exercise's next-week volume it will affect and in which
    /// direction.
    @ViewBuilder
    private var feedbackSection: some View {
        if let rating = prescription.autoregulationRating {
            let system = HypertrophyFeedbackCopy.programmingSystem(for: prescription)
            let label = HypertrophyFeedbackCopy.label(forRating: rating, system: system) ?? "Rating: \(rating)"
            let dependents = prescription.sourcePrescriptionTemplate?.referencedAsPairedSlotBy ?? []

            VStack(alignment: .leading, spacing: 4) {
                Text("TRAINING FEEDBACK")
                    .font(Theme.label)
                    .foregroundStyle(Theme.primary)
                Text(label)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
                ForEach(dependents, id: \.id) { dependent in
                    if let name = dependent.exerciseSlot?.resolvedExercise?.canonicalName ?? dependent.exerciseSlot?.name {
                        Text("This will \(direction(for: rating)) next time's \(name) volume.")
                            .font(Theme.label)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 10))
        } else {
            EmptyView()
        }
    }

    private func direction(for rating: Int) -> String {
        rating > 0 ? "increase" : (rating < 0 ? "decrease" : "hold steady")
    }

    /// Point 6: "why is this week's own set count what it is" (a real,
    /// already-applied decision — `appliedSetCountReasonCode` — not a
    /// future one), plus the next-*load* recommendation, recomputed
    /// on-demand from the pure, idempotent `CompleteSessionUseCase.
    /// progressionPreview` using this exercise's own already-logged
    /// results. Never a fabricated future `ExercisePrescription`.
    @ViewBuilder
    private var nextTimeSection: some View {
        let setCountReason = prescription.appliedSetCountReasonCode.flatMap(StrengthReasonCodePresentation.setCountReasonText)
        let loadPreview = CompleteSessionUseCase.progressionPreview(for: session, userProfile: nil)
            .first { $0.exerciseName == prescription.exercise?.canonicalName }

        if setCountReason != nil || loadPreview != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("NEXT TIME")
                    .font(Theme.label)
                    .foregroundStyle(Theme.primary)
                if let setCountReason {
                    Text(setCountReason)
                        .font(Theme.body)
                        .foregroundStyle(Theme.textPrimary)
                }
                if let loadPreview {
                    if let weight = loadPreview.recommendedWeight {
                        Text("\(weight.formattedWeight) kg")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Text(loadPreview.inputsSummary)
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 10))
        } else {
            EmptyView()
        }
    }
}
