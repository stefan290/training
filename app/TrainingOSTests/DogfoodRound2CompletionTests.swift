import XCTest
import SwiftData
@testable import TrainingOS

/// Dogfood Round 2 — real manual dogfood findings from Stefan's committed
/// build (`e533220`):
///
/// 1. Athlete cannot review/change training-day/double-session decisions
///    after onboarding.
/// 2. `RollTacticalWindowUseCase.rollForward`'s un-normalized `asOf` could
///    create a second `Day` entity for a calendar date an earlier,
///    properly-midnight-normalized call already used.
/// 3. A Functional Fitness program's own embedded strength block never
///    resolved a real exercise — `ResolveProgramInstanceExerciseSlotsUseCase`
///    was never widened to cover it.
/// 4. Muscle Gain Functional Fitness was still fundamentally a traditional
///    metcon with a strength block attached, never a real Functional
///    Bodybuilding / athletic-hypertrophy session with subordinate
///    conditioning.
///
/// Every test here runs through the real production path already
/// established by `ConcurrentProgrammingGoldenScenarioTests`
/// (`AppRootStateResolver.ensureBaselineIdentity` -> real seeded
/// `ExerciseCatalog` -> `StrategicPlanSelectionViewModel.buildCustomMix`
/// -> `acceptAndStart` -> `StartPhaseUseCase.start` -> real materializers)
/// wherever the finding is reachable that way; narrower unit-level tests
/// are used only where the real path would require excessive unrelated
/// setup for a fact provable at the engine level alone.
@MainActor
final class DogfoodRound2CompletionTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar.current.date(from: components)!
    }

    @discardableResult
    private func makeOnboardedAthlete(
        goalType: GoalType = .muscleGain, trainingDays: Int, allowsDoubles: Bool = false
    ) throws -> (user: User, goal: Goal) {
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        user.profile?.trainingEnvironments = [environment]
        user.profile?.defaultTrainingEnvironment = environment
        let goal = Goal(
            ownerUserID: user.id, primaryType: goalType,
            preferences: GoalPreferences(availableTrainingDaysPerWeek: trainingDays, allowsDoubleSessions: allowsDoubles)
        )
        context.insert(goal)
        user.addGoal(goal)
        try context.save()
        return (user, goal)
    }

    private func loadedViewModel(referenceDate: Date) -> StrategicPlanSelectionViewModel {
        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context, referenceDate: referenceDate)
        return viewModel
    }

    private func completeAnyCalibration(goal: Goal, trainingDays: Int, allowsDoubles: Bool = false, asOf: Date) throws {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let environment = goal.user?.profile?.defaultTrainingEnvironment
        guard let phase = goal.plans.first?.orderedPhases.first else { return }
        try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: phase, performanceProfile: goal.user?.performanceProfile,
            availability: UserAvailability(trainingDaysPerWeek: trainingDays, allowsDoubleSessions: allowsDoubles, maxSessionsPerDay: allowsDoubles ? 2 : 1),
            materializationContext: TacticalMaterializationContext(
                equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
                strengthCandidateExercises: exercises, functionalFitnessCandidateExercises: exercises,
                trainingEnvironment: environment
            ),
            asOf: asOf,
            context: context
        )
    }

    // MARK: - Acceptance journey: Stefan's exact real dogfood scenario

    /// Goal=Build Muscle, current phase=Muscle Gain, 5 days/week, Full Gym,
    /// TrainingMix=4 Hypertrophy + 1 Functional Fitness, doubles OFF —
    /// proves items 1, 3, 6-13 of the required acceptance journey in one
    /// real, end-to-end pass.
    func testAcceptanceJourney_BuildMuscleFourHypertrophyOneFunctionalFitness() throws {
        let monday = date(2026, 1, 5)
        let (_, goal) = try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: 5, allowsDoubles: false)
        let viewModel = loadedViewModel(referenceDate: monday)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.hypertrophy, 4), (.functionalFitness, 1)]))
        let mix = try XCTUnwrap(viewModel.reviewedMix)
        // 13: exact 4H + 1FF mix remains authoritative — never silently
        // dropped or altered.
        XCTAssertEqual(mix.orderedComponents.count, 2)
        XCTAssertEqual(mix.orderedComponents.first { $0.programmingSystem == .hypertrophy }?.frequency.target, 4)
        XCTAssertEqual(mix.orderedComponents.first { $0.programmingSystem == .functionalFitness }?.frequency.target, 1)

        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))
        try completeAnyCalibration(goal: goal, trainingDays: 5, asOf: monday)

        let hypertrophySessions = mix.orderedComponents.first { $0.programmingSystem == .hypertrophy }?.programInstance?.sessions ?? []
        let ffSessions = mix.orderedComponents.first { $0.programmingSystem == .functionalFitness }?.programInstance?.sessions ?? []
        // 1: exactly five sessions scheduled across five distinct calendar days.
        XCTAssertEqual(hypertrophySessions.count, 4)
        XCTAssertEqual(ffSessions.count, 1)
        let allSessions = hypertrophySessions + ffSessions
        let distinctDates = Set(allSessions.compactMap { $0.day.map { Calendar.current.startOfDay(for: $0.date) } })
        XCTAssertEqual(distinctDates.count, 5, "five real sessions must land on five distinct calendar days — no unapproved double session")

        // 2: no duplicate Day entity exists for the same calendar date.
        let ownerID = goal.ownerUserID
        // Real materializers each create their own naive `Day` before
        // scheduling ever runs, keyed off their own dayIndex — when
        // scheduling later moves a session to a different real day, the
        // ABANDONED naive `Day` is left behind, empty but not deleted
        // (`Day.addSession`'s own nullify-not-cascade discipline). This is
        // a pre-existing, harmless architectural byproduct, unrelated to
        // Finding 2 — confirmed by direct inspection to already occur on
        // the pristine baseline. The real invariant Finding 2 protects is
        // narrower: exactly one Day HOLDING A SESSION per real calendar
        // date, and never more than one session on it — proven here, and
        // proven precisely (including the exact non-midnight-asOf defect
        // mechanism) by `testFinding2_RollForwardNormalizesAsOfSoNoDuplicateDayEntityIsCreated`
        // below.
        let allDays = try context.fetch(FetchDescriptor<Day>(predicate: #Predicate { $0.ownerUserID == ownerID }))
        for uniqueDate in distinctDates {
            let matchingWithSessions = allDays.filter { Calendar.current.isDate($0.date, inSameDayAs: uniqueDate) && !$0.orderedSessions.isEmpty }
            XCTAssertEqual(matchingWithSessions.count, 1, "exactly one Day must hold a real session for this calendar date")
            XCTAssertEqual(matchingWithSessions.first?.orderedSessions.count, 1, "with doubles off, at most one session per day")
        }

        let ffSession = try XCTUnwrap(ffSessions.first)
        let strengthBlock = ffSession.orderedBlocks.first { ($0.type == .strength || $0.type == .hypertrophy) }
        let ffBlock = try XCTUnwrap(ffSession.orderedBlocks.first { $0.functionalFitnessPrescription != nil })
        let ffPrescription = try XCTUnwrap(ffBlock.functionalFitnessPrescription)

        // 6/7: the FF session contains real executable Functional
        // Bodybuilding work — never "Strength — No exercises."
        let strengthPrescription = try XCTUnwrap(strengthBlock?.orderedPrescriptions.first, "a real strength block must materialize for a Muscle Gain phase")
        XCTAssertNotNil(strengthPrescription.exercise, "the strength block must carry a real, resolved exercise — never nil")

        // 8: dominant identity is Muscle-Gain-appropriate Functional Bodybuilding.
        XCTAssertEqual(ffPrescription.archetype, .functionalBodybuilding)

        // 10: athlete-facing overview reflects the real hierarchy.
        XCTAssertEqual(BlockPresentation.functionalFitnessAwareBlockLabel(for: try XCTUnwrap(strengthBlock)), "Functional Bodybuilding")
        XCTAssertEqual(BlockPresentation.functionalFitnessAwareBlockLabel(for: ffBlock), "Conditioning")

        // 9: conditioning exists as a subordinate component (real, composed
        // FF movements, never suppressed to nothing).
        XCTAssertFalse(ffPrescription.orderedMovements.isEmpty)

        // 12: FF relative-load guidance (or a real numeric load) remains
        // visible for every loaded movement — Dogfood Round 1 invariant,
        // unbroken by this round's archetype bias.
        let loadedMovements = ffPrescription.orderedMovements.filter { $0.exercise?.functionalModality == .weightlifting }
        for movement in loadedMovements {
            XCTAssertTrue(movement.loadKilograms != nil || movement.relativeLoadTier != nil, "every loaded FF movement must carry a numeric load or relative guidance")
        }

        // 5: active/completed history preserved by a preference change —
        // proven below via TrainingPreferencesViewModel against this exact
        // already-materialized state.
        let preChangeDates = distinctDates

        // 3/4: changing training-day availability post-onboarding is
        // possible, and a change that would strain the current mix shows
        // its real consequence before it's applied.
        let prefsViewModel = TrainingPreferencesViewModel()
        prefsViewModel.load(modelContext: context)
        // Independent Review Correction 1: onboarding's own legacy
        // day-COUNT question never implies specific weekdays — the
        // athlete never having opened this real editor before means "no
        // restriction" (every weekday selected), never a guess at which
        // 5 of 7 days the original "5" meant.
        XCTAssertEqual(prefsViewModel.selectedWeekdays, Set(Weekday.allCases))
        XCTAssertEqual(prefsViewModel.availableTrainingDaysPerWeek, 7)
        XCTAssertEqual(prefsViewModel.allowsDoubleSessions, false)
        XCTAssertEqual(prefsViewModel.currentMixSummary, PlanPresentation.mixSummary(mix))
        prefsViewModel.selectedWeekdays = [.monday, .tuesday, .wednesday, .thursday]
        let consequence = prefsViewModel.previewConsequence()
        XCTAssertEqual(consequence, .exceedsCapacityEvenWithDoubles(shortfallSessionsPerWeek: 1), "4H+1FF (5 sessions) cannot fit 4 real weekdays with doubles still off")
        XCTAssertTrue(prefsViewModel.save(modelContext: context))
        XCTAssertEqual(goal.preferences?.availableWeekdays, [.monday, .tuesday, .wednesday, .thursday])
        XCTAssertEqual(goal.preferences?.availableTrainingDaysPerWeek, 4)

        // 5 (continued): the already-materialized sessions/days are
        // completely untouched by that save.
        let postChangeDays = try context.fetch(FetchDescriptor<Day>(predicate: #Predicate { $0.ownerUserID == ownerID }))
        let postChangeDates = Set(postChangeDays.flatMap(\.orderedSessions).compactMap { $0.day.map { Calendar.current.startOfDay(for: $0.date) } })
        XCTAssertEqual(postChangeDates, preChangeDates, "a preference save must never rewrite the already-materialized active tactical week")
    }

    // MARK: - Finding 1: athlete-configurable training preferences

    /// Real weekday selection round-trips exactly — never a guessed
    /// subset inferred from the legacy count.
    func testFinding1_TrainingPreferencesViewModelLoadsRealPersistedValues() throws {
        let (_, goal) = try makeOnboardedAthlete(trainingDays: 4, allowsDoubles: true)
        goal.preferences?.availableWeekdays = [.monday, .wednesday, .friday, .saturday]
        goal.preferences?.typicalSessionDurationMinutes = 60
        goal.preferences?.varietyPreference = .high
        try context.save()

        let viewModel = TrainingPreferencesViewModel()
        viewModel.load(modelContext: context)
        XCTAssertEqual(viewModel.selectedWeekdays, [.monday, .wednesday, .friday, .saturday])
        XCTAssertEqual(viewModel.availableTrainingDaysPerWeek, 4)
        XCTAssertEqual(viewModel.allowsDoubleSessions, true)
        XCTAssertEqual(viewModel.typicalSessionDurationMinutes, 60)
        XCTAssertEqual(viewModel.varietyPreference, .high)
    }

    /// A pre-existing athlete who has never opened this real editor sees
    /// "no restriction" (every weekday), never a guess at which specific
    /// days their old onboarding day-count meant.
    func testFinding1_LegacyDayCountAloneNeverInfersSpecificWeekdays() throws {
        try makeOnboardedAthlete(trainingDays: 5, allowsDoubles: false)
        let viewModel = TrainingPreferencesViewModel()
        viewModel.load(modelContext: context)
        XCTAssertEqual(viewModel.selectedWeekdays, Set(Weekday.allCases), "no explicit weekday choice exists yet — this must never guess a subset from the legacy count")
        XCTAssertEqual(viewModel.availableTrainingDaysPerWeek, 7)
    }

    func testFinding1_SaveOnlyEverPersistsGoalPreferencesNeverDuplicateStorage() throws {
        let (_, goal) = try makeOnboardedAthlete(trainingDays: 5, allowsDoubles: false)
        let viewModel = TrainingPreferencesViewModel()
        viewModel.load(modelContext: context)
        viewModel.selectedWeekdays = [.monday, .wednesday, .friday]
        viewModel.allowsDoubleSessions = true
        XCTAssertTrue(viewModel.save(modelContext: context))

        // Reused, real `GoalPreferences` — never a second, parallel
        // persisted preferences model. `availableWeekdays` is the one
        // real truth; `availableTrainingDaysPerWeek` is kept strictly in
        // sync as its count, never independently settable.
        XCTAssertEqual(goal.preferences?.availableWeekdays, [.monday, .wednesday, .friday])
        XCTAssertEqual(goal.preferences?.availableTrainingDaysPerWeek, 3)
        XCTAssertEqual(goal.preferences?.allowsDoubleSessions, true)
    }

    /// Saving with zero weekdays selected must be refused outright —
    /// never silently persisted as "no restriction."
    func testFinding1_SaveRefusesAnEmptyWeekdaySelection() throws {
        try makeOnboardedAthlete(trainingDays: 5, allowsDoubles: false)
        let viewModel = TrainingPreferencesViewModel()
        viewModel.load(modelContext: context)
        viewModel.selectedWeekdays = []
        XCTAssertFalse(viewModel.save(modelContext: context))
    }

    func testFinding1_EvaluateConsequence_FitsAsIs() {
        let components = [TrainingMixComponent(label: "A", priority: .primary, frequency: SessionFrequency(target: 3))]
        let consequence = EvaluateTrainingPreferencesChangeUseCase.evaluate(
            activeComponents: components, newAvailableTrainingDaysPerWeek: 5, newAllowsDoubleSessions: false
        )
        XCTAssertEqual(consequence, .fitsAsIs)
    }

    func testFinding1_EvaluateConsequence_RequiresDoubleSessions() {
        let components = [
            TrainingMixComponent(label: "A", priority: .primary, frequency: SessionFrequency(target: 4)),
            TrainingMixComponent(label: "B", priority: .secondary, frequency: SessionFrequency(target: 2)),
        ]
        let consequence = EvaluateTrainingPreferencesChangeUseCase.evaluate(
            activeComponents: components, newAvailableTrainingDaysPerWeek: 4, newAllowsDoubleSessions: true
        )
        XCTAssertEqual(consequence, .requiresDoubleSessions)
    }

    func testFinding1_EvaluateConsequence_ExceedsCapacityEvenWithDoubles() {
        let components = [TrainingMixComponent(label: "A", priority: .primary, frequency: SessionFrequency(target: 10))]
        let consequence = EvaluateTrainingPreferencesChangeUseCase.evaluate(
            activeComponents: components, newAvailableTrainingDaysPerWeek: 3, newAllowsDoubleSessions: true
        )
        XCTAssertEqual(consequence, .exceedsCapacityEvenWithDoubles(shortfallSessionsPerWeek: 4))
    }

    /// Proves the real, previously-hardcoded
    /// `UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions:
    /// false, maxSessionsPerDay: 1)` in `PhaseDetailViewModel
    /// .advanceTacticalWeek` now genuinely reads the athlete's own current
    /// `Goal.preferences.allowsDoubleSessions` — the one field of the two
    /// that actually has real scheduling teeth
    /// (`availableTrainingDaysPerWeek` is documented, informational-only:
    /// `UserAvailability`'s own hard limits are `availableWeekdays`/
    /// `maxSessionsPerDay`, and no per-weekday restriction is collected
    /// anywhere in this app today — Dogfood Round 2's own trace). A mix
    /// requiring 8 sessions/week (more than a 7-day window without at
    /// least one double) can only roll forward successfully if the
    /// athlete's real `allowsDoubleSessions == true` preference actually
    /// reaches the scheduler — under the OLD hardcoded
    /// `allowsDoubleSessions: false`, this exact roll would be
    /// infeasible regardless of what the athlete had really approved.
    func testFinding1_AdvanceTacticalWeekRespectsRealGoalPreferencesAllowsDoubleSessions() throws {
        let monday = date(2026, 1, 5)
        // `trainingDays: 10` clears `buildCustomMix`'s own separate
        // weekly-capacity gate (`total <= capacity`, unrelated to this
        // finding) — the real constraint this test exercises is the
        // scheduler's always-7-real-calendar-day window, which 8
        // sessions genuinely cannot fit without at least one double.
        let (_, goal) = try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: 10, allowsDoubles: true)
        let viewModel = loadedViewModel(referenceDate: monday)
        // 6 Hypertrophy + 2 Functional Fitness = 8 sessions/week — more
        // than 7 real calendar days, so at least one real double session
        // is structurally required just to fit.
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.hypertrophy, 6), (.functionalFitness, 2)]))
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))
        try completeAnyCalibration(goal: goal, trainingDays: 10, allowsDoubles: true, asOf: monday)

        guard let phase = goal.plans.first?.orderedPhases.first else { return XCTFail("no phase") }
        for component in (phase.selectedTrainingMix ?? phase.recommendedTrainingMix)?.orderedComponents ?? [] {
            for session in component.programInstance?.sessions ?? [] {
                try ChangeSessionStatusUseCase.skip(session, modelContext: context)
            }
        }
        // Reaffirm the real, current preference explicitly — this is what
        // `PhaseDetailViewModel.advanceTacticalWeek` must itself read,
        // never a value baked in at an earlier call.
        goal.preferences?.allowsDoubleSessions = true
        try context.save()

        let phaseDetailViewModel = PhaseDetailViewModel()
        phaseDetailViewModel.load(phase: phase, modelContext: context)
        let advanced = phaseDetailViewModel.advanceTacticalWeek(modelContext: context)
        XCTAssertTrue(advanced, "the athlete's real allowsDoubleSessions == true preference must reach the scheduler on this roll — the old hardcoded `false` would have made this exact 8-session/week roll infeasible")
    }

    // MARK: - Independent Review Correction 1: real weekday availability

    /// Maps a `Date` to this app's own `Weekday` convention (Monday = 1
    /// ... Sunday = 7) — mirrors `ConcurrentScheduler`'s own private,
    /// identical mapping, duplicated here only because that one is
    /// private to that file.
    private func appWeekday(for date: Date) -> Weekday {
        let raw = Calendar(identifier: .gregorian).component(.weekday, from: date)
        let mapped = raw == 1 ? 7 : raw - 1
        return Weekday(rawValue: mapped) ?? .monday
    }

    /// Item 1: the athlete selects exactly four real weekdays, and they
    /// persist exactly — never a guessed subset, never a disagreeing
    /// count.
    func testCorrection1_ExactlyFourWeekdaysSelectedPersistExactly() throws {
        let (_, goal) = try makeOnboardedAthlete(trainingDays: 7, allowsDoubles: false)
        let viewModel = TrainingPreferencesViewModel()
        viewModel.load(modelContext: context)
        viewModel.selectedWeekdays = [.monday, .tuesday, .thursday, .saturday]
        XCTAssertTrue(viewModel.save(modelContext: context))
        XCTAssertEqual(goal.preferences?.availableWeekdays, [.monday, .tuesday, .thursday, .saturday])
        XCTAssertEqual(goal.preferences?.availableTrainingDaysPerWeek, 4, "the count is derived from the real weekday selection, never a second, independently-set truth")
    }

    /// Items 2-4: the athlete's real selected weekdays reach
    /// `UserAvailability.availableWeekdays` on the next tactical roll
    /// (`PhaseDetailViewModel.currentAvailability`), and no session ever
    /// lands on an unavailable weekday.
    func testCorrection1_SelectedWeekdaysReachSchedulerAndUnavailableWeekdaysAreNeverUsed() throws {
        let monday = date(2026, 1, 5)
        let (_, goal) = try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: 7, allowsDoubles: false)
        let viewModel = loadedViewModel(referenceDate: monday)
        // 4 Hypertrophy/week only — isolates the weekday constraint from
        // any Functional Fitness same-week complementarity logic.
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.hypertrophy, 4)]))
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))
        try completeAnyCalibration(goal: goal, trainingDays: 7, asOf: monday)

        guard let phase = goal.plans.first?.orderedPhases.first else { return XCTFail("no phase") }
        let instance = try XCTUnwrap(phase.primaryInstance)
        let week0SessionIDs = Set(instance.sessions.map(\.id))
        for component in (phase.selectedTrainingMix ?? phase.recommendedTrainingMix)?.orderedComponents ?? [] {
            for session in component.programInstance?.sessions ?? [] {
                try ChangeSessionStatusUseCase.skip(session, modelContext: context)
            }
        }

        // The athlete selects exactly four real weekdays.
        let selected: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday]
        goal.preferences?.availableWeekdays = selected
        goal.preferences?.availableTrainingDaysPerWeek = selected.count
        goal.preferences?.allowsDoubleSessions = false
        try context.save()

        let phaseDetailViewModel = PhaseDetailViewModel()
        phaseDetailViewModel.load(phase: phase, modelContext: context)
        let advanced = phaseDetailViewModel.advanceTacticalWeek(modelContext: context)
        XCTAssertTrue(advanced, "4 required sessions must fit within the 4 selected real weekdays")

        // `advanceTacticalWeek` rolls relative to the real `Date()`, not
        // `monday` — identify the newly-rolled week's sessions by set
        // difference from week 0's own, rather than assuming a date
        // range relative to the test's own fixture date.
        let week1Sessions = instance.sessions.filter { !week0SessionIDs.contains($0.id) }
        XCTAssertEqual(week1Sessions.count, 4, "the exact weekly TrainingMix must still roll forward — never silently dropped")
        for session in week1Sessions {
            let day = try XCTUnwrap(session.day)
            let weekday = appWeekday(for: day.date)
            XCTAssertTrue(selected.contains(weekday), "a session landed on \(weekday), which the athlete never made available — a 5th/6th/7th-day session must never silently land on an unavailable weekday")
        }
    }

    /// Items 5-7: the same real 4-weekday selection, evaluated against a
    /// real 4H+1FF (5-session) mix — infeasible with doubles off, requires
    /// a double when doubles are allowed, and never touches already-
    /// materialized history either way.
    func testCorrection1_FourWeekdaysWithFiveRequiredSessionsConsequenceAndHistoryPreservation() throws {
        let monday = date(2026, 1, 5)
        let (_, goal) = try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: 7, allowsDoubles: false)
        let viewModel = loadedViewModel(referenceDate: monday)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.hypertrophy, 4), (.functionalFitness, 1)]))
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))
        try completeAnyCalibration(goal: goal, trainingDays: 7, asOf: monday)

        let ownerID = goal.ownerUserID
        let allDaysBefore = try context.fetch(FetchDescriptor<Day>(predicate: #Predicate { $0.ownerUserID == ownerID }))
        let preChangeDates = Set(allDaysBefore.flatMap(\.orderedSessions).compactMap { $0.day.map { Calendar.current.startOfDay(for: $0.date) } })
        XCTAssertEqual(preChangeDates.count, 5)

        let prefsViewModel = TrainingPreferencesViewModel()
        prefsViewModel.load(modelContext: context)
        prefsViewModel.selectedWeekdays = [.monday, .tuesday, .wednesday, .thursday]

        // Item 5: doubles OFF — 5 required sessions cannot fit 4 real
        // available weekdays.
        XCTAssertEqual(prefsViewModel.previewConsequence(), .exceedsCapacityEvenWithDoubles(shortfallSessionsPerWeek: 1))

        // Item 6: doubles ON — now fits, but only via a double session.
        prefsViewModel.allowsDoubleSessions = true
        XCTAssertEqual(prefsViewModel.previewConsequence(), .requiresDoubleSessions)

        XCTAssertTrue(prefsViewModel.save(modelContext: context))

        // Item 7: the already-materialized active week is byte-identical
        // before and after this save, regardless of which consequence was
        // shown.
        let allDaysAfter = try context.fetch(FetchDescriptor<Day>(predicate: #Predicate { $0.ownerUserID == ownerID }))
        let postChangeDates = Set(allDaysAfter.flatMap(\.orderedSessions).compactMap { $0.day.map { Calendar.current.startOfDay(for: $0.date) } })
        XCTAssertEqual(postChangeDates, preChangeDates, "a preference save must never rewrite the already-materialized active tactical week, regardless of the consequence shown")
    }

    // MARK: - Finding 2: no duplicate Day entity from a non-midnight asOf

    /// Reproduces the exact defect: `rollForward` is invoked with a raw,
    /// non-midnight `asOf` (mirroring `PhaseDetailViewModel
    /// .advanceTacticalWeek`'s real `Date()` call). Before the fix, every
    /// `Day` this call placed a session on would carry `asOf`'s own raw
    /// time-of-day; after it, every such `Day` is exactly midnight-
    /// normalized, and never more than one real Day holds a session for
    /// the same calendar date.
    func testFinding2_RollForwardNormalizesAsOfSoDayDatesAreMidnightAndNeverDoubleUp() throws {
        let monday = date(2026, 1, 5)
        let (_, goal) = try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: 5, allowsDoubles: false)
        let viewModel = loadedViewModel(referenceDate: monday)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.hypertrophy, 4), (.functionalFitness, 1)]))
        let mix = try XCTUnwrap(viewModel.reviewedMix)
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))
        try completeAnyCalibration(goal: goal, trainingDays: 5, asOf: monday)

        let ownerID = goal.ownerUserID
        let nextWeekApprox = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: monday))
        // Raw, non-midnight `asOf` — mirrors
        // `PhaseDetailViewModel.advanceTacticalWeek`'s real `Date()` call
        // exactly (a real wall-clock timestamp, never pre-normalized by
        // any caller).
        let rawAsOf = try XCTUnwrap(Calendar.current.date(byAdding: .hour, value: 14, to: nextWeekApprox))
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let environment = goal.user?.profile?.defaultTrainingEnvironment
        let materializationContext = TacticalMaterializationContext(
            equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
            strengthCandidateExercises: exercises, functionalFitnessCandidateExercises: exercises,
            trainingEnvironment: environment
        )
        let availability = UserAvailability(trainingDaysPerWeek: 5, allowsDoubleSessions: false, maxSessionsPerDay: 1)

        let result = try XCTUnwrap(RollTacticalWindowUseCase.rollForward(
            mix: mix, asOf: rawAsOf, ownerUserID: ownerID, performanceProfile: nil,
            availability: availability, materializationContext: materializationContext, context: context
        ))
        // The exact weekly TrainingMix is not silently dropped.
        XCTAssertFalse(result.newSessionsByComponent.isEmpty)
        XCTAssertEqual(result.newSessionsByComponent.values.flatMap { $0 }.count, 5, "all 4 Hypertrophy + 1 Functional Fitness sessions must still roll forward")

        let allDays = try context.fetch(FetchDescriptor<Day>(predicate: #Predicate { $0.ownerUserID == ownerID }))
        let daysWithSessions = allDays.filter { !$0.orderedSessions.isEmpty }
        XCTAssertFalse(daysWithSessions.isEmpty)
        for day in daysWithSessions {
            XCTAssertEqual(day.date, Calendar.current.startOfDay(for: day.date), "every real Day a rolled-forward session lands on must be exactly midnight-normalized — never carrying asOf's raw time-of-day")
        }
        // Never two different Day rows both holding a session for the
        // same real calendar date, and never more than one session per
        // Day with doubles disallowed — the invariant this defect broke.
        let byCalendarDate = Dictionary(grouping: daysWithSessions) { Calendar.current.startOfDay(for: $0.date) }
        for (_, days) in byCalendarDate {
            XCTAssertEqual(days.count, 1, "at most one real Day may hold a session for a given calendar date")
            XCTAssertLessThanOrEqual(days.first?.orderedSessions.count ?? 0, 1, "with double sessions disallowed, at most one session may land on this Day")
        }
    }

    // MARK: - Finding 3: FF strength slot resolution / no empty blocks

    func testFinding3_FFStrengthSlotResolvesARealExerciseThroughStartPhaseUseCase() throws {
        let monday = date(2026, 1, 5)
        let (_, goal) = try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: 5, allowsDoubles: false)
        let viewModel = loadedViewModel(referenceDate: monday)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.hypertrophy, 4), (.functionalFitness, 1)]))
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))
        try completeAnyCalibration(goal: goal, trainingDays: 5, asOf: monday)

        guard let phase = goal.plans.first?.orderedPhases.first,
              let ffComponent = (phase.selectedTrainingMix ?? phase.recommendedTrainingMix)?.orderedComponents.first(where: { $0.programmingSystem == .functionalFitness }),
              let ffSession = ffComponent.programInstance?.sessions.first
        else { return XCTFail("expected a real FF session") }

        let strengthBlock = try XCTUnwrap(ffSession.orderedBlocks.first { ($0.type == .strength || $0.type == .hypertrophy) })
        let prescription = try XCTUnwrap(strengthBlock.orderedPrescriptions.first)
        XCTAssertNotNil(prescription.exercise, "the embedded strength slot must resolve a real exercise, never stay nil")
        XCTAssertFalse(prescription.orderedSetPrescriptions.isEmpty)
    }

    /// Invariant: a generated WorkoutBlock must either contain a legitimate
    /// executable prescription or not exist — never a persisted
    /// "Strength — No exercises." Proven directly at the materializer
    /// level with a genuinely empty strength candidate pool.
    func testFinding3_NoStrengthCandidatesMeansTheBlockIsAbsentNeverEmpty() throws {
        let weeklyPlan = try XCTUnwrap(FunctionalFitnessAuthoredProgramLibrary.weeklyPlan(forSessionsPerWeek: 2))
        let biased = FunctionalFitnessPhaseBiasPolicy.apply(weeklyPlan, phaseType: .muscleGain)
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 2, lengthWeeks: 4, targetStimulus: biased[0].stimulus, format: biased[0].format,
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false, weeklyPlan: biased
        )
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition

        // Deliberately never resolves the strength slot (no
        // `ResolveProgramInstanceExerciseSlotsUseCase.resolve` call, no
        // GOING FORWARD override) — the honest "genuinely could not
        // resolve" state.
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let ffCandidates = [
            Exercise(canonicalName: "Test Pull-up", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "test", movementFunctions: [.gymnasticsPull], functionalModality: .gymnastics),
            Exercise(canonicalName: "Test Bike", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "test", movementFunctions: [.monostructural], functionalModality: .metabolicConditioning, measuredDimensions: [.distance]),
        ]
        for exercise in ffCandidates { context.insert(exercise) }

        let sessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, startDate: Date(), ownerUserID: instance.ownerUserID,
            candidateExercises: ffCandidates, exposureHistory: [], environment: environment, context: context
        )
        let structuredSession = try XCTUnwrap(sessions.first { session in session.orderedBlocks.contains { $0.functionalFitnessPrescription != nil } })
        XCTAssertNil(structuredSession.orderedBlocks.first { ($0.type == .strength || $0.type == .hypertrophy) }, "an unresolvable strength block must not exist at all — never a persisted empty one")
    }

    // MARK: - Finding 4: real phase-biased Functional Fitness archetype

    func testFinding4_MuscleGainArchetypeIsFunctionalBodybuilding() throws {
        let weeklyPlan = try XCTUnwrap(FunctionalFitnessAuthoredProgramLibrary.weeklyPlan(forSessionsPerWeek: 1))
        let biased = FunctionalFitnessPhaseBiasPolicy.apply(weeklyPlan, phaseType: .muscleGain)
        XCTAssertTrue(biased.allSatisfy { $0.archetype == .functionalBodybuilding })
        XCTAssertTrue(biased.allSatisfy(\.includeStrengthBlock))
    }

    func testFinding4_StrengthArchetypeIsDistinctFromMuscleGain() throws {
        let weeklyPlan = try XCTUnwrap(FunctionalFitnessAuthoredProgramLibrary.weeklyPlan(forSessionsPerWeek: 1))
        let muscleGainBiased = FunctionalFitnessPhaseBiasPolicy.apply(weeklyPlan, phaseType: .muscleGain)
        let strengthBiased = FunctionalFitnessPhaseBiasPolicy.apply(weeklyPlan, phaseType: .strength)
        XCTAssertTrue(strengthBiased.allSatisfy { $0.archetype == .strengthPower })
        XCTAssertTrue(strengthBiased.allSatisfy(\.includeStrengthBlock))
        XCTAssertNotEqual(muscleGainBiased.map(\.archetype), strengthBiased.map(\.archetype), "Strength and Muscle Gain must produce a genuinely distinct archetype, never the same merged bias")
    }

    func testFinding4_RecoveryArchetypeUnchangedFromRound1() throws {
        let weeklyPlan = try XCTUnwrap(FunctionalFitnessAuthoredProgramLibrary.weeklyPlan(forSessionsPerWeek: 1))
        let biased = FunctionalFitnessPhaseBiasPolicy.apply(weeklyPlan, phaseType: .recovery)
        XCTAssertTrue(biased.allSatisfy { $0.archetype == .recoveryConditioning })
        XCTAssertTrue(biased.allSatisfy { !$0.includeStrengthBlock })
        XCTAssertTrue(biased.allSatisfy { $0.stimulus.loading == .bodyweightOnly && $0.stimulus.intensity == .low && $0.stimulus.systemicDemand == .low })
    }

    func testFinding4_FunctionalFitnessPerformancePhaseRemainsUnbiased() throws {
        let weeklyPlan = try XCTUnwrap(FunctionalFitnessAuthoredProgramLibrary.weeklyPlan(forSessionsPerWeek: 1))
        let unbiased = FunctionalFitnessPhaseBiasPolicy.apply(weeklyPlan, phaseType: .functionalFitness)
        XCTAssertEqual(unbiased, weeklyPlan, "a dedicated FF-performance phase must remain exactly the authored plan, byte-for-byte")
        XCTAssertTrue(unbiased.allSatisfy { $0.archetype == .unbiased })
    }

    /// Confirms the phase-bias switch keys off the real `PhaseType`, never
    /// a `Goal`-name/primaryType string check.
    func testFinding4_BiasIsKeyedOnPhaseTypeNeverGoalString() throws {
        let weeklyPlan = try XCTUnwrap(FunctionalFitnessAuthoredProgramLibrary.weeklyPlan(forSessionsPerWeek: 1))
        // Same phase type, unrelated to any specific Goal — proves the
        // function's own signature/behavior depends only on `PhaseType`.
        let biased = FunctionalFitnessPhaseBiasPolicy.apply(weeklyPlan, phaseType: .muscleGain)
        XCTAssertTrue(biased.allSatisfy { $0.archetype == .functionalBodybuilding })
    }

    func testFinding4_ComposerPrefersLoadedFunctionsForFunctionalBodybuildingArchetype() {
        var composer = FunctionalFitnessMovementComposer()
        let eligible: Set<MovementFunction> = [.squatLoaded, .hingeLoaded, .gymnasticsPull, .gymnasticsPush]
        let roles = composer.composeSession(eligibleFunctions: eligible, monostructuralEligible: true, archetype: .functionalBodybuilding)
        XCTAssertEqual(roles.count, 3)
        XCTAssertTrue(roles.contains(.squatLoaded))
        XCTAssertTrue(roles.contains(.hingeLoaded), "loaded compound patterns must dominate primary coverage for the Functional Bodybuilding archetype")
    }

    /// Regression: an earlier version of this fix suppressed the
    /// composer's monostructural fill entirely for `.functionalBodybuilding`,
    /// which — with only one real candidate per loaded/gymnastics
    /// function — forced a role to repeat an already-exhausted exercise
    /// and left it genuinely unresolvable. Conditioning fill must remain
    /// the safe, always-available fallback.
    func testFinding4_ConditioningFillRemainsAvailableAsSafeFallbackForFunctionalBodybuildingArchetype() {
        var composer = FunctionalFitnessMovementComposer()
        let eligible: Set<MovementFunction> = [.squatLoaded, .gymnasticsPull]
        let roles = composer.composeSession(eligibleFunctions: eligible, monostructuralEligible: true, archetype: .functionalBodybuilding)
        XCTAssertEqual(roles.count, 3, "conditioning fill must still be available as a safe third role even when biased toward loaded emphasis")
        XCTAssertTrue(roles.contains(.monostructural))
    }

    func testFinding4_UnbiasedArchetypeReproducesExactPriorComposerBehavior() {
        var composer = FunctionalFitnessMovementComposer()
        let eligible: Set<MovementFunction> = [.squatLoaded, .hingeLoaded, .gymnasticsPull, .gymnasticsPush]
        let roles = composer.composeSession(eligibleFunctions: eligible, monostructuralEligible: true)
        // Default `.unbiased` alternates loaded/gymnastics starting with
        // `.loaded` — exactly Round 1's own already-tested behavior.
        XCTAssertEqual(roles, [.squatLoaded, .gymnasticsPull, .hingeLoaded])
    }

    func testFinding4_PresentationLabelsReflectRealArchetype() throws {
        let stimulus = Stimulus(
            targetDurationDomain: .short, intensity: .moderate, loading: .moderate,
            movementFunctions: [], movementModalityMix: [], skillDemand: .low, systemicDemand: .low, scoreType: .load
        )
        let session = Session(name: "Test FF Session", modality: .functionalFitness, status: .scheduled, role: nil)
        context.insert(session)
        let strengthBlock = WorkoutBlock(type: .strength)
        context.insert(strengthBlock)
        session.addBlock(strengthBlock)
        let ffBlock = WorkoutBlock(type: .functionalFitness)
        context.insert(ffBlock)
        session.addBlock(ffBlock)
        let prescription = FunctionalFitnessPrescription(stimulus: stimulus, format: .maxLoad, archetype: .functionalBodybuilding)
        context.insert(prescription)
        ffBlock.attachFunctionalFitnessPrescription(prescription)

        XCTAssertEqual(BlockPresentation.functionalFitnessAwareBlockLabel(for: strengthBlock), "Functional Bodybuilding")
        XCTAssertEqual(BlockPresentation.functionalFitnessAwareBlockLabel(for: ffBlock), "Conditioning")
    }

    func testFinding4_UnbiasedArchetypeFallsBackToGenericLabels() throws {
        let stimulus = Stimulus(
            targetDurationDomain: .short, intensity: .moderate, loading: .moderate,
            movementFunctions: [], movementModalityMix: [], skillDemand: .low, systemicDemand: .low, scoreType: .load
        )
        let session = Session(name: "Test FF Session", modality: .functionalFitness, status: .scheduled, role: nil)
        context.insert(session)
        let ffBlock = WorkoutBlock(type: .functionalFitness)
        context.insert(ffBlock)
        session.addBlock(ffBlock)
        let prescription = FunctionalFitnessPrescription(stimulus: stimulus, format: .maxLoad, archetype: .unbiased)
        context.insert(prescription)
        ffBlock.attachFunctionalFitnessPrescription(prescription)

        XCTAssertEqual(BlockPresentation.functionalFitnessAwareBlockLabel(for: ffBlock), BlockPresentation.blockTypeLabel(.functionalFitness))
    }

    // MARK: - Finding E (revision): training-role main body, subordinate conditioning

    /// The real acceptance scenario end-to-end: Build Muscle, Muscle Gain
    /// phase, 4 Hypertrophy + 1 Functional Fitness, Full Gym, 5 days,
    /// doubles off — same real production path as
    /// `testFinding3_FFStrengthSlotResolvesARealExerciseThroughStartPhaseUseCase`.
    /// The main body must contain MULTIPLE distinct real movements, never
    /// one fixed lift — proving the fix reaches the real generator/
    /// materializer, not just the composer in isolation.
    func testFindingE_MuscleGainMainBodyHasMultipleDistinctRealMovements() throws {
        let monday = date(2026, 1, 5)
        let (_, goal) = try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: 5, allowsDoubles: false)
        let viewModel = loadedViewModel(referenceDate: monday)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.hypertrophy, 4), (.functionalFitness, 1)]))
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))
        try completeAnyCalibration(goal: goal, trainingDays: 5, asOf: monday)

        guard let phase = goal.plans.first?.orderedPhases.first,
              let ffComponent = (phase.selectedTrainingMix ?? phase.recommendedTrainingMix)?.orderedComponents.first(where: { $0.programmingSystem == .functionalFitness }),
              let ffSession = ffComponent.programInstance?.sessions.first
        else { return XCTFail("expected a real FF session") }

        let strengthBlock = try XCTUnwrap(ffSession.orderedBlocks.first { ($0.type == .strength || $0.type == .hypertrophy) })
        let prescriptions = strengthBlock.orderedPrescriptions
        XCTAssertGreaterThan(prescriptions.count, 1, "Muscle Gain's Functional Bodybuilding main body must contain more than one movement — never a single fixed lift")
        let exercises = prescriptions.compactMap(\.exercise)
        XCTAssertEqual(exercises.count, prescriptions.count, "every authored main-body role that materialized must have resolved a real exercise")
        XCTAssertEqual(Set(exercises.map(\.id)).count, exercises.count, "every main-body role must resolve a DISTINCT exercise, never the same one repeated")
        // MUSCLE + 5FF FINAL CLOSURE, Section 5 (project-owner decision):
        // carry/trunk are no longer unconditional main-body decorations —
        // the real main body for this family is now the 2-role primary+
        // complementary loaded-pattern pair only (see
        // `causal-analysis/conditioning-test-authority-migration.md`).
        // The "must reach a carry/trunk role" requirement below encoded
        // the now-rejected old behavior and is removed, not loosened.

        // Conditioning remains present but must never OUTGROW the main
        // body — it is the subordinate finisher, not the session's
        // identity. `<=` (not `<`) because the main body itself shrank to
        // 2 roles under the new closure decision, matching this family's
        // own real 2-role conditioning exactly — equal size is still
        // subordinate, never dominant.
        let ffBlock = try XCTUnwrap(ffSession.orderedBlocks.first { $0.functionalFitnessPrescription != nil })
        let conditioningMovementCount = ffBlock.functionalFitnessPrescription?.orderedMovements.count ?? 0
        XCTAssertLessThanOrEqual(conditioningMovementCount, prescriptions.count, "conditioning must never outgrow the main body")
    }

    /// Direct composer proof: Muscle Gain's conditioning finisher is a
    /// single, genuinely-subordinate monostructural role — never another
    /// loaded role, and never the full 3-role standalone metcon `.unbiased`
    /// still produces (regression-guarded by
    /// `testFinding4_UnbiasedArchetypeReproducesExactPriorComposerBehavior`,
    /// unchanged).
    func testFindingE_ConditioningRoleCountReducedForFunctionalBodybuildingArchetype() {
        var composer = FunctionalFitnessMovementComposer()
        let eligible: Set<MovementFunction> = [.squatLoaded, .hingeLoaded, .gymnasticsPull, .gymnasticsPush]
        let roles = composer.composeSession(eligibleFunctions: eligible, monostructuralEligible: true, targetRoleCount: 1, archetype: .functionalBodybuilding)
        XCTAssertEqual(roles, [.monostructural], "a reduced-role-count Functional Bodybuilding conditioning block must lead with real conditioning, never repeat a loaded role")
    }

    /// Existing capability gating is untouched: a main-body role with no
    /// real, semantically-eligible candidate at all is simply absent —
    /// never a placeholder, and never forces the other real roles away.
    /// Mirrors `testFinding3_NoStrengthCandidatesMeansTheBlockIsAbsentNeverEmpty`'s
    /// existing invariant, extended to the multi-role case.
    func testFindingE_MainBodyRoleWithNoRealCandidateIsAbsentButOtherRolesStillMaterialize() throws {
        let weeklyPlan = try XCTUnwrap(FunctionalFitnessAuthoredProgramLibrary.weeklyPlan(forSessionsPerWeek: 1))
        let biased = FunctionalFitnessPhaseBiasPolicy.apply(weeklyPlan, phaseType: .muscleGain)
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 4, targetStimulus: biased[0].stimulus, format: biased[0].format,
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false, weeklyPlan: biased
        )
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition

        let environment = TrainingEnvironmentTestSupport.full(context: context)
        // Covers all 4 loaded patterns (squat/hinge/press/pull) so both the
        // primary and complementary roles resolve regardless of which pair
        // this relative week's rotation lands on — deliberately no
        // candidate at all for the carry/trunk accessory roles.
        let candidates = [
            Exercise(canonicalName: "Test Front Squat", modality: .functionalFitness, equipment: "barbell", movementPattern: "squat", primaryTargets: [.quadriceps, .glutes], movementFunctions: [.squatLoaded], functionalModality: .weightlifting),
            Exercise(canonicalName: "Deadlift", modality: .functionalFitness, equipment: "barbell", movementPattern: "hinge", primaryTargets: [.hamstrings, .glutes, .back], movementFunctions: [.hingeLoaded], functionalModality: .weightlifting),
            Exercise(canonicalName: "Test Bench Press", modality: .functionalFitness, equipment: "barbell", movementPattern: "press", primaryTargets: [.shoulders, .chest, .triceps], movementFunctions: [.pressLoaded], functionalModality: .weightlifting),
            Exercise(canonicalName: "Test Barbell Row", modality: .functionalFitness, equipment: "barbell", movementPattern: "pull", primaryTargets: [.back, .biceps], movementFunctions: [.horizontalPullLoaded], functionalModality: .weightlifting),
        ]
        for exercise in candidates { context.insert(exercise) }
        try ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: candidates, environment: environment)

        let ffCandidates = [
            Exercise(canonicalName: "Test Bike", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "test", movementFunctions: [.monostructural], functionalModality: .metabolicConditioning, measuredDimensions: [.distance]),
        ]
        for exercise in ffCandidates { context.insert(exercise) }

        let sessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, startDate: date(2026, 1, 5), ownerUserID: instance.ownerUserID,
            candidateExercises: candidates + ffCandidates, exposureHistory: [], environment: environment, context: context
        )
        let structuredSession = try XCTUnwrap(sessions.first)
        let strengthBlock = try XCTUnwrap(structuredSession.orderedBlocks.first { ($0.type == .strength || $0.type == .hypertrophy) }, "the two loaded roles must still materialize a real block even though the accessory roles could not resolve")
        XCTAssertEqual(strengthBlock.orderedPrescriptions.count, 2, "only the 2 roles with a real candidate materialize — the carry/trunk roles are simply absent, never a placeholder")
    }

    /// Existing environment filtering is untouched: a role's candidate
    /// exists semantically but is equipment-incompatible with the
    /// athlete's real `TrainingEnvironment` — that role must not resolve,
    /// exactly like every other slot in this app.
    func testFindingE_MainBodyRoleRespectsEnvironmentFiltering() throws {
        // MUSCLE + 5FF FINAL CLOSURE, Section 5 (project-owner decision):
        // Carry/Trunk roles only exist for the `.lowerFatigueComplementary`
        // family now (no longer unconditional on every session) — a
        // `forSessionsPerWeek: 1` plan's lone session never resolves to
        // that family (`resistanceDominant`/`mixedResistanceWorkCapacity`
        // only), so it no longer carries a Carry/Trunk slot at all to
        // test environment-filtering against. `forSessionsPerWeek: 5`'s
        // real, real-world session index 4 is the one that does — same
        // real scenario `testFixtureD_MuscleFiveFFAlone` exercises.
        let weeklyPlan = try XCTUnwrap(FunctionalFitnessAuthoredProgramLibrary.weeklyPlan(forSessionsPerWeek: 5))
        let biased = FunctionalFitnessPhaseBiasPolicy.apply(weeklyPlan, phaseType: .muscleGain)
        let lowerFatigueSession = try XCTUnwrap(biased.first { $0.sessionFamily == .lowerFatigueComplementary })
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 4, targetStimulus: lowerFatigueSession.stimulus, format: lowerFatigueSession.format,
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false, weeklyPlan: [lowerFatigueSession]
        )
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition

        // A restricted environment with no dumbbells/pull-up bar — the
        // Carry/Trunk roles' only real candidates below require exactly
        // that equipment.
        let restricted = TrainingEnvironment(name: "Test Restricted Gym", availableEquipment: [.barbell, .rack, .bench, .bodyweight])
        context.insert(restricted)

        let candidates = [
            Exercise(canonicalName: "Test Front Squat", modality: .functionalFitness, equipment: "barbell", movementPattern: "squat", primaryTargets: [.quadriceps, .glutes], movementFunctions: [.squatLoaded], functionalModality: .weightlifting),
            Exercise(canonicalName: "Test Deadlift", modality: .functionalFitness, equipment: "barbell", movementPattern: "hinge", primaryTargets: [.hamstrings, .glutes, .back], functionalModality: .weightlifting),
            Exercise(canonicalName: "Test Farmer's Carry", modality: .functionalFitness, equipment: "dumbbell", movementPattern: "carry", primaryTargets: [.forearms, .core], movementFunctions: [.carry], functionalModality: .weightlifting, requiredEquipment: [.dumbbells]),
            Exercise(canonicalName: "Test Toes-to-Bar", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "coreFlexion", primaryTargets: [.core], movementFunctions: [.gymnasticsPull, .trunk], functionalModality: .gymnastics, requiredEquipment: [.pullUpBar]),
        ]
        for exercise in candidates { context.insert(exercise) }

        // Existing, pre-existing `ResolveProgramInstanceExerciseSlotsUseCase`
        // invariant (shared by every slot in this app, unchanged by Finding
        // E): a candidate that matches a role SEMANTICALLY but is excluded
        // only by equipment is a real, attributable environment conflict —
        // it throws rather than silently vanishing. This proves the new
        // Carry/Trunk roles are gated by the SAME real environment-
        // filtering mechanism as every other slot, not a bypassed or
        // second one.
        XCTAssertThrowsError(
            try ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: candidates, environment: restricted)
        ) { error in
            guard case ExerciseSlotResolutionError.environmentIncompatible(let slot, let missing) = error else {
                return XCTFail("expected .environmentIncompatible, got \(error)")
            }
            XCTAssertTrue(slot.contains("Carry") || slot.contains("Trunk"), "the reported slot must be one of the new accessory roles, not an unrelated one")
            XCTAssertTrue(missing.contains(.dumbbells) || missing.contains(.pullUpBar))
        }
    }

    // MARK: - Finding K (Continuation 2): FBB conditioning format/duration honesty

    /// The conditioning component's authored `format`/`targetDurationDomain`
    /// for `.functionalBodybuilding` must honestly describe a short,
    /// coherent finisher — not the unbiased library's own full-metcon
    /// shape — and must survive real Stage-E materialization across all 4
    /// authored weeks without throwing `stimulusValidationFailed`, proving
    /// the disabled `avoidRepeatingDurationDomainWithinSessions` check
    /// prevents week 3+ from drifting the domain away from the authored
    /// format (the exact decoupling risk this finding closes).
    func testFindingK_MuscleGainConditioningFormatMatchesActualShortContentAcrossAllFourWeeks() throws {
        let weeklyPlan = try XCTUnwrap(FunctionalFitnessAuthoredProgramLibrary.weeklyPlan(forSessionsPerWeek: 1))
        let biased = FunctionalFitnessPhaseBiasPolicy.apply(weeklyPlan, phaseType: .muscleGain)
        // PROGRAMMING MODEL CORRECTION: supersedes the entire prior format
        // sequence (`.amrap`/`.roundsAndReps` → `.forTime`/`.time` →
        // `.intervals(1,...)`/`.completedIntervals` → a second, still-wrong
        // `.amrap` guess based on the composer's generic 3-role default).
        // The real defect was never the format — it was the conditioning
        // block's role COUNT. With a deliberate `targetRoleCount: 2` (see
        // `FunctionalFitnessMaterializer`'s own correction comment for the
        // full role-by-role reasoning), the conditioning block is now a
        // real, small, 2-movement circuit, for which `.amrap`/
        // `.roundsAndReps` is the correct, truthful, already-validated
        // pairing — see `testFindingP_...` below for the full rationale.
        // CONDITIONING DOSE AUTHORITY V1: the historical unconditional
        // `240` every week is gone by deliberate product decision — this
        // finisher now cycles through the real, locked SHORT_HIGH_OUTPUT
        // sequence (4→6→8→4 min) keyed on `relativeWeek`, and the
        // duration DOMAIN is honestly derived from whichever concrete
        // duration was resolved (6/8-minute exposures genuinely land in
        // this codebase's real `.medium` bucket, not an error). The real
        // invariant this finding actually protects — format and domain
        // never DECOUPLE from each other, at any week — is unaffected and
        // still verified below via the real materialized results.
        XCTAssertEqual(biased.map(\.format), [240, 360, 480, 240].map { WorkoutFormat.amrap(capSeconds: $0) }, "the real, locked SHORT_HIGH_OUTPUT weekly cycle")
        XCTAssertEqual(biased.map(\.stimulus.targetDurationDomain), [DurationDomain.short, .medium, .medium, .short], "domain must be honestly derived from each week's own resolved duration")
        XCTAssertTrue(biased.allSatisfy { $0.varianceConstraints.avoidRepeatingDurationDomainWithinSessions == nil }, "duration-domain VARIETY is not the right invariant for a deliberately-uniform subordinate finisher")

        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 4, targetStimulus: biased[0].stimulus, format: biased[0].format,
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false, weeklyPlan: biased
        )
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition

        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let candidates = [
            Exercise(canonicalName: "Test Front Squat", modality: .functionalFitness, equipment: "barbell", movementPattern: "squat", primaryTargets: [.quadriceps, .glutes], movementFunctions: [.squatLoaded], functionalModality: .weightlifting),
            Exercise(canonicalName: "Deadlift", modality: .functionalFitness, equipment: "barbell", movementPattern: "hinge", primaryTargets: [.hamstrings, .glutes, .back], movementFunctions: [.hingeLoaded], functionalModality: .weightlifting),
            Exercise(canonicalName: "Test Bench Press", modality: .functionalFitness, equipment: "barbell", movementPattern: "press", primaryTargets: [.shoulders, .chest, .triceps], movementFunctions: [.pressLoaded], functionalModality: .weightlifting),
            Exercise(canonicalName: "Test Barbell Row", modality: .functionalFitness, equipment: "barbell", movementPattern: "pull", primaryTargets: [.back, .biceps], movementFunctions: [.horizontalPullLoaded], functionalModality: .weightlifting),
            Exercise(canonicalName: "Test Farmers Carry", modality: .functionalFitness, equipment: "dumbbell", movementPattern: "carry", primaryTargets: [.forearms, .core], movementFunctions: [.carry], functionalModality: .weightlifting),
            Exercise(canonicalName: "Test Toes To Bar", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "coreFlexion", primaryTargets: [.core], movementFunctions: [.gymnasticsPull, .trunk], functionalModality: .gymnastics),
            Exercise(canonicalName: "Test Assault Bike", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "bike", movementFunctions: [.monostructural], functionalModality: .metabolicConditioning, measuredDimensions: [.distance]),
        ]
        for exercise in candidates { context.insert(exercise) }
        try ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: candidates, environment: environment)

        var conditioningFormats: [WorkoutFormat] = []
        var conditioningDomains: [DurationDomain] = []
        var conditioningMovementCounts: [Int] = []
        for weekIndex in 0..<4 {
            let sessions = try FunctionalFitnessMaterializer.materializeWeek(
                definition: definition, instance: instance, weekIndex: weekIndex,
                startDate: date(2026, 1, 5 + weekIndex * 7), ownerUserID: instance.ownerUserID,
                candidateExercises: candidates,
                exposureHistory: FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn: instance),
                environment: environment, context: context
            )
            let ffBlock = try XCTUnwrap(sessions.first?.orderedBlocks.first { $0.functionalFitnessPrescription != nil })
            let prescription = try XCTUnwrap(ffBlock.functionalFitnessPrescription)
            conditioningFormats.append(prescription.format)
            conditioningDomains.append(prescription.stimulus.targetDurationDomain)
            conditioningMovementCounts.append(prescription.orderedMovements.count)
        }

        // CONDITIONING DOSE AUTHORITY V1: see this test's own updated note
        // above the `biased` assertions — the real materialized week
        // must reproduce the SAME locked weekly cycle the generation-time
        // `biased` array already resolved, proving format/domain stay
        // coupled together (never decoupled) at every week, exactly as
        // this finding requires — just no longer frozen at one value.
        XCTAssertEqual(conditioningFormats, [240, 360, 480, 240].map { WorkoutFormat.amrap(capSeconds: $0) }, "the format must reproduce the real, locked SHORT_HIGH_OUTPUT weekly cycle — never an unrelated drift")
        XCTAssertEqual(conditioningDomains, [DurationDomain.short, .medium, .medium, .short], "this is the exact decoupling risk this finding closes: format and duration domain must never diverge from EACH OTHER across weeks, even though the concrete duration itself now legitimately varies")
        XCTAssertTrue(conditioningMovementCounts.allSatisfy { $0 == 2 }, "format and actual composed content must agree: a real, deliberately small 2-movement circuit, an AMRAP-shaped short finisher")
    }

    /// PROGRAMMING MODEL CORRECTION: proves `FunctionalFitnessMovementTargetRule`'s
    /// format-independence fix end-to-end — the Muscle Gain conditioning
    /// block's real LOADED role (Role 2) must carry real reps and relative
    /// load guidance even though this block's format is `.amrap`, never
    /// the pre-correction `.roundsForTime`-only gate. A DB/barbell squat,
    /// hinge, or press role does not stop needing load guidance because it
    /// appears in an AMRAP.
    func testProgrammingModelCorrection_MuscleGainLoadedConditioningRoleReceivesRealLoadGuidanceUnderAMRAP() throws {
        let weeklyPlan = try XCTUnwrap(FunctionalFitnessAuthoredProgramLibrary.weeklyPlan(forSessionsPerWeek: 1))
        let biased = FunctionalFitnessPhaseBiasPolicy.apply(weeklyPlan, phaseType: .muscleGain)
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 1, targetStimulus: biased[0].stimulus, format: biased[0].format,
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false, weeklyPlan: biased
        )
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition

        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let candidates = [
            Exercise(canonicalName: "Test Front Squat", modality: .functionalFitness, equipment: "barbell", movementPattern: "squat", primaryTargets: [.quadriceps, .glutes], movementFunctions: [.squatLoaded], functionalModality: .weightlifting),
            Exercise(canonicalName: "Deadlift", modality: .functionalFitness, equipment: "barbell", movementPattern: "hinge", primaryTargets: [.hamstrings, .glutes, .back], movementFunctions: [.hingeLoaded], functionalModality: .weightlifting),
            Exercise(canonicalName: "Test Assault Bike", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "bike", movementFunctions: [.monostructural], functionalModality: .metabolicConditioning, measuredDimensions: [.distance]),
        ]
        for exercise in candidates { context.insert(exercise) }
        try ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: candidates, environment: environment)

        let sessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, startDate: date(2026, 1, 5), ownerUserID: instance.ownerUserID,
            candidateExercises: candidates, exposureHistory: [], environment: environment, context: context
        )
        let ffBlock = try XCTUnwrap(sessions.first?.orderedBlocks.first { $0.functionalFitnessPrescription != nil })
        let prescription = try XCTUnwrap(ffBlock.functionalFitnessPrescription)
        XCTAssertEqual(prescription.format, .amrap(capSeconds: 240))
        XCTAssertEqual(prescription.orderedMovements.count, 2)

        let loadedMovement = try XCTUnwrap(prescription.orderedMovements.first { $0.exercise?.canonicalName != "Test Assault Bike" })
        XCTAssertNotNil(loadedMovement.reps, "a real loaded role must carry a real rep target under AMRAP — the target rule must never be format-gated")
        XCTAssertNotNil(loadedMovement.relativeLoadTier, "a real loaded role must carry real relative load guidance under AMRAP")
    }

    // MARK: - Finding P (Continuation 3): conditioning format/scoring semantics for a single continuous activity

    /// Dogfood Round 2 Continuation 3 (Finding P), superseded by the
    /// PROGRAMMING MODEL CORRECTION checkpoint: Finding K's original
    /// `.amrap(capSeconds: 240)`/`.roundsAndReps` was semantically
    /// incomplete for the 1-movement, monostructural-only composition the
    /// composer produced AT THAT TIME (a continuous activity like Assault
    /// Bike has no discrete repeatable "round" ON ITS OWN). Three further
    /// corrections (`.forTime`/`.time`, `.intervals(1,...)`/
    /// `.completedIntervals`, then a second wrong `.amrap` guess based on
    /// the composer's generic 3-role default) each tried to fix this at
    /// the FORMAT level — but the real defect was always the conditioning
    /// block's role COUNT, never the format. With a deliberate
    /// `targetRoleCount: 2` (see `FunctionalFitnessMaterializer`'s own
    /// correction comment for the full role-by-role reasoning), the
    /// conditioning block is now a REAL, small, 2-movement circuit
    /// (conditioning-leads + 1 loaded compound pattern) — a genuine
    /// repeatable round `.amrap` can truthfully score. `.amrap(capSeconds:
    /// 240)` paired with `.roundsAndReps` is therefore the correct,
    /// already-validated pairing AGAIN — not a reversion to the original
    /// mistake, but the same format now describing genuinely different,
    /// real, deliberately-sized multi-movement content.
    func testFindingP_MuscleGainConditioningUsesARealRepeatableRoundNeverASingleMovementAMRAP() throws {
        let weeklyPlan = try XCTUnwrap(FunctionalFitnessAuthoredProgramLibrary.weeklyPlan(forSessionsPerWeek: 1))
        let biased = FunctionalFitnessPhaseBiasPolicy.apply(weeklyPlan, phaseType: .muscleGain)
        // CONDITIONING DOSE AUTHORITY V1: see `testFindingK_...`'s
        // identical note — the historical unconditional `240` every week
        // is gone; the real, locked SHORT_HIGH_OUTPUT cycle now varies
        // the concrete duration across weeks while the FORMAT KIND
        // (`.amrap`, still a real 2-movement AMRAP, never a reversion to
        // single-movement) stays exactly what this finding requires.
        XCTAssertEqual(biased.map(\.format), [240, 360, 480, 240].map { WorkoutFormat.amrap(capSeconds: $0) }, "the finisher's format kind must stay the composer's own real, current output — a real 2-movement AMRAP, never a reversion to a single-movement composition; only the concrete duration now legitimately cycles")
        XCTAssertTrue(biased.allSatisfy { $0.stimulus.scoreType == .roundsAndReps }, "the scoreType must be the format's own real, Stage-E-validated natural pairing")
        for intent in biased {
            XCTAssertEqual(
                FunctionalFitnessStimulusValidator.defaultScoreType(for: intent.format), intent.stimulus.scoreType,
                "format and scoreType must be the format's own real, already-validated natural pairing — never an invented or mismatched combination"
            )
        }
    }

    /// Generic regression coverage for `IntervalTimerResolution`/`.intervals`'s
    /// own count=1/rest=0 edge case (a plain continuous countdown, no
    /// phantom recovery phase) — kept even though the Muscle Gain
    /// archetype no longer authors `.intervals` (superseded by the real
    /// 2-movement `.amrap` above); `.intervals` remains a real, valid
    /// `WorkoutFormat` case this codebase may still use elsewhere, and
    /// this edge case is worth proving correct independent of which
    /// archetype currently exercises it.
    func testFindingP_SingleIntervalWithNoRestNeverProducesAPhantomRecoveryPhase() {
        let midWork = IntervalTimerResolution.resolve(elapsedSeconds: 120, workDurationSeconds: 240, recoveryDurationSeconds: 0, intervalCount: 1)
        XCTAssertTrue(midWork.isWork, "count: 1, rest: 0 must never produce a recovery phase")
        XCTAssertEqual(midWork.intervalNumber, 1)
        XCTAssertEqual(midWork.remainingInLegSeconds, 120)
        XCTAssertFalse(midWork.isSessionComplete)

        let complete = IntervalTimerResolution.resolve(elapsedSeconds: 240, workDurationSeconds: 240, recoveryDurationSeconds: 0, intervalCount: 1)
        XCTAssertTrue(complete.isSessionComplete)

        XCTAssertEqual(FunctionalFitnessStimulusValidator.defaultScoreType(for: .intervals(count: 1, workSeconds: 240, restSeconds: 0)), .completedIntervals)
        XCTAssertEqual(FunctionalFitnessStimulusValidator.estimatedDurationSeconds(for: .intervals(count: 1, workSeconds: 240, restSeconds: 0)), 240)
        XCTAssertEqual(FunctionalFitnessStimulusValidator.durationDomain(forEstimatedSeconds: 240), .short)
    }

    // MARK: - Finding L (Continuation 2): FBB main-body prescription semantics

    /// A Muscle Gain FBB loaded-pattern role must correctly enter the
    /// EXISTING calibration lifecycle — never an unexplained blank weight/
    /// RIR — and it must carry real, reused RIR guidance from week 0.
    func testFindingL_LoadedPatternRoleCorrectlyEntersExistingCalibrationLifecycle() throws {
        let weeklyPlan = try XCTUnwrap(FunctionalFitnessAuthoredProgramLibrary.weeklyPlan(forSessionsPerWeek: 1))
        let biased = FunctionalFitnessPhaseBiasPolicy.apply(weeklyPlan, phaseType: .muscleGain)
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: 1, lengthWeeks: 4, targetStimulus: biased[0].stimulus, format: biased[0].format,
            sessionRole: .functionalFitness, varianceConstraints: VarianceConstraints(),
            requiresRecentExposureToProgress: false, includeStrengthBlock: false, weeklyPlan: biased
        )
        let definition = FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        instance.programDefinition = definition
        // `ResolveCalibrationDependentPrescriptionsUseCase.resolve` buckets
        // "week 0" via `ProgramWeekGrouping.realSessions`, which reads
        // `instance.startDate` — NOT the `startDate` passed to
        // `materializeWeek` below — so both must agree for this test's
        // real backfill call to find the just-materialized session.
        instance.startDate = date(2026, 1, 5)

        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let frontSquat = Exercise(canonicalName: "Test Front Squat", modality: .functionalFitness, equipment: "barbell", movementPattern: "squat", primaryTargets: [.quadriceps, .glutes], movementFunctions: [.squatLoaded], functionalModality: .weightlifting)
        let candidates = [
            frontSquat,
            Exercise(canonicalName: "Deadlift", modality: .functionalFitness, equipment: "barbell", movementPattern: "hinge", primaryTargets: [.hamstrings, .glutes, .back], movementFunctions: [.hingeLoaded], functionalModality: .weightlifting),
            Exercise(canonicalName: "Test Bench Press", modality: .functionalFitness, equipment: "barbell", movementPattern: "press", primaryTargets: [.shoulders, .chest, .triceps], movementFunctions: [.pressLoaded], functionalModality: .weightlifting),
            Exercise(canonicalName: "Test Barbell Row", modality: .functionalFitness, equipment: "barbell", movementPattern: "pull", primaryTargets: [.back, .biceps], movementFunctions: [.horizontalPullLoaded], functionalModality: .weightlifting),
            Exercise(canonicalName: "Test Farmers Carry", modality: .functionalFitness, equipment: "dumbbell", movementPattern: "carry", primaryTargets: [.forearms, .core], movementFunctions: [.carry], functionalModality: .weightlifting),
            Exercise(canonicalName: "Test Toes To Bar", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "coreFlexion", primaryTargets: [.core], movementFunctions: [.gymnasticsPull, .trunk], functionalModality: .gymnastics),
            Exercise(canonicalName: "Test Assault Bike", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "bike", movementFunctions: [.monostructural], functionalModality: .metabolicConditioning, measuredDimensions: [.distance]),
        ]
        for exercise in candidates { context.insert(exercise) }
        try ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: candidates, environment: environment)

        let sessions = try FunctionalFitnessMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, startDate: date(2026, 1, 5),
            ownerUserID: instance.ownerUserID, candidateExercises: candidates, exposureHistory: [],
            environment: environment, context: context
        )
        let strengthBlock = try XCTUnwrap(sessions.first?.orderedBlocks.first { ($0.type == .strength || $0.type == .hypertrophy) })
        let loadedRoles = strengthBlock.orderedPrescriptions.filter { $0.appliedLoadReasonCode != nil }
        XCTAssertGreaterThan(loadedRoles.count, 0, "at least the 2 loaded-pattern roles must be RM-based")
        for role in loadedRoles {
            XCTAssertEqual(role.appliedLoadReasonCode, .calibrationRequired, "an unresolved RM-based load must use the real, existing calibration-required state — never an unexplained blank")
            // SOURCE AUTHORITY REUSE IMPLEMENTATION: this role now reuses
            // Hypertrophy's own real, source-cited week-1 RIR target
            // (`HypertrophyProgramGenerator.repGoalSchedule[0] == .rir(3)`)
            // directly — never the old borrowed, unrelated
            // `HypertrophyV2ProgressionEngine.accessoryTargetRir` flat
            // constant. Read from the real static rather than hardcoding
            // "3" so this test tracks the same source of truth production
            // code does.
            let expectedWeek1Rir: Int? = {
                guard case .rir(let n) = HypertrophyProgramGenerator.repGoalSchedule.first?.prescription else { return nil }
                return n
            }()
            XCTAssertEqual(role.orderedSetPrescriptions.first?.targetRir, expectedWeek1Rir, "must reuse Hypertrophy's own real source-backed RIR schedule — never a borrowed or invented number")
            // Basic Hypertrophy's real "N/fail" notation is an RIR/effort
            // target with NO fixed rep count (Stage 10R.1D correction,
            // reused directly here) — a real rep RANGE is only present
            // for a `.fixedReps` role (e.g. Heavy/Power patterns), not
            // this one.
            XCTAssertNil(role.orderedSetPrescriptions.first?.repRangeLow, "a real Hypertrophy-authority RIR-only prescription has no fixed rep count — asserting one would itself be the old, corrected defect")
            XCTAssertNil(role.orderedSetPrescriptions.first?.targetWeight, "honestly unresolved until the athlete calibrates")
        }
        // MUSCLE + 5FF FINAL CLOSURE, Section 5 (project-owner decision):
        // this scenario's main body is now the 2-role primary+
        // complementary loaded-pattern pair only — no carry/trunk
        // accessory roles exist here anymore (see
        // `causal-analysis/conditioning-test-authority-migration.md`).
        XCTAssertEqual(strengthBlock.orderedPrescriptions.filter { $0.appliedLoadReasonCode == nil }.count, 0, "this family's main body no longer carries any non-RM-based accessory role")

        // The real, existing, already-shipped mechanism (unchanged by this
        // finding) must now actually reach this newly-tagged prescription:
        // submitting the athlete's real RM10 for Front Squat must resolve a
        // real weight, not just flip a label.
        let frontSquatRole = try XCTUnwrap(strengthBlock.orderedPrescriptions.first { $0.exercise?.id == frontSquat.id })
        XCTAssertEqual(frontSquatRole.appliedLoadReasonCode, .calibrationRequired)
        try ResolveCalibrationDependentPrescriptionsUseCase.resolve(
            exercise: frontSquat, rmType: .rm10, kilograms: 100, instance: instance, userProfile: nil, modelContext: context
        )
        XCTAssertEqual(frontSquatRole.appliedLoadReasonCode, .rmBasedLoad, "the existing calibration-backfill use case must now recognize and resolve this FF-sourced prescription")
        XCTAssertNotNil(frontSquatRole.orderedSetPrescriptions.first?.targetWeight, "a real weight must now be resolved — reusing the exact same engine Hypertrophy/Powerlifting already use")
    }

    // MARK: - Finding Q (Continuation 4): calibration must end in real execution, never a loop

    /// Dogfood Round 2 Continuation 4 (Finding Q): the complete real
    /// athlete journey — fresh FBB session, multiple loaded movements
    /// requiring calibration, submit every required RM, and PROVE actual
    /// set execution becomes reachable (not just that local ViewModel
    /// fields changed in isolation, which is exactly what the earlier
    /// Finding N/O tests proved and which was NOT sufficient — this
    /// checkpoint's own real simulator run disproved that closure).
    ///
    /// This test would have FAILED against the pre-Finding-Q code: the old
    /// `advanceToNextUnresolvedCalibrationIfNeeded` left `movementIndex` on
    /// whichever movement was LAST calibrated (Barbell Bench Press, index
    /// 1) rather than recomputing the real canonical resume target (Back
    /// Squat, index 0 — the first genuinely not-yet-complete movement,
    /// exactly what a FRESH `StrengthExecutionViewModel(block:)` — i.e.
    /// what the athlete would see after any navigation/relaunch — would
    /// independently compute). That divergence between "wherever
    /// incremental advance stopped" and "what a fresh reconstruction says"
    /// is the real defect this finding closes: the two must always agree,
    /// or the athlete can land somewhere the rest of the app disagrees is
    /// correct. This test asserts they agree, then drives an actual
    /// Log Set and one real exercise transition through to completion.
    func testFindingQ_AllCalibrationsResolveIntoRealReachableSetExecutionNeverALoop() throws {
        try assertCalibrationReachesExecution(moveBeforeProgramStart: false)
    }

    func testStartTodayBeforeProgramStartCalibrationReachesExecutionAndPersists() throws {
        try assertCalibrationReachesExecution(moveBeforeProgramStart: true)
    }

    private func assertCalibrationReachesExecution(moveBeforeProgramStart: Bool) throws {
        let monday = date(2026, 1, 5)
        try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: 5, allowsDoubles: false)
        let viewModel = loadedViewModel(referenceDate: monday)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.hypertrophy, 4), (.functionalFitness, 1)]))
        let mix = try XCTUnwrap(viewModel.reviewedMix)
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))

        let ffInstance = mix.orderedComponents.first { $0.programmingSystem == .functionalFitness }?.programInstance
        let strengthBlock = try XCTUnwrap(ffInstance?.sessions.first?.orderedBlocks.first { ($0.type == .strength || $0.type == .hypertrophy) }, "a real FBB main-body block must materialize immediately, calibration required or not (Finding 3/E)")

        // Multiple loaded movements really do require calibration — this
        // is the exact real scenario Finding Q reports, not a contrived one.
        let loadedRolesNeedingCalibration = strengthBlock.orderedPrescriptions.filter { $0.appliedLoadReasonCode == .calibrationRequired }
        XCTAssertGreaterThanOrEqual(loadedRolesNeedingCalibration.count, 2, "the real Muscle Gain FBB main body authors 2 loaded-pattern roles, both RM-based")

        if moveBeforeProgramStart {
            let instance = try XCTUnwrap(ffInstance)
            let session = try XCTUnwrap(strengthBlock.session)
            let originalStart = instance.startDate
            let earlyDate = Calendar.current.date(byAdding: .day, value: -4, to: originalStart)!
            try StartSessionOnDifferentDayUseCase.startToday(session, asOf: earlyDate, modelContext: context)
            XCTAssertEqual(instance.startDate, originalStart)
            XCTAssertFalse(ProgramWeekGrouping.realSessions(in: instance, forWeek: 0).contains { $0.id == session.id })
        }
        let execVM = StrengthExecutionViewModel(block: strengthBlock)
        XCTAssertFalse(execVM.submitCalibration(kilograms: 0, modelContext: context))
        XCTAssertNotNil(execVM.calibrationErrorMessage)
        XCTAssertTrue(execVM.currentMovementNeedsCalibration)

        // Submit EVERY required RM, driven purely by the ViewModel's own
        // real "what needs calibration right now" state — never a
        // hardcoded exercise/order assumption.
        var submissions = 0
        while execVM.currentMovementNeedsCalibration {
            submissions += 1
            XCTAssertLessThanOrEqual(submissions, loadedRolesNeedingCalibration.count, "must never re-request a calibration that was already resolved — a repeat request here IS Finding Q's reported loop")
            XCTAssertNotNil(execVM.currentMovementCalibrationRequirement, "the athlete must always see a real (exercise, RM type) requirement while a calibration prompt is showing")
            guard execVM.submitCalibration(kilograms: 100, modelContext: context) else {
                XCTFail(execVM.calibrationErrorMessage ?? "Calibration failed")
                return
            }
            XCTAssertNil(execVM.calibrationErrorMessage)
        }
        XCTAssertEqual(submissions, loadedRolesNeedingCalibration.count, "exactly the real number of required calibrations were submitted — never more (a loop), never fewer")

        // No calibration prompt remains anywhere in this block.
        XCTAssertTrue(strengthBlock.orderedPrescriptions.allSatisfy { $0.appliedLoadReasonCode != .calibrationRequired }, "every loaded role must be resolved after submitting every required RM")
        XCTAssertFalse(execVM.currentMovementNeedsCalibration)

        // THE CORE FINDING Q ASSERTION: the live ViewModel's post-calibration
        // resting state must be IDENTICAL to what a completely fresh
        // ViewModel (the real shape of "navigate away and back," or a
        // relaunch) independently computes for the exact same block — the
        // two sources of truth this finding unifies must actually agree,
        // not merely coincidentally match in one hand-picked scenario.
        let freshVM = StrengthExecutionViewModel(block: strengthBlock)
        XCTAssertEqual(execVM.movementIndex, freshVM.movementIndex, "a fresh reconstruction (what the athlete sees after any real navigation) must land on the exact same movement as the live post-calibration state — never a second, disagreeing notion of 'where we are'")
        XCTAssertFalse(freshVM.currentMovementNeedsCalibration, "a fresh reconstruction must never re-surface a calibration prompt for an already-resolved movement — this is the literal reported bug")

        // The first executable set is genuinely reachable: a real resolved
        // target weight, a real rep prescription, not another calibration
        // screen and not a dead end.
        let firstMovement = try XCTUnwrap(execVM.currentMovement)
        XCTAssertFalse(StrengthExecutionViewModel.isComplete(firstMovement))
        let firstSetPrescription = try XCTUnwrap(execVM.currentSetPrescription)
        let resolvedWeight = try XCTUnwrap(firstSetPrescription.targetWeight, "the athlete must see a real, resolved load — never a blank target after calibrating it")
        // SOURCE AUTHORITY REUSE IMPLEMENTATION: this main-body role now
        // reuses Hypertrophy's real RIR-only week-1 schedule
        // (`.rir(3)`, Stage 10R.1D's "N/fail" semantics) — a genuine
        // real prescription has EITHER a fixed rep range (`.fixedReps`
        // roles) OR a target RIR (`.rir` roles, this one), never neither.
        // Asserting `repRangeLow` unconditionally would itself be the old
        // FF-invented-`.fixedReps(10)` assumption this checkpoint corrects.
        XCTAssertTrue(firstSetPrescription.repRangeLow != nil || firstSetPrescription.targetRir != nil, "a real rep prescription (range or RIR target), not a placeholder")

        // Log the first real set through the exact production path.
        let loggedCountBefore = firstMovement.loggedSetResults.count
        let highlight = execVM.logCurrentSet(
            weight: resolvedWeight, reps: firstSetPrescription.repRangeHigh ?? 10, actualRir: firstSetPrescription.targetRir, modelContext: context
        )
        XCTAssertNotNil(highlight, "a real result must be logged and returned for the completion summary")
        XCTAssertEqual(firstMovement.loggedSetResults.count, loggedCountBefore + 1, "the set result must actually persist onto the real ExercisePrescription")
        XCTAssertEqual(execVM.block.status, .active, "logging a real set — never merely resolving calibration — is what starts the block (Finding O)")
        try context.save()
        let blockID = strengthBlock.id
        let freshContext = ModelContext(container)
        let persistedBlock = try XCTUnwrap(freshContext.fetch(FetchDescriptor<WorkoutBlock>()).first { $0.id == blockID })
        XCTAssertFalse(StrengthExecutionViewModel(block: persistedBlock).currentMovementNeedsCalibration)
        XCTAssertEqual(persistedBlock.orderedPrescriptions.flatMap(\.loggedSetResults).count, 1)

        // Advance through one real exercise transition and confirm
        // execution mode, not calibration mode, on the far side.
        if execVM.isMovementComplete, execVM.hasNextMovement {
            execVM.goToNextMovement(modelContext: context)
            XCTAssertFalse(execVM.currentMovementNeedsCalibration, "advancing to the next real exercise must never re-enter calibration for an already-resolved movement")
        }
    }
}
