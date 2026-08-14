import Foundation
import SwiftData

/// Which adaptation is prioritised over a period, and the scheduling
/// priority rule that follows from it. Ending or deleting a Phase must
/// never delete a ProgramInstance's history — enforced by the `.nullify`
/// relationship below.
///
/// **Stage 3C generalization:** a Phase can now hold one primary
/// `ProgramInstance` plus zero or more secondary ones (Modules) — e.g. a
/// Muscle Gain phase with a primary Hypertrophy instance and a secondary
/// Aerobic Base instance, or a Running phase with a primary Running
/// instance and a secondary Strength Maintenance instance
/// (`ENDURANCE_PROGRAMMING_MODEL.md` §9, `CONCURRENT_SCHEDULER_MODEL.md`
/// §1). This is composition/priority only — `TrainingPhase` still performs
/// no scheduling logic itself; a future `ConcurrentScheduler` reads
/// `primaryInstance`/`secondaryInstances` to decide placement. No new
/// `HybridProgramDefinition`-style type was introduced: this is the same
/// `programInstances` array as before, now readable by priority via the
/// two computed properties below, plus `ProgramInstance.priority` itself.
///
/// **"ProgramJourney" note:** the phase *sequencing* concept explored in
/// Stage 3B docs (`PROGRAMMING_SYSTEM_MODEL.md` §5.1) needed no new
/// entity — `TrainingPlan.orderedPhases` already provides it. This
/// generalization is the one real schema change Stage 3B's validation
/// found necessary, and it lives here, on `TrainingPhase`/`ProgramInstance`,
/// not on a new `ProgramJourney` type.
@Model
final class TrainingPhase {
    @Attribute(.unique) var id: UUID
    var plan: TrainingPlan?
    var type: PhaseType
    /// Stable position among a Plan's phases, assigned by
    /// `TrainingPlan.addPhase(_:)`.
    var sortIndex: Int
    var startDate: Date
    var endDate: Date?
    var priorityRule: TrainingPriority
    var status: PhaseStatus

    /// Nullify, not cascade: deleting a Phase must never delete the
    /// ProgramInstances (and therefore the Sessions and results) that ran
    /// inside it.
    @Relationship(deleteRule: .nullify, inverse: \ProgramInstance.phase)
    var programInstances: [ProgramInstance] = []

    init(
        id: UUID = UUID(),
        type: PhaseType,
        startDate: Date,
        endDate: Date? = nil,
        priorityRule: TrainingPriority,
        status: PhaseStatus = .planned
    ) {
        self.id = id
        self.type = type
        self.sortIndex = 0
        self.startDate = startDate
        self.endDate = endDate
        self.priorityRule = priorityRule
        self.status = status
    }

    /// The only way application code should attach a ProgramInstance to a
    /// Phase. Mutates exactly one side (this array); SwiftData maintains
    /// `instance.phase` from the declared inverse. Does not set
    /// `instance.priority` — set that on the `ProgramInstance` itself
    /// (defaults to `.primary`) before or after calling this.
    func addProgramInstance(_ instance: ProgramInstance) {
        programInstances.append(instance)
    }

    /// The Phase's primary system, if one has been attached. `nil` only
    /// before any instance is added — a Phase with instances but no
    /// `.primary` one is a caller bug, not a valid, silently-tolerated
    /// state, but this property does not crash on it; it simply returns
    /// `nil`, matching the model's general preference for surfacing gaps
    /// via tests rather than runtime traps.
    var primaryInstance: ProgramInstance? {
        programInstances.first { $0.priority == .primary }
    }

    /// Zero or more secondary Modules running alongside the primary
    /// instance this Phase — e.g. an Aerobic Base module alongside a
    /// primary Hypertrophy instance.
    var secondaryInstances: [ProgramInstance] {
        programInstances.filter { $0.priority == .secondary }
    }
}
