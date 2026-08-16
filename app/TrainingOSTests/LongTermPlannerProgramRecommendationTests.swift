import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 5B §42: proves `LongTermPlanner.proposeProgram` only ever
/// returns real, executable candidates, uses `ProgramCapabilityRegistry`
/// as the gate, and never fabricates a `ProgramDefinition`.
@MainActor
final class LongTermPlannerProgramRecommendationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func makeComponent(
        label: String,
        system: ProgrammingSystemKind,
        target: Int,
        priority: GoalPriority = .primary
    ) -> TrainingMixComponent {
        TrainingMixComponent(
            label: label, programmingSystem: system, priority: priority,
            frequency: SessionFrequency(target: target)
        )
    }

    // MARK: - Curated-library path (Hypertrophy/Powerlifting)

    func testHypertrophyComponentRecommendsClosestDayCountFromCuratedLibrary() throws {
        let component = makeComponent(label: "Hypertrophy", system: .hypertrophy, target: 5)
        let availability = UserAvailability(trainingDaysPerWeek: 5)

        let (candidates, gaps) = LongTermPlanner.proposeProgram(
            component: component, profile: nil, availability: availability, context: context
        )

        XCTAssertTrue(gaps.isEmpty)
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.allSatisfy { $0.programmingSystem == .hypertrophy })
        // The top candidate should be an exact 5-day match.
        XCTAssertEqual(candidates.first?.programDefinition.hypertrophyConfiguration?.dayCount, 5)
        XCTAssertTrue(candidates.contains { $0.factors.contains { $0.kind == .programAvailabilityMatch && $0.satisfied } },
                      "a curated V1 preset should be marked as such")
    }

    func testPowerliftingComponentRecommendsFromCuratedLibrary() throws {
        let component = makeComponent(label: "Strength", system: .powerlifting, target: 4)
        let availability = UserAvailability(trainingDaysPerWeek: 4)

        let (candidates, _) = LongTermPlanner.proposeProgram(
            component: component, profile: nil, availability: availability, context: context
        )

        XCTAssertFalse(candidates.isEmpty)
        XCTAssertEqual(candidates.first?.programDefinition.powerliftingConfiguration?.dayCount, 4)
    }

    // MARK: - No curated preset, still real and executable (§5d of PROGRAM_RECOMMENDATION_MODEL.md)

    func testSteadyStateComponentGeneratesRealExecutableProgramWithNoCuratedPreset() throws {
        let component = makeComponent(label: "Zone 2", system: .steadyState, target: 2, priority: .supporting)
        let availability = UserAvailability(trainingDaysPerWeek: 6)

        let (candidates, gaps) = LongTermPlanner.proposeProgram(
            component: component, profile: nil, availability: availability, context: context
        )

        XCTAssertTrue(gaps.isEmpty)
        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.programmingSystem, .steadyState)
        // Real, materialized — has template sessions, not a fabricated stub.
        XCTAssertFalse(candidate.programDefinition.orderedTemplateSessions.isEmpty)
        XCTAssertFalse(candidate.factors.contains { $0.kind == .programAvailabilityMatch && $0.satisfied },
                       "no curated preset exists for SteadyState yet — factor must say so honestly")
    }

    func testFunctionalFitnessComponentGeneratesRealExecutableProgram() throws {
        let component = makeComponent(label: "Functional Fitness", system: .functionalFitness, target: 3)
        let availability = UserAvailability(trainingDaysPerWeek: 6)

        let (candidates, gaps) = LongTermPlanner.proposeProgram(
            component: component, profile: nil, availability: availability, context: context
        )

        XCTAssertTrue(gaps.isEmpty)
        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidate.programDefinition.programmingSystem, .functionalFitness)
        XCTAssertFalse(candidate.programDefinition.orderedTemplateSessions.isEmpty)
    }

    // MARK: - PerformanceProfile informs experienceMatch (§34)

    func testConfidentPerformanceHistoryImprovesExperienceMatch() throws {
        let component = makeComponent(label: "Hypertrophy", system: .hypertrophy, target: 4)
        let availability = UserAvailability(trainingDaysPerWeek: 4)

        let (withoutHistory, _) = LongTermPlanner.proposeProgram(
            component: component, profile: nil, availability: availability, context: context
        )
        XCTAssertFalse(try XCTUnwrap(withoutHistory.first).factors.contains { $0.kind == .experienceMatch && $0.satisfied })

        let profile = PerformanceProfile()
        context.insert(profile)
        let exercise = Exercise(canonicalName: "Barbell Back Squat", modality: .hypertrophy, equipment: "barbell", movementPattern: "squat")
        context.insert(exercise)
        let exerciseProfile = ExercisePerformanceProfile(estimatedOneRepMax: 100, confidence: 0.9)
        exerciseProfile.exercise = exercise
        context.insert(exerciseProfile)
        profile.addExerciseProfile(exerciseProfile)

        let (withHistory, _) = LongTermPlanner.proposeProgram(
            component: component, profile: profile, availability: availability, context: context
        )
        XCTAssertTrue(try XCTUnwrap(withHistory.first).factors.contains { $0.kind == .experienceMatch && $0.satisfied })
    }

    // MARK: - Never a fabricated candidate (§33)

    func testUninstantiableComponentProducesOnlyACapabilityGapNeverAFakeCandidate() throws {
        // A component with no programmingSystem assigned at all cannot
        // be resolved to any generator.
        let component = TrainingMixComponent(label: "Unassigned", priority: .supporting, frequency: SessionFrequency(target: 2))
        let availability = UserAvailability(trainingDaysPerWeek: 6)

        let (candidates, gaps) = LongTermPlanner.proposeProgram(
            component: component, profile: nil, availability: availability, context: context
        )

        XCTAssertTrue(candidates.isEmpty)
        XCTAssertEqual(gaps.count, 1)
        XCTAssertEqual(gaps.first?.reason, .noGeneratorForSystem)
    }

    // MARK: - Determinism (§37)

    func testIdenticalInputsProduceIdenticalRanking() throws {
        let componentA = makeComponent(label: "Hypertrophy", system: .hypertrophy, target: 4)
        let componentB = makeComponent(label: "Hypertrophy", system: .hypertrophy, target: 4)
        let availability = UserAvailability(trainingDaysPerWeek: 4)

        let (candidatesA, _) = LongTermPlanner.proposeProgram(component: componentA, profile: nil, availability: availability, context: context)
        let (candidatesB, _) = LongTermPlanner.proposeProgram(component: componentB, profile: nil, availability: availability, context: context)

        XCTAssertEqual(candidatesA.map(\.programDefinition.name), candidatesB.map(\.programDefinition.name))
        XCTAssertEqual(candidatesA.map(\.fitRating), candidatesB.map(\.fitRating))
    }
}
