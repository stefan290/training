# Long-Term Planner

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

## 2. The required pipeline

```
LongTermGoal                              (extended Goal — STRATEGIC_PLAN_MODEL.md §1)
  ↓
LongTermPlanner                           (new Application-layer engine — §5)
  ↓
StrategicPlan                             (= existing TrainingPlan — STRATEGIC_PLAN_MODEL.md §2)
  ↓
TrainingPhase                             (existing entity, unchanged shape — PHASE_PLANNING_RULES.md §1)
  ↓
RecommendedTrainingMix                    (existing TrainingMix, kind == .recommended)
  ↓
ProgramGenerator(s)                       (existing: Hypertrophy/Powerlifting/SteadyState/Interval/FunctionalFitness)
  ↓
ProgramDefinition / ProgramInstance       (existing, unchanged)
  ↓
Sessions                                  (existing, unchanged — materializer-produced, naive dates)
  ↓
SchedulingPipeline                        (existing, Stage 4G)
  ↓
ScheduleProposal + GoalAlignment          (existing, Stage 4G)
  ↓
User approval                             (existing pattern: Engine recommendation -> Explanation -> User approval)
  ↓
TacticalPlan / accepted schedule          (= accepted Sessions via AcceptScheduleProposalUseCase — TACTICAL_PLANNING_HANDOFF.md)
```

**Validated: every downstream stage from `RecommendedTrainingMix` onward
already exists and is already tested (298 tests through Stage 4F, 310
through Stage 4G).** `LongTermPlanner`'s entire job is producing the
first four boxes — a `TrainingPlan` with ordered `TrainingPhase`s, each
carrying a `RecommendedTrainingMix` — and handing the *current* phase's
mix into the exact same `ScheduledProgramInput`/`SchedulingConstraints`/
`SchedulingPipeline.propose` contract any test in
`ConcurrentSchedulerTests`/`SchedulerHardeningTests` already exercises.
Nothing about the scheduler, `GoalAlignmentEvaluator`, or any
`ProgrammingSystem` needs to change to support this — confirmed during
this pass's own review, per the kickoff's instruction to stop and explain
if a genuine incompatibility were found. None was.

## 2a. The decision hierarchy (locked, resolves all four Stage 5A MUST RESOLVE items)

Every candidate a caller ever asks the planner to rank — mixes,
programs, or a revised roadmap — passes through the same five ordered
stages, never in a different order and never with a later stage
overriding an earlier one's rejection:

```
HARD FEASIBILITY
  ↓   (can this even be scheduled? — ScheduleFeasibility/PROGRAM_RECOMMENDATION_MODEL.md §2a's
       narrow, mechanical Infeasible definition. Fails here -> Infeasible, out, full stop.)
GOAL ALIGNMENT
  ↓   (given it's feasible, how well does it serve the phase's goal? — GoalAlignmentEvaluator,
       unmodified. Produces the qualitative rating everything downstream reads.)
CANDIDATE QUALITY / COMPATIBILITY GATE
  ↓   (is this candidate's alignment at or above the compatibility threshold —
       ADHERENCE_AWARE_PLANNING.md §5a? Below the gate -> shown only as Poor Fit,
       never eligible for promotion, never Infeasible on this basis alone.)
ADHERENCE / USER PREFERENCE
  ↓   (among gated-in candidates only, does stated preference/variety/adherence
       favor one enough to reorder — ADHERENCE_AWARE_PLANNING.md §5b's
       tier-gap-bounded promotion rule?)
RANKED RECOMMENDATION
      (.recommended + .bestGoalAlignment (when different) + at most 2 further
       alternatives — ADHERENCE_AWARE_PLANNING.md §5c. User choice remains final:
       any candidate the user actually selects is scheduled, whatever its rank.)
```

**Hard constraints determine what is possible. `GoalAlignment` determines
how well it serves the current phase. Preference/adherence can reorder
viable, sufficiently compatible options. User choice remains final.**
This is the single hierarchy every Stage 5A document now implements —
`PHASE_PLANNING_RULES.md` §8 (protected-minimum shortfalls), 
`PROGRAM_RECOMMENDATION_MODEL.md` §2a (Infeasible/Poor Fit), and
`ADHERENCE_AWARE_PLANNING.md` §5 (candidate ranking) are three
applications of it, not three separate rules.

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
LongTermPlanner.proposeStrategicPlan(goal: LongTermGoal, asOf: Date) -> StrategicPlanProposal
LongTermPlanner.proposeTrainingMix(phase: TrainingPhase, goal: LongTermGoal) -> [CandidateTrainingMix]
LongTermPlanner.proposeProgram(component: TrainingMixComponent, profile: PerformanceProfile, equipment: EquipmentProfile) -> [ProgramCandidate]
LongTermPlanner.reviseStrategicPlan(current: TrainingPlan, revision: PlanRevisionRequest, asOf: Date) -> StrategicPlanProposal
```

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

## 6. What already exists vs. what Stage 5B would add

| Concept | Status |
|---|---|
| `TrainingPlan`, `PlanStatus` | Exists (Stage 1-2), unchanged |
| `TrainingPhase`, `PhaseType`, `PhaseStatus`, `TrainingPriority` | Exists (Stage 1-2/3C), unchanged shape |
| `Goal`, `GoalType`, `GoalStatus` | Exists (Stage 1-2); extension proposed, not a new type — `STRATEGIC_PLAN_MODEL.md` §1 |
| `TrainingMix`/`TrainingMixComponent`, `GoalPriority`, `ComponentFlexibility` | Exists (Stage 4F/4G), unchanged — this pass reuses them directly for phase goal composition |
| `ScheduledProgramInput`/`SchedulingConstraints`/`SchedulingPipeline` | Exists (Stage 4F/4G), unchanged |
| `LongTermPlanner` engine | **New in Stage 5B** — proposed shape only, §5 |
| `PlannerDecision` (reason-coded provenance) | **New in Stage 5B** — `PLAN_REVISION_MODEL.md` §2 |
| `StrategicPlanProposal`/`CandidateTrainingMix`/`ProgramCandidate`/`PlanRevisionRequest` | **New in Stage 5B** — plain value types, mirroring `ScheduleProposal`'s own "transient, non-persisted" shape |
| Program recommendation reasoning | **New in Stage 5B** — `PROGRAM_RECOMMENDATION_MODEL.md` |

No existing type's *meaning* changes. Every new type is additive, and
every new persisted field (if any survive `STAGE5A_DECISION_MEMO.md`'s
open questions) is optional, matching this codebase's established
migration discipline throughout Stage 3C-4G.

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
