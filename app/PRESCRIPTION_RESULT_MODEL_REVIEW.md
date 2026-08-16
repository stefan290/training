# Prescription / Result Model Review

**Stage 6A status:** `WORKOUT_EXECUTION.md` §1 confirms the typed
`BlockPrescription`/`BlockResult` shape this document proposed is
exactly what execution reads/writes through — no new case, no
modality-specific `Session` subclass. It also confirms the migration
this document once proposed and deferred (`WorkoutResult` →
`SteadyStateResult`/`IntervalResult`/`FunctionalFitnessResult`) is now
real and implemented for the modern path; the legacy `.amrap`/`.emom`/
`.forTime`/`WorkoutResult` combination is Stage 1-2 seed-scenario-only
and is not a target for Stage 6 execution.

Stage 3B stress test of `ExercisePrescription` and `WorkoutResult`/
`SetResult` against every modality validated in this document set. This
is a **proposed migration, documented, not implemented** — per the
brief's explicit instruction (§33: "Do NOT refactor production code yet.
Document the proposed migration first"). No file under `TrainingOS/` is
touched by this document.

## 1. The stress test

Can `ExercisePrescription` (sets, reps, load, RIR — Stage 1–2's strength
model) cleanly represent, without abusing irrelevant fields:

| Case | Strength-shaped? |
|---|---|
| 3×10 Bench Press | Yes — this is exactly what it was designed for |
| 45 min Zone 2 | No — no sets/reps concept applies; `load`/`RIR` would sit `nil` forever |
| 5×1 km running intervals | Partially — "5×" resembles `sets`, but the payload is distance+pace, not reps+load |
| 4×4 min intervals | No — duration-based work/recovery structure, no reps/load at all |
| 12 min AMRAP | No — no predetermined rep/set count exists; the *result* (rounds+reps) is what's counted, not prescribed |
| EMOM rotation | No — per-minute movement rotation has no set/rep/load shape |

**Conclusion: `ExercisePrescription` is confirmed too strength-specific to
serve as the universal prescription type.** Forcing every case above
through it would require either populating strength fields with dummy
values (`sets: 1, reps: 1` for a 45-minute ride) or leaving most of the
type's fields permanently `nil` for entire modalities — both are exactly
the architecture smells §43 of the brief warns against.

## 2. Proposed shape: `BlockPrescription`, additive not destructive

**`ExercisePrescription` is not renamed, replaced, or deprecated.** It
becomes one typed case among siblings, all introduced net-new:

```
enum BlockPrescription {
    case strength(ExercisePrescription)                    // UNCHANGED — Stage 1–2's existing type
    case steadyState(SteadyStatePrescription)               // new — ENDURANCE_PROGRAMMING_MODEL.md §5
    case interval(IntervalPrescription)                     // new — ENDURANCE_PROGRAMMING_MODEL.md §3
    case functionalFitness(FunctionalFitnessPrescription)   // new — FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md §2
}

struct SteadyStatePrescription {
    let duration: Duration
    let targetIntensity: IntensityTarget
}

struct IntervalPrescription {
    let intervalCount: Int
    let workSpec: IntervalLegSpec
    let recoverySpec: IntervalLegSpec
}
```

`WorkoutBlock` gains one field: `prescription: BlockPrescription`,
discriminated by the block's own existing `WorkoutBlockType` (already
locked, `CLAUDE.md` rule 7 — "never branch UI or persistence code on 'is
this a strength session'; branch on the block's `WorkoutBlockType`
instead"). This is the same principle, applied one layer deeper: a
`.strength` block always carries `.strength(ExercisePrescription)`; a
`.steadyState` block always carries `.steadyState(SteadyStatePrescription)`;
the enum's case and the block's type are kept in lockstep by construction,
not by convention that could silently drift.

**Why an enum of typed payloads, not a broader base class or a bag of
optional fields:** per the brief's own §44 ("do not over-generalize... no
giant generic object through dictionaries/JSON blobs... prefer shared
protocols / enums / typed value objects"). An enum with associated values
gets exhaustiveness checking (the compiler forces every switch/consumer to
handle every case, or explicitly ignore it) — a property no "one big
optional-riddled struct" design can offer, and no untyped dictionary
design can offer at all.

**Migration path (documented, not applied):**
1. Add `BlockPrescription` and its new payload types as pure additions —
   zero changes to any existing type.
2. Add `WorkoutBlock.prescription: BlockPrescription` as a new field.
3. Existing strength `WorkoutBlock`s continue populating whatever
   strength-specific storage they use today (`ExercisePrescription`
   relationships, unchanged) — `prescription` is a computed convenience
   wrapper (`.strength(self.existingExercisePrescription)`) during a
   transition period, or backfilled once, depending on what the Stage 4
   implementer finds cheaper; either is non-breaking to existing tests
   from Stage 1–2 (`DomainModelScenarioTests`, `PerformanceProfileContinuityTests`,
   etc. — none of them need to change for this addition to land).

## 3. The same stress test, for results

Per Stage 3B §34: does `WorkoutResult`/`SetResult` need the same
treatment? **Yes, for the same reason and by the same method.**

```
enum BlockResult {
    case strength([SetResult])                          // UNCHANGED
    case steadyState(SteadyStateResult)                  // new
    case interval(IntervalResult)                        // new
    case functionalFitness(FunctionalFitnessResult)      // new
}

struct SteadyStateResult {
    let duration: Duration
    let averageHR: Int?
    let averagePower: Int?
    let distance: Distance?
}

struct IntervalResult {
    let perInterval: [IntervalRepResult]     // actualTime, pace/power/HR — per Stage 3B §12
    let sessionDuration: Duration
    let sessionDistance: Distance?
    let averagePace: Pace?
    let averageHR: Int?
    let rpe: Int?
}

struct IntervalRepResult {
    let actualTime: Duration
    let pace: Pace?
    let averageHR: Int?
}

struct FunctionalFitnessResult {
    let scoreType: ScoreType              // FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md §4
    let scoreValue: ScoreValue             // typed union: .time(Duration) | .roundsAndReps(Int, Int) |
                                            // .repetitions(Int) | .calories(Int) | .distance(Distance) |
                                            // .load(Double) | .completedIntervals(Int)
    let context: ResultContext             // .rx | .scaled — existing enum, reused
    let benchmark: BenchmarkDefinition?    // nil unless this was a benchmark attempt
}
```

**Confirmed: avoid one huge entity with dozens of nullable properties** —
the brief's explicit warning (§34) is satisfied by the same enum-of-typed-
cases approach as §2, not by adding fields to `WorkoutResult` for every
modality. `WorkoutResult` (the Session-level aggregate, distinct from
`SetResult`) stays as the container that references a `BlockResult` per
`WorkoutBlock`, exactly mirroring the new `BlockPrescription`/`WorkoutBlock`
relationship.

## 4. `ScoreValue` deserves its own note

`FunctionalFitnessResult.scoreValue` is itself a typed union rather than
one field per possible score shape — this is the one place in this
document where "typed enum with associated values" is chosen over
"several optional fields" for a reason worth stating explicitly: a
`ScoreType.roundsAndReps` result is *two* numbers (rounds AND partial
reps), not reducible to a single scalar, so a naive `scoreValue: Double`
would either lose information or need a second `partialReps: Double?`
field living awkwardly outside the union — the union keeps the invariant
"a score's shape is determined by its type" enforced by the compiler
rather than by convention.

## 5. What stays completely unchanged

- `SetResult`, `WorkoutResult`'s existing strength-side relationships,
  `PersonalRecord`, `RecordSetResultUseCase`/`RecordWorkoutResultUseCase`
  — none of Stage 1–2's strength persistence code is touched. This
  document adds siblings; it does not modify what already ships.
- The Prescription/Recommendation/Actual separation (`CLAUDE.md` rule 3)
  — `BlockPrescription` is squarely on the Prescription side;
  `BlockResult` is squarely on the Actual side; nothing here blurs that
  line for any modality.
- `ProgressionEngine`'s existing protocol shape — see
  `MODALITY_ARCHITECTURE_VALIDATION.md` §5 for how `ProgressionInput`/
  `ProgressionOutput` relate to `BlockPrescription`/`BlockResult`; that's
  a progression-architecture question, addressed there, not here.

## 6. What this document does not decide

- **Whether `BlockPrescription`/`BlockResult` are Swift enums with
  associated values, or a protocol with concrete conforming structs plus a
  discriminator** — both satisfy §44's "strong typing" requirement
  equally well; the choice is an implementation detail for whoever
  actually builds this in Stage 4, not an architecture question this
  validation pass needs to settle.
- **The exact `Distance`/`Pace`/`Duration` value-type implementations** —
  assumed to exist or be trivially added (thin wrappers over `Double`/
  `TimeInterval` with unit safety); not specified further here.
- **Migration of any already-persisted data** — moot for this app today
  (no shipped users, no existing production data to migrate), noted only
  so a future reader doesn't wonder why no migration script is proposed.
