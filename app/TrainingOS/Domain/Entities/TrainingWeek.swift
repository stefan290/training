import Foundation
import SwiftData

/// A templated week inside a ProgramDefinition. Deliberately minimal,
/// unchanged since Stage 1-2: just the Program -> weeks structure and the
/// program-owned deload flag. **Not a session-structure container** —
/// Family A's own rules (`RMBasedLoad.laterWeekMultipliers`,
/// `StrengthProgressionRules.repGoalSchedule`) already express a whole
/// mesocycle's week-by-week progression as arrays on a *single*
/// `PrescriptionTemplate`, and deload behavior is a rule
/// (`deloadWeightAction`/`deloadRepAction`) resolved by `isDeload`, not a
/// separately-templated week. Duplicating the session/block/prescription
/// graph once per `TrainingWeek` would be redundant with that design and
/// was corrected during Stage 4A's own implementation before it shipped —
/// see `ProgramDefinition.templateSessions` for where the one recurring
/// weekly structure actually lives.
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
