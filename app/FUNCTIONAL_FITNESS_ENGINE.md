# Functional Fitness Engine

Stage 4E's `FunctionalFitnessProgrammingSystem` contract — read this
before touching `FunctionalFitnessProgramGenerator`,
`FunctionalFitnessMaterializer`, `FunctionalFitnessDecisionEngine`, or the
Fran benchmark path. Builds directly on
`FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md`'s Stage 3B validation — this
document is what actually got implemented, and where it deviates from
that earlier sketch.

## 1. Not a random WOD generator

Every workout this system produces traces back to a target `Stimulus`
supplied by configuration, resolved through a fixed, deterministic
pipeline. There is no path from "generate a workout" to a result that
isn't explainable by walking the pipeline below. Planned variance (§5)
adjusts the stimulus deterministically when configured to; it never
rolls dice.

## 2. The five-stage pipeline, and where each stage actually runs

```
A. Target stimulus       →  supplied directly (FunctionalFitnessProgramConfiguration.targetStimulus)
B. Format                →  supplied directly (FunctionalFitnessProgramConfiguration.format)
C. Movement slots         →  FunctionalFitnessProgramGenerator, at generation time
D. Concrete exercise selection →  FunctionalFitnessMaterializer, at materialization time
E. Stimulus validation    →  FunctionalFitnessMaterializer, at materialization time
```

Stages A and B are content-authoring decisions ("given a training goal,
what stimulus and format should this program use") — genuinely out of
this pass's scope (a real "goal → stimulus" recommender is a future,
separate concern). Stage C runs once, at generation time, producing the
persisted template graph. Stages D and E are deliberately deferred to
materialization, exactly like Stage 4A deferred strength's concrete-
exercise resolution and Stage 4D deferred interval progression that
depends on a live outcome — they need information (available candidates,
recent exposure) the generator cannot know in advance.

## 3. Template graph

```
WorkoutBlockTemplate
  -> FunctionalFitnessPrescriptionTemplate   (stimulus: Stimulus, format: WorkoutFormat, stored directly)
       -> FunctionalFitnessMovementSlotTemplate[]   (one per ModalityCount in stimulus.movementModalityMix)
            -> ExerciseSlot   (allowedMovementFunctions, allowedModalities, allowedTargets, allowedExercises)
```

`Stimulus`/`WorkoutFormat` are stored as direct top-level properties, not
flattened — this is not a fresh risk. `FunctionalFitnessPrescription.stimulus`/
`.format` and `BenchmarkDefinition.stimulus`/`.format` have stored them
this exact way since Stage 3C, exercised by pre-existing passing
round-trip tests. `movementModalityMix: [ModalityCount]` (an array of a
2-field struct) round-tripping safely is real, existing evidence, not an
assumption.

`FunctionalFitnessMovementSlotTemplate` is the Functional Fitness
sibling of `PrescriptionTemplate`: it owns one `ExerciseSlot` (cascade)
plus its own prescription-target fields (`reps`/`calories`/
`distanceMeters`/`loadKilograms`/`minuteSlot`/`loadingRole`/`repScheme`).
`ExerciseSlot` itself gained two constraint dimensions
(`allowedMovementFunctions: [MovementFunction]`, `allowedModalities:
[FunctionalModality]`) and a second owning-parent back-reference —
see `SUBSTITUTION_MODEL.md` §7 for why this reuses `ExerciseSlot` rather
than a parallel slot type.

`repScheme: [Int]` is the typed, explicit rep-scheme sequence (e.g.
`[21, 15, 9]` for Fran's descending ladder, `[1, 2, 3, 4, 5]` for an
ascending ladder) — never a parsed "21-15-9" string. The execution-layer
`FunctionalFitnessMovement.reps` still carries a single flat total-volume
figure (45 = 21+15+9 for Fran) — a pre-existing Stage 1-2 simplification,
unchanged; the template is the methodology-level source of truth for the
actual per-rung breakdown.

## 4. Format vs. stimulus — enforced by construction

`FunctionalFitnessPrescriptionTemplate` stores `stimulus` and `format` as
two independent fields with no subtyping relationship. Two AMRAPs with
identical `format` but different `stimulus.intensity`/`.loading` are
never conflated — proven directly
(`FunctionalFitnessProgramGeneratorTests.testSameFormatWithDifferentStimuliAreNotConflated`).

## 5. Planned variance — `FunctionalFitnessDecisionEngine`

The first concrete `ProgrammingDecisionEngine` conformer
(`Engines/FunctionalFitnessDecisionEngine.swift`). Pure and deterministic:
identical `exposureHistory`/`stimulusRequirements`/`varianceConstraints`
always yield an identical `nextStimulus`/`reasonCode`.

Checks exactly 4 dimensions, in this fixed order, adjusting only the
first one it finds violated per call (never several at once):

1. **Duration domain** (`avoidRepeatingDurationDomainWithinSessions`) —
   if the last N sessions all used the stimulus's own duration domain,
   rotate to the next domain in `DurationDomain.allCases`' own order.
2. **Loading** (`avoidRepeatingLoadingWithinSessions`) — same rotation,
   over `LoadingClassification.allCases`.
3. **Modality mix** (`avoidRepeatingModalityMixWithinSessions`) — if the
   last N sessions all used the exact same modality set, add the
   least-exposed `FunctionalModality` (by total count across all of
   `exposureHistory`) to the target's `movementModalityMix`.
4. **Movement function** (`avoidRepeatingMovementFunctionWithinSessions`)
   — same idea, over `MovementFunction`.

If fewer than N records exist, or no configured constraint is violated,
the target stimulus passes through unchanged
(`.stimulusAsConfigured`). This is deliberately simple, deterministic
rule-following — not a scoring model, and not a claim of scientifically
optimal programming.

`FunctionalFitnessExposureHistoryBuilder` (Application/UseCases —
touches `@Model` types, so it isn't part of the pure `Engines/` layer)
builds the `[VarianceExposureRecord]` input from a `ProgramInstance`'s
actual history: only a `Session` with `status == .completed` **and** a
`WorkoutBlock` carrying both a real `FunctionalFitnessResult` and its
originating `FunctionalFitnessPrescription` contributes. A scheduled-but-
skipped Session contributes nothing — exposure comes from what actually
happened, never from what was merely prescribed.

## 6. Scoring

`ScoreType`/`ScoreDirection`/`ScoreValue` (Stage 3C) are unchanged and
already cover every required case. Direction is always set explicitly at
`FunctionalFitnessResult` construction — never inferred from `scoreType`
or a format's name. `RecordFunctionalFitnessResultUseCase` is the sole
path from a result to a `PersonalRecord`:

- `comparableValue(for:)` turns the structured `ScoreValue` into one
  `Double` purely for `ScoringEngine`'s comparison — the stored value
  stays the structured `ScoreValue`, never flattened for real. The
  `.roundsAndReps` proxy (`rounds * 100_000 + partialReps`) is
  TRAININGOS_DESIGNED: more rounds always beats fewer, and within the
  same round count more partial reps wins.
- `mapToScoringDirection(_:)` bridges `ScoreDirection` (2 cases) onto the
  pre-existing `ScoringDirection` (4 cases) `ScoringEngine`/
  `PersonalRecord` already use.

Rx and Scaled are never compared as the same PR sequence —
`ScoringEngine.bestRecord`'s existing `context` filter already enforces
this, unchanged.

## 7. Benchmark identity — the Fran consolidation

Before this stage, two representations of "Fran" existed:

1. **Legacy:** a canonical `Exercise` (`ExerciseCatalog.fran`), scored
   through `RecordWorkoutResultUseCase`'s `benchmarkExercise`/
   `prCandidateValue` parameters, folding a PR into
   `ExercisePerformanceProfile` — the same entity type ordinary
   strength-exercise PRs live in.
2. **Canonical:** `BenchmarkDefinition` (`canonicalID`, `stimulus`,
   `format`, `scoreType`/`scoreDirection`) + `BenchmarkPerformanceProfile`,
   fed by the typed `FunctionalFitnessPrescription`/`FunctionalFitnessResult`
   path.

**(2) is now the sole canonical representation.** `ExerciseCatalog.fran`
is gone. `RecordWorkoutResultUseCase` lost its benchmark-folding
parameters entirely — a new `RecordFunctionalFitnessResultUseCase` is
the only path to a benchmark `PersonalRecord`.
`SeedScenarios.forTimeBenchmarkSession` builds Fran through (2)
end-to-end. Three existing tests that asserted against (1) were migrated
to assert the identical invariant against (2) — see
`STAGE4_IMPLEMENTATION_REPORT.md`'s Stage 4E §5 for the exact list.

A `BenchmarkDefinition` never gets its prescription changed in place —
the same "new version, not a silent mutation" discipline every
`ProgramDefinition` already follows — though no versioning field was
added since nothing in this pass actually needs to revise an existing
benchmark's definition.

## 8. Scaling vs. substitution

Both concepts remain representable, distinctly:

- **Scaling** (Toes-to-Bar prescribed, Knee Raises performed): already
  fully solved since Stage 3C via
  `FunctionalFitnessPerformedMovement.prescribedMovement`/
  `.performedExercise` — the prescription is never overwritten; the
  performed variant is recorded alongside it. `resultContext == .scaled`
  marks the attempt accordingly. No new code this stage; re-confirmed
  with a test.
- **Substitution** (Row prescribed, Bike performed because the rower was
  unavailable): the `SlotSelectionOverride`/`SubstituteExerciseUseCase`
  mechanism from Stage 4C, now reachable for Functional Fitness movement
  slots too (§3 above). THIS SESSION ONLY and GOING FORWARD both apply.

Which real-world scenario is "scaling" vs. "substitution" is a UI/product
framing choice layered on top — the domain does not force them to be the
same mechanism, and isn't required to decide that framing itself.

## 9. TrainingStressProfile

`FunctionalFitnessStressProfileMapper` (pure, `Engines/`) maps a resolved
`Stimulus` to a `TrainingStressProfile` — coarse classifications only,
never a fabricated numeric score:

- `overallIntensity`/`metabolicDemand` <- `stimulus.intensity`.
- `systemicDemand`/`recoveryDemand` <- `stimulus.systemicDemand`.
- `lowerBodyLoad` <- `stimulus.loading`, only if `.squatLoaded`/
  `.hingeLoaded` is present in `movementFunctions`; `.none` otherwise.
- `upperBodyLoad` <- `stimulus.loading`, only if `.pressLoaded`/
  `.gymnasticsPull`/`.gymnasticsPush` is present; `.none` otherwise.
- `impactLoading` <- `.moderate` only if `.monostructural`/`.locomotion`
  is present (a coarse, explicitly-labeled simplification); `.none`
  otherwise.
- `durationClassification` <- `stimulus.targetDurationDomain` directly
  (same type, no re-classification needed).

## 10. Source-derived vs. TrainingOS-designed

Reused unchanged from Stage 3B (`PROGRAMMING_SOURCES.md` §4): the
five-stage pipeline's shape, the 3-modality vocabulary (metabolic
conditioning / gymnastics / weightlifting), and "planned variance, not
randomness" as the governing philosophy — all SOURCE-DERIVED or
TRAININGOS-INTERPRETATION, already verified in Stage 3B, not re-verified
this pass. Every number this stage adds is TRAININGOS_DESIGNED and
labeled as such: the short(<5min)/medium(5-15min)/long(>15min)
duration-domain thresholds (`FunctionalFitnessStimulusValidator`, carried
from Stage 3B's own sketch), the `.roundsAndReps` PR-comparison proxy,
and the strength+metcon composition's fixed 5×5 numbers. No proprietary
CrossFit workout catalog was imported — the curated movement catalog is
small and generic, and Fran is the one widely-known, non-proprietary
reference benchmark already used since Stage 3C.

## 11. What this system does not claim

- A curated V1 built-in library — no `V1_PROGRAM_LIBRARY.md` entry names
  a Functional Fitness configuration.
- Skill-level gating (`skillDemand <= configuredUserLevel`) — no
  per-Exercise skill classification exists yet; `FunctionalFitnessStimulusValidator`
  documents this as deferred rather than inventing a score.
  `FunctionalFitnessReasonCode.functionalSkillExposure` is declared for
  vocabulary completeness but never produced.
- A biomechanical or scientifically-optimized variance model — the
  balancing rules are simple, deterministic, and configured, not a
  claim of programming superiority.
- ConcurrentScheduler integration — Functional Fitness emits Sessions/
  WorkoutBlocks/`TrainingStressProfile` the future scheduler can consume,
  but nothing here schedules across systems.
- Any execution UI (AMRAP/EMOM timers, benchmark UI).
