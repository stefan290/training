import Foundation
import SwiftData

/// Which adaptation is prioritised over a period, and the scheduling
/// priority rule that follows from it. Owns at most one active
/// ProgramInstance at a time via a nullify relationship: ending or deleting
/// a Phase must never delete the ProgramInstance's history.
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
    /// `instance.phase` from the declared inverse.
    func addProgramInstance(_ instance: ProgramInstance) {
        programInstances.append(instance)
    }
}
