import Foundation
import SwiftData

/// Which adaptation is prioritised over a period, and the scheduling
/// priority rule that follows from it. Ending or deleting a Phase must
/// never delete a ProgramInstance's history — enforced by the `.nullify`
/// relationship below.
///
/// **Stage 3C generalization:** a Phase can now hold one primary
/// `ProgramInstance` plus zero or more secondary ones (Modules) — e.g. a
/// Muscle Gain phase with a primary Hypertrophy instance and a secondary
/// Aerobic Base instance, or a Running phase with a primary Running
/// instance and a secondary Strength Maintenance instance
/// (`ENDURANCE_PROGRAMMING_MODEL.md` §9, `CONCURRENT_SCHEDULER_MODEL.md`
/// §1). This is composition/priority only — `TrainingPhase` still performs
/// no scheduling logic itself; a future `ConcurrentScheduler` reads
/// `primaryInstance`/`secondaryInstances` to decide placement. No new
/// `HybridProgramDefinition`-style type was introduced: this is the same
/// `programInstances` array as before, now readable by priority via the
/// two computed properties below, plus `ProgramInstance.priority` itself.
///
/// **"ProgramJourney" note:** the phase *sequencing* concept explored in
/// Stage 3B docs (`PROGRAMMING_SYSTEM_MODEL.md` §5.1) needed no new
/// entity — `TrainingPlan.orderedPhases` already provides it. This
/// generalization is the one real schema change Stage 3B's validation
/// found necessary, and it lives here, on `TrainingPhase`/`ProgramInstance`,
/// not on a new `ProgramJourney` type.
@Model
final class TrainingPhase {
    @Attribute(.unique) var id: UUID
    var plan: TrainingPlan?
    var type: PhaseType
    /// Stable position among a Plan's phases, assigned by
    /// `TrainingPlan.addPhase(_:)`.
    var sortIndex: Int
    var startDate: Date
    var endDate: Date?
    var priorityRule: TrainingPriority
    var status: PhaseStatus

    /// Nullify, not cascade: deleting a Phase must never delete the
    /// ProgramInstances (and therefore the Sessions and results) that ran
    /// inside it.
    @Relationship(deleteRule: .nullify, inverse: \ProgramInstance.phase)
    var programInstances: [ProgramInstance] = []

    /// Stage 4F addition: this Phase's `TrainingMix`es (recommended
    /// and/or selected) — cascade, not nullify, since a `TrainingMix` is
    /// pure planning/preference metadata scoped to this phase, not
    /// performance history (mirrors `ProgramInstance.slotSelectionOverrides`'
    /// identical cascade reasoning).
    @Relationship(deleteRule: .cascade, inverse: \TrainingMix.phase)
    var trainingMixes: [TrainingMix] = []

    init(
        id: UUID = UUID(),
        type: PhaseType,
        startDate: Date,
        endDate: Date? = nil,
        priorityRule: TrainingPriority,
        status: PhaseStatus = .planned
    ) {
        self.id = id
        self.type = type
        self.sortIndex = 0
        self.startDate = startDate
        self.endDate = endDate
        self.priorityRule = priorityRule
        self.status = status
    }

    /// The only way application code should attach a ProgramInstance to a
    /// Phase. Mutates exactly one side (this array); SwiftData maintains
    /// `instance.phase` from the declared inverse. Does not set
    /// `instance.priority` — set that on the `ProgramInstance` itself
    /// (defaults to `.primary`) before or after calling this.
    func addProgramInstance(_ instance: ProgramInstance) {
        programInstances.append(instance)
    }

    /// The Phase's primary system, if one has been attached. `nil` only
    /// before any instance is added — a Phase with instances but no
    /// `.primary` one is a caller bug, not a valid, silently-tolerated
    /// state, but this property does not crash on it; it simply returns
    /// `nil`, matching the model's general preference for surfacing gaps
    /// via tests rather than runtime traps.
    ///
    /// **Stage 10R.7A:** once a program-level succession (e.g. a
    /// Hypertrophy mesocycle transition) can attach more than one
    /// `ProgramInstance` to the SAME strategic `TrainingPhase` over its
    /// lifetime (`STAGE10R7_STRATEGIC_PHASE_LIFECYCLE_DESIGN.md`), `.first`
    /// over the unordered, purely historical `programInstances` bag is no
    /// longer safe — it could return a long-superseded instance instead of
    /// the current one. The authoritative "current" pointer is instead
    /// each mix's own `TrainingMixComponent.programInstance` (reassigned
    /// at each succession, exactly the mechanism that makes it current) —
    /// read through the phase's active mix first, falling back to the raw
    /// historical scan only when no mix exists yet (unchanged behavior for
    /// every phase that predates any mix, e.g. `HypertrophyProgramJourney
    /// .build`'s own standalone fixture phases).
    var primaryInstance: ProgramInstance? {
        guard let mix = selectedTrainingMix ?? recommendedTrainingMix else {
            return programInstances.first { $0.priority == .primary }
        }
        return mix.orderedComponents.first { $0.priority == .primary }?.programInstance
    }

    /// Zero or more secondary Modules running alongside the primary
    /// instance this Phase — e.g. an Aerobic Base module alongside a
    /// primary Hypertrophy instance. Same "current pointer via the mix
    /// component" discipline as `primaryInstance` above, and for the same
    /// reason.
    var secondaryInstances: [ProgramInstance] {
        guard let mix = selectedTrainingMix ?? recommendedTrainingMix else {
            return programInstances.filter { $0.priority == .secondary }
        }
        return mix.orderedComponents.filter { $0.priority == .secondary }.compactMap(\.programInstance)
    }

    /// The only way application code should attach a `TrainingMix`.
    /// Mutates exactly one side (this array); SwiftData maintains
    /// `mix.phase` from the declared inverse.
    func addTrainingMix(_ mix: TrainingMix) {
        trainingMixes.append(mix)
    }

    /// The currently active `.selected` mix, if the phase has one — the
    /// mix `ConcurrentScheduler` should actually schedule (§7/§36: a
    /// selected mix always wins over the recommendation).
    var selectedTrainingMix: TrainingMix? {
        trainingMixes.first { $0.kind == .selected }
    }

    /// The system's `.recommended` mix, if one has been generated —
    /// informational/comparison only; never scheduled directly when a
    /// `.selected` mix exists.
    var recommendedTrainingMix: TrainingMix? {
        trainingMixes.first { $0.kind == .recommended }
    }

    /// Stage 5B addition: the `.selected` mix that is actually active as
    /// of a given date, once more than one `.selected` mix may exist on
    /// the same phase (a temporary modality switch, `ADHERENCE_AWARE_PLANNING.md`
    /// §2, never deletes the mix it replaces — it only closes its
    /// `validUntil` window). Purely additive: `selectedTrainingMix` above
    /// is untouched and keeps its exact Stage 4F meaning for every
    /// existing call site that only ever expects a single `.selected`
    /// mix; this is a second, temporally-aware query for callers that
    /// need to disambiguate among several.
    func activeTrainingMix(asOf: Date) -> TrainingMix? {
        trainingMixes
            .filter { $0.kind == .selected }
            .filter { mix in
                if let validFrom = mix.validFrom, validFrom > asOf { return false }
                if let validUntil = mix.validUntil, validUntil <= asOf { return false }
                return true
            }
            .max { ($0.validFrom ?? .distantPast) < ($1.validFrom ?? .distantPast) }
    }
}
