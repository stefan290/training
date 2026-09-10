import Foundation
import SwiftData

/// Running 5K/2-Day V1 (R3): thrown only when `configuration` does not
/// match the single supported combination
/// (`ProgramCapabilityRegistry.isRunningConfigurationSupported`) — never
/// thrown for any other reason, since the generator's own literal source
/// data is fixed and cannot itself fail a structural-coverage check the
/// way `HypertrophyProgramGenerator`'s day-focus-driven path can.
/// Deliberately distinct from silently substituting the nearest supported
/// configuration — the R3 directive's own explicit "never choose the
/// nearest frequency" requirement.
enum RunningGenerationError: Error, Equatable {
    case unsupportedConfiguration(distance: RunningDistance, daysPerWeek: Int)
}

/// One literal block from the recovered 5K/2-day source program
/// (`RUNNING_PROGRAMMING_MODEL_R1.md`, `app/source_workbooks/
/// RP_5K_TrainingPeaks_Reference.xlsx`'s `Workout Blocks` sheet — all 145
/// rows re-derived directly from the workbook this pass, not from R1's own
/// prose summary, which only walks representative weeks). `percentOfThreshold`
/// is the sheet's own `Derived % Threshold` value for that row (never
/// re-derived from a hardcoded 5:00/km assumption baked into this generator
/// — the athlete's own threshold is supplied only at materialization time,
/// via `ThresholdPaceEngine`, per the R3 directive's PROGRAM STRUCTURE vs.
/// ATHLETE-SPECIFIC PRESCRIPTION separation). Exactly one of
/// `percentOfThreshold`/`rpe` is non-nil per block, mirroring
/// `IntensityTarget`'s own one-case-at-a-time discipline — the race week's
/// two blocks are the only rows where `rpe` is set.
struct RunningSourceBlock {
    var label: RunningSourceLabel
    var distanceMeters: Double?
    var rpe: Int?
    var percentOfThreshold: Double?
    /// Non-nil only for blocks that are one leg of a named Repeat Group
    /// (e.g. `"R1"`) — always appears in a Hard/Easy pair sharing the same
    /// group label and `repeatCount`, exactly as observed (R1 §5).
    var repeatGroup: String?
    var repeatCount: Int?
    var executionNotes: String?
}

/// One literal observed workout (`W01`-`W25`) — `relativeWeek` is 1-13,
/// `slot` is `"A"`/`"B"`/`"Race"` exactly as the source's own `Slot`
/// column reads (R1 §5: "character is organizational shorthand," never a
/// physiological classification).
struct RunningSourceWorkout {
    var workoutID: String
    var relativeWeek: Int
    var slot: String
    var blocks: [RunningSourceBlock]
}

/// Builds the recovered, source-backed 5K/2-day (13-relative-week, 25-
/// workout) Running V1 `ProgramDefinition` — the Running sibling of
/// `HypertrophyProgramGenerator`/`SteadyStateProgramGenerator`, but
/// structurally different from both in one deliberate way: every one of
/// this program's 25 `TemplateSession`s belongs to EXACTLY one relative
/// week (never a recurring weekly slot progressed by a rule) — see
/// `RunningProgramMaterializer`'s own doc comment for why `activeFromWeek`
/// is read with EXACT-equality semantics here, never the generic
/// `activeFromWeek <= weekIndex` recurring filter every other
/// materializer uses.
///
/// **PROGRAM STRUCTURE vs. ATHLETE-SPECIFIC PRESCRIPTION (R3's own
/// required separation):** every block below carries only a
/// `percentOfThreshold` fraction or an `rpe` value — never an absolute
/// pace, never any specific athlete's captured 5:00/km threshold. The
/// captured athlete's own paces (`RUNNING_PROGRAMMING_MODEL_R1.md` §6)
/// were used only to VERIFY these percentages during R1 (re-deriving
/// `%threshold = 300s / observedPaceSeconds` and confirming it matches the
/// sheet's own `Derived % Threshold` column) — no absolute pace or the
/// 5:00/km value appears anywhere in this file. A real athlete's absolute
/// target pace is computed only at materialization time
/// (`RunningProgramMaterializer`), from that athlete's own
/// `RunningThresholdCalibration`, via `ThresholdPaceEngine` (R2) — never
/// hardcoded here.
enum RunningProgramGenerator {
    static let currentVersion = 1

    /// Relative weeks (1-indexed, matching the source's own numbering)
    /// that are genuine reductions by RP's own volume-based deload
    /// definition (`RUNNING_PROGRAMMING_MODEL_R1.md` §9-§10: weeks 4 and 8
    /// in the 12-week build portion) plus the taper's own contraction in
    /// week 12 (R1 §10's own finding that it satisfies RP's volume-drop
    /// test even though nothing in the source labels it "deload"
    /// verbatim). This is a literal property of THIS source-backed
    /// definition's specific weeks — never a computed "every 4th week"
    /// engine rule (R3's own explicit prohibition on a generalized
    /// deload-cadence engine).
    static let reductionRelativeWeeks: Set<Int> = [4, 8, 12]

    /// Disclosed placement of scheduled Threshold Pace Adjustment
    /// checkpoints — see `TrainingWeek.isThresholdRecalibrationCheckpoint`'s
    /// own doc comment for the full PROGRAMMING INFERENCE / TRAININGOS
    /// PRODUCT DECISION disclosure. Never a resolved SOURCE FACT position.
    static let thresholdRecalibrationCheckpointRelativeWeeks: Set<Int> = [5, 9]

    @discardableResult
    static func generate(
        configuration: RunningProgramConfiguration,
        provenance: ProgramProvenance,
        context: ModelContext
    ) throws -> ProgramDefinition {
        guard ProgramCapabilityRegistry.isRunningConfigurationSupported(distance: configuration.distance, daysPerWeek: configuration.daysPerWeek) else {
            throw RunningGenerationError.unsupportedConfiguration(distance: configuration.distance, daysPerWeek: configuration.daysPerWeek)
        }

        let definition = ProgramDefinition(
            name: "5K / 2-Day Running (Source-Backed V1)",
            lengthWeeks: 13,
            intent: "Running, 5K, 2 days/week — recovered 13-relative-week source structure",
            programmingSystem: .running,
            generatorVersion: currentVersion,
            provenance: provenance,
            runningConfiguration: configuration
        )
        context.insert(definition)

        for relativeWeek in 1...13 {
            let week = TrainingWeek(
                isDeload: reductionRelativeWeeks.contains(relativeWeek),
                isThresholdRecalibrationCheckpoint: thresholdRecalibrationCheckpointRelativeWeeks.contains(relativeWeek)
            )
            context.insert(week)
            definition.addWeek(week)
        }

        for sourceWorkout in sourceWorkouts {
            let session = TemplateSession(
                name: "Week \(sourceWorkout.relativeWeek) — Slot \(sourceWorkout.slot)",
                role: sessionRole(for: sourceWorkout),
                activeFromWeek: sourceWorkout.relativeWeek - 1
            )
            context.insert(session)
            definition.addTemplateSession(session)

            var index = 0
            let blocks = sourceWorkout.blocks
            while index < blocks.count {
                let block = blocks[index]
                if block.repeatGroup != nil, index + 1 < blocks.count, blocks[index + 1].repeatGroup == block.repeatGroup {
                    let workLeg = block
                    let recoveryLeg = blocks[index + 1]
                    let blockTemplate = WorkoutBlockTemplate(type: .intervals)
                    context.insert(blockTemplate)
                    session.addBlockTemplate(blockTemplate)

                    let intervalTemplate = IntervalPrescriptionTemplate(
                        preferredActivityType: .running,
                        workIntensity: intensityTarget(for: workLeg),
                        recoveryIntensity: intensityTarget(for: recoveryLeg),
                        recoveryType: .active,
                        progressionRules: IntervalProgressionRules(
                            priority: [],
                            weekOneIntervalCount: workLeg.repeatCount ?? 1,
                            weekOneWorkDurationSeconds: nil,
                            weekOneWorkDistanceMeters: workLeg.distanceMeters,
                            weekOneRecoveryDurationSeconds: nil,
                            weekOneRecoveryDistanceMeters: recoveryLeg.distanceMeters,
                            requiresSuccessfulCompletionToProgress: false
                        )
                    )
                    intervalTemplate.sourceLabel = workLeg.label
                    intervalTemplate.executionNotes = workLeg.executionNotes ?? recoveryLeg.executionNotes
                    context.insert(intervalTemplate)
                    blockTemplate.attachIntervalPrescriptionTemplate(intervalTemplate)

                    index += 2
                } else {
                    let blockTemplate = WorkoutBlockTemplate(type: workoutBlockType(for: block))
                    context.insert(blockTemplate)
                    session.addBlockTemplate(blockTemplate)

                    let steadyTemplate = SteadyStatePrescriptionTemplate(
                        preferredActivityType: .running,
                        primaryIntensity: intensityTarget(for: block),
                        progressionRules: SteadyStateProgressionRules(
                            progressionDimension: block.distanceMeters != nil ? .distance : .none,
                            weekOneDistanceMeters: block.distanceMeters
                        )
                    )
                    steadyTemplate.sourceLabel = block.label
                    steadyTemplate.executionNotes = block.executionNotes
                    context.insert(steadyTemplate)
                    blockTemplate.attachSteadyStatePrescriptionTemplate(steadyTemplate)

                    index += 1
                }
            }
        }

        return definition
    }

    /// `.interval` for any Slot A workout containing at least one Repeat
    /// Group (relative week 9 onward, R1 §5) — `.tempo` for the earlier,
    /// non-repeat Slot A workouts (weeks 1-8's constant-pace Tempo/Active
    /// quality content); `.easy` for every Slot B workout (the source's
    /// own lower-intensity Active/Cool-Down slot throughout, R1 §5/§7);
    /// `nil` for the race week — it does not fit any existing `SessionRole`
    /// honestly (R2's own `RunningOrchestrationContract.qualityClassification`
    /// already returns `nil` for roles it cannot honestly derive; this
    /// generator follows the identical discipline rather than forcing one).
    private static func sessionRole(for workout: RunningSourceWorkout) -> SessionRole? {
        switch workout.slot {
        case "Race": return nil
        case "B": return .easy
        default: return workout.blocks.contains { $0.repeatGroup != nil } ? .interval : .tempo
        }
    }

    private static func workoutBlockType(for block: RunningSourceBlock) -> WorkoutBlockType {
        switch block.label {
        case .warmUp, .warmUpEasyWalkSlowJog: return .warmup
        case .coolDown: return .cooldown
        default: return .steadyState
        }
    }

    private static func intensityTarget(for block: RunningSourceBlock) -> IntensityTarget? {
        if let rpe = block.rpe {
            return .rpe(BoundedRange(lower: rpe, upper: rpe))
        }
        if let percent = block.percentOfThreshold {
            return .percentOfReference(BoundedRange(lower: percent, upper: percent), metric: .thresholdPace)
        }
        return nil
    }

    // MARK: - Literal source data (re-derived directly from
    // `RP_5K_TrainingPeaks_Reference.xlsx`'s `Workout Blocks` sheet, all
    // 145 rows, this pass — not from R1's prose summary alone)

        static let sourceWorkouts: [RunningSourceWorkout] = [
            RunningSourceWorkout(workoutID: "W01", relativeWeek: 1, slot: "A", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.6993006993006993, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .tempo, distanceMeters: 3218.69, rpe: nil, percentOfThreshold: 0.9009009009009009, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .easy, distanceMeters: 2414.02, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W02", relativeWeek: 1, slot: "B", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 1207.01, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .active, distanceMeters: 4023.36, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .coolDown, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W03", relativeWeek: 2, slot: "A", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.6993006993006993, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .tempo, distanceMeters: 3621.02, rpe: nil, percentOfThreshold: 0.9009009009009009, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .easy, distanceMeters: 3621.02, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W04", relativeWeek: 2, slot: "B", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 1207.01, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .active, distanceMeters: 4828.03, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .coolDown, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W05", relativeWeek: 3, slot: "A", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.6993006993006993, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .tempo, distanceMeters: 4828.03, rpe: nil, percentOfThreshold: 0.9009009009009009, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .easy, distanceMeters: 3218.69, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W06", relativeWeek: 3, slot: "B", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 1207.01, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .active, distanceMeters: 5632.7, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .coolDown, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W07", relativeWeek: 4, slot: "A", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.6993006993006993, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .tempo, distanceMeters: 1609.34, rpe: nil, percentOfThreshold: 0.9009009009009009, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .easy, distanceMeters: 5632.7, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W08", relativeWeek: 4, slot: "B", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 1207.01, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .active, distanceMeters: 2414.02, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .coolDown, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W09", relativeWeek: 5, slot: "A", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.6993006993006993, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.9009009009009009, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 1.0, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .active, distanceMeters: 2414.02, rpe: nil, percentOfThreshold: 0.9493670886075949, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .recovery, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .active, distanceMeters: 1609.34, rpe: nil, percentOfThreshold: 0.9493670886075949, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .recovery, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W10", relativeWeek: 5, slot: "B", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 1207.01, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .active, distanceMeters: 4828.03, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .coolDown, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W11", relativeWeek: 6, slot: "A", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.6993006993006993, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.9009009009009009, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 1.0, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .active, distanceMeters: 3218.69, rpe: nil, percentOfThreshold: 0.970873786407767, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .recovery, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.7692307692307693, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .active, distanceMeters: 2414.02, rpe: nil, percentOfThreshold: 0.9493670886075949, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .recovery, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W12", relativeWeek: 6, slot: "B", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 1207.01, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .active, distanceMeters: 6437.38, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .coolDown, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W13", relativeWeek: 7, slot: "A", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.6993006993006993, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.9009009009009009, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 1.0, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .active, distanceMeters: 3218.69, rpe: nil, percentOfThreshold: 0.970873786407767, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .recovery, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.7692307692307693, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .active, distanceMeters: 3218.69, rpe: nil, percentOfThreshold: 0.9493670886075949, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .recovery, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W14", relativeWeek: 7, slot: "B", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 1207.01, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .active, distanceMeters: 8046.72, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .coolDown, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W15", relativeWeek: 8, slot: "A", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.6993006993006993, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.9009009009009009, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 1.0, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .active, distanceMeters: 1609.34, rpe: nil, percentOfThreshold: 1.0, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .recovery, distanceMeters: 4828.03, rpe: nil, percentOfThreshold: 0.7692307692307693, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W16", relativeWeek: 8, slot: "B", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 1207.01, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .active, distanceMeters: 4828.03, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .coolDown, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W17", relativeWeek: 9, slot: "A", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 1207.01, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.8695652173913043, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.9287925696594427, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 400.0, rpe: nil, percentOfThreshold: 1.0, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 400.0, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 200.0, rpe: nil, percentOfThreshold: 1.098901098901099, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 200.0, rpe: nil, percentOfThreshold: 0.6, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .hard, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 1.098901098901099, repeatGroup: "R1", repeatCount: 4, executionNotes: nil),
                RunningSourceBlock(label: .easy, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.6, repeatGroup: "R1", repeatCount: 4, executionNotes: nil),
                RunningSourceBlock(label: .coolDown, distanceMeters: 1609.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W18", relativeWeek: 9, slot: "B", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.6993006993006993, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.9009009009009009, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 1.0, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .active, distanceMeters: 4023.36, rpe: nil, percentOfThreshold: 0.9009009009009009, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .recovery, distanceMeters: 2414.02, rpe: nil, percentOfThreshold: 0.7692307692307693, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W19", relativeWeek: 10, slot: "A", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.8695652173913043, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.9287925696594427, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 400.0, rpe: nil, percentOfThreshold: 1.0, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 400.0, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 200.0, rpe: nil, percentOfThreshold: 1.098901098901099, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 200.0, rpe: nil, percentOfThreshold: 0.6, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .hard, distanceMeters: 800.0, rpe: nil, percentOfThreshold: 1.098901098901099, repeatGroup: "R1", repeatCount: 6, executionNotes: nil),
                RunningSourceBlock(label: .easy, distanceMeters: 400.0, rpe: nil, percentOfThreshold: 0.6, repeatGroup: "R1", repeatCount: 6, executionNotes: nil),
                RunningSourceBlock(label: .coolDown, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W20", relativeWeek: 10, slot: "B", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 1207.01, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .active, distanceMeters: 9656.06, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .coolDown, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W21", relativeWeek: 11, slot: "A", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.9009009009009009, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 200.0, rpe: nil, percentOfThreshold: 1.0, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 200.0, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 200.0, rpe: nil, percentOfThreshold: 1.098901098901099, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 200.0, rpe: nil, percentOfThreshold: 0.6, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .hard, distanceMeters: 800.0, rpe: nil, percentOfThreshold: 1.098901098901099, repeatGroup: "R1", repeatCount: 2, executionNotes: nil),
                RunningSourceBlock(label: .easy, distanceMeters: 400.0, rpe: nil, percentOfThreshold: 0.6, repeatGroup: "R1", repeatCount: 2, executionNotes: nil),
                RunningSourceBlock(label: .hard, distanceMeters: 3218.69, rpe: nil, percentOfThreshold: 0.9493670886075949, repeatGroup: "R2", repeatCount: 1, executionNotes: nil),
                RunningSourceBlock(label: .easy, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.6, repeatGroup: "R2", repeatCount: 1, executionNotes: nil),
                RunningSourceBlock(label: .hard, distanceMeters: 800.0, rpe: nil, percentOfThreshold: 1.048951048951049, repeatGroup: "R3", repeatCount: 2, executionNotes: nil),
                RunningSourceBlock(label: .easy, distanceMeters: 400.0, rpe: nil, percentOfThreshold: 0.6, repeatGroup: "R3", repeatCount: 2, executionNotes: nil),
                RunningSourceBlock(label: .coolDown, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W22", relativeWeek: 11, slot: "B", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 1207.01, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .active, distanceMeters: 9656.06, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .coolDown, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W23", relativeWeek: 12, slot: "A", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 804.67, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.9009009009009009, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 200.0, rpe: nil, percentOfThreshold: 1.0, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 200.0, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 200.0, rpe: nil, percentOfThreshold: 1.098901098901099, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .warmUp, distanceMeters: 200.0, rpe: nil, percentOfThreshold: 0.6, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .hard, distanceMeters: 800.0, rpe: nil, percentOfThreshold: 1.098901098901099, repeatGroup: "R1", repeatCount: 1, executionNotes: nil),
                RunningSourceBlock(label: .easy, distanceMeters: 400.0, rpe: nil, percentOfThreshold: 0.6, repeatGroup: "R1", repeatCount: 1, executionNotes: nil),
                RunningSourceBlock(label: .hard, distanceMeters: 1609.34, rpe: nil, percentOfThreshold: 0.9493670886075949, repeatGroup: "R2", repeatCount: 1, executionNotes: nil),
                RunningSourceBlock(label: .easy, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.6, repeatGroup: "R2", repeatCount: 1, executionNotes: nil),
                RunningSourceBlock(label: .easy, distanceMeters: 3218.69, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W24", relativeWeek: 12, slot: "B", blocks: [
                RunningSourceBlock(label: .warmUp, distanceMeters: 1207.01, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .active, distanceMeters: 3218.69, rpe: nil, percentOfThreshold: 0.8, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .coolDown, distanceMeters: 402.34, rpe: nil, percentOfThreshold: 0.75, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
            ]),
            RunningSourceWorkout(workoutID: "W25", relativeWeek: 13, slot: "Race", blocks: [
                RunningSourceBlock(label: .warmUpEasyWalkSlowJog, distanceMeters: 500.0, rpe: 3, percentOfThreshold: nil, repeatGroup: nil, repeatCount: nil, executionNotes: nil),
                RunningSourceBlock(label: .active, distanceMeters: 5000.0, rpe: 6, percentOfThreshold: nil, repeatGroup: nil, repeatCount: nil, executionNotes: "Start conservatively; pick up effort ~1.5 mi; if strong at mile 2, increase effort to finish."),
            ]),
        ]
}
