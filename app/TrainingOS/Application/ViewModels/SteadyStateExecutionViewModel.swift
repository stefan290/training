import Foundation
import SwiftData
import Observation

/// Drives Steady State execution (`ENDURANCE_EXECUTION_FLOW.md`, Part H) —
/// manual V1 for Running/Cycling/Rowing/SkiErg, fully usable without
/// HealthKit. A block's own `timerState` is a plain count-up (or, when
/// `durationSeconds` is prescribed, a count-up shown against that target)
/// clock; nothing here auto-completes the activity — the user always
/// explicitly finishes and enters what actually happened.
@Observable
final class SteadyStateExecutionViewModel {
    let block: WorkoutBlock

    init(block: WorkoutBlock) {
        self.block = block
    }

    var prescription: SteadyStatePrescription? { block.steadyStatePrescription }

    /// `scoringDirection` is passed through unused whenever
    /// `prCandidateValue` is `nil` (V1 default: Steady State has no single
    /// unambiguous PR metric — CLAUDE.md rule 10) but the use case still
    /// requires a value, so `.none` (not-scored) is always correct here.
    @discardableResult
    func logResult(
        actualDurationSeconds: Int,
        actualDistanceMeters: Double?,
        averageHeartRate: Int?,
        averagePower: Int?,
        averagePaceSecondsPerKilometer: Double?,
        rpe: Int?,
        modelContext: ModelContext
    ) -> LoggedResultHighlight? {
        guard let prescription else { return nil }
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        guard let performanceProfile = users.first?.performanceProfile else { return nil }

        let result = SteadyStateResult(
            actualDurationSeconds: actualDurationSeconds,
            actualDistanceMeters: actualDistanceMeters,
            averageHeartRate: averageHeartRate,
            averagePower: averagePower,
            averagePaceSecondsPerKilometer: averagePaceSecondsPerKilometer,
            rpe: rpe
        )

        guard let outcome = try? LogEnduranceResultUseCase.logSteadyStateResult(
            result, for: block, activityType: prescription.activityType,
            prCandidateValue: nil, scoringDirection: .none,
            performanceProfile: performanceProfile, modelContext: modelContext
        ) else { return nil }

        let minutes = actualDurationSeconds / 60
        return LoggedResultHighlight(
            label: IntensityPresentation.activityLabel(prescription.activityType),
            value: "\(minutes) min",
            // `prCandidateValue` is always `nil` above (V1: no single
            // unambiguous PR metric for Steady State), so PR detection
            // never runs — never `true` here.
            isPersonalRecord: false,
            isFirstEverEntry: outcome.isFirstEverEntry
        )
    }
}
