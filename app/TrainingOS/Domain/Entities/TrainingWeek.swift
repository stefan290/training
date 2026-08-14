import Foundation
import SwiftData

/// A templated week inside a ProgramDefinition. Deliberately minimal in
/// this pass: it proves the Program -> weeks structure and the
/// program-owned deload flag (handoff section on Deload) without
/// implementing session/block templating or the full planning engine.
@Model
final class TrainingWeek {
    @Attribute(.unique) var id: UUID
    var programDefinition: ProgramDefinition?
    /// Stable position among a ProgramDefinition's weeks, assigned by
    /// `ProgramDefinition.addWeek(_:)`.
    var sortIndex: Int
    var isDeload: Bool

    init(id: UUID = UUID(), isDeload: Bool = false) {
        self.id = id
        self.sortIndex = 0
        self.isDeload = isDeload
    }
}
