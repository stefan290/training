import Foundation
import SwiftData

/// Everything the seeded dev dataset produced, handed back so previews and
/// tests can assert against or display it without re-querying the store.
struct SeedResult {
    let user: User
    let performanceProfile: PerformanceProfile
    let catalog: ExerciseCatalog
    let goal: Goal
    let plan: TrainingPlan
    let phaseA: TrainingPhase
    let phaseB: TrainingPhase
    let programDefinitionA: ProgramDefinition
    let programDefinitionB: ProgramDefinition
    let programInstanceA: ProgramInstance
    let programInstanceB: ProgramInstance
    let todaySessions: (morning: Session, evening: Session, programInstance: ProgramInstance, multiAlternativeSlot: ExerciseSlot)
}

/// Builds the fixed development dataset described in the Stage 2 brief:
/// eight distinct scenarios proving the domain model has no special cases,
/// plus the Program A -> Program B continuity case for the Performance
/// Profile. Every entity is created through the same use-case layer the
/// real app would use — nothing here bypasses RecordSetResultUseCase or
/// RecordWorkoutResultUseCase — and every relationship is established from
/// exactly one side via the owning model's `addX` method. See CLAUDE.md
/// and DELETE_RULE_MATRIX.md.
/// Everything `seedAll`'s own scenario-building needs before it starts —
/// broken out so the app's own bootstrap (`TrainingOSApp`) can seed these
/// shared prerequisites WITHOUT also rendering `seedAll`'s 8 hand-built
/// demo scenarios into the same user's Today/Week (Stage 7 Slice 4
/// acceptance finding: a Simulator user should see ONE coherent training
/// universe — the real, use-case-driven `SeedAnnualPlanJourney` — never
/// `seedAll`'s own scenario Sessions mixed in alongside it). `seedAll`
/// itself calls this internally so every existing test/preview that
/// depends on its exact return shape is completely unaffected.
struct SeedPrerequisites {
    let user: User
    let performanceProfile: PerformanceProfile
    let catalog: ExerciseCatalog
}

enum SeedDataProvider {
    @discardableResult
    static func seedPrerequisites(in context: ModelContext) -> SeedPrerequisites {
        let user = User(displayName: "Alex Rivera")
        context.insert(user)

        let profile = UserProfile()
        context.insert(profile)
        user.attachProfile(profile)

        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        user.attachPerformanceProfile(performanceProfile)

        let catalog = ExerciseCatalog.makeAndInsert(context: context)
        WarmupCatalog.makeAndInsert(exerciseCatalog: catalog, context: context)

        return SeedPrerequisites(user: user, performanceProfile: performanceProfile, catalog: catalog)
    }

    @discardableResult
    static func seedAll(in context: ModelContext) -> SeedResult {
        let prerequisites = seedPrerequisites(in: context)
        let user = prerequisites.user
        let performanceProfile = prerequisites.performanceProfile
        let catalog = prerequisites.catalog

        let goal = Goal(ownerUserID: user.id, primaryType: .muscleGain, status: .active)
        context.insert(goal)
        user.addGoal(goal)

        let plan = TrainingPlan(status: .active)
        context.insert(plan)
        goal.addPlan(plan)

        // Phase A / Program A: completed, proving history survives once a
        // phase and its program instance are no longer active.
        let phaseA = TrainingPhase(
            type: .muscleGain,
            startDate: dayStart(offset: -10),
            endDate: dayStart(offset: -3),
            priorityRule: .strength,
            status: .completed
        )
        context.insert(phaseA)
        plan.addPhase(phaseA)

        let programDefinitionA = ProgramDefinition(name: "5-Day Hypertrophy", lengthWeeks: 8, intent: "Linear hypertrophy across five weekly sessions.")
        context.insert(programDefinitionA)
        for weekIndex in 0..<8 {
            let week = TrainingWeek(isDeload: weekIndex == 5)
            context.insert(week)
            programDefinitionA.addWeek(week)
        }

        let programInstanceA = ProgramInstance(ownerUserID: user.id, startDate: dayStart(offset: -10), status: .completed)
        programInstanceA.programDefinition = programDefinitionA
        context.insert(programInstanceA)
        phaseA.addProgramInstance(programInstanceA)

        // Phase B / Program B: active, started after Phase A completed.
        let phaseB = TrainingPhase(
            type: .strength,
            startDate: dayStart(offset: -2),
            priorityRule: .strength,
            status: .active
        )
        context.insert(phaseB)
        plan.addPhase(phaseB)

        let programDefinitionB = ProgramDefinition(name: "3-Day Full Body", lengthWeeks: 6, intent: "Full-body strength, three sessions per week.")
        context.insert(programDefinitionB)
        for _ in 0..<6 {
            let week = TrainingWeek(isDeload: false)
            context.insert(week)
            programDefinitionB.addWeek(week)
        }

        let programInstanceB = ProgramInstance(ownerUserID: user.id, startDate: dayStart(offset: -2), status: .active)
        programInstanceB.programDefinition = programDefinitionB
        context.insert(programInstanceB)
        phaseB.addProgramInstance(programInstanceB)

        // A-G: one distinct historical day each, under Program A.
        SeedScenarios.hypertrophySession(
            day: makeDay(offset: -10, ownerUserID: user.id, context: context),
            catalog: catalog,
            performanceProfile: performanceProfile,
            programInstance: programInstanceA,
            modelContext: context
        )
        SeedScenarios.zone2Session(
            day: makeDay(offset: -9, ownerUserID: user.id, context: context),
            catalog: catalog,
            programInstance: programInstanceA,
            modelContext: context
        )
        SeedScenarios.intervalSession(
            day: makeDay(offset: -8, ownerUserID: user.id, context: context),
            catalog: catalog,
            programInstance: programInstanceA,
            modelContext: context
        )
        SeedScenarios.amrapSession(
            day: makeDay(offset: -7, ownerUserID: user.id, context: context),
            catalog: catalog,
            programInstance: programInstanceA,
            modelContext: context
        )
        SeedScenarios.emomSession(
            day: makeDay(offset: -6, ownerUserID: user.id, context: context),
            catalog: catalog,
            programInstance: programInstanceA,
            modelContext: context
        )
        SeedScenarios.forTimeBenchmarkSession(
            day: makeDay(offset: -5, ownerUserID: user.id, context: context),
            catalog: catalog,
            performanceProfile: performanceProfile,
            programInstance: programInstanceA,
            modelContext: context
        )
        SeedScenarios.hybridStrengthAndMetconSession(
            day: makeDay(offset: -4, ownerUserID: user.id, context: context),
            catalog: catalog,
            performanceProfile: performanceProfile,
            programInstance: programInstanceA,
            modelContext: context
        )

        // Continuity case: Program A has ended, Program B has begun, and
        // logging Bench Press again must land in the same permanent
        // history as before.
        SeedScenarios.benchPressContinuitySession(
            day: makeDay(offset: -1, ownerUserID: user.id, context: context),
            catalog: catalog,
            performanceProfile: performanceProfile,
            programInstance: programInstanceB,
            modelContext: context
        )

        // H: today, two scheduled sessions, nothing logged yet.
        let todaySessions = SeedScenarios.twoSessionsSameDay(
            day: makeDay(offset: 0, ownerUserID: user.id, context: context),
            catalog: catalog,
            ownerUserID: user.id,
            modelContext: context
        )

        // Stage 6C: a real, scheduled (not yet performed) future Session
        // within the current week, so Week's read-only future-Session
        // inspection (Part R) has genuine materialized data to show —
        // never a fabricated exact prescription beyond what's actually
        // materialized. Renamed after creation, distinct from the
        // historical "Zone 2 Run" scenario above, so name-based test/UI
        // lookups never collide between the two.
        let upcomingZone2 = SeedScenarios.zone2Session(
            day: makeDay(offset: 1, ownerUserID: user.id, context: context),
            catalog: catalog,
            programInstance: programInstanceB,
            modelContext: context,
            status: .scheduled
        )
        upcomingZone2.name = "Upcoming Zone 2"

        return SeedResult(
            user: user,
            performanceProfile: performanceProfile,
            catalog: catalog,
            goal: goal,
            plan: plan,
            phaseA: phaseA,
            phaseB: phaseB,
            programDefinitionA: programDefinitionA,
            programDefinitionB: programDefinitionB,
            programInstanceA: programInstanceA,
            programInstanceB: programInstanceB,
            todaySessions: todaySessions
        )
    }

    static func dayStart(offset: Int) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    static func makeDay(offset: Int, ownerUserID: UUID, context: ModelContext) -> Day {
        let day = Day(ownerUserID: ownerUserID, date: dayStart(offset: offset))
        context.insert(day)
        return day
    }
}
