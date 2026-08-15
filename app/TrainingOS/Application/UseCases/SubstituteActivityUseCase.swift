import Foundation
import SwiftData

/// The endurance sibling of `SubstituteExerciseUseCase` — same two scopes,
/// same validation-before-mutation discipline, applied to `ActivityType`
/// instead of `Exercise`.
enum SubstituteActivityUseCase {
    /// A candidate activity is valid for a template only when it appears
    /// in `allowedActivityTypes` — Stage 4C §35's explicit requirement
    /// that a running-specific prescription (`allowedActivityTypes ==
    /// [.running]`) must reject Bike, while a generic aerobic prescription
    /// may permit `[.cycling, .rowing, .skiErg]` or whatever a program
    /// author configured.
    static func isValid(candidate: ActivityType, for template: SteadyStatePrescriptionTemplate) -> Bool {
        template.allowedActivityTypes.contains(candidate)
    }

    /// **THIS SESSION ONLY.** Directly edits an already-materialized
    /// `SteadyStatePrescription` — `activityType` changes, and any
    /// modality-specific intensity target is translated (never blindly
    /// carried over — Stage 4C §37) via `IntensityTranslation`; a
    /// physiological target (HR zone/percent, RPE) survives unchanged.
    @discardableResult
    static func substituteThisSessionOnly(
        prescription: SteadyStatePrescription,
        template: SteadyStatePrescriptionTemplate,
        with activityType: ActivityType,
        reason: SubstitutionReason? = nil
    ) throws -> SteadyStatePrescription {
        guard isValid(candidate: activityType, for: template) else {
            throw SubstitutionError.invalidForSlot
        }
        let originalActivity = prescription.activityType
        prescription.activityType = activityType
        prescription.primaryIntensity = IntensityTranslation.translate(prescription.primaryIntensity, from: originalActivity, to: activityType)
        prescription.secondaryIntensity = IntensityTranslation.translate(prescription.secondaryIntensity, from: originalActivity, to: activityType)
        prescription.substitutionUsed = true
        prescription.substitutionReason = reason
        return prescription
    }

    /// **GOING FORWARD.** Same "at most one row per (instance, template)
    /// pair" invariant as `SlotSelectionOverride`.
    @discardableResult
    static func substituteGoingForward(
        instance: ProgramInstance,
        template: SteadyStatePrescriptionTemplate,
        with activityType: ActivityType,
        reason: SubstitutionReason? = nil,
        context: ModelContext
    ) throws -> ActivitySelectionOverride {
        guard isValid(candidate: activityType, for: template) else {
            throw SubstitutionError.invalidForSlot
        }
        if let existing = instance.activitySelectionOverride(for: template) {
            existing.selectedActivityType = activityType
            existing.reason = reason
            existing.createdAt = Date()
            return existing
        }
        let override = ActivitySelectionOverride(selectedActivityType: activityType, reason: reason)
        override.templateSteadyState = template
        context.insert(override)
        instance.addActivitySelectionOverride(override)
        return override
    }

    /// What a steady-state materializer should call instead of reading
    /// `template.preferredActivityType` directly.
    static func resolvedActivityType(for template: SteadyStatePrescriptionTemplate, in instance: ProgramInstance) -> ActivityType {
        instance.activitySelectionOverride(for: template)?.selectedActivityType ?? template.preferredActivityType
    }
}
