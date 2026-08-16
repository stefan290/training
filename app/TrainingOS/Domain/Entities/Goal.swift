import Foundation
import SwiftData

/// What the user wants to achieve. One primary at a time, optional
/// secondaries — see handoff section 2.
///
/// Stage 5B extends this compositionally (`STRATEGIC_PLAN_MODEL.md` §1):
/// `secondaryTypes: [GoalType]` became `secondaryObjectives:
/// [SecondaryObjective]` (a strict superset — `.map(\.type)` recovers
/// the old list), and three fields were added
/// (`milestoneDate`/`bodyCompositionDirection`/`preferences`). No new
/// `GoalType` case was needed for any required objective family.
@Model
final class Goal {
    @Attribute(.unique) var id: UUID
    /// Denormalised for query scoping per handoff section 12 ("scoping
    /// every query to userId"), in addition to the `user` relationship.
    var ownerUserID: UUID

    var user: User?
    var primaryType: GoalType
    var secondaryObjectives: [SecondaryObjective]
    var targetDate: Date?
    /// An intermediate date the user needs to look/perform a certain way
    /// BY — distinct from `targetDate` (the plan's own horizon end).
    /// `STRATEGIC_PLAN_MODEL.md` §3.
    var milestoneDate: Date?
    /// Independent of `primaryType` — a `.generalStrength` primary
    /// objective can still carry a `.loseFat` direction.
    var bodyCompositionDirection: BodyCompositionDirection?
    /// `nil` means no stated preference context yet — every planner call
    /// degrades to coarser recommendations, it never fails.
    var preferences: GoalPreferences?
    var createdAt: Date
    var status: GoalStatus

    @Relationship(deleteRule: .cascade, inverse: \TrainingPlan.goal)
    var plans: [TrainingPlan] = []

    init(
        id: UUID = UUID(),
        ownerUserID: UUID,
        primaryType: GoalType,
        secondaryObjectives: [SecondaryObjective] = [],
        targetDate: Date? = nil,
        milestoneDate: Date? = nil,
        bodyCompositionDirection: BodyCompositionDirection? = nil,
        preferences: GoalPreferences? = nil,
        createdAt: Date = Date(),
        status: GoalStatus = .active
    ) {
        self.id = id
        self.ownerUserID = ownerUserID
        self.primaryType = primaryType
        self.secondaryObjectives = secondaryObjectives
        self.targetDate = targetDate
        self.milestoneDate = milestoneDate
        self.bodyCompositionDirection = bodyCompositionDirection
        self.preferences = preferences
        self.createdAt = createdAt
        self.status = status
    }

    /// The only way application code should attach a TrainingPlan to a
    /// Goal. Mutates exactly one side (this array); SwiftData maintains
    /// `plan.goal` from the declared inverse.
    func addPlan(_ plan: TrainingPlan) {
        plans.append(plan)
    }
}
