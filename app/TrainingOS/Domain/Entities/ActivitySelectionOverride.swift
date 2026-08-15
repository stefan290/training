import Foundation
import SwiftData

/// The endurance/activity sibling of `SlotSelectionOverride` — the GOING
/// FORWARD half of Stage 4C §34's endurance substitution model. Deliberately
/// a separate, single-purpose type rather than one entity covering both
/// Exercise- and ActivityType-scoped selections with nullable dual-purpose
/// columns (item 57's "nullable mega-entity" smell): a strength slot's
/// template object is an `ExerciseSlot` selecting an `Exercise`; a
/// steady-state block's template object is a `SteadyStatePrescriptionTemplate`
/// selecting an `ActivityType` — genuinely different template object types
/// and selection value types, not two views of the same fact.
///
/// THIS SESSION ONLY endurance substitution is, exactly like the strength
/// side, not modeled as a persisted type at all — it's a direct edit of an
/// already-materialized `SteadyStateResult`/`SteadyStatePrescription`'s
/// `activityType` for one Session (see `SteadyStatePrescription`'s own
/// Stage 4C addition).
@Model
final class ActivitySelectionOverride {
    @Attribute(.unique) var id: UUID
    var programInstance: ProgramInstance?
    /// Real declared inverse (`SteadyStatePrescriptionTemplate` genuinely
    /// gets deleted when its `ProgramDefinition` is), same reasoning as
    /// `SlotSelectionOverride.templateSlot`.
    var templateSteadyState: SteadyStatePrescriptionTemplate?
    var selectedActivityType: ActivityType
    var reason: SubstitutionReason?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        selectedActivityType: ActivityType,
        reason: SubstitutionReason? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.selectedActivityType = selectedActivityType
        self.reason = reason
        self.createdAt = createdAt
    }
}
