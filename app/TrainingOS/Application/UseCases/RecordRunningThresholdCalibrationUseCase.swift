import Foundation
import SwiftData

/// Running R2: the only way application code should write a
/// `RunningThresholdCalibration`. Mirrors
/// `RecordSourceRMCalibrationUseCase`'s discipline: never computes,
/// converts, or estimates the value — exactly what the athlete entered —
/// and, per HowTo.txt line 13 ("Don't adjust any other time"), refuses to
/// record anything except the athlete's first-ever entry or an entry made
/// at an explicitly-flagged scheduled checkpoint
/// (`RunningThresholdRecalibrationGate`).
enum RecordRunningThresholdCalibrationUseCase {
    /// Returns `nil` (and inserts nothing) when the gate rejects the
    /// attempt — never silently records an out-of-schedule adjustment.
    @discardableResult
    static func record(
        thresholdPaceSecondsPerKilometer: Double,
        for instance: ProgramInstance,
        isScheduledCheckpoint: Bool,
        enteredAt: Date = Date(),
        modelContext: ModelContext
    ) -> RunningThresholdCalibration? {
        let isInitial = instance.runningThresholdCalibrations.isEmpty
        let (allowed, reasonCode) = RunningThresholdRecalibrationGate.evaluate(
            isInitialCalibration: isInitial,
            isScheduledCheckpoint: isScheduledCheckpoint
        )
        guard allowed else { return nil }
        let calibration = RunningThresholdCalibration(
            thresholdPaceSecondsPerKilometer: thresholdPaceSecondsPerKilometer,
            enteredAt: enteredAt,
            reasonCode: reasonCode
        )
        modelContext.insert(calibration)
        instance.addRunningThresholdCalibration(calibration)
        return calibration
    }

    /// The athlete's current, most-recently-entered threshold — `nil`
    /// means genuinely never calibrated, never a guessed/default value.
    static func currentThreshold(for instance: ProgramInstance) -> RunningThresholdCalibration? {
        instance.runningThresholdCalibrations.max { $0.enteredAt < $1.enteredAt }
    }
}
