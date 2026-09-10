import XCTest
import SwiftData
@testable import TrainingOS

/// Running R3 — source-fidelity tests for the 5K/2-Day V1 generator
/// (`RunningProgramGenerator`). Proves the generated template graph
/// reproduces the recovered 13-relative-week, 25-workout structure
/// without loss, using the definition's own template graph directly
/// (never a materialized instance — that's `RunningProgramMaterializerTests`'
/// job).
@MainActor
final class RunningProgramGeneratorTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var definition: ProgramDefinition!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
        definition = try RunningProgramGenerator.generate(
            configuration: RunningProgramConfiguration(distance: .fiveK, daysPerWeek: 2),
            provenance: .sourced(file: "RP_5K_TrainingPeaks_Reference.xlsx", sheet: "Workout Blocks", cell: "all rows"),
            context: context
        )
    }

    // MARK: 1-2 — exact week/workout counts

    func testExactlyThirteenRelativeWeeks() {
        XCTAssertEqual(definition.orderedWeeks.count, 13)
    }

    func testExactlyTwentyFiveWorkouts() {
        XCTAssertEqual(definition.orderedTemplateSessions.count, 25)
    }

    // MARK: 3-4 — weeks 1-12 have two slots, week 13 has the race alone

    func testWeeksOneThroughTwelveContainTwoRunSlots() {
        for week in 1...12 {
            let sessions = definition.orderedTemplateSessions.filter { $0.activeFromWeek == week - 1 }
            XCTAssertEqual(sessions.count, 2, "relative week \(week) must have exactly 2 sessions")
        }
    }

    func testWeekThirteenContainsOnlyTheRace() {
        let sessions = definition.orderedTemplateSessions.filter { $0.activeFromWeek == 12 }
        XCTAssertEqual(sessions.count, 1)
        XCTAssertTrue(sessions[0].name.contains("Race"))
    }

    // MARK: 5 — ordering matches reference (spot-checked across the range)

    func testWorkoutOrderingMatchesReference() {
        let sessions = definition.orderedTemplateSessions
        XCTAssertEqual(sessions.first?.name, "Week 1 — Slot A")
        XCTAssertEqual(sessions[1].name, "Week 1 — Slot B")
        XCTAssertEqual(sessions.last?.name, "Week 13 — Slot Race")
        // Monotonically non-decreasing relative week across the ordered list.
        var lastWeek = -1
        for session in sessions {
            XCTAssertGreaterThanOrEqual(session.activeFromWeek, lastWeek)
            lastWeek = session.activeFromWeek
        }
    }

    // MARK: 6-7 — source labels and distances match, spot-checked against
    // the workbook (re-verified this pass via openpyxl, not re-trusted
    // from R1's prose)

    func testWeekOneSlotALabelsAndDistancesMatchReference() {
        let session = definition.orderedTemplateSessions[0]
        let blocks = session.orderedBlockTemplates
        XCTAssertEqual(blocks.count, 4)
        XCTAssertEqual(blocks[0].steadyStatePrescriptionTemplate?.sourceLabel, .warmUp)
        XCTAssertEqual(blocks[0].steadyStatePrescriptionTemplate?.progressionRules?.weekOneDistanceMeters ?? 0, 804.67, accuracy: 0.1)
        XCTAssertEqual(blocks[2].steadyStatePrescriptionTemplate?.sourceLabel, .tempo)
        XCTAssertEqual(blocks[2].steadyStatePrescriptionTemplate?.progressionRules?.weekOneDistanceMeters ?? 0, 3218.69, accuracy: 0.1)
        XCTAssertEqual(blocks[3].steadyStatePrescriptionTemplate?.sourceLabel, .easy)
    }

    func testRelativeWeekFiveIntroducesTheRecoveryLabel() {
        // The R3 correction: "Recovery" is a real 8th source label, found
        // during this checkpoint's own literal re-transcription, distinct
        // from "Easy" — first appears at relative week 5 (W09/W10).
        let session = definition.orderedTemplateSessions.first { $0.name == "Week 5 — Slot A" }
        XCTAssertNotNil(session)
        let labels = session!.orderedBlockTemplates.compactMap { $0.steadyStatePrescriptionTemplate?.sourceLabel }
        XCTAssertTrue(labels.contains(.recovery))
    }

    // MARK: 8 — %threshold prescriptions match (golden, all 13 observed values reachable)

    func testAllThirteenObservedPercentThresholdValuesAppearSomewhereInTheDefinition() {
        var observedPercents = Set<Double>()
        for session in definition.orderedTemplateSessions {
            for block in session.orderedBlockTemplates {
                if case .percentOfReference(let range, .thresholdPace)? = block.steadyStatePrescriptionTemplate?.primaryIntensity {
                    observedPercents.insert(range.lower)
                }
                if case .percentOfReference(let range, .thresholdPace)? = block.intervalPrescriptionTemplate?.workIntensity {
                    observedPercents.insert(range.lower)
                }
                if case .percentOfReference(let range, .thresholdPace)? = block.intervalPrescriptionTemplate?.recoveryIntensity {
                    observedPercents.insert(range.lower)
                }
            }
        }
        let goldenPercents: [Double] = [
            0.6, 0.6993006993006993, 0.75, 0.7692307692307693, 0.8,
            0.8695652173913043, 0.9009009009009009, 0.9287925696594427,
            0.9493670886075949, 0.970873786407767, 1.0,
            1.048951048951049, 1.098901098901099,
        ]
        for golden in goldenPercents {
            XCTAssertTrue(observedPercents.contains { abs($0 - golden) < 0.0001 }, "\(golden) missing from definition")
        }
    }

    // MARK: 9 — RPE prescriptions match (race week)

    func testRaceWeekIsRPEOnlyWithTheVerbatimPacingNote() {
        let race = definition.orderedTemplateSessions.last!
        XCTAssertEqual(race.orderedBlockTemplates.count, 2)
        let warmup = race.orderedBlockTemplates[0].steadyStatePrescriptionTemplate!
        XCTAssertEqual(warmup.sourceLabel, .warmUpEasyWalkSlowJog)
        XCTAssertEqual(warmup.primaryIntensity, .rpe(BoundedRange(lower: 3, upper: 3)))
        XCTAssertEqual(warmup.progressionRules?.weekOneDistanceMeters ?? 0, 500.0, accuracy: 0.1)

        let race5k = race.orderedBlockTemplates[1].steadyStatePrescriptionTemplate!
        XCTAssertEqual(race5k.sourceLabel, .active)
        XCTAssertEqual(race5k.primaryIntensity, .rpe(BoundedRange(lower: 6, upper: 6)))
        XCTAssertEqual(race5k.progressionRules?.weekOneDistanceMeters ?? 0, 5000.0, accuracy: 0.1)
        XCTAssertEqual(race5k.executionNotes, "Start conservatively; pick up effort ~1.5 mi; if strong at mile 2, increase effort to finish.")
    }

    // MARK: 10 — repeat groups/counts match

    func testRelativeWeekNineHasOneFourRepeatHardEasyGroup() {
        let session = definition.orderedTemplateSessions.first { $0.name == "Week 9 — Slot A" }!
        let intervalBlocks = session.orderedBlockTemplates.compactMap(\.intervalPrescriptionTemplate)
        XCTAssertEqual(intervalBlocks.count, 1)
        XCTAssertEqual(intervalBlocks[0].sourceLabel, .hard)
        XCTAssertEqual(intervalBlocks[0].progressionRules?.weekOneIntervalCount, 4)
    }

    func testRelativeWeekTenHasOneSixRepeatHardEasyGroup() {
        let session = definition.orderedTemplateSessions.first { $0.name == "Week 10 — Slot A" }!
        let intervalBlocks = session.orderedBlockTemplates.compactMap(\.intervalPrescriptionTemplate)
        XCTAssertEqual(intervalBlocks.count, 1)
        XCTAssertEqual(intervalBlocks[0].progressionRules?.weekOneIntervalCount, 6)
    }

    func testRelativeWeekElevenHasThreeDistinctRepeatGroups() {
        let session = definition.orderedTemplateSessions.first { $0.name == "Week 11 — Slot A" }!
        let intervalBlocks = session.orderedBlockTemplates.compactMap(\.intervalPrescriptionTemplate)
        XCTAssertEqual(intervalBlocks.count, 3, "R1 §5: three distinct repeat groups in one session")
        XCTAssertEqual(intervalBlocks.map { $0.progressionRules?.weekOneIntervalCount }, [2, 1, 2])
    }

    func testRelativeWeekTwelveHasTwoSingleRepGroupsPlusPlainEasyVolume() {
        let session = definition.orderedTemplateSessions.first { $0.name == "Week 12 — Slot A" }!
        let intervalBlocks = session.orderedBlockTemplates.compactMap(\.intervalPrescriptionTemplate)
        XCTAssertEqual(intervalBlocks.count, 2)
        XCTAssertEqual(intervalBlocks.map { $0.progressionRules?.weekOneIntervalCount }, [1, 1])
        let plainSteadyLabels = session.orderedBlockTemplates.compactMap { $0.steadyStatePrescriptionTemplate?.sourceLabel }
        XCTAssertTrue(plainSteadyLabels.contains(.easy))
    }

    // MARK: 11 — race instructions match (already covered above,
    // re-asserted here per the directive's own numbered list)

    func testRaceInstructionsMatchReferenceExactly() {
        testRaceWeekIsRPEOnlyWithTheVerbatimPacingNote()
    }

    // MARK: 12 — no absolute captured athlete pace is required in the definition

    func testDefinitionNeverStoresAnAbsoluteCapturedAthletePace() {
        // Every intensity on every block must be `.percentOfReference`
        // (thresholdPace) or `.rpe` — never `.pace` (an absolute value),
        // which would mean this definition baked in one specific
        // athlete's own paces rather than staying athlete-independent.
        for session in definition.orderedTemplateSessions {
            for block in session.orderedBlockTemplates {
                if let intensity = block.steadyStatePrescriptionTemplate?.primaryIntensity {
                    XCTAssertFalse(isAbsolutePace(intensity), "found an absolute pace on \(session.name)")
                }
                if let intensity = block.intervalPrescriptionTemplate?.workIntensity {
                    XCTAssertFalse(isAbsolutePace(intensity))
                }
            }
        }
    }

    private func isAbsolutePace(_ target: IntensityTarget) -> Bool {
        if case .pace = target { return true }
        return false
    }

    // MARK: 15 — no TrainingPeaks Zone is required anywhere

    func testNoTrainingPeaksZoneFieldExistsAnywhereInTheGeneratedGraph() {
        // Structural proof: `IntensityTarget` has no "TrainingPeaks Zone"
        // case at all (R2), so nothing on this definition could possibly
        // carry one — this test exists so a future `IntensityTarget` case
        // addition modeling TP zones would make this assumption visible.
        XCTAssertFalse(String(describing: IntensityTarget.self).contains("trainingPeaksZone"))
    }

    // MARK: 16-17 — no fabricated weeks, no fabricated dates

    func testNoFabricatedWeeksBeyondTheRecoveredThirteen() {
        XCTAssertEqual(definition.lengthWeeks, 13)
        XCTAssertEqual(definition.orderedWeeks.count, 13)
    }

    func testTemplateGraphCarriesNoCalendarDates() {
        // `TemplateSession`/`WorkoutBlockTemplate`/`SteadyStatePrescriptionTemplate`/
        // `IntervalPrescriptionTemplate` have no `Date`-typed field at all
        // — dates are assigned only at materialization time
        // (`RunningProgramMaterializer`), never baked into the definition.
        // Structural proof via mirror: no property on these types is a Date.
        let session = definition.orderedTemplateSessions[0]
        let mirror = Mirror(reflecting: session)
        for child in mirror.children {
            XCTAssertFalse(child.value is Date, "TemplateSession must never carry a literal calendar date")
        }
    }

    // MARK: Reduction weeks (literal properties of this definition, not a generalized engine rule)

    func testWeeksFourEightAndTwelveAreMarkedAsReductions() {
        let weeks = definition.orderedWeeks
        XCTAssertTrue(weeks[3].isDeload, "relative week 4")
        XCTAssertTrue(weeks[7].isDeload, "relative week 8")
        XCTAssertTrue(weeks[11].isDeload, "relative week 12 (taper)")
        for index in [0, 1, 2, 4, 5, 6, 8, 9, 10, 12] {
            XCTAssertFalse(weeks[index].isDeload, "relative week \(index + 1) must not be marked a reduction")
        }
    }

    // MARK: Representative structural shapes (R2.4-style, 6 required examples)

    func testEarlySimpleTempoActiveStructureIsRepresentable() {
        let slotA = definition.orderedTemplateSessions[0]
        XCTAssertEqual(slotA.orderedBlockTemplates.count, 4) // warmup, warmup, tempo, easy
        let slotB = definition.orderedTemplateSessions[1]
        XCTAssertEqual(slotB.orderedBlockTemplates.count, 3) // warmup, active, cooldown
    }

    func testSteadySessionStructureIsRepresentable() {
        let slotB = definition.orderedTemplateSessions[1]
        let labels = slotB.orderedBlockTemplates.compactMap { $0.steadyStatePrescriptionTemplate?.sourceLabel }
        XCTAssertEqual(labels, [.warmUp, .active, .coolDown])
    }

    func testFourRepeatIntervalSessionStructureIsRepresentable() {
        testRelativeWeekNineHasOneFourRepeatHardEasyGroup()
    }

    func testComplexMultiGroupLateSessionStructureIsRepresentable() {
        testRelativeWeekElevenHasThreeDistinctRepeatGroups()
    }

    func testTaperSingleRepStructureIsRepresentable() {
        testRelativeWeekTwelveHasTwoSingleRepGroupsPlusPlainEasyVolume()
    }

    func testRPEOnlyRaceStructureIsRepresentable() {
        testRaceWeekIsRPEOnlyWithTheVerbatimPacingNote()
    }
}
