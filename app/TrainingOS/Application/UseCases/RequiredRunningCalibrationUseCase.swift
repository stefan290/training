import Foundation

/// Running R3: the running sibling of `RequiredSourceCalibrationsUseCase` —
/// whether an athlete's threshold pace still needs to be entered before a
/// `%threshold`-prescribed Running definition can honestly resolve real
/// target paces. Generic over ANY definition using
/// `IntensityTarget.percentOfReference(_, metric: .thresholdPace)` (on
/// either a steady-state or interval template) — never Running-specific
/// by name, mirroring `RequiredSourceCalibrationsUseCase`'s own genericity
/// over any `.rmBased` rule.
///
/// **No silent default.** Nothing in this codebase may ever fall back to
/// the captured reference athlete's 5:00/km value (or any other constant)
/// when this returns `true` — that value exists only in R1's analysis and
/// in test/dogfood fixtures, never in production defaulting logic.
enum RequiredRunningCalibrationUseCase {
    /// `true` only when the definition actually contains at least one
    /// `%threshold`-prescribed block AND the instance has no
    /// `RunningThresholdCalibration` yet. A definition with no such block
    /// (e.g. a hypothetical future all-RPE program) never requires one.
    static func isThresholdCalibrationRequired(for definition: ProgramDefinition, instance: ProgramInstance) -> Bool {
        guard usesThresholdRelativeIntensity(definition) else { return false }
        return RecordRunningThresholdCalibrationUseCase.currentThreshold(for: instance) == nil
    }

    private static func usesThresholdRelativeIntensity(_ definition: ProgramDefinition) -> Bool {
        for session in definition.orderedTemplateSessions {
            for block in session.orderedBlockTemplates {
                if isThresholdRelative(block.steadyStatePrescriptionTemplate?.primaryIntensity) { return true }
                if isThresholdRelative(block.intervalPrescriptionTemplate?.workIntensity) { return true }
                if isThresholdRelative(block.intervalPrescriptionTemplate?.recoveryIntensity) { return true }
            }
        }
        return false
    }

    private static func isThresholdRelative(_ target: IntensityTarget?) -> Bool {
        if case .percentOfReference(_, let metric) = target, metric == .thresholdPace { return true }
        return false
    }
}
