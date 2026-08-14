import Foundation
import SwiftData

/// Account identity only. Training preferences live on `UserProfile`, kept
/// separate so identity and mutable training settings can evolve
/// independently (e.g. multiple profiles per account, later).
@Model
final class User {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \UserProfile.user)
    var profile: UserProfile?

    @Relationship(deleteRule: .cascade, inverse: \PerformanceProfile.user)
    var performanceProfile: PerformanceProfile?

    @Relationship(deleteRule: .cascade, inverse: \Goal.user)
    var goals: [Goal] = []

    init(id: UUID = UUID(), displayName: String, createdAt: Date = Date()) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
    }

    /// The only way application code should attach a UserProfile. Mutates
    /// exactly one side (`profile`); SwiftData maintains `profile.user`
    /// from the declared inverse.
    func attachProfile(_ profile: UserProfile) {
        self.profile = profile
    }

    /// The only way application code should attach a PerformanceProfile.
    /// Mutates exactly one side (`performanceProfile`); SwiftData
    /// maintains `performanceProfile.user` from the declared inverse.
    func attachPerformanceProfile(_ performanceProfile: PerformanceProfile) {
        self.performanceProfile = performanceProfile
    }

    /// The only way application code should attach a Goal. Mutates
    /// exactly one side (this array); SwiftData maintains `goal.user` from
    /// the declared inverse.
    func addGoal(_ goal: Goal) {
        goals.append(goal)
    }
}
