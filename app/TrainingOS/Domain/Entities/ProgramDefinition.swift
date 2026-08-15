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

    /// Stage 4 additions — which generator produced this definition, at
    /// what version, and where its numbers trace back to. `nil` for every
    /// pre-Stage-4 `ProgramDefinition` (hand-authored Stage 1-2 seed data),
    /// which is a legal, permanent state, not a migration gap to fill in.
    /// Once a `ProgramInstance` exists against a given `ProgramDefinition`,
    /// that definition's template graph is treated as frozen by convention
    /// — if a generator's logic changes, it produces a new
    /// `ProgramDefinition`/`generatorVersion`, never mutates this one in
    /// place (Stage 4 architecture: "an old configuration must NOT
    /// suddenly produce a different program structure").
    var programmingSystem: ProgrammingSystemKind?
    var generatorVersion: Int?
    var provenance: ProgramProvenance?
    /// Only set when `programmingSystem == .hypertrophy`. `powerliftingConfiguration`
    /// below is the sibling field for `.powerlifting`, not a shared/generic
    /// blob — the same pattern as `WorkoutBlock`'s typed per-modality
    /// prescriptions.
    var hypertrophyConfiguration: HypertrophyProgramConfiguration?
    /// Only set when `programmingSystem == .powerlifting`.
    var powerliftingConfiguration: PowerliftingProgramConfiguration?
    /// Only set when `programmingSystem == .steadyState`.
    var steadyStateConfiguration: SteadyStateProgramConfiguration?

    @Relationship(deleteRule: .cascade, inverse: \TrainingWeek.programDefinition)
    var weeks: [TrainingWeek] = []

    /// Stage 4 addition: the reusable weekly session structure — see
    /// `TrainingWeek`'s doc comment for why this hangs off
    /// `ProgramDefinition` directly rather than off each individual week.
    /// Cascade: a `TemplateSession` has no independent meaning outside its
    /// program.
    @Relationship(deleteRule: .cascade, inverse: \TemplateSession.programDefinition)
    var templateSessions: [TemplateSession] = []

    /// Nullify, not cascade: a ProgramInstance (and everything under it —
    /// Sessions, SetResults, PersonalRecords) must survive the deletion of
    /// the ProgramDefinition it was built from. `inverse:` is required here
    /// even though nothing reads this array — SwiftData needs a declared
    /// inverse on both sides of a relationship to run the delete rule
    /// correctly; without it, deleting a ProgramDefinition referenced by an
    /// active ProgramInstance produced a Core Data validation error instead
    /// of a clean nullify (caught by
    /// `DeleteRuleMatrixTests.testDeletingProgramDefinitionPreservesPerformanceHistory`).
    @Relationship(deleteRule: .nullify, inverse: \ProgramInstance.programDefinition)
    var instances: [ProgramInstance] = []

    init(
        id: UUID = UUID(),
        name: String,
        source: ProgramSource = .builtIn,
        lengthWeeks: Int,
        adherenceMode: AdherenceMode = .strict,
        intent: String = "",
        programmingSystem: ProgrammingSystemKind? = nil,
        generatorVersion: Int? = nil,
        provenance: ProgramProvenance? = nil,
        hypertrophyConfiguration: HypertrophyProgramConfiguration? = nil,
        powerliftingConfiguration: PowerliftingProgramConfiguration? = nil,
        steadyStateConfiguration: SteadyStateProgramConfiguration? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.lengthWeeks = lengthWeeks
        self.adherenceMode = adherenceMode
        self.intent = intent
        self.programmingSystem = programmingSystem
        self.generatorVersion = generatorVersion
        self.provenance = provenance
        self.hypertrophyConfiguration = hypertrophyConfiguration
        self.powerliftingConfiguration = powerliftingConfiguration
        self.steadyStateConfiguration = steadyStateConfiguration
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

    /// The only way application code should attach a `TemplateSession`.
    /// Mutates exactly one side (this array); SwiftData maintains
    /// `session.programDefinition` from the declared inverse.
    func addTemplateSession(_ session: TemplateSession) {
        session.sortIndex = templateSessions.count
        templateSessions.append(session)
    }

    var orderedTemplateSessions: [TemplateSession] {
        templateSessions.sorted { $0.sortIndex < $1.sortIndex }
    }
}
