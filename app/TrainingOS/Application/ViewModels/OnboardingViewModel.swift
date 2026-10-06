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
    /// V1 "Explicit Weekly Composition" checkpoint: `.modalityPreferences`
    /// (the soft "especially want/rather avoid" step) is REMOVED from the
    /// primary flow — explicit weekly composition (chosen on the Plan
    /// screen, where a real `TrainingPhase` exists to build a real
    /// `TrainingMix` against — see `StrategicPlanSelectionView`'s "Build
    /// My Own Mix") supersedes it as the one athlete-facing authority for
    /// desired training composition. The underlying `preferredModalities`/
    /// `dislikedModalities`/`TrainingStyle` machinery is NOT deleted —
    /// `preferredTrainingStyles`/`dislikedTrainingStyles` below remain
    /// real properties, still reloaded from any pre-existing persisted
    /// data in `start()` and still written by `createOrUpdateGoal`, kept
    /// only for backward compatibility and the still-real
    /// `CandidateTrainingMix` preset-ranking path — simply no longer
    /// editable from this primary flow.
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
    /// Dogfood Round 2 Continuation (Finding I): mirrors
    /// `UserProfile.hasConfirmedTrainingEnvironment` the same way
    /// `hasDefaultTrainingEnvironment` mirrors `defaultTrainingEnvironment`
    /// — a directly-observed scalar refreshed alongside it, never read via
    /// a transitive relationship path at the call site.
    private(set) var hasConfirmedTrainingEnvironment = false

    /// DF-BUG-1 fix (Dogfood Release Readiness V1): a genuinely new
    /// athlete must see NO Goal pre-selected — the athlete-facing
    /// screenshot review this checkpoint performed found "Get Stronger"
    /// pre-checkmarked before any real tap, a real first-run defect (the
    /// screen is asking the athlete to choose, not confirming a choice
    /// already made for them). `nil` means "no selection yet"; `start()`'s
    /// existing resume branch (below) still sets this to the real,
    /// persisted `activeGoal.primaryType` for a returning athlete — this
    /// change only affects the brand-new, no-active-goal case.
    var selectedGoalType: GoalType?
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
    /// Dogfood Round 2 Continuation (Finding A): the real, athlete-selected
    /// weekly-availability authority — same `GoalPreferences.availableWeekdays`
    /// field, same "no restriction = every weekday" default, `TrainingPreferencesViewModel`
    /// already established for post-onboarding editing. Onboarding writes
    /// this same authority directly rather than inventing separate
    /// onboarding-only storage.
    var selectedWeekdays: Set<Weekday> = Set(Weekday.allCases)
    /// Read-only — the real capacity number IS the count of days selected
    /// above, never a second, independently-set truth that could disagree
    /// with it.
    var availableTrainingDaysPerWeek: Int { selectedWeekdays.count }
    var allowsDoubleSessions = false
    /// R6 Visual Correction Pass: `GoalPreferences.typicalSessionDurationMinutes`
    /// is real, already-persisted state (`LongTermGoalTypes.swift`) that
    /// had no onboarding surface before this pass — round-trips correctly
    /// (`LongTermPlannerPersistenceTests`) but is not yet READ by any
    /// scheduling/planning engine. Exposed here as real state exposure,
    /// never fabricated; the artifact's own "Time available per training
    /// day" chips (45/60/75/90+) map directly onto it. `nil` (unset) is a
    /// real, valid state — no discrete option is force-selected.
    var typicalSessionDurationMinutes: Int?
    /// V1 "Goal ≠ Training Method" checkpoint: the athlete-facing Training
    /// Style vocabulary (`TrainingStyle`) — replaces the previous raw
    /// `ProgrammingSystemKind` checkboxes (which leaked "Powerlifting"/
    /// "Steady State"/"Intervals" verbatim to the athlete). Each style
    /// expands to real `ModalityPreference`(s) via
    /// `TrainingStyle.modalityPreferences` — the exact same
    /// `GoalPreferences.preferredModalities`/`.dislikedModalities` fields
    /// `LongTermPlanner.isPreferenceAligned`/`preferredActivityType` already
    /// read; no new planner semantics. Running/Cycling being their own
    /// explicit, activity-scoped styles means disliking one no longer
    /// needs a separate "just running, not all conditioning" toggle — that
    /// distinction is now inherent to which style was disliked.
    var preferredTrainingStyles: Set<TrainingStyle> = []
    var dislikedTrainingStyles: Set<TrainingStyle> = []

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
                selectedWeekdays = preferences.availableWeekdays ?? Set(Weekday.allCases)
                allowsDoubleSessions = preferences.allowsDoubleSessions ?? false
                typicalSessionDurationMinutes = preferences.typicalSessionDurationMinutes
                preferredTrainingStyles = trainingStyles(matching: preferences.preferredModalities)
                dislikedTrainingStyles = trainingStyles(matching: preferences.dislikedModalities)
            }
            hasDefaultTrainingEnvironment = resolvedUser.profile?.defaultTrainingEnvironment != nil
            hasConfirmedTrainingEnvironment = resolvedUser.profile?.hasConfirmedTrainingEnvironment ?? false
            // Finding I: a default existing (true immediately, via the
            // baseline auto-seed) is no longer sufficient on its own to
            // skip the Environment step — the athlete must have actually
            // seen and accepted it at least once.
            step = (hasDefaultTrainingEnvironment && hasConfirmedTrainingEnvironment) ? .review : .environment
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
    /// Reverse-maps real, persisted `ModalityPreference`s back to the
    /// athlete-facing `TrainingStyle`(s) that would have produced them — a
    /// style counts as selected when EVERY one of its own
    /// `modalityPreferences` is present (mirrors that `createOrUpdateGoal`
    /// always writes a style's full set atomically). Legacy pre-checkpoint
    /// data (a raw system-wide `ModalityPreference(system: .steadyState)`
    /// with no `activityType`, from the previous raw-`ProgrammingSystemKind`
    /// UI) does not match `.running`/`.cycling` — a disclosed, non-
    /// destructive FOLLOW-UP (re-opening onboarding simply shows that style
    /// unchecked; the athlete can re-select, nothing is corrupted or lost).
    private func trainingStyles(matching modalities: [ModalityPreference]) -> Set<TrainingStyle> {
        Set(TrainingStyle.allCases.filter { style in
            style.modalityPreferences.allSatisfy(modalities.contains)
        })
    }

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
        hasConfirmedTrainingEnvironment = refreshedUser.profile?.hasConfirmedTrainingEnvironment ?? false
    }

    func advance(from currentStep: Step, modelContext: ModelContext) {
        switch currentStep {
        case .goal:
            // DF-BUG-1: defense in depth alongside the real UI's own
            // `.disabled(viewModel.selectedGoalType == nil)` Continue
            // button — the ViewModel, not the View, is the one place
            // that must actually enforce "no advancing with no Goal
            // chosen."
            guard selectedGoalType != nil else { return }
            step = .preferences
        case .preferences:
            // Finding A: mirrors DF-BUG-1's own defense-in-depth discipline
            // — the ViewModel, not only the View's `.disabled`, refuses to
            // advance with no training day selected.
            guard !selectedWeekdays.isEmpty else { return }
            createOrUpdateGoal(modelContext: modelContext)
            refreshEnvironmentState(modelContext: modelContext)
            // Dogfood Round 2 Continuation (Finding I): a default existing
            // (true immediately via the baseline auto-seed) no longer
            // skips the Environment step on its own — the athlete must
            // have explicitly accepted/confirmed it at least once
            // (`hasConfirmedTrainingEnvironment`). A RETURNING athlete who
            // already confirmed it on an earlier pass through onboarding
            // still skips straight to Review, exactly as before.
            step = (hasDefaultTrainingEnvironment && hasConfirmedTrainingEnvironment) ? .review : .environment
        case .environment:
            // Finding I: this Continue tap IS the athlete's real,
            // explicit acceptance of whatever Training Environment is
            // currently their default (Full Gym, unchanged, or a real
            // custom one they just created/switched to) — persisted so
            // this athlete is never routed back through this step again
            // on a later resume/relaunch.
            if let profile = user?.profile {
                profile.hasConfirmedTrainingEnvironment = true
                try? modelContext.save()
                hasConfirmedTrainingEnvironment = true
            }
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
        // DF-BUG-1: unreachable in practice — `advance(from: .goal, ...)`
        // and the real Continue button's own `.disabled` already refuse to
        // leave the Goal step with no selection — but this function owns
        // its own correctness rather than trusting an upstream UI gate.
        guard let user, let selectedGoalType else { return }
        // V1 "Goal ≠ Training Method" checkpoint: each selected
        // `TrainingStyle` expands to its own real `ModalityPreference`(s) —
        // the single, shared mapping used for both "especially want" and
        // "I'd rather avoid," never two separate translation tables.
        let preferredModalities = preferredTrainingStyles.flatMap(\.modalityPreferences)
        let dislikedModalities = dislikedTrainingStyles.flatMap(\.modalityPreferences)
        let preferences = GoalPreferences(
            preferredModalities: preferredModalities,
            dislikedModalities: dislikedModalities,
            varietyPreference: varietyPreference,
            availableTrainingDaysPerWeek: selectedWeekdays.count,
            typicalSessionDurationMinutes: typicalSessionDurationMinutes,
            allowsDoubleSessions: allowsDoubleSessions,
            availableWeekdays: selectedWeekdays
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
