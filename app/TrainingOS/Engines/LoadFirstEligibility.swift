import Foundation

/// Stage 10R.5, D-10R5-20: the overlay's own scope guard — implemented
/// as its own small, explicit check (never folded into
/// `LoadFirstOverlayEngine`'s pure classification logic) so the "where
/// does this apply" decision stays legible and easy to audit on its own.
/// Scoped to exactly the recovered 3-Day Full Body Family A path: a real
/// `.rmBased` load rule AND the specific `dayCount == 3, split ==
/// .fullBody` configuration. Never silently activates for an unrecovered
/// Family A configuration, Family B/C, or any non-`.rmBased` modality —
/// each of those would need its own independently-verified eligibility
/// pass before this guard is ever widened.
enum LoadFirstEligibility {
    static func isEligible(_ prescription: ExercisePrescription) -> Bool {
        guard prescription.sourcePrescriptionTemplate?.loadRuleKind == .rmBased else { return false }
        guard let configuration = prescription.sourcePrescriptionTemplate?
            .workoutBlockTemplate?.templateSession?.programDefinition?.hypertrophyConfiguration
        else { return false }
        return configuration.dayCount == 3 && configuration.split == .fullBody
    }
}
