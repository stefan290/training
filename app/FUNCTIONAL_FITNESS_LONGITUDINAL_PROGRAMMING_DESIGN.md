# Functional Fitness Longitudinal Programming — Design / Audit

**Status: DESIGN / AUDIT ONLY. Nothing implemented, committed, or pushed.**
This document is separate from, and does not modify, `TRAINING_MIX_CONCURRENT_PROGRAMMING_DESIGN.md`
(CP.1/CP.2, closed at commit `bca43e2ff47d21d8703275d06354af6a086f0d45`). CP.2
answered "what fits with the surrounding TrainingMix THIS WEEK." This
document investigates a different, independent question: **what should
Functional Fitness itself be trying to develop ACROSS TIME?**

Every claim below is grounded in a direct read of the real production code as
it stands after CP.2 — not from a prior document's own claims, and not from
unit-test-only configurations.

---

## Core product principle (locked by the requester, restated here)

**VARIATION != RANDOMNESS.** Functional Fitness must not mean random workouts
or "constantly varied" read as arbitrary novelty. The athlete should
experience recognizable progression, purposeful variation, complementary
sessions, changing-but-coherent stimuli, repeated exposure where repetition
is useful, enough novelty to build broad capacity, and sparse deliberate
retesting where appropriate — while avoiding movement roulette, arbitrary
format changes, novelty for its own sake, identical workouts every week, and
permanently avoiding a stimulus because it was used once recently.

## Source/product authority

Functional Fitness is **TrainingOS-original programming**. CrossFit
methodology may *inform* stimulus/variance/movement-selection/structure/
scaling principles, but CrossFit.com WOD is not source authority, the way
Family A's hypertrophy prescriptions are. Every new semantic proposed below
is labeled **PRODUCT DECISION** — TrainingOS's own choice, not recovered
methodology — never presented as if extracted from an external source.

---

## 1. Real current FF production path

Traced end to end against the one real construction site
(`LongTermPlanner.functionalFitnessParameterCandidates`, `:1200-1224`) — not
a test fixture:

`LongTermPlanner.functionalFitnessParameterCandidates(component:)` builds
exactly **one** fixed `Stimulus` (medium duration, moderate intensity/
loading/skill/systemic-demand, `[.squatLoaded, .gymnasticsPull,
.monostructural]`, an even weightlifting/gymnastics/metcon mix) and exactly
one fixed `WorkoutFormat` (`.roundsForTime(rounds: 5, capSeconds: nil)`),
wrapped in one `FunctionalFitnessProgramConfiguration` with
`varianceConstraints: VarianceConstraints()` — every field `nil` — and
`lengthWeeks: 4`.

`FunctionalFitnessProgramGenerator.generate` (`:36-87`) is called exactly
once per `ProgramInstance`. It builds `configuration.lengthWeeks` identical
`TrainingWeek`s (all `isDeload: false` — Functional Fitness has no deload
concept at all, confirmed by absence), then, for each of `daysPerWeek`
`TemplateSession`s, builds **one** `FunctionalFitnessPrescriptionTemplate`
carrying the SAME `configuration.targetStimulus`/`format`/
`varianceConstraints` — reused identically across every week of the
`ProgramDefinition`'s life. Stage C (movement-slot derivation) runs here,
deterministically, from `stimulus.movementModalityMix`/`movementFunctions`.
Stages D (concrete exercise resolution) and E (Stage-E validation) are
deliberately deferred to materialization time.

`RollTacticalWindowUseCase.materializeFirstWindow`/`.rollForward` call
`FunctionalFitnessMaterializer.materializeWeek` once per real tactical week.
Inside it, for each of that week's `TemplateSession`s, `decide()` is called
against `ffTemplate.stimulus` (**the same fixed baseline, every single
week** — confirmed: nothing computes a different baseline per week
anywhere in this pipeline) plus `ffTemplate.varianceConstraints ??
VarianceConstraints()` (also the same fixed, all-`nil` value every week) plus
`FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn:
instance)` (real, but — see §2/§6 — never populated with anything the 4
original checks can act on in production, since every check requires
`varianceConstraints`'s corresponding field to be non-nil to even run).
`decision.nextStimulus` is what actually gets persisted onto a NEW
`FunctionalFitnessPrescription` — this is the **only** `Stimulus` value ever
stored (see §17).

`FunctionalFitnessExposureHistoryBuilder.build` (`:18-39`) reads
`instance.sessions.filter { $0.status == .completed }`, and for each
completed block requiring both a real `FunctionalFitnessResult` AND its
originating `FunctionalFitnessPrescription`, derives a `VarianceExposureRecord`
from **the prescription's stimulus fields only** (`durationDomain`,
`loading`, `movementModalityMix`, `movementFunctionsUsed`, `skillDemand`,
`wasHighIntensity`) — `result.completedAt` is read only for the sort/window
key. **No field of the real `FunctionalFitnessResult`
(`scoreValue`/`scoreDirection`/`resultContext`) or of any
`FunctionalFitnessPerformedMovement` (scaling, substitutions, performed
reps/load/distance/calories) is ever read here.** This is the central
finding this whole audit turns on (§6/§17).

**What happens when every `VarianceConstraints` field is `nil`:** each of the
4 original `FunctionalFitnessDecisionEngine` checks begins with
`guard let window = input.varianceConstraints.avoidRepeating...WithinSessions,
window > 0 else { return nil }` — with the real production configuration,
**every guard fails immediately, every call.** `decide()` therefore always
falls through, in production, to `.stimulusAsConfigured` — the identical
fixed baseline, forever, for the life of the `ProgramInstance`. CP.2's own
two new checks (cross-modality discouragement, same-week complementarity) are
the *only* mechanism that currently ever produces a different `Stimulus` than
the configured baseline in the real default production path.

**What is lost between weeks:** everything except "which dimensions did the
last N completed sessions' *stimulus* look like" (and even that signal is
inert today, since `window` is always `nil`). No performance quality, no
scaling degree, no completion difficulty, no trend of any kind survives from
one week to the next.

**Progression independent of variance:** none exists. There is no code path
anywhere that increases duration, load, density, or difficulty over time for
Functional Fitness. `includeStrengthBlock`'s fixed 5×5 strength composition
(`FunctionalFitnessProgramGenerator.addStrengthBlock`) is explicitly
documented as "a plain, fixed, non-progressing strength block... not wired to
`StrengthProgressionEngine`'s... machinery" — confirming this by its own
admission.

## 2. VarianceConstraints audit

```swift
struct VarianceConstraints: Codable, Equatable {
    var avoidRepeatingModalityMixWithinSessions: Int?
    var avoidRepeatingMovementFunctionWithinSessions: Int?
    var avoidRepeatingDurationDomainWithinSessions: Int?
    var avoidRepeatingLoadingWithinSessions: Int?
}
```

Each field means: *"if the last N completed sessions all shared the exact
same value on this one dimension AND the newly-configured baseline would
repeat it again, rotate to the next value in that dimension's own declared
`CaseIterable` order (wrapping around), or — for modality mix/movement
function — append the single least-exposed-overall value."* Every field is a
**repetition-avoidance minimum-rotation-interval**, never a hard maximum,
never a preference score, never anything probabilistic. `nil` means "this
dimension's rotation check is disabled" (the corresponding `decide()` guard
short-circuits to `nil` immediately) — not "rotate every session" and not
"rotate never under any circumstance," simply *inert*.

**The one real production call site (`LongTermPlanner.swift:1219`) supplies
`VarianceConstraints()` with zero surrounding explanation** — no comment, no
"TODO," no reference to a deferred product decision anywhere nearby. Every
non-`nil` `VarianceConstraints` value in the entire repository exists **only**
in `TrainingOSTests/` fixtures, which is exactly what exercises and proves the
engine's 4 checks work correctly in isolation.

**Classification:** the engine side is unquestionably **(B) unfinished
wiring** — a fully implemented, fully tested, working mechanism that the
one real caller simply never populates — corroborated by **(D) tests exercise
a capability never enabled in production** (every non-nil instance is
test-only). However, the repository gives no evidence of *why* — no comment
ever states an intentional product reason to leave it disabled, nor any
architectural note explaining what blocked wiring it up. Per the audit's own
instruction not to guess: **the specific reason `LongTermPlanner` never
populates real values is INTENT NOT RECOVERABLE FROM CODE** — the *fact* that
it's unpopulated is B/D; *why nobody has populated it yet* is unknown.

## 3. Current longitudinal behavior — variance vs. progression, by axis

| Axis | Classification |
|---|---|
| Load | NOT IMPLEMENTED — no FF load ever changes across weeks; `loading` only ever changes via a variance-rotation check (inactive, §2) or CP.2's repair (reactive, same-week, not progressive) |
| Duration | NOT IMPLEMENTED (progression sense) — `targetDurationDomain` only ever changes via the same inactive rotation check |
| Density (work per time) | NOT APPROPRIATE AT THIS LAYER today — no domain concept currently represents "density" as distinct from duration + score; would require a new derived concept (§9) |
| Total work | NOT IMPLEMENTED — nothing tracks or targets a total-work trend |
| Skill complexity | NOT IMPLEMENTED — `skillDemand` is a fixed configured value, never adjusted by any existing mechanism (not even a variance check exists for it) |
| Movement difficulty | NOT IMPLEMENTED — movement function selection is deterministic/round-robin at generation time (§14), never escalated |
| Sustainable intensity | NOT IMPLEMENTED — `intensity` only ever changes via CP.2's reactive repair, never progressively |
| Repeatability (consistent output under load) | NOT IMPLEMENTED — no signal from `FunctionalFitnessResult` is ever consumed (§6) |
| Workout quality (completion/execution) | NOT IMPLEMENTED — `resultContext` (rx/scaled) exists in the domain but is never read by any programming decision |
| Work/rest structure | PARTIALLY REPRESENTED — `WorkoutFormat` encodes work/rest shape (e.g. `.emom`, `.intervals`) structurally, but format is fixed once at configuration time and never varies or progresses (§13) |

**Bottom line:** Functional Fitness today is exactly what the requester's own
hypothesis states — **a fixed baseline `Stimulus` plus local (same-week only,
CP.2-driven) corrections.** No form of longitudinal progression exists.

## 4. Stimulus field audit

| Field | Represents | Chosen by | Varies session-to-session? | Progresses week-to-week? | Influenced by completed performance? | CP.2-modifiable? | Changing it changes real generated content? |
|---|---|---|---|---|---|---|---|
| `targetDurationDomain` | Roughly how long the block should take | `LongTermPlanner` (Stage A, fixed) | Only via inactive variance check | No | No | No (CP.2's repair never touches this field — its only repair table is `.lowerBodyLoad`, §5 in CP.2's own doc) | Yes — feeds Stage-E validation and the estimated-duration/format coherence check |
| `intensity` | Overall effort classification | `LongTermPlanner` (fixed) | Only via CP.2's same-week pairing nudge (`.power`'s mapping) | No | No | Yes (pairing nudge only, never the cross-modality repair) | Yes — feeds `FunctionalFitnessStressProfileMapper`, and `AdaptationObjectiveStimulusMapping.objectivesServed` |
| `loading` | How heavy/loaded the movements are | `LongTermPlanner` (fixed) | Only via inactive variance check, or CP.2's repair | No | No | Yes (CP.2's ONLY repair-table field, §5) | Yes — the load-bearing dimension for `lowerBodyLoad`/`upperBodyLoad` |
| `movementModalityMix` | Which of weightlifting/gymnastics/metcon, and how many slots each | `LongTermPlanner` (fixed) | Only via inactive variance check (append-only) | No | No | No | Yes — directly drives Stage-C slot generation (`FunctionalFitnessProgramGenerator.movementSlots`) |
| `movementFunctions` | Which movement patterns (squat/hinge/pull/etc.) | `LongTermPlanner` (fixed) | Only via inactive variance check (append-only) | No | No | No | Yes — assigned round-robin to slots |
| `skillDemand` | How technically demanding | `LongTermPlanner` (fixed) | Never — no check of any kind touches this field | No | No | Yes (pairing nudge only, `.skillAcquisition`'s mapping) | Yes — feeds `objectivesServed`, but has zero effect on movement/slot generation today (no code reads it for anything except mapping/validation) |
| `systemicDemand` | Overall metabolic/systemic load | `LongTermPlanner` (fixed) | Never via any existing check | No | No | Yes (pairing nudge only, `.workCapacity`'s mapping) | Yes — the sole driver of `TrainingStressProfile.systemicDemand`/`.recoveryDemand` |
| `scoreType` | How the workout is scored | `LongTermPlanner` (fixed) | Never | No | No | No | Yes — must agree with `format`'s natural default or Stage-E validation fails (a real, already-discovered coupling) |

**Not every field is equally useful for longitudinal programming today**:
`movementModalityMix`/`movementFunctions` already have SOME automatic
variance machinery (inactive in production, but real); `skillDemand` has
literally zero mechanism touching it outside CP.2's narrow pairing nudge;
`loading`/`intensity`/`systemicDemand` are the three fields CP.2 already
proved *can* meaningfully change same-week outcomes, making them the most
plausible progression-axis candidates too (§9).

## 5. Exposure-history audit

`VarianceExposureRecord` (`ProgrammingDecisionEngine.swift:7-15`):

| Field | Classification |
|---|---|
| `date` | RECENCY ONLY (sort/window key) |
| `durationDomain` | VARIANCE EVIDENCE (what was prescribed, not how it went) |
| `loading` | VARIANCE EVIDENCE |
| `movementModalityMix` | VARIANCE EVIDENCE + a light FREQUENCY signal (used to compute `exposureCounts` in `adjustForModality`) |
| `movementFunctionsUsed` | VARIANCE EVIDENCE + FREQUENCY (same pattern in `adjustForMovementFunction`) |
| `skillDemand` | Stored but **never read anywhere** in the current 4 checks or CP.2's 2 checks — dead data at present |
| `wasHighIntensity` | Stored but **never read anywhere** — also dead data at present |

**Not represented at all:** PERFORMANCE (was the prescribed stimulus actually
achieved, comfortably or barely), PROGRESSION EVIDENCE (any trend across
sessions), RECOVERY/FATIGUE EVIDENCE (nothing FF-specific — readiness is
explicitly out of scope per CLAUDE.md rule 11 anyway).

**Is the missing information already derivable from existing `Session`/
`WorkoutResult`-family data, without new persistence?** Yes, largely —
`FunctionalFitnessResult.scoreValue`/`.scoreDirection`/`.resultContext` and
`FunctionalFitnessPerformedMovement.performedExercise`/`.performedReps`/
`.performedLoadKilograms`/etc. already exist, are already persisted (for an
entirely different reason — permanent training history, per
`FunctionalFitnessResult`'s own doc comment), and are simply never *read* by
the programming path. This strongly favors a **derived** history-builder
extension over any new persisted summary type (§6/§9).

## 6. Performance-feedback audit

Real, already-persisted feedback available per completed FF session, never
currently consumed for programming: `FunctionalFitnessResult.scoreValue`
(typed union: time/roundsAndReps/repetitions/calories/distance/load/
completedIntervals) + `.scoreDirection` (lower-is-better/higher-is-better/
completion-based) + `.resultContext` (`.rx`/`.scaled` — a real, already-
modeled Rx-vs-Scaled distinction); per-movement
`FunctionalFitnessPerformedMovement.performedExercise` (non-`nil` = a scaled
substitution occurred), `.performedReps`/`.performedCalories`/
`.performedDistanceMeters`/`.performedLoadKilograms` (each comparable against
its own `prescribedMovement`'s target). **No RPE/RIR field exists anywhere
in the Functional Fitness result model** — confirmed absent by direct search;
FF's only subjective/effort-adjacent signal is `resultContext`'s binary
Rx/Scaled flag, nothing finer-grained.

**Currently used for future programming: none of it.** Confirmed by direct
read of `FunctionalFitnessExposureHistoryBuilder` (§1/§5) — every field above
exists, is queryable, and is completely ignored by the one function that
builds the programming engine's history input.

**Narrowest missing feedback seam:** extend
`FunctionalFitnessExposureHistoryBuilder.build` (or add a small sibling
derived function) to also read `resultContext` (Rx vs. Scaled — a real,
already-modeled binary) and whether `performedMovements` contains any
non-`nil` `performedExercise` (a real, already-modeled substitution flag) per
completed session — the two coarsest, most honest signals the domain
already supports, corresponding respectively to "comfortably completed as
Rx" vs. "had to scale substantially." **`scoreValue` comparison across
sessions of the identical `Stimulus`+`format` shape is the only way to detect
"improved density/output at similar difficulty," but only when the SAME
workout (or a domain-recognized equivalent) repeats — see §10 for why this
requires distinguishing workout identity from stimulus, a real prerequisite.**
Signals like "tolerated longer work" or "increased load" are expressible once
`scoreValue`/`resultContext` feed a real progression axis (§9); "improved
skill" requires either `resultContext` trending Rx over Scaled at the same
`skillDemand`, or the substitution-per-movement signal shrinking over time —
both derivable from existing fields, no new field required.

## 7. Programming-horizon finding

The engine, exactly as it exists today, reasons over **at most the last N
completed sessions** where N is `VarianceConstraints`'s own configured window
per dimension (always `nil` in production, so effectively **zero** sessions
of real influence today). There is no concept of "this ProgramInstance's
arc" or "this strategic TrainingPhase's arc" anywhere in the FF programming
path — `exposureHistory` is a flat, unbounded list the caller happens to
build fresh from `instance.sessions` each time, and the engine itself only
ever looks at a `.suffix(window)` slice of it.

**Recommended smallest useful horizon for the next stage: a small, bounded
rolling window (on the order of the last 2-4 completed sessions, i.e.
roughly the last 1-2 tactical weeks at a typical frequency) — not a full
`ProgramInstance` history, and certainly not a `TrainingPhase`-spanning
mesocycle engine.** This matches the granularity `VarianceConstraints`
already assumes (its own fields are literally named `...WithinSessions`, not
`...WithinWeeks`/`...WithinPhase`), requires no new persisted concept (it's
still derived from `instance.sessions` exactly as today), and is sufficient
to express every progression/variance idea raised in §8/§9 without inventing
a mesocycle-periodization model this product has never asked for.

## 8. Purposeful-variance model

| Dimension | Encourage repeated exposure sometimes? | How soon does repetition become undesirable? | Exact-workout vs. broad-stimulus repetition treated differently? | Hard or soft? | Already represented by `VarianceConstraints`? |
|---|---|---|---|---|---|
| Duration domain | Yes — repeating a duration domain across 2-3 sessions is normal training, not roulette | Only after `avoidRepeatingDurationDomainWithinSessions`'s configured N identical in a row (coarse, count-based, no invented day-count) | Not distinguished today — the check only ever looks at `durationDomain`, never at whether it was the identical workout | Soft — a rotation preference, never a hard ban (existing code always still permits an unconfigured/undetected repeat) | Yes, fully — `avoidRepeatingDurationDomainWithinSessions` |
| Intensity | Yes | No existing check at all — `intensity` is untouched by any of the 4 original checks | N/A (no mechanism exists) | N/A | **No** — `VarianceConstraints` has no intensity field; CP.2's pairing nudge is the only thing that ever touches it, and only for a different reason (objective coverage, not variance-for-its-own-sake) |
| Loading | Yes — repeated moderate/heavy weeks are normal, e.g. a real strength-biased FF block | After N identical (`avoidRepeatingLoadingWithinSessions`) | Not distinguished | Soft | Yes |
| Modality mix | Yes — repeating a familiar weightlifting/gymnastics/metcon balance is fine | After N identical, then append (never remove) the single least-exposed-overall modality | Not distinguished | Soft (additive nudge, never a ban) | Yes |
| Movement function | Yes — repeating foundational patterns (squat, hinge) is desirable, not a flaw (§14) | After N identical, then append the least-exposed-overall function | Not distinguished | Soft | Yes |
| Skill demand | Yes — repeated exposure to a skill is how it's acquired (§9's `.skillAcquisition`) | No existing check | N/A | N/A | **No** |
| Systemic demand | Yes | No existing check | N/A | N/A | **No** |
| Format | Yes — repeating a format (e.g. two AMRAPs in a row) can be entirely appropriate if the underlying stimulus differs (WorkoutFormat's own doc comment already states this) | No existing check at all — format is fixed at configuration time, never varies | N/A — the domain already distinguishes format from stimulus at the type level (`WorkoutFormat` vs. `Stimulus`), it's simply never exercised for variance | N/A | No — `VarianceConstraints` has no format field |

No arbitrary physiological thresholds (no invented "never repeat within 7
days") are proposed anywhere here — every existing rule is already
count-based ("N consecutive identical sessions"), which is the correct,
already-established, coarse, explainable shape to extend.

## 9. Progression-axis model (TrainingOS-native — not copied from Hypertrophy)

| Axis | Classification | Reasoning |
|---|---|---|
| CAPACITY (longer sustainable duration / more work in the same duration) | REQUIRES SMALL DOMAIN EXTENSION | `targetDurationDomain` already exists and is coarse/categorical exactly like Hypertrophy's own RIR scale — a longitudinal check comparing recent `scoreValue`s at the same duration domain could justify "ready for `.medium` → `.long`," but this comparison doesn't exist yet |
| DENSITY (more work per unit time, less rest at same quality) | REQUIRES FUTURE INTEGRATION | No domain concept currently isolates "work density" from `scoreValue`+`format`+`resultContext` combined — would need a derived comparison across same-shape workouts, itself gated on the workout-identity finding (§10) |
| LOAD (heavier loading at comparable stimulus) | REQUIRES SMALL DOMAIN EXTENSION | `loading: LoadingClassification` is exactly as coarse as CP.1's own `LoadLevel` scale; a rule like "N consecutive Rx completions at this loading → eligible to progress one step" is a direct, small extension of the exact rotation shape `adjustForLoading` already has, just triggered by performance instead of repetition-count |
| SKILL (more demanding movement variant / less scaling) | REQUIRES SMALL DOMAIN EXTENSION | `resultContext == .scaled` vs. `.rx`, tracked over recent sessions at the same `skillDemand`, is a real, already-modeled signal (§6) — "N consecutive Rx at this skill demand → eligible to progress" mirrors the same shape again |
| REPEATABILITY (similar output with less degradation) | REQUIRES FUTURE INTEGRATION | Would need multiple attempts at directly comparable stimuli (workout-identity gated, §10) — not justified as a first stage |
| QUALITY (improved execution/completion at same intended stimulus) | SUPPORTED NOW, in its coarsest form | `resultContext` (Rx vs. Scaled) already IS a binary quality signal, already persisted, already readable without any change — the cheapest, most honest quality axis to wire in first |
| POWER (higher output where measurable) | REQUIRES FUTURE INTEGRATION | `scoreValue` comparison across attempts of a truly identical stimulus+format is required to detect this honestly — gated on §10 |

**No linear weight progression is proposed for Functional Fitness** — LOAD's
proposed mechanism is a categorical step (`LoadingClassification`'s own 4
cases), never a numeric percentage, consistent with CP.1/CP.2's entire
"coarse, categorical, no numeric scoring" discipline and CLAUDE.md rule 4.

## 10. Stimulus-vs-workout identity finding

The architecture currently distinguishes, cleanly, at the type level:
**broad stimulus** (`Stimulus`, 7 typed fields), **format** (`WorkoutFormat`,
a separate enum, explicitly documented as intentionally distinct from
stimulus), **movement exposure** (`movementFunctions`/`movementModalityMix`
on `Stimulus`, plus per-movement `FunctionalFitnessMovement.exercise`),
**loading exposure** (`Stimulus.loading`, plus per-movement
`loadKilograms`), and **duration exposure** (`Stimulus.targetDurationDomain`,
plus format's own `estimatedDurationSeconds`). **What the architecture
CANNOT currently distinguish is "exact workout identity"** — there is no
identifier or hash anywhere that says "this session's prescription is the
SAME named/shaped workout as that earlier session's prescription," only that
they happen to share some subset of `Stimulus`/`format` field values. Two
prescriptions with identical `Stimulus`+`format` values are, today,
*structurally* the same workout by coincidence of field equality, not by any
declared identity relationship — there is no `workoutTemplate`/`workoutName`/
`canonicalWorkoutID` concept anywhere in the FF domain (unlike
`BenchmarkDefinition`, which DOES have a stable identity, precisely because
retesting requires one).

**This is exactly the gap benchmark/retest already solved for its own narrow
case** (`BenchmarkDefinition`/`BenchmarkPerformanceProfile`) — but that
identity concept is scoped to benchmarks specifically, not to ordinary
generated programming. **Ordinary variance should be driven by broad
stimulus (already fully supported), never by exact-workout identity** — this
matches the requester's own framing exactly ("two different workouts can
train essentially the same stimulus"). **No architectural blocker exists for
future benchmark/retest work**: `BenchmarkDefinition`'s own identity model
already exists and is completely independent of ordinary FF programming's
stimulus-driven variance — nothing about extending ordinary variance/
progression (§8/§9) touches or constrains it. Benchmark/retest remains
correctly deferred; this audit finds no reason to build any part of it now.

## 11. Real 2-session/week longitudinal walkthrough — `muscleGainVariedMix`

Real mix: 3 Strength (`.primary`, `[.muscleGain]`) + 2 Functional Fitness
(`.supporting`, `[.workCapacity, .aerobicCapacity, .power]`, `frequency ==
2`) + 1 Running. Conceptual 6-week walkthrough, using only domain-valid
mechanisms (no hardcoded FF-A/FF-B template — the label is purely "whichever
session in `orderedTemplateSessions` materializes first/second this call,"
per CP.2's own finding):

- **Week 1 (Strength early, moderate stress):** Both FF sessions' fixed
  baseline stimulus is unmodified by CP.2 (Strength stress below `.high`).
  Session 2 sees Session 1's real programmed stimulus via
  `CurrentWeekFunctionalFitnessProgrammingContext` and, if Session 1 already
  served `.power`/`.workCapacity`, nudges toward the under-covered
  `.aerobicCapacity` (CP.2's existing, real mechanism). **What should
  influence week 2 and doesn't today:** whether the athlete completed both
  sessions Rx or scaled — real data (`resultContext`), completely unused.
- **Week 2 (identical structurally):** Because `VarianceConstraints` is
  all-`nil`, both sessions' baseline is byte-identical to week 1's baseline
  again (modulo CP.2's same-week pairing nudge, itself deterministic given
  identical inputs) — **the athlete would experience the exact same two
  workouts, week after week, forever**, unless CP.2's cross-modality
  discouragement happens to fire differently because Strength's real stress
  differs. This is the concrete, first-hand demonstration of "fixed baseline
  + local corrections" the requester asked this audit to confirm.
- **Weeks 3-4 (Strength peak week, real `.high` lowerBodyLoad):** CP.2's
  existing cross-modality repair correctly softens both FF sessions' loading
  one step — this is real, already-shipped, already-tested behavior, and
  correctly NOT something this audit proposes changing.
- **Week 5 (Strength deload, real lower stress):** CP.2's discouragement
  naturally doesn't fire (emergent from the lower real profile, not a
  special case) — both FF sessions revert to their unmodified configured
  baseline. **What SHOULD differ here and doesn't:** a deload week is a
  natural, coherent moment to intentionally push FF's own intensity/loading
  slightly, precisely because surrounding systemic demand is genuinely lower
  — but no longitudinal mechanism exists to recognize or act on that
  opportunity; only CP.2's reactive, same-week logic runs, and it has
  nothing to push TOWARD, only away from.
- **Week 6:** Identical structural story to week 2 — nothing about "5 weeks
  of consistent Rx completions" or "3 consecutive scaled attempts at the
  same skill demand" is visible anywhere, because none of it is captured.

**What mechanism is exposed as missing:** a longitudinal FF programming
context — computed BEFORE `FunctionalFitnessDecisionEngine.decide` is even
called, from the SAME kind of derived exposure-history read CP.1/CP.2 already
established as the right pattern — that can say "the last 2-3 completions of
this stimulus/dimension were solidly Rx; this component's own objectives
justify progressing loading/duration/skill-demand one categorical step," feeding
that as a new, additive engine input exactly like CP.2's own two new checks
did. This is squarely **(B): a small longitudinal FF programming context
before `FunctionalFitnessDecisionEngine`**, and the walkthrough shows the gap
concretely rather than abstractly.

## 12. FF-primary (`functionalFitnessFocusedMix`) vs. FF-supporting analysis

Real mix: FF `.primary`, `[.workCapacity, .aerobicCapacity, .anaerobicCapacity,
.power, .skillAcquisition]` (the true-GPP 5-objective product decision from
CP.2 §3) — no other component exists in this builder at all (confirmed:
`functionalFitnessFocusedMix` constructs exactly one component).

**`GoalPriority` and programming methodology, kept separate on purpose:**
`GoalPriority` (`.primary` here) currently means, and should CONTINUE to
mean, exactly one thing per its own CP.2-locked definition — *how protected
this component's stress budget is from encroachment by siblings.* This audit
finds **no honest justification** for `GoalPriority` to ALSO drive objective
coverage breadth, progression aggressiveness, allowed systemic demand, or
weekly variation breadth — those are `AdaptationObjectives`
count/composition questions (already real, already assigned per-builder,
§3 of CP.2's own design), not protection-level questions. Concretely: a
`.primary` FF component with 5 real objectives naturally attempts broader
coverage than a `.supporting` component with 3 — **but that's because it has
5 objectives, not because it's `.primary`.** A hypothetical `.supporting`
component that also happened to carry 5 objectives should behave identically
in coverage/aggressiveness terms; only its cross-modality protection (CP.2's
existing mechanism) would differ. **Recommendation: do not let priority
influence anything proposed in this document — objective count/composition
already fully explains the observed difference, and conflating the two would
reintroduce exactly the GoalPriority-vs-AdaptationObjective collapse CP.2's
own review explicitly rejected once already** (see CP.2 design doc's Step
2/§2 — a locked, settled precedent this audit deliberately does not
re-litigate, only extends).

## 13. WorkoutFormat finding

`format` is chosen exactly once, at `LongTermPlanner` configuration time
(Stage B, `LongTermPlanner.swift:1219`), and is **never varied by anything**
— confirmed by exhaustive grep: no check, no rotation, no CP.2 logic ever
reads or writes `FunctionalFitnessPrescriptionTemplate.format` after
generation. History does not track it as a first-class dimension (`
VarianceExposureRecord` has no format field at all). **Format should be
Stimulus-driven, not independently rotated** — its own doc comment already
states the reason correctly ("two workouts sharing a format can have
completely different stimuli"), meaning format is a structural CONSEQUENCE
of what stimulus/objective is being served this session, not an independent
variance axis of its own. **Repeating format IS desirable** when the
underlying stimulus differs (exactly the requester's framing) — this is
already possible today (nothing forces format to change), it's simply never
exercised because format never changes at all, coherent or otherwise. **A
real, concrete latent-incoherence risk found in this audit:** `format` is
fixed while `targetDurationDomain` is (inertly) capable of rotating —
`FunctionalFitnessStimulusValidator.estimatedDurationSeconds(for:)` implies a
real duration for a given format, and if duration-domain rotation were ever
activated without format also being reconsidered, a `.roundsForTime(rounds:
5, capSeconds: nil)` format could end up validated against a
`targetDurationDomain` it was never designed to match — **format and
duration-domain progression must be co-designed, not treated as
independent**, a real prerequisite for any future stage that activates
duration-domain variance/progression.

## 14. Movement-selection finding

Movement/exercise selection (`FunctionalFitnessMaterializer.materializeWeek`,
`:112-135`) resolves each `FunctionalFitnessMovementSlotTemplate` via
`SubstituteExerciseUseCase.resolvedExercise` (a GOING-FORWARD override, if
any) or else the first candidate satisfying the slot's typed constraints
(`allowedMovementFunctions`/`allowedModalities`) — **deterministic, and
completely independent of recent exposure, equipment, skill, scaling, or CP.2
constraints.** There is no longitudinal movement-VARIATION mechanism at all
today — the same slot always resolves to the same first-matching candidate,
every week, unless a manual substitution override exists. **This is
consistent with, not contrary to, the requester's own stated principle**:
repeating foundational movements (e.g. always resolving to the same
canonical squat-pattern exercise) is not automatically a defect — deliberate
novelty-for-its-own-sake in movement selection is explicitly the wrong
target. Any future movement-variation mechanism should be scoped carefully
against this same "repetition can be correct" principle, not built
reflexively.

## 15. Scaling finding

Scaling is currently **session-local and remembered, but not fed forward**:
`FunctionalFitnessPerformedMovement.performedExercise`/`.performedReps`/etc.
are real, persisted, and visible per completed result (queryable/editable via
whatever UI surfaces results), but — confirmed in §1/§6 — nothing in the
programming path ever reads them for a future decision. Given the locked
"scaling preserves stimulus" principle (unchanged, correctly untouched by
this audit): **what CAN be supported today, without inventing coaching
theory, is exactly the `resultContext` (Rx/Scaled) binary already modeled** —
a repeated `.scaled` result at the same `skillDemand` is a real, honestly
derivable signal. Whether the engine should then keep exposing that skill
demand (for continued acquisition), reduce complexity, change movement, or
preserve-but-alter-dose is **explicitly a future PRODUCT DECISION**, not
something the current domain model dictates one way or the other — flagged
as genuinely unresolved (§23), not answered here from generic coaching
theory.

## 16. Benchmark/retest architecture finding

**No architectural blocker exists.** `BenchmarkDefinition`/
`BenchmarkPerformanceProfile` already own a completely separate identity
concept from ordinary generated FF programming (§10) — nothing proposed
anywhere in this document (a bounded rolling exposure window, a Rx/Scaled-
derived progression signal, an intended-vs-adapted stimulus distinction)
touches, constrains, or would need to be revisited by future benchmark/retest
work. Confirmed by direct check: `FunctionalFitnessResult.benchmark`/
`.benchmarkPerformanceProfile` are already optional, already orthogonal
fields on the exact same result type this audit's proposed feedback seam
(§6) would read from — adding a coarse Rx/Scaled-aware history read does not
narrow, coalesce, or complicate the benchmark path at all. No reservation is
needed now.

## 17. CP.2 interaction / intended-vs-adapted finding — critical

**The gap is real, confirmed by direct inspection of
`FunctionalFitnessPrescription`:** it stores exactly **one** `stimulus:
Stimulus` field — the value is always `decision.nextStimulus`, i.e.
whatever `FunctionalFitnessDecisionEngine.decide` ultimately returned, AFTER
any of CP.2's checks (or the original 4, if ever active) have already run.
**The original, unadjusted baseline (`ffTemplate.stimulus`, what the
longitudinal engine — today, and any future longitudinal stage — would
consider "intended") is never separately persisted anywhere.**
`FunctionalFitnessExposureHistoryBuilder` (§1/§5) reads this single stored
value back as if it were straightforwardly "what this session's stimulus
was" — with no way to distinguish "the component's own longitudinal intent"
from "what CP.2 softened it to because of a real, temporary, same-week
cross-modality condition."

This matters exactly the way the requester's readiness analogy states: **an
adapted completion must never be misread as proof the ORIGINAL prescription
was what got trained.** Concretely, if a future longitudinal stage ever reads
exposure history to decide "has this component been consistently exposed to
`.power` at `.heavy` loading, therefore eligible to progress," a week where
CP.2 softened `.heavy` to `.moderate` (because of real, unrelated Strength
peak-week stress) would silently look identical to a week where the
component was simply never programmed toward `.power` at all — corrupting
any future progression signal that reads `loading`/`intensity` from history
without this distinction.

**This is found to be a real, load-bearing architecture requirement for the
next stage** — not merely a nice-to-have. No persistence is added in this
pass (per instruction); the finding is that **§20's recommended stage cannot
honestly build a progression signal from exposure history without this
distinction existing first** (see §19-21).

## 18. Source/product authority framing

Every semantic proposed in §8-§17 is a **TrainingOS PRODUCT DECISION**:
the count-based repetition-avoidance shape (already real, CP.2/pre-CP.2
precedent), the Rx/Scaled-derived quality signal (§9), the categorical
one-step load/skill progression shape (§9), the bounded rolling-window
horizon (§7), and the intended-vs-adapted distinction (§17) are all
TrainingOS's own design choices, informed by (never dictated by) general
strength-and-conditioning/CrossFit-adjacent principles the requester's own
message already names (recognizable progression, purposeful variation,
sparse retesting) — none of them are presented as, or should ever be
confused with, an authoritative external methodology this app is obligated
to reproduce.

## 19. Exact domain/code gaps

- No mechanism reads `FunctionalFitnessResult.scoreValue`/`.resultContext`/
  `FunctionalFitnessPerformedMovement`'s performed-vs-prescribed fields for
  any programming decision (§6).
- No distinction between the longitudinal/configured INTENDED stimulus and
  CP.2's FINAL adapted stimulus anywhere in the persisted model (§17).
- No workout-identity concept for ordinary (non-benchmark) generated content
  (§10) — acceptable, since ordinary variance should be stimulus-driven, not
  identity-driven, but worth naming explicitly as a design constraint, not an
  oversight.
- `WorkoutFormat` has zero variance/progression mechanism and zero coupling
  check against `targetDurationDomain` if that field's own (inactive)
  rotation were ever turned on (§13).
- `LongTermPlanner`'s one real production call site supplies an
  unexplained, all-`nil` `VarianceConstraints()` (§2) — not fixed in this
  pass per instruction, but is the actual root reason FF appears to have
  "no variance" in production today, when in fact 4 working checks already
  exist and are simply never fed real windows.

## 20. Smallest recommended next implementation stage

**(D) Preserve intended-vs-adapted Stimulus, as the necessary first step —
followed immediately by (C) performance-feedback-derived progression
evidence, as the smallest stage that is actually user-visible.** Framed as
one combined smallest stage per the instruction's own option (E): D is a
strict prerequisite for C to be trustworthy (§17), and C alone — without D —
would silently corrupt its own evidence the first time CP.2's cross-modality
check fires in the same week a progression-relevant history read happens.
**(A) activating `VarianceConstraints` in production** is explicitly NOT
recommended as the next stage: it would only ever produce *rotation*
(variance), never *progression*, and the requester's own core principle
draws exactly this line — "recognizable progression" is the stated goal,
not merely "less repetition." **(B) a small longitudinal programming context
before the decision engine** is the RIGHT SHAPE for how this ships (mirroring
CP.2's own successful pattern: compute a derived value before `decide()`,
pass it in as one more `ProgrammingDecisionInput` field, add one more check
to the existing fixed-priority chain) — but B is the mechanism, not a
standalone milestone; D+C together are what B's new check would actually
consume and act on.

**Concretely, the smallest real stage:** (1) preserve the pre-CP.2
"configured/intended" stimulus alongside the post-CP.2 "final" one — likely
as an additional field on `FunctionalFitnessPrescription`, or (preferred,
smaller) a derived recomputation, since `ffTemplate.stimulus` is already the
real configured baseline and is still reachable at persistence time without
needing a NEW stored value if the materializer is willing to record which
reason code fired (a case already: `.crossModalityDiscouraged`/
`.sameWeekComplementarityPreferred` vs. `.stimulusAsConfigured`/the original
4 variance codes) — this needs a careful audit at implementation time of
whether the reason code alone is sufficient evidence or a genuine second
stored `Stimulus` is required; (2) extend
`FunctionalFitnessExposureHistoryBuilder` (or a small sibling derived
builder) to also surface `resultContext` per completed session — no new
persisted field, purely a read of existing data; (3) add ONE new check to
`FunctionalFitnessDecisionEngine`'s existing chain that reads a small,
bounded rolling window (§7) of Rx/Scaled outcomes at a given
`loading`/`skillDemand` and, if consistently Rx, nudges that ONE field one
categorical step up (mirroring CP.2's own single-field, single-check
philosophy exactly) — reusing the identical shape CP.2 already proved twice.

## 21. Why this stage should come before alternatives

Activating `VarianceConstraints` (A) first would ship *more rotation*, which
the requester has explicitly distinguished from the actual goal
("progression," not "less repetition") — shipping A alone would not move the
product any closer to what was asked for, and risks being mistaken for
"solved" when it isn't. Building a full progression engine (C) without D
first would silently misattribute CP.2's own reactive softening as evidence
about the athlete's real capability — a genuine correctness risk, not a
theoretical one, given CP.2 is real, shipped, and already actively softening
real sessions today. D+C together are the smallest change that is both
CORRECT (doesn't corrupt its own evidence) and USER-VISIBLE (an athlete who
consistently completes Rx actually sees their program change), matching the
instruction's own selection criterion exactly.

## 22. Ranking vs. initial-window CP.2 parity

**INDEPENDENT.** The `StartPhaseUseCase`/initial-window cross-modality gap
(CP.2's own documented, deliberately-not-fixed limitation) is about WHICH
WEEKS receive cross-modality coordination; this audit's proposed stage is
about WHAT INFORMATION any given week's FF decision considers, regardless of
whether that week came from `StartPhaseUseCase` or `rollForward`. Neither is
a prerequisite for the other: fixing initial-window parity would not unlock
or simplify D/C, and building D/C does not require initial-window parity to
be fixed first (the same `FunctionalFitnessDecisionEngine.decide` call site
is shared by both paths already, so D/C's new check benefits both call sites
identically, working or not, the moment it exists). No ranking of "higher/
lower priority" is asserted between them since they solve genuinely
unrelated problems — the choice of which to build next is a scheduling
decision, not an architectural dependency.

## 23. Genuinely unresolved product decisions

- Whether a repeated `.scaled` result at the same `skillDemand` should keep
  exposing that skill demand, reduce complexity, change movement, or
  preserve-but-alter-dose (§15) — not answered here, flagged as a future
  product decision requiring explicit input.
- Whether the intended-vs-adapted distinction (§17) should be a genuine
  second persisted `Stimulus` field or can be honestly reconstructed from
  `reasonCode` alone — an implementation-time architectural choice, not
  resolved by this audit.
- Whether `.skillAcquisition`'s and `.workCapacity`'s progression signals
  (§9) should share one unified "consistently Rx" check or remain two
  logically separate checks (mirroring CP.2's own one-check-per-concern
  discipline) — a design choice for the implementation stage, not decided
  here.
- What the smallest honest DENSITY/REPEATABILITY/POWER signal would
  eventually look like once workout-identity (§10) is available for a
  future stage — explicitly deferred, not designed here.
- The unexplained `VarianceConstraints()` all-`nil` production gap's root
  cause (§2) remains genuinely unknown — flagged as INTENT NOT RECOVERABLE
  FROM CODE, not resolved.

---

## Design Lock — Intended vs. Final Stimulus (follow-up narrow audit)

**Status: DESIGN LOCK / AUDIT ONLY. Nothing implemented, committed, or pushed.** This section narrows the prior audit's D+C recommendation down to one specific, precise design lock, per instruction. Every claim below is re-verified directly against the real code as it stands now (not trusted from the section above without re-checking).

### 1. Exact current decision-engine ordering

`FunctionalFitnessDecisionEngine.decide` (`FunctionalFitnessDecisionEngine.swift:29-42`) is a **single flat "first match wins" list**, not a staged pipeline:

```swift
func decide(_ input: ProgrammingDecisionInput) -> ProgrammingDecisionOutput {
    if let output = adjustForCrossModalityConstraint(input) { return output }   // CP.2
    if let output = adjustForSameWeekComplementarity(input) { return output }  // CP.2
    if let output = adjustForDurationDomain(input) { return output }          // original variance
    if let output = adjustForLoading(input) { return output }                 // original variance
    if let output = adjustForModality(input) { return output }                // original variance
    if let output = adjustForMovementFunction(input) { return output }        // original variance
    return .stimulusAsConfigured
}
```

Every function reads the SAME `input.stimulusRequirements` (the raw configured baseline) independently — this is not a pipe where one check's output feeds the next check's input. Whichever check fires first **returns immediately**; every later check is skipped entirely for that call (confirmed by the engine's own doc comment: "If either [CP.2 check] fires, the original 4 checks do not run against the baseline this same call").

### 2. Proposed longitudinal/CP.2 responsibility boundary — a real refactor is required

**This flat-list design is structurally incompatible with the desired "longitudinal decides intent, then CP.2 adapts it" ordering**, and this is the single most important finding of this design lock. If a future longitudinal check were simply inserted into this same flat list:
- **Inserted before CP.2's checks:** if it fires, CP.2's checks never run at all this call (per the existing "return immediately" semantics) — a longitudinally-progressed stimulus (e.g. heavier loading) would ship WITHOUT ever being checked for cross-modality safety. A real correctness risk, not theoretical.
- **Inserted after CP.2's checks (where the original 4 variance checks sit today):** it would only ever fire when CP.2 has nothing to say — meaning longitudinal progression would never get a chance to matter whenever CP.2 has ANY same-week concern, even a mild pairing nudge. Backwards from "longitudinal decides intent first."

**Smallest required refactor:** split `decide()` into two literal, ordered phases instead of one flat list:
- **Phase 1 (intent):** the existing 4 variance checks (unchanged) plus any future longitudinal check, still "first match wins" among themselves, producing an **INTENDED** stimulus (defaults to the configured baseline if none fire — today's exact behavior, since no longitudinal check exists yet).
- **Phase 2 (adaptation):** CP.2's two existing checks (unchanged internally), but now run **against Phase 1's INTENDED output**, not the raw configured baseline directly — producing the **FINAL** stimulus.

This is not a new engine — it's reordering the existing 6 checks into two named phases and changing what CP.2's checks receive as their own "baseline" argument (Phase 1's result, not `input.stimulusRequirements` directly). Not implemented in this pass (Option 1, see §17) — named here as the necessary shape for whenever a longitudinal check is actually added.

### 3. Intended Stimulus definition

**INTENDED = the output of Phase 1** (§2) — the value after every longitudinal/variance-family check has had its chance to run, before CP.2 ever sees it. **Explicitly not merely `ffTemplate.stimulus`**: today, with no longitudinal check yet built, INTENDED happens to equal the configured baseline in every real case (since the original 4 variance checks are inert in production per `VarianceConstraints()` being all-`nil`) — but the *architectural* definition must be "Phase 1's output," so the representation remains valid once a real longitudinal check exists and can change it.

### 4. Final Stimulus definition

**FINAL = the output of Phase 2** (§2) — `decision.nextStimulus` exactly as it exists today, i.e. whatever CP.2's two checks decided (or, if neither fired, INTENDED unchanged). This is the **only** value currently persisted (`FunctionalFitnessPrescription.stimulus`, confirmed by direct read — exactly one `stimulus: Stimulus` field, `FunctionalFitnessPrescription.swift:20`).

### 5. Persistence decision and proof — intended Stimulus MUST persist as a genuine second field

**Reconstruction is rejected.** Tested against all 6 required scenarios:

- **(A) No CP.2 adaptation:** reconstructable today (`reasonCode == .stimulusAsConfigured` implies intended == final) — but this alone doesn't justify skipping persistence, since (D)/(E)/(F) below break it.
- **(B) Lower-body CP.2 loading repair:** `reasonCode == .crossModalityDiscouraged` proves final ≠ intended, but **does not encode what intended actually WAS** — reconstructing it would require re-deriving "what would `CrossModalityStimulusRepair.minimalRepair` have received as input," which means re-running the CURRENT repair logic backwards against the CURRENT `FunctionalFitnessStressProfileMapper` — exactly the "rerunning current engine logic against historical state" the instruction says to reject.
- **(C) Same-week FF complementarity:** identical problem — `.sameWeekComplementarityPreferred` proves a nudge happened, not what the pre-nudge value was.
- **(D) Future longitudinal adjustment before CP.2:** once a real longitudinal check exists, a session's `reasonCode` will only ever record ONE code (whichever phase last modified something) — with the CURRENT `ProgrammingDecisionOutput` shape (one `reasonCode`, §11), a longitudinal-then-CP.2-adapted session's reason code would show only the CP.2 code, silently discarding the fact that longitudinal programming ALSO acted. This is not a hypothetical — it is a structural consequence of `ProgrammingDecisionOutput` having exactly one `reasonCode` field today.
- **(E) Multiple future CP.2 adjustments:** same problem, compounded — reason codes are not a stack or list.
- **(F) Reason-code evolution across app versions:** even where a `reasonCode` DOES accurately describe what happened at the time, using it to *reconstruct a value* means trusting that the code's CURRENT semantics (e.g. what `.crossModalityDiscouraged` implies about the repair applied) still match what an OLDER app version's engine actually did — this is exactly "historical evidence changes meaning when the algorithm changes," the scenario the instruction explicitly forbids.

**Conclusion: `FunctionalFitnessPrescription` must persist BOTH `intendedStimulus` and `finalStimulus` as two genuine, independent `Stimulus` values, captured at materialization time, never recomputed later.** This is the smallest representation that satisfies "a completed historical session must remain interpretable correctly even after the programming engine changes in a future app version" — a snapshot, not a derivation. Classification: **PERSISTED STATE** (justified — this is the one case in this whole document where persistence-over-derivation is the correct call, precisely because the requirement is immutable historical evidence, not a live-recomputable fact).

### 6. Exact meaning of Rx/Scaled in production — decisive finding, corrects the prior audit

**Rx/Scaled has NO real assignment path in production today.** Traced exhaustively:
- `FunctionalFitnessResult.resultContext` defaults to `.rx` at initialization (`FunctionalFitnessResult.swift:47`, `resultContext: ResultContext = .rx`).
- The one real production construction site, `FunctionalFitnessExecutionViewModel.finish` (`:88-90`), constructs `FunctionalFitnessResult(scoreType:scoreValue:scoreDirection:)` **without ever passing `resultContext`** — meaning every real completed Functional Fitness session in the shipped app is `.rx`, unconditionally, by construction default, regardless of what actually happened.
- No UI element sets it to `.scaled` — `CompletedFunctionalFitnessDetail.swift`'s only reference to `resultContext` is a read-only `Text(resultContextLabel(...))` display, never a picker or editor.
- `FunctionalFitnessPerformedMovement` (the type that would prove a substitution/scaling occurred) is **never constructed anywhere in the real completion flow** — `addPerformedMovement` is never called from `FunctionalFitnessExecutionViewModel` or any real use case. The only place a `FunctionalFitnessResult` is ever built with an explicit `resultContext` is `SeedScenarios.swift` (demo/seed data, itself hardcoded to `.rx`).

**Rx does NOT currently certify anything** — "every prescribed movement/load/rep performed exactly as prescribed," "no substitution," "the athlete could complete it as intended" are all, today, simply **always true by construction default**, never actually verified or user-attested. This is a materially different (and more severe) finding than the prior audit's framing of Rx/Scaled as "real, already-modeled, usable evidence" — **it is real and modeled, but entirely unpopulated with real signal today.**

### 7. First-axis evaluation table

| Axis | Persisted signal honest? | Engine decision explainable? | Changing the field changes real generated content? | Verdict |
|---|---|---|---|---|
| LOAD | `performedLoadKilograms` exists but is never compared to anything (§8) | Would be, if the other two links held | **NO** — `Stimulus.loading` never reaches a real numeric prescribed load (§8) | **REJECTED** |
| CAPACITY/DURATION | N/A — chain breaks downstream regardless | Would be, if the other two links held | **NO, WORSE THAN INERT** — actively throws a Stage-E validation error if changed without co-changing `format` (§9) | **REJECTED — BLOCKED BY FORMAT COHERENCE** |
| SKILL | N/A — chain breaks downstream regardless | N/A | **NO** — `skillDemand` has zero effect on movement/slot generation anywhere (confirmed by exhaustive grep across the generator/materializer/validator — no contradicting evidence found) | **REJECTED**, per the instruction's own exclusion rule |
| QUALITY (Rx/Scaled) | **NO** — `resultContext` never varies from `.rx` in real production data (§6) | N/A — nothing to decide from a constant signal | N/A | **REJECTED FOR NOW** — not because the concept is wrong, but because the signal doesn't exist in production yet |

**No axis survives all three required links today.** This is a stronger, more conservative conclusion than the prior audit reached — it directly determines §17's recommendation.

### 8. LOAD end-to-end finding

Traced fully: `Stimulus.loading` → `FunctionalFitnessProgramGenerator.movementSlots` passes it ONLY as `FunctionalFitnessMovementSlotTemplate(loadingRole: stimulus.loading)` (`FunctionalFitnessProgramGenerator.swift:110`) — `loadKilograms` is never set (stays `nil`, its own default). `FunctionalFitnessMaterializer` reads `slotTemplate.loadKilograms` (always `nil`) straight into the final `FunctionalFitnessMovement.loadKilograms` (`FunctionalFitnessMaterializer.swift:127`) — **no numeric load is ever prescribed from `Stimulus.loading`, anywhere.** `loadingRole`'s own doc comment confirms this by design: "Informational for the generator/decision engine, not itself a hard substitution filter" (`FunctionalFitnessMovementSlotTemplate.swift:39-41`). Its only real consumer is `FunctionalFitnessStimulusValidator` (`:77-82`), which checks internal *consistency* (does the slot's `loadingRole` contradict the target stimulus's `loading`) — never exercise eligibility, never a real weight. **Changing `loading` today changes: `TrainingStressProfile` (CP.1/CP.2's own concern) and an internal validation consistency check — nothing the athlete would ever see or feel differently.** LOAD cannot be the first progression axis.

### 9. CAPACITY/DURATION end-to-end finding

`targetDurationDomain` is compared, at Stage-E validation, against `FunctionalFitnessStimulusValidator.estimatedDurationSeconds(for: format)` → `durationDomain(forEstimatedSeconds:)` (`:58-64`) — `format` is fixed once at `LongTermPlanner` configuration time and never varies (confirmed, §13 of the prior audit, re-confirmed here). **If `targetDurationDomain` were changed by a future check without `format` also being reconsidered, Stage-E validation's `matchesDuration` check would fail, and `FunctionalFitnessMaterializer.materializeWeek` throws `FunctionalFitnessMaterializationError.stimulusValidationFailed`** (`FunctionalFitnessMaterializer.swift:144-150`) — a real, active break, not a silently-ignored field. **Duration progression is correctly marked BLOCKED BY FORMAT COHERENCE**, and this design lock does not attempt to solve format generation.

### 10. QUALITY evidence finding

`resultContext` (Rx/Scaled) is the right SHAPE for a future qualification gate ("was this session's FINAL prescription actually met, comfortably, before considering any progression") rather than a progression axis of its own — this part of the prior audit's framing is correct and preserved. But **it cannot serve as a gate — or any evidence at all — until it has a real production assignment path**, which does not exist today (§6). This is a genuinely new, separate prerequisite this design lock surfaces, independent of the intended-vs-final gap.

### 11. Smallest derived performance-history value

**Not proposed for consumption in this stage** — since no axis has a complete honest chain (§7), there is nothing for a performance-history value to feed yet. For continuity of design (not to be built now): once `resultContext` has a real assignment path, the smallest such value would be a plain, non-persisted, per-session derived tuple — `(finalStimulus: Stimulus, resultContext: ResultContext)` — read fresh from `instance.sessions` exactly like `FunctionalFitnessExposureHistoryBuilder` already does, never a new persisted summary type. **DERIVED VALUE**, deferred.

### 12. Reason-code model recommendation

`ProgrammingDecisionOutput` (`ProgrammingDecisionEngine.swift:82-88`) has exactly ONE `reasonCode` field today — confirmed sufficient only because exactly one phase currently ever fires (CP.2's own two checks, mutually exclusive by the flat-list design). Once Phase 1/Phase 2 (§2) are separated, **two independent reason codes are needed**: one explaining why INTENDED differs from the configured baseline (today, always `.stimulusAsConfigured`, since no longitudinal check exists yet), and one explaining why FINAL differs from INTENDED (today's existing `.crossModalityDiscouraged`/`.sameWeekComplementarityPreferred`/`.stimulusAsConfigured`). **Smallest model: a paired before/after, not an array or history** — `FunctionalFitnessPrescription` gains `intendedReasonCode: FunctionalFitnessReasonCode` alongside `intendedStimulus`, and the existing `stimulus` field's meaning is clarified as `finalStimulus` with its own already-existing implicit reason (recoverable today from the materializer's own `decision.reasonCode`, which should now be understood as "the final-stage reason," not renamed). No new `FunctionalFitnessReasonCode` cases are required for this design lock itself — the existing vocabulary already covers both phases' current real cases; a future longitudinal check would add its own new, additive cases when it exists, not before.

### 13. Concrete end-to-end example — real `muscleGainVariedMix`, FF supporting

Real mix: 3 Strength (`.primary`, `[.muscleGain]`) + 2 Functional Fitness (`.supporting`, `[.workCapacity, .aerobicCapacity, .power]`) + 1 Running. Real week 4 (Strength's peak progressive week, RIR 1, real `lowerBodyLoad = .high`, reusing CP.1's own decisive fixture):

1. **Configured baseline:** FF's one fixed Stage-A `Stimulus` (medium duration, moderate loading, `[.squatLoaded, .gymnasticsPull, .monostructural]`) — identical every week, per `LongTermPlanner.functionalFitnessParameterCandidates`.
2. **Prior completed FF Sessions:** real, exist in `instance.sessions`, each `.completed` with a `FunctionalFitnessResult` whose `resultContext` is `.rx` — not because the athlete necessarily found it easy, but because **every real result defaults to `.rx` regardless of what happened** (§6).
3. **Persisted prescription/result evidence:** each prior `FunctionalFitnessPrescription.stimulus` (today, the single FINAL value only) plus its `FunctionalFitnessResult.scoreValue`/`.resultContext` (uninformative per §6).
4. **Derived performance-history value:** not built in this stage (§11) — there is no honest signal to derive yet.
5. **Longitudinal decision:** none exists yet (§2's Phase 1 has no real longitudinal check today) — Phase 1's output equals the configured baseline, unchanged.
6. **INTENDED Stimulus:** identical to the configured baseline this week (Phase 1 did nothing, since no longitudinal check and `VarianceConstraints` is inert).
7. **CP.2 sibling Strength stress:** real, `.high` `lowerBodyLoad`, composed via unchanged `SessionStressComposer` over the real materialized Strength sessions.
8. **CP.2 adaptation:** fires — `adjustForCrossModalityConstraint` finds the baseline's squat-loaded/heavy shape triggers `InterferenceAvoidanceRule.conservativeDefault`, and `CrossModalityStimulusRepair.minimalRepair` steps `loading` back one case (`.heavy → .moderate`), clearing the condition while still serving `.workCapacity`/`.aerobicCapacity`.
9. **FINAL Stimulus:** the repaired value — `loading = .moderate`, everything else unchanged from INTENDED.
10. **Generated workout consequence:** movement slots, format, and any prescribed content are unaffected by the `loading` change itself (§8) — the only real-world difference this repair produces is what `TrainingStressProfile`/CP.1's interference check sees; the actual athlete-facing workout content is otherwise identical to what INTENDED would have produced.
11. **Athlete result:** completes the session; `FunctionalFitnessResult` is constructed with `resultContext` defaulting to `.rx` regardless of actual difficulty (§6) — **this is not evidence of anything, today.**
12. **What the next week is allowed to infer:** **nothing new.** Without a real Rx/Scaled signal and without a persisted INTENDED-vs-FINAL distinction, next week's FF materialization has exactly the same information as this week's did — the configured baseline, unchanged, forever, exactly as the prior audit's own walkthrough already demonstrated. This example additionally proves WHY: even if intended/final persistence existed today, there is still no performance signal (§6) to act on it with — both gaps are real and independent.

### 14. Stress-test results

| Case | Model holds? |
|---|---|
| (A) FF-only primary program | Yes — INTENDED/FINAL persistence is per-session, independent of mix composition; no special case |
| (B) FF supporting Hypertrophy | Yes — identical mechanism, `.primary` sibling is Hypertrophy instead of Strength, no difference to the representation |
| (C) CP.2 does not adapt | INTENDED == FINAL, both persisted identically, `intendedReasonCode == .stimulusAsConfigured`, trivially correct |
| (D) CP.2 DOES adapt | INTENDED and FINAL genuinely differ and both are captured as real snapshots, never re-derived |
| (E) athlete completes Rx | Currently uninformative (§6) but not misleading — the model doesn't claim evidence it doesn't have |
| (F) athlete completes Scaled | **Cannot occur in real production today** (§6) — the model is honest about this: it doesn't fabricate a distinction the app doesn't yet let the athlete report |
| (G) movement substitution exists | Same as (F) — `FunctionalFitnessPerformedMovement` is never populated in the real flow, so this case cannot occur today either; the model does not pretend otherwise |
| (H) same-week complementarity changes final | Same as (D) — `.sameWeekComplementarityPreferred` becomes the final-stage reason code, INTENDED unaffected by it (complementarity is a Phase 2/CP.2 concern, not longitudinal intent) |

The evidence model remains truthful in every case specifically BECAUSE it does not claim more than the domain currently supports (cases F/G honestly cannot occur yet, and the model doesn't pretend they can).

### 15. Exact files/types the next stage (Option 1) would change

- `FunctionalFitnessPrescription.swift` — add `intendedStimulus: Stimulus` and `intendedReasonCode: FunctionalFitnessReasonCode` (new persisted fields, additive); rename no existing field (keep `stimulus` as the FINAL value to avoid an unnecessary migration of meaning, or rename to `finalStimulus` for clarity — an implementation-time naming choice, not decided here).
- `FunctionalFitnessDecisionEngine.swift` — restructure `decide()` into the two named phases (§2); no behavior change for any input where no longitudinal check exists yet (there isn't one), so every existing test's expected output is unchanged.
- `ProgrammingDecisionOutput` (`ProgrammingDecisionEngine.swift`) — add a second reason code field (or produce two `ProgrammingDecisionOutput`-shaped values, one per phase, at the materializer's call site — implementation-time choice).
- `FunctionalFitnessMaterializer.swift` — persist both values onto the new prescription fields at materialization time.
- No change to `LongTermPlanner.swift`, `CrossModalityStimulusRepair.swift`, `CurrentWeekFunctionalFitnessProgrammingContext.swift`, `AdaptationObjectiveStimulusMapping.swift`, `FunctionalFitnessStressProfileMapper.swift`, `FunctionalFitnessProgramGenerator.swift`, `WorkoutFormat.swift`, or any source-authority file.

### 16. Tests the next stage would require

Persistence round-trip of both `intendedStimulus`/`intendedReasonCode` and the existing final stimulus; a migration test confirming the additive fields trigger no schema bump; a test proving `intendedStimulus == finalStimulus` whenever neither CP.2 check fires (case A/§14); a test proving they genuinely differ and both are captured as real, independent values when a CP.2 check does fire (cases B/C/D/§14, reusing CP.1/CP.2's own real fixtures); a regression test confirming the two-phase restructuring produces byte-identical `nextStimulus`/`reasonCode` output to today's flat-list engine for every existing test case (since no longitudinal check exists yet, Phase 1 must be a no-op relative to today's behavior); full existing suite unchanged.

### 17. Recommendation: **OPTION 1**

**OPTION 1 (intended-vs-final representation boundary only, no progression behavior) is the correct choice** — Option 2 is explicitly disqualified by this audit's own criterion: no progression axis (LOAD, CAPACITY/DURATION, SKILL, QUALITY) has a complete, honest, real production chain today (§7). LOAD and DURATION are structurally broken links (one inert, one actively error-throwing); SKILL has zero real effect; QUALITY's underlying signal (`resultContext`) never varies in real production data at all. Building Option 2 now would mean inventing evidence the domain does not actually produce — exactly what this whole design-lock process exists to prevent.

### 18. Genuinely unresolved product decisions remaining

- **Rx/Scaled has no real assignment mechanism** — a genuinely new prerequisite this design lock surfaces, separate from and in addition to the intended-vs-final gap: some future UI/product flow must let an athlete honestly report scaling/substitution before `resultContext` (or the substitution-tracking `FunctionalFitnessPerformedMovement` machinery) can be real evidence for anything. Not designed here — out of this design lock's narrow scope, but load-bearing for whatever future stage attempts Option 2's QUALITY axis.
- Whether `intendedStimulus`/`finalStimulus` should be named exactly that, or something else matching a future naming convention — an implementation-time choice.
- Whether `ProgrammingDecisionOutput` should literally return two values, or the materializer should call the engine twice (once per phase) — an implementation-time choice, not resolved here.
- Every item already flagged unresolved in the prior audit section above (the muscle-gain/retention direction concept, aggregate 3+-modality interference, `VarianceConstraints` production-default gap, `CrossModalityExposureSummary`) remains unresolved and is unaffected by this narrower lock.
- `VarianceConstraints` remains explicitly deferred/unactivated in this stage, per instruction — confirmed untouched (no diff to `LongTermPlanner.swift` or any production file).
- The CP.2 initial-window/`StartPhaseUseCase` limitation remains explicitly deferred/unfixed in this stage, per instruction — confirmed untouched.

---

## FF.L1 Implementation Report — Intended vs. Final Stimulus Foundation

**Status: IMPLEMENTED (uncommitted). Not CP.3 — a separate, narrow foundation stage. CP.2 remains closed, unmodified, at `bca43e2ff47d21d8703275d06354af6a086f0d45`.**

### Semantic pipeline (locked)

CONFIGURED BASELINE → FF INTENT SHAPING (Phase 1 — today: the 4 original variance checks only, always a no-op in production; future: any real longitudinal-programming/purposeful-variance check, internal ordering deliberately undecided) → **INTENDED STIMULUS** → CP.2 ADAPTATION (Phase 2 — the cross-modality/same-week checks, unchanged) → **FINAL STIMULUS** → materialization → performance result.

**Explicit semantic note — Phase 1's current contents do not lock future variance-vs-progression precedence.** Phase 1 today happens to contain only the 4 original variance checks (real, but always inert in production, per `VarianceConstraints()` being all-`nil`). This is accepted as the honest, repository-native representation of CURRENT behavior — it is **not** a design decision about how a future real longitudinal-progression check and a future real purposeful-variance check should relate to each other once both exist. **Variance != progression remains a locked product principle** (the prior audit's own core finding): nothing about today's Phase 1 ordering implies progression should run before variance, after variance, replace it, or be checked independently of it. When real longitudinal programming is introduced, its relationship to purposeful variance — precedence, mutual exclusivity, or some other composition — must be designed explicitly, as its own decision, at that time; it must never be inferred or defaulted from the fact that the 4 variance checks happen to occupy Phase 1 alone today.

### Persistence semantics (exact, as implemented)

`FunctionalFitnessPrescription` (`Domain/Entities/FunctionalFitnessPrescription.swift`):
- `stimulus: Stimulus` — kept as the FINAL value, unrenamed (the smaller, safer diff — every real consumer already wanted FINAL and already read this field name: `FunctionalFitnessExecutionViewModel`, `FunctionalFitnessExposureHistoryBuilder`, every test). Documented explicitly in its own doc comment as FINAL.
- `intendedStimulus: Stimulus?` — new, additive, optional. `nil` for every prescription persisted before this field existed (a genuinely unknown historical fact, never fabricated as equal to `stimulus`); a real, non-nil snapshot for every prescription materialized from this point forward.
- No `intendedReasonCode` was added — `stimulus`'s existing (unnamed/unpersisted-as-a-separate-field-but-implicit) reason semantics continue to mean "why FINAL is what it is," unchanged. `FunctionalFitnessProgrammingDecision` (below) carries a transient `intendedReasonCode` for internal explainability, never persisted.

### Engine responsibility boundary (exact, as implemented)

`FunctionalFitnessDecisionEngine` (`Engines/FunctionalFitnessDecisionEngine.swift`) now exposes:
```swift
func decideWithIntent(_ input: ProgrammingDecisionInput) -> FunctionalFitnessProgrammingDecision {
    let intended = intentPhase(input)              // Phase 1: original 4 checks, unchanged
    var adaptationInput = input
    adaptationInput.stimulusRequirements = intended.nextStimulus
    let final = adaptationPhase(adaptationInput) ?? intended   // Phase 2: CP.2's 2 checks, unchanged, against INTENDED
    return FunctionalFitnessProgrammingDecision(
        intendedStimulus: intended.nextStimulus, intendedReasonCode: intended.reasonCode,
        finalStimulus: final.nextStimulus, finalReasonCode: final.reasonCode,
        confidence: final.confidence, inputsSummary: final.inputsSummary
    )
}
func decide(_ input: ProgrammingDecisionInput) -> ProgrammingDecisionOutput {
    let decision = decideWithIntent(input)
    return ProgrammingDecisionOutput(nextStimulus: decision.finalStimulus, reasonCode: decision.finalReasonCode, confidence: decision.confidence, inputsSummary: decision.inputsSummary)
}
```
`decide(_:)` is preserved, unchanged in signature and behavior, delegating to `decideWithIntent` — one real decision flow, never two that could diverge. `ProgrammingDecisionInput.stimulusRequirements` changed from `let` to `var` to support constructing Phase 2's own input with Phase 1's output substituted in.

**Behavior proof:** in every real production case (`VarianceConstraints()` all-`nil`), Phase 1 is a no-op (`intended == input.stimulusRequirements`, `reasonCode == .stimulusAsConfigured`), so Phase 2 evaluates against the identical raw baseline it always did — FINAL is byte-identical to pre-FF.L1 behavior. In every existing CP.2 test (which never sets non-nil `VarianceConstraints`), the same holds. In every pre-CP.2 variance-only test (which never sets `protectedSiblingStressProfilesThisWeek`/`currentWeekContext`), Phase 2 is a guaranteed no-op (its own checks guard on those being non-empty), so FINAL == INTENDED == whatever Phase 1 produced, matching old behavior exactly. No existing test combines both — confirmed by direct audit of every real test fixture — so this refactor is behavior-preserving for every case that exists today, by construction, not by coincidence.

### CurrentWeekFunctionalFitnessProgrammingContext uses FINAL

`FunctionalFitnessMaterializer.materializeWeek` calls `currentWeekContext.record(stimulus: decision.finalStimulus)` — confirmed against CP.2's own same-week pairing contract: a sibling session must coordinate against what was ACTUALLY programmed after adaptation, never pre-adaptation intent. Proven by `testCurrentWeekContextRecordsFinalStimulusNeverIntended` and the real-materialization test `testRealMaterializationPersistsDistinctIntendedAndFinalAndSessionTwoCoordinatesAgainstFinal`.

### Exposure history uses FINAL

`FunctionalFitnessExposureHistoryBuilder` reads `prescription.stimulus` — unchanged, still FINAL, never switched to `intendedStimulus`.

### Performance evidence / progression / VarianceConstraints / StartPhaseUseCase parity — all remain deferred, unchanged

No Rx/Scaled work, no `FunctionalFitnessPerformedMovement` population, no progression axis, no `VarianceConstraints` activation (zero diff to `LongTermPlanner.swift`), no `StartPhaseUseCase` fix — all exactly as instructed, all still exactly the gaps the prior audit sections already documented.

### Files changed

New: `TrainingOSTests/FunctionalFitnessIntendedVsFinalStimulusTests.swift` (8 tests). Modified: `FunctionalFitnessPrescription.swift`, `FunctionalFitnessDecisionEngine.swift`, `ProgrammingDecisionEngine.swift`, `FunctionalFitnessMaterializer.swift`, `TrainingOS.xcodeproj/project.pbxproj`. Zero diff: `LongTermPlanner.swift`, every source-authority file, `ConcurrentScheduler.swift`, `SchedulingPipeline.swift`, `StartPhaseUseCase.swift`, `FunctionalFitnessResult`/`FunctionalFitnessPerformedMovement`.

### Verification record

8/8 targeted FF.L1 tests pass; 24/24 existing CP.2 tests pass unchanged; full suite independently re-run at checkpoint: **1013 passed / 2 skipped / 0 failed**, exit code 0, zero failures; clean `build-for-testing`, no new warnings; zero CoreData/SwiftData/migration warnings; source-authority diff zero; exactly one `SchedulingPipeline.propose` call site (`RollTacticalWindowUseCase.swift:231`).

### Remaining deferred prerequisites for real FF progression (unchanged from the prior audit)

Rx/Scaled has no real production assignment path; no progression axis (LOAD/CAPACITY-DURATION/SKILL/QUALITY) has a complete honest chain; `VarianceConstraints` stays unactivated; `CrossModalityExposureSummary` remains deferred; the muscle-gain/retention direction concept remains deferred; aggregate 3+-modality interference remains unresolved; the CP.2 initial-window/`StartPhaseUseCase` limitation remains unfixed.

---

## STOP

**Design / audit only for everything above the FF.L1 Implementation Report; that section reflects real, uncommitted implementation work.** No production Swift file outside the narrow FF.L1 boundary was modified. CP.2 remains
closed, unmodified, at commit `bca43e2ff47d21d8703275d06354af6a086f0d45`.
`TRAINING_MIX_CONCURRENT_PROGRAMMING_DESIGN.md` was not edited. Nothing has been committed or pushed.
