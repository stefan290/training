import SwiftUI

/// Read-only preview of a **template-only** (not yet materialized)
/// `TemplateSession` — shows the known, reusable program structure
/// (block types, slot names, and rep-goal reps/to-failure where the rule
/// is deterministic from the template alone) without ever claiming a
/// specific future load has been resolved. Load always depends on a
/// tested RM (a runtime input), so it is never shown here — showing one
/// would mean fabricating a number the domain model doesn't actually
/// know yet (Part 4's tactical-window requirement).
struct TemplateSessionPreviewView: View {
    let templateSession: TemplateSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Planned structure — not yet materialized")
                    .font(Theme.label)
                    .foregroundStyle(Theme.attention)

                ForEach(templateSession.orderedBlockTemplates) { blockTemplate in
                    blockSection(blockTemplate)
                }
            }
            .padding(16)
        }
        .background(Theme.ground)
        .navigationTitle(templateSession.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func blockSection(_ blockTemplate: WorkoutBlockTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(blockTemplate.type.rawValue.uppercased())
                .font(Theme.label)
                .foregroundStyle(Theme.primary)

            ForEach(blockTemplate.orderedPrescriptionTemplates) { template in
                slotRow(template)
            }

            if let steadyState = blockTemplate.steadyStatePrescriptionTemplate {
                Text(IntensityPresentation.activityLabel(steadyState.preferredActivityType))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
            }
            if let interval = blockTemplate.intervalPrescriptionTemplate {
                Text("\(IntensityPresentation.activityLabel(interval.preferredActivityType)) intervals")
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
            }
            if let ff = blockTemplate.functionalFitnessPrescriptionTemplate {
                Text(BlockPresentation.formatLabel(ff.format))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func slotRow(_ template: PrescriptionTemplate) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(template.exerciseSlot?.name ?? "Movement slot")
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            if let repGoal = template.rules?.repGoalSchedule.first {
                Text(repGoal.toFailure ? "\(repGoal.reps) reps to failure" : "\(repGoal.reps) reps")
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
