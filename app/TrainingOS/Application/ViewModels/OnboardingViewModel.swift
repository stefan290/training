import Foundation
import SwiftData

/// Stage V1.Checkpoint 1: the four screens this exposes are exactly the
/// fields real production code already reads — `Goal.primaryType`/
/// `.targetDate` (`LongTermPlanner.PlanningParameters(goal:)`) and
/// `GoalPreferences.varietyPreference`/`.availableTrainingDaysPerWeek`/
/// `.allowsDoubleSessions` (`LongTermPlanner.swift` lines ~435/509/564-568/
/// 1030-1042) — never a field nothing consumes. `preferredModalities`/
/// `dislikedModalities` are also genuinely read (`rankCandidateMixes`) but
/// deliberately NOT exposed here: a modality multi-select is a materially
/// bigger UI (needs a real `ProgrammingSystemKind`/`ActivityType` picker) —
/// documented FOLLOW-UP, not built in this checkpoint (CLAUDE.md rule 11 —
/// don't build a partial version of something bigger; this omission doesn't
/// block the planner, which degrades to no stated preference exactly as
/// `GoalPreferences`'s own doc comment already promises it must).
@MainActor
@Observable
final class OnboardingViewModel {
    enum Step: Int, CaseIterable {
        case goal, preferences, environment, review
    }

    private(set) var step: Step = .goal
    private(set) var user: User?
    /// Stage V1 dogfooding fix: a directly-`@Observable`-owned scalar,
    /// deliberately NOT read via `viewModel.user?.profile?.defaultTrainingEnvironment`
    /// at the call site — that transitive SwiftData relationship read,
    /// mutated by the SIBLING `TrainingEnvironmentSettingsView`'s own
    /// independently-fetched `profile` reference, does not reliably
    /// re-trigger this view's re-render. This property is explicitly
    /// recomputed (`refreshEnvironmentState`) in response to
    /// `.trainingEnvironmentDefaultChanged`, so the Continue button's
    /// enablement is driven by a property SwiftUI is guaranteed to observe.
    private(set) var hasDefaultTrainingEnvironment = false

    var selectedGoalType: GoalType = .generalStrength
    var hasTargetDate = false
    var targetDate = Date()
    var varietyPreference: VarietyPreference = .moderate
    var availableTrainingDaysPerWeek: Int = 4
    var allowsDoubleSessions = false

    /// Resumes at whichever real step this athlete's persisted state hasn't
    /// reached yet — never a separately-persisted "current step" field
    /// (CLAUDE.md rule 10: don't invent state a real predicate already
    /// determines). Called once, on the flow's first appearance.
    func start(modelContext: ModelContext) {
        let resolvedUser = AppRootStateResolver.ensureBaselineIdentity(context: modelContext)
        user = resolvedUser
        if let activeGoal = resolvedUser.goals.first(where: { $0.status == .active }) {
            selectedGoalType = activeGoal.primaryType
            hasTargetDate = activeGoal.targetDate != nil
            targetDate = activeGoal.targetDate ?? Date()
            if let preferences = activeGoal.preferences {
                varietyPreference = preferences.varietyPreference
                availableTrainingDaysPerWeek = preferences.availableTrainingDaysPerWeek ?? 4
                allowsDoubleSessions = preferences.allowsDoubleSessions ?? false
            }
            hasDefaultTrainingEnvironment = resolvedUser.profile?.defaultTrainingEnvironment != nil
            step = hasDefaultTrainingEnvironment ? .review : .environment
        } else {
            step = .goal
        }
    }

    /// Re-fetches `user` fresh from `modelContext` and recomputes
    /// `hasDefaultTrainingEnvironment` from that live state — called in
    /// response to `.trainingEnvironmentDefaultChanged`, posted by
    /// `TrainingEnvironmentSettingsView` whenever it sets a default. A
    /// fresh `FetchDescriptor` re-read (not merely re-reading the existing
    /// `user` reference) is used deliberately, since the whole reason this
    /// method exists is that relationship-level mutation on that same
    /// object did not reliably propagate to this view on its own —
    /// re-fetching and reassigning `user` guarantees a directly-observed
    /// property change on this `@Observable` type.
    func refreshEnvironmentState(modelContext: ModelContext) {
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        guard let refreshedUser = users.first else { return }
        user = refreshedUser
        hasDefaultTrainingEnvironment = refreshedUser.profile?.defaultTrainingEnvironment != nil
    }

    func advance(from currentStep: Step, modelContext: ModelContext) {
        switch currentStep {
        case .goal:
            step = .preferences
        case .preferences:
            createOrUpdateGoal(modelContext: modelContext)
            step = .environment
        case .environment:
            step = .review
        case .review:
            break
        }
    }

    func goBack(from currentStep: Step) {
        switch currentStep {
        case .goal: break
        case .preferences: step = .goal
        case .environment: step = .preferences
        case .review: step = .environment
        }
    }

    /// Idempotent — if this athlete already has an active Goal (e.g. they
    /// backed up from a later step and changed their mind), this UPDATES it
    /// in place rather than creating a second one. `Goal.status == .active`
    /// is the only stated intent this checkpoint ever needs; nothing else
    /// reads a "draft" Goal state.
    private func createOrUpdateGoal(modelContext: ModelContext) {
        guard let user else { return }
        let preferences = GoalPreferences(
            varietyPreference: varietyPreference,
            availableTrainingDaysPerWeek: availableTrainingDaysPerWeek,
            allowsDoubleSessions: allowsDoubleSessions
        )
        if let existingGoal = user.goals.first(where: { $0.status == .active }) {
            existingGoal.primaryType = selectedGoalType
            existingGoal.targetDate = hasTargetDate ? targetDate : nil
            existingGoal.preferences = preferences
        } else {
            let goal = Goal(
                ownerUserID: user.id, primaryType: selectedGoalType,
                targetDate: hasTargetDate ? targetDate : nil, preferences: preferences
            )
            modelContext.insert(goal)
            user.addGoal(goal)
        }
        try? modelContext.save()
    }
}
