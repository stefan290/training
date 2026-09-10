import Foundation
import SwiftData

/// A templated week inside a ProgramDefinition. Deliberately minimal,
/// unchanged since Stage 1-2: just the Program -> weeks structure and the
/// program-owned deload flag. **Not a session-structure container** —
/// Family A's own rules (`RMBasedLoad.laterWeekMultipliers`,
/// `StrengthProgressionRules.repGoalSchedule`) already express a whole
/// mesocycle's week-by-week progression as arrays on a *single*
/// `PrescriptionTemplate`, and deload behavior is a rule
/// (`deloadWeightAction`/`deloadRepAction`) resolved by `isDeload`, not a
/// separately-templated week. Duplicating the session/block/prescription
/// graph once per `TrainingWeek` would be redundant with that design and
/// was corrected during Stage 4A's own implementation before it shipped —
/// see `ProgramDefinition.templateSessions` for where the one recurring
/// weekly structure actually lives.
@Model
final class TrainingWeek {
    @Attribute(.unique) var id: UUID
    var programDefinition: ProgramDefinition?
    /// Stable position among a ProgramDefinition's weeks, assigned by
    /// `ProgramDefinition.addWeek(_:)`.
    var sortIndex: Int
    var isDeload: Bool
    /// Running R3 addition: this week is a scheduled "Threshold Pace
    /// Adjustment" checkpoint — HowTo.txt line 13's own rule ("scheduled
    /// Threshold Pace Adjustment reminders... Don't adjust any other
    /// time"). Placement is a disclosed **PROGRAMMING INFERENCE /
    /// TRAININGOS PRODUCT DECISION**, not a resolved SOURCE FACT: R1
    /// corroborated two calendar-side checkpoints ("around Nov 2" /
    /// "...2 around Nov 30") but the exact relative-week alignment
    /// between `Calendar Overview` and `Workout Blocks` numbering is
    /// explicitly UNRESOLVED (R1 §17/§20). `RunningProgramGenerator`
    /// places these at relative weeks 5 and 9 — immediately after the two
    /// doubly-corroborated reduction weeks (4 and 8) — as its own
    /// best-effort, disclosed placement, never claiming source precision
    /// it doesn't have. This flag only marks WHERE a checkpoint exists;
    /// the new threshold VALUE is never computed here or anywhere else —
    /// see `RunningThresholdRecalibrationGate`/
    /// `RecordRunningThresholdCalibrationUseCase` (R2) for the actual
    /// enforcement, which requires the athlete's own entered number.
    /// Declared with an inline default (`= false`), not just an `init`
    /// parameter default — required for SwiftData's lightweight migration
    /// to synthesize a value for every already-persisted `TrainingWeek`
    /// row from before this field existed (an `init`-only default has no
    /// effect on existing on-disk rows; confirmed the hard way this pass —
    /// a real on-disk store from earlier checkpoints in this engagement
    /// failed to migrate with `init`-only defaulting, exactly the
    /// documented Bug 2/3-style migration hazard `SteadyStatePrescriptionTemplate`'s
    /// own inline-default fields already guard against).
    var isThresholdRecalibrationCheckpoint: Bool = false

    init(id: UUID = UUID(), isDeload: Bool = false, isThresholdRecalibrationCheckpoint: Bool = false) {
        self.id = id
        self.sortIndex = 0
        self.isDeload = isDeload
        self.isThresholdRecalibrationCheckpoint = isThresholdRecalibrationCheckpoint
    }
}
