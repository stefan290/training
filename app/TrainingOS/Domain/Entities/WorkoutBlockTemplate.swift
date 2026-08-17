import Foundation
import SwiftData

/// The template-graph analogue of `WorkoutBlock` — reusable structure
/// only, no execution state (no `status`, no result). Strength content
/// uses `prescriptionTemplates` (Stage 4A); steady-state content uses
/// `steadyStatePrescriptionTemplate` (Stage 4C); interval content uses
/// `intervalPrescriptionTemplate` (Stage 4D); Functional Fitness content
/// uses `functionalFitnessPrescriptionTemplate` (Stage 4E addition,
/// closing the gap this doc comment used to flag) — mirroring how
/// `WorkoutBlock` itself already carries one typed relationship per
/// modality rather than a generic slot.
@Model
final class WorkoutBlockTemplate {
    @Attribute(.unique) var id: UUID
    var templateSession: TemplateSession?
    /// Stable position among a session template's blocks, assigned by
    /// `TemplateSession.addBlockTemplate(_:)`.
    var sortIndex: Int
    /// Reuses the existing modality-agnostic `WorkoutBlockType` — Stage 4A
    /// only ever sets `.hypertrophy`/`.strength`/`.accessory`, Stage 4C
    /// adds `.steadyState`, Stage 4D adds `.intervals`/`.warmup`/`.cooldown`,
    /// but nothing here restricts future systems from using their own
    /// cases.
    var type: WorkoutBlockType

    @Relationship(deleteRule: .cascade, inverse: \PrescriptionTemplate.workoutBlockTemplate)
    var prescriptionTemplates: [PrescriptionTemplate] = []

    /// Cascade: a `SteadyStatePrescriptionTemplate` has no independent
    /// meaning outside its block template, exactly like
    /// `prescriptionTemplates` above.
    @Relationship(deleteRule: .cascade, inverse: \SteadyStatePrescriptionTemplate.workoutBlockTemplate)
    var steadyStatePrescriptionTemplate: SteadyStatePrescriptionTemplate?

    /// Cascade: same reasoning, Stage 4D addition.
    @Relationship(deleteRule: .cascade, inverse: \IntervalPrescriptionTemplate.workoutBlockTemplate)
    var intervalPrescriptionTemplate: IntervalPrescriptionTemplate?

    /// Cascade: same reasoning, Stage 4E addition.
    @Relationship(deleteRule: .cascade, inverse: \FunctionalFitnessPrescriptionTemplate.workoutBlockTemplate)
    var functionalFitnessPrescriptionTemplate: FunctionalFitnessPrescriptionTemplate?

    /// `ActivitySelectionOverride`'s required inverse — nothing reads
    /// this collection. Stage 4D addition: moved here from
    /// `SteadyStatePrescriptionTemplate` (see `ActivitySelectionOverride`'s
    /// own "Stage 4D correction" doc comment) once a second endurance
    /// template type needed the same override mechanism.
    @Relationship(deleteRule: .nullify, inverse: \ActivitySelectionOverride.templateBlock)
    var activitySelectionOverrides: [ActivitySelectionOverride] = []

    /// Stage 6B addition: `SteadyStatePrescription.sourceWorkoutBlockTemplate`'s
    /// required inverse — nothing reads this collection. Lets a live
    /// execution's Change Activity flow trace a materialized steady-state
    /// block back to the template it came from (both its
    /// `ActivitySubstitutionTemplate` for THIS SESSION ONLY validation and
    /// this `WorkoutBlockTemplate` itself for GOING FORWARD), while
    /// `.nullify` keeps the materialized prescription (and any logged
    /// result) intact if this template's `ProgramDefinition` is later
    /// deleted (CLAUDE.md rule 1).
    @Relationship(deleteRule: .nullify, inverse: \SteadyStatePrescription.sourceWorkoutBlockTemplate)
    var materializedSteadyStatePrescriptions: [SteadyStatePrescription] = []

    /// Stage 6B addition — the interval sibling of
    /// `materializedSteadyStatePrescriptions` above, same reasoning.
    @Relationship(deleteRule: .nullify, inverse: \IntervalPrescription.sourceWorkoutBlockTemplate)
    var materializedIntervalPrescriptions: [IntervalPrescription] = []

    init(id: UUID = UUID(), type: WorkoutBlockType) {
        self.id = id
        self.sortIndex = 0
        self.type = type
    }

    /// The only way application code should attach a `PrescriptionTemplate`.
    /// Mutates exactly one side (this array); SwiftData maintains
    /// `template.workoutBlockTemplate` from the declared inverse.
    func addPrescriptionTemplate(_ template: PrescriptionTemplate) {
        template.sortIndex = prescriptionTemplates.count
        prescriptionTemplates.append(template)
    }

    /// The only way application code should attach a
    /// `SteadyStatePrescriptionTemplate`. Mutates exactly one side;
    /// SwiftData maintains the declared inverse.
    func attachSteadyStatePrescriptionTemplate(_ template: SteadyStatePrescriptionTemplate) {
        steadyStatePrescriptionTemplate = template
    }

    /// The only way application code should attach an
    /// `IntervalPrescriptionTemplate`. Mutates exactly one side; SwiftData
    /// maintains the declared inverse.
    func attachIntervalPrescriptionTemplate(_ template: IntervalPrescriptionTemplate) {
        intervalPrescriptionTemplate = template
    }

    /// The only way application code should attach a
    /// `FunctionalFitnessPrescriptionTemplate`. Mutates exactly one side;
    /// SwiftData maintains the declared inverse.
    func attachFunctionalFitnessPrescriptionTemplate(_ template: FunctionalFitnessPrescriptionTemplate) {
        functionalFitnessPrescriptionTemplate = template
    }

    var orderedPrescriptionTemplates: [PrescriptionTemplate] {
        prescriptionTemplates.sorted { $0.sortIndex < $1.sortIndex }
    }

    /// Whichever `ActivitySubstitutionTemplate` (steady-state or interval)
    /// this block template carries, if any — the one lookup
    /// `SubstituteActivityUseCase` needs to stay generic over both.
    var activitySubstitutionTemplate: ActivitySubstitutionTemplate? {
        steadyStatePrescriptionTemplate ?? intervalPrescriptionTemplate
    }
}
