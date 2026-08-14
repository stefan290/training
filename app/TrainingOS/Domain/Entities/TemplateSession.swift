import Foundation
import SwiftData

/// The template-graph analogue of `Session` — one reusable training-day
/// slot in a `ProgramDefinition`'s recurring weekly structure, not a
/// dated, executable occasion. Attaches directly to `ProgramDefinition`
/// (not to an individual `TrainingWeek`) because the week-by-week
/// progression already lives on `PrescriptionTemplate`'s rule arrays —
/// see `TrainingWeek`'s doc comment for why one shared structure, not one
/// per week, is correct. Becomes a real `Session` only when a
/// `ProgramInstance` is materialized from the template.
@Model
final class TemplateSession {
    @Attribute(.unique) var id: UUID
    var programDefinition: ProgramDefinition?
    /// Stable position among a program's session templates, assigned by
    /// `ProgramDefinition.addTemplateSession(_:)`.
    var sortIndex: Int
    var name: String
    var role: SessionRole?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutBlockTemplate.templateSession)
    var blockTemplates: [WorkoutBlockTemplate] = []

    init(id: UUID = UUID(), name: String, role: SessionRole? = nil) {
        self.id = id
        self.sortIndex = 0
        self.name = name
        self.role = role
    }

    /// The only way application code should attach a `WorkoutBlockTemplate`.
    /// Mutates exactly one side (this array); SwiftData maintains
    /// `block.templateSession` from the declared inverse.
    func addBlockTemplate(_ block: WorkoutBlockTemplate) {
        block.sortIndex = blockTemplates.count
        blockTemplates.append(block)
    }

    var orderedBlockTemplates: [WorkoutBlockTemplate] {
        blockTemplates.sorted { $0.sortIndex < $1.sortIndex }
    }
}
