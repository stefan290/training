# Plan Revision Model

How a strategic plan changes after it's already been accepted — phase
extension/shortening, milestone changes, a long-term goal change entirely
— without ever rewriting what actually happened. Also the authoritative
`PlannerReasonCode` vocabulary every other Stage 5A document references.

## 1. The one invariant every revision must preserve

> Do not rewrite past plans to make them look as if the new plan was
> always intended. (§53)

Concretely: a completed `TrainingPhase`'s `startDate`/`endDate`/
`trainingMixes`/`programInstances` never change once `status == .completed`.
A revision only ever affects phases that are `.planned` or the
currently-`.active` one's *future* boundary (its own already-elapsed
portion is equally frozen). This is the same discipline
`ProgramDefinition.generatorVersion`/`Session.schedulerVersion` already
established for template/scheduling history — extended here to strategic
history.

## 2. `PlannerDecision` — the audit trail, mirroring `Recommendation`

`Recommendation` (Stage 1-2) already established the exact shape a
persisted, reason-coded engine output needs: *"A Recommendation without
a reason code is a bug — there is deliberately no way to construct one
without it."* `PlannerDecision` (new, Stage 5B) is that same shape one
layer up:

```swift
@Model
final class PlannerDecision {
    var reasonCode: PlannerReasonCode
    /// Small structured extras — mirrors `ScheduleIssue.metadata`'s exact
    /// shape and the exact same rule: never parsed back by any logic,
    /// display-generation input only.
    var factors: [String: String]
    /// Display copy only, generated FROM `reasonCode`/`factors` — CLAUDE.md
    /// rule 16's discipline extended to planning, one layer up from
    /// scheduling.
    var explanation: String
    var decidedAt: Date

    // Optional one-to-one back-references — at most one is ever set,
    // mirroring `WorkoutBlock`'s own established "multiple optional
    // typed children" pattern rather than an unsafe enum-with-payload
    // holding a `@Model` reference.
    var phase: TrainingPhase?
    var trainingMix: TrainingMix?
    var programInstance: ProgramInstance?
}
```

Every strategic recommendation — a phase transition, a mix recommendation,
a program recommendation, an extension, a temporary-preference expiry
choice — produces exactly one `PlannerDecision`, persisted at acceptance
time (mirroring `AcceptScheduleProposalUseCase`'s own "only accept
mutates" pattern — proposing a revision never persists a `PlannerDecision`
by itself; only `AcceptPlanRevisionUseCase`, Stage 5B's counterpart, does,
alongside whatever phase/mix rows the revision actually changes).

## 3. `PlannerReasonCode` — the authoritative vocabulary

Additive, exactly like `SchedulingReasonCode`/`ScheduleIssueCode` — never
renamed or repurposed once a `PlannerDecision` referencing one exists.
Grouped here by concern; every code named in another Stage 5A document
is defined once, here:

**Phase selection / composition**
- `PHASE_SELECTED_FOR_GOAL` — this phase exists because it serves
  `LongTermGoal.primaryType`/`bodyCompositionDirection`.
- `FAT_LOSS_TIMED_TO_MILESTONE` — backward-planned from `milestoneDate`
  (`STRATEGIC_PLAN_MODEL.md` §4).
- `MUSCLE_RETENTION_PRIORITY` — a component was set `.secondary`+
  `.required` specifically to protect muscle during a non-Muscle-Gain
  phase (`PHASE_PLANNING_RULES.md` §2).
- `TRANSITION_PHASE_INSERTED` / `RECOVERY_PHASE_INSERTED` — an
  in-between phase was added by roadmap duration math, not requested
  directly.

**Mix/program recommendation**
- `VARIETY_PREFERENCE_APPLIED` — `varietyPreference` influenced which
  candidate was surfaced as `.bestVarietyAlternative`.
- `PROGRAM_MATCH_AVAILABILITY` / `PROGRAM_MATCH_EXPERIENCE` /
  `PROGRAM_MATCH_PERFORMANCE_PROFILE` — one of
  `PROGRAM_RECOMMENDATION_MODEL.md` §3's factors was the deciding one.
- `USER_SELECTED_ALTERNATIVE` — the accepted mix/program is not the
  top-ranked recommendation.

**Temporary preference**
- `TEMPORARY_PREFERENCE_APPLIED` — a bounded `TrainingMix` window
  (`ADHERENCE_AWARE_PLANNING.md` §2) was accepted.
- `TEMPORARY_PREFERENCE_EXPIRED` — its `validUntil` passed; a return
  choice is being offered.

**Revision**
- `PHASE_EXTENDED` / `PHASE_SHORTENED` (§4 below).
- `MILESTONE_DATE_CHANGED`.
- `LONG_TERM_GOAL_CHANGED` (§5 below).
- `MISSED_PROGRESS_ADJUSTMENT_RECOMMENDED` (`PHASE_PLANNING_RULES.md` §6).

**Transition triggers** (`PHASE_PLANNING_RULES.md` §4, repeated here since
they're still `PlannerReasonCode` values): `PHASE_DATE_REACHED`,
`PHASE_DURATION_REACHED`, `MILESTONE_PHASE_COMPLETED`,
`USER_REQUESTED_TRANSITION`, `PLANNER_RECOMMENDED_TRANSITION`,
`PROGRAM_JOURNEY_COMPLETED`.

## 4. Minor revision: extend/shorten in place

Extending or shortening a phase that hasn't completed yet, within the
*same* long-term goal, is an in-place recalculation — no new
`TrainingPlan` needed, since nothing "completed" is being rewritten:

1. `LongTermPlanner.reviseStrategicPlan` with a `PlanRevisionRequest`
   (`.extendPhase(phase:additionalWeeks:)`/`.shortenPhase(phase:reduceWeeks:)`)
   returns a `StrategicPlanProposal` showing the recalculated remaining
   phase boundaries (`PHASE_PLANNING_RULES.md` §5's redistribution rule).
2. On acceptance, `AcceptPlanRevisionUseCase` updates only the affected
   `TrainingPhase.endDate`/subsequent phases' `startDate`/`endDate` (all
   `.planned` or the current phase's own future boundary) and persists
   one `PlannerDecision` (`PHASE_EXTENDED`/`PHASE_SHORTENED`).
3. Every already-`.completed` phase is untouched, by construction — the
   use case never targets one.

## 5. Major revision: a long-term goal change supersedes the plan

Example (§33): a full year targeting Muscle Gain + summer leanness
becomes "run a half marathon." This is not an in-place recalculation —
the entire remaining roadmap's premise changed. The existing
`PlanStatus`/`PhaseStatus` vocabulary already models exactly what this
needs, with one new optional field:

- `TrainingPlan.supersedes: TrainingPlan?` (new, nullify delete rule,
  purely for traceability — `goal.plans` already holds every plan a
  `Goal` ever had, so this is a convenience back-reference, not the only
  path to history).
- The current plan's status becomes `.superseded` (already exists).
- Its `.planned` (not-yet-lived) future phases become `.abandoned`
  (already exists as a `PhaseStatus` case) — inert historical record,
  never deleted.
- Its `.completed`/currently-`.active`-up-to-today phases are **left
  exactly as they are** — real history of what was actually trained,
  untouched.
- A new `TrainingPlan` (`.active`, `supersedes` pointing at the old one)
  is created from today's state via the ordinary `proposeStrategicPlan`
  path (`STRATEGIC_PLAN_MODEL.md` §4), using the new `LongTermGoal`.
  `PerformanceProfile` history is untouched — CLAUDE.md rule 1's own
  invariant, restated at the strategic layer: changing the long-term
  goal is not a new user, and it must never look like one.
- One `PlannerDecision` (`LONG_TERM_GOAL_CHANGED`) records the pivot,
  attached to the new plan's first phase.

## 6. Planned vs. actual — no new schema, a derivable comparison

§54 wants "Planned: 5 Hypertrophy / Actual: 3 Hypertrophy + 2 Functional
Fitness" comparable without losing either side. Both sides already exist
in the schema with no new type required:

- **Planned** = the phase's `selectedTrainingMix`'s components (frequency,
  priority) — exactly what was accepted.
- **Actual** = real, completed `Session`s grouped by which
  `TrainingMixComponent` produced them, traceable via
  `Session.programInstance` → `ProgramInstance.trainingMixComponents`
  (already an existing relationship, Stage 4F) → `TrainingMixComponent.trainingMix`.

This is a **query**, not a new persisted concept — deferred to whichever
future analytics surface wants it (not a Stage 5A/5B deliverable), but
confirmed here as already representable, satisfying §54's "architecture
should eventually allow this" without adding speculative schema now.
