# Functional Fitness Execution Flow

Stage 6A: execution for `.functionalFitness` `WorkoutBlock`s — every
`WorkoutFormat` case, scaling, and benchmark completion/PR detection.
**Design pass — nothing here is implemented yet.**

**Status: RESOLVED.** §7/§8 reflect the product owner's confirmed
benchmark Rx/Scaled and first-entry PR presentation decisions — see
`STAGE6A_DECISION_MEMO.md` §1b/§1f.

## 0. One block type, nine formats — never a modality-specific block

All of AMRAP/EMOM/For Time/Rounds For Time/Chipper/Ladder/Max Load/Max
Reps/Intervals share the single `.functionalFitness` `WorkoutBlockType`,
distinguished only by `FunctionalFitnessPrescription.format: WorkoutFormat`
(`WorkoutFormat.swift`) and scored via `FunctionalFitnessResult.scoreType`/
`.scoreValue`/`.scoreDirection` (`ScoreTypes.swift`). Execution branches
on `format`, never on a new per-format block type — the same "typed
enum, not a subclass per case" discipline already used throughout this
codebase. **The legacy `.amrap`/`.emom`/`.forTime` `WorkoutBlockType`
cases and `WorkoutResult` are Stage 1-2 seed-scenario-only** (confirmed:
their only production call sites are `SeedScenarios.swift` and one
legacy test) — Stage 6 execution targets `.functionalFitness` +
`FunctionalFitnessPrescription`/`FunctionalFitnessResult` exclusively;
it does not build a second execution path for the legacy type.

```
FunctionalFitnessPrescription { stimulus: Stimulus, format: WorkoutFormat,
                                 movements: [FunctionalFitnessMovement] }
FunctionalFitnessResult { scoreType, scoreValue: ScoreValue, scoreDirection,
                          resultContext: .rx | .scaled,
                          performedMovements: [FunctionalFitnessPerformedMovement] }
```

## 1. AMRAP (§19) — one full-width tap target

Per the *rebuilt* design (`Training OS.dc.html` frame 13, which supersedes
frame 04's earlier stepper layout — the Handoff's own locked description
matches frame 13 exactly):

```
                    WORK
                   11:47                 (countdown, WorkoutFormat.amrap(capSeconds:))

┌──────────────────────────────────────────┐
│              TAP TO COUNT A ROUND          │
│                                              │
│                    7                        │
│              rounds complete                │
└──────────────────────────────────────────┘
Now: Cal Bike (15)                                    undo

[ Start/Pause ]              [ Finish · score 7 rounds ]
```

- A single tap anywhere on the large target increments the round
  counter by one — **no per-movement rep logging during the effort**,
  per the kickoff's explicit instruction. `undo` (small, secondary)
  decrements by one for mis-taps.
- "Now: `<movement>`" shows which movement in the round rotation is
  current, purely informational — it does not gate the tap.
- **Extra reps are asked exactly once, after time expires** (not
  during) — a stepper for "reps completed in the unfinished round,"
  shown only once the countdown reaches zero (`a2Capped`-style
  condition in the design source). **Resolved relaunch behavior**
  (`TIMER_ARCHITECTURE.md` §4): if the cap already passed while the app
  was closed, the round-tap target is disabled immediately on relaunch
  and the flow goes straight to this extra-reps step — the user is
  required to complete the result, never left sitting at a stale
  pre-cap screen.
- **Final score**: `ScoreValue.roundsAndReps(rounds:, partialReps:)` —
  "7 + 14," never a single collapsed number.
- Scaling (§4) is decided once, before the first tap, and shown
  alongside the movement rotation, never re-asked mid-effort.

## 2. EMOM (§20) — hands-off, auto-advancing

Per frame 14 ("hands off"):

```
Minute 4 / 12
        0:38
This minute
12 CAL ROW
──────────────────────────
Next          10 BURPEES
[1][2][3][4][5][6][7][8][9][10][11][12]   (minute strip, colored by status)
◔ 3-second cue incoming
[ mark incomplete ]  (optional, reversible)

[ Start/Pause ]     [ Reset ]
```

- The movement **advances automatically** on the minute boundary — no
  tap required to "complete" a minute; `FunctionalFitnessMovement.minuteSlot`
  (1-based) already encodes which minute each rotation movement belongs
  to, so the block's own materialized movement list drives what's shown
  each minute without any live decision logic.
- A 3-second pre-cue and a minute-change cue fire as tone + haptic
  (§40) — the screen need not be watched, matching the Handoff's own
  "no interaction is required to complete the block" instruction.
- **Mark incomplete** is optional, per-minute, reversible — recorded as
  one of `WorkoutResult.incompleteMinuteIndexes`'s spiritual successor:
  for the modern `.functionalFitness` path, incomplete minutes are
  tracked per `FunctionalFitnessPerformedMovement` (e.g. a
  `performedReps` short of the prescribed `reps` for that minute's
  movement) rather than a flat index array — non-blocking build-time
  verification (`STAGE6A_DECISION_MEMO.md` §5) confirms whether the
  existing fields are sufficient or one more field is needed for "which
  minutes were incomplete."
- **Resolved relaunch behavior** (`TIMER_ARCHITECTURE.md` §4): the
  current minute is recomputed deterministically from elapsed time
  (`floor(elapsed ÷ intervalSeconds)`), never replayed minute by minute
  — the app closed at minute 4 and reopened during what would be minute
  9 shows minute 9 immediately, with no burst of missed cues.
- **Score**: `ScoreType.completedIntervals`/`ScoreValue.completedIntervals(_:)`
  — minutes actually completed as prescribed, out of the total.

## 3. For Time (§21) — running clock, typed completion

Per frame 11:

```
Elapsed
  6:42
21-15-9 · Thrusters 42.5 kg · Pull-ups

[ Start/Stop ]      [ Split ]

21   Thrusters / Pull-ups          [✓]
15   Thrusters / Pull-ups          [ ]
 9   Thrusters / Pull-ups          [ ]

Scaling: Rx                 [Rx]  [Scale pull-ups]

[         Finish · time 6:42         ]
```

- Round checkboxes are large tap targets (accessibility §39); checking
  a round is informational pacing only — the authoritative result is
  the typed completion below, not the checkboxes themselves.
- **Time cap**: when `WorkoutFormat.forTime(capSeconds:)` (or
  `.roundsForTime`/`.chipper`/`.ladder`, all of which carry an optional
  `capSeconds`) has a cap and it's reached, the clock turns amber and
  keeps running — it does **not** stop or force-finish the block. The
  eventual result stores `ScoreValue.time(seconds:)` at the moment
  Finish is actually tapped, with the capped context preserved via
  `FunctionalFitnessResult`'s own fields (a "capped, not a clean finish"
  fact). Today's `FunctionalFitnessResult` has no dedicated `cappedAt`
  field the way legacy `WorkoutResult.cappedAtSeconds` does — add one if
  Stage 6B implementation confirms `scoreValue`'s stored time alone is
  insufficient context (non-blocking build-time verification,
  `STAGE6A_DECISION_MEMO.md` §5).
- **Scaling** (§4) is chosen and shown before the first rep, recorded
  with the result (`resultContext`).

## 4. Rounds For Time / Chipper / Ladder (§22)

All three reuse the exact same For Time execution shell (§3) — a running
clock, a typed completion time — differing only in how the prescribed
work is displayed, driven entirely by `WorkoutFormat`/`orderedMovements`:

- **`.roundsForTime(rounds:, capSeconds:)`** — the round list (§3) repeats
  `rounds` times through the same movement set; round checkboxes count
  up to `rounds`, never re-listed per movement per round.
- **`.chipper(capSeconds:)`** — one long, ordered list of distinct
  movements (`orderedMovements`, no repeating rounds) — each movement is
  its own checkbox row, checked off once, top to bottom.
- **`.ladder(direction:, capSeconds:)`** — `orderedMovements`/rep counts
  displayed in the prescribed ascending/descending sequence
  (`LadderDirection`); execution is otherwise identical to the chipper
  shell.

None of these need their own screen — the kickoff's own instruction
("V1 interaction can stay simple") is satisfied by parameterizing the
existing For Time shell on `format`, never building three more bespoke
UIs. The typed `FunctionalFitnessPrescription`/`orderedMovements` already
carry every structural fact each format needs to render its list
correctly; nothing here reduces a format to unstructured workout text.

## 5. Max Load / Max Reps (§0's remaining two formats)

Not named explicitly in the kickoff's numbered items, but real
`WorkoutFormat` cases that need a place in this design:

- **`.maxLoad`** — a single best-effort attempt at a load (e.g. a max
  Clean & Jerk within a Functional Fitness block, distinct from a
  Powerlifting main lift). Execution shell: a single stepper for the
  achieved load, logged once. `ScoreValue.load(kilograms:)`,
  `scoreDirection: .higherIsBetter`.
- **`.maxReps(capSeconds:)`** — as many reps as possible of one
  movement within a cap (distinct from AMRAP's *rounds* of a whole
  circuit). Execution shell: a single large rep counter, tap-to-
  increment exactly like AMRAP's round target, capped by a countdown.
  `ScoreValue.repetitions(_:)`, `scoreDirection: .higherIsBetter`.

Both reuse UI primitives already established by §1/§2 (a countdown, a
tap-to-increment counter, a single-value stepper) — no new interaction
pattern is introduced.

## 6. Scaling (§23) — Scale/Modify, never mutating the prescription

From any movement: **"Scale / Modify"** → e.g. Toes-to-Bar → Knee Raises.

```
FunctionalFitnessPerformedMovement {
    prescribedMovement: FunctionalFitnessMovement   // unchanged pointer — traceability only
    performedExercise: Exercise?                     // nil = performed exactly as prescribed;
                                                       // non-nil = the scaled substitute
    performedReps / performedCalories /
    performedDistanceMeters / performedLoadKilograms // what actually happened
}
```

Exactly mirrors `FunctionalFitnessPerformedMovement`'s own doc comment:
*"the original prescription is preserved exactly as prescribed, and the
performed variant... is recorded alongside it, never overwriting it."*
The prescribed movement (`FunctionalFitnessMovement`) is never mutated —
scaling is entirely expressed in the **result's** performed-movement
row, attached at completion time, not at prescription time. This is the
same THIS-SESSION-ONLY-by-default posture as exercise substitution (§10
of `STRENGTH_EXECUTION_FLOW.md`), but scaling has no "going forward"
persisted-override counterpart in the current schema — Stage 3B/3C
deliberately left "remembered scaling, offered, never assumed" (the
Handoff's own locked language) as informational history only
(`FunctionalFitnessExposureHistoryBuilder` already reads exactly this
history to inform future *stimulus variance* decisions, not to
auto-apply a scaling choice) — **deferred** (`STAGE6A_DECISION_MEMO.md`
§4): a "remember my usual scaling for this movement" persisted override
is not built this stage, since the exposure-history mechanism already
gives the planner what it needs without one. Recorded via
`LogFunctionalFitnessResultUseCase` (wrapping
`RecordFunctionalFitnessResultUseCase`), saving immediately — identical
convention to every other logged result (`WORKOUT_COMPLETION_PIPELINE.md`
§1).

## 7. Benchmark completion and PR detection (§24-25) — RESOLVED, architecture confirmed unchanged

A `.functionalFitness` block whose `FunctionalFitnessResult.benchmark`
is set (a `BenchmarkDefinition`, e.g. "Fran") is recorded through
`RecordFunctionalFitnessResultUseCase.recordResult(_:for:benchmark:performanceProfile:modelContext:)`
(existing, unchanged) — the **sole** path a Functional Fitness result
becomes a `PersonalRecord`. **The product owner confirmed this
architecture as-is; it is not reopened.**

1. Get-or-create the `BenchmarkPerformanceProfile` for this
   `BenchmarkDefinition` (`PerformanceProfileStore.benchmarkProfile`).
2. `ScoringEngine.bestRecord(among: benchmarkProfile.personalRecords, context: result.resultContext, repBand: nil)`
   — **Rx and Scaled never compete for the same record**, enforced by
   the `context` filter already in `ScoringEngine`, not something Stage 6
   needs to re-implement (§24's requirement is already fully satisfied
   by existing, tested code).
3. `ScoringEngine.isNewPersonalRecord` compares the new
   `RecordFunctionalFitnessResultUseCase.comparableValue(for:)`-derived
   number against the existing best in that same context — a genuine
   PR only when it actually beats the prior best, or when there was no
   prior best at all (§8 below).
4. A generated (non-benchmark) Functional Fitness workout is **never**
   automatically treated as a benchmark — `benchmark`/`performanceProfile`
   are both optional on the recording call precisely so a one-off
   generated metcon records as permanent training history without
   silently becoming a tracked benchmark (`FunctionalFitnessResult.swift`'s
   own doc comment; §24's "do not make every generated WOD a benchmark"
   is already the existing, tested behavior).

**Finer Scaled-vs-Scaled comparability — data already sufficient, not
built now:** the resolved decision asks that, if two Scaled attempts are
only meaningfully comparable when their scaling context matches, enough
structured context exists to make that determination later.
`FunctionalFitnessPerformedMovement` (§6) already retains exactly this —
`performedExercise`/`performedReps`/`performedLoadKilograms`/etc. per
movement — so a future, finer-grained "these two Scaled attempts aren't
really comparable" rule could be built without any schema change. Stage
6B does not build that finer rule; `ScoringEngine`'s existing binary
Rx/Scaled `context` gate is confirmed sufficient for V1.

Cross-modality PR detection (§25) is uniform because `ScoringEngine` is
the single shared comparator everywhere:

| Modality | Comparable value | Direction |
|---|---|---|
| Strength | `SetResult.weight` within a `repBand` | `higherIsBetter` |
| For Time (incl. Rounds For Time/Chipper/Ladder) | elapsed seconds | `lowerIsBetter` |
| AMRAP / Max Reps | rounds+partial (proxy) / reps | `higherIsBetter` |
| Max Load | load kilograms | `higherIsBetter` |
| EMOM | completed intervals | `higherIsBetter` — informational only; EMOM is completion-based by nature and is not treated as a benchmark-style PR context unless a future benchmark explicitly defines one |

## 8. First-entry PR semantics (§25) — RESOLVED: data unchanged, presentation split

`ScoringEngine.isNewPersonalRecord` already returns `true` for the
**first-ever** result in a given (context, band) — `guard let existingBest
else { return true }` — this is existing, tested, locked engine
behavior and Stage 6 does not change it: a first-ever squat, a first-ever
Fran attempt, both correctly become a real `PersonalRecord` row on day
one. The resolved decision confirms the underlying data model stays
exactly as-is; only the completion screen's copy changes:

- The recording use case already computes `existingBest` before
  deciding; its return value now also reports whether `existingBest ==
  nil` (`isFirstEverEntry`, `WORKOUT_COMPLETION_PIPELINE.md` §2), so the
  completion screen (§4 of `WORKOUT_COMPLETION_PIPELINE.md`) labels a
  true first-ever entry neutrally ("First recorded: Fran — 4:58") and
  reserves "Personal record!" for an entry that actually beat a prior
  compatible best. The underlying `PersonalRecord`/`isPersonalRecord`
  data is identical in both cases — this is a presentation-only branch,
  not a scoring-architecture change, and the benchmark Rx/Scaled
  compatibility rule (§7) still governs what counts as "a prior
  compatible best" either way.

## Implementation status (Stage 6B)

`FunctionalFitnessExecutionView` covers every typed `WorkoutFormat` —
AMRAP (large countdown + large "+ROUND" tap target + end-of-time
remaining-reps entry, no live rep logging), EMOM (auto-advancing
current/next station via `WorkoutTimer.currentUnitIndex`, a true fit here
since every minute shares one duration), For Time/Chipper/Ladder (running
clock to an explicit Finish/time-cap), Rounds For Time (the same round
counter as AMRAP plus a running clock), Max Load/Max Reps (single-entry
forms, the latter behind its own countdown), and Intervals (reusing
`IntervalTimerResolution` unchanged). One real gap this doc's own scoring
model didn't fully specify: a live, *non-benchmark* result still needs a
`ScoreDirection` to construct its `FunctionalFitnessResult`, and no field
anywhere on `FunctionalFitnessPrescription` carries one (only
`BenchmarkDefinition` does). `FunctionalFitnessScoring.scoreDirection(for:)`
supplies it deterministically from the format's own definition (an AMRAP
is definitionally higher-is-better; a For Time is definitionally
lower-is-better) — `ScoreType` itself is never re-derived, always read
from `Stimulus.scoreType`.

**Known gap, not a defect:** tagging a generated result as an attempt at
a specific `BenchmarkDefinition` (so it can qualify for "First recorded"/
"New PR") has no UI yet — the Finish flow always logs with
`benchmark: nil`. Per this doc's own §14 ("generated workouts are never
automatically a tracked benchmark"), the safe default is simply no
benchmark/no PR-eligibility until that picker is built, not an incorrect
one.
