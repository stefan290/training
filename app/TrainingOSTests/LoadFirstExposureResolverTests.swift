import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 10R.5: proves `LoadFirstExposureResolver`'s exclusion/scoping
/// rules — deload, readiness-adapted, incomplete/missing exposures are
/// all invisible to the streak, never counted as either success or
/// failure (D-10R5-10/11/14); evidence is exercise-specific and
/// instance-scoped (D-10R5-12/13).
@MainActor
final class LoadFirstExposureResolverTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func makeInstance() -> ProgramInstance {
        let instance = ProgramInstance(ownerUserID: ownerUserID, startDate: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(instance)
        return instance
    }

    private func makeExercise(_ name: String = "Barbell Bench Press") -> Exercise {
        let exercise = Exercise(canonicalName: name, modality: .strength, equipment: "barbell", movementPattern: "press", primaryTargets: [.chest])
        context.insert(exercise)
        return exercise
    }

    /// One real exposure — one `ExercisePrescription` with `setCount`
    /// sets, each logged at `actualRir`, materialized `daysAfterStart`
    /// days after `instance.startDate`.
    @discardableResult
    private func makeExposure(
        for exercise: Exercise, in instance: ProgramInstance, daysAfterStart: Int,
        targetRir: Int = 3, actualRirPerSet: [Int?], targetWeight: Double = 90,
        deload: Bool = false, readinessAccepted: Bool = false
    ) -> ExercisePrescription {
        let date = Calendar.current.date(byAdding: .day, value: daysAfterStart, to: instance.startDate) ?? instance.startDate
        let day = Day(ownerUserID: ownerUserID, date: date)
        context.insert(day)
        let session = Session(name: "Session", modality: .strength, status: .completed)
        context.insert(session)
        day.addSession(session)
        instance.addSession(session)

        let block = WorkoutBlock(type: .hypertrophy)
        context.insert(block)
        session.addBlock(block)

        let prescription = ExercisePrescription(exercise: exercise)
        context.insert(prescription)
        if deload {
            prescription.appliedLoadReasonCode = .deloadWeightPrescribed
        }
        block.addPrescription(prescription)

        for actualRir in actualRirPerSet {
            let setPrescription = SetPrescription(targetWeight: targetWeight, targetRir: targetRir)
            context.insert(setPrescription)
            prescription.addSetPrescription(setPrescription)
            if let actualRir {
                let result = SetResult(setIndex: 0, weight: targetWeight, reps: 8, targetRir: targetRir, actualRir: actualRir)
                context.insert(result)
                setPrescription.addResult(result)
                prescription.addLoggedSetResult(result)
            }
        }

        if readinessAccepted {
            let decision = ReadinessAdaptationDecision(
                decidedAt: date, triggeringSignals: [.poorSleep], actionKind: .noChangeConfirmed,
                userResponse: .accepted, explanation: "test fixture", exercisePrescription: prescription
            )
            context.insert(decision)
            prescription.readinessAdaptationDecisions.append(decision)
        }

        return prescription
    }

    // MARK: 6/7/8 — skipped/missed/abandoned = no evidence (no logged SetResult at all)

    func testExposureWithNoLoggedResultsIsInvisibleToTheResolver() {
        let instance = makeInstance()
        let exercise = makeExercise()
        let current = makeExposure(for: exercise, in: instance, daysAfterStart: 7, actualRirPerSet: [nil, nil, nil])
        let exposures = LoadFirstExposureResolver.recentEligibleExposures(for: exercise, in: instance, excluding: current, limit: 2)
        XCTAssertTrue(exposures.isEmpty, "no actual RIR logged for any set — never fabricated as either easy or hard")
    }

    func testPartiallyLoggedExposureIsAlsoInvisible() {
        let instance = makeInstance()
        let exercise = makeExercise()
        let current = makeExposure(for: exercise, in: instance, daysAfterStart: 14, actualRirPerSet: [nil])
        makeExposure(for: exercise, in: instance, daysAfterStart: 7, actualRirPerSet: [3, nil, 3])
        let exposures = LoadFirstExposureResolver.recentEligibleExposures(for: exercise, in: instance, excluding: current, limit: 2)
        XCTAssertTrue(exposures.isEmpty, "an incomplete exposure (one valid set missing its actual RIR) is ineligible entirely, never partially counted")
    }

    // MARK: 9 — readiness-adapted exposure excluded

    func testReadinessAdaptedExposureIsExcluded() {
        let instance = makeInstance()
        let exercise = makeExercise()
        let current = makeExposure(for: exercise, in: instance, daysAfterStart: 14, actualRirPerSet: [nil])
        makeExposure(for: exercise, in: instance, daysAfterStart: 7, actualRirPerSet: [5, 5, 5], readinessAccepted: true)
        let exposures = LoadFirstExposureResolver.recentEligibleExposures(for: exercise, in: instance, excluding: current, limit: 2)
        XCTAssertTrue(exposures.isEmpty, "an accepted readiness adaptation must never create a false easy (or hard) signal")
    }

    // MARK: 10/11 — deload exposure excluded, and can never leak forward

    func testDeloadExposureIsExcluded() {
        let instance = makeInstance()
        let exercise = makeExercise()
        let current = makeExposure(for: exercise, in: instance, daysAfterStart: 14, actualRirPerSet: [nil])
        makeExposure(for: exercise, in: instance, daysAfterStart: 7, actualRirPerSet: [5, 5, 5], deload: true)
        let exposures = LoadFirstExposureResolver.recentEligibleExposures(for: exercise, in: instance, excluding: current, limit: 2)
        XCTAssertTrue(exposures.isEmpty, "a deload week's deliberately-easy performance must never read as 'load too light' for a future week")
    }

    // MARK: 12 — substitution resets evidence (different exercise = zero shared history)

    func testDifferentExerciseHasNoSharedEvidence() {
        let instance = makeInstance()
        let benchPress = makeExercise("Barbell Bench Press")
        let dumbbellPress = makeExercise("Dumbbell Bench Press")
        makeExposure(for: benchPress, in: instance, daysAfterStart: 7, actualRirPerSet: [5, 5, 5])
        let current = makeExposure(for: dumbbellPress, in: instance, daysAfterStart: 14, actualRirPerSet: [nil])
        let exposures = LoadFirstExposureResolver.recentEligibleExposures(for: dumbbellPress, in: instance, excluding: current, limit: 2)
        XCTAssertTrue(exposures.isEmpty, "Bench Press's real easy history must never transfer to Dumbbell Bench Press")
    }

    // MARK: 13 — new ProgramInstance resets active evidence

    func testDifferentProgramInstanceHasNoSharedEvidence() {
        let firstInstance = makeInstance()
        let secondInstance = makeInstance()
        let exercise = makeExercise()
        makeExposure(for: exercise, in: firstInstance, daysAfterStart: 7, actualRirPerSet: [5, 5, 5])
        let current = makeExposure(for: exercise, in: secondInstance, daysAfterStart: 0, actualRirPerSet: [nil])
        let exposures = LoadFirstExposureResolver.recentEligibleExposures(for: exercise, in: secondInstance, excluding: current, limit: 2)
        XCTAssertTrue(exposures.isEmpty, "a new mesocycle's ProgramInstance must never inherit the previous instance's evidence")
    }

    // MARK: Real, eligible history is found correctly, most-recent-first

    func testRealEligibleHistoryIsOrderedMostRecentFirst() {
        let instance = makeInstance()
        let exercise = makeExercise()
        // targetRir defaults to 3 — actual RIR 3 -> surplus 0; actual RIR 5 -> surplus +2.
        makeExposure(for: exercise, in: instance, daysAfterStart: 0, actualRirPerSet: [3, 3, 3])
        makeExposure(for: exercise, in: instance, daysAfterStart: 7, actualRirPerSet: [5, 5, 5])
        let current = makeExposure(for: exercise, in: instance, daysAfterStart: 14, actualRirPerSet: [nil])

        let exposures = LoadFirstExposureResolver.recentEligibleExposures(for: exercise, in: instance, excluding: current, limit: 2)
        XCTAssertEqual(exposures.count, 2)
        XCTAssertEqual(exposures[0].setSurpluses, [2, 2, 2], "most recent (day 7) first")
        XCTAssertEqual(exposures[1].setSurpluses, [0, 0, 0], "day 0 second")
    }

    /// Test 19 (resolver half): identical persisted state always
    /// produces an identical resolved exposure list.
    func testResolverIsDeterministicAcrossRepeatedCalls() {
        let instance = makeInstance()
        let exercise = makeExercise()
        makeExposure(for: exercise, in: instance, daysAfterStart: 7, actualRirPerSet: [2, 2, 2])
        let current = makeExposure(for: exercise, in: instance, daysAfterStart: 14, actualRirPerSet: [nil])

        let first = LoadFirstExposureResolver.recentEligibleExposures(for: exercise, in: instance, excluding: current, limit: 2)
        let second = LoadFirstExposureResolver.recentEligibleExposures(for: exercise, in: instance, excluding: current, limit: 2)
        XCTAssertEqual(first.map(\.setSurpluses), second.map(\.setSurpluses))
        XCTAssertEqual(first.map(\.effectiveWeightUsed), second.map(\.effectiveWeightUsed))
    }
}
