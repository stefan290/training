# Strategic Plan Model

`LongTermGoal` and `StrategicPlan` — the two concepts sitting above
`TrainingPhase` in `LONG_TERM_PLANNER.md`'s pipeline. The central finding
of this document: **neither needs a new persisted container.**
`StrategicPlan` maps directly onto the existing `TrainingPlan`/`PlanStatus`
entities, and `LongTermGoal` is proposed as an additive extension of the
existing `Goal` entity, not a new parallel type.

## 1. `LongTermGoal` — extends `Goal`, does not replace it

`Goal` (Stage 1-2, unchanged shape today) already models exactly what
§4 calls "primary outcome" (`primaryType: GoalType`), "secondary outcomes"
(`secondaryTypes: [GoalType]`), "target/end date" (`targetDate: Date?`),
and status. The richer inputs Stage 5 needs are proposed as new,
optional fields on the same entity — following the identical pattern
`Session.schedulerVersion`/`Session.isKeySession` already used to extend
a Stage-1 entity without disturbing its existing meaning:

| Field | Type | Maps to kickoff item |
|---|---|---|
| `milestoneDate` | `Date?` | §5 "important milestone date" — distinct from `targetDate` (see §3 below) |
| `bodyCompositionDirection` | `BodyCompositionDirection?` (new: `.gainMuscle`/`.loseFat`/`.maintain`/`.recomposition`) | §3, §4 |
| `performanceGoals` | `[String]` | §4 "performance goals" — see §1a below for why a plain label, not a typed metric, is this pass's recommendation |
| `priorityMuscleGroups` | `[MuscleGroup]` (existing enum, reused directly) | §4 |
| `preferredModalities` | `[ModalityPreference]` (new small struct, §1b) | §4 |
| `dislikedModalities` | `[ModalityPreference]` | §4 |
| `availableTrainingDaysPerWeek` | `Int?` | §4 — coarse, strategic-grain only; see §1c |
| `typicalSessionDurationMinutes` | `Int?` | §4 |
| `allowsDoubleSessions` | `Bool?` | §4 |
| `varietyPreference` | `VarietyPreference` (new: `.low`/`.moderate`/`.high`, default `.moderate`) | §13, `ADHERENCE_AWARE_PLANNING.md` §1 |

Every field is optional (or has a safe default) — "do not require every
field" (§4's own instruction) is satisfied the same way every other
optional field in this schema satisfies it: a `LongTermPlanner` call with
sparse input degrades to coarser recommendations, it never fails.

This is the one genuinely foundational schema question this pass
surfaces — extending `Goal` (a Stage-1 entity with no prior migration
history to break) is low-risk, but it's still a core entity, so
`STAGE5A_DECISION_MEMO.md` lists it as **MUST RESOLVE**, not a silent
decision.

### 1a. Why `performanceGoals` stays a plain label for now

A fully typed performance goal (e.g. "sub-20 5K" as a structured
`ActivityType` + target duration, or "225kg deadlift" as a structured
`Exercise` + target load) would let the planner reason about progress
automatically — genuinely valuable, and a natural Stage 5B+ enhancement.
It would also require deciding a metric vocabulary broad enough for
every current modality (pace, load, rounds/reps, benchmark score) without
duplicating `ScoreType`/`BenchmarkDefinition`'s existing vocabulary — real
design work this pass did not do. `performanceGoals: [String]` (a short
freeform label, e.g. `"Sub-20 5K"`) is the smallest model that still lets
a user state a performance goal and lets a future UI display it; it is
explicitly **not** read by any structured comparison logic in this pass.
Flagged as a deferred question, not silently decided as final —
`STAGE5A_DECISION_MEMO.md`.

### 1b. `ModalityPreference` — reusing existing vocabulary, not inventing new

```swift
struct ModalityPreference {
    var system: ProgrammingSystemKind   // existing enum (Stage 4A-4E)
    var activityType: ActivityType?     // existing enum (Stage 3C) — only meaningful
                                         // when system is .steadyState/.interval
}
```

This directly expresses "prefers Functional Fitness"
(`ModalityPreference(system: .functionalFitness, activityType: nil)`) and
"prefers cycling to running" (`ModalityPreference(system: .steadyState,
activityType: .cycling)`, proving proof case §48 needs no new modality
vocabulary — `ActivityType` already exists precisely so `ConcurrentScheduler`
and now the planner never need to special-case running as *the* endurance
activity, see `PROGRAM_RECOMMENDATION_MODEL.md` §6).

### 1c. Why availability fields here are coarse, not a full `UserAvailability`

`UserAvailability` (Stage 4F) already exists and remains the sole
authority for tactical-time scheduling — its specific weekday sets and
per-day minute ceilings are exactly the kind of thing that changes week
to week (a business trip, a schedule change) and must never be treated
as a stale, persisted assumption. `LongTermGoal`'s availability fields
are strategic-grain only ("roughly how many days, roughly how long, is
doubling generally acceptable") — just enough to pick a plausible
`RecommendedTrainingMix` frequency (5 Hypertrophy vs. 3, say). Every
actual `SchedulingPipeline.propose` call still takes a freshly-supplied
`UserAvailability`, exactly as it does today; nothing here duplicates or
overrides that.

## 2. `StrategicPlan` = `TrainingPlan` — no new container

Stage 5A's kickoff (§6) describes a "strategic horizon" containing
`TrainingPhase`s, phase goals/priorities, expected `ProgrammingSystem`s,
a recommended `TrainingMix`, and approximate durations. `TrainingPlan`
(`goal: Goal?`, `phases: [TrainingPhase]`, `status: PlanStatus`) plus
`TrainingPhase` (`type`, `priorityRule`, `startDate`, `endDate`,
`trainingMixes`, `programInstances`) together already carry every one of
those:

| Strategic horizon requirement | Existing field |
|---|---|
| Ordered `TrainingPhase`s | `TrainingPlan.orderedPhases` |
| Phase goal/priority | `TrainingPhase.type` (`PhaseType`) + `.priorityRule` (`TrainingPriority`) |
| Recommended `TrainingMix` | `TrainingPhase.recommendedTrainingMix` (Stage 4F computed property) |
| Expected `ProgrammingSystem`s | `phase.recommendedTrainingMix?.orderedComponents.map(\.programmingSystem)` |
| Approximate duration | `startDate`/`endDate` |
| Draft vs. active vs. superseded | `TrainingPlan.status: PlanStatus` |

No new "StrategicPlan" entity is proposed. `LongTermPlanner.proposeStrategicPlan`
(`LONG_TERM_PLANNER.md` §5) returns a plain, non-persisted
`StrategicPlanProposal` value (mirroring `ScheduleProposal`'s own
transient shape) whose *acceptance* creates ordinary `TrainingPlan`/
`TrainingPhase`/`TrainingMix` rows via the same
`addPhase`/`addTrainingMix`/`addComponent` methods those types already
expose — no new persistence mechanism, just a new caller.

## 3. `targetDate` vs. `milestoneDate` — why both exist

`Goal.targetDate` is the plan's own horizon end (e.g. "in 12 months").
`milestoneDate` (new) is an *intermediate* date the user needs to look/
perform a certain way BY — "lean and looking my best by June 15" while
the overall goal (maximize muscle) runs a full year. These are
independent: a plan can have a `targetDate` with no `milestoneDate` (pure
forward planning), a `milestoneDate` with no further `targetDate` (plan
ends at the milestone), or both (the required annual proof case, §44).

## 4. Backward planning from a milestone

When `milestoneDate` is set, `LongTermPlanner.proposeStrategicPlan` plans
**backward** from it for whichever phase type the milestone implies
(inferred from `bodyCompositionDirection`/`primaryType` — a milestone
paired with `.loseFat` implies the milestone sits at or just after a Fat
Loss phase's completion) and **forward** from `startDate`/today for
everything before that boundary:

1. Anchor a Fat-Loss-completion (or milestone-appropriate) phase so it
   *ends* at or just before `milestoneDate`.
2. Insert a Transition phase immediately before it, if the preceding
   phase's primary goal differs (e.g. Muscle Gain -> Fat Loss almost
   always wants a short transition — `PHASE_PLANNING_RULES.md` §7).
3. Fill everything from `startDate` to the Transition phase's start with
   phases serving the plan's `primaryType` (e.g. repeated Muscle Gain
   phases, with a Maintenance/Recovery phase inserted per
   `PHASE_PLANNING_RULES.md` §6's own cadence rule, not "one fixed
   recovery month a year").
4. If the available time is too short to fit even the minimum durations
   below, `proposeStrategicPlan` returns a proposal whose feasibility is
   explicitly `.infeasible`-equivalent (mirroring `ScheduleFeasibility`'s
   own vocabulary) with a structured explanation — never a silently
   compressed, unrealistic plan.

### 4a. Phase duration policy — TRAININGOS_DESIGNED, explicitly not validated

Reusing `SessionFrequency`'s exact target/minimum/maximum shape for
duration instead of a single number, per this codebase's own established
"smallest clean model, but ranges where useful" convention:

```swift
struct PhaseDurationPolicy {
    var typicalWeeks: Int
    var minimumWeeks: Int?
    var maximumWeeks: Int?
}
```

Illustrative defaults, keyed by `PhaseType` — **every number below is
TRAININGOS_DESIGNED and explicitly unvalidated against any source**; no
literature search was performed this pass, matching this document's
scope as a design pass, not a research pass. `STAGE5A_DECISION_MEMO.md`
lists confirming/replacing these as **MUST RESOLVE**:

| `PhaseType` | typical | minimum | maximum |
|---|---|---|---|
| `muscleGain` | 12 weeks | 6 | 20 |
| `fatLoss` | 8 weeks | 4 | 12 |
| `maintenance` | 4 weeks | 2 | 8 |
| `recovery` | 2 weeks | 1 | 4 |
| `transition` | 2 weeks | 1 | 3 |
| `strength` | 8 weeks | 4 | 12 |
| `enduranceEvent` | varies with event date | — | — |

These are **configurable**, not hardcoded per-plan constants — a single
shared default table the planner consults, overridable centrally (a
future settings surface) without touching planner logic, exactly like
`InterferenceAvoidanceRule.conservativeDefault` is a default a caller may
override, not a baked-in rule.

## 5. Rolling planning — the strategic/tactical stability invariant

The strategic roadmap (`TrainingPlan.phases`) is stable across tactical
rolls. Generating the next `TacticalPlan` window
(`TACTICAL_PLANNING_HANDOFF.md`) reads the current phase and its
`RecommendedTrainingMix`/`UserSelectedTrainingMix` — it never mutates
phase boundaries, never re-runs `proposeStrategicPlan`, and never
silently regenerates a `TrainingMix`. Only an explicit
`LongTermPlanner.reviseStrategicPlan` call (`PLAN_REVISION_MODEL.md`) may
change the roadmap itself — phase extension/shortening, a milestone
change, or a long-term goal change all go through that one explicit path,
never through ordinary tactical rolling. Completed phases/history are
never rewritten by either path (§7's own instruction, reinforced in
`PLAN_REVISION_MODEL.md` §1).
