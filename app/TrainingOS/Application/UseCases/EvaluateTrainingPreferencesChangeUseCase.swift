import Foundation

/// Dogfood Round 2 (Finding 1): the smallest honest "what would this
/// preference change mean for the active mix" check — pure arithmetic
/// over already-real fields (`TrainingMixComponent.frequency`), mirroring
/// `StrategicPlanSelectionViewModel.reviewedMixRequiresDoubles`'s existing
/// precedent exactly. Never invokes `ConcurrentScheduler` itself — no
/// Sessions exist yet for a future week to actually schedule, so this is
/// a feasibility PREVIEW, computed before the athlete approves a change,
/// never a real scheduling run.
enum TrainingPreferencesConsequence: Equatable {
    /// The active mix's required weekly sessions already fit within the
    /// new available days, with no double session needed.
    case fitsAsIs
    /// Fits only if a double session is used on at least one day.
    case requiresDoubleSessions
    /// Does not fit even with double sessions allowed — TrainingOS never
    /// silently drops a required component to make this look feasible;
    /// the athlete must allow doubles, add days, or reduce their mix.
    case exceedsCapacityEvenWithDoubles(shortfallSessionsPerWeek: Int)
}

enum EvaluateTrainingPreferencesChangeUseCase {
    static func evaluate(
        activeComponents: [TrainingMixComponent],
        newAvailableTrainingDaysPerWeek: Int,
        newAllowsDoubleSessions: Bool
    ) -> TrainingPreferencesConsequence {
        let requiredSessionsPerWeek = activeComponents.reduce(0) { $0 + ($1.frequency.minimum ?? $1.frequency.target) }
        guard requiredSessionsPerWeek > newAvailableTrainingDaysPerWeek else { return .fitsAsIs }
        guard newAllowsDoubleSessions else {
            return .exceedsCapacityEvenWithDoubles(shortfallSessionsPerWeek: requiredSessionsPerWeek - newAvailableTrainingDaysPerWeek)
        }
        let capacityWithDoubles = newAvailableTrainingDaysPerWeek * 2
        guard requiredSessionsPerWeek > capacityWithDoubles else { return .requiresDoubleSessions }
        return .exceedsCapacityEvenWithDoubles(shortfallSessionsPerWeek: requiredSessionsPerWeek - capacityWithDoubles)
    }
}
