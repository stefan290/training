# Session State Machine

Stage 6A: the exact execution states for `Session` and `WorkoutBlock`, their
transitions, and what must survive a crash. **This is a design pass —
nothing here is implemented yet** (Stage 6B builds it); see
`STAGE6A_DECISION_MEMO.md` for what's still open.

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

`.abandoned` is reserved for a Session that was started
(`inProgress`) and never explicitly finished at all — discovered later
(e.g. the next day, or the next time the app opens), never a status the
user directly chooses from an in-session action sheet. See §4's exact
mapping of the three "stopped halfway" options.

## 2. New, additive field: `Session.completionContext`

```swift
enum SessionCompletionContext: String, Codable, CaseIterable {
    /// Every non-skipped block reached `.completed`.
    case full
    /// The user explicitly finished early via "Finish partial" (§4) —
    /// some blocks remain `.pending`/`.active`. Logged results are kept
    /// exactly as recorded; nothing is discarded.
    case partial
}

// Session gains:
var completionContext: SessionCompletionContext?   // nil until `.completed`
```

**Why one new field instead of a new `SessionStatus` case:** "how much
was actually done" and "is this Session finished" are independent
questions. Collapsing them into more `SessionStatus` cases (`.completed`,
`.partiallyCompleted`, `.completedWithSkips`, …) would just be the same
information split across more enum cases with no new behavior attached
to any of them — every consumer (the planner's adherence read, the Plan
calendar dot, `WORKOUT_COMPLETION_PIPELINE.md`'s transaction) only ever
needs to ask "is it completed" and, separately, "was it the whole
thing." One optional field answers the second question without
multiplying the first. `nil` is a valid, common state for every Session
that is not yet `.completed` (`.scheduled`/`.inProgress`/`.skipped`/
`.missed`/`.abandoned` never set it).

**Flagged as a decision-memo item** (`STAGE6A_DECISION_MEMO.md` §1) —
this is a schema addition, not something the locked Handoff spec states
explicitly; the resolution above is a recommendation, not a foregone
conclusion.

## 3. Session transitions

```
scheduled ──[user taps Start]──────────────────────────────► inProgress
scheduled ──[user taps "Skip / Can't train today," §4]─────► skipped
scheduled ──[reflow prompt accepted/dismissed, day passed]─► missed
inProgress ──[Finish Session — every block .completed/.skipped]──► completed(.full)
inProgress ──[Finish partial — some blocks still .pending/.active]──► completed(.partial)
inProgress ──[Abandon]──────────────────────────────────────► abandoned
inProgress ──[background / lock / force-quit / crash]──────► inProgress (no transition — §5)
```

No transition ever moves a Session backward (`.completed` →
`.inProgress`, etc.) — resuming a mistakenly-finished Session is out of
scope for this stage; if it's needed later it is a new, explicitly-named
transition, not a reuse of an existing one.

### 3a. What "Abandon" actually does differently from "Finish partial"

Both preserve every logged result — CLAUDE.md rule 1 applies to a
Session's own state exactly as it does to a `ProgramDefinition`'s.  The
difference is intent, not data loss:

- **Finish partial** — the user is done for today and wants what they
  did to count as today's legitimate training. Runs the full completion
  pipeline (`WORKOUT_COMPLETION_PIPELINE.md`) exactly like a full
  finish, just over fewer blocks.
- **Abandon** — the user is walking away from something that didn't
  really happen as training (interrupted, injured, a mistake). Still
  never discards logged sets/results (they already live permanently in
  `ExercisePerformanceProfile`/`ActivityPerformanceProfile`/
  `BenchmarkPerformanceProfile` the moment each was logged — see §5 of
  `WORKOUT_COMPLETION_PIPELINE.md`), but the Session itself does not
  count as a positive adherence signal for planning purposes (§32 of
  `PHASE_PLANNING_RULES.md`'s missed-progress signal reads
  `.abandoned` the same way it would read a genuine miss — an
  observable fact, never a punitive label shown to the user).

**Flagged as a decision-memo item** — the exact planner-adherence
treatment of `.abandoned` vs. `.completed(.partial)` is a product
question this stage surfaces the *state* for for; it does not implement
new planner logic to consume it (`LongTermPlanner`/`PHASE_PLANNING_RULES.md`
already reads `Session.status` for missed-progress detection today; that
reading logic is unchanged by this stage).

## 4. The three "stopped halfway" options, and the pre-start "can't train" option

| User sees | Action | Result |
|---|---|---|
| Before starting: "Skip / Can't train today" | Explicit, one tap, from Today | `status = .skipped` — a structured fact, never silently dropped from the schedule. `ProposeMissedSessionReflowUseCase` (not yet built, §33) is the only thing that acts on it, and only when the user next opens the app. |
| Mid-session: "Resume later" | No state change at all | Session stays `.inProgress`; this is simply leaving the screen. Recovery (§5) picks it back up exactly where it was. |
| Mid-session: "Finish partial" | Explicit tap | `status = .completed`, `completionContext = .partial`. Full completion pipeline runs. |
| Mid-session: "Abandon / skip remainder" | Explicit tap | `status = .abandoned`. Logged results are untouched and permanent; the Session itself is not treated as a positive adherence signal (§3a). |

## 5. `BlockStatus` — unchanged, no new cases

```swift
enum BlockStatus: String, Codable, CaseIterable {
    case pending
    case active
    case completed
    case skipped
}
```

A block reaching `.completed` never implies "every prescribed set/rep/
interval was logged" — a strength block with 2 of 3 sets logged and then
moved past is still `.completed` at the block level; the true record of
what happened lives in the actual `SetResult`/`SteadyStateResult`/
`IntervalResult`/`FunctionalFitnessResult` rows, which the completion
pipeline never fabricates to match the prescription. This mirrors §2's
same reasoning one level down: block-level partial-ness needs no new
enum case because the underlying result rows already carry the whole
truth.

`.skipped` at the block level is what the kickoff's "mark incomplete"
actions (an EMOM minute, a For Time round not attempted, an entire block
the user chooses not to do) resolve to — always an explicit user action
via the block's own execution screen, never inferred by a timer expiring
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
  permanent result row — recovering it needs an explicit, promptly-
  persisted draft, not app-lifecycle luck. `STAGE6A_DECISION_MEMO.md` §2
  flags exactly what that draft needs to hold and how often it's
  written.
- Which block is "current" is always re-derivable from `WorkoutBlock.status`
  (`orderedBlocks.first { $0.status != .completed && $0.status != .skipped }`)
  — never a separately-stored "current block index" that could drift out
  of sync with the blocks' own statuses.
- Timer state recovers from wall-clock-anchored persisted fields
  (`startedAt`/`pausedAt`/accumulated pause), never from an in-memory
  `Timer`/`Task` — see `TIMER_ARCHITECTURE.md`.

## 7. Missed-session state contract (structural only — full reflow UX deferred, §33)

Stage 6 defines the *state*, not the reflow proposal/approval UI itself
(that is `LongTermPlanner`/`SchedulingPipeline` territory, already
partly built in Stage 5, and screen 09's approval-sheet UI is explicitly
out of scope for this stage's screens):

- A `.scheduled` Session whose `scheduledTime` (or its Day's date) is in
  the past, read as of a caller-supplied `asOf`, is *displayable* as
  missed without its `status` having changed yet.
- The transition to a persisted `.missed` status happens only through an
  explicit use case (`ProposeMissedSessionReflowUseCase`/
  `AcceptMissedSessionReflowUseCase` — names only, not built this stage)
  triggered by the user viewing and acting on the prompt — never a
  background job, matching the Handoff's own locked instruction.
- Once `.missed`, the existing `SchedulingPipeline`/`LongTermPlanner`
  read this fact through `Session.status`/`ScheduleIssue` exactly as
  they already do for any other scheduling signal — no new reading
  mechanism is required, only the new writer described above.
