import Foundation
import SwiftData

/// Any template-graph child of `WorkoutBlockTemplate` that offers
/// activity-substitution eligibility — implemented by
/// `SteadyStatePrescriptionTemplate` and `IntervalPrescriptionTemplate`
/// (Stage 4D addition). Lets `ActivitySelectionOverride`/
/// `SubstituteActivityUseCase` stay generic over both systems without a
/// second near-duplicate override entity.
protocol ActivitySubstitutionTemplate: AnyObject {
    var preferredActivityType: ActivityType { get }
    var allowedActivityTypes: [ActivityType] { get }
}

/// The endurance/activity sibling of `SlotSelectionOverride` — the GOING
/// FORWARD half of Stage 4C §34's endurance substitution model.
/// Deliberately a separate, single-purpose type rather than one entity
/// covering both Exercise- and ActivityType-scoped selections with
/// nullable dual-purpose columns (item 57's "nullable mega-entity"
/// smell): a strength slot's template object is an `ExerciseSlot`
/// selecting an `Exercise`; an endurance block's template object selects
/// an `ActivityType` — genuinely different template object types and
/// selection value types, not two views of the same fact.
///
/// **Stage 4D correction:** originally keyed directly to
/// `SteadyStatePrescriptionTemplate` (the only endurance template type
/// that existed in Stage 4C). Now keyed to the owning
/// `WorkoutBlockTemplate` instead, since Stage 4D adds a second endurance
/// template type (`IntervalPrescriptionTemplate`) that also needs GOING
/// FORWARD activity substitution — `WorkoutBlockTemplate` is the one
/// object both template types already hang off of, so this is the
/// smaller, cleaner fix, not a parallel `IntervalActivitySelectionOverride`
/// duplicate entity. Made before any Stage 4D generator/materializer code
/// was written against the old shape, exactly the Stage 4A/4B discipline
/// of correcting a schema mistake before it ships, not working around it.
///
/// THIS SESSION ONLY endurance substitution is, exactly like the strength
/// side, not modeled as a persisted type at all — it's a direct edit of an
/// already-materialized `SteadyStatePrescription`/`IntervalPrescription`'s
/// `activityType` for one Session.
@Model
final class ActivitySelectionOverride {
    @Attribute(.unique) var id: UUID
    var programInstance: ProgramInstance?
    /// Real declared inverse (`WorkoutBlockTemplate` genuinely gets
    /// deleted when its `ProgramDefinition` is), same reasoning as
    /// `SlotSelectionOverride.templateSlot`.
    var templateBlock: WorkoutBlockTemplate?
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
