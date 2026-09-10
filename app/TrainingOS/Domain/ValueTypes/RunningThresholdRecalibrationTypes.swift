import Foundation

/// Why a `RunningThresholdCalibration` was (or was not) recorded —
/// HowTo.txt line 13: "There are scheduled Threshold Pace Adjustment
/// reminders within the plan... Don't adjust any other time."
/// Deliberately does NOT compute or infer *when* a checkpoint occurs —
/// R1 §20 leaves the universal cadence unresolved, and CLAUDE.md rule 10
/// forbids inventing the missing formula. `isScheduledCheckpoint` is
/// always a plain caller-supplied fact (e.g. a `TrainingWeek`-level flag
/// set by whatever later feature owns scheduling), never derived here.
enum RunningThresholdRecalibrationReasonCode: String, Codable, CaseIterable {
    /// The athlete's very first threshold entry — nothing to "adjust"
    /// yet, so the scheduled-only restriction does not apply.
    case initialCalibration
    case recordedAtScheduledCheckpoint
    case rejectedNotAtScheduledCheckpoint
}

/// The gate deciding whether a threshold value may be recorded right now.
/// Pure and stateless — never reads a clock, never infers a cadence.
enum RunningThresholdRecalibrationGate {
    static func evaluate(isInitialCalibration: Bool, isScheduledCheckpoint: Bool) -> (allowed: Bool, reasonCode: RunningThresholdRecalibrationReasonCode) {
        if isInitialCalibration {
            return (true, .initialCalibration)
        }
        if isScheduledCheckpoint {
            return (true, .recordedAtScheduledCheckpoint)
        }
        return (false, .rejectedNotAtScheduledCheckpoint)
    }
}
