import Foundation
import SwiftData

/// A proposed-or-active route toward a Goal: an ordered set of Phases.
/// Mirrors the Plan state model in handoff section 3 — DRAFT is a proposal
/// where nothing else has been saved, ACTIVE is the one currently followed,
/// SUPERSEDED is replaced history that is kept, not deleted.
@Model
final class TrainingPlan {
    @Attribute(.unique) var id: UUID
    var goal: Goal?
    var status: PlanStatus
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TrainingPhase.plan)
    var phases: [TrainingPhase] = []

    init(id: UUID = UUID(), status: PlanStatus = .draft, createdAt: Date = Date()) {
        self.id = id
        self.status = status
        self.createdAt = createdAt
    }

    /// The only way application code should attach a TrainingPhase to a
    /// Plan. Mutates exactly one side (this array); SwiftData maintains
    /// `phase.plan` from the declared inverse.
    func addPhase(_ phase: TrainingPhase) {
        phase.sortIndex = phases.count
        phases.append(phase)
    }

    /// Phases in their persisted, stable order. Never rely on `phases`'s
    /// raw collection order.
    var orderedPhases: [TrainingPhase] {
        phases.sorted { $0.sortIndex < $1.sortIndex }
    }
}
