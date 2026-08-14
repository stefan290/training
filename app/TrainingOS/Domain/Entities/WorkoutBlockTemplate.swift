import Foundation
import SwiftData

/// The template-graph analogue of `WorkoutBlock` — reusable structure
/// only, no execution state (no `status`, no result). Scoped to strength
/// content for Stage 4A (`prescriptionTemplates`); steady-state/interval/
/// functional-fitness template equivalents are a Stage 4C/D/E extension,
/// not built here — see `type`'s doc comment.
@Model
final class WorkoutBlockTemplate {
    @Attribute(.unique) var id: UUID
    var templateSession: TemplateSession?
    /// Stable position among a session template's blocks, assigned by
    /// `TemplateSession.addBlockTemplate(_:)`.
    var sortIndex: Int
    /// Reuses the existing modality-agnostic `WorkoutBlockType` — Stage 4A
    /// only ever sets `.hypertrophy`/`.strength`/`.accessory`, but nothing
    /// here restricts future systems from using their own cases.
    var type: WorkoutBlockType

    @Relationship(deleteRule: .cascade, inverse: \PrescriptionTemplate.workoutBlockTemplate)
    var prescriptionTemplates: [PrescriptionTemplate] = []

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

    var orderedPrescriptionTemplates: [PrescriptionTemplate] {
        prescriptionTemplates.sorted { $0.sortIndex < $1.sortIndex }
    }
}
