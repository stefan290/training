# Timer Architecture

Stage 6A: how every clock in the execution UI (rest timer, AMRAP, EMOM,
interval work/recovery) stays correct across backgrounding, locking and a
force-quit, without ever depending on an in-memory `Timer` tick surviving.
**Design pass — nothing here is implemented yet.**

## 1. The one rule everything else follows

> Timers are wall-clock anchored (`startedAt` + offset), never tick
> counts, so backgrounding, lock and app kill cannot drift the score.
> — `Training OS Handoff.dc.html` §12

A timer's displayed value is always **computed from persisted
timestamps at render time** — `elapsed = now - startedAt - accumulatedPauseDuration`
— never accumulated by counting `Timer.scheduledTimer` fire events.
SwiftUI's own periodic re-render (`TimelineView`/a lightweight
`Task`-based tick) only decides *when to redraw*; it never decides *what
the number is*. This is what makes §28's requirement ("in-progress
workout state must survive app backgrounding, force close, device
restart where local persistence survives") true by construction rather
than by careful timer bookkeeping.

## 2. `TimerState` — the one persisted shape, reused everywhere

```swift
struct TimerState: Codable, Equatable {
    var startedAt: Date
    /// nil while running.
    var pausedAt: Date?
    /// Sum of every prior pause's duration — updated when a pause ends,
    /// not accumulated tick-by-tick.
    var accumulatedPauseSeconds: TimeInterval
    /// The timer's own target duration, when it counts down (AMRAP cap,
    /// EMOM total, rest timer default) — nil for a pure count-up clock
    /// (For Time's elapsed clock).
    var targetDurationSeconds: Int?
    /// Which discrete unit this timer is currently on — the AMRAP has
    /// none (a single continuous clock), EMOM's is the current minute
    /// index (0-based), an interval block's is the current interval
    /// index alternating work/recovery. `nil` for timers with no
    /// sub-unit concept.
    var currentUnitIndex: Int?
}
```

**Never persist a tick count, a "seconds remaining" snapshot, or
anything else derived** — only the four inputs above. Every other value
(seconds remaining, which phase, whether the cap has passed) is a pure
function of `(TimerState, now)`, computed fresh every time it's needed
and never cached in a way that could go stale. This is what §38 asks for
explicitly: *"Persist startedAt, duration, pausedAt/accumulated pause,
relevant interval index... Do not persist timer ticks."*

```swift
func elapsedSeconds(_ state: TimerState, asOf now: Date) -> TimeInterval {
    let pauseSoFar = state.accumulatedPauseSeconds + (state.pausedAt.map { now.timeIntervalSince($0) } ?? 0)
    return now.timeIntervalSince(state.startedAt) - pauseSoFar
}

func remainingSeconds(_ state: TimerState, asOf now: Date) -> TimeInterval? {
    guard let target = state.targetDurationSeconds else { return nil }
    return TimeInterval(target) - elapsedSeconds(state, asOf: now)
}
```

`now` is always supplied by the caller at read time (the view's own
render pass), never read implicitly deep inside a shared helper —
mirroring this codebase's existing determinism discipline
(`SchedulingWindow.startDate`, `LongTermPlanner`'s `asOf` parameters):
nothing here needs a mockable clock because nothing here reads the clock
itself except the one call site that renders.

## 3. Where `TimerState` lives

`TimerState` is small, `Codable`, and scoped to exactly the `WorkoutBlock`
it's timing — persisted as a single optional field on `WorkoutBlock`:

```swift
// WorkoutBlock gains:
var timerState: TimerState?     // Codable struct, stored inline — not a
                                  // new @Model entity; nothing about a
                                  // timer's own state needs independent
                                  // identity, relationships, or a delete
                                  // rule of its own.
```

One block, one timer. A Session with a rest timer running inside a
strength block and, later, an AMRAP clock inside a different block never
needs two timers active at once — blocks execute one active block at a
time (`WORKOUT_EXECUTION.md` §3), so `WorkoutBlock.timerState` is never
ambiguous about which timer it refers to.

**Rest timer is the one exception worth naming explicitly:** it is not
really "the block's timer" — it counts down between two sets *inside* an
already-`.active` strength block. It still fits the same shape: a
`TimerState` that starts fresh each time a set is logged (§7), overwriting
the block's `timerState` for however long the rest lasts, never
persisted as a separate collection of "past rests" (a rest timer has no
result of its own — CLAUDE.md rule 3 doesn't apply here since a rest
timer is not a prescription/recommendation/result at all, just execution
scaffolding, matching §7's own instruction: *"Do not couple rest timing
to progression engine business logic."*)

## 4. Recovery on relaunch

1. Read `Session.status == .inProgress`, find the current block
   (`SESSION_STATE_MACHINE.md` §6 — the first block not `.completed`/
   `.skipped`).
2. If that block has a non-nil `timerState`, resume the UI directly from
   it — `elapsedSeconds`/`remainingSeconds` computed against `Date()` at
   the moment the view appears. No special "was this a crash or a normal
   background" branch exists; the exact same computation runs whether
   the app was gone for 3 seconds or 3 hours.
3. A timer whose `remainingSeconds` is already `<= 0` when recovered
   (the countdown finished while the app was closed) renders in its
   already-expired state immediately — an AMRAP/EMOM does not silently
   replay the transitions that would have fired while backgrounded; it
   simply shows "time's up" / the last scheduled minute, and the block's
   own completion flow (§17/§20 execution flows) takes over from there.

## 5. Persistence cadence — promptly, not continuously

`TimerState` is written:
- Once when a timer starts (`startedAt` stamped) — via whichever
  ViewModel action begins the block/rest/AMRAP/EMOM.
- Once when paused (`pausedAt` stamped) and once when resumed
  (`accumulatedPauseSeconds` updated, `pausedAt` cleared).
- Once when `currentUnitIndex` advances (EMOM's minute change, an
  interval's work→recovery→work transition).

Never on every UI tick. A `TimelineView`/periodic redraw needs no
persistence at all — it only re-renders the pure function in §2 against
a fresh `Date()`. This keeps the SwiftData write volume flat regardless
of how long a timer runs, per the offline-first, no-network-dependency
requirement (§29) and the general "views render state, they do not
themselves decide when to persist" separation (§37).

## 6. Local notifications and haptic/sound cues — presentation, not state

A local notification (rest timer, per the Handoff's §6: *"Rest timer
starts on log, runs in the background, and fires a local notification"*)
and haptic/sound cues (EMOM minute change, interval transition, AMRAP/
EMOM/For Time completion — §40) are **scheduled from `TimerState`**, never
the other way around: they are derived, best-effort UX layered on top of
the wall-clock-anchored truth, and their firing (or not firing, e.g. if
notification permission was denied) never changes what
`elapsedSeconds`/`remainingSeconds` compute. Losing a haptic cue because
the app was suspended is an acceptable UX gap; losing timer accuracy is
not — this asymmetry is deliberate and is why §7's instruction ("do not
couple rest timing to progression engine business logic") generalizes to
"do not couple *any* engine/business state to a cue's delivery."

## 7. Per-execution-mode use of `TimerState`

| Execution mode | `targetDurationSeconds` | `currentUnitIndex` meaning |
|---|---|---|
| Rest timer (strength) | The configured rest duration (§7 of `STRENGTH_EXECUTION_FLOW.md`) | `nil` |
| AMRAP | The block's `WorkoutFormat.amrap(capSeconds:)` | `nil` — one continuous clock |
| EMOM | `WorkoutFormat.emom(intervalSeconds:totalSeconds:).totalSeconds` | The current minute, 0-based; a new `TimerState` is not created per minute — `currentUnitIndex` simply increments and the same countdown restarts at `intervalSeconds` (a fresh `startedAt` is stamped at each minute boundary so the per-minute countdown itself stays wall-clock anchored, not just the overall session) |
| Interval work/recovery | The current leg's own duration (`IntervalPrescription.workDurationSeconds`/`recoveryDurationSeconds`) | The current interval index; a work leg and its following recovery leg are two separate `TimerState` writes (fresh `startedAt` each), not one timer spanning both |
| For Time | `nil` (count-up, no cap) or the block's `capSeconds` when `WorkoutFormat.forTime(capSeconds:)`/`.roundsForTime`/`.chipper`/`.ladder` carries one | `nil` |
| Distance-based intervals (no GPS automation, §18) | `nil` — the work leg has no timer at all until the user marks the distance complete; only the recovery leg between reps is timed | The current interval index |

Distance-based work legs (`workDistanceMeters` set, `workDurationSeconds`
nil) have no running clock during the work portion at all in V1 — per
§18's explicit instruction, distance completion is a manual "mark done"
action, not a timer. Only `recoveryDurationSeconds` (still a duration)
gets a `TimerState` between reps.
