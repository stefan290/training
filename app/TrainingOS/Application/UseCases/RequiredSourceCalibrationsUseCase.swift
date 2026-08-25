import Foundation

/// Stage 10R.1C: a pure, read-only query — which `(Exercise, RMType)`
/// pairs a `.rmBased` program definition's resolved slots still need a
/// `SourceRMCalibration` for, before `RollTacticalWindowUseCase
/// .materializeFirstWindow` can honestly resolve Week-1 loads. Generic
/// across every source family that uses `.rmBased` (Family A/B/C) —
/// never Hypertrophy-specific — since the requirement is derived purely
/// from `PrescriptionTemplate.rules.loadRule` and the slot's own already-
/// resolved exercise, not from any program-family assumption.
enum RequiredSourceCalibrationsUseCase {
    struct Requirement {
        var exercise: Exercise
        var rmType: RMType
    }

    /// Deduplicated by `(exercise.id, rmType)` — a program that resolves
    /// the same exercise into several slots requiring the identical
    /// `RMType` is asked for that exercise exactly once
    /// (`STAGE10R1C_SOURCE_RM_CALIBRATION_DESIGN.md` Decision 1). Order
    /// matches the order slots are first encountered walking the
    /// definition's sessions/blocks/templates — deterministic, never
    /// randomized.
    static func stillRequired(for definition: ProgramDefinition, instance: ProgramInstance) -> [Requirement] {
        var seenKeys = Set<String>()
        var ordered: [Requirement] = []

        for session in definition.orderedTemplateSessions {
            for block in session.orderedBlockTemplates {
                for template in block.orderedPrescriptionTemplates {
                    guard let loadRule = template.rules?.loadRule, case .rmBased(let payload) = loadRule else { continue }
                    guard let slot = template.exerciseSlot else { continue }
                    guard let exercise = SubstituteExerciseUseCase.resolvedExercise(for: slot, in: instance) else { continue }

                    let key = "\(exercise.id.uuidString)|\(payload.rmType.rawValue)"
                    guard seenKeys.insert(key).inserted else { continue }
                    guard instance.sourceRMCalibration(for: exercise, rmType: payload.rmType) == nil else { continue }
                    ordered.append(Requirement(exercise: exercise, rmType: payload.rmType))
                }
            }
        }
        return ordered
    }
}
