# Long-Term Planner

**Stage 5B status: implemented.** `LongTermPlanner` (`Application/UseCases/LongTermPlanner.swift`)
implements `proposeProgram`, `proposeTrainingMix`, `proposeStrategicPlan`
and `reviseStrategicPlan` exactly per this document's §5 signatures (plus
`AcceptStrategicPlanUseCase`/`SwitchTrainingModalityUseCase` as the
explicit acceptance steps §5 calls for). See `STAGE5B_IMPLEMENTATION_REPORT.md`
for what was built, which illustrative fixture numbers were chosen, and
the small number of deliberately deferred nuances (each flagged with a
code comment at its exact call site, never silently decided). Everything
below is retained as the original Stage 5A design record; where the
implementation made a concrete choice among several this document left
open, the report is the authoritative account, not a rewrite of history
here.

Stage 5A: architecture for turning a long-term user goal into executable
training, without duplicating any existing system. **This is a
design/domain/algorithm specification pass — nothing in this document is
implemented yet.** No new `@Model` type, engine, or use case described
here exists in the codebase as of this document; see
`STAGE5A_DECISION_MEMO.md` for what's still open before Stage 5B may
build any of it.

## 1. The core product principle

TrainingOS optimizes for **the best long-term training path the user is
likely to follow** — not the theoretically perfect one. A recommendation
nobody performs produces zero adaptation; a good-enough plan a user
actually runs produces real adaptation. Every model in this document
exists to make that principle concrete rather than aspirational:
`RecommendedTrainingMix`/`UserSelectedTrainingMix` are equally real,
equally schedulable outcomes (§5), variety and modality preference are
first-class planning inputs (`ADHERENCE_AWARE_PLANNING.md`), and nothing
here ever silently reverts a user's choice back to what the system would
have preferred.

This is CLAUDE.md rule 14, restated as an implementation mandate for this
specific system: *"TrainingOS optimizes for long-term goal alignment
subject to explicit user training preferences and adherence. User-selected
training modalities must not be silently replaced by theoretically more
optimal modalities."*

## 2. The required pipeline (locked, final)

```
LONG-TERM GOAL                  (primary + secondary/protected objectives + milestone
                                  — extended Goal, STRATEGIC_PLAN_MODEL.md §1)
  ↓
STRATEGIC PLAN REVISION          (= existing TrainingPlan, revision-lineage-aware
                                  — STRATEGIC_PLAN_MODEL.md §2, PLAN_REVISION_MODEL.md §4)
  ↓
TRAINING PHASE                   (strategic objective, NOT modality composition
                                  — existing entity, unchanged shape, PHASE_PLANNING_RULES.md §1)
  ↓
CANDIDATE TRAINING MIXES         (existing TrainingMix/TrainingMixComponent, kind == .recommended
                                  — ADHERENCE_AWARE_PLANNING.md §5)
  ↓
EXECUTABILITY / CAPABILITY CHECK (NEW gate — ProgramCapabilityRegistry,
                                  PROGRAM_RECOMMENDATION_MODEL.md §5 — runs BEFORE alignment)
  ↓
GOAL ALIGNMENT                   (existing GoalAlignmentEvaluator, Stage 4G, unmodified)
  ↓
PROGRAM / MIX QUALITY            (ProgramFitFactor/ProgramCandidate ranking,
                                  PROGRAM_RECOMMENDATION_MODEL.md §1-3)
  ↓
ADHERENCE / USER PREFERENCE      (bounded promotion among compatible candidates only
                                  — ADHERENCE_AWARE_PLANNING.md §5a-5b)
  ↓
RANKED RECOMMENDATION            (.recommended + .bestGoalAlignment + ≤2 alternatives
                                  — ADHERENCE_AWARE_PLANNING.md §5c)
  ↓
USER SELECTION                   (any candidate the user actually picks is honored,
                                  whatever its rank — §1 above)
  ↓
PROGRAM GENERATORS / DEFINITIONS (existing: Hypertrophy/Powerlifting/SteadyState/Interval/FunctionalFitness)
  ↓
ROLLING TACTICAL WINDOW          (existing materializers, naive dates
                                  — TACTICAL_PLANNING_HANDOFF.md §1-2)
  ↓
SCHEDULING PIPELINE               (existing, Stage 4G)
  ↓
USER APPROVAL                     (existing pattern: Engine recommendation -> Explanation -> User approval)
  ↓
EXECUTION / PERFORMANCE PROFILE  (accepted Sessions via AcceptScheduleProposalUseCase;
                                  PerformanceProfile accrues permanently, unchanged)
```

**Validated: every stage from PROGRAM GENERATORS / DEFINITIONS onward
already exists and is already tested (298 tests through Stage 4F, 310
through Stage 4G).** `LongTermPlanner`'s entire job is everything above
that line — producing a `TrainingPlan` revision with ordered
`TrainingPhase`s, ranking candidate mixes/programs through the
capability/alignment/preference gates, and handing the *selected*
mix/program into the exact same `ScheduledProgramInput`/
`SchedulingConstraints`/`SchedulingPipeline.propose` contract any test in
`ConcurrentSchedulerTests`/`SchedulerHardeningTests` already exercises.
Nothing about the scheduler, `GoalAlignmentEvaluator`, or any
`ProgrammingSystem` needs to change to support this — confirmed during
this pass's own review, per the kickoff's instruction to stop and explain
if a genuine incompatibility were found. None was.

## 2a. Two distinct feasibility gates — never conflated

The pipeline above has **two** different "can this even happen" checks,
at two different stages, answering two different questions — collapsing
them into one "Hard Feasibility" concept (this document's own earlier
draft) was itself a conflation worth correcting:

1. **EXECUTABILITY / CAPABILITY CHECK** (early, right after candidate
   mixes are proposed) — can TrainingOS actually *instantiate* a real
   `ProgramDefinition` for this candidate at all?
   `ProgramCapabilityRegistry`, `PROGRAM_RECOMMENDATION_MODEL.md` §5. A
   candidate that fails this never becomes a `ProgramCandidate` — it
   becomes a `CapabilityGap`, surfaced as "Unavailable / not currently
   executable," never disguised as a normal recommendation.
2. **Scheduling feasibility** (late, inside SCHEDULING PIPELINE) — given
   an executable, alignment-ranked, user-approved mix, can it actually
   be *placed on the calendar* within real availability?
   `ScheduleFeasibility`/`GoalAlignmentRating.infeasible`,
   `PROGRAM_RECOMMENDATION_MODEL.md` §2a's narrow, mechanical definition
   — unchanged from Stage 4G.

A candidate can pass (1) and still fail (2) later (conceptually
buildable, but this user's specific availability can't fit it) — the two
gates are independent, and neither is a stand-in for the other.

## 2b. The ranking hierarchy (locked) — the middle five stages, zoomed in

```
GOAL ALIGNMENT
  ↓   (given it's executable, how well does it serve the phase's goal? — GoalAlignmentEvaluator,
       unmodified. Produces the qualitative rating everything downstream reads.)
PROGRAM / MIX QUALITY / COMPATIBILITY GATE
  ↓   (is this candidate's alignment at or above the compatibility threshold —
       ADHERENCE_AWARE_PLANNING.md §5a? Below the gate -> shown only as Poor Fit,
       never eligible for promotion, never Infeasible on this basis alone.)
ADHERENCE / USER PREFERENCE
  ↓   (among gated-in candidates only, does stated preference/variety/adherence
       favor one enough to reorder — ADHERENCE_AWARE_PLANNING.md §5b's
       tier-gap-bounded promotion rule?)
RANKED RECOMMENDATION
  ↓   (.recommended + .bestGoalAlignment (when different) + at most 2 further
       alternatives — ADHERENCE_AWARE_PLANNING.md §5c.)
USER SELECTION
      (User choice remains final: any candidate the user actually selects is
       scheduled, whatever its rank.)
```

**Executability determines what can be built. `GoalAlignment` determines
how well it serves the current phase. The compatibility gate determines
which candidates are even eligible to be promoted. Preference/adherence
can reorder only among those. User choice remains final.** This is the
single hierarchy every Stage 5A document now implements —
`PHASE_PLANNING_RULES.md` §8 (protected-minimum shortfalls),
`PROGRAM_RECOMMENDATION_MODEL.md` §2a/§5 (Infeasible/Poor Fit,
capability), and `ADHERENCE_AWARE_PLANNING.md` §5 (candidate ranking) are
four applications of it, not four separate rules.

## 3. Engine boundaries — what `LongTermPlanner` decides, and what it never touches

**`LongTermPlanner` decides:**

- Which `TrainingPhase`s make up a `TrainingPlan`, in what order, with
  what approximate duration and transition criteria.
- Each phase's priorities — which adaptation is primary, which is
  protected, which is merely supporting (§9's phase goal composition —
  see `PHASE_PLANNING_RULES.md` §2).
- A `RecommendedTrainingMix` for each phase (component labels, priorities,
  frequencies, flexibility, preferred days) — the same
  `TrainingMix`/`TrainingMixComponent` types Stage 4F already defines,
  populated by the planner instead of by a test fixture.
- Which existing `ProgramDefinition`/generator configuration each mix
  component should use (`PROGRAM_RECOMMENDATION_MODEL.md`).
- When to hand off to tactical materialization + scheduling
  (`TACTICAL_PLANNING_HANDOFF.md`).

**`LongTermPlanner` never:**

- Calculates a load, rep target, pace, or interval progression — that is
  `StrengthProgressionEngine`/`SteadyStateProgressionEngine`/
  `IntervalProgressionEngine`/`FunctionalFitnessDecisionEngine`'s job,
  unchanged.
- Invents a CrossFit movement, exercise, or benchmark — that is the
  relevant generator/materializer's job, unchanged.
- Places a session on a specific calendar day — that is
  `ConcurrentScheduler`'s job, unchanged (CLAUDE.md rule 15).
- Rewrites a Strict program's methodology — see
  `PROGRAM_RECOMMENDATION_MODEL.md` §4 for exactly what "Strict" still
  means here.
- Predicts adherence/motivation via any opaque model — see
  `ADHERENCE_AWARE_PLANNING.md` §4.

This mirrors every existing engine boundary in this codebase exactly:
`ConcurrentScheduler` schedules, it does not progress methodology
(CLAUDE.md rule 15); `ProgrammingDecisionEngine` conformers decide
variance, they do not generate a template graph. `LongTermPlanner` is one
more layer in the same stack, not a parallel authority — it decides
*composition and sequencing*, then delegates *everything about how a
session's numbers are computed* to systems that already do that
correctly and are already tested.

## 4. Two entry flows: Guided Planning and Start From Program

Both flows produce the same downstream artifacts (a `TrainingPlan` with a
current `RecommendedTrainingMix`/`UserSelectedTrainingMix`) — they differ
only in which end the user starts from.

**Guided Planning** (§57):
```
Goal -> timeframe -> milestone -> availability -> preferences
  -> proposed strategic roadmap (TrainingPhase sequence)
  -> recommended TrainingMix for the current phase
  -> recommended Program(s) for that mix's components
  -> tactical plan -> start
```

**Start From Program** (§58):
```
User selects an existing ProgramDefinition (e.g. "5-Day Hypertrophy")
  -> goal/context captured (what is this program serving?)
  -> availability
  -> long-term phase placement (which phase does this become/start?)
  -> surrounding Modules recommended (what fills the remaining days?)
  -> tactical plan
```

`LongTermPlanner` works *around* the selected program in the second flow
— the same "planner recommends, user may substitute, planner adapts
around the substitution" pattern §11/§18/§19 require for a mix
component, just entered from the opposite direction. No second code path
is needed: Start From Program is Guided Planning with one component's
selection already fixed before the recommendation step runs, evaluated
via the identical `GoalAlignment` machinery (§13 below).

## 5. `LongTermPlanner` as an engine — shape, not implementation

Following the same "pure function(s), typed input, typed output, reason
codes" shape every engine in this codebase already uses
(`ConcurrentScheduler.schedule`, `GoalAlignmentEvaluator.evaluate`,
`ProgrammingDecisionEngine`), `LongTermPlanner`'s eventual (Stage 5B)
surface is expected to be:

```
LongTermPlanner.proposeStrategicPlan(goal: Goal, asOf: Date) -> StrategicPlanProposal
LongTermPlanner.proposeTrainingMix(phase: TrainingPhase, goal: Goal) -> [CandidateTrainingMix]
LongTermPlanner.proposeProgram(component: TrainingMixComponent, profile: PerformanceProfile, equipment: EquipmentProfile)
    -> (candidates: [ProgramCandidate], gaps: [CapabilityGap])
LongTermPlanner.reviseStrategicPlan(current: TrainingPlan, revision: PlanRevisionRequest, asOf: Date) -> StrategicPlanProposal
```

`proposeProgram`'s two-part return is deliberate, not incidental: a
`ProgramCandidate` is always executable (§2a); a `CapabilityGap` never is
— returning them as two separate collections, rather than one list mixing
both, makes it structurally impossible for a UI to accidentally render a
gap as if it were a normal, startable option
(`PROGRAM_RECOMMENDATION_MODEL.md` §5).

Every one of these is a **proposal-producing, non-mutating** call,
continuing the Engine-recommendation → Explanation → User-approval
pattern `ConcurrentScheduler`/`AcceptScheduleProposalUseCase` already
established: nothing above ever writes to a `TrainingPlan`/`TrainingPhase`/
`TrainingMix` directly. A separate, explicit acceptance step (mirroring
`AcceptScheduleProposalUseCase`) is what turns a `StrategicPlanProposal`
into persisted `TrainingPhase`/`TrainingMix` rows — see
`PLAN_REVISION_MODEL.md` §4. `asOf: Date` is passed explicitly by the
caller everywhere a "how far are we into the plan" computation is needed
— `LongTermPlanner` never reads the system clock itself, mirroring
`SchedulingWindow.startDate`'s identical discipline (CLAUDE.md rule 4,
extended to planning).

## 6. What already exists vs. what Stage 5B would add (final, all 7 engineering items resolved)

| Concept | Status |
|---|---|
| `TrainingPlan`, `PlanStatus` | Exists (Stage 1-2); **+2 new fields** (`supersedes: TrainingPlan?`, `lineageID: UUID`) — `PLAN_REVISION_MODEL.md` §4 |
| `TrainingPhase`, `PhaseType`, `PhaseStatus`, `TrainingPriority` | Exists (Stage 1-2/3C), **unchanged shape, zero new `PhaseType` cases** (`PhaseType.hybrid` explicitly withdrawn — `PHASE_PLANNING_RULES.md` §1) |
| `Goal`, `GoalType`, `GoalStatus` | Exists (Stage 1-2); extended in place — `secondaryTypes: [GoalType]` → `secondaryObjectives: [SecondaryObjective]`, plus new `milestoneDate`/`bodyCompositionDirection`/`preferences` — `STRATEGIC_PLAN_MODEL.md` §1 |
| `SecondaryObjective`, `SecondaryObjectiveRole`, `BodyCompositionDirection`, `GoalPreferences`, `ModalityPreference`, `VarietyPreference` | **New in Stage 5B** — small `Codable` value types on `Goal`, no new `@Model` entity — `STRATEGIC_PLAN_MODEL.md` §1 |
| `TrainingMix`/`TrainingMixComponent`, `GoalPriority`, `ComponentFlexibility` | Exists (Stage 4F/4G), unchanged — this pass reuses them directly for phase goal composition |
| `ScheduledProgramInput`/`SchedulingConstraints`/`SchedulingPipeline` | Exists (Stage 4F/4G), unchanged |
| `LongTermPlanner` engine | **New in Stage 5B** — proposed shape only, §5 |
| `PlannerDecision`, `PlannerDecisionType`, `DecisionSource`, `ConsideredAlternative` | **New in Stage 5B** — `PLAN_REVISION_MODEL.md` §2 |
| `PhaseDurationKind` | **New in Stage 5B** — planner-internal value type, no new `TrainingPhase` field — `STRATEGIC_PLAN_MODEL.md` §4a |
| `ProgramCapabilityRegistry`, `ProgramSystemCapability`, `CapabilityGap`, `CapabilityGapReason` | **New in Stage 5B** — read-only query layer over existing generators/`V1_PROGRAM_LIBRARY.md`, no new persistence — `PROGRAM_RECOMMENDATION_MODEL.md` §5 |
| `StrategicPlanProposal`/`CandidateTrainingMix`/`ProgramCandidate`/`PlanRevisionRequest` | **New in Stage 5B** — plain value types, mirroring `ScheduleProposal`'s own "transient, non-persisted" shape |
| Program recommendation reasoning | **New in Stage 5B** — `PROGRAM_RECOMMENDATION_MODEL.md` |

No existing type's *meaning* changes; `TrainingPlan`/`Goal` each gain a
small, additive/narrowly-migrated set of fields (detailed above), every
other type is wholly new and additive. Zero blocking open questions
remain — see `STAGE5A_DECISION_MEMO.md`'s final status.

## 7. Document map

- `STRATEGIC_PLAN_MODEL.md` — `LongTermGoal`, `StrategicPlan` (=
  `TrainingPlan`), important-date backward planning, rolling planning.
- `PHASE_PLANNING_RULES.md` — phase goal composition, transition
  criteria, extension/shortening, per-goal-type phase architecture
  (fat loss / muscle gain / maintenance / hybrid transition).
- `PROGRAM_RECOMMENDATION_MODEL.md` — program/config recommendation
  reasoning, compatibility ratings, Strict/Adaptive handling.
- `ADHERENCE_AWARE_PLANNING.md` — variety, temporary modality switches,
  recommended alternatives, adherence-signal boundaries.
- `PLAN_REVISION_MODEL.md` — `PlannerDecision`, versioning/audit,
  planned-vs-actual, goal changes.
- `TACTICAL_PLANNING_HANDOFF.md` — tactical horizon, rolling window
  triggers, phase-start procedure, UI data contracts.
- `STAGE5A_DECISION_MEMO.md` — what must be resolved before Stage 5B,
  what's safely assumed, what's deliberately deferred.
