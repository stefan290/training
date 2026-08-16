# Stage 6A Decision Memo

Every place this pass's design documents (`WORKOUT_EXECUTION.md` and its
6 companions — `SESSION_STATE_MACHINE.md`, `TIMER_ARCHITECTURE.md`,
`STRENGTH_EXECUTION_FLOW.md`, `ENDURANCE_EXECUTION_FLOW.md`,
`FUNCTIONAL_FITNESS_EXECUTION_FLOW.md`, `WORKOUT_COMPLETION_PIPELINE.md`)
made a judgment call, found a real gap, or deferred a question — and how
each was resolved.

**Status: all 7 MUST RESOLVE items are RESOLVED** — decided by the
product owner, applied to every affected document. **Zero MUST RESOLVE
items remain before Stage 6B implementation.** What's left (§4) is
non-blocking build-time verification, not a gate.

## 1. The seven resolved decisions

### 1a. Partial-session semantics — RESOLVED

**Decision:** a Session may end `PARTIALLY COMPLETED`. Completed work is
never discarded because the whole Session wasn't finished.

**Final model:**
- `Session.completionContext: SessionCompletionContext?` (`.full`/`.partial`)
  — unchanged from the original proposal.
- `WorkoutBlock.completionContext: BlockCompletionContext?` (`.full`/`.partial`)
  — **new**: added specifically because "which blocks were completed /
  partially completed / not started" needs to be answerable per block,
  not only per session. `BlockStatus` itself still gains no new case
  (`.pending`/`.active`/`.completed`/`.skipped` unchanged) —
  `completionContext` only exists once a block reaches `.completed`.
- **Stopped-halfway actions reduced to two, not three:** `Resume later`
  (no state change) and `Finish as Partial` (terminal — every remaining
  `.pending`/`.active` block becomes `.skipped`, the Session becomes
  `.completed` with `completionContext = .partial`). The previous
  proposal's separate "Abandon" action is **removed as a direct,
  user-facing action** — `.abandoned` remains in `SessionStatus` only as
  a passive fallback for a Session nobody ever explicitly closed out
  (discovered later, e.g. by a future "you left this unfinished 3 days
  ago" prompt — out of scope this stage), never a button the user taps
  mid-session.
- **Progression consumption:** execution never decides progress/hold/
  repeat itself — it only records the structured facts
  (`completionContext`, actual result rows) and hands them to whichever
  `ProgrammingSystem`'s engine already consumes them. Verified per
  system (§2 of `WORKOUT_COMPLETION_PIPELINE.md`, restated in
  `ENDURANCE_EXECUTION_FLOW.md`):
  - **Strength** — `DoubleProgressionEngine` already defaults to `HOLD`
    the moment `targets.count != latestResults.count` — a partial
    strength block already gets exactly the conservative, non-invented
    outcome the decision calls for, with zero new engine code.
  - **Interval** — `IntervalProgressionEngine.evaluateSessionOutcome(completedCount:totalCount:worstRpe:)`
    is already a graduated, deterministic partial-completion-aware
    system: a completion fraction maps to `.progress`/`.hold`/
    `.repeatSession`/`.reduceIntensity`/`.reduceIntervalCount`, and
    `totalCount == 0` (nothing attempted) already yields
    `.calibrationRequired`. Execution's only job is to report
    `completedCount`/`totalCount`/`worstRpe` accurately from what
    actually happened.
  - **Steady state** — `SteadyStateProgressionEngine`'s resolve
    functions do not consume actual results at all; next week's
    duration/distance/intensity is already a pure function of
    configured rules + week index. A partial steady-state session
    therefore has no special "insufficient data" branch to add — there
    is nothing for partial-ness to feed into under this engine's
    existing, unchanged contract.
  - **Functional Fitness** — `FunctionalFitnessDecisionEngine` reasons
    over *exposure history* (`FunctionalFitnessExposureHistoryBuilder`,
    already filtered to `Session.status == .completed`), not a
    completion fraction. A partial FF result still represents a real
    stimulus exposure and correctly continues to count — no change
    needed.

  **No new `ProgressionInput`/engine parameter is introduced anywhere.**
  Every system's existing "insufficient information" branch already
  satisfies "default to a conservative outcome rather than pretending
  the Session was fully completed" — this decision is implemented
  entirely by *execution reporting actual results honestly*, never by
  execution computing a progression outcome itself.

**Files updated:** `SESSION_STATE_MACHINE.md` §2-4, `WORKOUT_COMPLETION_PIPELINE.md`
§1/§5, `ENDURANCE_EXECUTION_FLOW.md` §2/§4, `WORKOUT_EXECUTION.md` §4.

### 1b. First-entry PR presentation — RESOLVED

**Decision:** the first valid result establishes the baseline but is
never presented as "you beat a PR." Data model is unchanged.

**Final model:** `ScoringEngine`/`PersonalRecord`/`isPersonalRecord` are
untouched — a first-ever entry still creates a real `PersonalRecord`
row, exactly as today. The recording use cases (and
`CompleteSessionUseCase`'s `CompletionSummary`) additionally surface
whether `existingBest == nil` at the moment of recording, so the
completion screen can render:
- **First-ever valid result** → neutral copy ("First recorded result" /
  "Baseline established").
- **Later result that beats a compatible prior best** → "New PR."

"Compatible" means the same `ResultContext`/rep-band comparison
`ScoringEngine.bestRecord` already enforces (§1f) — this decision adds
no new compatibility rule of its own.

**Files updated:** `FUNCTIONAL_FITNESS_EXECUTION_FLOW.md` §8,
`STRENGTH_EXECUTION_FLOW.md` §2, `WORKOUT_COMPLETION_PIPELINE.md` §4.

### 1c. Timer catch-up on relaunch — RESOLVED (confirmed as designed)

**Decision:** no catch-up playback, ever. Timer truth is derived from
persisted wall-clock timestamps and explicit state transitions, never
in-memory ticks.

**Final behavior, by scenario:**
- **Background:** the timer keeps running per elapsed wall-clock time
  unless explicitly paused (`pausedAt` set) — no special handling
  needed, this is the default behavior of `elapsedSeconds`/
  `remainingSeconds` (`TIMER_ARCHITECTURE.md` §2).
- **Force-close / relaunch:** recovered directly from `TimerState`
  (`startedAt`/`pausedAt`/`accumulatedPauseSeconds`/`currentUnitIndex`)
  against `Date()` at the moment the view reappears.
- **Device restart:** identical, provided the persisted store survived
  the restart (ordinary SwiftData persistence guarantee, nothing
  timer-specific).
- **Expired while closed:**
  - *Rest timer* — renders as completed/expired immediately, no replay.
  - *AMRAP* — if the cap already passed, the round-tap target is
    disabled and the flow moves directly to the post-cap "extra reps"
    completion step (§1 of `FUNCTIONAL_FITNESS_EXECUTION_FLOW.md`) —
    the screen **requires** the user to complete the result rather than
    silently sitting at its last-rendered state.
  - *EMOM/interval* — the current minute/interval index is recomputed
    from elapsed time against the prescribed per-unit duration
    (deterministic: `elapsed ÷ unitDuration`, floored), landing directly
    on the correct current unit — never replaying the minutes/intervals
    in between.
- **No missed haptic/sound cues are replayed** — cues are best-effort
  presentation derived from `TimerState`, never a source of truth
  (`TIMER_ARCHITECTURE.md` §6, unchanged).

**Files updated:** `TIMER_ARCHITECTURE.md` §4/§7,
`FUNCTIONAL_FITNESS_EXECUTION_FLOW.md` §1/§2.

### 1d. Save-boundary convention — RESOLVED (revises the original Stage 6A proposal)

**Decision:** incremental durability. A single final `save()` at Session
completion is **not** the only persistence boundary — completed work
must survive a crash at any point.

**Final model — who saves, and when:**

| Action | Use case | Saves? |
|---|---|---|
| Log a set | `LogSetUseCase` (wraps `RecordSetResultUseCase`) | Yes — immediately after |
| Log an endurance/interval result | `LogEnduranceResultUseCase` (wraps `RecordSteadyStateResultUseCase`/`RecordIntervalResultUseCase`) | Yes — immediately after |
| Apply a substitution/scaling choice | `ApplySubstitutionUseCase` | Yes — immediately after |
| A block changes status (pending→active→completed/skipped) | `CompleteBlockUseCase` (or the block-start equivalent) | Yes — immediately after |
| Session status changes (start/pause-timer/resume/completion) | `ChangeSessionStatusUseCase` / `CompleteSessionUseCase` | Yes — immediately after |
| Every UI tick / in-progress stepper edit before confirming | *(nothing)* | No — never persisted until confirmed |

The lower-level, already-existing recording use cases
(`RecordSetResultUseCase`, `RecordFunctionalFitnessResultUseCase`, and
the new `RecordSteadyStateResultUseCase`/`RecordIntervalResultUseCase`)
**remain pure mutation, no `save()`** — unchanged, since they're reused
outside live execution too (seed data, tests). The **new, execution-
specific orchestrating use cases** named above are what actually own
`save()`, each covering exactly one meaningful user action. Views never
call `save()` (or any use case directly bypassing a ViewModel action) —
unchanged from the original design.

`CompleteSessionUseCase`'s own final save covers only what's left at
that point: `Session.status`/`completionContext`/`completedAt` and any
still-`.pending` blocks flipping to `.skipped`. It is the **final
consistency/commit point**, not the first durability point — every
result row logged earlier in the session is already durable by the time
Finish is tapped.

**Files updated:** `WORKOUT_COMPLETION_PIPELINE.md` §1 (rewritten),
`WORKOUT_EXECUTION.md` §5, `STRENGTH_EXECUTION_FLOW.md` §3,
`ENDURANCE_EXECUTION_FLOW.md` §1/§3, `ARCHITECTURE.md`, `CLAUDE.md`
(new locked invariant).

### 1e. Within-session autoregulation — RESOLVED (confirmed as designed)

**Decision:** no new within-session load-adjustment logic in Stage 6B.
Progression happens between Sessions, using the existing engines,
exactly as already documented.

**Final model:**
- The suggested load/`Recommendation` shown before an exercise starts is
  unchanged and still comes from the existing engine, computed once.
- Every set's stepper values are **user-editable** — the user may
  manually type/adjust a different load or rep count for any set,
  including sets later in the same exercise. This is **ordinary
  execution input**, not a new autoregulation rule: it is recorded as
  `SetResult` (actual), never conflated with `SetPrescription` (target)
  or `Recommendation` (engine output) — the three stay strictly
  separate, exactly as CLAUDE.md rule 3 already requires.
  `SESSION_STATE_MACHINE.md`/`STRENGTH_EXECUTION_FLOW.md` are explicit
  that this manual edit is user-initiated, never system-suggested
  mid-session.
- The app never automatically tells the user to add/remove weight after
  set 1 unless an existing `ProgrammingSystem` rule already defines that
  behavior (none currently does, per the engine audit in
  `STRENGTH_EXECUTION_FLOW.md` §6) — Stage 6B does not add one.

**Files updated:** `STRENGTH_EXECUTION_FLOW.md` §3/§6.

### 1f. Benchmark Rx/Scaled comparison — RESOLVED (confirmed, architecture unchanged)

**Decision:** preserve the existing compatibility rules exactly.

**Confirmed, unchanged:** `ScoringEngine.bestRecord`'s `context` filter
already guarantees Rx and Scaled never compete for the same
`PersonalRecord`, for every modality. `BenchmarkDefinition` remains the
canonical benchmark identity; Rx/Scaled context is never inferred from
the score value alone, always from the explicit `resultContext` the
recording call supplies. `FunctionalFitnessPerformedMovement` already
retains per-movement scaling detail (`performedExercise`/`performedReps`/
`performedLoadKilograms`/etc.), which is enough structured context to
support a *finer*-grained "were these two Scaled attempts actually
comparable" judgment later, without any schema change now — Stage 6B
does not build that finer comparison, it only confirms the data needed
for it already exists. No architecture is reopened.

**Files updated:** `FUNCTIONAL_FITNESS_EXECUTION_FLOW.md` §7 (confirmed,
no material change beyond noting this decision).

### 1g. Missed-session scope boundary — RESOLVED (confirmed, one distinction sharpened)

**Decision:** Workout Execution records **what happened**; the
Scheduling Pipeline / Long-Term Planner decide **what happens next**.
Execution never implements a second reflow engine.

**Final model:**
```
Execution → records missed/partial/skipped state
         → SchedulingPipeline/LongTermPlanner reads that state
         → generates a reflow proposal
         → user approves/rejects (existing approval-sheet pattern)
```
**The one sharpened distinction:** `SessionStatus` already has two
separate cases for exactly the two situations that must never be
merged — no new case is needed:
- **`.skipped`** — the user explicitly tapped "Can't train today"
  *before* starting. An intentional, structured fact.
- **`.missed`** — a `.scheduled` Session's date passed with no action at
  all. Never written by a background process; only written when the
  user next opens the app and interacts with the missed-session prompt
  (§7 of `SESSION_STATE_MACHINE.md`, unchanged).

Stage 6B must never auto-write `.missed` onto every past-due Session
indiscriminately, and must never write `.skipped` for a session the user
simply never got to — these two cases stay driven by two different,
explicit triggers.

**Files updated:** `SESSION_STATE_MACHINE.md` §4/§7 (sharpened wording,
no structural change).

## 2. Final Stage 6B schema changes (confirmed, complete list)

1. `Session.completionContext: SessionCompletionContext?` (`.full`/`.partial`).
2. `WorkoutBlock.completionContext: BlockCompletionContext?` (`.full`/`.partial`).
3. `WorkoutBlock.timerState: TimerState?` (`Codable` struct — `startedAt`/
   `pausedAt`/`accumulatedPauseSeconds`/`targetDurationSeconds`/
   `currentUnitIndex`).
4. New use cases (mutation only, no `save()`): `RecordSteadyStateResultUseCase`,
   `RecordIntervalResultUseCase`.
5. New orchestrating use cases (own `save()`, one per meaningful action):
   `LogSetUseCase`, `LogEnduranceResultUseCase`, `ApplySubstitutionUseCase`,
   `CompleteBlockUseCase`, `ChangeSessionStatusUseCase`,
   `CompleteSessionUseCase`, plus the not-yet-detailed
   `ProposeMissedSessionReflowUseCase`/`AcceptMissedSessionReflowUseCase`
   pair (§1g — state-writing only, no reflow logic of their own).
6. Recording use cases' return values widen to also report whether
   `existingBest == nil` (first-entry flag) — a function-signature
   change, not a persisted schema change.
7. **No new `SessionStatus` cases.** **No new `BlockStatus` cases.** **No
   new `WorkoutBlockType` cases.** **No change to `ScoringEngine`/
   `ResultContext`/`BenchmarkDefinition`.**

## 3. Safe to implement (unchanged from before, still no further sign-off needed)

- `Session`/`WorkoutBlock` reuse exactly as documented — zero new
  `WorkoutBlockType`/`BlockStatus` cases (`SESSION_STATE_MACHINE.md` §1/§5).
- `TimerState` as a `Codable` struct on `WorkoutBlock` — purely additive.
- Suggested-load display, RIR chip logging, rest timer (non-blocking,
  uncoupled from progression) — directly specified by the locked
  Handoff document.
- Exercise/activity substitution UX (Today only / Going forward) —
  Stage 4C's existing use cases, unchanged, now saved immediately (§1d).
- Calibration flow — no new persisted type, a `SetResult` like any
  other.
- AMRAP/EMOM/For Time/Rounds For Time/Chipper/Ladder execution shells —
  fully specified by existing `WorkoutFormat` cases.
- Steady-state/interval manual completion without HealthKit.
- Benchmark PR detection via `RecordFunctionalFitnessResultUseCase` —
  existing, unchanged, correct.
- `RecordSteadyStateResultUseCase`/`RecordIntervalResultUseCase` — a
  mechanical mirror of `RecordSetResultUseCase`'s already-proven shape.
- Every per-modality partial-result progression path (§1a) — no new
  engine logic anywhere, only accurate reporting of actual results.

## 4. Deferred (explicitly out of scope this stage)

- **Missed-session reflow UI** (approval sheet) — state contract only
  this stage (§1g).
- **Genuine intra-session/mid-set autoregulation** — no existing engine
  contract; a future, separately-designed engine feature (§1e).
- **"Remember my usual scaling" as a persisted override** — the
  existing exposure-history mechanism already informs future stimulus
  variance without one.
- **HealthKit read/write** — explicitly out of scope.
- **Full execution screens/SwiftUI implementation** — Stage 6B.
- **A finer Scaled-vs-Scaled comparability rule** (§1f) — data already
  supports it later; not built now.
- **A seventh tactical-window regeneration trigger for "Session just
  completed"** — not in the locked `TacticalWindowTrigger` list; still
  flagged, not added.

## 5. Non-blocking build-time verification (Stage 6B implementation detail, not a gate)

1. `FunctionalFitnessResult` has no dedicated "capped, not a clean
   finish" field the way legacy `WorkoutResult.cappedAtSeconds` does —
   add one if implementation reveals `scoreValue`'s stored time alone is
   insufficient context (`FUNCTIONAL_FITNESS_EXECUTION_FLOW.md` §3).
2. EMOM "incomplete minute" tracking — confirm
   `FunctionalFitnessPerformedMovement`'s existing fields are sufficient
   before adding anything new (`FUNCTIONAL_FITNESS_EXECUTION_FLOW.md` §2).
3. `IntensityTranslation`'s exact activity-pair coverage — verify it
   covers every substitution pair the endurance substitution UX offers
   before shipping that screen (`ENDURANCE_EXECUTION_FLOW.md` §3).
4. `IntervalProgressionEngine.evaluateSessionOutcome`'s exact
   `totalCount` semantics (prescribed interval count vs. attempted-this-
   session count) — confirm against its existing call sites so a
   partial interval session genuinely maps to a conservative outcome,
   not an inflated one computed only against what was attempted
   (`ENDURANCE_EXECUTION_FLOW.md` §2c).
