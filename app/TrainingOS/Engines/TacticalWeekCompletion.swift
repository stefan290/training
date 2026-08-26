import Foundation

/// Stage 10R.4A: pure, derived tactical-lifecycle queries — never a
/// persisted status (`STAGE10R4_TACTICAL_ROLLFORWARD_DESIGN.md` §2/§16,
/// Locked Decision 4: no `TrainingWeek.status`, no automatic
/// `ProgramInstance.status`/`TrainingPhase.status` mutation). Every
/// answer here is recomputed from `Session.status` and the already-
/// generated `ProgramDefinition.orderedWeeks` — the same "pure,
/// deterministic, no stored derived state" discipline
/// `ProgramWeekGrouping`/`AutoregulationRatingResolver` already
/// established. Scoping is always via the real `ProgramInstance`/
/// `TrainingMixComponent` relationships (never inferred from a date or
/// a display title) — `TrainingWeek` itself is template-scoped, not
/// per-instance, so it cannot answer any of these questions on its own.
enum TacticalWeekCompletion {
    /// Locked Decision 1/3: these four `SessionStatus` values all count
    /// as terminal for tactical week-completion purposes — a Session
    /// being terminal says nothing about whether useful performance data
    /// exists (`.skipped`/`.missed`/`.abandoned` legitimately carry
    /// none). `.scheduled`/`.inProgress` are the only non-terminal
    /// states.
    private static let terminalStatuses: Set<SessionStatus> = [.completed, .skipped, .missed, .abandoned]

    /// `true` when `weekIndex` has at least one real materialized
    /// `Session` for `instance`, and every one of them is terminal. A
    /// week with zero materialized Sessions is deliberately NOT
    /// terminal — there is nothing yet to resolve, matching
    /// `ProgramWeekGrouping.nextWeekIndex`'s own "not yet reached"
    /// semantics for an unmaterialized week.
    static func isWeekTerminal(for instance: ProgramInstance, weekIndex: Int) -> Bool {
        let sessions = ProgramWeekGrouping.realSessions(in: instance, forWeek: weekIndex)
        guard !sessions.isEmpty else { return false }
        return sessions.allSatisfy { terminalStatuses.contains($0.status) }
    }

    /// `true` when `instance`'s `ProgramDefinition` has a real,
    /// source-defined week immediately after `weekIndex` — reads
    /// `ProgramDefinition.orderedWeeks` (the generator's own frozen
    /// output, e.g. 5 weeks for Mesocycle 1/2, 3 for Mesocycle 3 —
    /// Stage 10R.3A), never a hardcoded week count.
    static func hasNextSourceWeek(for instance: ProgramInstance, afterWeekIndex weekIndex: Int) -> Bool {
        guard let definition = instance.programDefinition else { return false }
        return definition.orderedWeeks.indices.contains(weekIndex + 1)
    }

    /// The most recently materialized week index for `instance` — the
    /// real "current tactical week," derived the same way
    /// `PhaseDetailViewModel.currentWeekIndex` already does
    /// (`ProgramWeekGrouping.nextWeekIndex(for:) - 1`). `nil` when
    /// nothing has been materialized yet.
    static func currentMaterializedWeekIndex(for instance: ProgramInstance) -> Int? {
        let index = ProgramWeekGrouping.nextWeekIndex(for: instance) - 1
        return index >= 0 ? index : nil
    }

    /// `true` when `instance`'s current materialized week is terminal
    /// AND it is the definition's own final week — nothing left to
    /// tactically roll forward to. Distinct from any persisted
    /// `ProgramInstance.status` (Locked Decision 4) — purely a read of
    /// real Session/week-count state.
    static func isInstanceExhausted(for instance: ProgramInstance) -> Bool {
        guard let currentWeekIndex = currentMaterializedWeekIndex(for: instance) else { return false }
        guard isWeekTerminal(for: instance, weekIndex: currentWeekIndex) else { return false }
        return !hasNextSourceWeek(for: instance, afterWeekIndex: currentWeekIndex)
    }

    /// `true` when `instance`'s current materialized week is terminal
    /// AND a next source-defined week genuinely exists to roll to (the
    /// exact complement of `isInstanceExhausted`, for one instance).
    static func canAdvanceTacticalWeek(for instance: ProgramInstance) -> Bool {
        guard let currentWeekIndex = currentMaterializedWeekIndex(for: instance) else { return false }
        guard isWeekTerminal(for: instance, weekIndex: currentWeekIndex) else { return false }
        return hasNextSourceWeek(for: instance, afterWeekIndex: currentWeekIndex)
    }

    /// The mixed-modality gate (Locked Decision 2's 4th bullet): `true`
    /// only when EVERY component `RollTacticalWindowUseCase.rollForward`
    /// would actually attempt to advance for `mix` is itself ready to
    /// advance. Mirrors `rollForward`'s own eligibility filter exactly
    /// (has `programInstance` + `programDefinition`, `programmingSystem
    /// != .steadyState` — Steady State materializes its whole block up
    /// front and `rollForward` always skips it, so it is never part of
    /// this gate either).
    ///
    /// An already-**exhausted** component is deliberately excluded from
    /// the "must be ready" set, not folded into it: `rollForward` itself
    /// (with the Stage 10R.4B bounds guard) already safely no-ops for an
    /// exhausted component rather than advancing it — so requiring it to
    /// also be "ready" would incorrectly and permanently block every
    /// OTHER, still-progressing component in the same mix from ever
    /// advancing again once one component finishes early. If, after
    /// excluding exhausted components, nothing eligible remains at all,
    /// there is nothing left to advance and the gate is `false`.
    static func canAdvanceTacticalWeek(for mix: TrainingMix) -> Bool {
        let rollableComponents = mix.orderedComponents.filter { component in
            guard let instance = component.programInstance, instance.programDefinition != nil,
                  let system = component.programmingSystem, system != .steadyState
            else { return false }
            return !isInstanceExhausted(for: instance)
        }
        guard !rollableComponents.isEmpty else { return false }
        return rollableComponents.allSatisfy { component in
            guard let instance = component.programInstance else { return false }
            return canAdvanceTacticalWeek(for: instance)
        }
    }
}
