import SwiftUI
import SwiftData

/// Part E's endurance sibling of `ChangeExerciseView` — Steady State and
/// Interval blocks share one substitution mechanism
/// (`SubstituteActivityUseCase`/`ActivitySelectionOverride`), so one view
/// covers both prescription types rather than duplicating the same
/// Today Only / Going Forward flow twice. `IntensityTranslation` (inside
/// `SubstituteActivityUseCase`) — never a raw numeric carry-over between
/// incompatible activities — already handles "no incompatible numeric-
/// target transfer."
enum ActivityPrescriptionRef {
    case steadyState(SteadyStatePrescription)
    case intervals(IntervalPrescription)

    var activityType: ActivityType {
        switch self {
        case .steadyState(let p): p.activityType
        case .intervals(let p): p.activityType
        }
    }

    var workoutBlockTemplate: WorkoutBlockTemplate? {
        switch self {
        case .steadyState(let p): p.sourceWorkoutBlockTemplate
        case .intervals(let p): p.sourceWorkoutBlockTemplate
        }
    }
}

struct ChangeActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let reference: ActivityPrescriptionRef
    let session: Session

    @State private var pendingActivity: ActivityType?
    @State private var errorMessage: String?

    private var eligibilityTemplate: ActivitySubstitutionTemplate? { reference.workoutBlockTemplate?.activitySubstitutionTemplate }

    private var candidates: [ActivityType] {
        guard let template = eligibilityTemplate else { return [] }
        return template.allowedActivityTypes.filter { $0 != reference.activityType }
    }

    var body: some View {
        NavigationStack {
            Group {
                if eligibilityTemplate == nil {
                    ContentUnavailableView(
                        "Change Activity isn't available",
                        systemImage: "arrow.triangle.2.circlepath",
                        description: Text("This block wasn't materialized from a template, so there's nothing to validate an alternative against.")
                    )
                } else if candidates.isEmpty {
                    ContentUnavailableView("No valid alternatives", systemImage: "questionmark.circle")
                } else {
                    List(candidates, id: \.self) { activity in
                        Button(IntensityPresentation.activityLabel(activity)) { pendingActivity = activity }
                    }
                }
            }
            .navigationTitle("Change Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                pendingActivity.map { "Switch to \(IntensityPresentation.activityLabel($0))" } ?? "",
                isPresented: Binding(get: { pendingActivity != nil }, set: { if !$0 { pendingActivity = nil } }),
                titleVisibility: .visible
            ) {
                Button("Today Only") { apply(goingForward: false) }
                if session.programInstance != nil {
                    Button("Going Forward") { apply(goingForward: true) }
                }
                Button("Cancel", role: .cancel) { pendingActivity = nil }
            }
            .alert("Couldn't change activity", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func apply(goingForward: Bool) {
        guard let activity = pendingActivity, let template = eligibilityTemplate else { return }
        do {
            if goingForward {
                guard let instance = session.programInstance, let templateBlock = reference.workoutBlockTemplate else { return }
                try ApplySubstitutionUseCase.substituteActivityGoingForward(
                    instance: instance, templateBlock: templateBlock, eligibilityTemplate: template,
                    with: activity, reason: .userExerciseSubstitution, modelContext: modelContext
                )
            } else {
                switch reference {
                case .steadyState(let prescription):
                    try ApplySubstitutionUseCase.substituteActivityThisSessionOnly(
                        prescription: prescription, template: template, with: activity,
                        reason: .userExerciseSubstitution, modelContext: modelContext
                    )
                case .intervals(let prescription):
                    try ApplySubstitutionUseCase.substituteActivityThisSessionOnly(
                        prescription: prescription, template: template, with: activity,
                        reason: .userExerciseSubstitution, modelContext: modelContext
                    )
                }
            }
            pendingActivity = nil
            dismiss()
        } catch {
            errorMessage = "\(error)"
            pendingActivity = nil
        }
    }
}
