import Foundation
import SwiftData

/// The reusable, user-agnostic methodology. Per the handoff's core
/// invariant, a ProgramDefinition must never hold performance data — only
/// TrainingWeek templates, expressed as a structure, not flattened
/// workouts. Deleting a ProgramDefinition must not lose a single logged
/// set; enforced by ProgramInstance's nullify relationship to Sessions.
///
/// No field here may ever store a result, a PR, or anything derived from
/// what a specific user did — see CLAUDE.md rule 2 and
/// `PerformanceProfileContinuityTests.testProgramDefinitionExposesNoPerformanceLookingFields`.
@Model
final class ProgramDefinition {
    @Attribute(.unique) var id: UUID
    var name: String
    var source: ProgramSource
    var lengthWeeks: Int
    var adherenceMode: AdherenceMode
    /// Free-text statement of intent (e.g. "linear hypertrophy, 5 days/week").
    /// A placeholder for the structured progression/substitution/deload
    /// rule set the full import pipeline will produce later.
    var intent: String

    @Relationship(deleteRule: .cascade, inverse: \TrainingWeek.programDefinition)
    var weeks: [TrainingWeek] = []

    init(
        id: UUID = UUID(),
        name: String,
        source: ProgramSource = .builtIn,
        lengthWeeks: Int,
        adherenceMode: AdherenceMode = .strict,
        intent: String = ""
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.lengthWeeks = lengthWeeks
        self.adherenceMode = adherenceMode
        self.intent = intent
    }

    /// The only way application code should attach a TrainingWeek
    /// template. Mutates exactly one side (this array); SwiftData
    /// maintains `week.programDefinition` from the declared inverse.
    func addWeek(_ week: TrainingWeek) {
        week.sortIndex = weeks.count
        weeks.append(week)
    }

    /// Weeks in their persisted, stable order. Never rely on `weeks`'s raw
    /// collection order.
    var orderedWeeks: [TrainingWeek] {
        weeks.sorted { $0.sortIndex < $1.sortIndex }
    }
}
