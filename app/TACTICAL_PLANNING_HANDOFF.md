# Tactical Planning Handoff

Where the strategic layer (`STRATEGIC_PLAN_MODEL.md`,
`PHASE_PLANNING_RULES.md`) meets the already-existing execution machinery
(`ProgramGenerator`s, `SchedulingPipeline`) — the tactical horizon, when
it rolls forward, how a phase actually starts, and what a UI needs to
render any of this.

## 1. Tactical horizon length — 4 weeks, and why that's not arbitrary

§38 asks for a recommended initial horizon, defaulting to 4 weeks unless
the architecture suggests otherwise. It doesn't — **4 weeks is already
the natural block length this codebase's own generators use**: every
`StrengthProgressionEngine`/`PowerliftingProgramGenerator`-backed program
in this repository runs 4-week blocks with `TrainingWeek.isDeload` marking
week 4 (the "Week-4 autoregulation" behavior `STAGE3_DECISION_MEMO.md`/
`PowerliftingRegressionTests` already exercise). A tactical window
therefore defaults to **one full mesocycle block** of whichever program
is primary for the current phase, not a fixed "28 days" detached from
program structure — for a 4-week-block program that's 4 weeks; Stage 5A
proposes this as the general rule (tactical horizon = the primary
component's own natural block length, falling back to 4 weeks when a
system has no such natural block, e.g. a single steady-state week
repeated) rather than hardcoding 4 weeks as a universal constant.

No exact workout is ever generated more than one tactical window ahead
(§6/§38's explicit constraint) — materialization for week 5 does not
exist until the next tactical window is generated.

## 2. Rolling window triggers — deterministic, never a bare timer

A new tactical window is generated only when one of these fires — never
merely because calendar time passed, and never on an implicit background
timer:

1. **Scheduled**: today is within a configured buffer (proposed default:
   7 days) of the current window's last placed day — leaving enough lead
   time to review and approve the next window before the current one
   runs out.
2. **Phase transition accepted** (`PHASE_PLANNING_RULES.md` §4) — the new
   phase's mix needs its own first tactical window immediately.
3. **Plan revision accepted** (`PLAN_REVISION_MODEL.md` §4/§5) — an
   extension, shortening, or goal change invalidates the premise of
   whatever window was previously planned.
4. **Temporary preference change** — a bounded mix accepted or its expiry
   resolved (`ADHERENCE_AWARE_PLANNING.md` §2).
5. **Explicit pause/resume** — the user pauses training (no new window
   generated while paused) and later resumes (a fresh window is
   generated from the resume date, not backfilled for missed time).

Every trigger is an explicit event or an explicit date comparison against
a caller-supplied "now" (mirroring `SchedulingWindow.startDate`'s own
discipline — the planner is never the one reading the system clock).

## 3. Starting a new phase — orchestration only, no new mechanism

§27's pipeline (`ProgramDefinition` + `PerformanceProfile` +
`EquipmentProfile` → `ProgramInstance` → starting recommendations) is
**already exactly how every existing generator/materializer works** —
`HypertrophyProgramGenerator`/`PowerliftingProgramGenerator`/etc. already
resolve starting numbers from performance history (with
`ExercisePerformanceProfile.confidence`/`.lastPerformedAt` already
governing whether a historical number is trusted — `PROGRAM_RECOMMENDATION_MODEL.md`
§4). Starting a new phase requires no new resolution mechanism:

1. `LongTermPlanner` selects the phase's `RecommendedTrainingMix`/
   `UserSelectedTrainingMix` and, per component, a `ProgramCandidate`.
2. For each component, the existing generator (`HypertrophyProgramGenerator`,
   etc.) is invoked exactly as it already is today, producing a
   `ProgramDefinition` and a `ProgramInstance` — reusing existing
   `PerformanceProfile`/`EquipmentProfile` history automatically, because
   that's what these generators already do.
3. `TrainingMixComponent.programInstance` is set to the new instance
   (Stage 4F's existing optional-by-design field, `TRAINING_MIX.md` §4).
4. The phase's first tactical window is generated (§2 above).

No weights are reset (CLAUDE.md rule 1, restated: nothing here deletes
or truncates any `PerformanceProfile`); no user is asked to
rediscover an exercise that already has confident, recent history — this
is what the existing generators already guarantee, unchanged.

## 4. UI data contracts

Plain, non-persisted read shapes a future UI would assemble from existing
+ Stage 5B data — not new persistence, and not UI code itself (§59's own
scope limit: specify what UI must receive, don't build it).

**Annual plan screen** (§59), one row per `TrainingPhase`:
```
phaseName          <- TrainingPhase.type (display-mapped)
dates              <- startDate / endDate
primaryGoal        <- recommendedTrainingMix's .primary component label
trainingMix        <- selectedTrainingMix ?? recommendedTrainingMix, orderedComponents
recommendedProgram <- top ProgramCandidate per component
status             <- TrainingPhase.status
nextTransition      <- next phase's startDate + its trigger type (§4 of PHASE_PLANNING_RULES.md)
```

**Alternatives** (§59's second half): `[CandidateTrainingMix]`
(`ADHERENCE_AWARE_PLANNING.md` §5) as-is — `alignment`/`reasonCodes`
already carry everything a tradeoff explanation needs.

**Current phase screen** (§60):
```
purpose            <- PlannerDecision(reasonCode: PHASE_SELECTED_FOR_GOAL).explanation
weekProgress        <- elapsed weeks / PhaseDurationPolicy.typicalWeeks (or endDate)
currentMix          <- selectedTrainingMix ?? recommendedTrainingMix
primaryProgram      <- primary component's ProgramInstance
supportingModules   <- non-primary components' ProgramInstances
upcomingTransition  <- as above
whyThisPhase        <- §5 below
```

## 5. "Why this phase" / "why this program" — structured first, always

§61/§62 require the explanation to derive from structured reason codes,
never treat natural language as the source of truth. Both questions
resolve identically: find the `PlannerDecision` attached to the subject
(`phase`/`programInstance`, `PLAN_REVISION_MODEL.md` §2's optional
back-references) and read its `reasonCode`/`factors` — `explanation` is
already-generated display copy from exactly those fields, cached at
decision time rather than regenerated on every view (cheap, and
consistent with `Recommendation.inputsSummary`'s own "cache the
explanation, don't recompute it live" precedent). §61's own example —
"you are in Muscle Gain because your long-term goal is maximum muscle and
your fat-loss phase is scheduled closer to your June milestone" — is
`PHASE_SELECTED_FOR_GOAL` plus `factors: ["milestoneDate": "…",
"phaseSequencePosition": "…"]`, rendered, not a free-standing sentence
authored ad hoc. §62's example is the identical pattern one layer down,
using `PROGRAM_MATCH_AVAILABILITY`/`PROGRAM_MATCH_EXPERIENCE`.

## 6. What tactical planning does not do

- Does not generate exact sets/loads/paces for the whole phase up front
  — only for the current tactical window, per §1.
- Does not re-run `proposeStrategicPlan` on every roll — the strategic
  roadmap is read, not regenerated (`STRATEGIC_PLAN_MODEL.md` §5).
- Does not silently change which mix is active — a new window always
  materializes whichever mix (`recommended` or `selected`) was already
  the phase's active one; changing it is a distinct, explicit action
  (`ADHERENCE_AWARE_PLANNING.md`/`PLAN_REVISION_MODEL.md`).
