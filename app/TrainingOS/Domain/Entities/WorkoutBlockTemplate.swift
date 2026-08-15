import Foundation
import SwiftData

/// The template-graph analogue of `WorkoutBlock` — reusable structure
/// only, no execution state (no `status`, no result). Strength content
/// uses `prescriptionTemplates` (Stage 4A); steady-state content uses
/// `steadyStatePrescriptionTemplate` (Stage 4C addition, closing the gap
/// this doc comment used to flag) — mirroring how `WorkoutBlock` itself
/// already carries one typed relationship per modality rather than a
/// generic slot. Interval/functional-fitness template equivalents remain
/// a Stage 4D/E extension, not built here — see `type`'s doc comment.
@Model
final class WorkoutBlockTemplate {
    @Attribute(.unique) var id: UUID
    var templateSession: TemplateSession?
    /// Stable position among a session template's blocks, assigned by
    /// `TemplateSession.addBlockTemplate(_:)`.
    var sortIndex: Int
    /// Reuses the existing modality-agnostic `WorkoutBlockType` — Stage 4A
    /// only ever sets `.hypertrophy`/`.strength`/`.accessory`, Stage 4C
    /// adds `.steadyState`, but nothing here restricts future systems from
    /// using their own cases.
    var type: WorkoutBlockType

    @Relationship(deleteRule: .cascade, inverse: \PrescriptionTemplate.workoutBlockTemplate)
    var prescriptionTemplates: [PrescriptionTemplate] = []

    /// Cascade: a `SteadyStatePrescriptionTemplate` has no independent
    /// meaning outside its block template, exactly like
    /// `prescriptionTemplates` above.
    @Relationship(deleteRule: .cascade, inverse: \SteadyStatePrescriptionTemplate.workoutBlockTemplate)
    var steadyStatePrescriptionTemplate: SteadyStatePrescriptionTemplate?

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

    var orderedPrescriptionTemplates: [PrescriptionTemplate] {
        prescriptionTemplates.sorted { $0.sortIndex < $1.sortIndex }
    }
}
