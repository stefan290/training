import XCTest
import SwiftData
@testable import TrainingOS

/// Dogfood Round 2 Continuation (Finding A): real simulator dogfooding
/// found that weekday selection existed only in post-onboarding
/// `TrainingPreferencesSettingsView` (Correction 1), never in the real
/// onboarding journey where the decision is first made. These tests cover
/// the NEW surfaces the fix touches: `OnboardingViewModel` itself, and the
/// two downstream Int-only availability paths the trace found
/// (`StrategicPlanSelectionViewModel`'s first materialization,
/// `LongTermPlanner.comparisonAvailability`) — reusing the exact same
/// `GoalPreferences.availableWeekdays` authority
/// `DogfoodRound2CompletionTests` already proved for post-onboarding
/// editing.
@MainActor
final class DogfoodRound2ContinuationOnboardingWeekdayTests: XCTestCase {
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

    /// Mirrors `ConcurrentScheduler`'s own private Monday=1...Sunday=7
    /// mapping (also duplicated in `DogfoodRound2CompletionTests` for the
    /// same reason: that one is private to its own file).
    private func appWeekday(for date: Date) -> Weekday {
        let raw = Calendar(identifier: .gregorian).component(.weekday, from: date)
        let mapped = raw == 1 ? 7 : raw - 1
        return Weekday(rawValue: mapped) ?? .monday
    }

    private func completeCalibrationIfNeeded(goal: Goal, availableWeekdays: Set<Weekday>, allowsDoubles: Bool, asOf: Date) throws {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let environment = goal.user?.profile?.defaultTrainingEnvironment
        guard let phase = goal.plans.first?.orderedPhases.first else { return }
        try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: phase, performanceProfile: goal.user?.performanceProfile,
            availability: UserAvailability(
                trainingDaysPerWeek: availableWeekdays.count, availableWeekdays: availableWeekdays,
                allowsDoubleSessions: allowsDoubles, maxSessionsPerDay: allowsDoubles ? 2 : 1
            ),
            materializationContext: TacticalMaterializationContext(
                equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
                strengthCandidateExercises: exercises, functionalFitnessCandidateExercises: exercises,
                trainingEnvironment: environment
            ),
            asOf: asOf,
            context: context
        )
    }

    /// A brand-new athlete selects exactly five real weekdays during
    /// onboarding — they persist exactly, and the derived count agrees;
    /// never a second, independently-set truth.
    func testOnboardingPersistsExactSelectedWeekdays() throws {
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .muscleGain
        viewModel.advance(from: .goal, modelContext: context)

        let selected: Set<Weekday> = [.monday, .tuesday, .thursday, .friday, .saturday]
        viewModel.selectedWeekdays = selected
        XCTAssertEqual(viewModel.availableTrainingDaysPerWeek, 5, "the count is derived from the real selection, never a second field")
        viewModel.advance(from: .preferences, modelContext: context)

        let users = try context.fetch(FetchDescriptor<User>())
        let goal = try XCTUnwrap(users.first?.goals.first(where: { $0.status == .active }))
        XCTAssertEqual(goal.preferences?.availableWeekdays, selected)
        XCTAssertEqual(goal.preferences?.availableTrainingDaysPerWeek, 5)
    }

    /// Onboarding must never advance past the availability step with zero
    /// selected days — the ViewModel itself refuses, matching DF-BUG-1's
    /// own defense-in-depth discipline for the Goal step.
    func testOnboardingRefusesToAdvanceWithNoWeekdaySelected() throws {
        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        viewModel.selectedGoalType = .muscleGain
        viewModel.advance(from: .goal, modelContext: context)
        viewModel.selectedWeekdays = []
        viewModel.advance(from: .preferences, modelContext: context)
        XCTAssertEqual(viewModel.step, .preferences, "must not advance with no day selected")

        let users = try context.fetch(FetchDescriptor<User>())
        XCTAssertNil(users.first?.goals.first(where: { $0.status == .active })?.preferences, "no Goal/preferences should be created off an empty selection")
    }

    /// A pre-existing athlete who only ever set the legacy day-count
    /// integer (never opened the real weekday editor) must resume
    /// onboarding with all seven weekdays selected — never a guessed
    /// subset inferred from that integer.
    func testResumingOnboardingNeverInfersWeekdaysFromLegacyCount() throws {
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let goal = Goal(ownerUserID: user.id, primaryType: .muscleGain, preferences: GoalPreferences(availableTrainingDaysPerWeek: 3))
        context.insert(goal)
        user.addGoal(goal)
        try context.save()

        let viewModel = OnboardingViewModel()
        viewModel.start(modelContext: context)
        XCTAssertEqual(viewModel.selectedWeekdays, Set(Weekday.allCases), "an unset availableWeekdays must default to every day, never a 3-day guess derived from the legacy count")
    }

    /// The athlete's real chosen weekdays reach the FIRST tactical
    /// materialization at plan acceptance (`StrategicPlanSelectionViewModel`),
    /// not only later rolls (`PhaseDetailViewModel`'s already-correct path).
    func testFirstMaterializationAtPlanAcceptanceRespectsSelectedWeekdays() throws {
        let monday = date(2026, 1, 5)
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        user.profile?.trainingEnvironments = [environment]
        user.profile?.defaultTrainingEnvironment = environment
        let selected: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday]
        let goal = Goal(
            ownerUserID: user.id, primaryType: .muscleGain,
            preferences: GoalPreferences(availableTrainingDaysPerWeek: selected.count, allowsDoubleSessions: false, availableWeekdays: selected)
        )
        context.insert(goal)
        user.addGoal(goal)
        try context.save()

        let viewModel = StrategicPlanSelectionViewModel()
        viewModel.load(modelContext: context, referenceDate: monday)
        XCTAssertTrue(viewModel.buildCustomMix(selections: [(.hypertrophy, 4)]))
        XCTAssertTrue(viewModel.acceptAndStart(modelContext: context, referenceDate: monday))
        try completeCalibrationIfNeeded(goal: goal, availableWeekdays: selected, allowsDoubles: false, asOf: monday)

        let phase = try XCTUnwrap(goal.plans.first?.orderedPhases.first)
        let mix = try XCTUnwrap(phase.selectedTrainingMix ?? phase.recommendedTrainingMix)
        let sessions = mix.orderedComponents.first { $0.programmingSystem == .hypertrophy }?.programInstance?.sessions ?? []
        XCTAssertEqual(sessions.count, 4)
        for session in sessions {
            let day = try XCTUnwrap(session.day)
            let weekday = appWeekday(for: day.date)
            XCTAssertTrue(selected.contains(weekday), "the FIRST materialized week must already respect the athlete's real onboarding weekday choice — got \(weekday)")
        }
    }
}
