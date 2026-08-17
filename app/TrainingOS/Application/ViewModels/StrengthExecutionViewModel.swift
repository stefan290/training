import Foundation
import SwiftData
import Observation

/// Drives Strength/Hypertrophy/Accessory execution for one `WorkoutBlock`,
/// one movement (`ExercisePrescription`) at a time — `STRENGTH_EXECUTION_
/// FLOW.md`. Reused as-is for Powerlifting (Part G): nothing here branches
/// on programming methodology, only on the same materialized
/// prescription/result shapes every strength movement already has.
@Observable
final class StrengthExecutionViewModel {
    let block: WorkoutBlock
    private(set) var movementIndex: Int = 0
    /// Captured once when a movement loads — what the user did last time,
    /// never recomputed as new sets are logged this same visit (a "you
    /// just did this a second ago" previous-performance line would be
    /// useless and confusing).
    private(set) var previousResults: [SetResult] = []

    init(block: WorkoutBlock) {
        self.block = block
    }

    var movements: [ExercisePrescription] { block.orderedPrescriptions }

    var currentMovement: ExercisePrescription? {
        movements.indices.contains(movementIndex) ? movements[movementIndex] : nil
    }

    var currentSetIndex: Int { currentMovement?.loggedSetResults.count ?? 0 }

    var currentSetPrescription: SetPrescription? {
        guard let movement = currentMovement else { return nil }
        let ordered = movement.orderedSetPrescriptions
        return ordered.indices.contains(currentSetIndex) ? ordered[currentSetIndex] : nil
    }

    var isMovementComplete: Bool {
        guard let movement = currentMovement else { return true }
        return !movement.orderedSetPrescriptions.isEmpty
            && movement.loggedSetResults.count >= movement.orderedSetPrescriptions.count
    }

    func selectMovement(_ index: Int, modelContext: ModelContext) {
        guard movements.indices.contains(index) else { return }
        movementIndex = index
        loadPreviousPerformance(modelContext: modelContext)
    }

    func loadPreviousPerformance(modelContext: ModelContext) {
        guard let exercise = currentMovement?.exercise else {
            previousResults = []
            return
        }
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        guard let profile = users.first?.performanceProfile?.profile(for: exercise) else {
            previousResults = []
            return
        }
        previousResults = Array(profile.orderedSetResults.suffix(3))
    }

    /// Logs the current set and returns a display-ready highlight for the
    /// eventual completion screen to collect (`CompletionSummary`'s
    /// caller-accumulated `highlights`) — `nil` if nothing could be
    /// logged (no current movement/set, or no user/performance profile
    /// yet seeded).
    @discardableResult
    func logCurrentSet(weight: Double, reps: Int, actualRir: Int?, modelContext: ModelContext) -> LoggedResultHighlight? {
        guard let movement = currentMovement, let exercise = movement.exercise else { return nil }
        let setPrescription = currentSetPrescription
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        guard let performanceProfile = users.first?.performanceProfile else { return nil }
        let prBand = setPrescription.map { "\($0.repRangeLow)-\($0.repRangeHigh)" }

        guard let outcome = try? LogSetUseCase.logSet(
            setIndex: currentSetIndex,
            weight: weight,
            reps: reps,
            targetRir: setPrescription?.targetRir,
            actualRir: actualRir,
            prBand: prBand,
            scoringDirection: .higherIsBetter,
            context: .rx,
            setPrescription: setPrescription,
            exercisePrescription: movement,
            exercise: exercise,
            performanceProfile: performanceProfile,
            completedAt: Date(),
            modelContext: modelContext
        ) else { return nil }

        return LoggedResultHighlight(
            label: exercise.canonicalName,
            value: "\(weight.formattedWeight) x \(reps)",
            isPersonalRecord: outcome.result.isPersonalRecord,
            isFirstEverEntry: outcome.isFirstEverEntry
        )
    }
}

extension Double {
    /// Trims a trailing `.0` for a whole-number weight (e.g. `60` not
    /// `60.0`) while still showing a fractional plate load (e.g. `62.5`).
    var formattedWeight: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(format: "%.1f", self)
    }
}
