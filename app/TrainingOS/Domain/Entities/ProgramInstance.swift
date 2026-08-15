import Foundation
import SwiftData

/// This user's execution of a ProgramDefinition inside a specific Phase.
/// Holds dates and progress state — never performance data, which lives
/// permanently in PerformanceProfile regardless of which instance produced
/// it. Sessions relate back with `.nullify` so ending, replacing or
/// deleting an instance can never delete history.
@Model
final class ProgramInstance {
    @Attribute(.unique) var id: UUID
    /// The delete rule that matters lives on `ProgramDefinition.instances`
    /// (see DELETE_RULE_MATRIX.md) — this side is a plain inverse property,
    /// same pattern as `TrainingWeek.programDefinition`.
    var programDefinition: ProgramDefinition?
    var phase: TrainingPhase?
    var ownerUserID: UUID
    var startDate: Date
    var adherenceModeOverride: AdherenceMode?
    var status: PhaseStatus
    /// Stage 3C addition: which system wins scheduling conflicts within
    /// its Phase — defaults to `.primary` so every pre-existing call site
    /// (Stage 1-2 seed data, all current tests) is unaffected. Set
    /// `.secondary` explicitly when attaching a Module alongside a
    /// primary instance — see `TrainingPhase.primaryInstance`/
    /// `.secondaryInstances` below.
    var priority: GoalPriority

    @Relationship(deleteRule: .nullify, inverse: \Session.programInstance)
    var sessions: [Session] = []

    /// Stage 4C addition: the GOING FORWARD substitution state for this
    /// instance's slots — cascade, unlike `sessions` above, because this
    /// is pure instance-specific preference state, not performance
    /// history; deleting the instance has nothing left worth preserving
    /// here (contrast with `sessions`, which survive via `.nullify`
    /// because they hold real logged history). See
    /// `SlotSelectionOverride`'s own doc comment.
    @Relationship(deleteRule: .cascade, inverse: \SlotSelectionOverride.programInstance)
    var slotSelectionOverrides: [SlotSelectionOverride] = []

    /// Stage 4C addition: the endurance/activity sibling of
    /// `slotSelectionOverrides` above — see `ActivitySelectionOverride`'s
    /// own doc comment for why this is a separate, single-purpose type
    /// rather than one entity awkwardly covering both Exercise- and
    /// ActivityType-scoped selections.
    @Relationship(deleteRule: .cascade, inverse: \ActivitySelectionOverride.programInstance)
    var activitySelectionOverrides: [ActivitySelectionOverride] = []

    init(
        id: UUID = UUID(),
        ownerUserID: UUID,
        startDate: Date = Date(),
        adherenceModeOverride: AdherenceMode? = nil,
        status: PhaseStatus = .active,
        priority: GoalPriority = .primary
    ) {
        self.id = id
        self.ownerUserID = ownerUserID
        self.startDate = startDate
        self.adherenceModeOverride = adherenceModeOverride
        self.status = status
        self.priority = priority
    }

    /// The only way application code should attach a Session to a
    /// ProgramInstance. Mutates exactly one side (this array); SwiftData
    /// maintains `session.programInstance` from the declared inverse. A
    /// Session logged ad hoc simply never has this called — the
    /// relationship stays nil, which is a valid, supported state.
    func addSession(_ session: Session) {
        sessions.append(session)
    }

    /// The only way application code should attach a
    /// `SlotSelectionOverride`. Mutates exactly one side (this array);
    /// SwiftData maintains `override.programInstance` from the declared
    /// inverse.
    func addSlotSelectionOverride(_ override: SlotSelectionOverride) {
        slotSelectionOverrides.append(override)
    }

    /// The only way application code should attach an
    /// `ActivitySelectionOverride`. Mutates exactly one side; SwiftData
    /// maintains the declared inverse.
    func addActivitySelectionOverride(_ override: ActivitySelectionOverride) {
        activitySelectionOverrides.append(override)
    }

    /// The single authoritative GOING FORWARD override for a slot, if one
    /// exists — never more than one per slot (`SubstituteExerciseUseCase`
    /// enforces this at write time), so first-match is unambiguous.
    func slotSelectionOverride(for slot: ExerciseSlot) -> SlotSelectionOverride? {
        slotSelectionOverrides.first { $0.templateSlot?.id == slot.id }
    }

    /// The single authoritative GOING FORWARD activity override for an
    /// endurance block template (steady-state or interval), if one
    /// exists. Stage 4D: keyed by `WorkoutBlockTemplate` rather than a
    /// specific endurance template type — see `ActivitySelectionOverride`'s
    /// own "Stage 4D correction" doc comment.
    func activitySelectionOverride(for templateBlock: WorkoutBlockTemplate) -> ActivitySelectionOverride? {
        activitySelectionOverrides.first { $0.templateBlock?.id == templateBlock.id }
    }
}
