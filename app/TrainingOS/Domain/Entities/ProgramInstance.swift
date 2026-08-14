import Foundation
import SwiftData

/// This user's execution of a ProgramDefinition inside a specific Phase.
/// Holds dates and progress state — never performance data, which lives
/// permanently in PerformanceProfile regardless of which instance produced
/// it. Sessions relate back with `.nullify` so ending, replacing or
/// deleting an instance can never delete history.
@Model
final class ProgramInstance {
    @Attribute(.unique) var id: UUID
    /// The delete rule that matters lives on `ProgramDefinition.instances`
    /// (see DELETE_RULE_MATRIX.md) — this side is a plain inverse property,
    /// same pattern as `TrainingWeek.programDefinition`.
    var programDefinition: ProgramDefinition?
    var phase: TrainingPhase?
    var ownerUserID: UUID
    var startDate: Date
    var adherenceModeOverride: AdherenceMode?
    var status: PhaseStatus
    /// Stage 3C addition: which system wins scheduling conflicts within
    /// its Phase — defaults to `.primary` so every pre-existing call site
    /// (Stage 1-2 seed data, all current tests) is unaffected. Set
    /// `.secondary` explicitly when attaching a Module alongside a
    /// primary instance — see `TrainingPhase.primaryInstance`/
    /// `.secondaryInstances` below.
    var priority: GoalPriority

    @Relationship(deleteRule: .nullify, inverse: \Session.programInstance)
    var sessions: [Session] = []

    init(
        id: UUID = UUID(),
        ownerUserID: UUID,
        startDate: Date = Date(),
        adherenceModeOverride: AdherenceMode? = nil,
        status: PhaseStatus = .active,
        priority: GoalPriority = .primary
    ) {
        self.id = id
        self.ownerUserID = ownerUserID
        self.startDate = startDate
        self.adherenceModeOverride = adherenceModeOverride
        self.status = status
        self.priority = priority
    }

    /// The only way application code should attach a Session to a
    /// ProgramInstance. Mutates exactly one side (this array); SwiftData
    /// maintains `session.programInstance` from the declared inverse. A
    /// Session logged ad hoc simply never has this called — the
    /// relationship stays nil, which is a valid, supported state.
    func addSession(_ session: Session) {
        sessions.append(session)
    }
}
