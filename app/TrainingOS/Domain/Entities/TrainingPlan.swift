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

    /// Stage 5B revision lineage (`PLAN_REVISION_MODEL.md` §4): the
    /// immediately-prior revision this one replaced, or `nil` for the
    /// first revision of a lineage. Nullify — a superseded plan's own
    /// history must never be deleted just because a later revision
    /// pointing at it is.
    var supersedes: TrainingPlan?
    /// Shared by every revision of "the same evolving roadmap" — a
    /// fresh UUID only when a genuinely new strategic intent begins
    /// (e.g. a full long-term-goal change), copied forward from
    /// `supersedes.lineageID` for an ordinary revision (extend/shorten/
    /// milestone change). Gives an O(1) "every revision of this roadmap"
    /// query without walking the `supersedes` chain.
    var lineageID: UUID

    @Relationship(deleteRule: .cascade, inverse: \TrainingPhase.plan)
    var phases: [TrainingPhase] = []

    init(
        id: UUID = UUID(),
        status: PlanStatus = .draft,
        createdAt: Date = Date(),
        supersedes: TrainingPlan? = nil,
        lineageID: UUID? = nil
    ) {
        self.id = id
        self.status = status
        self.createdAt = createdAt
        self.supersedes = supersedes
        // Defaults to a fresh lineage (a brand-new UUID) unless the
        // caller explicitly continues an existing one — this makes "new
        // lineage" the safe default for ordinary construction, and
        // "same lineage" an explicit, deliberate choice at the one call
        // site (a minor revision) that needs it.
        self.lineageID = lineageID ?? UUID()
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
