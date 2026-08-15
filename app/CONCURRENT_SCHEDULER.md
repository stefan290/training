# Concurrent Scheduler

Stage 4F's placement engine — it decides *where* on the calendar an
already-produced Session lands. It never decides *what* that Session is.

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

**Soft** (avoided when possible; placed anyway with `.softConstraintViolated`
and a warning when every hard-valid candidate would violate it):

- An `InterferenceAvoidanceRule` triggers against an already-placed
  neighbor (same day or the immediately adjacent day).
- None of a component's `preferredDays` is reachable at all within the
  hard-valid candidate set.

## 4. The placement algorithm

Deterministic and greedy, session-by-session:

1. Flatten every `ScheduledProgramInput` into `[SchedulableSession]` (one
   entry per Session, annotated with its component's priority,
   flexibility, double-pairing permission, preferred days, required
   spacing, and its own composed `TrainingStressProfile` — see §7).
2. Sort by `GoalPriority` (`.primary` before `.secondary` before
   `.supporting`). The sort is stable, so within a tier the caller's own
   input order is preserved — the one remaining degree of freedom
   belongs to the caller, not the algorithm.
3. For each session in that order, collect every day in the window that
   passes all hard constraints (§3). None -> the session becomes part of
   a `SchedulingConflict` (§6), never silently dropped.
4. Score every hard-valid candidate day with a fixed, lexicographic
   tuple (lower wins on every field, in this order):
   1. Not a double-session (prefer a free day).
   2. No soft interference-rule trigger.
   3. Lands on one of the component's `preferredDays`.
   4. Among double-session candidates, the lightest existing partner
      (lowest worst-case `TrainingStressProfile` ordinal on that day) —
      this is what produces `.lowIntensityPairing`.
   5. Earliest day offset — the final, always-decisive tie-break, so two
      identical `(inputs, constraints)` calls never diverge.
5. Place on the winning day, tag reason codes (§6), record the day as
   occupied, and continue.

Nothing here special-cases a modality. The same five steps place a
Strength session, a Functional Fitness session, or a Running session
identically — proven directly by the required Case B test (3 Strength +
2 Functional Fitness + 1 Running, one `schedule()` call, no branch
anywhere keyed on `TrainingModality`).

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

Every non-trivial placement carries one or more of these ten codes — the
kickoff's own authoritative list, additive and never renamed once a
`ScheduleProposal` referencing one has shipped:

| Code | Meaning |
|---|---|
| `primaryGoalPriority` | This placement belongs to the mix's `.primary` component — processed (and given first claim on days) before any other tier. |
| `recoverySpacing` | Placement honored `requiredSpacingDays` against this component's own prior session. |
| `interferenceAvoided` | A non-adjacent/non-triggering day was chosen over an available interference-triggering alternative. |
| `lowIntensityPairing` | A double-session was paired with the lightest available partner day. |
| `doubleSessionSelected` | Two sessions were deliberately placed on the same day. |
| `preferredDayUsed` | Landed on one of the component's `preferredDays`. |
| `availabilityConstraint` | The user's own availability shaped this window's placements (at least one day in the window was excluded). |
| `softConstraintViolated` | A soft constraint (interference or "no reachable preferred day") had to give way — always paired with a warning. |
| `programOrderPreserved` | This component's own sessions landed in their existing materialized order — always true, on every placement. |
| `userSelectedMix` | This session belongs to the phase's `.selected` mix, not a `.recommended` one. |

**Documented simplification:** `.primaryGoalPriority` marks first-claim
status (the primary component is processed, and picks its days, before
anyone else), not a proof that an actual conflict was resolved in its
favor — determining the latter would require simulating the schedule
without priority and diffing outcomes, which this pass does not do.

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
(`placements`, `conflicts`, `feasibility`, `warnings`, `schedulerVersion`),
a plain, non-persisted value type. This is the Engine-recommendation ->
Explanation -> User-approval pattern this project already uses
elsewhere: only `AcceptScheduleProposalUseCase.accept(_:ownerUserID:context:)`
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
(`.poor`/`.acceptable`/`.good`/`.excellent`) plus a fully transparent list
of `GoalAlignmentFactor`s (primary-stimulus coverage, minimum-frequency
satisfaction, supporting-goal coverage, scheduling feasibility,
interference cost, user-preference satisfaction) — each a plain boolean
plus a note, never a fabricated numeric percentage.

**Documented simplification:** the `interferenceCost` and
`userPreferenceSatisfaction` factors are currently detected by matching
`ScheduleProposal.warnings`' own generated text, rather than from a
dedicated structured signal — this correctly distinguishes "was any soft
constraint of this kind violated" but does not yet distinguish severity
or count. A future pass could add a structured per-placement violation
reason instead of text-matching, but the qualitative-only output is
already accurate at the granularity this stage promises.

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

## 13. What this system does not claim

- No Long-Term Planner. This stage never generates a `.recommended`
  `TrainingMix` — see `TRAINING_MIX.md` §10.
- No full-year scheduling. The window is tactical (a rolling week/short
  horizon) by design, never the whole `TrainingPlan`.
- No numeric interference thresholds beyond the two-dimension
  conservative default (§5), and no claim that literature specifies
  exactly these dimensions or this threshold.
- No workout-execution UI. `ScheduleProposal`/`ConflictResolutionOption`
  are data a future UI would render; none of that UI exists yet.
