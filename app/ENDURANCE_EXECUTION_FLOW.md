# Endurance Execution Flow

Stage 6A: execution for `.steadyState` and `.intervals` `WorkoutBlock`s.
**Design pass — nothing here is implemented yet.**

**Status: RESOLVED.** §1/§2c reflect the resolved save-boundary
convention and the confirmed per-modality partial-result progression
behavior — see `STAGE6A_DECISION_MEMO.md` §1a/§1d.

## 1. Steady state (§14)

`SteadyStatePrescription` already carries everything the screen needs:
`activityType`, `durationSeconds`/`distanceMeters` (either or both),
`primaryIntensity`/`secondaryIntensity` (`IntensityTarget` — an HR zone,
pace, power, or RPE target, unit already discriminated by the type
itself).

```
Zone 2 Bike
45 min @ Zone 2 (130–142 bpm)

[  timer: elapsed, counts up toward 45:00  ]
[  Start / Pause  ]

Optional live entry, manual, no HealthKit required:
  Distance so far        (stepper or keypad)
  Current HR             (stepper or keypad, only if the user wants to log it)
```

**On completion** (Finish):

```
actualDurationSeconds   <- from the block's own TimerState (elapsedSeconds
                           at the moment Finish is tapped — never a
                           separately-typed value the user re-enters)
actualDistanceMeters?   <- optional manual entry
averageHeartRate?       <- optional manual entry
averagePower?           <- optional manual entry
averagePaceSecondsPerKilometer?  <- derived from duration+distance when both
                                     are present, never asked for directly
rpe?                    <- optional manual entry (1-10, plain stepper)
```

All optional except `actualDurationSeconds` — `SteadyStateResult`'s own
shape already enforces exactly this (`SteadyStateResult.swift`'s doc
comment: *"a treadmill run might have no distance sensor, a bike ride
might have no power meter — never require values a given activity/
equipment combination can't supply"*). **V1 works entirely without
HealthKit** — every field above is a manual stepper/keypad entry; a later
HealthKit integration only pre-fills these same fields, it never becomes
a precondition for finishing the block (§14/§29, restated from
`ARCHITECTURE.md`'s existing HealthKit-boundary rule).

Recorded via `LogEnduranceResultUseCase`, wrapping the new
`RecordSteadyStateResultUseCase` (§2 of `WORKOUT_COMPLETION_PIPELINE.md`
— the identified gap), mirroring `RecordSetResultUseCase`'s exact shape:
get-or-create the `ActivityPerformanceProfile` via
`PerformanceProfileStore.activityProfile`, attach the result, update
`lastPerformedAt`, run PR detection through `ScoringEngine` using the
phase/mix's own scoring direction for this activity (steady-state's
"better" is duration-at-a-held-intensity, per `Training OS.dc.html`'s
own workout-model table). `LogEnduranceResultUseCase` saves immediately
after recording — this result is durable the instant Finish is tapped
(resolved save-boundary convention, `WORKOUT_COMPLETION_PIPELINE.md` §1),
and the recording call also reports `isFirstEverEntry` for the resolved
PR-presentation split (§4 of `FUNCTIONAL_FITNESS_EXECUTION_FLOW.md`,
applied identically here).

**Partial steady-state completion and progression — resolved, no engine
change:** `SteadyStateProgressionEngine`'s `resolveDuration`/
`resolveDistance`/`resolveIntensity` do not consume actual results at
all — next week's prescribed values are already a pure function of
configured rules + week index (`WORKOUT_COMPLETION_PIPELINE.md` §5).
A steady-state block finished early (`completionContext = .partial`)
has no special progression consequence to add, because this engine's
contract never reads "how much happened" for *any* session, full or
partial.

## 2. Interval execution (§16-18)

`IntervalPrescription` already models a repeated work/recovery structure,
each leg duration- **or** distance-based independently
(`workDurationSeconds`/`workDistanceMeters`, never both required):

```
5 × 4 min @ Threshold, 2 min recovery

Interval 3 of 5
WORK    3:42 remaining          (or, distance-based: "1 km to go")
Target: Threshold (pace/HR band from IntensityTarget)
Next:   Recovery · 2:00
```

### 2a. Time-based intervals (§17) — timer-driven, minimal taps

When both work and recovery legs carry a duration, the block's
`TimerState` automatically transitions Work → Recovery → Work
(`TIMER_ARCHITECTURE.md` §7 — a fresh `TimerState` per leg, `currentUnitIndex`
advancing each transition) with no tap required at a transition the
timer can handle on its own, per the kickoff's explicit instruction.
Controls: **pause**, **skip interval** (advances `currentUnitIndex`
without recording a completed rep for the skipped one), **mark
incomplete** (records an `IntervalRepResult` with
`wasCompletedAsPrescribed = false`, never silently dropped).

### 2b. Distance-based intervals (§18) — manual completion, no GPS assumed

When a leg is distance-based (`workDistanceMeters` set, no
`workDurationSeconds`), there is no running clock for that leg in V1 —
the user marks it complete manually:

```
1 km — Work
[  Mark complete  ]
  → optional: enter actual time/pace for this rep
  → recovery timer starts (recovery, if duration-based, still ticks
    automatically per §2a)
```

This is exactly `TIMER_ARCHITECTURE.md` §7's "no running clock during
the work portion" row — a deliberate V1 boundary, never blocked on
HealthKit/GPS distance detection (§18/§29). A later integration
automating distance detection only changes *how* "mark complete" gets
triggered; it does not change the result shape below.

### 2c. Per-interval result storage — never collapsed

Each completed (or marked-incomplete) rep becomes its own
`IntervalRepResult`, attached via `IntervalResult.addRepResult` — **never
averaged into one overall number**, per `IntervalResult.swift`'s own doc
comment ("the engine should be able to inspect individual intervals
later") and the kickoff's explicit instruction. Session-level summary
fields (`sessionDurationSeconds`, `averagePaceSecondsPerKilometer`, etc.)
are computed once at Finish, from the per-rep rows, and stored alongside
them — both, not one instead of the other. Recorded via
`LogEnduranceResultUseCase` (wrapping `RecordIntervalResultUseCase`),
saving immediately, identically to §1's steady-state path.

**Partial interval completion and progression — resolved, already
mechanically supported, no engine change:**
`IntervalProgressionEngine.evaluateSessionOutcome(completedCount:totalCount:worstRpe:)`
is already a graduated, deterministic, completion-fraction-based outcome
mapper — `.progress`/`.hold`/`.repeatSession`/`.reduceIntensity`/
`.reduceIntervalCount`, with `totalCount == 0` (nothing attempted at
all) already yielding `.calibrationRequired` rather than inventing a
fraction from no data. Execution's job is only to supply
`completedCount`/`totalCount`/`worstRpe` accurately from the block's own
`IntervalRepResult` rows — **the exact meaning of `totalCount`
(prescribed interval count vs. attempted-this-session count) should be
confirmed against `evaluateSessionOutcome`'s call sites during Stage 6B
implementation** (non-blocking build-time verification,
`STAGE6A_DECISION_MEMO.md` §5) so a partial session genuinely produces a
conservative outcome and not an inflated one from comparing only
against what was attempted. No new engine logic, no new reason code, no
execution-layer progression decision either way.

## 3. Endurance substitution (§15, Stage 4C reused exactly)

From the activity name: **"Substitute"** → candidates limited to
`template.allowedActivityTypes` (`SubstituteActivityUseCase.isValid`) —
e.g. a generic aerobic prescription might allow
`[.cycling, .rowing, .skiErg]`; a running-specific one allows only
`[.running]` and rejects everything else.

- **Today only** →
  `SubstituteActivityUseCase.substituteThisSessionOnly` (steady-state or
  interval overload) — edits the materialized prescription's
  `activityType` directly, and **translates** (never blindly carries
  over) any physiological intensity target via `IntensityTranslation`;
  a target already expressed as physiology (HR zone, RPE, %) survives
  the switch unchanged, while a modality-specific numeric target (a
  bike-specific power band, a running-specific pace) is never silently
  reinterpreted as the same raw number on the new modality — per the
  kickoff's explicit instruction, **no numeric power/pace target is
  translated across modalities except through this existing,
  already-built `IntensityTranslation` rule**; where no translation rule
  exists for a given pair, the target is dropped to `nil` rather than
  guessed (verify exact `IntensityTranslation` coverage during Stage 6B
  implementation — flagged in the decision memo if a gap is found).
- **Going forward** → `SubstituteActivityUseCase.substituteGoingForward`
  — writes/updates an `ActivitySelectionOverride` on the
  `ProgramInstance`, read by future materialization via
  `SubstituteActivityUseCase.resolvedActivityType`; historical Sessions
  and `ProgramDefinition` untouched, identical guarantee to the strength
  side.

Both scopes are invoked through `ApplySubstitutionUseCase`
(`WORKOUT_COMPLETION_PIPELINE.md` §1), saving immediately — identical
convention to the strength side (`STRENGTH_EXECUTION_FLOW.md` §7).

## 4. What endurance execution does not do

- Does not require HealthKit for any part of starting, running, or
  finishing a block (§14/§29).
- Does not invent a live pace/HR autoregulation rule mid-block — any
  "hold this effort" guidance shown is the already-resolved
  `IntensityTarget`, never recomputed from live sensor data this stage
  has no contract for.
- Does not translate a numeric target across modalities without an
  existing `IntensityTranslation` rule (§3).
