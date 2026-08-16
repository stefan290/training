# Goal Alignment

Stage 4G's hardening of Stage 4F's two weakest points: `GoalAlignmentEvaluator`
no longer infers anything from display text, and priority/conflict
resolution reflects real, configuration-driven scheduling priority rather
than "whichever component was processed first." This document is the
one place that describes both together, since they're two views of the
same underlying contract: `ScheduleIssue` (structured facts about a
`ScheduleProposal`) is what makes `GoalAlignment` (structured facts about
how well a `TrainingMix` fit) possible without parsing anything.

## 1. Why this pass exists

Stage 4F's own implementation report flagged two known weak points
before any Long-Term Planner work could safely start:

1. `GoalAlignmentEvaluator` detected two of its factors by matching
   substrings in `ScheduleProposal.warnings` — human-readable text. That
   made "does this mix have an interference compromise" depend on
   exactly how a sentence was worded, which is fragile and, more
   importantly, is exactly the kind of coupling that breaks silently the
   first time someone rewords a message for the UI.
2. `.primaryGoalPriority` was tagged on every primary-tier placement
   regardless of whether a real conflict existed — it recorded *when* a
   component was processed, not whether priority *decided* anything.

Both are fixed structurally, not just patched: `ScheduleProposal.warnings`
is now a **computed** property (`issues.map(\.reason)`), so there is no
way to construct a proposal where the display text and the structured
facts disagree in a way that matters to business logic — changing one
cannot change the other's *meaning*, only its wording.

## 2. `ScheduleIssue` — the structured signal vocabulary

`ScheduleIssueCode` (11 cases) classifies every compromise or failure a
`ScheduleProposal` can contain. Each carries a fixed `IssueSeverity`
character (not literally a stored field on the code — severity is
assigned by whoever constructs the issue, but each code has one natural
severity described below):

| Code | Natural severity | Meaning |
|---|---|---|
| `unavailableDay` | hard | Every candidate weekday was excluded by availability. |
| `maxSessionsExceeded` | hard | Every candidate would have exceeded `maxSessionsPerDay` (including "no room to double"). |
| `insufficientTime` | hard | `minutesAvailablePerDay` couldn't fit the session's estimated duration on any candidate day. |
| `requiredFrequencyUnsatisfied` | hard | A `.required` component missed its minimum/target. |
| `preferredFrequencyUnsatisfied` | soft | A `.preferred` component missed its minimum/target. |
| `interferenceConflict` | soft | A soft `InterferenceAvoidanceRule` had to be violated to place a session at all. |
| `recoverySpacingCompromise` | hard | A component's own required spacing could not be honored for at least one session (declared for vocabulary completeness — spacing is enforced as a hard constraint today, so this only ever fires as the classification of a conflict, never as an accepted soft compromise; see `FunctionalFitnessReasonCode`'s "reserved code" precedent in `STAGE4_IMPLEMENTATION_REPORT.md`'s Stage 4E section). |
| `primaryGoalCompromise` | hard | The mix's primary-priority component ended up with an unplaced session — the single most serious signal this system produces. |
| `preferenceCompromise` | soft | A session could not land on any of its component's preferred days. |
| `optionalComponentUnscheduled` | soft | A `.optional` component ended up with zero placed sessions — accepted, not urgent. |
| `doubleSessionRequired` | soft | A session could only be placed by doubling — every one of its own hard-valid days was already occupied, so pairing wasn't a preference, it was the only option. |

`GoalAlignmentEvaluator` and any future UI must read `code`/`severity`/
`componentLabel`/`session` — never `reason`, which is display copy
generated FROM those fields and safe to reword freely.

## 3. `GoalAlignment` — 7 structured factors, never a percentage

`GoalAlignmentFactorKind` has exactly 7 cases, each computed from
`proposal.issues`/`.placements` typed data only:

| Factor | Satisfied when | Reads |
|---|---|---|
| `primaryStimulusCoverage` | No `.primaryGoalCompromise` issue. | `issues` |
| `requiredComponentSatisfaction` | No `.requiredFrequencyUnsatisfied` issue. | `issues` |
| `targetFrequencySatisfaction` | Every component (any flexibility) reached its minimum-or-target placed count. | `placements` counts vs. `mix.orderedComponents` |
| `supportingGoalCoverage` | Every non-primary component has ≥1 placement. | `placements` counts |
| `userSelectedPreferenceSatisfaction` | No `.preferenceCompromise` issue. | `issues` |
| `schedulingFeasibility` | `proposal.feasibility != .infeasible`. | `feasibility` |
| `interferenceAndRecoveryCompromise` | No `.interferenceConflict`/`.recoverySpacingCompromise` issue. | `issues` |

`GoalAlignmentRating` has 5 tiers, ordered but never claiming
interval-scale precision: `.infeasible` < `.poor` < `.acceptable` <
`.good` < `.excellent`.

- **`.infeasible`** is a hard short-circuit: whenever
  `proposal.feasibility == .infeasible`, `evaluate` returns
  `GoalAlignment(rating: .infeasible, factors: [])` immediately — an
  unschedulable mix is a different *kind* of outcome than one that was
  produced but scores badly, and a per-factor breakdown would mostly be
  noise once the mix couldn't even be placed.
- Otherwise, the rating is a deterministic function of how many of the 7
  factors are satisfied: 7/7 → `.excellent`, 6/7 → `.good`, 4-5/7 →
  `.acceptable`, ≤3/7 → `.poor`. These thresholds are TRAININGOS_DESIGNED
  — a transparent, fixed rule, not a tuned or validated scoring model.

## 4. Priority model — two separate dimensions, never collapsed

A `TrainingMixComponent` already carries two independent fields, and this
pass keeps them independent rather than merging them:

- `priority: GoalPriority` — `.primary` / `.secondary` / `.supporting`.
  Which adaptation goal this component serves relative to the others.
- `flexibility: ComponentFlexibility` — `.required` / `.preferred` /
  `.optional`. Whether this component's own frequency can be reduced or
  dropped under scheduling pressure.

These answer different questions — "Strength may be `.primary` AND
`.required`; Functional Fitness may be `.secondary` AND `.preferred`;
Zone 2 may be `.supporting` AND `.optional`" — and neither can be derived
from the other. Priority comes entirely from the mix/phase configuration
a caller supplies; nothing in `ConcurrentScheduler` ever branches on
`TrainingModality` to decide priority — proven directly by
`SchedulerHardeningTests.testRunningPriorityPhaseProtectsKeyRunningWork`/
`.testMuscleGainPhaseProtectsRequiredResistanceTraining`, the same
algorithm protecting whichever component was *configured* primary,
Running in one case and Strength in the other.

## 5. Conflict resolution — the exact, fixed order

When two sessions could both use the same day, this is the order that
decides who gets it (see `CONCURRENT_SCHEDULER.md` §4 for the
implementation):

1. **Hard constraints.** A session with no hard-valid day anywhere in the
   window is never a contender — it becomes a conflict, full stop.
2. **Required-minimum urgency.** Every component's own required minimum
   (or target, when no minimum was set) is placed — across ALL
   components — before any component's sessions *beyond* its own minimum
   are even attempted. This is a genuine two-phase pass, not a per-item
   flag: `ConcurrentScheduler.buildPhases` computes it once, up front.
3. **Primary-goal protection.** Within either phase, a `.primary`-priority
   component's session is attempted before any non-primary one.
4. **Component priority ordinal** (`.primary` < `.secondary` <
   `.supporting`) — the general fallback when two contenders are both
   non-primary.
5. **Program ordering / key sessions.** A component's own sessions are
   attempted in their materialized order, except that a session flagged
   `Session.isKeySession` is promoted ahead of a standard sibling from the
   *same* component — see §6.
6. **Interference/recovery preference** — prefer a day/partner that
   doesn't trigger a soft `InterferenceAvoidanceRule`.
7. **User preferred days** — prefer a day on the component's own
   `preferredDays`.
8. **Stable deterministic tie-break** — `componentLabel` alphabetically,
   then the session's own effective sequence position. Never array
   insertion order — `SchedulerHardeningTests
   .testInsertionOrderOfEquallyPrioritizedComponentsNeverChangesTheResult`
   proves swapping two same-priority components' order in the caller's
   own input array changes nothing.

`.primaryGoalPriority` is tagged on a placement **only** when a genuine,
still-pending, different-component session could *also* have used that
exact day at that moment — never merely because the winning component
happened to be primary. `.requiredFrequencyProtected` (new this pass) is
tagged on every placement made during phase 2 above, regardless of
whether a specific conflict existed for its day — an honest, narrower
claim ("this counts toward a required minimum") than
`.primaryGoalPriority`'s ("priority genuinely decided this").

## 6. Key sessions

Some sessions within one component matter more than others — a running
week's long run or threshold session vs. an easy run. `Session.isKeySession: Bool`
(default `false`) is the minimum concept needed to express that: when a
component has more sessions than the window can fit, a key session is
preferred over a standard one from the *same* component, regardless of
its position in the component's own materialized sequence. It never
crosses component boundaries and never reorders which day a *placed*
session lands on relative to its own placed siblings — it only affects
which specific sessions get first claim when not all of a component's own
sessions can fit. No general "Running planner" was built to support
this — it's a single boolean, read only by `ConcurrentScheduler`.

## 7. Recommended vs. selected — still one type, two kinds

This pass deliberately did **not** split `TrainingMix` into two duplicate
Swift types (`RecommendedTrainingMix`/`UserSelectedTrainingMix`).
`TrainingMix.kind: TrainingMixKind` (`.recommended`/`.selected`) already
gives two fully separate, independently-persisted objects — a selected
mix scoring lower than a recommended alternative is schedulable and
untouched by evaluating or scheduling the other, proven by
`SchedulerHardeningTests.testUserSelectedHybridMixRemainsRespectedEvenIfAlignmentIsLowerThanRecommendedMix`.
Building two duplicate types would reintroduce exactly the schema
duplication `TRAINING_MIX.md` §2 already rejected for the same reason.
This is a judgment call worth the product owner's explicit sign-off,
flagged rather than silently decided (CLAUDE.md rule 10's spirit,
applied to an architecture choice rather than a training rule) — the
behavioral requirement ("never silently overwritten, never mutated into
the other, always independently schedulable") is met either way.

## 8. Planner-facing API

`SchedulingPipeline.propose(mix:inputs:constraints:) -> (proposal:
alignment:)` is the entire contract a future Long-Term Planner needs:

```
TrainingPhaseGoal
  + RecommendedTrainingMix OR UserSelectedTrainingMix   (TrainingMix.kind)
  + Availability                                        (UserAvailability)
  + Program-generated Sessions                          (ScheduledProgramInput)
  -> ConcurrentScheduler.schedule(_:constraints:)
  -> ScheduleProposal
  -> GoalAlignmentEvaluator.evaluate(mix:proposal:)
  -> GoalAlignment
  -> user approval (AcceptScheduleProposalUseCase — a separate, explicit step)
```

A planner calls `propose` once per candidate mix it wants to compare and
reads only `proposal`/`alignment` — it never needs to know how
`ConcurrentScheduler` resolves a conflict internally, and it never
inspects `warnings`. `ScheduleProposal.alternatives: [ScheduleProposal]`
is reserved (always empty in this pass) for whatever comparison
structure the planner eventually needs — declared now so the shape
doesn't change again when that work starts.

## 9. What this pass does not claim

- No Long-Term Planner — `SchedulingPipeline` is the contract it will
  use, not the planner itself.
- `interferenceAndRecoveryCompromise` treats interference and
  recovery-spacing compromises as one combined factor, matching the
  hardening kickoff's own wording ("interference/recovery compromises") —
  it does not distinguish which of the two occurred within the factor
  itself (the underlying `issues` array still does, via `code`).
- The 7-factor → 4-tier rating thresholds (7/7, 6/7, 4-5/7, ≤3/7) are a
  fixed, transparent product policy, not a validated or tuned scoring
  model — deliberately simple rather than an attempt at more precision
  than 7 booleans can honestly support.
