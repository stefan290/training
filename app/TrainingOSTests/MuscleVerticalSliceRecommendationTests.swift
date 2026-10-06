import XCTest
import SwiftData
@testable import TrainingOS

/// MUSCLE VERTICAL SLICE REPAIR — Section 21, tests A-E: the recommendation-
/// engine/Custom-Mix unification half of the order (Sections 1-4). Every
/// assertion here goes through the REAL production entry points
/// (`PlanPresentation`, `LongTermPlanner.proposeTrainingMix`,
/// `LongTermPlanner.buildCustomMix`) — never a hand-built stand-in.
@MainActor
final class MuscleVerticalSliceRecommendationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    @discardableResult
    private func makeOnboardedAthlete(
        goalType: GoalType, trainingDays: Int,
        preferredModalities: [ModalityPreference] = []
    ) throws -> (user: User, goal: Goal) {
        let user = AppRootStateResolver.ensureBaselineIdentity(context: context)
        let environment = TrainingEnvironmentTestSupport.full(context: context)
        user.profile?.trainingEnvironments = [environment]
        user.profile?.defaultTrainingEnvironment = environment
        let goal = Goal(
            ownerUserID: user.id, primaryType: goalType,
            preferences: GoalPreferences(
                preferredModalities: preferredModalities,
                availableTrainingDaysPerWeek: trainingDays
            )
        )
        context.insert(goal)
        user.addGoal(goal)
        try context.save()
        return (user, goal)
    }

    private func muscleGainPreviewPhase() -> TrainingPhase {
        TrainingPhase(type: .muscleGain, startDate: Date(), priorityRule: .mixedModal, status: .planned)
    }

    // MARK: - A: "Lose Fat" absent from new-athlete Main Goal options

    func testLoseFatAbsentFromNewAthleteMainGoalOptions() {
        XCTAssertFalse(PlanPresentation.mainGoalOptions.contains(.fatLoss),
                       "Lose Fat must never be offered as a new-athlete primary goal")
        // Legacy compatibility: the case and its label are untouched.
        XCTAssertEqual(PlanPresentation.mainGoalLabel(.fatLoss), "Lose Fat")
    }

    // MARK: - B: Build Muscle + 5 days + no conditioning preference -> exactly 5x Hypertrophy

    func testBuildMuscleFiveDaysNoConditioningPreferenceRecommendsExactlyFiveHypertrophy() throws {
        let (_, goal) = try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: 5)
        let candidates = LongTermPlanner.proposeTrainingMix(phase: muscleGainPreviewPhase(), goal: goal)

        let recommended = try XCTUnwrap(candidates.first { $0.roles.contains(.recommended) },
                                        "no candidate carries the .recommended role")
        let components = recommended.mix.orderedComponents
        XCTAssertEqual(components.count, 1, "the locked product decision is a single-system recommendation, not an invented split")
        let hypertrophy = try XCTUnwrap(components.first)
        XCTAssertEqual(hypertrophy.programmingSystem, .hypertrophy)
        XCTAssertEqual(hypertrophy.frequency.target, 5, "5 days, no conditioning preference -> 5x Hypertrophy, never a fabricated Hypertrophy+Zone2 split")
    }

    // MARK: - C: the fixed "Focused Hypertrophy" candidate passes the canonical
    // TrainingMix validation at every realistic capacity, not merely the
    // exact worked example

    /// Scoped to the ONE candidate Sections 2-3 actually redesigned
    /// ("Focused Hypertrophy," now single-component Hypertrophy-only).
    /// NOTE (honest disclosure, not silently decided): the OTHER real
    /// muscleGain candidate, "Strength Plus Variety" (`muscleGainVariedMix`),
    /// was found DURING this fix to scale its Hypertrophy component below
    /// its real curated minimum (3) at 3/4/5-day capacities (e.g. 2 at 5
    /// days) — `proposeProgram`'s pre-existing, deliberate, separately-
    /// tested "closest curated day count" graceful degradation
    /// (`testHypertrophyComponentRecommendsClosestDayCountFromCuratedLibrary`)
    /// still recovers a real, executable 3-day program for it, so this is
    /// NOT the same defect class as the removed hardcoded Zone2 worked
    /// example (which used a genuinely UNVALIDATED, unrestricted system).
    /// Attempting to blanket-reject every scaled candidate against
    /// `buildCustomMix`'s strict standard broke multiple other REAL,
    /// already-accepted preference-driven recommendations (verified by
    /// reproducing the regression, then reverting) — this is a genuine,
    /// pre-existing product-design question (should a recommendation-
    /// engine-scaled candidate ever be allowed to silently target a
    /// non-curated frequency the way Custom Mix explicitly may not?),
    /// out of this checkpoint's scope to silently decide (CLAUDE.md rule
    /// 10) and flagged here rather than papered over.
    func testFocusedHypertrophyRecommendationPassesCanonicalCapabilityValidationAtEveryRealisticCapacity() throws {
        for days in [3, 4, 5, 6, 7] {
            let (_, goal) = try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: days)
            let candidates = LongTermPlanner.proposeTrainingMix(phase: muscleGainPreviewPhase(), goal: goal)
            let focused = try XCTUnwrap(candidates.first { $0.mix.name == "Focused Hypertrophy" },
                                       "'Focused Hypertrophy' candidate missing at \(days) days/week")
            XCTAssertTrue(
                LongTermPlanner.recommendedMixPassesCanonicalCapabilityValidation(focused.mix),
                "'Focused Hypertrophy' at \(days) days/week fails the same capability validation a user-created Custom Mix would be held to"
            )
        }
    }

    // MARK: - D: the exact locked scenario's recommendation would also be
    // accepted by Custom Mix's own validation

    func testLockedFiveDayRecommendationWouldAlsoBeAcceptedByBuildCustomMixValidation() throws {
        let (_, goal) = try makeOnboardedAthlete(goalType: .muscleGain, trainingDays: 5)
        let candidates = LongTermPlanner.proposeTrainingMix(phase: muscleGainPreviewPhase(), goal: goal)
        let recommended = try XCTUnwrap(candidates.first { $0.roles.contains(.recommended) })

        let selections: [(style: TrainingStyle, frequency: Int)] = recommended.mix.orderedComponents.compactMap { component in
            guard let system = component.programmingSystem, component.frequency.target > 0 else { return nil }
            guard let style = TrainingStyle.allCases.first(where: { LongTermPlanner.underlyingSystem(for: $0) == system }) else {
                return nil
            }
            return (style, component.frequency.target)
        }
        XCTAssertFalse(selections.isEmpty)
        let capacity = selections.reduce(0) { $0 + $1.frequency }

        let result = LongTermPlanner.buildCustomMix(selections: selections, capacity: capacity, phaseType: .muscleGain)
        switch result {
        case .success: break
        case .failure(let error):
            XCTFail("The locked 5-day recommendation would be REJECTED by the same domain validation the Custom Mix flow uses: \(error)")
        }
    }

    // MARK: - E: Running's real supported-frequency constraint is never weakened

    func testRunningSupportedFrequencyConstraintIsNotWeakenedByCustomMixValidation() throws {
        let supported = try XCTUnwrap(ProgramCapabilityRegistry.supportedFrequencies(for: .running),
                                      "Running must remain a REAL, restricted-frequency system (never unrestricted)")
        XCTAssertEqual(supported, [2], "Running's real curated capability today is exactly the 5K/2-Day V1 program")

        // A frequency Running does NOT support must still be rejected by
        // buildCustomMix (the exact same authority `.hypertrophy`'s fix
        // above must respect) -- this proves Section 2's unification did
        // not accidentally loosen Running's own real constraint.
        let rejected = LongTermPlanner.buildCustomMix(
            selections: [(style: .running, frequency: 3)], capacity: 3, phaseType: nil
        )
        switch rejected {
        case .success:
            XCTFail("Running at an unsupported frequency (3) must be rejected, not silently accepted")
        case .failure(let error):
            XCTAssertEqual(error, .unsupportedFrequency(style: .running, frequency: 3))
        }

        // The one real supported frequency must still succeed.
        let accepted = LongTermPlanner.buildCustomMix(
            selections: [(style: .running, frequency: 2)], capacity: 2, phaseType: nil
        )
        guard case .success = accepted else {
            XCTFail("Running at its real supported frequency (2) must be accepted")
            return
        }
    }
}
