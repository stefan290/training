# Functional Fitness Programming Model

Stage 3B architecture validation for CrossFit-style functional fitness
programming. Proposed abstraction only — nothing here is implemented, and
per the brief's explicit instruction, **this does not build a workout
generator of any kind.** Source grounding is in `PROGRAMMING_SOURCES.md`
§4; this document builds directly on CrossFit's own stated
stimulus-first sequence rather than inventing a competing one.

## 1. `FunctionalFitnessProgrammingSystem` — the five-stage pipeline

Per Stage 3B §18, mapped directly from CrossFit's own described sequence
(`PROGRAMMING_SOURCES.md` §4: goal/stimulus → program → analyze,
TRAININGOS INTERPRETATION of that structure expressed in our
`ProgrammingSystem` vocabulary):

```
protocol FunctionalFitnessProgrammingSystem: ProgrammingSystem {
    func defineStimulus(for goal: TrainingGoal) -> Stimulus                     // A
    func selectFormat(for stimulus: Stimulus) -> WorkoutFormat                  // B
    func defineMovementSlots(for stimulus: Stimulus, format: WorkoutFormat) -> [MovementSlot]  // C
    func resolveExercises(for slots: [MovementSlot]) -> [ExercisePrescription]  // D
    func validate(_ programmed: ProgrammedWorkout, against stimulus: Stimulus) -> StimulusValidation  // E
}
```

Each stage produces a typed value the next stage consumes — this mirrors
`PROGRAM_GENERATOR_SPEC.md`'s existing generation hierarchy (§3 there:
select system → derive structural parameters → instantiate → resolve
slots) closely enough that **no new top-level architectural pattern is
introduced**; Functional Fitness reuses the same "hierarchy of typed
stages" shape already validated for Hypertrophy/Powerlifting generation,
just with different stage content.

### 1.1 Stage A — Stimulus

```
struct Stimulus {
    let targetDurationDomain: DurationDomain     // e.g. .short(<5min), .medium(5-15min), .long(>15min)
    let intensity: IntensityLevel                // .high | .moderate | .low — separate from format
    let loading: LoadingProfile                  // .heavy | .moderate | .light | .bodyweightOnly
    let movementFunctions: [MovementFunction]    // e.g. .squat, .hinge, .pull, .push, .monostructural
    let movementModalityMix: [Modality: Int]     // per PROGRAMMING_SOURCES.md §4's M/G/W split —
                                                   // e.g. [.metabolicConditioning: 1, .gymnastics: 1, .weightlifting: 1]
                                                   // for a triplet
    let skillDemand: SkillLevel                   // .low | .moderate | .high (e.g. muscle-ups = high)
    let localFatigue: MuscleGroup?                // which region this stimulus is expected to tax
    let systemicDemand: SystemicDemandLevel       // whole-body fatigue cost, independent of localFatigue
    let scoreType: ScoreType                      // see §4 — decided here, at stimulus time, not
                                                    // inferred later from the format
}
```

### 1.2 Stage B — Format (kept strictly separate from Stage A, see §2)

```
enum WorkoutFormat {
    case amrap(cap: Duration)
    case emom(intervalDuration: Duration, totalDuration: Duration)
    case forTime(cap: Duration?)
    case roundsForTime(rounds: Int, cap: Duration?)
    case chipper(cap: Duration?)
    case ladder(direction: LadderDirection, cap: Duration?)
    case interval(count: Int, workDuration: Duration, restDuration: Duration)
    case maxLoad
    case maxReps(cap: Duration)
}
```

### 1.3 Stage C — Movement slots (not concrete exercises yet)

```
struct MovementSlot {
    let function: MovementFunction                // e.g. .looselyLoadedSquat, .gymnasticsPull, .monostructural
    let loadingRole: LoadingProfile?               // how heavy this slot should be, independent of which
                                                     // exercise ends up filling it
    let candidates: [Exercise]                     // reuses the existing canonical Exercise Library —
                                                     // exactly the same ExerciseSlot.candidates pattern
                                                     // from PROGRAM_GENERATOR_SPEC.md §4, not a new mechanism
}
```

### 1.4 Stage D — Concrete exercise selection

Reuses `ExerciseSlot`/canonical-exercise resolution unchanged from
`PROGRAM_GENERATOR_SPEC.md` §4.1 — Functional Fitness's "moderate loaded
squat" candidate-list-with-resolution is architecturally identical to
Family A's "Incline Push" category dropdown. No new resolution mechanism.

### 1.5 Stage E — Stimulus validation

```
struct StimulusValidation {
    let estimatedDuration: Duration
    let estimatedLoadingAdequacy: Bool
    let estimatedSkillMatch: Bool
    let passes: Bool
    let notes: [String]     // e.g. "estimated duration exceeds target domain by 40%"
}
```

Directly implements CrossFit's own "analyze the programmed workout for
accuracy against the goal" step (`PROGRAMMING_SOURCES.md` §4) — this is
the stage that would let a future (not-built-yet) generator reject or
adjust its own output, rather than trusting Stage D blindly.

## 2. Format and stimulus are different types — never conflated

Per Stage 3B §19, this is a hard requirement, not a soft preference: **two
AMRAPs can have completely different stimuli**, so `WorkoutFormat` and
`Stimulus` must be two separate types with no inheritance or subtyping
relationship between them, and a `WorkoutBlock`'s prescription must carry
both independently.

```
struct FunctionalFitnessPrescription {
    let stimulus: Stimulus            // §1.1
    let format: WorkoutFormat         // §1.2
    let movements: [ResolvedMovement] // concrete exercises + their per-movement targets (reps/load/etc.)
}
```

A 12-minute AMRAP triplet at moderate loading and a 12-minute AMRAP of
max-effort heavy singles are both `.amrap(cap: 12min)` for `format`, but
have entirely different `stimulus.loading`, `stimulus.movementModalityMix`,
and `stimulus.intensity` — the type system enforces that nothing can
collapse these into "the same kind of workout" just because they share a
format tag.

## 3. WorkoutBlock proof — the four required examples

### Example 1 — 12-minute AMRAP triplet

```
WorkoutBlock(
    type: .functionalFitness,
    prescription: .functionalFitness(FunctionalFitnessPrescription(
        stimulus: Stimulus(targetDurationDomain: .medium, intensity: .high, loading: .moderate,
                            movementFunctions: [.hingeLoaded, .gymnasticsPull, .monostructural],
                            movementModalityMix: [.weightlifting: 1, .gymnastics: 1, .metabolicConditioning: 1],
                            skillDemand: .moderate, localFatigue: nil, systemicDemand: .high,
                            scoreType: .roundsAndReps),
        format: .amrap(cap: .minutes(12)),
        movements: [
            ResolvedMovement(exercise: .dbThruster, reps: 10),
            ResolvedMovement(exercise: .toesToBar, reps: 12),
            ResolvedMovement(exercise: .bike, target: .calories(15))
        ]
    ))
)
// Result: FunctionalFitnessResult(scoreType: .roundsAndReps, roundsCompleted: 7, partialReps: 14, context: .rx)
```

### Example 2 — EMOM 12, three rotating stations

```
WorkoutBlock(
    type: .functionalFitness,
    prescription: .functionalFitness(FunctionalFitnessPrescription(
        stimulus: Stimulus(targetDurationDomain: .medium, intensity: .moderate, loading: .bodyweightOnly,
                            movementFunctions: [.monostructural, .gymnasticsPush, .hingeLoaded],
                            movementModalityMix: [.metabolicConditioning: 1, .gymnastics: 1, .weightlifting: 1],
                            skillDemand: .low, localFatigue: nil, systemicDemand: .moderate,
                            scoreType: .completedIntervals),
        format: .emom(intervalDuration: .minutes(1), totalDuration: .minutes(12)),
        movements: [
            ResolvedMovement(exercise: .row, target: .calories(12), minuteSlot: 1),
            ResolvedMovement(exercise: .burpee, reps: 10, minuteSlot: 2),
            ResolvedMovement(exercise: .wallBall, reps: 12, minuteSlot: 3)
        ]
    ))
)
```

`minuteSlot` on `ResolvedMovement` is the one genuinely new mechanic this
example surfaces: EMOM's rotation is a *scheduling-within-the-block*
concept, not a new `WorkoutBlockType`. Modeled as metadata on the
movement list, not as a structural change to `WorkoutBlock` itself.

### Example 3 — For Time, 21-15-9 (a named benchmark)

```
WorkoutBlock(
    type: .functionalFitness,
    prescription: .functionalFitness(FunctionalFitnessPrescription(
        stimulus: Stimulus(targetDurationDomain: .short, intensity: .high, loading: .moderate,
                            movementFunctions: [.hingeLoaded, .gymnasticsPull],
                            movementModalityMix: [.weightlifting: 1, .gymnastics: 1],
                            skillDemand: .moderate, localFatigue: nil, systemicDemand: .high,
                            scoreType: .time),
        format: .forTime(cap: nil),
        movements: [
            ResolvedMovement(exercise: .thruster, repsByRound: [21, 15, 9]),
            ResolvedMovement(exercise: .pullUp, repsByRound: [21, 15, 9])
        ]
    ))
)
// Result: FunctionalFitnessResult(scoreType: .time, completionTime: Duration, context: .rx)
```

This is "Fran" — see §5 for why the *benchmark identity* ("this is Fran")
is a separate concern from the *prescription* above, which is
self-sufficient without knowing it has a name.

### Example 4 — Strength + Metcon, one Session, heterogeneous blocks

```
Session(blocks: [
    WorkoutBlock(type: .strength, prescription: .strength(ExercisePrescription(
        exercise: .backSquat, sets: 5, reps: 5, /* load/RIR per existing model */))),
    WorkoutBlock(type: .functionalFitness, prescription: .functionalFitness(
        FunctionalFitnessPrescription(/* 12-minute AMRAP, per Example 1 */)))
])
```

**No change required to `Session` or the Day → Session → ordered
WorkoutBlocks invariant.** This was already true by construction from
Stage 1–2 ("A Session is an ordered list of blocks of any type; that is
normal, not a special case" — `CLAUDE.md` rule 7) — this example simply
exercises that existing invariant with a real cross-`ProgrammingSystem`
case (Block 1 from `HypertrophyProgrammingSystem`/`PowerliftingProgrammingSystem`,
Block 2 from `FunctionalFitnessProgrammingSystem`) and confirms it holds.

## 4. Scoring — a generic model with a mandatory, never-inferred direction

Per Stage 3B §21, explicitly: never infer direction from the workout's
name or format.

```
enum ScoreType {
    case time
    case roundsAndReps
    case repetitions
    case calories
    case distance
    case load
    case completedIntervals
}

enum ScoreDirection {
    case lowerIsBetter
    case higherIsBetter
}

struct ScoreDefinition {
    let type: ScoreType
    let direction: ScoreDirection   // always explicitly set at Stimulus-definition time (§1.1),
                                     // never derived from `type` or from `format` by a lookup table
}
```

**Why a lookup table from `ScoreType` to `ScoreDirection` is deliberately
not provided, even though `.time` is "obviously" lower-is-better in
almost every case:** the brief's own instruction is "do not infer score
direction from workout name" — extending that discipline consistently
means also not inferring it from `type` via an implicit default, because
an implicit default is exactly as fragile as name-inference the moment
a genuine exception exists (e.g. a max-distance-in-time-cap score is
`.distance` + `higherIsBetter`, but a "fewest total reps across three
max-effort attempts" oddity would be `.repetitions` + `lowerIsBetter` —
rare, but the type system should not have quietly ruled it out). Every
`ScoreDefinition` sets `direction` explicitly, every time, at authoring
time.

## 5. Benchmark vs. generated workout — smallest correct abstraction

Per Stage 3B §22: determine the smallest correct abstraction, not
necessarily a new persisted entity.

**Decision: one new lightweight entity, `BenchmarkDefinition` — not a
new result type, not a new WorkoutBlock type.**

```
struct BenchmarkDefinition {
    let canonicalID: String            // stable identity, e.g. "benchmark.fran" — see
                                         // PERFORMANCE_PROFILE_MODALITY_REVIEW.md §3 for the
                                         // full canonical-identity treatment
    let name: String                   // "Fran"
    let prescription: FunctionalFitnessPrescription   // the exact, stable, repeatable prescription
}
```

- A **generated Functional Fitness workout** (Examples 1, 2, 4 above) is
  an ordinary `WorkoutBlock`/`FunctionalFitnessPrescription` with **no**
  `BenchmarkDefinition` reference — it's permanent training history
  exactly like any other logged session (per the existing, locked
  invariant that all training history is permanent), but it is not
  automatically a PR-tracked benchmark, exactly as §22 requires.
- A **benchmark attempt** (Example 3, "Fran") is the same
  `WorkoutBlock`/`FunctionalFitnessPrescription` shape, **plus** a
  reference to the `BenchmarkDefinition` it was an attempt at. This is the
  same "reference, don't duplicate or subclass" pattern already used for
  `ExercisePrescription.pairedSlot` (`PROGRAMMING_SYSTEM_MODEL.md` §5.2) —
  no new prescription shape, just an optional pointer.

```
extension FunctionalFitnessPrescription {
    var benchmark: BenchmarkDefinition?   // nil for a generated workout, set for a benchmark attempt
}
```

This is what makes "meaningful longitudinal comparison" (§22's
requirement) possible: querying "all attempts where `benchmark.canonicalID
== "benchmark.fran"`" is a plain filter over ordinary training history,
not a separate PR-tracking subsystem. See
`PERFORMANCE_PROFILE_MODALITY_REVIEW.md` §2 for how this feeds
`PerformanceProfile`.

## 6. Scaling — never overwrite the prescription

Per Stage 3B §23, this is a direct instance of the already-locked
Prescription/Recommendation/Actual separation (`CLAUDE.md` rule 3),
applied to Functional Fitness's specific scaling vocabulary:

```
struct ResolvedMovement {
    let prescribedExercise: Exercise          // e.g. Toes-to-Bar — never mutated
    let performedExercise: Exercise?          // e.g. Knee Raises — set only when scaled;
                                                // nil means "performed as prescribed"
    let prescribedLoad: Double?
    let performedLoad: Double?
    let context: ResultContext                // .rx | .scaled — existing enum from Stage 1–2,
                                                // reused, not replaced
}
```

The prescribed/performed split already exists in the domain model exactly
this shape for strength (`ExercisePrescription` vs. `SetResult` — Stage
1–2) — this section confirms the same split, not a new one, correctly
extends to movement *substitution* (not just load), which strength's
existing model didn't previously need to express as sharply (a strength
substitution is comparatively rare; in Functional Fitness, Rx-vs-Scaled
substitution is a routine, expected part of every session). **The
original `prescribedExercise` is never overwritten** — satisfying §23's
explicit requirement directly.

## 7. Planned variance — exposed metadata, no generator

Per Stage 3B §24 and the standing product constraint (§17: do not create
a random WOD generator): the rolling-exposure metadata a future generator
would query, without building that generator now.

```
struct VarianceExposureRecord {
    let date: Date
    let durationDomain: DurationDomain
    let loadingProfile: LoadingProfile
    let movementModalityMix: [Modality: Int]
    let movementPatternsUsed: [MovementFunction]
    let skillDemand: SkillLevel
    let wasHighIntensity: Bool
}
```

Derived directly and mechanically from each logged
`FunctionalFitnessPrescription` (§1.1's `Stimulus` fields), not a
separately-authored record — every generated or benchmark workout already
carries everything needed to produce one of these; a query surface, not
new input data. This satisfies §24's "architecture should allow a future
generator to query this history" without implementing the generator
itself, consistent with CrossFit's own "planned/constrained variance" —
avoiding gap/repetition, not randomizing — per `PROGRAMMING_SOURCES.md` §4.

## 8. What this document does not decide

- **The actual `ProgramGenerator`/WOD-selection algorithm** — explicitly
  out of scope (§17, §24, §45 of the brief).
- **A complete, canonical `MovementFunction` taxonomy** — sketched here
  (`.hingeLoaded`, `.gymnasticsPull`, `.monostructural`, etc.) with enough
  cases to prove the four required examples; a full taxonomy is content
  work, not an architecture question.
- **Whether `BenchmarkDefinition` needs its own catalog/curation UI** —
  a product decision, not an architecture one; the data shape (§5) doesn't
  depend on how benchmarks get authored.
