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
    /// Stage 4C addition: frequency progression, modeled at the correct
    /// architecture level (Stage 4C §7-8). A program whose session count
    /// increases partway through a mesocycle (e.g. 3x/week -> 4x/week)
    /// does *not* get a second copy of the recurring weekly structure —
    /// it gets one additional `TemplateSession` whose `activeFromWeek` is
    /// the (0-indexed) week it joins the rotation. `0` (the default) means
    /// "part of the structure from week 1," which is every pre-Stage-4C
    /// `TemplateSession` and every Family A/B/C session unchanged.
    /// Deliberately **not** a `BlockProgressionEngine` concern: frequency
    /// is how many Sessions exist in a week, a `TemplateSession`/program
    /// property, not a within-block dimension any single block's engine
    /// could express without being distorted into something it isn't
    /// (`STAGE4_IMPLEMENTATION_REPORT.md`'s Stage 4C section documents
    /// this boundary explicitly). Materializers filter on this field when
    /// building a given week: `orderedTemplateSessions.filter { $0.activeFromWeek <= weekIndex }`.
    var activeFromWeek: Int

    @Relationship(deleteRule: .cascade, inverse: \WorkoutBlockTemplate.templateSession)
    var blockTemplates: [WorkoutBlockTemplate] = []

    init(id: UUID = UUID(), name: String, role: SessionRole? = nil, activeFromWeek: Int = 0) {
        self.id = id
        self.sortIndex = 0
        self.name = name
        self.role = role
        self.activeFromWeek = activeFromWeek
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
