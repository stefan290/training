import Foundation
import SwiftData

/// What the user wants to achieve. One primary at a time, optional
/// secondaries — see handoff section 2.
@Model
final class Goal {
    @Attribute(.unique) var id: UUID
    /// Denormalised for query scoping per handoff section 12 ("scoping
    /// every query to userId"), in addition to the `user` relationship.
    var ownerUserID: UUID

    var user: User?
    var primaryType: GoalType
    var secondaryTypes: [GoalType]
    var targetDate: Date?
    var createdAt: Date
    var status: GoalStatus

    @Relationship(deleteRule: .cascade, inverse: \TrainingPlan.goal)
    var plans: [TrainingPlan] = []

    init(
        id: UUID = UUID(),
        ownerUserID: UUID,
        primaryType: GoalType,
        secondaryTypes: [GoalType] = [],
        targetDate: Date? = nil,
        createdAt: Date = Date(),
        status: GoalStatus = .active
    ) {
        self.id = id
        self.ownerUserID = ownerUserID
        self.primaryType = primaryType
        self.secondaryTypes = secondaryTypes
        self.targetDate = targetDate
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
