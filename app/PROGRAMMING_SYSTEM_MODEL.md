# Programming System Model

Proposed architecture for representing training methodologies generically,
based on `PROGRAM_LOGIC_SPEC.md` and `PROGRAM_FAMILY_MATRIX.md`. This is a
specification, not an implementation — nothing here is built yet (Stage 4).

## 1. Where this sits relative to what already exists

TrainingOS already has, from the Stage 1–2 foundation:

- `ProgramDefinition` / `ProgramInstance` / `TrainingWeek` entities (structural,
  currently near-empty — a definition just holds a name and a list of
  weeks with an `isDeload` flag)
- A `ProgressionEngine` protocol and one concrete implementation
  (`DoubleProgressionEngine`) that is pure, deterministic, and operates on
  plain value types (`ProgressionInput` → `ProgressionOutput` with a reason
  code)

**`ProgrammingSystem` is a new layer that sits above `ProgressionEngine`,
not a replacement for it.** A `ProgrammingSystem` knows a methodology's full
rule set — which progression rule types it uses, with what parameters, for
which slots — and is responsible for producing the *structured rules*
inside a `ProgramDefinition`. The `ProgressionEngine`(s) remain the pure
functions that evaluate one rule against one set of inputs and return one
recommendation. A `ProgrammingSystem` is what decides *which* rule and
*which* parameters apply to *this* prescription; the engine still does the
actual arithmetic.

```
ProgrammingSystem            "what methodology, what rules, what parameters"
        |
        v
ProgramDefinition            "one concrete configuration of that methodology"
   -> TrainingWeek[]
        -> ExercisePrescription[] (each carrying a ProgressionRule reference)
             -> SetPrescription[]
        |
        v
ProgramInstance               "this user's execution of that definition"
        |
        v
ProgressionEngine.recommend() "the pure function that turns a rule + a
                                Performance Profile + a latest result into
                                today's actual number"
```

## 2. The core problem this solves

Every rule in `PROGRAM_LOGIC_SPEC.md` has the same shape: *a small formula
with a few numeric parameters*, e.g. `weekN = week1 × multiplier` or
`sets = priorSets + pairedRating`. If TrainingOS hardcodes these as Swift
code per program, every new imported program needs new code. If it stores
only the *computed numbers* (a flattened week-by-week table), it violates
the handoff's standing rule that imported program logic must survive as
*executable rules*, not flattened workouts, and it can never explain a
recommendation with a reason code.

The fix: every prescription in a `ProgramDefinition` carries a
**`ProgressionRule`** — a small, named, parametrized rule — instead of (or
alongside) a literal target. The `ProgressionEngine` layer gains one
handler per rule *type* (not per program), and `ProgrammingSystem`s are
just named, reusable bundles of rule-type + parameter choices.

## 3. `ProgressionRule` — the structured-rule vocabulary

A closed set of rule *types*, each with its own parameters, sufficient to
express every mechanic found in the source material:

| Rule type | Parameters | Source-material examples |
|---|---|---|
| `rmBasedWeekOneLoad` | `rmType` (5RM/8RM/10RM/etc.), `factor`, `roundingIncrement` | Family A Week 1 (`10RM×0.85`), Family B/C Week 1 (`RM×0.95` or `×0.7`/`×0.85` backoff) |
| `fixedMultiplierOfWeekOne` | `weekMultipliers: [Double]` (one per week, keyed to the Week-1 cell, not compounding) | The `×1.05/1.075/1.1` pattern, identical shape across every family |
| `autoregulatedSetCount` | `baselineSets`, `pairedSlotReference`, `ratingScale` | Family A/B/C's `sets = priorSets + pairedRating` |
| `fixedSetSchedule` | `setsByWeek: [Int]` | Family B's non-autoregulated 8RM accessories; Family C's dead-rating-input rows |
| `repGoalSchedule` | `targetsByWeek: [RepGoal]` (a rep count, an RIR-style "X/fail," or a fixed text like "Triples") | Every family's Week1–4 rep-goal row |
| `deloadWeightBySchedulePosition` | `positions: [ScheduleSlot: Factor]` | The full-weight/half-weight day-boundary split found in every family |
| `deloadRepInstruction` | `fraction` (e.g. 1/2, 2/3), `roundingDirection` | The always-text, never-computed deload rep rule |
| `linkedResultReference` | `sourceSlotReference`, `fractionOfSourceResult` | Family C's Friday backoff exercise ("1/2 Monday's" actual logged reps) |

Every one of these is a **pure data description** — no code branches on
"which program is this." The `ProgressionEngine` layer adds one evaluator
per rule type; `ProgrammingSystem`s just choose which rules, with which
parameters, go on which `ExercisePrescription`. This is what "the engine
must understand the meaning of the rule, not the spreadsheet coordinates"
(handoff rule 3) means concretely.

`pairedSlotReference` / `sourceSlotReference` need to name a slot
declaratively (e.g. "the other slot in this same day sharing category X,"
or "the slot most recently completed before this one") rather than a
literal cell address — this is the translation step from "M35" to a
domain-level reference, and it's where a chunk of the remaining
implementation risk lives (see `OPEN_PROGRAMMING_QUESTIONS.md` §10).

## 4. `ProgrammingSystem` — named bundles, not new entity types

A `ProgrammingSystem` is an identifier plus a rule-selection policy — it is
**not** a new persisted entity type with its own bespoke fields. Two are
justified by the source analysis:

### `HypertrophyProgrammingSystem`
Parameters: `dayCount` (3–6), `split` (full_body / legs / arms_shoulders /
back_chest / ...), `phaseSet` (which of Basic Hypertrophy / Metabolite
Focus / Resensitization to include, and in what order — see
`OPEN_PROGRAMMING_QUESTIONS.md` §2 for whether that order is even settled),
`exerciseCategoryOverrides` (e.g. the legs-only "Heavy" 1.0× exception,
modelled as an opt-in override on any category rather than hardcoded to
one split — see `PROGRAM_FAMILY_MATRIX.md` §1).

Explicitly **not** a parameter: an experience-level/novice flag. The
source material doesn't support one (`PROGRAM_FAMILY_MATRIX.md` §2). If
product direction later wants a real novice ruleset, add the parameter
then, backed by real evidence — don't add it speculatively now.

### `PowerliftingProgrammingSystem`
Parameters: `rmBasisMode` (uniform 10RM, or per-slot 5RM/8RM assignment),
`dayCount` and `dayMap` (which category trains which day), `perSlotFactor`
(standard vs. backoff/Triples factor per session), `deloadWeightSchedule`
(which days get which reduction factor), `deloadRepFraction` (which days
get which fraction). This single system represents both Family B and
Family C by parameter choice alone (`PROGRAM_FAMILY_MATRIX.md` §3), and
`Strength_Program_1`/`2` prove real users successfully reconfigure exactly
these parameters without touching engine code.

Both systems' `ProgressionRule` vocabulary is the *same* table from §3 —
they differ only in which rules they attach and what parameters they use.
This is deliberate: a future `EnduranceProgrammingSystem` or
`FunctionalFitnessProgrammingSystem` should reuse the same rule vocabulary
wherever the mechanic is actually the same shape (e.g. a deload is still
"a schedule-position-keyed weight reduction" no matter the modality), and
only add new rule types for mechanics that are genuinely new (pace zones,
round-based scoring, etc. — out of scope until that source material
arrives, see §5).

## 5. `ProgramDefinition` vs. `ProgramInstance` — restated, not changed

This distinction is already locked (`CLAUDE.md`, `ARCHITECTURE.md`) and
nothing here weakens it:

- **`ProgramDefinition`** = the reusable methodology: which
  `ProgrammingSystem` produced it, its parameter choices, and its
  `TrainingWeek`/`ExercisePrescription`/`SetPrescription` structure with
  `ProgressionRule`s attached. Contains **zero** user performance data —
  the same invariant already enforced by the Stage 1–2 delete-rule matrix
  applies unchanged; `ProgressionRule` parameters are methodology facts
  ("this program uses a 0.85 Week-1 factor"), never a specific user's
  numbers.
- **`ProgramInstance`** = one user's execution: dates, phase association,
  `Session`s, substitution choices, starting recommendations, progression
  state. Reads `ProgramDefinition`'s rules but writes nothing back into it.

## 6. Strict vs. Adaptive readiness

Per the existing `AdherenceMode` enum (`strict` | `adaptive`, already on
`ProgramDefinition`): `ProgrammingSystem`s generate `STRICT` definitions in
V1 — the imported/generated rule set runs exactly as configured. Nothing in
the `ProgressionRule` design above assumes immutability, though:
`ADAPTIVE` would mean the *engine* is permitted to substitute a different
parameter value or rule instance for one that isn't working (e.g. swapping
`autoregulatedSetCount`'s baseline if a user consistently maxes it out),
while preserving the rule *type* and the methodology's intent. Because
rules are already data (not code), an adaptive layer can be added later as
a policy that edits `ProgressionRule` parameters on a `ProgramInstance`'s
copy of the structure, without a schema migration. Not implemented in this
pass — flagged here only to confirm the data model doesn't block it.

## 7. Architectural proof — no special-case entity types required

Per the Stage 3A brief's requirement to show (not implement) that the
model above represents every required case using the *same* entity types:

| Required case | How it's represented | New entity type needed? |
|---|---|---|
| 3-day hypertrophy | `ProgramDefinition{system: Hypertrophy, params: {dayCount: 3, split: X}}` | No |
| 4-day / 5-day / 6-day hypertrophy | Same definition shape, `dayCount` changed | No |
| Specialization hypertrophy (arms/shoulders, legs, back/chest) | Same shape, `split` changed; legs' "Heavy" exception is an `exerciseCategoryOverride`, not a new type | No |
| Novice hypertrophy | Same shape — no parameter exists for this today because the evidence doesn't justify one (§4); if it's ever real, it's another parameter value, not a new type | No |
| Strength/powerlifting | `ProgramDefinition{system: Powerlifting, params: {...}}` — different `ProgrammingSystem`, identical entity types (`TrainingWeek`, `ExercisePrescription`, `SetPrescription`) | No |
| Different RM-based load models (5RM/8RM/10RM) | `rmBasedWeekOneLoad.rmType` parameter value on the `ProgressionRule` attached to each `ExercisePrescription` — a mixed-basis program (Family B) simply assigns different `rmType` values per slot | No |

Every case above is a **parameter or rule-attachment difference on the
same four entity types** (`ProgramDefinition`, `TrainingWeek`,
`ExercisePrescription`, `SetPrescription`) plus the new `ProgressionRule`
value type. Nothing in the source analysis required inventing a
program-family-specific entity — the closest candidate (a distinct
"novice" entity or flag) was explicitly tested against real files and
rejected for lack of evidence (`PROGRAM_FAMILY_MATRIX.md` §2).

## 8. What's explicitly deferred

- Exercise-slot architecture (slots vs. hardcoded exercises) — see
  `PROGRAM_GENERATOR_SPEC.md` §4, which covers this in the generation
  context; the canonical-exercise mapping itself is `PROGRAM_LOGIC_SPEC.md`-
  adjacent but detailed in `OPEN_PROGRAMMING_QUESTIONS.md` §10 since several
  mappings are genuinely uncertain.
- Actually implementing any `ProgressionRule` evaluator in
  `Engines/` — that's Stage 4, gated on this document's review.
- Endurance/functional-fitness `ProgrammingSystem`s — no source material
  yet (`PROGRAM_FAMILY_MATRIX.md` §4); only the *interface shape* they'd
  need is worth noting now: they'd need new `ProgressionRule` types (pace
  zones, round/time-based scoring) but the same `ProgrammingSystem` →
  `ProgramDefinition` → `ProgramInstance` skeleton.
