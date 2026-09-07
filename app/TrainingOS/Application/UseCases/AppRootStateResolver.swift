import Foundation
import SwiftData

/// Stage V1.Checkpoint 1: the truthful root-routing predicate this app's own
/// launch-time comment called for ("remove [seeding] once onboarding
/// exists"). Deliberately NOT "does any `User` row exist" — that single-field
/// check is exactly the fragile predicate a real athlete's own in-progress
/// (but not yet goal-having, or not yet environment-having) onboarding would
/// fail. Every condition here names a REAL prerequisite a later real
/// production path already requires: `LongTermPlanner.proposeStrategicPlan`
/// needs an `.active` `Goal`; every real materializer requires a non-nil
/// `TrainingEnvironment` (TE.1) or throws `.trainingEnvironmentRequired`.
enum AppRootState: Equatable {
    /// No real athlete/Goal/Environment state yet — show onboarding.
    case needsOnboarding
    /// Onboarding is complete (profile, active Goal, default Environment all
    /// exist) but no strategic plan has been accepted yet — Checkpoint 2's
    /// entry point.
    case readyForPlan
    /// A real accepted `TrainingPlan` exists — show the existing app.
    case activeTraining
}

enum AppRootStateResolver {
    /// Idempotent — safe to call on every launch. Creates only the baseline
    /// identity/infrastructure objects no screen ever asks the athlete
    /// about: the `User`/`UserProfile`/`PerformanceProfile` shell (mirrors
    /// `SeedDataProvider.seedPrerequisites`'s own shape, minus any Goal/
    /// Plan) and the static Exercise catalog (`ExerciseCatalog.resolveOrInsert`
    /// — content, not user data; every real materializer needs it
    /// regardless of onboarding state).
    /// Never creates a `Goal`, `TrainingPlan`, `ProgramInstance`, or
    /// `Session` — those are only ever created by an explicit athlete
    /// action (onboarding's own steps, or Checkpoint 2).
    ///
    /// V1 R5 (Training Environment product reconciliation): the ONE
    /// exception to "no environment is ever auto-created" — a brand-new
    /// `User`'s own profile is seeded with the built-in `.fullGym()`
    /// environment as its default, so `resolve` below never requires a
    /// manual equipment step for a normal new athlete. Deliberately scoped
    /// to the BRAND-NEW-user branch only, never as a backfill for an
    /// already-existing user with zero environments — an athlete who has
    /// already deliberately deleted every environment
    /// (`TrainingEnvironmentSettingsView`'s own real "Delete Environment"
    /// action) must never have Full Gym silently reappear on next launch;
    /// `nil`/`environmentUnknown` remains a real, reachable state for that
    /// athlete until they explicitly add one again.
    @discardableResult
    static func ensureBaselineIdentity(context: ModelContext) -> User {
        _ = ExerciseCatalog.resolveOrInsert(context: context)
        let users = (try? context.fetch(FetchDescriptor<User>())) ?? []
        if let existing = users.first {
            if existing.profile == nil {
                let profile = UserProfile()
                context.insert(profile)
                existing.attachProfile(profile)
            }
            if existing.performanceProfile == nil {
                let performanceProfile = PerformanceProfile()
                context.insert(performanceProfile)
                existing.attachPerformanceProfile(performanceProfile)
            }
            try? context.save()
            return existing
        }
        let user = User(displayName: "")
        context.insert(user)
        let profile = UserProfile()
        context.insert(profile)
        user.attachProfile(profile)
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        user.attachPerformanceProfile(performanceProfile)
        let fullGym = TrainingEnvironment.fullGym()
        context.insert(fullGym)
        profile.trainingEnvironments.append(fullGym)
        profile.defaultTrainingEnvironment = fullGym
        try? context.save()
        return user
    }

    static func resolve(context: ModelContext) -> AppRootState {
        let users = (try? context.fetch(FetchDescriptor<User>())) ?? []
        guard let user = users.first, let profile = user.profile else { return .needsOnboarding }
        guard let activeGoal = user.goals.first(where: { $0.status == .active }) else { return .needsOnboarding }
        guard profile.defaultTrainingEnvironment != nil else { return .needsOnboarding }
        let hasActivePlan = activeGoal.plans.contains { $0.status == .active }
        return hasActivePlan ? .activeTraining : .readyForPlan
    }
}
