# Phase Planning Rules

How `TrainingPhase` gets its goal, why it needs no new schema to express
a multi-objective phase, and when a phase ends. The central finding:
**"what a phase prioritizes" is already fully expressible through the
existing `TrainingMix`/`TrainingMixComponent` model (`GoalPriority` +
`ComponentFlexibility`) — a phase does not need its own separate
objectives field.**

## 1. `TrainingPhase` stays a small, typed concept — no subclassing

§8 explicitly warns against "excessive hard-coded phase subclasses" and
asks for typed goal/priorities instead. `TrainingPhase` (unchanged shape:
`type: PhaseType`, `priorityRule: TrainingPriority`, `startDate`/`endDate`,
`status`, `trainingMixes`, `programInstances`) already follows this — the
kickoff's named phase concepts (Muscle Gain, Fat Loss, Maintenance,
Strength, Aerobic Development, Running Performance, Functional Fitness,
Hybrid, Recovery, Transition) do **not** each need a `PhaseType` case:

- `muscleGain`, `fatLoss`, `strength`, `enduranceEvent`,
  `functionalFitness`, `recovery`, `transition`, `maintenance` already
  exist and cover 8 of the 10.
- "Aerobic Development" and "Running Performance" are **not** new
  `PhaseType` cases — both are `enduranceEvent`-typed phases whose
  `RecommendedTrainingMix`'s primary component names the specific system
  (`.steadyState`/`.interval`) and, via `ModalityPreference`
  (`STRATEGIC_PLAN_MODEL.md` §1b), the specific `ActivityType` (running
  vs. cycling). Adding a `PhaseType` case per activity would be exactly
  the combinatorial subclassing §8 warns against — the mix already
  carries that distinction.
- **`.hybrid` is the one genuinely missing case** — it names a phase with
  deliberately no single dominant adaptation (§43's transition target
  state), which none of the existing 8 cases can express even
  compositionally, since every existing case implies a specific primary
  adaptation. Proposed addition, purely additive
  (`STAGE5A_DECISION_MEMO.md`).

`TrainingPriority` (`strength`/`endurance`/`mixedModal`) remains the
coarse, UI-facing tag it already was in Stage 1-2 — it is not replaced by
anything in this document. It answers "broadly, what style of training is
this phase" for quick display; the *real*, scheduling-relevant priority
detail lives one level down, on the phase's `RecommendedTrainingMix`'s
components, per §2 below.

## 2. Phase goal composition — reusing `GoalPriority` + `ComponentFlexibility`, not inventing a third tier

§9's example (Fat Loss: primary Lose Fat, **protected** Maintain Muscle,
supporting Maintain Aerobic Fitness) looks like it needs three
distinct tiers. It does not — Stage 4F/4G's existing two independent
dimensions already express exactly this:

| §9 concept | Existing representation |
|---|---|
| Primary | `TrainingMixComponent.priority == .primary` |
| **Protected** | `priority == .secondary` **and** `flexibility == .required` — subordinate to the primary goal, but its required minimum must still be hit |
| Supporting | `priority == .supporting` (any flexibility, typically `.preferred`/`.optional`) |

A Fat Loss phase's `RecommendedTrainingMix` is therefore three ordinary
`TrainingMixComponent`s — a `.primary` conditioning/deficit-appropriate
component, a `.secondary`+`.required` resistance-training component
(this is what "protects" muscle: its required minimum cannot be dropped
under scheduling pressure, per `CONCURRENT_SCHEDULER.md`'s conflict
resolution order, §5 below), and a `.supporting` aerobic component. No
new field, no new enum case, no third priority tier. This is the single
most load-bearing finding in this document: **a phase's goal composition
is entirely a property of its mix, not of the phase entity itself.**

## 3. Why this matters for conflict resolution

Because "protected" resolves to `.secondary` + `.required`, the
hardened Stage 4G scheduler already handles it correctly with zero new
code: `ConcurrentScheduler`'s two-phase algorithm guarantees every
`.required` component's minimum before any component's "extra" sessions
are attempted (`GOAL_ALIGNMENT.md` §5 step 2), and a `.secondary`+
`.required` resistance component will still be protected ahead of a
`.supporting` aerobic component's own extras even though neither is
`.primary`. The planner does not need to teach the scheduler a new
concept — it only needs to *assign the right two tags* when building the
mix.

## 4. Phase transition criteria

A phase ends by exactly one of these triggers — `TrainingPhase.status`
(`.planned`/`.active`/`.completed`/`.paused`/`.abandoned`) records the
outcome, and every transition produces a `PlannerDecision`
(`PLAN_REVISION_MODEL.md` §2) naming which trigger fired:

| Trigger | Fires when | Reason code |
|---|---|---|
| Date-based | `endDate` reached | `PHASE_DATE_REACHED` |
| Duration-based | The phase's own elapsed-weeks counter hits its `PhaseDurationPolicy.typicalWeeks` (or a user-set override) with no fixed `endDate` | `PHASE_DURATION_REACHED` |
| Milestone-based | The plan's `milestoneDate`-anchored phase completes | `MILESTONE_PHASE_COMPLETED` |
| User-triggered | Explicit "I'm done with this phase" / "extend" / "shorten" action | `USER_REQUESTED_TRANSITION` |
| Planner recommendation | `LongTermPlanner` detects the current phase's goal is better served by transitioning now (e.g. missed-progress handling, §6) — always surfaced for approval, never auto-applied (§29) | `PLANNER_RECOMMENDED_TRANSITION` |
| ProgramJourney completion | The phase's primary `ProgramInstance` completes its own journey (`HypertrophyProgramJourney`-style progression) before the phase's own date/duration criterion | `PROGRAM_JOURNEY_COMPLETED` |

Not every transition is automatic — date-based and duration-based
transitions still surface as a proposal requiring approval (§29), just
like every other planner output in this pipeline. "Automatic" here means
*detected*, never *silently applied*.

## 5. Phase extension and shortening

Both are the same operation — replanning the remaining roadmap against a
new duration for the *current* phase — routed through
`LongTermPlanner.reviseStrategicPlan` (`PLAN_REVISION_MODEL.md` §4), never
a manual full-plan rebuild:

- **Extension** ("this is going well, extend 4 weeks" — §30): the
  current phase's `endDate` moves out; every later phase shifts by the
  same delta unless a `milestoneDate` anchor would be violated, in which
  case the proposal surfaces the conflict (e.g. "extending Muscle Gain by
  4 weeks pushes Fat Loss completion 4 weeks past your June 15
  milestone") rather than silently blowing through the milestone.
- **Shortening** ("start cutting earlier" — §31): the current phase's
  `endDate` moves in; the freed time is redistributed per §4a's duration
  policy (a later Maintenance/Recovery phase absorbs it first, before
  reducing another goal-serving phase's own typical duration below its
  `minimumWeeks`).

Both preserve every completed phase's history untouched — only phases
with `status != .completed` are eligible to move at all.

## 6. Missed progress / falling behind

If actual progress lags strategic expectation (a signal, not a
prediction — `ADHERENCE_AWARE_PLANNING.md` §4 draws this line precisely),
`LongTermPlanner` may **recommend** one of: extend the current phase,
shorten a later phase, adjust the target, or hold the current route
unchanged — always as a `PlannerDecision`-backed proposal requiring
approval (§29), never a silent large strategic change (§32's own
instruction). No behavioral-prediction model decides this; the trigger is
always an explicit, observable signal (e.g. a `.required` component
missing its frequency repeatedly — the same `ScheduleIssue.requiredFrequencyUnsatisfied`
signal Stage 4G already produces, read over multiple tactical windows
rather than invented anew).

## 7. Per-goal-type phase architecture

**Fat Loss** (§40): primary = body-composition-direction-appropriate
conditioning; protected = resistance training (§2's "protected" pattern
— never "more cardio is always better," an explicit non-rule); supporting
= aerobic maintenance where recovery capacity allows. Training mix is
still goal-driven composition, not a fixed cardio-heavy template.

**Muscle Gain** (§41): primary = hypertrophy/resistance stimulus,
adequate volume; conditioning may remain present as `.supporting` —
never automatically stripped out.

**Maintenance/Recovery** (§42): a genuinely lower-demand strategic
period — between accumulation blocks, around travel, before another
specialization block, or as a motivation reset. Not assumed on a fixed
annual cadence ("every year needs one recovery month" is explicitly not
a rule here); inserted when the roadmap's own duration math calls for one
(e.g. two consecutive long accumulation phases) or the user requests one.

**Hybrid Transition** (§43): a short phase whose `RecommendedTrainingMix`
deliberately blends the outgoing and incoming phase's components (e.g. 5
Hypertrophy → 3 Strength + 2 Functional Fitness + 1 Run) rather than a
hard single-day cutover — sized via the `transition` row in
`STRATEGIC_PLAN_MODEL.md` §4a's duration policy. A short configured
transition is the default; a hard switch is only what happens when a
transition phase's duration is configured to zero, never the implicit
default.
