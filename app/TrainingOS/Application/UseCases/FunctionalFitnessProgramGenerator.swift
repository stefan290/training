import Foundation
import SwiftData

/// Builds and persists a `FunctionalFitnessPrescriptionTemplate`-based
/// template graph from a `FunctionalFitnessProgramConfiguration` — the
/// Functional Fitness sibling of `HypertrophyProgramGenerator`/
/// `SteadyStateProgramGenerator`/`IntervalProgramGenerator`.
///
/// **The five-stage pipeline, at generation time (§2):** Stage A
/// (`configuration.targetStimulus`) is supplied by the caller, not
/// invented here — a real "given a training goal, choose a stimulus"
/// decision is a product/content authoring concern, out of this pass's
/// scope (§34's V1 constraint). Stage B (`configuration.format`) is
/// likewise supplied directly. **Stages C-E run here**: Stage C derives
/// one `FunctionalFitnessMovementSlotTemplate` per `ModalityCount` entry
/// in the target stimulus's `movementModalityMix` (a couplet's 2 counts
/// become 2 slots, a triplet's 3 become 3), each constrained by
/// `allowedModalities`/`allowedMovementFunctions` — never a literal,
/// hard-coded exercise list (§8). Stage D (concrete exercise selection)
/// and Stage E (stimulus validation) are deliberately **not** run at
/// generation time — they depend on live exposure history and available
/// candidates, so they run at `FunctionalFitnessMaterializer` time
/// instead, exactly mirroring how Stage 4A deferred strength's concrete-
/// exercise resolution to materialization.
///
/// **Scope, stated plainly (§34, same discipline as every other Stage 4
/// generator):** single-modality conditioning, couplets, triplets, basic
/// longer mixed-modal workouts, strength+metcon composition, and
/// benchmark-shaped prescriptions are all provable through this one
/// generator — not an infinite CrossFit programmer, not a curated V1
/// content library (no `V1_PROGRAM_LIBRARY.md` entry names one, matching
/// every endurance generator's identical finding).
enum FunctionalFitnessProgramGenerator {
    static let currentVersion = 1

    @discardableResult
    static func generate(
        configuration: FunctionalFitnessProgramConfiguration,
        provenance: ProgramProvenance,
        context: ModelContext
    ) -> ProgramDefinition {
        let definition = ProgramDefinition(
            name: "\(configuration.daysPerWeek)-Day Functional Fitness (\(configuration.sessionRole.rawValue))",
            lengthWeeks: configuration.lengthWeeks,
            intent: "Functional Fitness, \(configuration.format), \(configuration.targetStimulus.targetDurationDomain) duration domain",
            programmingSystem: .functionalFitness,
            generatorVersion: currentVersion,
            provenance: provenance,
            functionalFitnessConfiguration: configuration
        )
        context.insert(definition)

        for _ in 0..<configuration.lengthWeeks {
            let week = TrainingWeek(isDeload: false)
            context.insert(week)
            definition.addWeek(week)
        }

        for dayIndex in 0..<configuration.daysPerWeek {
            let session = TemplateSession(name: "Day \(dayIndex + 1)", role: configuration.sessionRole)
            context.insert(session)
            definition.addTemplateSession(session)

            if configuration.includeStrengthBlock {
                addStrengthBlock(to: session, context: context)
            }

            let ffBlock = WorkoutBlockTemplate(type: .functionalFitness)
            context.insert(ffBlock)
            session.addBlockTemplate(ffBlock)

            let prescriptionTemplate = FunctionalFitnessPrescriptionTemplate(
                stimulus: configuration.targetStimulus,
                format: configuration.format,
                requiresRecentExposureToProgress: configuration.requiresRecentExposureToProgress,
                varianceConstraints: configuration.varianceConstraints
            )
            context.insert(prescriptionTemplate)
            ffBlock.attachFunctionalFitnessPrescriptionTemplate(prescriptionTemplate)

            for movementSlotTemplate in movementSlots(for: configuration.targetStimulus, context: context) {
                prescriptionTemplate.addMovementSlot(movementSlotTemplate)
            }
        }

        return definition
    }

    /// Stage C: one `FunctionalFitnessMovementSlotTemplate` per
    /// `ModalityCount` entry (expanded by its own `count`), each
    /// constrained by that entry's modality and one round-robin-assigned
    /// movement function from `stimulus.movementFunctions` — deterministic,
    /// never a hard-coded exercise (§8).
    private static func movementSlots(for stimulus: Stimulus, context: ModelContext) -> [FunctionalFitnessMovementSlotTemplate] {
        var slots: [FunctionalFitnessMovementSlotTemplate] = []
        var slotIndex = 0
        for modalityCount in stimulus.movementModalityMix {
            for _ in 0..<modalityCount.count {
                let assignedFunction: MovementFunction? = stimulus.movementFunctions.isEmpty
                    ? nil
                    : stimulus.movementFunctions[slotIndex % stimulus.movementFunctions.count]

                let slot = ExerciseSlot(
                    name: "\(modalityCount.modality.rawValue) slot \(slotIndex + 1)",
                    allowedMovementFunctions: assignedFunction.map { [$0] } ?? [],
                    allowedModalities: [modalityCount.modality]
                )
                context.insert(slot)

                let movementSlotTemplate = FunctionalFitnessMovementSlotTemplate(loadingRole: stimulus.loading)
                context.insert(movementSlotTemplate)
                movementSlotTemplate.attachExerciseSlot(slot)
                slots.append(movementSlotTemplate)
                slotIndex += 1
            }
        }
        return slots
    }

    /// §20: strength + metcon composition — a plain, fixed, non-
    /// progressing strength block (5×5), proving composition works
    /// through the existing `Session`/`WorkoutBlock` architecture without
    /// needing any new entity. Deliberately not wired to
    /// `StrengthProgressionEngine`'s full autoregulation/deload machinery
    /// — that's out of scope for what this composition proof needs to
    /// demonstrate.
    private static func addStrengthBlock(to session: TemplateSession, context: ModelContext) {
        let block = WorkoutBlockTemplate(type: .strength)
        context.insert(block)
        session.addBlockTemplate(block)

        let template = PrescriptionTemplate(rules: StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(rmType: .rm5, weekOneFactor: 0.8, laterWeekMultipliers: [1.0, 1.0, 1.0])),
            setCountRule: .fixed(setsByWeek: [5, 5, 5, 5]),
            repGoalSchedule: [.fixedReps(5)]
        ))
        context.insert(template)
        block.addPrescriptionTemplate(template)

        let slot = ExerciseSlot(name: "Squat", allowedTargets: [.quadriceps, .glutes])
        context.insert(slot)
        template.attachExerciseSlot(slot)
    }
}
