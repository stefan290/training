import XCTest
import SwiftData
@testable import TrainingOS

/// Running R2.3/R2.4, Testing G/H/I: representation tests only — these
/// prove the EXISTING `SteadyStatePrescription`/`IntervalPrescription`/
/// `WorkoutBlock` architecture (extended only with the two additive
/// `sourceLabel`/`executionNotes` fields) can express every structurally
/// distinct observed session shape from `RUNNING_PROGRAMMING_MODEL_R1.md`
/// §5 without loss. NOT a generator: every fixture below is hand-built
/// from the report's own cited source facts, never produced by program
/// logic.
@MainActor
final class RunningPrescriptionRepresentationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func makeSession(name: String) -> Session {
        let session = Session(name: name, modality: .conditioning)
        context.insert(session)
        return session
    }

    // MARK: Golden fixture 1 — early simple Tempo/Active structure (relative weeks 1-3)

    func testEarlySimpleTempoActiveStructureIsRepresentable() throws {
        let session = makeSession(name: "Relative Week 1 — Slot A")
        let warmup = WorkoutBlock(type: .steadyState)
        session.addBlock(warmup)
        let warmupPrescription = SteadyStatePrescription(activityType: .running, distanceMeters: 800, sourceLabel: .warmUp)
        warmup.attachSteadyStatePrescription(warmupPrescription)

        let tempo = WorkoutBlock(type: .steadyState)
        session.addBlock(tempo)
        let tempoPrescription = SteadyStatePrescription(
            activityType: .running, distanceMeters: 1600,
            primaryIntensity: .percentOfReference(BoundedRange(lower: 0.95, upper: 0.95), metric: .thresholdPace),
            sourceLabel: .tempo
        )
        tempo.attachSteadyStatePrescription(tempoPrescription)

        let easy = WorkoutBlock(type: .steadyState)
        session.addBlock(easy)
        easy.attachSteadyStatePrescription(SteadyStatePrescription(activityType: .running, distanceMeters: 800, sourceLabel: .easy))

        try context.save()
        // `session.blocks` (a SwiftData to-many relationship array) is not
        // guaranteed insertion-ordered — `sortIndex` (assigned by
        // `Session.addBlock`) is the actual ordering signal, per that
        // property's own doc comment.
        XCTAssertEqual(session.blocks.sorted { $0.sortIndex < $1.sortIndex }.map(\.sortIndex), [0, 1, 2])
        XCTAssertEqual(warmup.steadyStatePrescription?.sourceLabel, .warmUp)
        XCTAssertEqual(tempo.steadyStatePrescription?.sourceLabel, .tempo)
        XCTAssertEqual(easy.steadyStatePrescription?.sourceLabel, .easy)
    }

    // MARK: G — a single repeat-group prescription (4-repeat Hard/Easy, relative week 9)

    func testFourRepeatHardEasyRepeatGroupIsRepresentable() throws {
        let session = makeSession(name: "Relative Week 9 — Slot A")
        let block = WorkoutBlock(type: .intervals)
        session.addBlock(block)
        let prescription = IntervalPrescription(
            activityType: .running,
            intervalCount: 4,
            workDistanceMeters: 400,
            workIntensity: .percentOfReference(BoundedRange(lower: 1.0, upper: 1.0), metric: .thresholdPace),
            recoveryDistanceMeters: 400,
            recoveryIntensity: .percentOfReference(BoundedRange(lower: 0.75, upper: 0.75), metric: .thresholdPace),
            sourceLabel: .hard
        )
        block.attachIntervalPrescription(prescription)
        try context.save()

        XCTAssertEqual(block.intervalPrescription?.intervalCount, 4)
        XCTAssertEqual(block.intervalPrescription?.sourceLabel, .hard)
    }

    // MARK: H — multi-repeat-group session (relative week 11, 3 distinct repeat groups)
    //
    // R1 §5 relative week 11 Slot A: a faster/shorter interval group, a
    // single longer "Hard" rep, and a 2-repeat 800m Hard/400m Easy group —
    // three structurally distinct repeat groups in one session. Reused,
    // ordered `.intervals` `WorkoutBlock`s (via `Session.addBlock`'s
    // existing `sortIndex` assignment) represent this without any new
    // "repeat group container" type — confirmed sufficient; no
    // interleaving requirement was found in the source data that a linear
    /// block list could not express.
    func testMultiRepeatGroupSessionIsRepresentableAsOrderedIntervalBlocks() throws {
        let session = makeSession(name: "Relative Week 11 — Slot A")

        let group1 = WorkoutBlock(type: .intervals)
        session.addBlock(group1)
        group1.attachIntervalPrescription(IntervalPrescription(
            activityType: .running, intervalCount: 6, workDistanceMeters: 200,
            workIntensity: .percentOfReference(BoundedRange(lower: 1.0989, upper: 1.0989), metric: .thresholdPace),
            recoveryDistanceMeters: 200, sourceLabel: .hard
        ))

        let group2 = WorkoutBlock(type: .intervals)
        session.addBlock(group2)
        group2.attachIntervalPrescription(IntervalPrescription(
            activityType: .running, intervalCount: 1, workDistanceMeters: 2.0 * 1609.34,
            workIntensity: .percentOfReference(BoundedRange(lower: 0.9494, upper: 0.9494), metric: .thresholdPace),
            sourceLabel: .hard
        ))

        let group3 = WorkoutBlock(type: .intervals)
        session.addBlock(group3)
        group3.attachIntervalPrescription(IntervalPrescription(
            activityType: .running, intervalCount: 2, workDistanceMeters: 800,
            workIntensity: .percentOfReference(BoundedRange(lower: 1.0490, upper: 1.0490), metric: .thresholdPace),
            recoveryDistanceMeters: 400, sourceLabel: .hard
        ))

        try context.save()

        XCTAssertEqual(session.blocks.count, 3)
        XCTAssertEqual(session.blocks.sorted { $0.sortIndex < $1.sortIndex }.map { $0.intervalPrescription?.intervalCount }, [6, 1, 2])
    }

    // MARK: 6-repeat structure (relative week 10)

    func testSixRepeatStructureIsRepresentable() throws {
        let session = makeSession(name: "Relative Week 10 — Slot A")
        let block = WorkoutBlock(type: .intervals)
        session.addBlock(block)
        block.attachIntervalPrescription(IntervalPrescription(
            activityType: .running, intervalCount: 6, workDistanceMeters: 300,
            workIntensity: .percentOfReference(BoundedRange(lower: 1.0, upper: 1.0), metric: .thresholdPace),
            recoveryDistanceMeters: 300, sourceLabel: .hard
        ))
        try context.save()
        XCTAssertEqual(block.intervalPrescription?.intervalCount, 6)
    }

    // MARK: Taper single-rep structure (relative week 12)

    func testTaperSingleRepStructureIsRepresentable() throws {
        let session = makeSession(name: "Relative Week 12 — Slot A")
        let block = WorkoutBlock(type: .intervals)
        session.addBlock(block)
        block.attachIntervalPrescription(IntervalPrescription(
            activityType: .running, intervalCount: 1, workDistanceMeters: 800,
            workIntensity: .percentOfReference(BoundedRange(lower: 1.0989, upper: 1.0989), metric: .thresholdPace),
            sourceLabel: .hard
        ))
        try context.save()
        XCTAssertEqual(block.intervalPrescription?.intervalCount, 1)
        XCTAssertEqual(block.intervalPrescription?.workIntensity, .percentOfReference(BoundedRange(lower: 1.0989, upper: 1.0989), metric: .thresholdPace))
    }

    // MARK: I — RPE-only prescription (race week, relative week 13)

    func testRPEOnlyRacePrescriptionIsRepresentableWithoutAnyPercentThreshold() throws {
        let session = makeSession(name: "Relative Week 13 — Race")

        let warmup = WorkoutBlock(type: .steadyState)
        session.addBlock(warmup)
        warmup.attachSteadyStatePrescription(SteadyStatePrescription(
            activityType: .running, distanceMeters: 500,
            primaryIntensity: .rpe(BoundedRange(lower: 3, upper: 3)),
            sourceLabel: .warmUpEasyWalkSlowJog
        ))

        let race = WorkoutBlock(type: .steadyState)
        session.addBlock(race)
        race.attachSteadyStatePrescription(SteadyStatePrescription(
            activityType: .running, distanceMeters: 5000,
            primaryIntensity: .rpe(BoundedRange(lower: 6, upper: 6)),
            sourceLabel: .active,
            executionNotes: "Start conservatively; pick up effort ~1.5 mi; if strong at mile 2, increase effort to finish."
        ))
        try context.save()

        XCTAssertEqual(race.steadyStatePrescription?.primaryIntensity, .rpe(BoundedRange(lower: 6, upper: 6)))
        if case .rpe = race.steadyStatePrescription!.primaryIntensity! {} else { XCTFail("race block must be RPE-only, never %threshold") }
        XCTAssertEqual(race.steadyStatePrescription?.executionNotes, "Start conservatively; pick up effort ~1.5 mi; if strong at mile 2, increase effort to finish.")
    }

    // MARK: Regression — source labels survive representation unchanged

    func testSourceLabelsSurviveRoundTripThroughPersistenceUnchanged() throws {
        let session = makeSession(name: "Round-trip check")
        let block = WorkoutBlock(type: .steadyState)
        session.addBlock(block)
        block.attachSteadyStatePrescription(SteadyStatePrescription(activityType: .running, sourceLabel: .coolDown))
        try context.save()

        let freshContext = ModelContext(container)
        let fetched = try freshContext.fetch(FetchDescriptor<SteadyStatePrescription>())
        XCTAssertTrue(fetched.contains { $0.sourceLabel == .coolDown })
    }

    func testEveryObservedSourceLabelIsRepresentableAndNoUnsupportedPhysiologicalLabelExists() {
        // RunningSourceLabel's case set is exactly RP's own 8 observed
        // labels (R1 §7, corrected during R3 implementation to add
        // "Recovery" — a real, distinct `Source Label` value found by
        // direct re-inspection of all 145 `Workout Blocks` rows, missed
        // by R1's representative-week prose) — this test is a
        // compile-time-adjacent guarantee via CaseIterable: if a future
        // edit added "vo2max"/"threshold"/"base"/"longRun" as a case,
        // this count would change, making the regression visible.
        XCTAssertEqual(RunningSourceLabel.allCases.count, 8)
        XCTAssertEqual(Set(RunningSourceLabel.allCases.map(\.rawValue)), [
            "warmUp", "tempo", "active", "easy", "hard", "coolDown", "warmUpEasyWalkSlowJog", "recovery",
        ])
    }
}
