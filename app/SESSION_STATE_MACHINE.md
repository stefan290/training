# Session State Machine

Stage 6A: the exact execution states for `Session` and `WorkoutBlock`, their
transitions, and what must survive a crash. **This is a design pass —
nothing here is implemented yet** (Stage 6B builds it).

**Status: RESOLVED.** All partial-session/completion-context decisions
below reflect the product owner's final Stage 6A resolution — see
`STAGE6A_DECISION_MEMO.md` §1a/§1g for the decision record.

## 1. `SessionStatus` — no new cases needed

The existing enum (`Domain/ValueTypes/Enums.swift`, Stage 1-2, unchanged
since) already covers every state the kickoff's minimum list names, once
"ready" and "paused" are recognized as *derived UI conditions*, not
persisted states:

```swift
enum SessionStatus: String, Codable, CaseIterable {
    case scheduled
    case inProgress
    case completed
    case skipped
    case missed
    case abandoned
}
```

| Kickoff's term | Maps to |
|---|---|
| planned | `.scheduled` |
| ready | **Not a stored state.** A `.scheduled` Session is always "ready" once its blocks are materialized — there is no separate blocking precondition in this codebase (no permission gate, no required-download). "Ready" is UI language for "Start is enabled," computed, never persisted. |
| inProgress | `.inProgress` |
| paused | **Not a `SessionStatus` case.** A Session stays `.inProgress` for its entire active lifetime, including while backgrounded, locked, or force-quit. "Paused" is a property of a *timer* (`TIMER_ARCHITECTURE.md`), not of the Session — pausing a rest timer or an AMRAP clock never changes `Session.status`. This is a deliberate scope narrowing: the kickoff's own §34 explicitly excludes universal re-entry/pause-of-training-itself from this stage; the only "pause" Stage 6 owns is pausing a running clock mid-block. |
| completed | `.completed` — see §2 for the new `completionContext` that distinguishes full vs. partial |
| skipped | `.skipped` — an explicit "Skip / Can't train today" action taken **before** the Session was ever started (§4 below) |
| partiallyCompleted | **Not a new `SessionStatus` case** — `.completed` with `completionContext == .partial` (§2). A session that was actually started and intentionally ended early is still, correctly, a *completed* session from the state machine's point of view; what differs is how much of it happened, which `completionContext` carries. |

`.missed` remains exactly as documented for the existing Plan/Calendar
surfaces (`TrainingOS.dc.html` frame 09, `Training OS Handoff.dc.html` §3):
**derived, never proactively written by a background process.** A
`.scheduled` Session whose day has passed is *treated* as missed for
display/planning purposes the moment the UI reads it (a pure function of
`status == .scheduled && scheduledTime < now`, `now` supplied by the
caller, never read implicitly) — but the persisted `status` field is only
actually written to `.missed` when the user interacts with the
missed-session prompt (`ProposeMissedSessionReflowUseCase`, not yet
built — §33). This preserves the Handoff's own invariant: *"the reflow
proposal is generated on next app open, not a background job, so the
user is never told about changes made while they were away."*

`.abandoned` is reserved **exclusively** for a Session that was started
(`inProgress`) and never explicitly closed out at all — discovered
later (e.g. a future "you left this unfinished 3 days ago" prompt, out
of scope this stage), never a button the user taps mid-session. Stopping
a Session early is always either "Resume later" (no state change) or
"Finish as Partial" (§2-4) — there is no separate, user-facing "Abandon"
action.

## 2. RESOLVED: two new, additive completion-context fields — Session and Block

```swift
enum SessionCompletionContext: String, Codable, CaseIterable {
    /// Every non-skipped block reached `.completed` with its own
    /// `completionContext == .full`.
    case full
    /// The user explicitly finished early via "Finish as Partial" (§4) —
    /// some blocks remain `.pending`/`.active` (and are flipped to
    /// `.skipped` as part of that action) and/or one or more completed
    /// blocks are themselves `.partial`. Logged results are kept exactly
    /// as recorded; nothing is discarded.
    case partial
}

// Session gains:
var completionContext: SessionCompletionContext?   // nil until `.completed`
```

```swift
enum BlockCompletionContext: String, Codable, CaseIterable {
    /// Every unit the block's prescription called for (sets, rounds,
    /// intervals, movements) has a real logged result.
    case full
    /// The block was marked `.completed` with fewer results than its
    /// prescription called for — e.g. 2 of 3 sets logged, one round of
    /// an AMRAP circuit skipped mid-effort.
    case partial
}

// WorkoutBlock gains:
var completionContext: BlockCompletionContext?   // nil until `.completed`
```

**Why two fields, not new `SessionStatus`/`BlockStatus` cases:** "how
much was actually done" and "is this Session/Block finished" are
independent questions. Collapsing them into more enum cases (`.completed`,
`.partiallyCompleted`, `.completedWithSkips`, …) would just split the
same information across more cases with no new behavior attached to any
of them — every consumer (the planner's adherence read, the Plan
calendar dot, `WORKOUT_COMPLETION_PIPELINE.md`'s transaction, a
`ProgrammingSystem`'s own progression engine) only ever needs to ask "is
it completed" and, separately, "was it the whole thing." `nil` is a
valid, common state for every Session/Block that is not yet `.completed`.

**Why the Block-level field is needed, not just the Session-level one:**
the resolved decision explicitly asks for "which blocks were completed /
partially completed / not started" to be individually answerable — a
Session-level flag alone can't say *which* block(s) were partial when a
Session has several. `BlockStatus.skipped` already answers "not
started/skipped" cleanly; `completionContext` only ever refines
`.completed`.

**Progression consumption — resolved, no new engine input:** execution
never computes progress/hold/repeat itself. It reports actual results
honestly; each `ProgrammingSystem`'s own engine already has (or, for
Steady State, structurally doesn't need) a conservative default for
incomplete input — see `STAGE6A_DECISION_MEMO.md` §1a for the full,
per-modality confirmation (`DoubleProgressionEngine` → `HOLD` on
mismatched count; `IntervalProgressionEngine.evaluateSessionOutcome` →
a graduated fraction-based outcome; `SteadyStateProgressionEngine` →
doesn't consume actual results at all; `FunctionalFitnessDecisionEngine`
→ reasons over exposure history, unaffected by a single partial
session). No new `ProgressionInput` field is introduced by this
decision.

## 3. Session transitions

```
scheduled ──[user taps Start]──────────────────────────────► inProgress
scheduled ──[user taps "Skip / Can't train today," §4]─────► skipped
scheduled ──[missed-session prompt interacted with, day passed]─► missed
inProgress ──[Finish Session — every block .completed(.full)]──► completed(.full)
inProgress ──[Finish as Partial — some blocks .pending/.active,
              and/or a completed block was itself .partial]────► completed(.partial)
inProgress ──[background / lock / force-quit / crash]──────► inProgress (no transition — §6)
```

No transition ever moves a Session backward (`.completed` →
`.inProgress`, etc.) — resuming a mistakenly-finished Session is out of
scope for this stage; if it's needed later it is a new, explicitly-named
transition, not a reuse of an existing one.

`.abandoned` is intentionally not reachable from any in-session action —
see §1's note. It has no transition arrow above because nothing in
Stage 6B writes it; it is reserved entirely for a future, separate
"unfinished session discovered later" mechanism, out of scope this
stage.

### 3a. "Finish as Partial" — the only stopped-halfway terminal action

**RESOLVED:** the original three-option design (Resume later / Finish
partial / Abandon) is reduced to two real choices — the product owner's
decision removed "Abandon" as a distinct, user-facing action. Every
early stop that the user explicitly commits to is "Finish as Partial":

- Every `.pending`/`.active` block becomes `.skipped`.
- Any block that was `.completed` with fewer results than prescribed
  keeps `completionContext = .partial` (set when that block itself was
  finished, §5 below) — untouched by the Session-level action.
- `Session.status = .completed`, `Session.completionContext = .partial`.
- The full completion pipeline runs exactly as it would for a full
  finish, just over fewer/partial blocks
  (`WORKOUT_COMPLETION_PIPELINE.md` §5) — never a different, lesser
  pipeline.
- Every logged result is permanent and untouched — CLAUDE.md rule 1
  applies to a Session's own state exactly as it does to a
  `ProgramDefinition`'s.

There is no separate "this didn't really count" outcome for an
in-session action — if a session genuinely didn't happen as training
(injury, a false start), the user simply never taps Start, or uses
"Skip / Can't train today" beforehand (§4). Once a Session is
`.inProgress` and the user explicitly finishes it, it is `.completed`
(full or partial), full stop.

## 4. The two "stopped halfway" options, and the pre-start "can't train" option

| User sees | Action | Result |
|---|---|---|
| Before starting: "Skip / Can't train today" | Explicit, one tap, from Today | `status = .skipped` — a structured fact, distinct from `.missed` (§7), never silently dropped from the schedule. Only the missed/skipped-session use cases (not yet built, §33) act on it, and only when the user next opens the app. |
| Mid-session: "Resume later" | No state change at all | Session stays `.inProgress`; this is simply leaving the screen. Recovery (§6) picks it back up exactly where it was. |
| Mid-session: "Finish as Partial" | Explicit tap | `status = .completed`, `completionContext = .partial` (§3a). Full completion pipeline runs. |

## 5. `BlockStatus` — unchanged, no new cases; `completionContext` refines `.completed`

```swift
enum BlockStatus: String, Codable, CaseIterable {
    case pending
    case active
    case completed
    case skipped
}
```

A block reaching `.completed` sets its own `completionContext` (§2) at
the moment it's finished: `.full` when every prescribed unit (set/round/
interval/movement) has a real logged result, `.partial` otherwise — e.g.
a strength block with 2 of 3 sets logged and then moved past is
`.completed`/`.partial`, never silently reported as `.full`. The true
record of what happened always lives in the actual `SetResult`/
`SteadyStateResult`/`IntervalResult`/`FunctionalFitnessResult` rows,
which the completion pipeline never fabricates to match the
prescription — `completionContext` is a cheap, pre-computed summary of
that fact for fast reads (planner/UI), never a second source of truth
that could disagree with the underlying rows.

`.skipped` at the block level (no `completionContext` — it's only set on
`.completed`) is what the kickoff's "mark incomplete" actions (an EMOM
minute, a For Time round not attempted, an entire block the user
chooses not to do) resolve to — always an explicit user action via the
block's own execution screen, never inferred by a timer expiring
silently.

## 6. Crash / app-restart recovery (offline-first, no network involved)

An interrupted Session (`.inProgress`, app backgrounded/locked/force-quit/
device restarted) must resume exactly where it left off, per
`Training OS Handoff.dc.html` §12: *"an interrupted Session resumes at its
last completed block; in-flight set entry is restored from local draft
state."* Concretely:

- Every `SetResult`/`SteadyStateResult`/`IntervalResult`/
  `FunctionalFitnessResult` already logged is already persisted (each is
  written the moment its recording use case runs — §2 of
  `WORKOUT_COMPLETION_PIPELINE.md`) — nothing about recovery depends on
  an in-memory buffer of completed sets.
- The **current, not-yet-logged** set/round/interval's in-progress entry
  (a stepper value the user was mid-adjustment on, an AMRAP round count
  before "Finish" was tapped) is the one thing that is *not* already a
  permanent result row — an unconfirmed edit like this is deliberately
  **not** persisted (`WORKOUT_COMPLETION_PIPELINE.md` §1's "no save for
  transient UI state" rule); only a *confirmed* action (a logged set, a
  round tap, a block/session status change) is promptly saved. A crash
  before confirmation loses only that one unconfirmed edit, never
  anything already confirmed — see `TIMER_ARCHITECTURE.md` §5 for the
  identical cadence rule applied to timer state.
- Which block is "current" is always re-derivable from `WorkoutBlock.status`
  (`orderedBlocks.first { $0.status != .completed && $0.status != .skipped }`)
  — never a separately-stored "current block index" that could drift out
  of sync with the blocks' own statuses.
- Timer state recovers from wall-clock-anchored persisted fields
  (`startedAt`/`pausedAt`/accumulated pause), never from an in-memory
  `Timer`/`Task` — see `TIMER_ARCHITECTURE.md`.

## 7. Missed-session scope boundary — RESOLVED

**Execution's job is to record what happened; deciding what happens to
the future schedule is `SchedulingPipeline`/`LongTermPlanner`'s job,
unchanged.** Stage 6B never implements a second reflow engine inside
workout execution:

```
Execution → records missed/partial/skipped state
         → SchedulingPipeline/LongTermPlanner reads that state
         → generates a reflow proposal
         → user approves/rejects (existing approval-sheet pattern)
```

**The one distinction Stage 6B must never blur — two different existing
`SessionStatus` cases, two different triggers, never auto-applied to
the wrong one:**

| | `.skipped` | `.missed` |
|---|---|---|
| Meaning | The user explicitly said "Can't train today" | The Session's date passed with no action at all |
| Written by | An explicit, one-tap user action, **before** the Session was ever started (§4) | Only when the user later views and interacts with the missed-session prompt — never a background process, never written just because a date comparison is true |
| What Stage 6B must not do | Must not write `.skipped` for a Session the user simply never got to | Must not auto-write `.missed` onto every past-due `.scheduled` Session indiscriminately the moment its date passes |

A `.scheduled` Session whose `scheduledTime` (or Day's date) is in the
past, read as of a caller-supplied `asOf`, is *displayable* as missed
without its `status` having changed yet — the persisted write to
`.missed` happens only through the explicit use case pair
(`ProposeMissedSessionReflowUseCase`/`AcceptMissedSessionReflowUseCase`
— names only, full reflow UX deferred, §33) triggered by user
interaction, matching the Handoff's own locked "never a background job"
instruction. Once written (`.skipped` or `.missed`), the existing
`SchedulingPipeline`/`LongTermPlanner` read it through `Session.status`/
`ScheduleIssue` exactly as they already do for any other scheduling
signal — no new reading mechanism, only the two narrowly-scoped writers
described above.

## Implementation status (Stage 6B)

Every transition described above is wired to a real UI action, never a
background process: `StartSessionUseCase` (Start, idempotent),
`CompleteSessionUseCase` (Finish/Finish-as-Partial, idempotent against a
double tap — `OrchestratingUseCaseTests.testCompleteSessionCalledTwiceNeverReMutatesOrDuplicates`),
`ChangeSessionStatusUseCase.skip`/`.markMissed` (Can't-train-today from
Session Detail; the missed-session prompt on Today's own card, written
only if the user taps "Mark Missed" — never inferred just because
`scheduledTime` has passed). "Resume Later" for a stopped-halfway Session
is a true no-op — dismissing the screen without calling any use case
leaves the Session exactly as `.inProgress` as it already was, exactly
as designed.
