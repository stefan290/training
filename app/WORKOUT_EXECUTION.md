# Workout Execution

Stage 6A: the execution architecture that turns a materialized `Session`
into logged, permanent results — Today → Session → ordered `WorkoutBlock`s
→ per-block logging → Session completion. **Design pass — nothing here is
implemented yet.**

**Status: RESOLVED.** §5 reflects the final, resolved save-boundary
convention — see `STAGE6A_DECISION_MEMO.md` §1d. See
`SESSION_STATE_MACHINE.md`/`TIMER_ARCHITECTURE.md`/`STRENGTH_EXECUTION_FLOW.md`/
`ENDURANCE_EXECUTION_FLOW.md`/`FUNCTIONAL_FITNESS_EXECUTION_FLOW.md`/
`WORKOUT_COMPLETION_PIPELINE.md` for the detail one level down.

## 1. The execution model is already fully typed — this stage consumes it, it does not invent a new one

Every system this stage needs already exists as real, tested,
persisted domain types (`ARCHITECTURE.md`, `PRESCRIPTION_RESULT_MODEL_REVIEW.md`):

```
Session { blocks: [WorkoutBlock] }                 (Domain/Entities/Session.swift)
WorkoutBlock { type, status, ... }                 (Domain/Entities/WorkoutBlock.swift)
  .blockPrescription -> BlockPrescription           (Domain/ValueTypes/BlockPrescription.swift)
      .exercise([ExercisePrescription])              — strength/hypertrophy/accessory
      .steadyState(SteadyStatePrescription)           — steady state
      .intervals(IntervalPrescription)                — intervals
      .functionalFitness(FunctionalFitnessPrescription) — AMRAP/EMOM/For Time/Rounds For
                                                          Time/Chipper/Ladder/Max Load/
                                                          Max Reps/Intervals (WorkoutFormat)
  .blockResult -> BlockResult                        (Domain/ValueTypes/BlockResult.swift)
      .strength(StrengthBlockResult)                  — wraps SetResult[]
      .steadyState(SteadyStateResult)
      .intervals(IntervalResult)                      — + IntervalRepResult[] per rep
      .functionalFitness(FunctionalFitnessResult)      — + FunctionalFitnessPerformedMovement[]
```

`BlockPrescription`/`BlockResult` are **never persisted directly** — they
are computed views `WorkoutBlock` synthesizes from whichever typed,
persisted relationship is populated (`WorkoutBlock.swift`'s own doc
comment). Stage 6's execution layer reads/writes through the typed
relationships (`ExercisePrescription`/`SteadyStatePrescription`/
`IntervalPrescription`/`FunctionalFitnessPrescription` and their result
siblings) exactly as every existing generator/materializer already does
— **it never introduces a modality-specific `Session` subclass**, per the
kickoff's explicit instruction, because `WorkoutBlockType` (the `type`
field) already is the one thing execution branches on, exactly as
`ConcurrentScheduler`/every `ProgrammingSystem` already branches on it
(CLAUDE.md rule 7).

**One real gap found during this pass:** `SteadyStateResult`/
`IntervalResult` have no `RecordSteadyStateResultUseCase`/
`RecordIntervalResultUseCase` yet — only `RecordSetResultUseCase`
(strength) and `RecordFunctionalFitnessResultUseCase` exist. Test-only
code (`ModalityPersistenceRoundTripTests`, etc.) attaches these results
directly via `WorkoutBlock.attachSteadyStateResult`/
`.attachIntervalResult` without folding them into
`ActivityPerformanceProfile`/PR detection. Stage 6B must build these two
use cases, mirroring `RecordSetResultUseCase`'s exact shape — see
`WORKOUT_COMPLETION_PIPELINE.md` §2.

## 2. Today — the daily entry surface

Today (`UI/Today/`, currently a plain list — `TodayViewModel` only loads
the day's Sessions) is where every execution flow begins and ends. Per
the kickoff's screen requirements and the design source
(`Training OS.dc.html` frames 01/06):

- **One Session today:** shown prominently — name, phase/mix context
  chip, duration/block-count/working-set summary, ordered block preview,
  a single "Start session" action.
- **Multiple Sessions today** (e.g. `07:00 Strength` / `18:30 Zone 2`):
  time-grouped, the next-up Session expanded with its full block list,
  later Sessions collapsed to a summary row — "hierarchy only when
  earned" (design source's own framing for frame 06), never a dashboard
  with every Session equally weighted.
- Each Session row/expansion exposes exactly the fields the kickoff
  names: `role` (`SessionRole`, or the coarse `modality` tag where no
  role is set), an estimated duration, its main purpose (the primary
  block's label, or the phase/mix chip), its ordered `WorkoutBlock`s,
  current `status`, and a start/resume action whose label reflects state
  (`"Start session"` when `.scheduled`, `"Resume session"` when
  `.inProgress`).
- Finishing the morning Session never marks the whole Day complete — the
  ViewModel re-reads the Day's Sessions and the evening Session simply
  becomes "up next" (§32; already true by construction, since Today's
  model is `Day.orderedSessions`, not a single flag).

Today's ViewModel-layer responsibility (new in Stage 6, replacing the
current bare `load`) is to also expose, per Session: whether it's the
"up next" one, its computed duration/block/working-set summary (derived
from its blocks, never stored redundantly), and — only if a `.scheduled`
Session's date has passed — the missed/reflow affordance
(`SESSION_STATE_MACHINE.md` §7). None of this requires new persisted
Today-specific state; it is all read from `Session`/`WorkoutBlock`/
`TrainingPhase`.

## 3. A Session executes its blocks in order — heterogeneous by default

`Session.orderedBlocks` is the single source of truth for execution
order (never raw collection order — already enforced by
`Session.addBlock`/`.orderedBlocks`). Execution always presents blocks
**one active block at a time**, in that order:

```
Warm-up (.warmup) → Strength (.strength/.hypertrophy/.accessory)
                  → Metcon (.functionalFitness)
Warm-up            → Intervals (.intervals) → Cool-down (.cooldown)
```

The user completes (or skips) the active block before the next one
becomes `.active` — never two blocks active simultaneously, never a
single logging UI flattened across modalities. Each `WorkoutBlockType`
gets its own execution screen shape (§5 below); a mixed Strength→Metcon
Session is simply two blocks, each rendered by its own screen, back to
back — `WorkoutBlock.type` is what a `WorkoutBlockExecutionView`
(illustrative name) switches on to decide which concrete execution view
to show, exactly mirroring how `ConcurrentScheduler` switches on
`WorkoutBlockType`/`ProgrammingSystemKind` and never on a session-level
flag.

**Multiple Sessions on one Day** are already fully independent
`Session` rows (Day → zero or more Sessions, CLAUDE.md rule 8/`ARCHITECTURE.md`)
— nothing new is needed to execute a morning Strength Session and an
evening Zone 2 Session as two entirely separate flows; Today (§2) is the
only place that needs to reason about "more than one Session exists,"
execution itself never does.

## 4. Data ownership — never blurred in execution code

Restated exactly for the execution layer, since this is precisely where
the six concepts are most tempting to conflate under time pressure:

| Concept | Owns | Execution code may |
|---|---|---|
| `ProgramDefinition` | Methodology (template graph) | Read it transitively via `ProgramInstance`, never write to it, never read it directly for a number to show — it holds no performance data by construction (CLAUDE.md rule 2) |
| `ProgramInstance` | This user's active execution context (dates, substitution overrides, progress state) | Read `TrainingMixComponent`/slot overrides through it (`SubstituteExerciseUseCase.resolvedExercise`) |
| Materialized `Session`/`WorkoutBlock`/`*Prescription` | A historical, already-resolved prescription snapshot, plus its own execution bookkeeping (`status`, `completionContext`, `timerState` — all new, additive fields owned by execution itself, `SESSION_STATE_MACHINE.md`/`TIMER_ARCHITECTURE.md`) | Read the target values; **never mutate a prescription's target fields to reflect what happened** — a substitution's THIS-SESSION-ONLY scope edits `ExercisePrescription.exercise` (an intentional, existing exception, §10), but `SetPrescription.repRangeLow/High`/`targetRir`/`targetWeight` are never rewritten by execution code once materialized |
| `Recommendation` | A cached, reason-coded engine output tied to one `ExercisePrescription` | Create one when a suggested load is shown (so the Why sheet never re-runs the engine); never fabricate a `Recommendation` without a `reasonCode` (`Recommendation.swift`'s own doc comment: *"there is deliberately no way to construct one without it"*) |
| `SetResult`/`SteadyStateResult`/`IntervalResult`/`FunctionalFitnessResult` | The actual, permanent performance fact | The only things execution code creates as "what happened" — always via the recording use case (`WORKOUT_COMPLETION_PIPELINE.md` §2), never constructed and left unattached |
| `PerformanceProfile` (+ its 3 sub-profiles) | Permanent, program-independent history | Read for suggested-load/history display; written to exclusively through the recording use cases, never directly by a View or ViewModel |

## 5. SwiftUI architecture — Views render state, they do not decide it

Continuing this codebase's existing `Application/ViewModels`/
`Application/UseCases` separation (CLAUDE.md rule 5), execution adds
**two layers** of use case, per the resolved save-boundary convention
(`STAGE6A_DECISION_MEMO.md` §1d):

- **Low-level recording use cases** (`Application/UseCases/`) — pure
  mutation, no `save()`, reused beyond live execution (seed data,
  tests): the existing `RecordSetResultUseCase`/
  `RecordFunctionalFitnessResultUseCase`, plus the two new ones this
  stage identifies, `RecordSteadyStateResultUseCase`/
  `RecordIntervalResultUseCase` (`WORKOUT_COMPLETION_PIPELINE.md` §2).
- **Orchestrating use cases** — one per meaningful user action, each
  wrapping exactly one low-level call and immediately saving:
  `StartSessionUseCase`, `LogSetUseCase`, `LogEnduranceResultUseCase`,
  `LogFunctionalFitnessResultUseCase`, `ApplySubstitutionUseCase`
  (wraps `SubstituteExerciseUseCase`/`SubstituteActivityUseCase`),
  `CompleteBlockUseCase`, `ChangeSessionStatusUseCase`,
  `CompleteSessionUseCase` (`WORKOUT_COMPLETION_PIPELINE.md` §1).
  Every one is a plain function/enum, `ModelContext`-taking, no SwiftUI
  import — directly unit-testable exactly like every existing use case
  in this codebase.
- **ViewModels** (`Application/ViewModels/`): one per screen family
  (`SessionExecutionViewModel`, `StrengthBlockViewModel`,
  `FunctionalFitnessBlockViewModel`, …), `@Observable`, holding only
  *presentation* state (which set is "logging," which RIR chip is
  highlighted, the live timer read) — every state-changing action calls
  an **orchestrating** use case, never a low-level recording use case
  directly, and never mutates a `@Model` object's business fields inline
  in a View's button handler. ViewModels never call `context.save()`
  themselves — that's the orchestrating use case's own job, once per
  action, not the ViewModel's.
- **Views**: render ViewModel output only. A timer's displayed value is
  computed from `TimerState` at render time (`TIMER_ARCHITECTURE.md` §2)
  — a View may recompute it every redraw, but it never owns or mutates
  the underlying state.

## 6. Offline-first — restated for execution specifically

Nothing in §1-5 above ever requires a network call: materialized
Sessions/blocks/prescriptions are already local (produced ahead of time
by the existing generators/materializers), suggested-load computation
reads only local `PerformanceProfile` data through the existing,
already-local `ProgressionEngine`/`DoubleProgressionEngine`/
`StrengthProgressionEngine`, and every write (`SetResult`, block/session
status, `PersonalRecord`) is a local SwiftData insert. HealthKit (write
of a completed workout, read of body metrics) is strictly additive and
never gates any of the above — see §14/§15's own "V1 must work without
HealthKit" instruction, expanded in `ENDURANCE_EXECUTION_FLOW.md`.
