import SwiftUI
import SwiftData

/// Part 6: the one lightweight check-in Stage 6 execution was missing —
/// never a questionnaire, never repeated per exercise when one rating
/// covers the same muscle/stimulus (`HypertrophyFeedbackPrompts` already
/// filtered the list down to exactly the exercises some other slot's
/// next-week set count depends on). Persists immediately per answer via
/// `RecordAutoregulationFeedbackUseCase`; `onDone` fires once every
/// prompt has been answered.
struct HypertrophyFeedbackView: View {
    @Environment(\.modelContext) private var modelContext
    let prescriptions: [ExercisePrescription]
    let onDone: () -> Void

    @State private var index = 0

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                if let prescription = currentPrescription {
                    Text("\(index + 1) of \(prescriptions.count)")
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                    Text(prescription.exercise?.canonicalName ?? "Exercise")
                        .font(Theme.heading)
                        .foregroundStyle(Theme.textPrimary)
                    Text("How did this feel?")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textSecondary)

                    VStack(spacing: 10) {
                        ForEach(options(for: prescription), id: \.rating) { option in
                            Button(option.label) { answer(option.rating, for: prescription) }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                Spacer()
            }
            .padding(16)
            .background(Theme.ground)
            .navigationTitle("Quick Check-in")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var currentPrescription: ExercisePrescription? {
        prescriptions.indices.contains(index) ? prescriptions[index] : nil
    }

    private func options(for prescription: ExercisePrescription) -> [HypertrophyFeedbackCopy.Option] {
        HypertrophyFeedbackCopy.options(for: HypertrophyFeedbackCopy.programmingSystem(for: prescription))
    }

    private func answer(_ rating: Int, for prescription: ExercisePrescription) {
        try? RecordAutoregulationFeedbackUseCase.recordRating(rating, for: prescription, modelContext: modelContext)
        if index + 1 < prescriptions.count {
            index += 1
        } else {
            onDone()
        }
    }
}
