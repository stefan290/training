import SwiftUI

/// Stage 6E: read-only completed detail for a `.functionalFitness` block
/// — prescribed workout, each movement's actual performed/scaled variant
/// (`FunctionalFitnessPerformedMovement.prescribedMovement` is never
/// mutated to represent scaling, so the original is always still here),
/// final score, prescription adherence (Stage FF.E1), and benchmark/PR
/// context.
struct CompletedFunctionalFitnessDetail: View {
    let block: WorkoutBlock

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let prescription = block.functionalFitnessPrescription {
                    prescribedSection(prescription)
                }
                performedSection
            }
            .padding(16)
        }
        .background(Theme.ground)
        .navigationTitle("Functional Fitness")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func prescribedSection(_ prescription: FunctionalFitnessPrescription) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PRESCRIBED")
                .font(Theme.label)
                .foregroundStyle(Theme.primary)
            Text(BlockPresentation.formatLabel(prescription.format))
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            ForEach(Array(prescription.orderedMovements.enumerated()), id: \.offset) { _, movement in
                Text(BlockPresentation.prescribedMovementLine(movement))
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var performedSection: some View {
        if let result = block.functionalFitnessResult {
            VStack(alignment: .leading, spacing: 10) {
                Text("PERFORMED")
                    .font(Theme.label)
                    .foregroundStyle(Theme.primary)

                HStack {
                    Text(formattedScore(result.scoreValue))
                        .font(Theme.heading)
                        .foregroundStyle(Theme.textPrimary)
                    Text(adherenceLabel(result.adherence))
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                }

                ForEach(result.orderedPerformedMovements, id: \.id) { movement in
                    performedMovementRow(movement)
                }

                if let benchmark = result.benchmark {
                    Text("Benchmark: \(benchmark.name)")
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                }
                if result.personalRecord != nil {
                    Text("Personal record!")
                        .font(Theme.label)
                        .foregroundStyle(Theme.attention)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
        } else {
            Text("Not completed")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func performedMovementRow(_ movement: FunctionalFitnessPerformedMovement) -> some View {
        let prescribedName = movement.prescribedMovement?.exercise?.canonicalName ?? "Movement"
        let performedName = movement.performedExercise?.canonicalName

        return VStack(alignment: .leading, spacing: 2) {
            if let performedName, performedName != prescribedName {
                Text("Prescribed: \(prescribedName)")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
                Text("Performed: \(performedName)")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
            } else {
                Text(prescribedName)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
            }
            HStack(spacing: 8) {
                if let reps = movement.performedReps { Text("\(reps) reps") }
                if let calories = movement.performedCalories { Text("\(calories) cal") }
                if let distance = movement.performedDistanceMeters { Text("\(Int(distance)) m") }
                if let load = movement.performedLoadKilograms { Text("\(load.formattedWeight) kg") }
            }
            .font(Theme.label)
            .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Stage FF.E1: displays `adherence`, not `resultContext` — the
    /// latter defaults `.rx` unconditionally on every real Functional
    /// Fitness result and was never actually confirmed by the athlete
    /// (`FUNCTIONAL_FITNESS_EXECUTION_TRUTH_DESIGN.md`). A legacy record
    /// therefore truthfully shows "Unknown," never a false "As prescribed."
    private func adherenceLabel(_ adherence: PrescriptionAdherence) -> String {
        switch adherence {
        case .asPrescribed: "As prescribed"
        case .modified: "Modified"
        case .unknown: "Unknown"
        }
    }

    private func formattedScore(_ value: ScoreValue) -> String {
        switch value {
        case .time(let seconds): String(format: "%d:%02d", seconds / 60, seconds % 60)
        case .roundsAndReps(let rounds, let partialReps): partialReps > 0 ? "\(rounds) rounds + \(partialReps)" : "\(rounds) rounds"
        case .repetitions(let reps): "\(reps) reps"
        case .calories(let cal): "\(cal) cal"
        case .distance(let meters): "\(Int(meters)) m"
        case .load(let kilograms): "\(kilograms.formattedWeight) kg"
        case .completedIntervals(let count): "\(count) intervals"
        }
    }
}
