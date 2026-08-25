import Foundation
import SwiftData

/// Stage 10R.1C: persists the literal, user-entered RM value for one
/// `(programInstance, exercise, rmType)` — the only way application code
/// should write a `SourceRMCalibration`. Never computes, converts, or
/// estimates `kilograms`; it is exactly what the user typed.
enum RecordSourceRMCalibrationUseCase {
    /// Overwrites an existing calibration for the same `(instance,
    /// exercise, rmType)` rather than appending a duplicate — mirrors
    /// `SlotSelectionOverride`'s "at most one row per pair, update in
    /// place" discipline.
    ///
    /// **Does not itself save.** A real manual-acceptance crash traced to
    /// calling `modelContext.save()` once per row, inside the loop that
    /// records every required calibration — saving mid-flight, before a
    /// `StartPhaseUseCase.start()`-originated object graph (other
    /// components' not-yet-scheduled instances/sessions, in particular)
    /// was fully constructed, produced spurious `infeasible` scheduling
    /// failures downstream. The caller that records a whole batch of
    /// calibrations (`SourceRMCalibrationViewModel.completeCalibrationAndStart`,
    /// `CalibrationTestSupport`) is responsible for one explicit
    /// `try modelContext.save()` after every required row has been
    /// recorded and BEFORE materialization is attempted — durable enough
    /// that a crash during materialization can never erase already-
    /// entered RM values, without the per-row save that caused the
    /// regression.
    @discardableResult
    static func record(
        exercise: Exercise, rmType: RMType, kilograms: Double,
        for instance: ProgramInstance, enteredAt: Date = Date(), modelContext: ModelContext
    ) -> SourceRMCalibration {
        if let existing = instance.sourceRMCalibration(for: exercise, rmType: rmType) {
            existing.kilograms = kilograms
            existing.enteredAt = enteredAt
            return existing
        }
        let calibration = SourceRMCalibration(exercise: exercise, rmType: rmType, kilograms: kilograms, enteredAt: enteredAt)
        modelContext.insert(calibration)
        instance.addSourceRMCalibration(calibration)
        return calibration
    }
}

/// Stage 10R.1C: read-only reference lookup for the calibration UX's
/// "PREVIOUS" display — the most recently entered value for the same
/// `(exercise, rmType)` from any OTHER `ProgramInstance` belonging to the
/// same owner, never the current instance itself. Purely informational;
/// never consulted by `RequiredSourceCalibrationsUseCase` or by
/// materialization — the current mesocycle's own calibration must always
/// be entered explicitly (`STAGE10R1C_SOURCE_RM_CALIBRATION_DESIGN.md`,
/// "Previous mesocycle values").
enum PreviousSourceRMCalibrationUseCase {
    static func mostRecentPriorValue(
        for exercise: Exercise, rmType: RMType, excluding currentInstance: ProgramInstance,
        ownerUserID: UUID, modelContext: ModelContext
    ) -> SourceRMCalibration? {
        let exerciseID = exercise.id
        // Filtered in plain Swift after a broad fetch, not via `#Predicate`,
        // to avoid comparing a stored enum (`rmType`) inside a SwiftData
        // predicate — an untested pattern elsewhere in this codebase and a
        // known source of runtime predicate-compilation failures; the
        // exercise-scoped fetch keeps the candidate set small regardless.
        let descriptor = FetchDescriptor<SourceRMCalibration>(predicate: #Predicate { $0.exercise?.id == exerciseID })
        let candidates = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter {
                $0.rmType == rmType && $0.programInstance?.id != currentInstance.id
                    && $0.programInstance?.ownerUserID == ownerUserID
            }
        return candidates.max { $0.enteredAt < $1.enteredAt }
    }
}
