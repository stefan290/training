# Tactical Planning Handoff

Where the strategic layer (`STRATEGIC_PLAN_MODEL.md`,
`PHASE_PLANNING_RULES.md`) meets the already-existing execution machinery
(`ProgramGenerator`s, `SchedulingPipeline`) — the tactical horizon, when
it rolls forward, how a phase actually starts, and what a UI needs to
render any of this.

## 1. Tactical horizon length — architecture locked, numbers are not (Decision 7, RESOLVED)

§38 asks for a recommended initial horizon, defaulting to 4 weeks unless
the architecture suggests otherwise. **The architecture is locked now;
the specific "4 weeks"/"7 days" numbers below remain configurable
TrainingOS policy, never presented as scientifically validated** — the
same distinction `STRATEGIC_PLAN_MODEL.md` §4a draws for phase durations,
applied here to the tactical window.

**Locked now:** a tactical window's length is derived, in order, from
whichever of these bounds it, never a bare constant in isolation:

1. **Program/mesocycle boundaries** — the phase's primary component's own
   natural block length (every `StrengthProgressionEngine`/
   `PowerliftingProgramGenerator`-backed program already runs 4-week
   blocks with `TrainingWeek.isDeload` marking week 4 — the "Week-4
   autoregulation" behavior `STAGE3_DECISION_MEMO.md`/
   `PowerliftingRegressionTests` already exercise).
2. **The current `TrainingPhase`'s own remaining time** — a window is
   never generated longer than the phase has left; if a phase transition
   is expected in 2 weeks, the window is capped at 2 weeks even if the
   program's natural block is longer, so tactical materialization never
   reaches into what will become a *different* mix under the next phase.
3. **Upcoming transition dates** — same rule as (2), generalized to any
   known future boundary (a milestone-anchored phase end, an accepted
   revision's new phase start).
4. **A configurable fallback** (illustrative default: 4 weeks) — used
   only when a system has no natural block length of its own (e.g. a
   single repeating steady-state week).

**Performance-dependent progression is never fabricated ahead of the
window it belongs to** — materialization for week 5 does not exist
until the next tactical window is generated, regardless of how long the
current one is; a longer natural block does not mean more weeks get
real numbers sooner, only that fewer separate windows are needed to
cover it.

## 2. Rolling window triggers — deterministic, never a bare timer (Decision 7, RESOLVED)

**Architecture locked now; the 7-day scheduling-buffer default is a
configurable number, not locked.** A new tactical window is generated
only when one of these fires — never merely because calendar time
passed, and never on an implicit background timer:

1. **Current window approaches its end** — today is within a configured
   buffer (illustrative default: 7 days) of the window's last placed day,
   leaving lead time to review/approve the next one.
2. **Current window completes** — a fallback catch-up trigger for when
   (1)'s lead time was missed entirely (e.g. the app wasn't opened) and
   the window has already fully elapsed with no successor generated yet.
3. **Phase changes** (`PHASE_PLANNING_RULES.md` §4) — the new phase's
   mix needs its own first tactical window immediately.
4. **User changes `TrainingMix`/preferences materially** — a bounded
   temporary mix accepted or its expiry/materiality prompt resolved
   (`ADHERENCE_AWARE_PLANNING.md` §2/§2a), or a stable preference/mix
   swap accepted directly — any of these invalidate the premise of
   whatever window was previously planned.
5. **Pause/return causes tactical reflow** — the user pauses training
   (no new window generated while paused) and later resumes (a fresh
   window is generated from the resume date, not backfilled for missed
   time).
6. **Strategic plan is revised** (`PLAN_REVISION_MODEL.md` §4) — any
   accepted revision, minor or major, invalidates the premise of
   whatever window was previously planned.

Every trigger is an explicit event or an explicit date comparison against
a caller-supplied "now" (mirroring `SchedulingWindow.startDate`'s own
discipline — the planner is never the one reading the system clock).

**A previously accepted tactical window is a historical snapshot** —
generating window N+1 never mutates window N's already-materialized
`Session`/`Day` placements, by construction
(`PLAN_REVISION_MODEL.md` §4d states the same invariant for strategic
revisions; this is its tactical-layer counterpart).

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
weekProgress        <- elapsed weeks / PhaseDurationKind's resolved typical value (or endDate)
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
