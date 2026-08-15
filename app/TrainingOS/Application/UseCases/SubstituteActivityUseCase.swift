import Foundation
import SwiftData

/// The endurance sibling of `SubstituteExerciseUseCase` — same two scopes,
/// same validation-before-mutation discipline, applied to `ActivityType`
/// instead of `Exercise`. Generic over `ActivitySubstitutionTemplate`
/// (both `SteadyStatePrescriptionTemplate` and, as of Stage 4D,
/// `IntervalPrescriptionTemplate`) via `WorkoutBlockTemplate` — see
/// `ActivitySelectionOverride`'s own "Stage 4D correction" doc comment.
enum SubstituteActivityUseCase {
    /// A candidate activity is valid for a template only when it appears
    /// in `allowedActivityTypes` — Stage 4C §35's explicit requirement
    /// that a running-specific prescription (`allowedActivityTypes ==
    /// [.running]`) must reject Bike, while a generic aerobic prescription
    /// may permit `[.cycling, .rowing, .skiErg]` or whatever a program
    /// author configured. Applies identically to interval templates
    /// (Stage 4D §24).
    static func isValid(candidate: ActivityType, for template: ActivitySubstitutionTemplate) -> Bool {
        template.allowedActivityTypes.contains(candidate)
    }

    /// **THIS SESSION ONLY**, steady-state. Directly edits an already-
    /// materialized `SteadyStatePrescription` — `activityType` changes,
    /// and any modality-specific intensity target is translated (never
    /// blindly carried over — Stage 4C §37) via `IntensityTranslation`; a
    /// physiological target (HR zone/percent, RPE) survives unchanged.
    @discardableResult
    static func substituteThisSessionOnly(
        prescription: SteadyStatePrescription,
        template: ActivitySubstitutionTemplate,
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

    /// **THIS SESSION ONLY**, interval (Stage 4D addition). Same shape as
    /// the steady-state overload, applied to `IntervalPrescription`'s two
    /// intensity legs (`workIntensity`/`recoveryIntensity`) instead of
    /// `primaryIntensity`/`secondaryIntensity`.
    @discardableResult
    static func substituteThisSessionOnly(
        prescription: IntervalPrescription,
        template: ActivitySubstitutionTemplate,
        with activityType: ActivityType,
        reason: SubstitutionReason? = nil
    ) throws -> IntervalPrescription {
        guard isValid(candidate: activityType, for: template) else {
            throw SubstitutionError.invalidForSlot
        }
        let originalActivity = prescription.activityType
        prescription.activityType = activityType
        prescription.workIntensity = IntensityTranslation.translate(prescription.workIntensity, from: originalActivity, to: activityType)
        prescription.recoveryIntensity = IntensityTranslation.translate(prescription.recoveryIntensity, from: originalActivity, to: activityType)
        prescription.substitutionUsed = true
        prescription.substitutionReason = reason
        return prescription
    }

    /// **GOING FORWARD.** Same "at most one row per (instance,
    /// templateBlock) pair" invariant as `SlotSelectionOverride`. Works
    /// identically for a steady-state or an interval `WorkoutBlockTemplate`
    /// — the caller supplies whichever `ActivitySubstitutionTemplate` the
    /// block carries (`WorkoutBlockTemplate.activitySubstitutionTemplate`).
    @discardableResult
    static func substituteGoingForward(
        instance: ProgramInstance,
        templateBlock: WorkoutBlockTemplate,
        eligibilityTemplate: ActivitySubstitutionTemplate,
        with activityType: ActivityType,
        reason: SubstitutionReason? = nil,
        context: ModelContext
    ) throws -> ActivitySelectionOverride {
        guard isValid(candidate: activityType, for: eligibilityTemplate) else {
            throw SubstitutionError.invalidForSlot
        }
        if let existing = instance.activitySelectionOverride(for: templateBlock) {
            existing.selectedActivityType = activityType
            existing.reason = reason
            existing.createdAt = Date()
            return existing
        }
        let override = ActivitySelectionOverride(selectedActivityType: activityType, reason: reason)
        override.templateBlock = templateBlock
        context.insert(override)
        instance.addActivitySelectionOverride(override)
        return override
    }

    /// What a materializer should call instead of reading
    /// `template.preferredActivityType` directly.
    static func resolvedActivityType(for templateBlock: WorkoutBlockTemplate, defaultActivityType: ActivityType, in instance: ProgramInstance) -> ActivityType {
        instance.activitySelectionOverride(for: templateBlock)?.selectedActivityType ?? defaultActivityType
    }
}
