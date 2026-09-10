import Foundation
import SwiftData

/// Running R2: the explicit, athlete-entered threshold-pace state — the
/// running sibling of `SourceRMCalibration`, same discipline: a literal,
/// user-entered value, never computed, never silently mutated by workout
/// performance. Scoped to `(programInstance)` — one current threshold per
/// running program instance, not global per athlete — mirroring
/// `SourceRMCalibration`'s own `(programInstance, exercise, rmType)`
/// scoping rationale (fresh input required per instance, never carried
/// forward automatically). Every historical entry is retained (never
/// overwritten in place) so "what was the threshold on date X" stays
/// answerable — `RecordRunningThresholdCalibrationUseCase` always inserts
/// a new row; `currentThreshold(for:)` reads the most recent one.
///
/// **CLAUDE.md rule 2 compliance:** this is its own entity, never a field
/// on `ProgramDefinition`/a template — a threshold is athlete performance
/// state, not program content.
@Model
final class RunningThresholdCalibration {
    @Attribute(.unique) var id: UUID
    var programInstance: ProgramInstance?
    var thresholdPaceSecondsPerKilometer: Double
    var enteredAt: Date
    var reasonCode: RunningThresholdRecalibrationReasonCode

    init(
        id: UUID = UUID(),
        thresholdPaceSecondsPerKilometer: Double,
        enteredAt: Date = Date(),
        reasonCode: RunningThresholdRecalibrationReasonCode
    ) {
        self.id = id
        self.thresholdPaceSecondsPerKilometer = thresholdPaceSecondsPerKilometer
        self.enteredAt = enteredAt
        self.reasonCode = reasonCode
    }
}
