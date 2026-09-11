import XCTest
import SwiftData
@testable import TrainingOS

/// Concurrent Programming V1 — golden scenarios G1-G4, G7, G9, run through
/// the REAL production path (`StrategicPlanSelectionViewModel.buildCustomMix`
/// -> `acceptAndStart` -> `StartPhaseUseCase.start` -> real materializers ->
/// `ConcurrentScheduler`), mirroring `ExplicitWeeklyCompositionTests`'s own
/// established harness exactly. Every mix here uses only source-valid
/// frequencies (`ProgramCapabilityRegistry`-checked): Running is always
/// exactly 2, Powerlifting is always 4 or 5 — never an invented frequency.
///
/// G5/G6 (hard-Running recovery protection against Hypertrophy/Functional
/// Fitness lower-body stress) and G8 (Week-1 parity) are proven at the
/// `ConcurrentScheduler` unit level in `ConcurrentProgrammingV1Tests.swift`
/// — deliberately, since that level lets both the "protected" and
/// "unavoidable adjacency" branches be constructed precisely. G10 (missed
/// session) is proven in `MissedSessionInvariantTests.swift`. This file
/// covers the composition-level (real end-to-end) scenarios: G1, G2, G3,
/// G4 (A/B), G7, G9.
@MainActor
final class ConcurrentProgrammingGoldenScenarioTests: XCTestCase {
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

    /// `referenceDate` here must match whatever is later passed to
    /// `acceptAndStart(referenceDate:)` — `load` bakes `asOf` into the
    /// proposal's own phase dates via `LongTermPlanner.proposeStrategicPlan`,
    /// and a mismatched later `decidedAt` does not retroactively move
    /// those already-proposed dates.
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

    private func realRunningSessions(mix: TrainingMix) -> [Session] {
        mix.orderedComponents
            .first { $0.programmingSystem == .running }?
            .programInstance?.sessions ?? []
    }

    // MARK: - G1: 3H + 1FF + 2Running, sufficient days

    func testG1_ThreeHypertrophyOneFunctionalFitnessTwoRunning_SufficientDays() throws {
        let monday = date(2026, 1, 5)
        let (_, goal) = try makeOnboardedAthlete(trainingDays: 6)
        let viewModel = loadedViewModel(referenceDate: monday)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.hypertrophy, 3), (.functionalFitness, 1), (.running, 2)]))
        let mix = try XCTUnwrap(viewModel.reviewedMix)
        XCTAssertEqual(mix.orderedComponents.count, 3, "no component may be silently dropped")

        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))
        try completeAnyCalibration(goal: goal, trainingDays: 6, asOf: monday)

        let hypertrophySessions = mix.orderedComponents.first { $0.programmingSystem == .hypertrophy }?.programInstance?.sessions ?? []
        let ffSessions = mix.orderedComponents.first { $0.programmingSystem == .functionalFitness }?.programInstance?.sessions ?? []
        let runningComponent = try XCTUnwrap(mix.orderedComponents.first { $0.label == "Running" })
        let runningSessions = realRunningSessions(mix: mix)

        XCTAssertEqual(hypertrophySessions.count, 3, "exactly 3 Hypertrophy sessions, never approximated")
        XCTAssertEqual(ffSessions.count, 1)
        // Running materializes its whole 13-relative-week block up front —
        // week 0 alone contributes exactly 2 real sessions.
        let runningWeek0 = runningSessions.filter { session in
            guard let d = session.day?.date else { return false }
            return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: monday), to: Calendar.current.startOfDay(for: d)).day.map { $0 >= 0 && $0 < 7 } ?? false
        }
        XCTAssertEqual(runningWeek0.count, 2, "Running V1's real frequency is exactly 2/week — never 1, never 3")

        XCTAssertEqual(runningComponent.programmingSystem, .running, "must be the real, source-backed Running system — never generic .steadyState")
        XCTAssertNotEqual(runningComponent.programmingSystem, .steadyState)
        XCTAssertEqual(runningComponent.programInstance?.programDefinition?.programmingSystem, .running)
        XCTAssertEqual(runningComponent.programInstance?.programDefinition?.lengthWeeks, 13, "the real 13-relative-week 5K/2-Day V1 structure, not a fabricated/mock program")

        // Source order preserved: the running program's own template order
        // survives into real materialized sessions — the calendar-ordered
        // real Sessions must exactly match the definition's own template
        // session order (never re-sorted/re-labeled by scheduling).
        let orderedRunningSessions = runningSessions.sorted { ($0.day?.date ?? .distantPast) < ($1.day?.date ?? .distantPast) }
        let templateNames = runningComponent.programInstance?.programDefinition?.orderedTemplateSessions.map(\.name) ?? []
        XCTAssertEqual(orderedRunningSessions.map(\.name), Array(templateNames.prefix(orderedRunningSessions.count)), "real materialized Running Sessions must preserve the source template's own session order")
    }

    // MARK: - G2: 3H + 2FF + 2Running, sufficient capacity

    /// Note: the directive's own illustrative "G2: 2H+2FF+2Run" example
    /// is itself semantically invalid — `HypertrophyBuiltInLibrary.all`'s
    /// curated day counts are exactly {3, 4, 5, 6}, never 2
    /// (`ProgramCapabilityRegistry.isFrequencySupported` confirms this by
    /// rejecting it: `.unsupportedFrequency(style: .hypertrophy,
    /// frequency: 2)`). Corrected here to 3H — a different SHAPE from G1
    /// (2 Functional Fitness instead of 1) while remaining fully
    /// source-valid, exactly the same discipline this checkpoint already
    /// applied to the readiness audit's own invalid "1 Run" examples.
    func testG2_ThreeHypertrophyTwoFunctionalFitnessTwoRunning_SufficientCapacity() throws {
        let monday = date(2026, 1, 5)
        let (_, goal) = try makeOnboardedAthlete(trainingDays: 7)
        let viewModel = loadedViewModel(referenceDate: monday)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.hypertrophy, 3), (.functionalFitness, 2), (.running, 2)]))
        let mix = try XCTUnwrap(viewModel.reviewedMix)
        XCTAssertEqual(mix.orderedComponents.count, 3)

        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))
        try completeAnyCalibration(goal: goal, trainingDays: 7, asOf: monday)

        let hypertrophySessions = mix.orderedComponents.first { $0.programmingSystem == .hypertrophy }?.programInstance?.sessions ?? []
        let ffSessions = mix.orderedComponents.first { $0.programmingSystem == .functionalFitness }?.programInstance?.sessions ?? []
        XCTAssertEqual(hypertrophySessions.count, 3)
        XCTAssertEqual(ffSessions.count, 2)
        XCTAssertFalse(realRunningSessions(mix: mix).isEmpty)
    }

    // MARK: - G3: 4H + 2Running

    func testG3_FourHypertrophyTwoRunning() throws {
        let monday = date(2026, 1, 5)
        let (_, goal) = try makeOnboardedAthlete(trainingDays: 6)
        let viewModel = loadedViewModel(referenceDate: monday)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.hypertrophy, 4), (.running, 2)]))
        let mix = try XCTUnwrap(viewModel.reviewedMix)
        XCTAssertEqual(mix.orderedComponents.count, 2)

        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))
        try completeAnyCalibration(goal: goal, trainingDays: 6, asOf: monday)

        let hypertrophySessions = mix.orderedComponents.first { $0.programmingSystem == .hypertrophy }?.programInstance?.sessions ?? []
        XCTAssertEqual(hypertrophySessions.count, 4)
        let runningComponent = try XCTUnwrap(mix.orderedComponents.first { $0.programmingSystem == .running })
        XCTAssertEqual(runningComponent.frequency.target, 2)
    }

    // MARK: - G4: 3H + 1FF + 2Running, FEWER available days

    /// `StrategicPlanSelectionViewModel.buildCustomMix` passes its own
    /// `weeklyCapacity` (== `availableTrainingDaysPerWeek`, with NO
    /// doubles adjustment) straight through as `LongTermPlanner
    /// .buildCustomMix`'s `capacity` ceiling — a pre-existing, real
    /// architectural boundary: COMPOSITION validation (session count vs.
    /// stated training days) is entirely separate from SCHEDULING
    /// feasibility (day-count vs. doubling), and the former has no
    /// concept of doubles at all. A 6-session mix on a 4-day athlete is
    /// therefore rejected by `buildCustomMix` itself as `.exceedsCapacity`
    /// even when doubles are allowed — this is not something Concurrent
    /// V1 was asked to change. G4 tests the SCHEDULER's own doubles
    /// behavior specifically, so it calls `LongTermPlanner.buildCustomMix`
    /// directly with a capacity that reflects the intended COMPOSITION
    /// size (6), then drives `StartPhaseUseCase.start` directly with the
    /// real, constrained `UserAvailability` (4 days) — mirroring
    /// `CrossModalityFunctionalFitnessProgrammingTests`'s own lower-level
    /// harness rather than the ViewModel.
    /// `UserAvailability.trainingDaysPerWeek` is PURELY informational —
    /// confirmed by reading `UserAvailability.isUsable(_:)` directly: it
    /// only ever checks `unavailableWeekdays`/`availableWeekdays`, never
    /// `trainingDaysPerWeek`. A genuinely restricted week REQUIRES
    /// `unavailableWeekdays` to be set explicitly — passing only a
    /// smaller `trainingDaysPerWeek` number changes nothing about which
    /// days the real scheduler may use.
    private func fewerDaysAvailability(trainingDays: Int, allowsDoubles: Bool) -> UserAvailability {
        let allWeekdays: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
        let unavailable = Set(allWeekdays.suffix(from: min(trainingDays, allWeekdays.count)))
        return UserAvailability(
            trainingDaysPerWeek: trainingDays, unavailableWeekdays: unavailable,
            allowsDoubleSessions: allowsDoubles, maxSessionsPerDay: allowsDoubles ? 2 : 1
        )
    }

    private func startDirectly(
        mix: TrainingMix, ownerUserID: UUID, trainingDays: Int, allowsDoubles: Bool, asOf: Date, phaseEndDate: Date? = nil
    ) throws -> StartPhaseUseCase.Result {
        let phase = TrainingPhase(type: .muscleGain, startDate: asOf, endDate: phaseEndDate, priorityRule: .strength, status: .planned)
        context.insert(phase)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        let materializationContext = TacticalMaterializationContext(
            equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
            strengthCandidateExercises: exercises, functionalFitnessCandidateExercises: exercises,
            trainingEnvironment: environment
        )
        return try StartPhaseUseCase.start(
            phase: phase, mix: mix, asOf: asOf, ownerUserID: ownerUserID, performanceProfile: nil,
            availability: fewerDaysAvailability(trainingDays: trainingDays, allowsDoubles: allowsDoubles),
            materializationContext: materializationContext, context: context
        )
    }

    /// Variant A: doubles disabled, 4 available days for 6 required
    /// sessions — must produce an explicit typed infeasibility
    /// (`ScheduleAcceptanceError.infeasible`), never drop a session and
    /// never silently change the mix.
    ///
    /// Hypertrophy is `.rmBased` and is deliberately DEFERRED by
    /// `StartPhaseUseCase.start` itself until source RM calibration
    /// exists (Stage 10R.1C, unmodified here) — so the FIRST `start()`
    /// call only ever attempts to place FF(1) + Running(2) = 3 sessions,
    /// which trivially fits 4 days and must NOT throw. The real
    /// infeasibility only appears once calibration completes and
    /// Hypertrophy's own 3 sessions are scheduled AROUND the 1-3 already-
    /// occupied sibling days (`preOccupiedDates`) — with no doubles
    /// allowed and only 1-3 free days left for 3 required sessions, that
    /// second call is where `AcceptScheduleProposalUseCase.accept` must
    /// throw.
    func testG4A_FewerDaysDoublesDisabled_ExplicitInfeasibility() throws {
        let monday = date(2026, 1, 5)
        let (user, _) = try makeOnboardedAthlete(trainingDays: 4, allowsDoubles: false)
        guard case .success(let mix) = LongTermPlanner.buildCustomMix(
            selections: [(style: .hypertrophy, frequency: 3), (style: .functionalFitness, frequency: 1), (style: .running, frequency: 2)],
            capacity: 6
        ) else { return XCTFail("3H+1FF+2Run must be a real, constructible composition") }
        context.insert(mix)
        XCTAssertEqual(mix.orderedComponents.count, 3, "the mix itself is still exact and valid — infeasibility is a SCHEDULING outcome, never a mix mutation")

        // A tight `phaseEndDate` (just over one week out) clamps
        // `TacticalWindowPolicy.windowLengthInDays` down to a single real
        // 7-day tactical window — without this, Hypertrophy's own 4-week
        // natural block would let its sessions slide into a LATER week
        // entirely free of its siblings, masking the real fewer-days
        // conflict this scenario is meant to prove.
        let tightPhaseEnd = Calendar.current.date(byAdding: .day, value: 8, to: monday)
        let result = try startDirectly(mix: mix, ownerUserID: user.id, trainingDays: 4, allowsDoubles: false, asOf: monday, phaseEndDate: tightPhaseEnd)
        XCTAssertFalse(result.componentsAwaitingCalibration.isEmpty, "Hypertrophy must still be the deferred, awaiting-calibration component")

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        XCTAssertThrowsError(try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: result.phase, ownerUserID: user.id, performanceProfile: nil,
            availability: fewerDaysAvailability(trainingDays: 4, allowsDoubles: false),
            materializationContext: TacticalMaterializationContext(
                equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
                strengthCandidateExercises: exercises, functionalFitnessCandidateExercises: exercises, trainingEnvironment: environment
            ),
            asOf: monday, context: context
        )) { error in
            XCTAssertEqual(error as? ScheduleAcceptanceError, .infeasible, "Hypertrophy's 3 remaining sessions cannot fit the days left free by its already-scheduled siblings, with no doubles allowed — an explicit typed infeasibility, never a silent drop")
        }

        // No component may have silently lost a session or changed
        // frequency — the mix itself is untouched by the failed attempt.
        XCTAssertEqual(mix.orderedComponents.first { $0.programmingSystem == .hypertrophy }?.frequency.target, 3)
        XCTAssertEqual(mix.orderedComponents.first { $0.programmingSystem == .functionalFitness }?.frequency.target, 1)
        XCTAssertEqual(mix.orderedComponents.first { $0.programmingSystem == .running }?.frequency.target, 2)
        // Materialization (real, source-backed Session content) and
        // SCHEDULING (calendar placement) are separate steps: every
        // materializer assigns each Session an initial NAIVE calendar day
        // immediately (still present here, unchanged) — only
        // `AcceptScheduleProposalUseCase.accept` REPLACES it with the
        // scheduler's own real placement, and it throws before doing so
        // here. `schedulerVersion` is stamped ONLY by a successful
        // `accept()` (`Session.schedulerVersion`'s own doc comment) — its
        // absence is the real proof this attempt was never accepted.
        let hypertrophySessions = mix.orderedComponents.first { $0.programmingSystem == .hypertrophy }?.programInstance?.sessions ?? []
        XCTAssertEqual(hypertrophySessions.count, 3, "the real 3 Hypertrophy sessions were still honestly generated")
        XCTAssertTrue(hypertrophySessions.allSatisfy { $0.schedulerVersion == nil }, "no Hypertrophy session may end up accepted/placed by the scheduler when the overall proposal was rejected as infeasible")
    }

    /// Variant B: doubles ENABLED, same fewer-days scenario — the exact
    /// mix must be fully preserved via deterministic double placement,
    /// never an infeasibility and never a dropped session.
    func testG4B_FewerDaysDoublesEnabled_ExactMixPreservedViaDoubles() throws {
        let monday = date(2026, 1, 5)
        let (user, _) = try makeOnboardedAthlete(trainingDays: 4, allowsDoubles: true)
        guard case .success(let mix) = LongTermPlanner.buildCustomMix(
            selections: [(style: .hypertrophy, frequency: 3), (style: .functionalFitness, frequency: 1), (style: .running, frequency: 2)],
            capacity: 6
        ) else { return XCTFail("3H+1FF+2Run must be a real, constructible composition") }
        context.insert(mix)

        let tightPhaseEnd = Calendar.current.date(byAdding: .day, value: 8, to: monday)
        let result = try startDirectly(mix: mix, ownerUserID: user.id, trainingDays: 4, allowsDoubles: true, asOf: monday, phaseEndDate: tightPhaseEnd)
        XCTAssertNotEqual(result.scheduleProposal.feasibility, .infeasible)

        // Hypertrophy is `.rmBased` and deferred pending calibration —
        // complete that real step exactly as every other test here does.
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: result.phase, ownerUserID: user.id, performanceProfile: nil,
            availability: fewerDaysAvailability(trainingDays: 4, allowsDoubles: true),
            materializationContext: TacticalMaterializationContext(
                equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
                strengthCandidateExercises: exercises, functionalFitnessCandidateExercises: exercises, trainingEnvironment: environment
            ),
            asOf: monday, context: context
        )

        let hypertrophySessions = mix.orderedComponents.first { $0.programmingSystem == .hypertrophy }?.programInstance?.sessions ?? []
        let ffSessions = mix.orderedComponents.first { $0.programmingSystem == .functionalFitness }?.programInstance?.sessions ?? []
        XCTAssertEqual(hypertrophySessions.count, 3, "every Hypertrophy session still placed via doubling — never dropped")
        XCTAssertEqual(ffSessions.count, 1)
        let runningWeek0 = realRunningSessions(mix: mix).filter { session in
            guard let d = session.day?.date else { return false }
            return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: monday), to: Calendar.current.startOfDay(for: d)).day.map { $0 >= 0 && $0 < 7 } ?? false
        }
        XCTAssertEqual(runningWeek0.count, 2, "Running's own exact frequency is preserved even under a fewer-days doubling scenario")

        // At least one real double-session pairing must have occurred —
        // 6 sessions across only 4 days is impossible without one.
        let allWeek0Placements = mix.orderedComponents.compactMap(\.programInstance).flatMap(\.sessions).filter { session in
            guard let d = session.day?.date else { return false }
            return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: monday), to: Calendar.current.startOfDay(for: d)).day.map { $0 >= 0 && $0 < 7 } ?? false
        }
        let byDay = Dictionary(grouping: allWeek0Placements) { Calendar.current.startOfDay(for: $0.day!.date) }
        XCTAssertTrue(byDay.values.contains { $0.count > 1 }, "at least one real calendar day must carry a double session pairing")
    }

    // MARK: - G7: Powerlifting (real, valid 4-day family) + Running

    /// Uses `.strengthTraining` at frequency 4 — a real, source-valid
    /// Powerlifting family (`PowerliftingBuiltInLibrary.all` has exactly
    /// `(family: .b, dayCount: 4)`/`(family: .c, dayCount: 5)` — never an
    /// invented 2-day Powerlifting).
    func testG7_PowerliftingFourDayPlusRunning_HardRunningStructurallyProtected() throws {
        let monday = date(2026, 1, 5)
        let (_, goal) = try makeOnboardedAthlete(trainingDays: 6)
        let viewModel = loadedViewModel(referenceDate: monday)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.strengthTraining, 4), (.running, 2)]))
        let mix = try XCTUnwrap(viewModel.reviewedMix)
        XCTAssertEqual(mix.orderedComponents.first { $0.label == "Strength Training" }?.programmingSystem, .powerlifting)

        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))
        try completeAnyCalibration(goal: goal, trainingDays: 6, asOf: monday)

        let powerliftingSessions = mix.orderedComponents.first { $0.programmingSystem == .powerlifting }?.programInstance?.sessions ?? []
        XCTAssertEqual(powerliftingSessions.count, 4, "the real 4-day Powerlifting family — never approximated")

        let runningSessions = realRunningSessions(mix: mix)
        let runningWeek0 = runningSessions.filter { session in
            guard let d = session.day?.date else { return false }
            return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: monday), to: Calendar.current.startOfDay(for: d)).day.map { $0 >= 0 && $0 < 7 } ?? false
        }
        XCTAssertEqual(runningWeek0.count, 2)

        // Structural protection check: no hard/quality Running session may
        // land the calendar day immediately after a Powerlifting session
        // whose real, composed `TrainingStressProfile` reads high on
        // lowerBodyLoad, UNLESS every hard-valid day was equally adjacent
        // (never asserted here as a hard requirement — this is a real,
        // empirical check against whichever real week-0 stress the actual
        // source prescriptions produce).
        let hardRunningSessions = runningWeek0.filter { session in
            guard let role = session.role else { return false }
            return RunningOrchestrationContract.qualityClassification(for: role) == .quality
        }
        let heavyLowerBodyPowerliftingDays = Set(powerliftingSessions.compactMap { session -> Date? in
            guard let profile = SessionStressComposer.compose(session), profile.lowerBodyLoad == .high, let d = session.day?.date else { return nil }
            return Calendar.current.startOfDay(for: d)
        })
        for hardSession in hardRunningSessions {
            guard let hardDate = hardSession.day?.date else { continue }
            let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: hardDate))!
            if heavyLowerBodyPowerliftingDays.contains(dayBefore) {
                // Only a real finding if a same-week alternative day existed
                // that would NOT have had this adjacency — report rather
                // than silently pass either way.
                XCTFail("hard Running (\(hardSession.name)) was placed immediately after a high-lowerBodyLoad Powerlifting day (\(dayBefore)) despite 6 available training days — the recovery-protection rule should have preferred another day")
            }
        }
    }

    // MARK: - G9: mid-week start preserved for a Running-inclusive mix

    /// Preserves the CLOSED R0 behavior (a brand-new plan's first source-
    /// backed tactical week may only ever be a genuine full calendar week)
    /// for a mix that now includes real Running — proves the fix
    /// generalizes, never special-cased to H+FF only.
    func testG9_MidWeekAcceptance_NoPartialSourceWeek_ForARunningInclusiveMix() throws {
        let friday = date(2026, 1, 2) // confirmed Friday
        let (_, goal) = try makeOnboardedAthlete(trainingDays: 5)
        let viewModel = loadedViewModel(referenceDate: friday)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.hypertrophy, 3), (.running, 2)]))
        let mix = try XCTUnwrap(viewModel.reviewedMix)

        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: friday))
        try completeAnyCalibration(goal: goal, trainingDays: 5, asOf: friday)

        let followingMonday = date(2026, 1, 5)
        let allSessions = mix.orderedComponents.compactMap(\.programInstance).flatMap(\.sessions)
        let sessionsBeforeMonday = allSessions.filter { session in
            guard let d = session.day?.date else { return false }
            return Calendar.current.startOfDay(for: d) < Calendar.current.startOfDay(for: followingMonday)
        }
        XCTAssertTrue(sessionsBeforeMonday.isEmpty, "zero source-backed Sessions (Hypertrophy OR Running) before the following Monday on a Friday acceptance")

        let runningSessionsFromMonday = realRunningSessions(mix: mix).filter { session in
            guard let d = session.day?.date else { return false }
            return Calendar.current.startOfDay(for: d) >= Calendar.current.startOfDay(for: followingMonday)
        }
        XCTAssertFalse(runningSessionsFromMonday.isEmpty, "Running's real full cadence begins Monday onward, exactly like every other component")
    }
}
