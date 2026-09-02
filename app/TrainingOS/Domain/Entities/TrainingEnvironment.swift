import Foundation
import SwiftData

/// Stage TE.1: a named, user-authored set of equipment actually available
/// wherever the user trains (e.g. "Home Gym" -> `[.dumbbells, .bench]`,
/// "Commercial Gym" -> everything). Reuses `EquipmentRequirement` as-is —
/// no new equipment vocabulary. Compared against an `Exercise`'s or
/// `ActivityType`'s `requiredEquipment` by `TrainingEnvironmentCompatibilityRule`,
/// never by any other ad hoc comparison.
@Model
final class TrainingEnvironment {
    @Attribute(.unique) var id: UUID
    var name: String
    var availableEquipment: [EquipmentRequirement]
    var userProfile: UserProfile?

    /// `Session.materializedInEnvironment`'s required inverse — nothing
    /// reads this collection. Needed purely so SwiftData's delete-rule
    /// engine has a path to correctly nullify that un-inversed-otherwise
    /// to-one reference when this row is deleted, rather than leaving a
    /// dangling reference to a faulted row — the exact same reasoning as
    /// `Exercise.resolvedSlots`'s own doc comment
    /// (`STAGE10R7A_TX_ROOT_CAUSE_REPORT.md`).
    @Relationship(deleteRule: .nullify, inverse: \Session.materializedInEnvironment)
    var materializedSessions: [Session] = []

    init(id: UUID = UUID(), name: String, availableEquipment: [EquipmentRequirement] = []) {
        self.id = id
        self.name = name
        self.availableEquipment = availableEquipment
    }
}
