import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 6E: a completed Session must remain inspectable — never routed
/// back into a live execution view, never mutated by being viewed. Tests
/// the pure routing logic (`SessionDisplayMode`) and the data shape every
/// completed-history view reads, mirroring the established convention in
/// this codebase of testing the data/logic layer rather than rendering
/// SwiftUI views directly (`SessionPreviewContent` itself has no
/// dedicated view-rendering test file either).
@MainActor
final class CompletedSessionHistoryTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func makeUserWithPerformanceProfile() -> PerformanceProfile {
        let profile = PerformanceProfile()
        context.insert(profile)
        let user = User(displayName: "Test User")
        context.insert(user)
        user.attachPerformanceProfile(profile)
        return profile
    }

    private func makeLowerA() -> (session: Session, catalog: ExerciseCatalog, performanceProfile: PerformanceProfile) {
        let performanceProfile = makeUserWithPerformanceProfile()
        let catalog = ExerciseCatalog.makeAndInsert(context: context)
        let day = Day(ownerUserID: ownerUserID, date: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(day)
        let fixture = SeedScenarios.materializedLowerASession(day: day, catalog: catalog, ownerUserID: ownerUserID, modelContext: context)
        return (fixture.session, catalog, performanceProfile)
    }

    private func logSet(_ setPrescription: SetPrescription, reps: Int, actualRir: Int?, movement: ExercisePrescription, performanceProfile: PerformanceProfile) throws {
        try LogSetUseCase.logSet(
            setIndex: movement.loggedSetResults.count, weight: setPrescription.targetWeight ?? 20, reps: reps,
            targetRir: setPrescription.targetRir, actualRir: actualRir, prBand: "\(setPrescription.repRangeLow)-\(setPrescription.repRangeHigh)",
            scoringDirection: .higherIsBetter, context: .rx, setPrescription: setPrescription,
            exercisePrescription: movement, exercise: movement.exercise!, performanceProfile: performanceProfile,
            completedAt: Date(), modelContext: context
        )
    }

    // MARK: A/O — routing

    func testCompletedSkippedMissedAndAbandonedAlwaysRouteToCompletedHistoryRegardlessOfReadOnly() {
        for status: SessionStatus in [.completed, .skipped, .missed, .abandoned] {
            XCTAssertEqual(SessionDisplayMode.mode(for: status, readOnly: false), .completedHistory)
            XCTAssertEqual(SessionDisplayMode.mode(for: status, readOnly: true), .completedHistory)
        }
    }

    func testInProgressAlwaysRoutesToExecutionRegardlessOfReadOnly() {
        XCTAssertEqual(SessionDisplayMode.mode(for: .inProgress, readOnly: false), .execution)
        XCTAssertEqual(SessionDisplayMode.mode(for: .inProgress, readOnly: true), .execution)
    }

    func testScheduledRoutesToExecutionWhenNotReadOnlyAndFuturePreviewWhenReadOnly() {
        XCTAssertEqual(SessionDisplayMode.mode(for: .scheduled, readOnly: false), .execution)
        XCTAssertEqual(SessionDisplayMode.mode(for: .scheduled, readOnly: true), .futurePreview)
    }

    // MARK: B/H/I/J — opening history never mutates anything

    func testReadingCompletedSessionDataRepeatedlyNeverMutatesStatusOrDuplicatesResults() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        for movement in block.orderedPrescriptions {
            for setPrescription in movement.orderedSetPrescriptions {
                try logSet(setPrescription, reps: setPrescription.repRangeHigh, actualRir: setPrescription.targetRir, movement: movement, performanceProfile: fixture.performanceProfile)
            }
        }
        try CompleteSessionUseCase.complete(fixture.session, context: .full, asOf: Date(), modelContext: context)

        let statusBefore = fixture.session.status
        let completedAtBefore = fixture.session.completedAt
        let setResultCountBefore = try context.fetchCount(FetchDescriptor<SetResult>())
        let personalRecordCountBefore = try context.fetchCount(FetchDescriptor<PersonalRecord>())
        let squat = try XCTUnwrap(block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Back Squat" })
        let profile = try XCTUnwrap(fixture.performanceProfile.profile(for: squat.exercise!))
        let lastPerformedAtBefore = profile.lastPerformedAt

        // Exercise every pure read completed history performs, repeatedly.
        for _ in 0..<3 {
            _ = SessionDisplayMode.mode(for: fixture.session.status, readOnly: false)
            _ = CompleteSessionUseCase.progressionPreview(for: fixture.session, userProfile: nil)
            for b in fixture.session.orderedBlocks {
                _ = b.blockPrescription
                _ = b.blockResult
            }
        }

        XCTAssertEqual(fixture.session.status, statusBefore)
        XCTAssertEqual(fixture.session.completedAt, completedAtBefore)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetResult>()), setResultCountBefore, "no SetResult duplicated by re-reading history")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PersonalRecord>()), personalRecordCountBefore, "no PersonalRecord re-created by re-reading history")
        XCTAssertEqual(profile.lastPerformedAt, lastPerformedAtBefore, "PerformanceProfile untouched by re-reading history")
    }

    // MARK: C/D/E — strength completed detail data shape

    func testCompletedStrengthDetailDataExposesEveryExerciseWithDistinguishablePrescribedAndPerformed() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        XCTAssertEqual(block.orderedPrescriptions.count, 5, "every exercise remains present")

        let squat = try XCTUnwrap(block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Back Squat" })
        let setPrescription = try XCTUnwrap(squat.orderedSetPrescriptions.first)
        // Outperform the prescription so prescribed and performed clearly differ.
        try logSet(setPrescription, reps: setPrescription.repRangeHigh + 2, actualRir: (setPrescription.targetRir ?? 0) + 2, movement: squat, performanceProfile: fixture.performanceProfile)

        let result = try XCTUnwrap(squat.loggedSetResults.first)
        XCTAssertNotEqual(result.reps, setPrescription.repRangeHigh, "performed reps stay distinguishable from the prescribed target")
        XCTAssertEqual(result.setIndex, 0)
        XCTAssertEqual(result.weight, setPrescription.targetWeight)
        XCTAssertNotNil(setPrescription.targetRir)
        XCTAssertNotNil(result.actualRir)
    }

    // MARK: F — substitution prescribed vs performed

    func testSubstitutedExerciseExposesBothOriginallyPrescribedAndPerformedIdentity() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        let legPressMovement = try XCTUnwrap(block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Leg Press" })
        let slot = try XCTUnwrap(legPressMovement.sourceExerciseSlot)

        try ApplySubstitutionUseCase.substituteExerciseThisSessionOnly(
            prescription: legPressMovement, slot: slot, with: fixture.catalog.bulgarianSplitSquat, modelContext: context
        )

        XCTAssertTrue(legPressMovement.substitutionUsed)
        XCTAssertEqual(legPressMovement.exercise?.canonicalName, "Bulgarian Split Squat", "performed identity")
        XCTAssertEqual(legPressMovement.sourceExerciseSlot?.resolvedExercise?.canonicalName, "Leg Press", "originally prescribed identity remains reconstructable")
    }

    // MARK: G — autoregulation feedback remains inspectable

    func testAutoregulationFeedbackAndSetCountReasonRemainInspectableAfterCompletion() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        for movement in block.orderedPrescriptions {
            for setPrescription in movement.orderedSetPrescriptions {
                try logSet(setPrescription, reps: setPrescription.repRangeHigh, actualRir: setPrescription.targetRir, movement: movement, performanceProfile: fixture.performanceProfile)
            }
        }
        let legPress = try XCTUnwrap(block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Leg Press" })
        try RecordAutoregulationFeedbackUseCase.recordRating(1, for: legPress, modelContext: context)
        try CompleteSessionUseCase.complete(fixture.session, context: .full, asOf: Date(), modelContext: context)

        XCTAssertEqual(legPress.autoregulationRating, 1)
        let system = HypertrophyFeedbackCopy.programmingSystem(for: legPress)
        let label = HypertrophyFeedbackCopy.label(forRating: 1, system: system)
        XCTAssertNotNil(label, "the exact copy the user was shown remains reconstructable from the raw rating")
        XCTAssertFalse(label!.isEmpty)

        let squat = try XCTUnwrap(block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Back Squat" })
        XCTAssertNotNil(squat.appliedSetCountReasonCode, "the reason THIS week's own set count is what it is remains persisted")
    }

    func testStrengthReasonCodePresentationOnlyProducesTextForAutoregulationCases() {
        XCTAssertNotNil(StrengthReasonCodePresentation.setCountReasonText(.autoregulatedSetIncrease))
        XCTAssertNotNil(StrengthReasonCodePresentation.setCountReasonText(.autoregulatedSetHold))
        XCTAssertNotNil(StrengthReasonCodePresentation.setCountReasonText(.autoregulatedSetDecrease))
        XCTAssertNil(StrengthReasonCodePresentation.setCountReasonText(.fixedSetSchedule), "nothing autoregulation-specific happened — nothing invented to say about it")
        XCTAssertNil(StrengthReasonCodePresentation.setCountReasonText(.calibrationRequired))
    }

    // MARK: K — partial history is inspectable

    func testPartiallyCompletedSessionRemainsInspectableWithSkippedAndCompletedBlocksDistinguishable() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        let squat = try XCTUnwrap(block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Back Squat" })
        // Only log the first exercise — the rest are left incomplete.
        for setPrescription in squat.orderedSetPrescriptions {
            try logSet(setPrescription, reps: setPrescription.repRangeHigh, actualRir: setPrescription.targetRir, movement: squat, performanceProfile: fixture.performanceProfile)
        }

        let summary = try CompleteSessionUseCase.complete(fixture.session, context: .partial, asOf: Date(), modelContext: context)

        XCTAssertEqual(SessionDisplayMode.mode(for: fixture.session.status, readOnly: false), .completedHistory)
        XCTAssertEqual(summary.completionContext, .partial)
        XCTAssertFalse(squat.loggedSetResults.isEmpty, "the exercise that was done stays inspectable")
        let legCurl = try XCTUnwrap(block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Leg Curl" })
        XCTAssertTrue(legCurl.loggedSetResults.isEmpty, "the exercise that was skipped is distinguishably incomplete, not silently hidden")
    }

    // MARK: L — completed Steady State detail data shape

    func testCompletedSteadyStateResultExposesActualMetricsAlongsidePrescription() throws {
        let profile = PerformanceProfile()
        context.insert(profile)
        let block = WorkoutBlock(type: .steadyState, status: .completed)
        context.insert(block)

        let result = SteadyStateResult(
            actualDurationSeconds: 2_700, actualDistanceMeters: 8_000,
            averageHeartRate: 148, averagePower: 210, averagePaceSecondsPerKilometer: 337, rpe: 6
        )
        try LogEnduranceResultUseCase.logSteadyStateResult(
            result, for: block, activityType: .running, prCandidateValue: nil,
            scoringDirection: .lowerIsBetter, performanceProfile: profile, modelContext: context
        )

        let stored = try XCTUnwrap(block.steadyStateResult)
        XCTAssertEqual(stored.actualDurationSeconds, 2_700)
        XCTAssertEqual(stored.actualDistanceMeters, 8_000)
        XCTAssertEqual(stored.averageHeartRate, 148)
        XCTAssertEqual(stored.averagePower, 210)
        XCTAssertEqual(stored.averagePaceSecondsPerKilometer, 337)
        XCTAssertEqual(stored.rpe, 6)
        XCTAssertEqual(IntensityPresentation.paceLabel(secondsPerKilometer: 337), "5:37")
    }

    // MARK: M — completed Interval per-rep detail data shape

    func testCompletedIntervalResultExposesEveryPerRepResultIncludingIncompleteOnes() throws {
        let profile = PerformanceProfile()
        context.insert(profile)
        let block = WorkoutBlock(type: .intervals, status: .completed)
        context.insert(block)

        let result = IntervalResult(sessionDurationSeconds: 1_500, averageHeartRate: 165, rpe: 8)
        let rep1 = IntervalRepResult(actualWorkDurationSeconds: 240, wasCompletedAsPrescribed: true)
        let rep2 = IntervalRepResult(actualWorkDurationSeconds: 220, wasCompletedAsPrescribed: false)
        result.addRepResult(rep1)
        result.addRepResult(rep2)

        try LogEnduranceResultUseCase.logIntervalResult(
            result, for: block, activityType: .rowing, prCandidateValue: nil,
            scoringDirection: .lowerIsBetter, performanceProfile: profile, modelContext: context
        )

        let stored = try XCTUnwrap(block.intervalResult)
        XCTAssertEqual(stored.orderedRepResults.count, 2, "per-rep detail is never collapsed")
        XCTAssertTrue(stored.orderedRepResults[0].wasCompletedAsPrescribed)
        XCTAssertFalse(stored.orderedRepResults[1].wasCompletedAsPrescribed, "an incomplete interval stays distinguishable")
        XCTAssertEqual(stored.averageHeartRate, 165)
    }

    // MARK: N — completed Functional Fitness score/scaling data shape

    func testCompletedFunctionalFitnessResultExposesScoreContextAndScaling() throws {
        let profile = PerformanceProfile()
        context.insert(profile)
        let catalog = ExerciseCatalog.makeAndInsert(context: context)
        let block = WorkoutBlock(type: .functionalFitness, status: .completed)
        context.insert(block)

        let prescribedMovement = FunctionalFitnessMovement(exercise: catalog.backSquat, reps: 21)
        context.insert(prescribedMovement)

        let result = FunctionalFitnessResult(scoreType: .time, scoreValue: .time(seconds: 302), scoreDirection: .lowerIsBetter, resultContext: .scaled)
        let performed = FunctionalFitnessPerformedMovement(prescribedMovement: prescribedMovement, performedExercise: catalog.legPress, performedReps: 21)
        context.insert(performed)
        result.addPerformedMovement(performed)

        try LogFunctionalFitnessResultUseCase.logResult(result, for: block, benchmark: nil, performanceProfile: profile, modelContext: context)

        let stored = try XCTUnwrap(block.functionalFitnessResult)
        XCTAssertEqual(stored.scoreValue, .time(seconds: 302))
        XCTAssertEqual(stored.resultContext, .scaled)
        let storedMovement = try XCTUnwrap(stored.orderedPerformedMovements.first)
        XCTAssertEqual(storedMovement.prescribedMovement?.exercise?.canonicalName, "Back Squat", "the original prescription is preserved, never overwritten")
        XCTAssertEqual(storedMovement.performedExercise?.canonicalName, "Leg Press", "the scaled substitution is recorded alongside it")
    }

    // MARK: PR first-vs-genuine reconstruction

    func testFirstEverEntryIsDerivedCorrectlyFromPersistedPersonalRecordsAfterTheFact() throws {
        let fixture = makeLowerA()
        let block = try XCTUnwrap(fixture.session.orderedBlocks.first)
        let squat = try XCTUnwrap(block.orderedPrescriptions.first { $0.exercise?.canonicalName == "Back Squat" })
        let sets = squat.orderedSetPrescriptions

        try logSet(sets[0], reps: sets[0].repRangeHigh, actualRir: sets[0].targetRir, movement: squat, performanceProfile: fixture.performanceProfile)
        let profile = try XCTUnwrap(fixture.performanceProfile.profile(for: squat.exercise!))
        let firstRecord = try XCTUnwrap(profile.personalRecords.first)
        XCTAssertTrue(CompletedResultPresentation.isFirstEverEntry(firstRecord, in: profile))

        // A genuinely heavier set in the same rep band is a real improvement, not a first-ever entry.
        let heavierWeight = (sets[1].targetWeight ?? 20) + 10
        try LogSetUseCase.logSet(
            setIndex: 1, weight: heavierWeight, reps: sets[1].repRangeHigh, targetRir: sets[1].targetRir,
            actualRir: sets[1].targetRir, prBand: "\(sets[1].repRangeLow)-\(sets[1].repRangeHigh)",
            scoringDirection: .higherIsBetter, context: .rx, setPrescription: sets[1],
            exercisePrescription: squat, exercise: squat.exercise!, performanceProfile: fixture.performanceProfile,
            completedAt: Date(), modelContext: context
        )
        let secondRecord = try XCTUnwrap(profile.personalRecords.first { $0.id != firstRecord.id })
        XCTAssertFalse(CompletedResultPresentation.isFirstEverEntry(secondRecord, in: profile))
    }
}
