# Programming System Model

Proposed architecture for representing training methodologies generically,
based on `PROGRAM_LOGIC_SPEC.md` and `PROGRAM_FAMILY_MATRIX.md`. This
remains a specification for the concrete `ProgrammingSystem` engines
themselves — nothing in `HypertrophyProgrammingSystem`/
`PowerliftingProgrammingSystem`/etc. is built yet (Stage 4).

**Stage 3C implementation note:** three of this document's proposals now
have real, implemented supporting types in the domain model, ahead of any
concrete engine — see `STAGE3C_IMPLEMENTATION_REPORT.md` for the full
detail. §5.1's `TrainingPhase` primary/secondary composition is
implemented (`TrainingPhase.primaryInstance`/`.secondaryInstances`,
`ProgramInstance.priority`). The generic `BlockPrescription`/`BlockResult`
carrier types this document's §3 rule vocabulary would eventually populate
are implemented (`PRESCRIPTION_RESULT_MODEL_REVIEW.md`'s design, built).
§5.2's structural `pairedSlotReference` is **not** implemented by Stage
3C — it remains exactly the proposal below, unaffected; it belongs to
Stage 4's concrete engine work, not to Stage 3C's cross-modality domain
generalization.

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
| `autoregulatedSetCount` | `baselineSets`, `pairedSlotReference`, `ratingScale`, `applyRatingOnFinalWeek: Bool` (**resolved**, `STAGE3_DECISION_MEMO.md` B3/B4 — `false` for Family B's Thu/Fri rows and Family C's Thu/Fri rows, `true` elsewhere; the two families' Week-4 behaviors are different *shapes*, not the same parameter — see §3.1), `freezeAfterWeek: Int?` (Family C only) | Family A/B/C's `sets = priorSets + pairedRating` |
| `fixedSetSchedule` | `setsByWeek: [Int]` | Family B's non-autoregulated 8RM accessories; Family C's dead-rating-input rows (**resolved** to this rule type rather than a dead `autoregulatedSetCount`, `STAGE3_DECISION_MEMO.md` C3) |
| `repGoalSchedule` | `targetsByWeek: [RepGoal]` (a rep count, an RIR-style "X/fail," or a fixed text like "Triples") | Every family's Week1–4 rep-goal row |
| `deloadWeightBySchedulePosition` | `positions: [ScheduleSlot: Factor]`, `exerciseAction: DeloadExerciseAction` (**new**, see §3.2) | The full-weight/half-weight day-boundary split found in every family |
| `deloadRepInstruction` | `fraction` (e.g. 1/2, 2/3), `roundingDirection` (**resolved**, `STAGE3_DECISION_MEMO.md` A3: always `.down`), `exerciseAction: DeloadExerciseAction` | The always-text, never-computed deload rep rule |
| `linkedResultReference` | `sourceSlotReference`, `fractionOfSourceResult` | Family C's Friday backoff exercise ("1/2 Monday's" actual logged reps) |

### 3.1 Week-4 autoregulation is not one shared shape (resolved)

`STAGE3_DECISION_MEMO.md` B3 and B4 confirmed two families have *different*
Week-4 quirks, not the same one: Family B's Thu/Fri rows drop the rating
addition term entirely (Week 4 = Week 3, computed *without* re-adding a
rating); Family C's Thu/Fri rows freeze the *value* itself (Week 4 copies
Week 3's already-computed number, ignoring any Week-4 rating input even if
one is supplied). Both are reproduced exactly via `autoregulatedSetCount`
parameters (`applyRatingOnFinalWeek` for B, `freezeAfterWeek` for C) —
**an evaluator must not infer one family's Week-4 behavior from the
other's**, per the decision memo's explicit warning.

### 3.2 `DeloadExerciseAction` (resolved, `STAGE3_DECISION_MEMO.md` A2)

```
enum DeloadExerciseAction {
    case standard   // follow this rule's normal deload weight/rep computation
    case omit       // this exercise has no prescription during deload week
}
```

Added to `deloadWeightBySchedulePosition` and `deloadRepInstruction` as an
explicit per-slot parameter, defaulting to `.standard`. Its only confirmed
`.omit` usage today is Family A Mesocycle 2's superset partner exercise
(`PROGRAM_LOGIC_SPEC.md` §2.2) — a blank source cell in that specific,
confirmed case, set explicitly on that prescription's `ProgressionRule`
parameters. **This is deliberately not a generic rule** ("a blank deload
cell always means omit") — no other blank deload cell anywhere in the
source set is interpreted this way unless it has its own confirmed
citation; `DeloadExerciseAction.omit` is set per-slot, from evidence, not
inferred from cell emptiness in general.

Every one of these is a **pure data description** — no code branches on
"which program is this." The `ProgressionEngine` layer adds one evaluator
per rule type; `ProgrammingSystem`s just choose which rules, with which
parameters, go on which `ExercisePrescription`. This is what "the engine
must understand the meaning of the rule, not the spreadsheet coordinates"
(handoff rule 3) means concretely.

`pairedSlotReference` / `sourceSlotReference` need to name a slot
declaratively rather than a literal cell address — this is the
translation step from "M35" to a domain-level reference. **Resolved**
(`STAGE3_DECISION_MEMO.md` A5): this is a **structural, authoring-time
reference** — a stable pointer from one `ExercisePrescription` to
another, set when the `ProgramDefinition` is built and never re-resolved
dynamically. No source file ever resolves a pairing at runtime by
searching training history ("the most recently completed session of this
pattern") — every pairing found in this analysis was fixed by whoever
built the workbook, so the domain model matches that shape rather than
inventing a lookup the source never needed. Movement-pattern and
muscle-group metadata stay on the `Exercise`/`ExerciseCategory` schema for
other explicit uses — substitutions, exercise discovery, the
`ProgramGenerator`, related-exercise performance estimates, analytics —
but are never consulted to *resolve* a `pairedSlotReference` at runtime;
that resolution is always the stored structural pointer. See §5.2 for the
resulting schema addition.

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

### 5.1 Program journeys — phase sequencing is a TrainingOS-level concept (resolved)

`STAGE3_DECISION_MEMO.md` A1 modified the original recommendation: Family
A's three phases (Basic Hypertrophy → Metabolite Focus → Resensitization)
are modeled as a sequential journey, not three unrelated programs. This
section states plainly what is and isn't being claimed by that decision,
because it's easy to misread as "the source proves a sequence" — **it
does not; nothing here changes that fact.**

**What stays exactly as sourced (phase-local):** each phase is still its
own self-contained rule set — its own `rmBasedWeekOneLoad` factor, its own
`fixedMultiplierOfWeekOne` table, its own `autoregulatedSetCount`
baselines and pairings. No `ProgressionRule` reads across phases. No new
rule type computes "next phase's Week-1 load from this phase's Week-4
result" as a spreadsheet formula, because no such formula exists to
represent.

**What is new, and is a TrainingOS product decision, not a source
finding:**

```
ProgramJourney {
    name: String                          // e.g. "RP General Hypertrophy — Full Body"
    phases: [ProgramDefinition]            // ordered; each phase is a normal,
                                            // independently-valid ProgramDefinition
    transitionTrigger: .userInitiated      // V1: the user explicitly starts the next
                                            // phase; no fixed-duration auto-advance
}
```

- `ProgramJourney` is a thin ordering wrapper around ordinary
  `ProgramDefinition`s — it introduces no new rule types and no change to
  how any individual phase computes its own prescriptions.
- **Transitioning to the next phase never invents a cross-phase load
  formula.** The new phase's Week-1 RM is not derived by a spreadsheet-style
  calculation from the prior phase — it comes from either (a) a starting
  recommendation the engine proposes using the user's `PerformanceProfile`
  (their actual logged history on the relevant exercises, already an
  existing Stage 1–2 entity), or (b) a calibration flow (e.g. a
  recommended-RM test) when history is insufficient to propose one
  confidently. Both are ordinary uses of already-existing
  `Recommendation`/`PerformanceProfile` machinery, not a new per-phase
  formula.
- **A phase remains independently usable.** `ProgramDefinition` doesn't
  require a `ProgramJourney` to exist or be instantiated — nothing here
  removes the ability to start "4-Day Full Body Hypertrophy" (Basic
  Hypertrophy only) as a standalone program, exactly as `V1_PROGRAM_LIBRARY.md`
  ships it. `ProgramJourney` is an optional, additional way to present
  several phases as one recommended path.

**Implemented (Stage 3C), separately from sequencing:** a `TrainingPhase`
can compose one primary `ProgramInstance` with zero or more secondary
Modules — `ProgramInstance.priority: GoalPriority` plus
`TrainingPhase.primaryInstance`/`.secondaryInstances`. This is a different
axis from the sequencing discussed above (sequencing is *across* phases,
via `TrainingPlan.orderedPhases`; primary/secondary composition is
*within* one phase) — both were found necessary by Stage 3B's validation,
and only the within-phase one required an actual schema change.

**This sequencing is a TrainingOS product interpretation of the phase
naming and ordering ("Mesocycle 1/2/3" reads as an obvious sequence to a
human), not a claim backed by a spreadsheet formula dependency.** Anyone
extending this model should not add a rule type or persisted field that
would only make sense if the source data proved sequencing — it doesn't,
and this document takes care not to imply otherwise.

### 5.2 Structural slot references (resolved, `STAGE3_DECISION_MEMO.md` A5)

The `pairedSlotReference`/`sourceSlotReference` mechanism from §3 needs a
concrete home in the schema. Resolved as a direct, optional self-reference
on `ExercisePrescription`, set once at `ProgramDefinition` authoring time:

```
ExercisePrescription {
    // ...existing fields from Stage 1–2...
    pairedSlot: ExercisePrescription?   // the slot this prescription's
                                         // ProgressionRule reads from, if any
                                         // (e.g. Front Squat's prescription
                                         // -> pairedSlot = High Bar Squat's
                                         // prescription, within the same
                                         // ProgramDefinition)
}
```

This is a schema addition beyond what Stage 1–2 specified, but it's a
single optional field on an existing entity — not a new entity type, and
not a runtime resolution algorithm. `autoregulatedSetCount` and
`linkedResultReference` rules read `pairedSlot` directly rather than
searching `ProgramInstance` history by movement pattern.

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

### 6.1 Deload strategy: source-compatible vs. TrainingOS-native (resolved, `STAGE3_DECISION_MEMO.md` A4)

Every family's deload behavior (`PROGRAM_LOGIC_SPEC.md` §2.1, §3, §4) is
preserved exactly as sourced — but the decision memo was explicit that
this preservation must **not** be read as "this is what TrainingOS thinks
deload should be." Two conceptual layers, one shared interface, so the
engine isn't duplicated for this distinction:

```
protocol DeloadStrategy {
    func weightFactor(for position: ScheduleSlot) -> Double
    func repInstruction(for position: ScheduleSlot) -> RepFraction
    func exerciseAction(for slot: ExercisePrescription) -> DeloadExerciseAction
}

struct SourceCompatibleDeloadStrategy: DeloadStrategy {
    // one instance per family, parameterized exactly from PROGRAM_LOGIC_SPEC.md:
    // Family A: ceil(dayCount/2)-boundary split, full vs. 0.5x
    // Family B: Mon/Tue 0.7 & "2/3 of Week1", Thu/Fri 0.5 & "1/2 of Week1"
    // Family C: Mon/Tue unchanged & "1/2 of Week1", Wed-Fri 0.5x
    //           (Friday backoff exercise: "Same reps as Week 1")
}

// TrainingOSDeloadStrategy: DeloadStrategy — intentionally NOT defined yet.
// Reserved for ProgramGenerator-authored (non-source-derived) programs.
// What TrainingOS's own deload methodology should be is a separate product
// decision, deferred to when native program generation is actually built
// (PROGRAM_GENERATOR_SPEC.md) — not implied by, or defaulted from, any of
// the three source families' asymmetric patterns above.
```

- Every source-derived `ProgramDefinition` in `V1_PROGRAM_LIBRARY.md`
  (all 8 configurations, since all 8 come from real workbooks) uses
  `SourceCompatibleDeloadStrategy` — this is what
  `PROGRAM_REGRESSION_TEST_PLAN.md`'s deload fixtures validate.
  `ProgramGenerator`-authored programs (Stage 4+, no source workbook
  behind them) would use `TrainingOSDeloadStrategy` once it exists.
- The two-layer split costs one protocol and one additional
  not-yet-implemented conforming type — not a second `ProgrammingSystem`,
  not a second `ProgressionEngine`, and not a fork of any of the rule
  evaluators from §3.

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
  context. The two schema-level ambiguities this used to flag as
  unresolved are now decided: slot-to-slot dependency resolution is §5.2
  above (`STAGE3_DECISION_MEMO.md` A5), and dual-tagged category targets
  are `ExerciseSlot.allowedTargets` (`STAGE3_DECISION_MEMO.md` A6,
  `PROGRAM_GENERATOR_SPEC.md` §4.1). What's still deferred is only
  *which* candidate exercise a generator should default to per slot — a
  product-taste decision, not a schema question.
- Actually implementing any `ProgressionRule` evaluator in
  `Engines/` — that's Stage 4, gated on this document's review.
- Endurance/functional-fitness `ProgrammingSystem`s — no source material
  yet (`PROGRAM_FAMILY_MATRIX.md` §4); only the *interface shape* they'd
  need is worth noting now: they'd need new `ProgressionRule` types (pace
  zones, round/time-based scoring) but the same `ProgrammingSystem` →
  `ProgramDefinition` → `ProgramInstance` skeleton.

## Stage 4A implementation update

`HypertrophyProgrammingSystem` is now built and Xcode-validated — see
`STAGE4_IMPLEMENTATION_REPORT.md` for the full account, and
`ARCHITECTURE.md`'s "Template graph vs. execution graph" section for the
schema this document's `ProgramDefinition -> TrainingWeek ->
ExercisePrescription[] (each carrying a ProgressionRule) ->
SetPrescription[]` diagram resolves to concretely.

Two corrections worth recording here specifically, since they revise this
document's own assumptions rather than just adding new code:

1. **`ProgressionRule` is not one polymorphic type carried directly by a
   persisted entity.** `LoadRule`/`SetCountRule` (this pass's concrete
   rule types) are never stored directly, nor nested inside a wrapping
   struct field — both shapes crashed SwiftData's Codable-enum
   persistence in ways this document had no way to anticipate without a
   compiler. `PrescriptionTemplate` stores a manually flattened tagged
   union instead (a plain discriminator enum + one field per case's
   parameter), with computed properties presenting the same
   `StrengthProgressionRules` bundle to calling code. See
   `STAGE4_IMPLEMENTATION_REPORT.md` §4 for the full diagnostic trail.
2. **This document's diagram implied one `ExercisePrescription`-shaped
   template hangs directly off `TrainingWeek`.** The actual shape is
   `ProgramDefinition -> TemplateSession -> WorkoutBlockTemplate ->
   PrescriptionTemplate -> ExerciseSlot`, attached to `ProgramDefinition`
   directly, not per-`TrainingWeek` — because a `PrescriptionTemplate`'s
   rule *already* carries the whole mesocycle's week-by-week progression
   as arrays, so one recurring weekly structure is correct, not one copy
   per week.

## Stage 4B implementation update

`PowerliftingProgrammingSystem` is now built and Xcode-validated (Family
B "RP Powerlifting Strength" and Family C "RP Powerlifting
Hypertrophy-block") — see `STAGE4_IMPLEMENTATION_REPORT.md`'s "Stage 4B"
section for the full account. No correction to this document's model is
needed: Family B/C are exactly the "one engine + configuration" outcome
this document's own framing anticipated, reusing
`PowerliftingProgramGenerator` over the identical template-graph shape
Stage 4A validated, with only `StrengthProgressionRules`' rule
*parameters* differing per family (line 7's "not built yet" note above
is now stale for Powerlifting specifically; still current for
SteadyState/Interval/FunctionalFitness/ConcurrentScheduler).

## Stage 4C implementation update

`SteadyStateProgrammingSystem` is now built and Xcode-validated (Running/
Cycling/Rowing/SkiErg, one generator/engine for all four) — see
`STAGE4_IMPLEMENTATION_REPORT.md`'s "Stage 4C" section for the full
account, and `ARCHITECTURE.md`'s "Steady-state template graph" section
for the schema. No correction to this document's model is needed: one
`ProgrammingSystem` + `ProgramConfiguration` + `ActivityType`, exactly the
outcome this document's own framing anticipated (line 7's "not built yet"
note is now stale for SteadyState specifically; still current for
Interval/FunctionalFitness/ConcurrentScheduler).

Stage 4C also builds the substitution foundation (Part B of its
kickoff) — a domain/programming requirement this document's model always
implied (a `ProgramInstance` executes a `ProgramDefinition`'s methodology
with user-specific state layered on top) but never made explicit before
now. See `SUBSTITUTION_MODEL.md` for the full contract: template slot ->
instance selection -> materialized prescription -> actual performance ->
permanent profile, with `ProgramDefinition` remaining immutable
throughout.
