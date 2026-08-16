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

## 2. `PlannerDecision` — the audit trail, mirroring `Recommendation` (RESOLVED)

`Recommendation` (Stage 1-2) already established the exact shape a
persisted, reason-coded engine output needs: *"A Recommendation without
a reason code is a bug — there is deliberately no way to construct one
without it."* `PlannerDecision` (new, Stage 5B) is that same shape one
layer up — extended per Decision 6 with a scope-limiting decision type,
an explicit source, and the alternatives that were *not* chosen:

```swift
/// The fixed, closed set of strategically-meaningful events worth an
/// audit record — deliberately narrow. Every low-level scheduler
/// comparison, every `ConcurrentScheduler` placement decision, and every
/// intermediate ranking step stays exactly where it already lives
/// (`ScheduleIssue`/`SchedulingReasonCode`, Stage 4G) — none of that is
/// duplicated here.
enum PlannerDecisionType: String, Codable, CaseIterable {
    case phaseSelected
    case programOrMixSelected
    case userChoseAlternative
    case temporaryPreferenceApplied
    case phaseExtendedOrShortened
    case roadmapRevised
}

/// Who/what actually made this decision — distinct from *why*
/// (`reasonCode`). A system recommendation that the user then overrides
/// produces two different `PlannerDecision`s, each with its own honest
/// `source`, never one row with an ambiguous origin.
enum DecisionSource: String, Codable, CaseIterable {
    case systemRecommended
    case userSelected
    case userOverride
    case planRevision
}

/// One option that was on the table and not chosen — enough to answer
/// "why not X" later without needing to persist the full transient
/// proposal it came from. An array of a small struct — already a
/// proven-safe SwiftData persistence shape in this codebase
/// (`Stimulus.movementModalityMix: [ModalityCount]`, Stage 4E).
struct ConsideredAlternative: Codable, Equatable {
    var label: String
    var ratingSummary: GoalAlignmentRating?
    var rejectionReasonCode: PlannerReasonCode?
}

@Model
final class PlannerDecision {
    @Attribute(.unique) var id: UUID
    var decidedAt: Date
    var decisionType: PlannerDecisionType
    var source: DecisionSource
    var reasonCode: PlannerReasonCode
    /// Small structured extras — mirrors `ScheduleIssue.metadata`'s exact
    /// shape and the exact same rule: never parsed back by any logic,
    /// display-generation input only.
    var factors: [String: String]
    /// What else was considered and why it wasn't chosen — omitted
    /// (empty) when there was only ever one option, e.g. a temporary
    /// preference application.
    var alternativesConsidered: [ConsideredAlternative]
    /// Display copy only, generated FROM the structured fields above —
    /// CLAUDE.md rule 16's discipline extended to planning, one layer up
    /// from scheduling. Never business source of truth.
    var explanation: String

    // Optional back-references — as many as are relevant are set (e.g.
    // a `.roadmapRevised` decision sets `goal`+`planRevision` but no
    // `phase`; a `.phaseSelected` decision sets `planRevision`+`phase`),
    // mirroring `WorkoutBlock`'s own established "multiple optional
    // typed children" pattern rather than an unsafe enum-with-payload
    // holding a `@Model` reference.
    var goal: Goal?
    var planRevision: TrainingPlan?
    var phase: TrainingPhase?
    var trainingMix: TrainingMix?
    var programInstance: ProgramInstance?
}
```

One `PlannerDecision` is persisted per strategically-meaningful event —
`PlannerDecisionType`'s own 6 cases are the exhaustive list; nothing else
produces one. Persisted at acceptance time only (mirroring
`AcceptScheduleProposalUseCase`'s "only accept mutates" pattern —
proposing something never persists a `PlannerDecision` by itself; only
`AcceptPlanRevisionUseCase`, Stage 5B's counterpart, does, alongside
whatever phase/mix/plan rows the decision actually changes). This is
deliberately **not** a debug log: no per-comparison scheduler internals,
no low-level candidate-scoring intermediate state — those already have a
home (`ScheduleIssue`, Stage 4G) and are not duplicated here.

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
- `ADHERENCE_PREFERENCE_PROMOTED_ALTERNATIVE` — a preference-aligned,
  goal-compatible candidate was promoted to `.recommended` over the
  highest-`GoalAlignment` candidate (`ADHERENCE_AWARE_PLANNING.md` §5b —
  Decision 3). Always paired with `.bestGoalAlignment` remaining visible
  on whichever candidate would otherwise have topped the list.

**Temporary preference**
- `TEMPORARY_PREFERENCE_APPLIED` — a bounded `TrainingMix` window
  (`ADHERENCE_AWARE_PLANNING.md` §2) was accepted.
- `TEMPORARY_PREFERENCE_EXPIRED` — its `validUntil` passed; a return
  choice is being offered.
- `TEMPORARY_PREFERENCE_MATERIALITY_THRESHOLD` — a temporary block (or
  its cumulative renewals) crossed the materiality threshold
  (`ADHERENCE_AWARE_PLANNING.md` §2a — Decision 2); the
  continue/convert/re-plan choice is being offered.
- `TEMPORARY_PREFERENCE_CONVERTED_TO_PHASE` — the user chose to make a
  temporary mix the phase's own stable selected mix (`validUntil`
  cleared).

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

## 4. Revision lineage — every re-plan creates a new `TrainingPlan` revision (Decision 5, RESOLVED)

**Resolution:** re-planning always creates a **new** `TrainingPlan`
revision — extend, shorten, a milestone change, and a full long-term
goal change are all the same mechanism, differing only in how much of
the roadmap the new revision actually changes. This replaces this
document's own earlier draft (which mutated minor revisions in place) —
"Old strategic plans are not rewritten to make history appear as if the
new plan was always intended" applies uniformly, not just to major
pivots.

```swift
// Two new fields on the existing TrainingPlan entity:
var supersedes: TrainingPlan?   // nullify — the immediately-prior revision;
                                 // nil for the first revision of a lineage
var lineageID: UUID              // shared by every revision of "the same
                                  // evolving roadmap"; a fresh UUID only
                                  // when a genuinely new strategic intent
                                  // begins (§4c)
```

`supersedes` reconstructs *order* (a linked chain); `lineageID` gives an
O(1) *grouping* query ("every revision of this roadmap") without walking
the chain. Both are cheap, additive, nullify/plain fields — no new
entity.

```
Plan Revision 1  (lineageID: L, supersedes: nil)
      ↓ superseded by
Plan Revision 2  (lineageID: L, supersedes: Revision 1)
      ↓ superseded by
Plan Revision 3  (lineageID: L, supersedes: Revision 2)
```

### 4a. What a new revision actually contains

A revision's own `phases: [TrainingPhase]` holds **only its own
new/future phases** — it never copies or re-parents phases that already
belong to a prior revision:

- Every `.completed` phase, and the currently-`.active` phase's own
  already-elapsed portion, stays exactly where it is, on whichever
  revision it actually happened under. **Never moved, never duplicated.**
- The prior revision's own `.planned` (not-yet-lived) future phases
  become `.abandoned` (existing `PhaseStatus` case) — inert historical
  record, never deleted.
- The prior revision's `status` becomes `.superseded` (existing
  `PlanStatus` case); the new revision is `.active`.
- The new revision's phases start from today's state, generated via the
  ordinary `proposeStrategicPlan`/`reviseStrategicPlan` path.

"The full history of this roadmap," when needed, is the union of every
revision-in-the-lineage's own phases, walked via `lineageID` — never one
mutated, unified phase list.

### 4b. Minor revision (extend/shorten, milestone change) — same lineage

`LongTermPlanner.reviseStrategicPlan` with a `PlanRevisionRequest`
(`.extendPhase`/`.shortenPhase`/`.changeMilestoneDate`) returns a
`StrategicPlanProposal` for the recalculated remaining phases
(`PHASE_PLANNING_RULES.md` §5's redistribution rule). On acceptance,
`AcceptPlanRevisionUseCase` creates Revision N+1 with the **same
`lineageID`**, `supersedes: <Revision N>`, containing the recalculated
future phases; Revision N's completed/elapsed history stays untouched
per §4a. One `PlannerDecision` (`decisionType: .phaseExtendedOrShortened`
or `.roadmapRevised`, reason code `PHASE_EXTENDED`/`PHASE_SHORTENED`/
`MILESTONE_DATE_CHANGED`) records it, `planRevision` pointing at the new
revision.

### 4c. Major revision (long-term goal change) — new lineage

Example (§33): a full year targeting Muscle Gain + summer leanness
becomes "run a half marathon." The new revision gets a **fresh
`lineageID`** (this is a new strategic intent, not a refinement of the
old one) while `supersedes` still points at the old revision for full
traceability — a lineage boundary, not a history gap. `PerformanceProfile`
history is untouched either way — CLAUDE.md rule 1's own invariant,
restated at the strategic layer: changing the long-term goal is not a
new user, and it must never look like one. One `PlannerDecision`
(`decisionType: .roadmapRevised`, reason code `LONG_TERM_GOAL_CHANGED`)
records the pivot.

### 4d. Accepted tactical schedules are permanent, unaffected by any revision

Once a `ScheduleProposal` is accepted (`AcceptScheduleProposalUseCase`),
the resulting `Session`/`Day` placements are real, materialized execution
data — a historical snapshot no later plan revision, of any size, ever
touches. Revisions only ever affect planning-layer `TrainingPhase`/
`TrainingMix` rows for *future* time; this was already true by
construction (Stage 4F/4G's `AcceptScheduleProposalUseCase` has no path
back into `TrainingPlan`/`TrainingPhase` at all), stated explicitly here
as a locked invariant rather than an incidental fact.

## 5. Planned vs. actual — no new schema, a derivable comparison

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
