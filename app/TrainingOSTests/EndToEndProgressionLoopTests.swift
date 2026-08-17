import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 6D Part 8: the real user loop end to end — a genuinely
/// materialized workout (via `SeedScenarios.materializedLowerASession`,
/// the same real `StrengthMaterializer`-shaped fixture Stage 6C/6D already
/// use), logged through the real use cases, completed through
/// `CompleteSessionUseCase`, read back through the real
/// `DoubleProgressionEngine`-backed `progressionPreview` — never a
/// hand-built prescription bypassing materialization.
@MainActor
final class EndToEndProgressionLoopTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func makeLowerA() -> (session: Session, performanceProfile: PerformanceProfile) {
        let profile = PerformanceProfile()
        context.insert(profile)
        let user = User(displayName: "Test User")
        context.insert(user)
        user.attachPerformanceProfile(profile)

        let catalog = ExerciseCatalog.makeAndInsert(context: context)
        let day = Day(ownerUserID: ownerUserID, date: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(day)
        let fixture = SeedScenarios.materializedLowerASession(day: day, catalog: catalog, ownerUserID: ownerUserID, modelContext: context)
        return (fixture.session, profile)
    }

    private func logSet(
        for movement: ExercisePrescription, setPrescription: SetPrescription, reps: Int, actualRir: Int?, performanceProfile: PerformanceProfile
    ) throws {
        try LogSetUseCase.logSet(
            setIndex: movement.loggedSetResults.count, weight: setPrescription.targetWeight ?? 20,
            reps: reps, targetRir: setPrescription.targetRir, actualRir: actualRir,
            prBand: nil, scoringDirection: .higherIsBetter, context: .rx, setPrescription: setPrescription,
            exercisePrescription: movement, exercise: movement.exercise!, performanceProfile: performanceProfile,
            completedAt: Date(), modelContext: context
        )
    }

    /// TEST A: the materialized workout carries a real prescribed
    /// reps/RIR/load — never a hardcoded execution-time value.
    func testA_MaterializedWorkoutExposesPrescribedRepsRIRAndLoad() throws {
        let (session, _) = makeLowerA()
        let squat = try XCTUnwrap(session.orderedBlocks.first?.orderedPrescriptions.first { $0.exercise?.canonicalName == "Back Squat" })
        let setPrescription = try XCTUnwrap(squat.orderedSetPrescriptions.first)

        XCTAssertGreaterThan(setPrescription.repRangeHigh, 0, "a real rep target, not a placeholder")
        XCTAssertEqual(setPrescription.targetRir, 0, "Squat Pattern is a to-failure primary — RIR is materialized, not hardcoded")
        XCTAssertNotNil(setPrescription.targetWeight, "a real suggested load resolved from the RM-based rule")
    }

    /// TEST B: completed exactly as prescribed (top of range, RIR target
    /// met) — the engine must recommend a load increase, sourced from the
    /// real materialized prescription's own rep range/RIR/weight.
    func testB_CompletingExactlyAsPrescribedRecommendsLoadIncrease() throws {
        let (session, profile) = makeLowerA()
        let block = try XCTUnwrap(session.orderedBlocks.first)
        let squat = try XCTUnwrap(block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Back Squat" })
        for setPrescription in squat.orderedSetPrescriptions {
            try logSet(for: squat, setPrescription: setPrescription, reps: setPrescription.repRangeHigh, actualRir: setPrescription.targetRir, performanceProfile: profile)
        }

        let summary = try CompleteSessionUseCase.complete(session, context: .partial, asOf: Date(), modelContext: context)

        let preview = try XCTUnwrap(summary.progressionPreview.first { $0.exerciseName == "Back Squat" })
        XCTAssertEqual(preview.reasonCode, .loadIncrease)
    }

    /// TEST C: outperforming the prescription — finishing farther from
    /// failure than the target RIR demanded, at or above the top of the
    /// rep range — must still be recognized as a load increase, not
    /// mistaken for a failed/held rep.
    func testC_OutperformingFartherFromFailureThanTargetStillRecommendsLoadIncrease() throws {
        let (session, profile) = makeLowerA()
        let block = try XCTUnwrap(session.orderedBlocks.first)
        let squat = try XCTUnwrap(block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Back Squat" })
        for setPrescription in squat.orderedSetPrescriptions {
            let target = setPrescription.targetRir ?? 0
            try logSet(for: squat, setPrescription: setPrescription, reps: setPrescription.repRangeHigh + 2, actualRir: target + 2, performanceProfile: profile)
        }

        let summary = try CompleteSessionUseCase.complete(session, context: .partial, asOf: Date(), modelContext: context)

        let preview = try XCTUnwrap(summary.progressionPreview.first { $0.exerciseName == "Back Squat" })
        XCTAssertEqual(preview.reasonCode, .loadIncrease, "exceeding the top of range with reps still in reserve is never mistaken for a miss")
    }

    /// TEST D: underperforming — hitting failure before the bottom of the
    /// rep range — must hold rather than advance load.
    func testD_UnderperformingBelowRangeHoldsRatherThanAdvancing() throws {
        let (session, profile) = makeLowerA()
        let block = try XCTUnwrap(session.orderedBlocks.first)
        let squat = try XCTUnwrap(block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Back Squat" })
        for setPrescription in squat.orderedSetPrescriptions {
            try logSet(for: squat, setPrescription: setPrescription, reps: setPrescription.repRangeLow - 1, actualRir: 0, performanceProfile: profile)
        }

        let summary = try CompleteSessionUseCase.complete(session, context: .partial, asOf: Date(), modelContext: context)

        let preview = try XCTUnwrap(summary.progressionPreview.first { $0.exerciseName == "Back Squat" })
        XCTAssertEqual(preview.reasonCode, .hold, "hitting failure below the bottom of the prescribed range never advances load")
    }

    /// TEST F: substituting to an exercise with no history is allowed
    /// (never blocked on missing history), and completing it gives that
    /// exercise its own usable history — the result belongs to the
    /// exercise actually performed, never the original.
    func testF_SubstitutingToAnExerciseWithNoHistoryThenCompletingItGivesThatExerciseUsableHistory() throws {
        let profile = PerformanceProfile()
        context.insert(profile)
        let user = User(displayName: "Test User")
        context.insert(user)
        user.attachPerformanceProfile(profile)

        let catalog = ExerciseCatalog.makeAndInsert(context: context)
        let day = Day(ownerUserID: ownerUserID, date: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(day)
        let fixture = SeedScenarios.materializedLowerASession(day: day, catalog: catalog, ownerUserID: ownerUserID, modelContext: context)

        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        let legPressMovement = try XCTUnwrap(block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Leg Press" })
        let slot = try XCTUnwrap(legPressMovement.sourceExerciseSlot)

        XCTAssertNil(profile.profile(for: catalog.bulgarianSplitSquat), "no history yet — this is the precondition this test exercises")

        try ApplySubstitutionUseCase.substituteExerciseThisSessionOnly(
            prescription: legPressMovement, slot: slot, with: catalog.bulgarianSplitSquat, modelContext: context
        )
        XCTAssertEqual(legPressMovement.exercise?.canonicalName, "Bulgarian Split Squat", "substitution succeeded despite no history — never blocked")

        for setPrescription in legPressMovement.orderedSetPrescriptions {
            try logSet(for: legPressMovement, setPrescription: setPrescription, reps: setPrescription.repRangeHigh, actualRir: setPrescription.targetRir, performanceProfile: profile)
        }

        let exerciseProfile = try XCTUnwrap(profile.profile(for: catalog.bulgarianSplitSquat), "completing the substituted exercise must create usable history for it")
        XCTAssertFalse(exerciseProfile.setResults.isEmpty)
        XCTAssertTrue(exerciseProfile.setResults.allSatisfy { $0.exercisePrescription?.exercise?.canonicalName == "Bulgarian Split Squat" }, "the result belongs to the exercise actually performed")
    }
}
