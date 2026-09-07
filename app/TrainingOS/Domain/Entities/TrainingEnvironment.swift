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
    /// V1 R5 (Training Environment product reconciliation): `true` only
    /// for the one, automatically-seeded "Full Gym" row
    /// (`AppRootStateResolver.ensureBaselineIdentity`) — never set by any
    /// athlete-facing creation path (`TrainingEnvironmentSettingsView`'s
    /// "Add Environment" always constructs `isBuiltIn: false`). Purely a
    /// UI/product-language signal ("built-in" vs. "custom," and gating
    /// deletion) — `TrainingEnvironmentCompatibilityRule` never reads
    /// this field; a built-in environment is compatible-checked exactly
    /// like any other real environment, never given a bypass.
    var isBuiltIn: Bool

    /// `Session.materializedInEnvironment`'s required inverse — nothing
    /// reads this collection. Needed purely so SwiftData's delete-rule
    /// engine has a path to correctly nullify that un-inversed-otherwise
    /// to-one reference when this row is deleted, rather than leaving a
    /// dangling reference to a faulted row — the exact same reasoning as
    /// `Exercise.resolvedSlots`'s own doc comment
    /// (`STAGE10R7A_TX_ROOT_CAUSE_REPORT.md`).
    @Relationship(deleteRule: .nullify, inverse: \Session.materializedInEnvironment)
    var materializedSessions: [Session] = []

    init(id: UUID = UUID(), name: String, availableEquipment: [EquipmentRequirement] = [], isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.availableEquipment = availableEquipment
        self.isBuiltIn = isBuiltIn
    }

    /// V1 R5: the zero-config default every new athlete effectively
    /// trains in without ever configuring equipment — a broad, well-
    /// equipped normal commercial gym, expressed honestly through the
    /// EXISTING `EquipmentRequirement` taxonomy (never a new equipment
    /// vocabulary, never a bypass of `TrainingEnvironmentCompatibilityRule`).
    /// Disclosed decision: includes every real case in the taxonomy
    /// (barbell/rack/bench/dumbbells/cable station/machine/pull-up bar/
    /// kettlebell/medicine ball/bodyweight/bike/rower/skiErg) — this
    /// taxonomy is deliberately coarse (category presence, never
    /// quantities/ranges/space), and a normal broad commercial gym
    /// plausibly has one of everything in this small list; excluding any
    /// category here would silently degrade normal source-program
    /// materialization for the common, zero-config case this checkpoint
    /// exists to guarantee.
    static func fullGym() -> TrainingEnvironment {
        TrainingEnvironment(name: "Full Gym", availableEquipment: EquipmentRequirement.allCases, isBuiltIn: true)
    }
}
