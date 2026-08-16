# Stage 6A Decision Memo

Every place this pass's design documents (`WORKOUT_EXECUTION.md` and its
6 companions — `SESSION_STATE_MACHINE.md`, `TIMER_ARCHITECTURE.md`,
`STRENGTH_EXECUTION_FLOW.md`, `ENDURANCE_EXECUTION_FLOW.md`,
`FUNCTIONAL_FITNESS_EXECUTION_FLOW.md`, `WORKOUT_COMPLETION_PIPELINE.md`)
made a judgment call, found a real gap, or deferred a question —
collected here so Stage 6B does not start on an unreviewed assumption.
Per the kickoff's own instruction: **do not silently invent product
behavior.**

**Status: nothing below is yet reviewed/approved.** Every "Recommended
resolution" is this pass's confident proposal, not a decision already
made — Stage 6B should not begin until the MUST RESOLVE items are
either accepted as written or corrected.

## 1. MUST RESOLVE before Stage 6B

### 1a. Partial-session semantics — new field, not new status

**Question:** how does a Session finished early differ, in the data
model, from one finished in full?

**Recommended resolution:** add `Session.completionContext: SessionCompletionContext?`
(`.full`/`.partial`) — `SessionStatus` itself gains no new case.
`.abandoned` (existing case) stays reserved for a Session walked away
from with no explicit finish action at all. See
`SESSION_STATE_MACHINE.md` §2-4 for the full reasoning and the exact
three "stopped halfway" options (Resume later / Finish partial /
Abandon).

**Why this needs sign-off:** it's a schema addition, and the exact
planner-adherence treatment of `.abandoned` vs. `.completed(.partial)`
(does a partial count as "trained today" for missed-progress detection?)
is a product question this memo does not resolve on its own —
`SESSION_STATE_MACHINE.md` §3a flags it explicitly.

### 1b. First-entry PR semantics — presentation split, data unchanged

**Question:** should a first-ever logged result for an exercise/
benchmark show as "Personal record!" the way a genuine improvement does?

**Finding:** `ScoringEngine.isNewPersonalRecord` already returns `true`
for a first-ever entry — existing, tested, correct, and Stage 6 must not
change it (CLAUDE.md rule 4-adjacent: don't silently change a
tested engine's behavior).

**Recommended resolution:** keep the data model exactly as is; have the
recording use case's return value (or `CompleteSessionUseCase`'s
`CompletionSummary`) additionally surface whether `existingBest == nil`,
so the completion screen can label a true first entry neutrally
("First recorded") instead of celebratory ("Personal record!") — see
`FUNCTIONAL_FITNESS_EXECUTION_FLOW.md` §8.

**Why this needs sign-off:** it's a UI/copy policy decision (what
counts as "over-celebrating"), not something derivable from existing
locked docs.

### 1c. Timer recovery behavior — confirmed safe, flagging the one edge case

**Finding:** wall-clock-anchored `TimerState` (`TIMER_ARCHITECTURE.md`
§2) already handles ordinary recovery correctly by construction. The one
edge case worth explicit sign-off: a countdown that fully elapsed while
the app was closed (§4 of `TIMER_ARCHITECTURE.md`) renders as
already-expired on relaunch rather than replaying missed transitions —
**recommended resolution: this is correct and intended**, but confirm no
stakeholder expects "catch-up" playback (e.g. re-firing every missed
EMOM minute cue) — that would be a materially different, more complex
design.

### 1d. Session-result transaction boundary — confirmed, one convention gap to close

**Finding:** every existing `RecordXResultUseCase` inserts/mutates but
never calls `context.save()` itself; `CompleteSessionUseCase` should
follow the identical convention, with the calling ViewModel issuing
exactly one `save()` (`WORKOUT_COMPLETION_PIPELINE.md` §1).

**Recommended resolution:** adopt this convention explicitly for Stage
6B and hold it as a project-wide rule going forward (candidate for
`ARCHITECTURE.md`) — flagged as MUST RESOLVE only because it's the first
time this convention is being written down as a *rule* rather than an
observed pattern; if the team wants a different boundary (e.g. `save()`
per block, not per Session), that changes the crash-recovery story in
`SESSION_STATE_MACHINE.md` §6 non-trivially.

### 1e. Within-session load adjustment — not supported, confirm no expectation otherwise

**Finding:** no existing engine contract (`ProgressionEngine`/
`DoubleProgressionEngine`/`StrengthProgressionEngine`) supports live,
same-session, set-to-set load/rep adjustment — every mechanism operates
at "last occurrence's results → this occurrence's target" or coarser.

**Recommended resolution:** Stage 6 does not add this; every
`SetPrescription` is shown exactly as materialized regardless of how
earlier sets in the same session went (`STRENGTH_EXECUTION_FLOW.md` §6).
**Needs explicit confirmation** because it's plausible a stakeholder
expects RPE-based autoregulation to feel more "live" than this — if so,
that is new engine design, out of scope for this stage entirely, not a
UI-only addition.

### 1f. Benchmark Rx/Scaled comparison rules — confirmed already correct

**Finding:** `ScoringEngine.bestRecord`'s `context` filter already
guarantees Rx and Scaled never compete for the same `PersonalRecord`,
for every modality (`FUNCTIONAL_FITNESS_EXECUTION_FLOW.md` §7) — no new
logic needed. Listed here only to record that it was explicitly checked
against the kickoff's own requirement (§24-25) and found already
satisfied, not overlooked.

### 1g. Missed-session state model — structural contract only, confirm scope boundary

**Finding:** a `.scheduled` Session past its date is *displayable* as
missed without a persisted status change; the actual `.missed` write
happens only through a not-yet-built
`ProposeMissedSessionReflowUseCase`/`AcceptMissedSessionReflowUseCase`
pair, triggered by explicit user interaction (`SESSION_STATE_MACHINE.md`
§7).

**Recommended resolution:** Stage 6B builds the *state* (the derived
missed-display condition, the two use case names/signatures) but not the
reflow proposal/approval screen itself (frame 09) — that screen's full
UX is explicitly deferred to a later substage per the kickoff's own
§33 allowance. **Confirm this scope line** before Stage 6B, since
"missed session" touches both execution (this stage) and planning
(`LongTermPlanner`, already built) — it would be easy to accidentally
duplicate reflow logic across both if the boundary isn't held precisely.

## 2. Safe to implement (no further sign-off needed)

- `Session`/`WorkoutBlock` reuse exactly as documented — zero new
  `WorkoutBlockType`/`BlockStatus` cases (`SESSION_STATE_MACHINE.md` §1/§5).
- `TimerState` as a `Codable` struct on `WorkoutBlock` (`TIMER_ARCHITECTURE.md`
  §2-3) — purely additive, no relationship/delete-rule questions.
- Suggested-load display, RIR chip logging, rest timer (non-blocking,
  uncoupled from progression) — all directly specified by the already-
  locked Handoff document (`STRENGTH_EXECUTION_FLOW.md` §2-5).
- Exercise/activity substitution UX (Today only / Going forward) —
  Stage 4C's existing use cases, unchanged, just given a UI.
- Calibration flow — no new persisted type, a `SetResult` like any
  other (`STRENGTH_EXECUTION_FLOW.md` §8).
- AMRAP/EMOM/For Time/Rounds For Time/Chipper/Ladder execution shells —
  fully specified by existing `WorkoutFormat` cases plus the already-
  approved design source (`FUNCTIONAL_FITNESS_EXECUTION_FLOW.md` §1-4).
- Steady-state/interval manual completion without HealthKit
  (`ENDURANCE_EXECUTION_FLOW.md` §1-2) — every field is already optional
  exactly where it needs to be.
- Benchmark PR detection via `RecordFunctionalFitnessResultUseCase` —
  existing, unchanged, correct.
- `RecordSteadyStateResultUseCase`/`RecordIntervalResultUseCase` — new
  use cases, but a mechanical mirror of `RecordSetResultUseCase`'s
  already-proven shape (`WORKOUT_COMPLETION_PIPELINE.md` §2).

## 3. Deferred (explicitly out of scope this stage)

- **Missed-session reflow UI** (approval sheet, frame 09) — state
  contract only this stage (§1g above).
- **Mid-session/intra-set autoregulation** — no existing engine
  contract; a future, separately-designed engine feature (§1e above).
- **"Remember my usual scaling" as a persisted override** — the
  existing exposure-history mechanism already informs future stimulus
  variance without one; not built unless a real product need surfaces
  (`FUNCTIONAL_FITNESS_EXECUTION_FLOW.md` §6).
- **HealthKit read/write** — explicitly out of scope per the kickoff;
  every manual-entry field this pass specifies is HealthKit's eventual
  pre-fill target, never a blocking dependency.
- **Full execution screens/SwiftUI implementation** — this stage is
  analysis/design; Stage 6B builds the screens.
- **A seventh tactical-window regeneration trigger for "Session just
  completed"** — plausible, but not in the locked
  `TacticalWindowTrigger` list; flagged, not added
  (`WORKOUT_COMPLETION_PIPELINE.md` §7).

## 4. Real schema/architecture gaps found during this pass (not decisions — facts)

1. `RecordSteadyStateResultUseCase`/`RecordIntervalResultUseCase` do not
   exist — only test code attaches these results directly, with no
   `PerformanceProfile` fold-in or PR detection
   (`WORKOUT_EXECUTION.md` §1, `WORKOUT_COMPLETION_PIPELINE.md` §2).
2. `FunctionalFitnessResult` has no dedicated "capped, not a clean
   finish" field the way legacy `WorkoutResult.cappedAtSeconds` does —
   needs either a new optional field or a documented decision that
   `scoreValue`'s stored time alone is sufficient context
   (`FUNCTIONAL_FITNESS_EXECUTION_FLOW.md` §3).
3. EMOM "incomplete minute" tracking has no direct modern-path
   equivalent to legacy `WorkoutResult.incompleteMinuteIndexes` —
   `FunctionalFitnessPerformedMovement`'s per-minute performed-vs-
   prescribed fields may already be sufficient, or may need one more
   field; confirm during Stage 6B implementation
   (`FUNCTIONAL_FITNESS_EXECUTION_FLOW.md` §2).
4. `IntensityTranslation`'s exact activity-pair coverage was not
   exhaustively audited this pass — verify it covers every substitution
   pair the endurance substitution UX can actually offer before Stage
   6B ships that screen (`ENDURANCE_EXECUTION_FLOW.md` §3).
