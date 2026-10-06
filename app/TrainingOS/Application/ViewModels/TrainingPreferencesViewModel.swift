import Foundation
import SwiftData
import Observation

/// Dogfood Round 2 (Finding 1): treats onboarding answers as ATHLETE
/// CONFIGURATION, not immutable onboarding history. Reuses `GoalPreferences`
/// exactly as-is (no duplicate storage) and the existing engine ->
/// explanation -> approval pattern: `EvaluateTrainingPreferencesChangeUseCase`
/// supplies the consequence preview, the View shows it, and `save` only
/// ever persists `Goal.preferences` — it never mutates a `Session`/`Day`
/// directly. The real scheduling effect is realized starting with the
/// NEXT tactical week roll (`AdvanceTacticalWeekUseCase.advance`), which
/// now reads this same, freshly-updated `Goal.preferences` instead of a
/// hardcoded availability (see `PhaseDetailViewModel`'s matching fix) —
/// the current/active tactical week and all completed history are never
/// touched here.
@MainActor
@Observable
final class TrainingPreferencesViewModel {
    private(set) var goal: Goal?
    private(set) var activeComponents: [TrainingMixComponent] = []
    private(set) var currentMixSummary: String?
    private(set) var hasActivePhase = false

    /// Dogfood Round 2 (Finding 1) — Independent Review Correction 1: the
    /// real, single authority for weekly availability. Defaults to every
    /// weekday when the athlete has never made an explicit choice — the
    /// same "no restriction" meaning `UserAvailability.availableWeekdays`
    /// itself already gives an empty set, never a guessed subset inferred
    /// from the legacy day-COUNT integer.
    var selectedWeekdays: Set<Weekday> = Set(Weekday.allCases)
    var allowsDoubleSessions = false
    /// Read-only for the athlete — the real capacity number IS the count
    /// of days selected above, never a second, independently-editable
    /// truth that could disagree with it.
    var availableTrainingDaysPerWeek: Int { selectedWeekdays.count }
    var typicalSessionDurationMinutes: Int?
    var varietyPreference: VarietyPreference = .moderate
    var preferredTrainingStyles: Set<TrainingStyle> = []
    var dislikedTrainingStyles: Set<TrainingStyle> = []

    private(set) var didSave = false

    func load(modelContext: ModelContext) {
        didSave = false
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        guard let activeGoal = users.first?.goals.first(where: { $0.status == .active }) else {
            goal = nil
            activeComponents = []
            currentMixSummary = nil
            hasActivePhase = false
            return
        }
        goal = activeGoal

        let preferences = activeGoal.preferences ?? GoalPreferences()
        // Correction 1: `availableWeekdays` is the real authority once
        // chosen; a never-chosen `nil` defaults to every weekday selected
        // — behaviorally identical to today's "no restriction" (never a
        // guessed subset of the legacy count).
        selectedWeekdays = preferences.availableWeekdays ?? Set(Weekday.allCases)
        allowsDoubleSessions = preferences.allowsDoubleSessions ?? false
        typicalSessionDurationMinutes = preferences.typicalSessionDurationMinutes
        varietyPreference = preferences.varietyPreference
        preferredTrainingStyles = trainingStyles(matching: preferences.preferredModalities)
        dislikedTrainingStyles = trainingStyles(matching: preferences.dislikedModalities)

        let activePhase = activeGoal.plans.first { $0.status == .active }?.orderedPhases.first { $0.status == .active }
        hasActivePhase = activePhase != nil
        let mix = activePhase?.selectedTrainingMix ?? activePhase?.recommendedTrainingMix
        activeComponents = mix?.orderedComponents ?? []
        currentMixSummary = mix.map(PlanPresentation.mixSummary)
    }

    private func trainingStyles(matching modalities: [ModalityPreference]) -> Set<TrainingStyle> {
        Set(TrainingStyle.allCases.filter { style in style.modalityPreferences.allSatisfy(modalities.contains) })
    }

    /// Recomputes the consequence of the CURRENTLY EDITED days/doubles
    /// against the real active mix — called before save so the athlete
    /// sees the real effect before anything is persisted.
    func previewConsequence() -> TrainingPreferencesConsequence {
        EvaluateTrainingPreferencesChangeUseCase.evaluate(
            activeComponents: activeComponents,
            newAvailableTrainingDaysPerWeek: availableTrainingDaysPerWeek,
            newAllowsDoubleSessions: allowsDoubleSessions
        )
    }

    /// Applies the change — persists `Goal.preferences` only. Never
    /// touches any already-materialized Session/Day; the active/in-
    /// progress tactical week and all completed history are left exactly
    /// as they were. The real scheduling effect begins with the next
    /// tactical week roll.
    @discardableResult
    func save(modelContext: ModelContext) -> Bool {
        guard let goal, !selectedWeekdays.isEmpty else { return false }
        var preferences = goal.preferences ?? GoalPreferences()
        // Correction 1: `availableWeekdays` is the one persisted truth;
        // `availableTrainingDaysPerWeek` is kept strictly in sync as its
        // count — the two are never allowed to disagree once the athlete
        // has used this real editor.
        preferences.availableWeekdays = selectedWeekdays
        preferences.availableTrainingDaysPerWeek = selectedWeekdays.count
        preferences.allowsDoubleSessions = allowsDoubleSessions
        preferences.typicalSessionDurationMinutes = typicalSessionDurationMinutes
        preferences.varietyPreference = varietyPreference
        preferences.preferredModalities = preferredTrainingStyles.flatMap(\.modalityPreferences)
        preferences.dislikedModalities = dislikedTrainingStyles.flatMap(\.modalityPreferences)
        goal.preferences = preferences
        do {
            try modelContext.save()
            didSave = true
            return true
        } catch {
            return false
        }
    }
}
