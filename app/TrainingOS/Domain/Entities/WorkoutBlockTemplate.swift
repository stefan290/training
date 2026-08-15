import Foundation
import SwiftData

/// The template-graph analogue of `WorkoutBlock` — reusable structure
/// only, no execution state (no `status`, no result). Strength content
/// uses `prescriptionTemplates` (Stage 4A); steady-state content uses
/// `steadyStatePrescriptionTemplate` (Stage 4C); interval content uses
/// `intervalPrescriptionTemplate` (Stage 4D addition, closing the gap
/// this doc comment used to flag) — mirroring how `WorkoutBlock` itself
/// already carries one typed relationship per modality rather than a
/// generic slot. Functional-fitness template equivalents remain a
/// Stage 4E extension, not built here — see `type`'s doc comment.
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

    /// `ActivitySelectionOverride`'s required inverse — nothing reads
    /// this collection. Stage 4D addition: moved here from
    /// `SteadyStatePrescriptionTemplate` (see `ActivitySelectionOverride`'s
    /// own "Stage 4D correction" doc comment) once a second endurance
    /// template type needed the same override mechanism.
    @Relationship(deleteRule: .nullify, inverse: \ActivitySelectionOverride.templateBlock)
    var activitySelectionOverrides: [ActivitySelectionOverride] = []

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
