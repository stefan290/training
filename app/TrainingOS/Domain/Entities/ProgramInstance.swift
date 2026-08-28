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
    /// Stage 10R.5, D-10R5-15: this instance's own override of the
    /// profile-level progression-style default (`nil` = defer to
    /// `UserProfile.preferredProgressionStyle`) — same shape as
    /// `adherenceModeOverride` above. Load-first evidence/streak state is
    /// always scoped to one `ProgramInstance` (D-10R5-13: resets at every
    /// new mesocycle boundary), so this override travels with it
    /// naturally rather than needing separate reset plumbing.
    var progressionStyleOverride: ProgressionStyle?

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

    /// Stage 4F addition: `TrainingMixComponent`s that reference this
    /// instance once it has been instantiated from a recommended or
    /// selected `TrainingMix`. Nullify, not cascade — the delete rule
    /// that matters lives here (matching `sessions` above), since a
    /// `TrainingMixComponent` outliving the `ProgramInstance` it once
    /// pointed to (component's `programInstance` simply goes back to
    /// `nil`) is far safer than deleting an instance and losing the
    /// only inverse Swift-Data needs to keep `programInstance` from
    /// crashing on a to-one reference to a deletable type.
    @Relationship(deleteRule: .nullify, inverse: \TrainingMixComponent.programInstance)
    var trainingMixComponents: [TrainingMixComponent] = []

    /// Stage 7 addition: `PlannerDecision.programInstance`'s required
    /// inverse — nothing reads this collection. Same reasoning as
    /// `trainingMixComponents` above: an un-inversed to-one reference to
    /// a type that genuinely gets deleted (this one, unlike `Goal`/
    /// `TrainingPlan`) crashes instead of nullifying cleanly on delete —
    /// confirmed by this pass's own deletion-invariant test. `.nullify`
    /// keeps the audit-trail row itself intact (never cascaded away)
    /// while letting it simply lose its instance reference, matching
    /// `PlannerDecision`'s own doc comment: every back-reference is
    /// optional, set only when relevant.
    @Relationship(deleteRule: .nullify, inverse: \PlannerDecision.programInstance)
    var plannerDecisions: [PlannerDecision] = []

    /// Stage 10R.1C addition: the explicit source-RM-calibration state for
    /// this instance's `.rmBased` slots — see `SourceRMCalibration`'s own
    /// doc comment. Cascade, like `slotSelectionOverrides` — this is
    /// instance-specific setup state, not permanent performance history;
    /// deleting the instance leaves nothing worth preserving here (a fresh
    /// instance needs fresh calibration anyway, per the source's own
    /// never-carried-over rule).
    @Relationship(deleteRule: .cascade, inverse: \SourceRMCalibration.programInstance)
    var sourceRMCalibrations: [SourceRMCalibration] = []

    init(
        id: UUID = UUID(),
        ownerUserID: UUID,
        startDate: Date = Date(),
        adherenceModeOverride: AdherenceMode? = nil,
        status: PhaseStatus = .active,
        priority: GoalPriority = .primary,
        progressionStyleOverride: ProgressionStyle? = nil
    ) {
        self.id = id
        self.ownerUserID = ownerUserID
        self.startDate = startDate
        self.adherenceModeOverride = adherenceModeOverride
        self.progressionStyleOverride = progressionStyleOverride
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

    /// Stage 10R.1C addition: the only way application code should attach
    /// a `SourceRMCalibration`. Mutates exactly one side; SwiftData
    /// maintains the declared inverse.
    func addSourceRMCalibration(_ calibration: SourceRMCalibration) {
        sourceRMCalibrations.append(calibration)
    }

    /// This instance's calibration for `(exercise, rmType)`, if one has
    /// been entered — `nil` means genuinely not yet calibrated (never a
    /// guessed value). Identity is `(programInstance, exercise, rmType)`
    /// exactly — never keyed by slot/template (`STAGE10R1C_SOURCE_RM_CALIBRATION_DESIGN.md`
    /// Decision 1): the same exercise appearing in multiple slots that
    /// require the identical `RMType` is satisfied by one entry.
    func sourceRMCalibration(for exercise: Exercise, rmType: RMType) -> SourceRMCalibration? {
        sourceRMCalibrations.first { $0.exercise?.id == exercise.id && $0.rmType == rmType }
    }

    /// Stage 10R.5, D-10R5-15: this instance's own override always wins;
    /// otherwise defers to the owning profile's default. Falls back to
    /// `.loadFocused` (matching `UserProfile`'s own default) if no
    /// profile exists at all, rather than silently assuming `.source`.
    func effectiveProgressionStyle(userProfile: UserProfile?) -> ProgressionStyle {
        progressionStyleOverride ?? userProfile?.preferredProgressionStyle ?? .loadFocused
    }
}
