# Concurrent Scheduler

Stage 4F's placement engine — it decides *where* on the calendar an
already-produced Session lands. It never decides *what* that Session is.
**Stage 4G** hardened its conflict-resolution and explanation semantics
(see §4/§6/§10 and `GOAL_ALIGNMENT.md`) without changing this scope.

## 1. Scope — what this system does and does not do

`ConcurrentScheduler` receives Sessions that some `ProgrammingSystem`'s
materializer already fully produced (`StrengthMaterializer`,
`SteadyStateMaterializer`, `IntervalMaterializer`,
`FunctionalFitnessMaterializer` — every one of them already places its
own Sessions on naive, sequential dates and says so in its own doc
comment: "real preferred-day/availability placement is
ConcurrentScheduler's job"). This stage is that job, and only that job:

- Calendar placement, ordering across systems, same-day pairing,
  recovery spacing, conflict resolution.
- **Never**: generating training methodology, prescribing intensity,
  picking exercises, or rewriting a `SetPrescription`/`SteadyStatePrescription`/
  `IntervalPrescription`/`FunctionalFitnessPrescription` of any kind.

This is also the exact content of the second required CLAUDE.md addition
this stage makes: *"ConcurrentScheduler schedules training; it does not
create or progress training methodology."* Concretely, that boundary
means `AcceptScheduleProposalUseCase` (§8) only ever touches `Session.day`,
`.sortIndex`, `.scheduledTime`, `.schedulerVersion` — never a block, a
prescription, or a result.

## 2. Inputs

- **`ScheduledProgramInput`** — one `TrainingMixComponent` plus its own
  already-materialized `[Session]`, in their existing execution order.
- **`SchedulingConstraints`** — `UserAvailability` (never just "sessions
  per week": training days/week, available/unavailable weekdays, minutes
  per day, longer-day flags, double-session permission, a hard
  `maxSessionsPerDay` ceiling), a `SchedulingWindow` (tactical — a rolling
  week/short horizon, `startDate` always supplied explicitly by the
  caller, never read from the system clock), and `[InterferenceAvoidanceRule]`
  (§5).

`ConcurrentScheduler.schedule(_:constraints:) -> ScheduleProposal` is the
entire public surface — a pure function, no `ModelContext` needed to run
it.

## 3. Hard vs. soft constraints

**Hard** (a candidate day is simply not valid, full stop):

- The weekday is unavailable (`UserAvailability.isUsable`).
- Placing here would exceed `maxSessionsPerDay`.
- Placing here would double up two sessions from the *same* component
  (never sensible — pairing is for two different components' work,
  never a component repeating itself same-day).
- Doubling here is disallowed because either the component's own
  `allowsDoubleSessionPairing` or `UserAvailability.allowsDoubleSessions`
  says no.
- `TrainingMixComponent.requiredSpacingDays`, when set, is violated
  against that component's own previously-placed session.
- `UserAvailability.minutesAvailablePerDay`, when set for that weekday,
  is below the session's estimated duration (§7's `minMinutesNeeded` —
  a TRAININGOS_DESIGNED conservative floor per `DurationDomain` category,
  never an exact-minute claim). A weekday absent from that dictionary has
  no ceiling and always passes this check.

**Soft** (avoided when possible; placed anyway with `.softConstraintViolated`
and a warning when every hard-valid candidate would violate it):

- An `InterferenceAvoidanceRule` triggers against an already-placed
  neighbor (same day or the immediately adjacent day).
- None of a component's `preferredDays` is reachable at all within the
  hard-valid candidate set.

## 4. The placement algorithm — conflict resolution, not first-claim

**Stage 4G rewrite.** Stage 4F's original algorithm sorted every session
once by `GoalPriority` tier alone and processed them in one single pass —
which meant a primary component's placements were tagged
`.primaryGoalPriority` even when no other component was actually
competing for that day. This section describes the replacement: a
genuine two-phase, contention-aware algorithm. The full, numbered
conflict-resolution order (the answer to "when two sessions could both
use the same day, who wins") is documented once, canonically, in
`GOAL_ALIGNMENT.md` §5 — this section describes how `ConcurrentScheduler`
actually implements that order.

1. **Flatten and snapshot.** Every `ScheduledProgramInput` becomes
   `[SchedulableSession]` (one entry per Session, annotated with its
   component's priority, flexibility, double-pairing permission,
   preferred days, required spacing, `isKeySession`, and its own composed
   `TrainingStressProfile` — see §7). Nothing is re-read from
   `TrainingMixComponent`/`Session` after this point.
2. **Split into two phases per component** (`buildPhases`): each
   component's own sessions, importance-ordered (`isKeySession` promoted
   first, then materialized sequence — see §14), are split into "counts
   toward `frequency.minimum ?? frequency.target`" (phase 1) and "beyond
   it" (phase 2). A component with no explicit `minimum` puts its entire
   `target` into phase 1 — the common case, and the reason most existing
   fixtures see no phase-2 sessions at all.
3. **Sort each phase into one deterministic global order**
   (`processingOrder`): primary-goal protection first (`.primary`-priority
   sessions before any other), then component-priority ordinal, then
   `componentLabel` alphabetically, then the session's own effective
   position — never array/insertion order. Phase 1 is processed to
   completion before phase 2 begins.
4. **For each session in that order:** collect every day in the window
   that passes all hard constraints (§3). None -> the session becomes
   part of a `SchedulingConflict` *and* a hard `ScheduleIssue` (§6),
   classified by whichever hard rule excluded the most candidate days —
   never silently dropped.
5. **Score every hard-valid candidate day** with the same fixed,
   lexicographic tuple as Stage 4F (unchanged): not-a-double, no
   interference trigger, lands on a preferred day, lightest available
   double-session partner, earliest day offset as the final tie-break.
6. **Before committing, check for genuine contention:** only when the
   session belongs to a `.primary`-priority component, scan the *rest* of
   this phase's remaining queue for any different-component session that
   could *also* have used the winning day right now (same hard-constraint
   check, current pre-commit occupancy). Only then is `.primaryGoalPriority`
   tagged — never merely because this component was processed first.
7. Place on the winning day, tag every applicable reason code (§6, plus
   any soft `ScheduleIssue`s this placement required), record the day as
   occupied, and continue.

Nothing here special-cases a modality. The same steps place a Strength
session, a Functional Fitness session, or a Running session identically
— proven directly by the required Case B test (3 Strength + 2 Functional
Fitness + 1 Running, one `schedule()` call) and, for priority
specifically, by `SchedulerHardeningTests
.testRunningPriorityPhaseProtectsKeyRunningWork`/
`.testMuscleGainPhaseProtectsRequiredResistanceTraining` — the same
algorithm protects whichever component the caller configured as primary,
proving priority comes from configuration, never from a hardcoded
modality check.

## 5. Interference avoidance — conservative, categorical, never a physiology claim

`InterferenceAvoidanceRule { dimension: StressDimension, threshold: LoadLevel }`
triggers when **both** the candidate session and a same-day/adjacent-day
neighbor reach at least `threshold` on `dimension` — purely in terms of
the existing categorical `TrainingStressProfile` vocabulary (`lowerBodyLoad`,
`impactLoading`, etc.), never a numeric hour count and never a claim like
"cardio kills gains." `InterferenceAvoidanceRule.conservativeDefault` (two
rules: `lowerBodyLoad >= .high`, `impactLoading >= .high`) is
**TRAININGOS_DESIGNED** product policy, explicitly not a citation — see
`PROGRAMMING_SOURCES.md`'s Stage 4F note for exactly which prior research
this policy is *motivated by* (the concurrent-training interference
literature's own conclusion that no single universal rule holds) without
claiming that research specifies these two dimensions or this threshold.
Callers may pass their own rule set; an empty list disables interference
avoidance entirely.

## 6. Reason codes

Every non-trivial placement carries one or more of these codes — additive
and never renamed once a `ScheduleProposal` referencing one has shipped.
The original 10 are the kickoff's own authoritative list; `.requiredFrequencyProtected`
is Stage 4G's one addition:

| Code | Meaning |
|---|---|
| `primaryGoalPriority` | This placement won a **genuine** same-day contention against a lower-priority, different component's session — see §4 step 6. Never tagged merely because a primary component was processed first. |
| `requiredFrequencyProtected` | **Stage 4G addition.** This session counts toward its component's required minimum (or target, when no minimum was set) — true for every phase-1 placement (§4 step 2), regardless of whether a specific conflict existed for its exact day. A narrower, always-honest claim than `primaryGoalPriority`'s. |
| `recoverySpacing` | Placement honored `requiredSpacingDays` against this component's own prior session. |
| `interferenceAvoided` | A non-adjacent/non-triggering day was chosen over an available interference-triggering alternative. |
| `lowIntensityPairing` | A double-session was paired with the lightest available partner day. |
| `doubleSessionSelected` | Two sessions were deliberately placed on the same day. |
| `preferredDayUsed` | Landed on one of the component's `preferredDays`. |
| `availabilityConstraint` | The user's own availability shaped this window's placements (at least one day in the window was excluded). |
| `softConstraintViolated` | A soft constraint (interference or "no reachable preferred day") had to give way — always paired with a matching `ScheduleIssue` (§6a), never left silent. |
| `programOrderPreserved` | This component's own sessions landed in their existing effective claim order (materialized order, with `isKeySession` promoted first — see §14) — always true, on every placement. |
| `userSelectedMix` | This session belongs to the phase's `.selected` mix, not a `.recommended` one. |

### 6a. `ScheduleIssue` — the structured signal `GoalAlignmentEvaluator` reads

`SchedulingReasonCode` above explains a placement that *happened*.
`ScheduleIssue` (new in Stage 4G) is the separate, structured vocabulary
for compromises and failures — 11 `ScheduleIssueCode` cases, each with a
`severity` (`.hard`/`.soft`), a `componentLabel`, an optional affected
`session`, and a `reason` that is **pure display copy**, generated from
the structured fields and safe to reword freely. `ScheduleProposal.warnings`
is a *computed* property (`issues.map(\.reason)`) — there is no
independent "warnings" state to drift out of sync with `issues`, and no
business logic (including `GoalAlignmentEvaluator`) may read it. See
`GOAL_ALIGNMENT.md` §2 for the full code table.

## 7. `TrainingStressProfile` composition — `SessionStressComposer`

A multi-block Session's own stress profile is the deterministic,
categorical **worst case** across its blocks' own `TrainingStressProfile`s
— per `LoadLevel` dimension, the highest ordinal present; for
`durationClassification`, the longest domain present. Never an average,
never a fabricated composite number. `nil` when none of a Session's
blocks carry a profile at all (composing nothing produces nothing, not a
fabricated all-`.none` profile).

## 8. `ScheduleProposal` and acceptance

`schedule()` never mutates anything — it returns a `ScheduleProposal`
(`placements`, `conflicts`, `feasibility`, `issues`, `schedulerVersion`,
plus a reserved, always-empty `alternatives: [ScheduleProposal]` for a
future planner — see `GOAL_ALIGNMENT.md` §8), a plain, non-persisted
value type. `warnings` is computed from `issues`, not a separate field —
see §6a. This is the Engine-recommendation -> Explanation -> User-approval
pattern this project already uses elsewhere: only `AcceptScheduleProposalUseCase.accept(_:ownerUserID:context:)`
turns an approved proposal into real state, and only by re-parenting
Sessions that already exist (removing from whatever naive `Day` the
materializer assigned, finding-or-creating the target `Day`, and stamping
`sortIndex`/`scheduledTime`/`schedulerVersion`). It throws rather than
accept an `.infeasible` proposal — an unresolved conflict must be dealt
with (or the mix explicitly reduced) before anything is committed.

`Session.schedulerVersion: Int?` mirrors `ProgramDefinition.generatorVersion`'s
own precedent: an already-accepted placement's meaning must never
silently change if the scheduler's algorithm changes later. Bump
`ConcurrentScheduler.currentVersion` only when placement logic changes in
a way that could alter results for identical inputs — never for a pure
refactor.

## 9. Impossible-mix handling

An unplaceable session is never silently dropped. It becomes part of a
`SchedulingConflict` naming exactly which sessions couldn't fit, why, and
which of four concrete `ConflictResolutionOption`s would actually help:
allow double sessions, add an available day, reduce frequency (only ever
offered when `flexibility != .required`), or shorten/move a flexible
session (same restriction). None of these is ever auto-applied — they are
proposals; only a separate, explicit user action changes the user's
requested mix or availability. `ScheduleFeasibility` has three states:
`.feasible`, `.feasibleWithSoftViolations` (everything placed, at least
one soft constraint gave way), and `.infeasible` (at least one session
has no valid day at all).

## 10. `GoalAlignmentEvaluator`

Scores a `(TrainingMix, ScheduleProposal)` pair as a `GoalAlignmentRating`
(`.infeasible`/`.poor`/`.acceptable`/`.good`/`.excellent`) plus 7 fully
transparent `GoalAlignmentFactor`s — never a fabricated numeric
percentage, and, since Stage 4G, computed entirely from `issues`/
`placements` typed data, never from `warnings` display text. The full
factor table, rating thresholds, and the reasoning behind the `.infeasible`
short-circuit live in `GOAL_ALIGNMENT.md` §3 — this section only points
there so the two documents don't drift.

## 11. Determinism

`schedule()` never reads the system clock (the caller supplies
`SchedulingWindow.startDate` explicitly) and never uses randomness.
Every tie-break in §4's scoring tuple is total — the final field (day
offset) always resolves any remaining tie — so identical `(inputs,
constraints)` always produce byte-identical `ScheduleProposal` placement
sequences. `ConcurrentSchedulerTests.testIdenticallyShapedInputsAlwaysProduceTheSameSchedule`
proves this directly.

## 12. Adherence-aware scheduling — how this stage actually delivers it

This stage's kickoff named three pillars: `ConcurrentScheduler`, Training
Mix, and adherence-aware scheduling. The third is not a separate
mechanism bolted onto the first two — it *is* the first two, applied
correctly:

- A user's `.selected` `TrainingMix` always wins over the `.recommended`
  one (`userSelectedMix`, §6) — the plan actually gets scheduled, not the
  theoretically-optimal one.
- Every preference that affects whether a user will actually follow a
  plan (preferred days, double-session tolerance, flexibility) is a
  first-class scheduling **constraint**, not a hidden weight — see §3/§4.
- `PreferenceStrength` (`TRAINING_MIX.md` §7) is deliberately *not* an
  active scheduling input in this pass — using it to algorithmically
  infer how hard to try would be exactly the "predict motivation" trap
  the kickoff explicitly ruled out.
- `AdherenceMode` (`ProgramInstance.adherenceModeOverride` — strict vs.
  adaptive) is **not read by `ConcurrentScheduler` at all**, and that is
  deliberate, not a gap: `AdherenceMode` governs progression-continuation
  behavior, a different engine's concern entirely; `ConcurrentScheduler`
  never rewrites a prescription regardless of a program's adherence mode,
  by construction (§1) — so there is nothing for it to respect or violate
  here. Coupling the two would blur exactly the boundary the second
  required CLAUDE.md addition exists to keep intact.

## 14. Key sessions

`Session.isKeySession: Bool` (default `false`, Stage 4G addition) marks a
session as more important than a standard sibling from the *same*
`TrainingMixComponent` — a running week's long run or threshold session
vs. an easy run. `buildPhases` (§4 step 2) promotes key sessions ahead of
standard ones when deciding both which sessions count toward a
component's required minimum and which get first claim on scarce days;
it never crosses component boundaries and never reorders which day a
*placed* session lands on relative to its own placed siblings. See
`GOAL_ALIGNMENT.md` §6 for the full reasoning and
`SchedulerHardeningTests.testRunningPriorityPhaseProtectsKeyRunningWork`
for the proof that a key session survives being dropped in favor of a
sequence-earlier standard one.

## 15. Planner-facing API

`SchedulingPipeline.propose(mix:inputs:constraints:) -> (proposal:
alignment:)` bundles `schedule()` and `GoalAlignmentEvaluator.evaluate`
into the single entry point a future Long-Term Planner calls once per
candidate mix — see `GOAL_ALIGNMENT.md` §8 for the full pipeline
contract.

## 16. What this system does not claim

- No Long-Term Planner. This stage never generates a `.recommended`
  `TrainingMix` — see `TRAINING_MIX.md` §10. `SchedulingPipeline` (§15)
  is the contract that planner will use, not the planner itself.
- No full-year scheduling. The window is tactical (a rolling week/short
  horizon) by design, never the whole `TrainingPlan`.
- No numeric interference thresholds beyond the two-dimension
  conservative default (§5), and no claim that literature specifies
  exactly these dimensions or this threshold.
- No workout-execution UI. `ScheduleProposal`/`ConflictResolutionOption`
  are data a future UI would render; none of that UI exists yet.
- `TrainingMix` remains one type with a `kind` flag, not two duplicate
  `RecommendedTrainingMix`/`UserSelectedTrainingMix` types — see
  `GOAL_ALIGNMENT.md` §7 for why this satisfies the "two separate
  concepts" requirement without duplicating `TrainingMixComponent`'s
  schema twice.
