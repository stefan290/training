# Program Generator Spec

Specification only — no generation algorithm is implemented in this pass.
This defines the shape a `ProgramGenerator` will have, once built, so that
Stage 4 has an agreed target rather than an open design question.

## 1. Purpose

Turn a small set of user-facing inputs into one concrete, structured
`ProgramDefinition` (per `PROGRAMMING_SYSTEM_MODEL.md`) — without the user
ever seeing a spreadsheet, an RM percentage, or a `ProgressionRule`.

## 2. Inputs

Matches the Stage 3A brief's example exactly, reconciled against the
already-locked planning model from the Stage 1 handoff (`Availability` is
training days/week + time/day + doubles + occasional-long-session, not a
raw session count — the planner derives session count, not the user):

```
GeneratorInput {
    goal: GoalType                       // e.g. .muscleGain, .strength
    availability: Availability            // existing entity: trainingDaysPerWeek,
                                          // minutesPerTrainingDay, allowsDoubleSessions,
                                          // allowsOccasionalLongSession
    experienceLevel: ExperienceLevel      // informs coaching copy today; see note below
    musclePriorities: [MuscleGroup]?      // optional specialization, e.g. [.chest, .shoulders, .back]
    equipmentContext: EquipmentContext    // e.g. .commercialGym, .homeGymBarbellOnly, .minimalDumbbellsOnly
}
```

**`experienceLevel` note:** per `PROGRAM_FAMILY_MATRIX.md` §2, the source
material does not support a distinct novice *ruleset*. `experienceLevel` is
retained as an input because it plausibly affects *other* generator
decisions this pass doesn't resolve (recommended starting day-count,
coaching copy, calibration emphasis) — it must **not** be wired to a
`ProgrammingSystem` parameter that doesn't exist. If Stage 4 finds no real
use for it beyond copy/day-count defaults, say so rather than inventing a
use.

## 3. Generation hierarchy

```
GeneratorInput
     |
     v
1. Select ProgrammingSystem
     goal -> {muscleGain, generalStrength -> Hypertrophy or Powerlifting family;
              other goals -> out of scope, see §5}
     |
     v
2. Derive structural parameters from availability
     trainingDaysPerWeek -> dayCount (bounded to what the chosen system supports:
        Hypertrophy family supports 3-6; Powerlifting family supports 4-5,
        per the source material's own stated limits)
     musclePriorities -> split selection (full_body if unspecified/broad;
        a specialization split if priorities are narrow, e.g. chest+shoulders
        -> arms_shoulders-style split)
     |
     v
3. Instantiate ProgramDefinition
     - weeks: TrainingWeek[] per the chosen system's phase/duration rules
       (e.g. Hypertrophy's phase set, Powerlifting's 4-week + deload block)
     - each week's sessions -> WorkoutBlock -> ExercisePrescription slots,
       each slot carrying its ProgressionRule(s) from PROGRAMMING_SYSTEM_MODEL.md §3
     - exercise SLOTS populated per §4 below — not yet resolved to a specific
       Exercise until slot resolution runs
     |
     v
4. Resolve exercise slots (see §4) -> concrete canonical Exercise per slot
     |
     v
Output: one STRICT-adherence ProgramDefinition, ready for a ProgramInstance
```

This hierarchy deliberately stops at "ready for a `ProgramInstance`" — it
does not decide *when* sessions get materialized into `Day`/`Session`
rows; that's the existing `materialiseTacticalWeeks` planning-engine
contract from the Stage 1 handoff, unchanged by this document.

## 4. Exercise-slot architecture

Confirmed directly from the source material: RP's own templates already
work this way. No workbook hardcodes "Barbell Bench Press" as the only
option for a session slot — every slot is a *category* (e.g. "Incline
Push," "Quads," "Push Move 1") with a bounded candidate list presented as
a dropdown, plus an "Other ___ move of choice" escape hatch for manual
entry (`PROGRAM_LOGIC_SPEC.md` §2, §3, §4). TrainingOS should model this
directly rather than re-derive it:

```
ExerciseSlot {
    category: ExerciseCategory        // e.g. "Incline Push", "Quads", "Push Move 1"
    allowedTargets: [MuscleGroup]     // resolved, STAGE3_DECISION_MEMO.md A6 — one
                                       // entry for an ordinary slot, two for a
                                       // dual-tagged slot (§4.1); never collapsed
                                       // to a single MuscleGroup before resolution
    candidates: [Exercise]            // canonical exercises tagged for this category
    allowsCustomEntry: Bool           // the "Other ___" escape hatch
    resolvedExercise: Exercise?       // set once the slot is resolved (§4.1)
    resolvedTarget: MuscleGroup?      // set alongside resolvedExercise — which
                                       // member of allowedTargets this specific
                                       // exercise choice actually satisfies
}
```

**Slot resolution (`§4` in the brief's own terms) happens once per
`ProgramDefinition` instantiation**, not once per source import — the
generator picks (or the user picks, or a future recommendation engine
picks) one candidate per slot. `ProgrammingSystem` logic (which categories
exist, what rules attach to them) stays entirely separate from the
Exercise Library (which concrete exercises exist and which categories they
belong to) — the same separation the source material itself already
enforces via its dropdown-list-plus-category design.

### 4.1 Canonical exercise identity

Reuses the import-pipeline pattern already specified in the Stage 1
handoff (source name → candidate canonical exercise → confidence → user
confirmation when uncertain), applied here to two concrete situations
found in the source data:

- **RP's own dropdown lists are already close to canonical** — e.g. the
  Powerlifting family's Legs category candidates (`Low Bar Squat`, `High
  Bar Squat`, `Front Squat`, `Pause Squat`, `Squat to Pins`) are distinct
  real exercises, not spelling variants of one exercise, and should map
  1:1 to canonical `Exercise` rows with high confidence.
- **The "Other ___ move of choice" free-text path** is exactly the
  low-confidence case the existing pipeline is for: free text needs full
  resolution (alias table → normalized string match → movement-pattern
  heuristic → user confirmation if still uncertain), because it's
  unconstrained user input, not a picklist value.

**Dual-tagged categories — resolved (`STAGE3_DECISION_MEMO.md` A6):** the
Hypertrophy family's dual-tagged categories (e.g. "Chest Isolation or
Triceps," "Rear or Side Delts" — `PROGRAM_LOGIC_SPEC.md` §2.1) let the
*same slot* resolve to either of two different target muscles depending on
user choice. The product decision was explicit: **do not** avoid this by
hardcoding one exercise per slot to sidestep the schema question, and
**do not** invent a special-case entity for it either. `ExerciseSlot`
carries `allowedTargets: [MuscleGroup]` (§4 above) — one `ExerciseCategory`
with a real list of valid targets, not a forced single value, and not two
categories artificially split apart. Selecting a concrete `Exercise` for
the slot resolves `resolvedTarget` from whichever of `allowedTargets` that
exercise actually satisfies — the *slot* keeps recording that it allowed
either, even after one is chosen, so the original program intent (this
slot was always meant to be flexible) survives resolution rather than
being discarded. **V1's shipped configurations may still default or
recommend one specific exercise per dual-tagged slot for convenience**
(`V1_PROGRAM_LIBRARY.md` configuration #4, "5-Day Upper/Arms Focus" —
exercises this exact case) — that's a UI/generator convenience, not a
narrowing of what the domain model actually represents.

## 5. Explicit non-goals for this document

- **No automatic candidate-picking algorithm.** Which specific exercise a
  generator should default to per slot (vs. leaving it to the user) is a
  Stage 4+ decision informed by product taste, not something the source
  spreadsheets specify (they always leave the pick to the human).
- **No interference/scheduling logic.** How a generated `ProgramDefinition`
  gets laid onto a calendar alongside modules or other phases is the
  existing planning-engine's job (`proposePlan`, `fitCapacity`, etc.),
  untouched by this spec.
- **No endurance/functional-fitness generation.** No source material to
  derive slot categories or rules from yet (`PROGRAM_FAMILY_MATRIX.md` §4).
- **Not implemented.** This is the target shape for Stage 4, gated on
  product-owner review of this whole document set.
