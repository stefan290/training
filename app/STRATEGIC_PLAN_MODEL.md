# Strategic Plan Model

`LongTermGoal` and `StrategicPlan` — the two concepts sitting above
`TrainingPhase` in `LONG_TERM_PLANNER.md`'s pipeline. The central finding
of this document: **neither needs a new persisted container.**
`StrategicPlan` maps directly onto the existing `TrainingPlan`/`PlanStatus`
entities, and `LongTermGoal` is proposed as an additive extension of the
existing `Goal` entity, not a new parallel type.

## 1. `LongTermGoal` — extends `Goal` compositionally (RESOLVED)

**Resolution:** `Goal` gains a small number of typed value fields —
never one giant object of unrelated nullable scalars, and never a
proliferation of new `@Model` entities. One existing field changes shape
(a justified, narrow migration); everything else is additive.

### 1a. Objectives — one primary, zero or more role-tagged secondaries

`Goal.primaryType: GoalType` is unchanged — still exactly one primary
objective. `secondaryTypes: [GoalType]` (an undifferentiated list) is
replaced by `secondaryObjectives: [SecondaryObjective]`, a strict
superset of the same information:

```swift
enum SecondaryObjectiveRole: String, Codable, CaseIterable {
    /// Downstream, this becomes a `.secondary`+`.required`
    /// `TrainingMixComponent` when the planner builds a phase's mix —
    /// PHASE_PLANNING_RULES.md §2a's exact "protected" pattern, now
    /// traceable back to the goal that asked for it.
    case protected
    case supporting
}

struct SecondaryObjective: Codable, Equatable {
    var type: GoalType
    var role: SecondaryObjectiveRole
}
```

**No new `GoalType` cases are needed.** Checking every required family
against the existing enum (`muscleGain, fatLoss, generalStrength,
enduranceEvent, functionalFitness, maintenance`) confirms full coverage:

| Required family (kickoff) | Existing `GoalType` |
|---|---|
| Muscle Gain | `.muscleGain` |
| Fat Loss | `.fatLoss` |
| Maintenance | `.maintenance` |
| Strength / Powerlifting performance | `.generalStrength` |
| Running performance | `.enduranceEvent` + `ModalityPreference.activityType == .running` + a `performanceGoals` label |
| Aerobic/endurance development | `.enduranceEvent` (undifferentiated from "running performance" at the objective level — the distinction is modality/intensity-focus detail, not a different strategic objective, per the same reasoning that removed `PhaseType.hybrid` — see `PHASE_PLANNING_RULES.md` §1) |
| Functional Fitness performance | `.functionalFitness` |

This mirrors Decision 3's own finding one layer up: **objective family
and modality/performance detail are different concepts**, and collapsing
"running" and "generic aerobic development" into two separate `GoalType`
cases would repeat the exact mistake `PhaseType.hybrid` made.

### 1b. Milestone, body-composition direction, and preferences

Three more additions, none of them a new entity:

| Field | Type |
|---|---|
| `milestoneDate` | `Date?` — §3 below |
| `bodyCompositionDirection` | `BodyCompositionDirection?` (new: `.gainMuscle`/`.loseFat`/`.maintain`/`.recomposition`) — independent of `primaryType`/`secondaryObjectives`; body-composition direction and training modality are different concepts (a `.generalStrength` primary objective can still carry a `.loseFat` direction) |
| `preferences` | `GoalPreferences?` — **one** bundled optional struct, not nine loose scalars |

```swift
struct GoalPreferences: Codable, Equatable {
    var preferredModalities: [ModalityPreference] = []
    var dislikedModalities: [ModalityPreference] = []
    var varietyPreference: VarietyPreference = .moderate
    var priorityMuscleGroups: [MuscleGroup] = []
    var performanceGoals: [String] = []
    var availableTrainingDaysPerWeek: Int?
    var typicalSessionDurationMinutes: Int?
    var allowsDoubleSessions: Bool?
}
```

A `Goal` with `preferences == nil` simply has no stated preference
context yet — every planner call degrades to coarser recommendations,
never fails, satisfying "do not require every field" the same way every
other optional field in this schema already does.

**Net schema change to `Goal`:** one field changes shape
(`secondaryTypes: [GoalType]` → `secondaryObjectives: [SecondaryObjective]`,
a narrow, behavior-preserving migration — old call sites recover the
prior list via `.map(\.type)`), and three fields are added
(`milestoneDate`, `bodyCompositionDirection`, `preferences`). No new
`@Model` entity. This resolves the prior "extend `Goal` directly vs. a
companion entity" question in favor of direct extension, per explicit
product-owner decision — reversing this document's own earlier
recommendation of a separate `LongTermGoalProfile` entity.

### 1c. Why `performanceGoals` stays a plain label for now

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

### 1d. `ModalityPreference` — reusing existing vocabulary, not inventing new

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

### 1e. Why availability fields here are coarse, not a full `UserAvailability`

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

### 4a. `PhaseDurationKind` — architecture locked, numbers explicitly not (RESOLVED)

**Resolution: the architecture below is locked now. The specific weeks
in any table are not — they remain TRAININGOS_DESIGNED, configurable
fixtures, never a claim of validated physiology, and are free to change
without touching this shape.**

A phase's duration is determined one of four distinct ways — richer than
a single min/target/max range, since "runs until a specific/milestone
date" and "a program's own fixed block length" are genuinely different
*kinds* of duration, not different numbers within one range:

```swift
enum PhaseDurationKind: Codable, Equatable {
    /// An exact length — e.g. a selected program's own fixed mesocycle
    /// (Strict programs commonly run in fixed 4-week blocks).
    case fixed(weeks: Int)
    /// The original min/target/max range shape (`SessionFrequency`'s own
    /// convention, reused here) — the common case for a phase with no
    /// externally-fixed length.
    case range(typical: Int, minimum: Int?, maximum: Int?)
    /// Runs until an explicit date (already resolved elsewhere — e.g. a
    /// milestone-anchored phase whose end date backward-planning has
    /// already computed).
    case untilDate(Date)
    /// Runs until `Goal.milestoneDate` — computed relative to the goal,
    /// not a literal stored date, so it stays correct if the milestone
    /// itself is later revised (`PLAN_REVISION_MODEL.md`).
    case untilMilestone
}
```

**What's deliberately *not* in this type:** "planner-recommended" and
"user-extended/shortened" are not separate `PhaseDurationKind` cases —
they're `PlannerDecision`-level *provenance* (who chose this value and
why, `PLAN_REVISION_MODEL.md` §2), not a different shape of the value
itself. A user-extended phase still resolves to one of the four cases
above (typically `.range` with an adjusted `typical`); the fact that it
was user-extended is recorded as a `PHASE_EXTENDED`-reason-coded
`PlannerDecision`, not encoded into the duration value. This keeps
`PhaseDurationKind` a pure description of the value, never conflating
data with audit trail.

`TrainingPhase.endDate` remains the single source of truth for the
actual, concrete boundary once a `PhaseDurationKind` is resolved at
proposal-construction time — no new persisted field is needed on
`TrainingPhase` itself; `PhaseDurationKind` is planner-internal
machinery, not new schema.

**Where the default `.range` numbers live (architecture decided now):** a
static Swift default table (mirroring `InterferenceAvoidanceRule
.conservativeDefault`'s exact "real default, always overridable per-call"
pattern) — deliberately built so the *source* of the default can migrate
to a persisted, owner-editable settings surface later without any caller
changing, since every consumer already takes the resolved policy as a
parameter.

**Illustrative-only fixture numbers** (for Stage 5B's own deterministic
tests, not a physiology claim, and not required to be finalized before
implementation starts):

| `PhaseType` | kind | typical | minimum | maximum |
|---|---|---|---|---|
| `muscleGain` | `.range` | 12 weeks | 6 | 20 |
| `fatLoss` | `.range` | 8 weeks | 4 | 12 |
| `maintenance` | `.range` | 4 weeks | 2 | 8 |
| `recovery` | `.range` | 2 weeks | 1 | 4 |
| `transition` | `.range` | 2 weeks | 1 | 3 |
| `strength` | `.range` | 8 weeks | 4 | 12 |
| `enduranceEvent` | `.untilMilestone` or `.range`, context-dependent | — | — | — |

`ADHERENCE_AWARE_PLANNING.md` §2a's temporary-preference materiality
check reads whichever `typical` value the enclosing phase's resolved
`PhaseDurationKind` carries (when it's `.range`) — same non-blocking,
configurable-fixture status applies there too.

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
