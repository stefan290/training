# Modality Architecture Validation

Stage 3B main analysis. This document answers the two governing questions
from the brief directly, ties together the five companion documents
(`ENDURANCE_PROGRAMMING_MODEL.md`, `FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md`,
`CONCURRENT_SCHEDULER_MODEL.md`, `PRESCRIPTION_RESULT_MODEL_REVIEW.md`,
`PERFORMANCE_PROFILE_MODALITY_REVIEW.md`), and provides the required
architectural proof table and smell checklist. Source grounding for every
external claim is `PROGRAMMING_SOURCES.md`; this document does not repeat
that classification, it only builds on it.

**Governing questions:**
1. Can the current `ProgrammingSystem` / `ProgramDefinition` / `Session` /
   `WorkoutBlock` / Prescription architecture cleanly represent Aerobic
   Base, Running, VO2/Intervals, Functional Fitness, and Concurrent
   scheduling, without strength-specific assumptions?
2. If not, what changes are needed before Stage 4?

## 1. Modalities validated

| # | Modality | Validated in |
|---|---|---|
| 1 | Aerobic Base / steady-state endurance | `ENDURANCE_PROGRAMMING_MODEL.md` §2, §5 |
| 2 | Beginner running / run-walk progression | `ENDURANCE_PROGRAMMING_MODEL.md` §7 |
| 3 | Developed running, multiple session roles | `ENDURANCE_PROGRAMMING_MODEL.md` §8–10 |
| 4 | VO2max / interval programming | `ENDURANCE_PROGRAMMING_MODEL.md` §3, §4 |
| 5 | Functional Fitness / CrossFit-style | `FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md` |
| 6 | Concurrent / hybrid scheduling | `CONCURRENT_SCHEDULER_MODEL.md` |

## 2. `ProgrammingSystem` protocol stress test — the answer

Per Stage 3B §32, not forced either direction: **the existing single
`ProgrammingSystem` protocol survives unchanged. The set of concrete
implementations is smaller than the brief's own illustrative list.**

| Brief's illustrative system | Survives as its own implementation? |
|---|---|
| `HypertrophyProgrammingSystem` | Yes — unchanged |
| `PowerliftingProgrammingSystem` | Yes — unchanged |
| `AerobicBaseProgrammingSystem` | **No** — subsumed into `SteadyStateProgrammingSystem`, generic across modality (`ENDURANCE_PROGRAMMING_MODEL.md` §2) |
| `RunningProgrammingSystem` | **Validated as a thin composer**, not an independent rule engine — orchestrates `SteadyStateProgrammingSystem`/`IntervalProgrammingSystem` output under a running-specific methodology (`ENDURANCE_PROGRAMMING_MODEL.md` §9) |
| `IntervalProgrammingSystem` | Yes — and generalized further than the brief's own framing: also subsumes the hypothesized `VO2ProgrammingSystem` as a named parameter preset, not a class (`ENDURANCE_PROGRAMMING_MODEL.md` §3) |
| `FunctionalFitnessProgrammingSystem` | Yes — a genuinely distinct authoring pipeline (stimulus-first, five stages), correctly kept separate (`FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md` §1) |

**Net result: 5 concrete systems, not the brief's illustrative 6+,** and
of those 5, two (`HypertrophyProgrammingSystem`, `PowerliftingProgrammingSystem`)
were already validated in Stage 3A. This is a genuine "smaller set of
more generic systems" outcome (the brief's second option), reached by
evidence — the deciding evidence being §4 of `ENDURANCE_PROGRAMMING_MODEL.md`
(the three-modality 4×4 side-by-side table), not a preference stated in
advance.

**Why `FunctionalFitnessProgrammingSystem` doesn't collapse into the
generic interval/steady-state systems the way Running did:** Running's
sessions are *individually* either continuous effort or discrete
work/recovery structure — exactly what `SteadyStateProgrammingSystem`/
`IntervalProgrammingSystem` already model. A Functional Fitness workout's
authoring process (stimulus → format → movement slots → exercises →
validation) has no analog in either generic system — `format` (AMRAP/
EMOM/For Time/etc.) is a structurally different kind of thing than
"duration + intensity target" or "work/recovery legs," and the
prescribed *content* (multiple distinct movements combined, per §1 of
`FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md`) has no equivalent in a single-
modality steady-state or interval session. This isn't a missed
generalization — it's a genuinely different mechanic, correctly kept
separate.

## 3. `ProgramJourney` — one real generalization surfaces

Per Stage 3B §38, validating `ProgramJourney` against Running and Hybrid
journey examples: Running's journey (`ENDURANCE_PROGRAMMING_MODEL.md`
§10) fits the existing shape from `PROGRAMMING_SYSTEM_MODEL.md` §5.1
with zero changes. The Hybrid journey example does not:

> Hybrid Journey: Muscle Gain → Hybrid Transition → Fat Loss + Functional
> Fitness

"Hybrid Transition" and "Fat Loss + Functional Fitness" are not single-
system phases — they're each a *concurrent combination* of multiple
`ProgramDefinition`s (exactly the kind of thing `ConcurrentScheduler`
operates over, per `CONCURRENT_SCHEDULER_MODEL.md`), not one
`ProgrammingSystem`'s output. `ProgramJourney.phases: [ProgramDefinition]`
as currently typed cannot express this — it assumes every phase is
exactly one system's output.

**Required generalization (small, additive):**

```
enum PhaseContent {
    case single(ProgramDefinition)
    case concurrent([ScheduledProgramInput])   // ScheduledProgramInput from
                                                 // CONCURRENT_SCHEDULER_MODEL.md §1
}

struct ProgramJourney {
    let name: String
    let phases: [PhaseContent]                  // was [ProgramDefinition]
    let transitionTrigger: TransitionTrigger
}
```

This is a type change to a field's element type, not a new top-level
entity, and not a change to any already-shipped phase (every existing
Family A/Running journey phase is trivially `.single(...)`). Flagged in
`STAGE3B_ARCHITECTURE_DECISIONS.md` as a required pre-Stage-4 change,
because it affects the `ProgramJourney` type itself, which Stage 4 will
otherwise build against the narrower, now-known-insufficient shape.

## 4. Long-Term Planner terminology check

Per Stage 3B §39: Goal → TrainingPhase → ProgrammingSystem →
ProgramDefinition/ProgramJourney → Modules → ConcurrentScheduler.

**Holds, with one term clarified rather than changed.** "Module" already
exists informally in the Stage 1 handoff and `PROGRAM_GENERATOR_SPEC.md`
§5 (a secondary program-like unit running alongside a primary program —
e.g. Stage 3B's own Hybrid proof case A, "Secondary: Aerobic Base Module:
2×45min Zone 2"). This validation confirms `Module` is exactly
`ScheduledProgramInput` (`CONCURRENT_SCHEDULER_MODEL.md` §1) tagged
`GoalPriority.secondary` — not a new entity, a naming clarification: a
"Module" is what a secondary-priority `ScheduledProgramInput` is called
in product/UI language. No pipeline term needs to change; "Modules"
correctly describes the `ConcurrentScheduler`'s secondary inputs, and
`ConcurrentScheduler` correctly sits exactly where the brief places it —
after `ProgramDefinition`/`ProgramJourney` production, before
Day/Session materialization.

## 5. Progression architecture — what's actually reusable

Per Stage 3B §35: the existing `ProgressionEngine` protocol
(`func recommend(_ input: ProgressionInput) -> ProgressionOutput`, Stage
1) already has the right *shape* — current prescription + relevant
history + rule state → next prescription + reason code. What needs
generalizing is the *payload*, not the protocol:

```
struct ProgressionInput {
    let currentPrescription: BlockPrescription   // was strength-shaped fields directly;
                                                   // now the enum from
                                                   // PRESCRIPTION_RESULT_MODEL_REVIEW.md §2
    let relevantHistory: [BlockResult]            // was [SetOutcome]; now the enum from
                                                   // PRESCRIPTION_RESULT_MODEL_REVIEW.md §3
    let ruleState: ProgressionRuleState           // per-ProgrammingSystem rule parameters —
                                                   // unchanged concept, e.g. autoregulation
                                                   // baseline, interval progression priority
}

struct ProgressionOutput {
    let nextPrescription: BlockPrescription
    let reasonCode: ProgressionReasonCode          // unchanged, open enum
    let confidence: Double
    let inputsSummary: String
}
```

**Confirmed reusable across every modality: the interface.** **Not fully
reusable: the implementation.** Hypertrophy's evaluator reasons about
load/reps/sets/RIR; Running's about duration/distance/pace/interval
structure; VO2's about interval count/duration/recovery/intensity — each
needs its own `ProgressionEngine` conformer reading its own
`BlockPrescription` case, exactly as `DoubleProgressionEngine` today only
handles strength. **Functional Fitness is the one case where even the
interface strains:** "progress capacity without repeating identical
workouts" doesn't cleanly produce a "next prescription" from "current
prescription + history" the way a numeric progression does — the *next*
Functional Fitness workout is typically not a parametric adjustment of
the *current* one, it's closer to "generate a new workout, informed by
exposure history" (`FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md` §7). The
interface still technically fits (`ProgressionInput`/`ProgressionOutput`
are generic enough to receive the right *types*), but calling this
"progression" in the same sense as Hypertrophy's is a stretch worth
naming honestly rather than papering over: Functional Fitness's use of
this interface is really "exposure-informed generation wearing the
progression interface's clothes," not incremental parameter adjustment.
This is a genuine finding, not a defect — it just means Stage 4 shouldn't
expect a `FunctionalFitnessProgressionEngine` to feel like
`DoubleProgressionEngine`, even though both satisfy the same protocol.

## 6. Architectural proof table

Per Stage 3B §42, the 11 required scenarios:

| # | Scenario | ProgrammingSystem | Session structure | WorkoutBlock type(s) | Prescription type | Result type | Progression dimensions | PerformanceProfile destination |
|---|---|---|---|---|---|---|---|---|
| 1 | Bench Press 3×8–12 @ 2 RIR | Hypertrophy | 1 block | `.strength` | `.strength(ExercisePrescription)` | `.strength([SetResult])` | load/reps/RIR (existing) | `ExercisePerformanceProfile` |
| 2 | Zone 2 Bike 45 min | SteadyState | 1 block | `.steadyState` | `.steadyState(SteadyStatePrescription)` | `.steadyState(SteadyStateResult)` | `progressDuration`/`progressIntensity` | `ActivityPerformanceProfile` (cycling) |
| 3 | Beginner Run/Walk session | Interval | 3 blocks (warm-up, interval, cool-down) | `.warmUp`, `.interval`, `.coolDown` | `.steadyState` (warm-up/cool-down) + `.interval` (main) | `.steadyState` + `.interval` | `increaseIntervalDuration`/`decreaseRecoveryDuration` (recovery = walking) | `ActivityPerformanceProfile` (running) |
| 4 | 5×1 km running intervals | Interval | 1 block | `.interval` | `.interval(IntervalPrescription)` | `.interval(IntervalResult)` | `increaseTargetIntensity`/`increaseIntervalCount` | `ActivityPerformanceProfile` (running) |
| 5 | 4×4 VO2 intervals | Interval (Helgerud preset) | 1 block | `.interval` | `.interval(IntervalPrescription)` | `.interval(IntervalResult)` | `.none` (fixed protocol, per source) | `ActivityPerformanceProfile` (running/cycling/rowing, per modality) |
| 6 | AMRAP | FunctionalFitness | 1 block | `.functionalFitness` | `.functionalFitness(FunctionalFitnessPrescription)` | `.functionalFitness(FunctionalFitnessResult)` | exposure-informed generation, not parametric (§5 above) | `ExercisePerformanceProfile` (per movement) + `BenchmarkPerformanceProfile` if it's a named benchmark |
| 7 | EMOM | FunctionalFitness | 1 block | `.functionalFitness` | `.functionalFitness(FunctionalFitnessPrescription)`, `minuteSlot`-tagged movements | `.functionalFitness(FunctionalFitnessResult)` | same as #6 | same as #6 |
| 8 | For Time benchmark (Fran) | FunctionalFitness | 1 block | `.functionalFitness` | `.functionalFitness(...)` with `.benchmark` set | `.functionalFitness(...)` with `.benchmark` set | same as #6, plus longitudinal comparison via `BenchmarkPerformanceProfile` | `BenchmarkPerformanceProfile` ("Fran") |
| 9 | Strength + Metcon Session | Hypertrophy/Powerlifting **and** FunctionalFitness, same `Session` | 2 blocks | `.strength`, `.functionalFitness` | one prescription per block, independently typed | one result per block, independently typed | independent per block — no cross-block progression coupling | `ExercisePerformanceProfile` (Block 1) + `ExercisePerformanceProfile`/`BenchmarkPerformanceProfile` (Block 2) |
| 10 | 5-Day Hypertrophy + 2 Zone 2 concurrent week | Hypertrophy + SteadyState, composed by `ConcurrentScheduler` | 7 `Session`s across the week | `.strength` (×5), `.steadyState` (×2) | per-session, per §1/§2 above | per-session, per §1/§2 above | independent per system; `ConcurrentScheduler` adds no progression, only placement | `ExercisePerformanceProfile` + `ActivityPerformanceProfile`, both accumulating independently |
| 11 | 4-run + 2-strength running-priority week | Running (Interval/SteadyState composer) + Hypertrophy/Powerlifting, composed by `ConcurrentScheduler`, `GoalPriority.primary` = running | 6 `Session`s | `.interval`/`.steadyState` (×4), `.strength` (×2) | per-session | per-session | independent per system; scheduler reason codes trace *placement* priority, not progression priority | `ActivityPerformanceProfile` (running, primary) + `ExercisePerformanceProfile` (strength, secondary) |

No row required a strength-specific field to be populated with a dummy
value, a new `WorkoutBlockType`-adjacent special case in `Session` itself,
or a new `ProgramDefinition` subclass — every "new" type introduced
across all 11 rows is a sibling value type (`BlockPrescription`/
`BlockResult` case, or a new `PerformanceMetricProfile` conformer), not a
change to `Session`, `WorkoutBlock`, `ProgramDefinition`, or
`ProgramInstance`'s own shape (`ProgramJourney`'s one required change is
in §3 above, and is likewise additive).

## 7. Architecture smells — explicit pass/fail

Per Stage 3B §43, checked against every scenario in §6 and every
companion document:

| Smell | Found? | Where checked |
|---|---|---|
| Irrelevant strength fields populated with dummy values | **No** | §1 of this doc; the whole point of `BlockPrescription` (`PRESCRIPTION_RESULT_MODEL_REVIEW.md` §2) is that a `.steadyState` block never touches `ExercisePrescription` at all |
| Excessive nullable properties | **No** | Same — enum-of-typed-cases chosen specifically to avoid this (`PRESCRIPTION_RESULT_MODEL_REVIEW.md` §2, §4) |
| Parsing human text to execute rules | **No** | Every prescription/result field across all 6 modalities is a typed value (`Duration`, `Pace`, `ScoreValue`, etc.), never a string parsed at runtime. (Stage 3A's own deload-text-instruction problem was a *source* artifact, not something this architecture reproduces for new modalities.) |
| Workout-format-specific hacks in `Session` | **No** | `Session`/`WorkoutBlock` are untouched by any modality-specific concept; format lives entirely inside `FunctionalFitnessPrescription.format` (§2 of `FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md`) |
| Special-case `ProgramDefinition` subclasses | **No** | Zero subclasses introduced anywhere in this document set; every new system produces the same `ProgramDefinition` shape from `PROGRAMMING_SYSTEM_MODEL.md` |
| Scoring direction inferred from names | **No** | `FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md` §4 — `ScoreDefinition.direction` is always set explicitly, by design, with no implicit default even for "obvious" cases |
| Deleting/replacing Prescription to represent scaling | **No** | `FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md` §6 — `prescribedExercise` is never overwritten; `performedExercise` is a separate, optional field |
| Duplicated engines just because modality changes | **Partially avoided, one clean exception** | Running/Bike/Row/VO2 share `SteadyStateProgrammingSystem`/`IntervalProgrammingSystem` (§2 above) — zero duplication. Functional Fitness is a genuinely separate engine, but for a substantiated reason (§2 above), not modality-change alone. |
| `PerformanceProfile` losing history across program changes | **No** | `PERFORMANCE_PROFILE_MODALITY_REVIEW.md` §5 — new profile types have the identical permanent, program-independent contract as the existing one |

**Zero unresolved smells.** The one item flagged as "partially avoided"
is explained, not excused — Functional Fitness's separateness is a
substantiated architectural conclusion (§2 above), the specific thing
this smell-check exists to distinguish from lazy duplication.

## 8. Confirming no over-generalization (§44)

Every new type introduced across the companion documents is a concrete,
strongly-typed struct/enum with named fields — `SteadyStatePrescription`,
`IntervalLegSpec`, `Stimulus`, `ScoreValue`, `ActivityPerformanceProfile`,
etc. **Zero** `[String: Any]`, zero JSON-blob fields, zero "generic
metric" catch-alls anywhere in this document set. Where a genuinely
generic *interface* was introduced (`PerformanceMetricProfile`,
`ProgrammingSystem` itself), it's a thin protocol with an associated type
or concrete conformers doing the real work — never a runtime-typed
container standing in for real types.

## 9. Summary — what changes, what stays

**Stays completely unchanged:** `ProgrammingSystem` protocol,
`ProgramDefinition`/`ProgramInstance`, `Session`, `WorkoutBlock`'s
existing structural shape, `ExercisePrescription`, `SetResult`/
`WorkoutResult`'s strength-side behavior, `ExercisePerformanceProfile`,
`ProgressionEngine` protocol, every Stage 1–2/3A locked invariant.

**New, additive, non-breaking:** `SteadyStateProgrammingSystem`,
`IntervalProgrammingSystem`, `FunctionalFitnessProgrammingSystem`,
`RunningProgrammingSystem` (as composer), `BlockPrescription`/
`BlockResult` and their payload types, `SessionRole`, `BenchmarkDefinition`,
`ActivityPerformanceProfile`/`BenchmarkPerformanceProfile`,
`ConcurrentScheduler` and its input/output types.

**One required generalization to an already-designed type:**
`ProgramJourney.phases` needs `PhaseContent` (single vs. concurrent) per
§3 above — the only place this validation pass found the existing
Stage 3A design to be insufficient, not merely incomplete.

Full must-do-before-Stage-4 vs. can-wait classification is in
`STAGE3B_ARCHITECTURE_DECISIONS.md`.
