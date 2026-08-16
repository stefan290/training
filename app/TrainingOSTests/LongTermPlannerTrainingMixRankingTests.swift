import XCTest
@testable import TrainingOS

/// `ADHERENCE_AWARE_PLANNING.md` §5 — the two-stage ranking model, tested
/// two ways: `rankCandidateMixes` directly against hand-constructed
/// `GoalAlignment`s (full control over tier gaps, no scheduler needed),
/// and `proposeTrainingMix` end-to-end against real `TrainingPhase`/`Goal`
/// inputs (`LONG_TERM_PLANNER.md` §5's actual public surface).
final class LongTermPlannerTrainingMixRankingTests: XCTestCase {
    private func alignment(_ rating: GoalAlignmentRating) -> GoalAlignment {
        GoalAlignment(rating: rating, factors: [])
    }

    private func mix(_ name: String, components: [(label: String, system: ProgrammingSystemKind, target: Int)]) -> TrainingMix {
        let mix = TrainingMix(kind: .recommended, name: name)
        for component in components {
            mix.addComponent(TrainingMixComponent(
                label: component.label, programmingSystem: component.system, priority: .primary,
                frequency: SessionFrequency(target: component.target)
            ))
        }
        return mix
    }

    // MARK: - §5a: the compatibility gate

    /// §5d's Candidate C: `.poor`-alignment, strongly preference-aligned
    /// — must never be promotable, regardless of preference match.
    func testPoorCandidateNeverPromotedRegardlessOfPreferenceAlignment() throws {
        let excellentCandidate = LongTermPlanner.RawMixCandidate(
            mix: mix("A", components: [("Hypertrophy", .hypertrophy, 5)]),
            alignment: alignment(.excellent),
            reasonCodes: [.phaseSelectedForGoal]
        )
        let poorButPreferredCandidate = LongTermPlanner.RawMixCandidate(
            mix: mix("C", components: [("Functional Fitness", .functionalFitness, 3)]),
            alignment: alignment(.poor),
            reasonCodes: [.phaseSelectedForGoal]
        )
        let preferences = GoalPreferences(
            preferredModalities: [ModalityPreference(system: .functionalFitness)],
            varietyPreference: .high
        )

        let ranked = LongTermPlanner.rankCandidateMixes([excellentCandidate, poorButPreferredCandidate], preferences: preferences)

        let poorResult = try XCTUnwrap(ranked.first { $0.mix.name == "C" })
        XCTAssertTrue(poorResult.roles.isEmpty, "a Poor candidate must never carry any promotable role")
        let excellentResult = try XCTUnwrap(ranked.first { $0.mix.name == "A" })
        XCTAssertTrue(excellentResult.roles.contains(.recommended))
        XCTAssertTrue(excellentResult.roles.contains(.bestGoalAlignment))
    }

    /// §5d's exact worked example: Candidate B is one tier below A,
    /// preference-aligned — promoted to `.recommended`; A remains shown,
    /// tagged `.bestGoalAlignment`.
    func testWorkedExamplePromotesOneTierLowerPreferenceAlignedCandidate() throws {
        let candidateA = LongTermPlanner.RawMixCandidate(
            mix: mix("5-Day Hypertrophy + 2 Zone 2", components: [
                ("Hypertrophy", .hypertrophy, 5), ("Zone 2", .steadyState, 2),
            ]),
            alignment: alignment(.excellent),
            reasonCodes: [.phaseSelectedForGoal]
        )
        let candidateB = LongTermPlanner.RawMixCandidate(
            mix: mix("3 Strength + 2 FF + 1 Run", components: [
                ("Strength", .hypertrophy, 3), ("Functional Fitness", .functionalFitness, 2), ("Running", .steadyState, 1),
            ]),
            alignment: alignment(.good),
            reasonCodes: [.phaseSelectedForGoal]
        )
        let preferences = GoalPreferences(
            preferredModalities: [ModalityPreference(system: .functionalFitness)],
            varietyPreference: .moderate
        )

        let ranked = LongTermPlanner.rankCandidateMixes([candidateA, candidateB], preferences: preferences)

        let resultB = try XCTUnwrap(ranked.first { $0.mix.name == "3 Strength + 2 FF + 1 Run" })
        XCTAssertEqual(resultB.roles, [.recommended])
        XCTAssertTrue(resultB.reasonCodes.contains(.adherencePreferencePromotedAlternative))

        let resultA = try XCTUnwrap(ranked.first { $0.mix.name == "5-Day Hypertrophy + 2 Zone 2" })
        XCTAssertEqual(resultA.roles, [.bestGoalAlignment])
        XCTAssertFalse(resultA.roles.contains(.recommended), "A is never hidden, but is no longer the recommended slot")
    }

    // MARK: - §5b: bounded promotion

    func testNoPromotionWhenNoPreferenceStatedRecommendedEqualsBestGoalAlignment() throws {
        let best = LongTermPlanner.RawMixCandidate(
            mix: mix("Best", components: [("Hypertrophy", .hypertrophy, 5)]),
            alignment: alignment(.excellent), reasonCodes: [.phaseSelectedForGoal]
        )
        let other = LongTermPlanner.RawMixCandidate(
            mix: mix("Other", components: [("Functional Fitness", .functionalFitness, 3)]),
            alignment: alignment(.good), reasonCodes: [.phaseSelectedForGoal]
        )

        let ranked = LongTermPlanner.rankCandidateMixes([best, other], preferences: nil)

        let bestResult = try XCTUnwrap(ranked.first { $0.mix.name == "Best" })
        XCTAssertEqual(bestResult.roles, [.recommended, .bestGoalAlignment])
    }

    /// A preference-aligned candidate more than `maxPromotableTierGap`
    /// tiers below the best must never be promoted — it may still be
    /// surfaced as a plain preference alternative.
    func testPromotionRespectsTierGapBound() throws {
        let best = LongTermPlanner.RawMixCandidate(
            mix: mix("Best", components: [("Hypertrophy", .hypertrophy, 5)]),
            alignment: alignment(.excellent), reasonCodes: [.phaseSelectedForGoal]
        )
        let tooFarBelow = LongTermPlanner.RawMixCandidate(
            mix: mix("TooFarBelow", components: [("Functional Fitness", .functionalFitness, 3)]),
            alignment: alignment(.acceptable), reasonCodes: [.phaseSelectedForGoal]
        )
        let preferences = GoalPreferences(preferredModalities: [ModalityPreference(system: .functionalFitness)])

        let ranked = LongTermPlanner.rankCandidateMixes([best, tooFarBelow], preferences: preferences)

        let bestResult = try XCTUnwrap(ranked.first { $0.mix.name == "Best" })
        XCTAssertTrue(bestResult.roles.contains(.recommended), "the 2-tier-below candidate must not have displaced the best")
        let farResult = try XCTUnwrap(ranked.first { $0.mix.name == "TooFarBelow" })
        XCTAssertFalse(farResult.roles.contains(.recommended))
        XCTAssertTrue(farResult.roles.contains(.userPreferenceAlternative), "still surfaced, just not promoted")
    }

    func testHighVarietyPreferenceRequiresStrictlyMoreDistinctSystemsThanBest() throws {
        let best = LongTermPlanner.RawMixCandidate(
            mix: mix("Best", components: [("Hypertrophy", .hypertrophy, 5), ("Functional Fitness", .functionalFitness, 2)]),
            alignment: alignment(.excellent), reasonCodes: [.phaseSelectedForGoal]
        )
        // Same distinct-system count (2) as `best` — high variety preference must reject this as "not more varied."
        let sameVarietyCount = LongTermPlanner.RawMixCandidate(
            mix: mix("SameVariety", components: [("Hypertrophy", .hypertrophy, 3), ("Functional Fitness", .functionalFitness, 2)]),
            alignment: alignment(.good), reasonCodes: [.phaseSelectedForGoal]
        )
        let preferences = GoalPreferences(
            preferredModalities: [ModalityPreference(system: .functionalFitness)],
            varietyPreference: .high
        )

        let ranked = LongTermPlanner.rankCandidateMixes([best, sameVarietyCount], preferences: preferences)

        let sameVarietyResult = try XCTUnwrap(ranked.first { $0.mix.name == "SameVariety" })
        XCTAssertFalse(sameVarietyResult.roles.contains(.recommended), "no strictly-more-variety, so high variety preference must not promote it")
    }

    // MARK: - Capability gate (`LONG_TERM_PLANNER.md` §2a)

    func testCandidateWithUnassignedComponentIsDroppedEntirely() {
        let unassigned = TrainingMix(kind: .recommended, name: "Unassigned")
        unassigned.addComponent(TrainingMixComponent(label: "Mystery", priority: .primary, frequency: SessionFrequency(target: 2)))
        let raw = LongTermPlanner.RawMixCandidate(mix: unassigned, alignment: alignment(.excellent), reasonCodes: [])

        let ranked = LongTermPlanner.rankCandidateMixes([raw], preferences: nil)

        XCTAssertTrue(ranked.isEmpty)
    }

    // MARK: - Determinism (§37)

    func testRankingIsDeterministicAcrossRepeatedCalls() {
        let candidateA = LongTermPlanner.RawMixCandidate(
            mix: mix("A", components: [("Hypertrophy", .hypertrophy, 5)]),
            alignment: alignment(.excellent), reasonCodes: [.phaseSelectedForGoal]
        )
        let candidateB = LongTermPlanner.RawMixCandidate(
            mix: mix("B", components: [("Functional Fitness", .functionalFitness, 3)]),
            alignment: alignment(.good), reasonCodes: [.phaseSelectedForGoal]
        )
        let preferences = GoalPreferences(preferredModalities: [ModalityPreference(system: .functionalFitness)])

        let firstRun = LongTermPlanner.rankCandidateMixes([candidateA, candidateB], preferences: preferences)
        let secondRun = LongTermPlanner.rankCandidateMixes([candidateA, candidateB], preferences: preferences)

        XCTAssertEqual(firstRun.map(\.mix.name), secondRun.map(\.mix.name))
        XCTAssertEqual(firstRun.map(\.roles), secondRun.map(\.roles))
    }

    // MARK: - `proposeTrainingMix` end-to-end (`LONG_TERM_PLANNER.md` §5)

    private func makeGoal(primaryType: GoalType, preferences: GoalPreferences? = nil, milestoneDate: Date? = nil) -> Goal {
        Goal(ownerUserID: UUID(), primaryType: primaryType, milestoneDate: milestoneDate, preferences: preferences, createdAt: Date(timeIntervalSince1970: 0))
    }

    private func makePhase(type: PhaseType, startDate: Date = Date(timeIntervalSince1970: 0)) -> TrainingPhase {
        TrainingPhase(type: type, startDate: startDate, priorityRule: .mixedModal)
    }

    func testMuscleGainPhaseProducesTheTwoWorkedExampleCandidates() {
        let phase = makePhase(type: .muscleGain)
        let goal = makeGoal(primaryType: .muscleGain)

        let candidates = LongTermPlanner.proposeTrainingMix(phase: phase, goal: goal)

        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.contains { $0.mix.orderedComponents.contains { $0.programmingSystem == .hypertrophy } })
        XCTAssertLessThanOrEqual(candidates.count, 4, "never dozens of choices — §5c")
        XCTAssertTrue(candidates.contains { $0.roles.contains(.recommended) })
    }

    func testFatLossPhaseProtectsResistanceTrainingAsRequiredSecondaryComponent() throws {
        let phase = makePhase(type: .fatLoss)
        let goal = makeGoal(primaryType: .fatLoss, milestoneDate: Date(timeIntervalSince1970: 86_400 * 90))

        let candidates = LongTermPlanner.proposeTrainingMix(phase: phase, goal: goal)

        let protectedResistance = candidates
            .flatMap(\.mix.orderedComponents)
            .first { $0.programmingSystem == .hypertrophy }
        let protected = try XCTUnwrap(protectedResistance)
        XCTAssertEqual(protected.priority, .secondary)
        XCTAssertEqual(protected.flexibility, .required)
        XCTAssertTrue(candidates.contains { $0.reasonCodes.contains(.fatLossTimedToMilestone) })
        XCTAssertTrue(candidates.contains { $0.reasonCodes.contains(.muscleRetentionPriority) })
    }

    func testFunctionalFitnessPhaseHasARequiredPrimaryComponent() throws {
        let phase = makePhase(type: .functionalFitness)
        let goal = makeGoal(primaryType: .functionalFitness)

        let candidates = LongTermPlanner.proposeTrainingMix(phase: phase, goal: goal)

        let primary = try XCTUnwrap(candidates.first?.mix.orderedComponents.first)
        XCTAssertEqual(primary.programmingSystem, .functionalFitness)
        XCTAssertEqual(primary.priority, .primary)
        XCTAssertEqual(primary.flexibility, .required)
    }

    func testEnduranceEventPhaseUsesStatedActivityPreferenceForItsLabel() {
        let phase = makePhase(type: .enduranceEvent)
        let preferences = GoalPreferences(preferredModalities: [ModalityPreference(system: .steadyState, activityType: .cycling)])
        let goal = makeGoal(primaryType: .enduranceEvent, preferences: preferences)

        let candidates = LongTermPlanner.proposeTrainingMix(phase: phase, goal: goal)

        XCTAssertTrue(candidates.contains { $0.mix.name.contains("Cycling") })
    }

    func testEveryPhaseTypeProducesAtLeastOneInstantiableCandidate() {
        for type in PhaseType.allCases {
            let phase = makePhase(type: type)
            let goal = makeGoal(primaryType: .maintenance)
            let candidates = LongTermPlanner.proposeTrainingMix(phase: phase, goal: goal)
            XCTAssertFalse(candidates.isEmpty, "\(type) produced no candidates")
        }
    }

    func testIdenticalPhaseAndGoalInputsProduceIdenticalCandidateRanking() {
        let phase = makePhase(type: .muscleGain)
        let goal = makeGoal(primaryType: .muscleGain)

        let firstRun = LongTermPlanner.proposeTrainingMix(phase: phase, goal: goal)
        let secondRun = LongTermPlanner.proposeTrainingMix(phase: phase, goal: goal)

        XCTAssertEqual(firstRun.map(\.mix.name), secondRun.map(\.mix.name))
        XCTAssertEqual(firstRun.map(\.roles), secondRun.map(\.roles))
        XCTAssertEqual(firstRun.map(\.alignment.rating), secondRun.map(\.alignment.rating))
    }
}
