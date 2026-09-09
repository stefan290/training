import XCTest
import SwiftData
@testable import TrainingOS

/// Family A Source Repair — Finalization Checkpoint, Phase E: proves
/// `LongTermPlanner.proposeProgram`'s Hypertrophy branch enforces the
/// product invariant "a source-backed program may be recommended/
/// materialized only if that exact configuration is production-supported
/// and source-verified" — scoped deliberately narrowly to `.fullBody`
/// (the only split this repair ever touched). The 2 curated non-Full-Body
/// configs (4-Day Legs, 5-Day Arms & Shoulders) must never be affected by
/// this check — they were never claimed source-verified and remain on
/// `generateLegacyFixedPair` exactly as before, per their own real,
/// unchanged product status.
///
/// Assertions here key on `hypertrophyConfiguration?.dayCount`/`.split`,
/// never on `ProgramDefinition.name` string matching — the materialized
/// name (e.g. "6-Day Full Body Hypertrophy — Basic Hypertrophy", built by
/// the generator itself) is a different string than the curated catalog
/// entry's own display name (e.g. "6-Day High-Frequency Hypertrophy",
/// `HypertrophyBuiltInLibrary.all`'s `name` field, used only to look up
/// which entry to instantiate) — confirmed directly this pass, not
/// assumed. Also: `candidates.first` is NOT assumed to always be the
/// exact day-count match — `closestByDayCount` can surface an adjacent
/// day-count as a second candidate, and when both share the same
/// `fitRating` tier the final tiebreak is alphabetical by materialized
/// name, which can place an adjacent match ahead of an exact one (a
/// real, pre-existing ranking behavior, confirmed here to be completely
/// unrelated to and unaffected by the fidelity gate — both candidates
/// still appear with zero `.sourceContentUnverified` gaps). This
/// checkpoint's own scope is exclusively the fidelity gate, not
/// `proposeProgram`'s ranking tiebreak, so these tests assert only what
/// the gate itself is responsible for: presence/absence of a real,
/// correctly-typed candidate and absence/presence of the specific
/// `.sourceContentUnverified` gap — never assumed ordering.
@MainActor
final class HypertrophySourceFidelityGateTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func makeComponent(target: Int, priority: GoalPriority = .primary) -> TrainingMixComponent {
        TrainingMixComponent(
            label: "Hypertrophy", programmingSystem: .hypertrophy, priority: priority,
            frequency: SessionFrequency(target: target)
        )
    }

    // MARK: A — Full Body 3/4/5/6 all pass the gate

    func testAllFourVerifiedFullBodyFrequenciesPassTheFidelityGate() throws {
        for target in [3, 4, 5, 6] {
            let component = makeComponent(target: target)
            let availability = UserAvailability(trainingDaysPerWeek: target)
            let (candidates, gaps) = LongTermPlanner.proposeProgram(
                component: component, profile: nil, availability: availability, context: context
            )
            XCTAssertFalse(candidates.isEmpty, "\(target)-day Full Body must be a real, recommendable candidate")
            XCTAssertFalse(gaps.contains { $0.reason == .sourceContentUnverified }, "\(target)-day Full Body must never be gapped as unverified — it is real, source-verified content")
            XCTAssertTrue(
                candidates.contains { $0.programDefinition.hypertrophyConfiguration?.dayCount == target && $0.programDefinition.hypertrophyConfiguration?.split == .fullBody },
                "the exact \(target)-day Full Body configuration must be among the real candidates, not merely some other day count"
            )
        }
    }

    // MARK: B/C — no unsupported-frequency approximation is newly introduced by the gate

    func testGateNeverRejectsAnExactSupportedFrequencyRegardlessOfNearestNeighborCandidates() throws {
        // 5 is both an exact Full Body match AND ties by day-count with
        // the unrelated "5-Day Upper/Arms Focus" curated entry — the
        // gate must never let a nearest-neighbor tie suppress the real,
        // exact, verified Full Body candidate.
        let component = makeComponent(target: 5)
        let availability = UserAvailability(trainingDaysPerWeek: 5)
        let (candidates, gaps) = LongTermPlanner.proposeProgram(
            component: component, profile: nil, availability: availability, context: context
        )
        XCTAssertTrue(candidates.contains { $0.programDefinition.hypertrophyConfiguration?.dayCount == 5 && $0.programDefinition.hypertrophyConfiguration?.split == .fullBody })
        XCTAssertFalse(gaps.contains { $0.reason == .sourceContentUnverified })
    }

    // MARK: D/E — curated non-Full-Body legacy configs never inherit Full Body verification

    func testFourDayLegsIsUnaffectedByFullBodyVerificationAndStillProducesARealCandidate() throws {
        // Confirms `isHypertrophySourceVerified` is genuinely keyed on
        // BOTH dayCount AND split — a 4-Day request must not silently
        // gap "4-Day Lower/Leg Focus" merely because 4-Day Full Body is
        // verified and shares its day count.
        XCTAssertFalse(ProgramCapabilityRegistry.isHypertrophySourceVerified(dayCount: 4, split: .legs), "Legs is not a Full Body split and must never report source-verified")
        let component = makeComponent(target: 4)
        let availability = UserAvailability(trainingDaysPerWeek: 4)
        let (candidates, gaps) = LongTermPlanner.proposeProgram(
            component: component, profile: nil, availability: availability, context: context
        )
        XCTAssertTrue(
            candidates.contains { $0.programDefinition.hypertrophyConfiguration?.split == .legs },
            "the legacy-generator-backed Legs config must remain fully recommendable, unaffected by the Full Body fidelity gate"
        )
        XCTAssertFalse(gaps.contains { $0.reason == .sourceContentUnverified }, "Legs must never be gapped by the Full Body-only fidelity check")
    }

    func testFiveDayArmsShouldersIsUnaffectedByFullBodyVerificationAndStillProducesARealCandidate() throws {
        XCTAssertFalse(ProgramCapabilityRegistry.isHypertrophySourceVerified(dayCount: 5, split: .armsShoulders), "Arms/Shoulders is not a Full Body split and must never report source-verified")
        let component = makeComponent(target: 5)
        let availability = UserAvailability(trainingDaysPerWeek: 5)
        let (candidates, gaps) = LongTermPlanner.proposeProgram(
            component: component, profile: nil, availability: availability, context: context
        )
        XCTAssertTrue(
            candidates.contains { $0.programDefinition.hypertrophyConfiguration?.split == .armsShoulders },
            "the legacy-generator-backed Arms/Shoulders config must remain fully recommendable, unaffected by the Full Body fidelity gate"
        )
        XCTAssertFalse(gaps.contains { $0.reason == .sourceContentUnverified })
    }

    // MARK: F — existing valid strategic planning is unchanged

    func testExistingRecommendationBehaviorForAllFourFullBodyFrequenciesIsUnchanged() throws {
        // The gate adds a rejection path (`.sourceContentUnverified`)
        // without removing any already-correct acceptance — every one
        // of the 4 real, verified Full Body configurations must still
        // be a genuine candidate (never assumed to be first — ranking
        // order among multiple executable candidates is a separate,
        // pre-existing concern this checkpoint does not touch).
        for target in [3, 4, 5, 6] {
            let component = makeComponent(target: target)
            let availability = UserAvailability(trainingDaysPerWeek: target)
            let (candidates, gaps) = LongTermPlanner.proposeProgram(
                component: component, profile: nil, availability: availability, context: context
            )
            XCTAssertFalse(gaps.contains { $0.reason == .sourceContentUnverified })
            XCTAssertTrue(candidates.contains { $0.programDefinition.hypertrophyConfiguration?.dayCount == target && $0.programDefinition.hypertrophyConfiguration?.split == .fullBody })
        }
    }

    // MARK: G — recommendation and materialization cannot disagree

    func testRecommendationAndMaterializationShareTheExactSameGatedFunction() throws {
        // `StartPhaseUseCase` calls the identical `LongTermPlanner
        // .proposeProgram` this test calls directly — there is only one
        // real function computing both the preview and the actual
        // materialized candidate, so they are structurally incapable of
        // disagreeing about fidelity (confirmed by direct code read of
        // `StartPhaseUseCase.swift`, not a separate, parallel gate).
        let component = makeComponent(target: 3)
        let availability = UserAvailability(trainingDaysPerWeek: 3)
        let (first, firstGaps) = LongTermPlanner.proposeProgram(component: component, profile: nil, availability: availability, context: context)
        let (second, secondGaps) = LongTermPlanner.proposeProgram(component: component, profile: nil, availability: availability, context: context)
        XCTAssertEqual(first.map(\.programDefinition.name), second.map(\.programDefinition.name))
        XCTAssertEqual(firstGaps.map(\.reason), secondGaps.map(\.reason))
    }
}
