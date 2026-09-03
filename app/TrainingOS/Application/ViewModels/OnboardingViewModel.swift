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
        case goal, preferences, modalityPreferences, environment, review
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
    /// Stage V1 "Milestone Onboarding": the athlete-facing surface for the
    /// ALREADY-REAL `Goal.milestoneDate`/`.bodyCompositionDirection` fields
    /// (`STRATEGIC_PLAN_MODEL.md` §3) — distinct from `targetDate` (the
    /// plan's own forward horizon). Only the single "Summer Shape"-style
    /// direction (`.loseFat`) is exposed in this checkpoint — a full
    /// `BodyCompositionDirection` picker would expose internal vocabulary
    /// for no athlete-facing benefit this checkpoint's own locked scope
    /// asks for; `.gainMuscle`/`.maintain`/`.recomposition` remain real,
    /// reachable domain states (e.g. for a future Fat Loss-primary athlete
    /// wanting a muscle-gain milestone) simply not surfaced by THIS control
    /// yet — a disclosed, deliberate FOLLOW-UP, not a planner limitation.
    var hasMilestone = false
    var milestoneDate = Date()
    /// Dated Objectives + 10K Strategic Reconciliation V1: the second real
    /// "working toward" item the same add-panel affordance now offers —
    /// a `DatedObjective(kind: .runningEvent)`, never a new persisted
    /// scalar pair (`Goal.datedObjectives` is the domain model this maps
    /// to; unlike Summer Shape, this never touches `Goal.milestoneDate`/
    /// `.bodyCompositionDirection`, so the two can coexist without either
    /// silently becoming non-authoritative — see `createOrUpdateGoal`).
    var hasRunningEvent = false
    var runningEventDate = Date()
    var runningStartingState: RunningStartingState = .notCurrentlyRunning
    /// A past/present event date must never be accepted — same discipline
    /// as `isMilestoneDateValid`.
    var isRunningEventDateValid: Bool { runningEventDate > Date() }
    /// Stage V1 "Milestone Onboarding UX correction": the athlete-facing
    /// confirm action reads this directly — a past/present milestone date
    /// must never be accepted. Deliberately a ViewModel-owned property (not
    /// a View-local computation) so a test can exercise the exact predicate
    /// the real confirm button's `.disabled()` reads.
    var isMilestoneDateValid: Bool { milestoneDate > Date() }
    var varietyPreference: VarietyPreference = .moderate
    var availableTrainingDaysPerWeek: Int = 4
    var allowsDoubleSessions = false
    /// Stage V1 dogfooding fix (Part 3): real, planner-consumed
    /// preferences — `LongTermPlanner.isPreferenceAligned` already reads
    /// `GoalPreferences.preferredModalities`/`.dislikedModalities`
    /// (`system`-level `ProgrammingSystemKind`). No new planner semantics;
    /// this is the previously-deferred onboarding surface for fields that
    /// were already real.
    var preferredSystems: Set<ProgrammingSystemKind> = []
    var dislikedSystems: Set<ProgrammingSystemKind> = []
    /// Only meaningful when `.steadyState` is in `dislikedSystems` —
    /// preserves the real, existing system-vs-activity-level distinction
    /// `ModalityPreference(system:activityType:)` already supports:
    /// disliking `.steadyState` with `activityType: .running` blocks
    /// running specifically, never all conditioning work.
    var dislikesRunningSpecifically = false

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
            hasMilestone = activeGoal.milestoneDate != nil
            milestoneDate = activeGoal.milestoneDate ?? Date()
            if let runningEvent = activeGoal.datedObjectives.first(where: { $0.kind == .runningEvent && $0.status == .planned }) {
                hasRunningEvent = true
                runningEventDate = runningEvent.date
                runningStartingState = runningEvent.runningStartingState ?? .notCurrentlyRunning
            } else {
                runningStartingState = suggestedRunningStartingState(user: resolvedUser)
            }
            if let preferences = activeGoal.preferences {
                varietyPreference = preferences.varietyPreference
                availableTrainingDaysPerWeek = preferences.availableTrainingDaysPerWeek ?? 4
                allowsDoubleSessions = preferences.allowsDoubleSessions ?? false
                preferredSystems = Set(preferences.preferredModalities.map(\.system))
                dislikedSystems = Set(preferences.dislikedModalities.map(\.system))
                dislikesRunningSpecifically = preferences.dislikedModalities.contains {
                    $0.system == .steadyState && $0.activityType == .running
                }
            }
            hasDefaultTrainingEnvironment = resolvedUser.profile?.defaultTrainingEnvironment != nil
            step = hasDefaultTrainingEnvironment ? .review : .environment
        } else {
            runningStartingState = suggestedRunningStartingState(user: resolvedUser)
            step = .goal
        }
    }

    /// Dated Objectives + 10K Strategic Reconciliation V1's locked
    /// "6-week recency" rule: existing `ActivityPerformanceProfile` data
    /// may SUGGEST a preselected answer, never silently override the
    /// athlete's own explicit choice — this only ever seeds the initial
    /// value before the athlete has interacted with the running-state
    /// question at all. Deliberately never suggests `.comfortably10K` —
    /// real result data can't reliably prove genuine 10K capability, and
    /// the locked spec is explicit that inventing that signal is out of
    /// scope; recent running activity at all only ever justifies the more
    /// conservative `.occasionalShorterDistances` tier.
    private func suggestedRunningStartingState(user: User) -> RunningStartingState {
        guard let lastRun = user.performanceProfile?.activityProfile(for: .running)?.lastPerformedAt else {
            return .notCurrentlyRunning
        }
        let sixWeeksAgo = Calendar.current.date(byAdding: .weekOfYear, value: -6, to: Date()) ?? Date()
        return lastRun >= sixWeeksAgo ? .occasionalShorterDistances : .notCurrentlyRunning
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
            step = .modalityPreferences
        case .modalityPreferences:
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
        case .modalityPreferences: step = .preferences
        case .environment: step = .modalityPreferences
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
        // Stage V1 dogfooding fix (Part 3): the real system-vs-activity
        // distinction `ModalityPreference(system:activityType:)` already
        // supports — disliking `.steadyState` with `activityType: .running`
        // blocks running specifically, never all conditioning work.
        let dislikedModalities = dislikedSystems.map { system in
            ModalityPreference(
                system: system,
                activityType: (system == .steadyState && dislikesRunningSpecifically) ? .running : nil
            )
        }
        let preferredModalities = preferredSystems.map { ModalityPreference(system: $0) }
        let preferences = GoalPreferences(
            preferredModalities: preferredModalities,
            dislikedModalities: dislikedModalities,
            varietyPreference: varietyPreference,
            availableTrainingDaysPerWeek: availableTrainingDaysPerWeek,
            allowsDoubleSessions: allowsDoubleSessions
        )
        // Dated Objectives + 10K Strategic Reconciliation V1: Summer Shape
        // keeps writing `milestoneDate`/`bodyCompositionDirection` exactly
        // as before (zero regression to the already-locked Milestone
        // Onboarding behavior/tests) — `datedObjectives` only becomes
        // non-empty at all when a running event is actually present. When
        // it IS present alongside an active Summer Shape milestone, the
        // milestone is also projected into this same array — `Goal
        // .datedObjectives` is authoritative once non-empty, so leaving
        // Summer Shape out of it here would silently drop it from planning
        // the moment a 10K is added.
        var datedObjectives: [DatedObjective] = []
        if hasRunningEvent {
            if hasMilestone {
                datedObjectives.append(DatedObjective(kind: .bodyCompositionMilestone, date: milestoneDate, bodyCompositionDirection: .loseFat))
            }
            datedObjectives.append(DatedObjective(kind: .runningEvent, date: runningEventDate, runningStartingState: runningStartingState))
        }
        if let existingGoal = user.goals.first(where: { $0.status == .active }) {
            existingGoal.primaryType = selectedGoalType
            existingGoal.targetDate = hasTargetDate ? targetDate : nil
            existingGoal.milestoneDate = hasMilestone ? milestoneDate : nil
            existingGoal.bodyCompositionDirection = hasMilestone ? .loseFat : nil
            existingGoal.preferences = preferences
            existingGoal.datedObjectives = datedObjectives
        } else {
            let goal = Goal(
                ownerUserID: user.id, primaryType: selectedGoalType,
                targetDate: hasTargetDate ? targetDate : nil,
                milestoneDate: hasMilestone ? milestoneDate : nil,
                bodyCompositionDirection: hasMilestone ? .loseFat : nil,
                preferences: preferences,
                datedObjectives: datedObjectives
            )
            modelContext.insert(goal)
            user.addGoal(goal)
        }
        try? modelContext.save()
    }
}
