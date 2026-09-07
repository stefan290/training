import Foundation
import SwiftData
import Observation

/// Loads today's Sessions. Fetches broadly and filters/sorts in Swift
/// rather than a SwiftData `#Predicate` — safe and simple at seed-data
/// scale; replace with a predicate-based `FetchDescriptor` once real
/// datasets make a full-table scan wasteful. See ARCHITECTURE.md.
@Observable
final class TodayViewModel {
    private(set) var sessions: [Session] = []
    /// V1 R2 (Today reconciliation): non-`nil` only when today has zero
    /// Sessions AND the reason is the R0 "a brand-new plan's first
    /// tactical week only begins on a genuine calendar-week boundary"
    /// rule (`AcceptStrategicPlanUseCase`/`LongTermPlanner.resolvedInitialPlanStartDate`,
    /// unmodified, read-only here) — never a guess, never a second
    /// planning concept. Distinguishes this from a genuine rest day
    /// (zero sessions WITHIN an already-started phase), which is real
    /// domain truth on its own and needs no special-casing at all
    /// (CLAUDE.md rule 8: a Day may legitimately hold zero Sessions).
    private(set) var upcomingPlanStart: UpcomingPlanStart?
    /// V1 R2 (Today reconciliation): the athlete's real current phase
    /// type, shown as light-touch context alongside today's Sessions
    /// (the artifact's own "phase/program context where useful"
    /// principle) — never a fabricated week-of-N count, since no single
    /// existing shared mechanism computes that truthfully across every
    /// component type in a mixed-modality phase; disclosed as a deliberate
    /// simplification rather than an invented number.
    private(set) var currentPhaseType: PhaseType?
    /// V1 R5 (Training Environment product reconciliation), Part 1: every
    /// real `TrainingEnvironment` the athlete has (Full Gym plus any
    /// custom ones) — the real, complete choice set for "use this
    /// environment for today's workout," never a fabricated list.
    private(set) var environments: [TrainingEnvironment] = []
    private var defaultEnvironment: TrainingEnvironment?

    struct UpcomingPlanStart {
        let startDate: Date
        let phaseType: PhaseType
    }

    /// The real environment a given Session is currently associated with
    /// — its own `materializedInEnvironment` when a materializer actually
    /// set one (Functional Fitness/Steady State/Interval), falling back
    /// to the athlete's real default (what a Strength/Hypertrophy
    /// Session's exercise slots were actually resolved against at
    /// instance-creation time, per `ResolveProgramInstanceExerciseSlotsUseCase`)
    /// — never a fabricated "no environment" state once any real default
    /// exists.
    func environment(for session: Session) -> TrainingEnvironment? {
        session.materializedInEnvironment ?? defaultEnvironment
    }

    /// `referenceDate` defaults to the real current moment for every
    /// existing caller (`TodayView`'s own call site is unaffected) — the
    /// injection point exists solely so a deterministic date can be
    /// supplied in tests, never so business logic itself reads an
    /// implicit, untestable `Date()` (mirrors CLAUDE.md rule 4's
    /// discipline for progression logic, applied here too).
    func load(modelContext: ModelContext, referenceDate: Date = Date()) {
        let days = (try? modelContext.fetch(FetchDescriptor<Day>())) ?? []
        let startOfToday = Calendar.current.startOfDay(for: referenceDate)
        // More than one `Day` row can legitimately share a calendar date:
        // `AcceptScheduleProposalUseCase.accept` re-parents a Session from
        // its naive materialized Day onto its real scheduled Day, leaving
        // the old Day behind, empty but not deleted (nullify, never
        // cascade — CLAUDE.md rule 1). Reading only the first matching Day
        // risked silently picking an emptied one while a sibling Day for
        // the same date held the real Session. Aggregating every matching
        // Day's Sessions is correct regardless of which one is which.
        let todaysDays = days.filter { Calendar.current.isDate($0.date, inSameDayAs: startOfToday) }
        sessions = todaysDays.flatMap(\.orderedSessions).sorted { $0.sortIndex < $1.sortIndex }

        let activePhase = Self.resolveActivePhase(modelContext: modelContext)
        currentPhaseType = activePhase?.type
        // R0's own truthful start-date resolution is the one, exact
        // signal: it guarantees zero Sessions exist before that date for
        // a phase in this state, so there is nothing else to distinguish
        // an upcoming start from a genuine rest day.
        if sessions.isEmpty, let activePhase, Calendar.current.startOfDay(for: activePhase.startDate) > startOfToday {
            upcomingPlanStart = UpcomingPlanStart(startDate: activePhase.startDate, phaseType: activePhase.type)
        } else {
            upcomingPlanStart = nil
        }

        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        let profile = users.first?.profile
        environments = profile?.trainingEnvironments ?? []
        defaultEnvironment = profile?.defaultTrainingEnvironment
    }

    /// Read-only: what would change if `session` were adapted to
    /// `targetEnvironment` — never writes anything (`WorkoutEnvironmentAdaptationUseCase.preview`).
    func previewEnvironmentSwitch(for session: Session, to targetEnvironment: TrainingEnvironment, modelContext: ModelContext) -> [WorkoutEnvironmentAdaptationUseCase.Adaptation] {
        let candidateExercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        let curatedRelationships = (try? modelContext.fetch(FetchDescriptor<ExerciseRelationship>())) ?? []
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        let performanceProfile = users.first?.performanceProfile
        return WorkoutEnvironmentAdaptationUseCase.preview(
            session: session, targetEnvironment: targetEnvironment, candidateExercises: candidateExercises,
            curatedRelationships: curatedRelationships,
            profileLookup: { exercise in performanceProfile?.exerciseProfiles.first { $0.exercise?.id == exercise.id } }
        )
    }

    /// Commits exactly the adaptations `previewEnvironmentSwitch` already
    /// found for THIS session only — never a going-forward preference,
    /// never a change to any other Session/the `ProgramInstance`/the
    /// `TrainingMix` (`WorkoutEnvironmentAdaptationUseCase.apply`).
    func applyEnvironmentSwitch(_ adaptations: [WorkoutEnvironmentAdaptationUseCase.Adaptation], environment: TrainingEnvironment, modelContext: ModelContext) {
        try? WorkoutEnvironmentAdaptationUseCase.apply(adaptations, environment: environment)
        try? modelContext.save()
        load(modelContext: modelContext)
    }

    /// Reads only real, already-persisted `Goal`/`TrainingPlan`/
    /// `TrainingPhase` state (all unmodified by this checkpoint).
    private static func resolveActivePhase(modelContext: ModelContext) -> TrainingPhase? {
        let goals = (try? modelContext.fetch(FetchDescriptor<Goal>())) ?? []
        guard let activeGoal = goals.first(where: { $0.status == .active }) else { return nil }
        guard let activePlan = activeGoal.plans.first(where: { $0.status == .active }) else { return nil }
        return activePlan.orderedPhases.first(where: { $0.status == .active })
    }

    /// Starts (or, if already in progress, no-ops via
    /// `StartSessionUseCase`'s own idempotency guard) a Session directly
    /// from its Today card, then reloads so the card's status reflects
    /// the change immediately (Part C: "Morning: Completed / Evening:
    /// Ready" without marking the whole Day complete prematurely — each
    /// Session's own status drives its own card, independent of siblings).
    func start(_ session: Session, modelContext: ModelContext) {
        try? StartSessionUseCase.start(session, asOf: Date(), modelContext: modelContext)
        load(modelContext: modelContext)
    }

    /// Written only when the user actually taps this on the missed-
    /// session prompt — never a background process, never auto-applied
    /// just because `scheduledTime` has passed (`SESSION_STATE_MACHINE.md`
    /// §7, CLAUDE.md rule on not silently deciding facts for the user).
    func markMissed(_ session: Session, modelContext: ModelContext) {
        try? ChangeSessionStatusUseCase.markMissed(session, modelContext: modelContext)
        load(modelContext: modelContext)
    }
}
