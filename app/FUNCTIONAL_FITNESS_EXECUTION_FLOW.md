# Functional Fitness Execution Flow

Stage 6A: execution for `.functionalFitness` `WorkoutBlock`s — every
`WorkoutFormat` case, scaling, and benchmark completion/PR detection.
**Design pass — nothing here is implemented yet.**

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
  condition in the design source).
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
  movement) rather than a flat index array — see decision memo §6 for
  the exact field shape to add if the existing `FunctionalFitnessPerformedMovement`
  fields prove insufficient for "which minutes were incomplete."
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
  fact — see decision memo §4 for the exact field: today's
  `FunctionalFitnessResult` has no dedicated `cappedAt` field the way
  legacy `WorkoutResult.cappedAtSeconds` does; this is a genuine schema
  gap to resolve before Stage 6B, not something to paper over with a
  string).
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
auto-apply a scaling choice) — flagged in the decision memo §8 if a
"remember my usual scaling for this movement" affordance is wanted this
stage; the recommendation is to defer it, since the exposure-history
mechanism already gives the planner what it needs without a new
override entity.

## 7. Benchmark completion and PR detection (§24-25)

A `.functionalFitness` block whose `FunctionalFitnessResult.benchmark`
is set (a `BenchmarkDefinition`, e.g. "Fran") is recorded through
`RecordFunctionalFitnessResultUseCase.recordResult(_:for:benchmark:performanceProfile:modelContext:)`
(existing, unchanged) — the **sole** path a Functional Fitness result
becomes a `PersonalRecord`:

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

Cross-modality PR detection (§25) is uniform because `ScoringEngine` is
the single shared comparator everywhere:

| Modality | Comparable value | Direction |
|---|---|---|
| Strength | `SetResult.weight` within a `repBand` | `higherIsBetter` |
| For Time (incl. Rounds For Time/Chipper/Ladder) | elapsed seconds | `lowerIsBetter` |
| AMRAP / Max Reps | rounds+partial (proxy) / reps | `higherIsBetter` |
| Max Load | load kilograms | `higherIsBetter` |
| EMOM | completed intervals | `higherIsBetter` (informational — EMOM is completion-based by nature; whether it should ever produce a PR at all is a decision-memo item, §9) |

## 8. First-entry PR semantics (§25) — data vs. presentation

`ScoringEngine.isNewPersonalRecord` already returns `true` for the
**first-ever** result in a given (context, band) — `guard let existingBest
else { return true }` — this is existing, tested, locked engine
behavior and Stage 6 does not change it: a first-ever squat, a first-ever
Fran attempt, both correctly become a real `PersonalRecord` row on day
one. What the kickoff's "do not over-celebrate arbitrary first entries"
(§25) actually asks for is a **presentation** distinction, not a data
one:

- The recording use case already computes `existingBest` before
  deciding; Stage 6B should have it (or the completion pipeline calling
  it) return whether `existingBest == nil` alongside the result, so the
  completion screen (`WORKOUT_COMPLETION_PIPELINE.md` §4) can label a
  true first-ever entry neutrally ("First recorded: Fran — 4:58") rather
  than celebratory ("Personal record!") — while the underlying
  `PersonalRecord`/`isPersonalRecord` data is identical either way.
  Flagged as a decision-memo item (§9) since it changes a use case's
  return shape, however slightly.
