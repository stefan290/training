import Foundation
import SwiftData

/// MUSCLE VERTICAL SLICE CONTINUATION, Sections 9-11: the real, athlete-
/// facing entry point for `MovementCapabilityProfile` — before this
/// checkpoint, the model existed and was already consumed by
/// `TechnicalCapacityDoseAuthority`/`MovementRoleExerciseSelector`, but
/// nothing in the app ever let an athlete actually record one; every
/// capability row a test constructed was seeded directly, never entered
/// through real UI. Get-or-create, mirroring `PerformanceProfileStore
/// .exerciseProfile`'s exact shape — never a duplicate row for the same
/// `(performanceProfile, exercise)` pair, always an update in place so a
/// later, corrected self-report replaces the prior one rather than
/// stacking history (this is a current-state capability, not a training
/// log).
enum RecordMovementCapabilityUseCase {
    @discardableResult
    static func record(
        exercise: Exercise,
        proficiency: MovementProficiency,
        capacityType: MovementCapacityType?,
        capacityValue: Double?,
        evidenceSource: CapabilityEvidenceSource,
        performanceProfile: PerformanceProfile,
        context: ModelContext
    ) -> MovementCapabilityProfile {
        if let existing = performanceProfile.movementCapability(for: exercise) {
            existing.proficiency = proficiency
            existing.capacityType = capacityType
            existing.capacityValue = capacityValue
            existing.evidenceSource = evidenceSource
            existing.evidenceDate = Date()
            return existing
        }
        let created = MovementCapabilityProfile(
            exercise: exercise, proficiency: proficiency,
            capacityType: capacityType, capacityValue: capacityValue,
            evidenceSource: evidenceSource
        )
        context.insert(created)
        performanceProfile.addMovementCapability(created)
        return created
    }
}
