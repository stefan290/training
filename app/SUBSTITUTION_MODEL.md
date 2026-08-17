# Substitution Model

**Stage 6A status: RESOLVED.** `STRENGTH_EXECUTION_FLOW.md` §7 and
`ENDURANCE_EXECUTION_FLOW.md` §3 design the execution-side UI for the
two scopes below (Today only / Going forward) — a design pass only,
nothing implemented yet. No change to this document's own contract was
needed: `SubstituteExerciseUseCase`/`SubstituteActivityUseCase`,
`SubstitutionValidator`, `SlotSelectionOverride`/`ActivitySelectionOverride`
are reused exactly as specified here, now invoked through the resolved
`ApplySubstitutionUseCase` orchestration layer that saves immediately
per substitution (`WORKOUT_COMPLETION_PIPELINE.md` §1). The one
remaining open item is non-blocking, build-time-only:
`IntensityTranslation`'s exact activity-pair coverage, to be confirmed
against every substitution the endurance execution UI actually offers
(`STAGE6A_DECISION_MEMO.md` §5).

**Stage 6D confirmation:** manual Simulator testing reported Change
Exercise as "unavailable because history is required." Audited the real
`ChangeExerciseView`/`SubstitutionCandidateRanking` code: no path there
ever blocks a substitution on missing history — `.calibrationRequired`
was always a fully selectable tier, exactly as this document specifies.
The observed failure was a seed-data completeness gap (4 of 5 Stage 6C
acceptance-fixture slots had only one `allowedExercises` entry each, so
"No valid alternatives" showed instead), fixed by giving every slot a
real second exercise in `SeedScenarios.swift`/`ExerciseCatalog.swift` —
no change to the substitution architecture itself. See
`STAGE6D_ACCEPTANCE_REPORT.md` §6.

Stage 4C's Part B deliverable: exercise/activity substitution is a
domain/programming requirement, not a future UI feature. Stage 4D
extended the activity-substitution half to cover `IntervalPrescriptionTemplate`
alongside `SteadyStatePrescriptionTemplate`, correcting
`ActivitySelectionOverride`'s key in the process (§3 below). Stage 4E
extended the *exercise*-substitution half to cover Functional Fitness
movement slots, with zero new mechanism (§7 below). This document is the
contract for how it works — read it before touching
`SlotSelectionOverride`, `ActivitySelectionOverride`,
`SubstituteExerciseUseCase`, or `SubstituteActivityUseCase`.

## 1. The three concepts that must never collapse into one

| Concept | Where it lives | Example |
|---|---|---|
| **Original Prescription** | `PrescriptionTemplate`/`ExerciseSlot` (methodology) | Slot "Horizontal Push," 3×8-12 @ 2 RIR, `allowedTargets: [.chest, .shoulders]` |
| **User Selection** | `ExerciseSlot.resolvedExercise` (template default) or `SlotSelectionOverride.selectedExercise` (instance override) | Barbell Bench Press (default), or Dumbbell Bench Press (this user's override) |
| **Actual Performance** | `ExercisePrescription`/`SetResult`/`ExercisePerformanceProfile` | Dumbbell Bench Press, 32.5 kg × 10, logged against Dumbbell Bench Press's own permanent history |

All three must remain independently recoverable at all times (§16). The
rest of this document is about how each layer resolves the next without
ever merging them.

## 2. The five-stage pipeline

```
Template Slot (ExerciseSlot / SteadyStatePrescriptionTemplate)
     |  default selection: slot.resolvedExercise / template.preferredActivityType
     v
ProgramInstance Selection (SlotSelectionOverride / ActivitySelectionOverride, optional)
     |  GOING FORWARD override, resolved at materialization time
     v
Materialized Prescription (ExercisePrescription / SteadyStatePrescription)
     |  THIS SESSION ONLY substitution edits this row directly, after the fact
     v
Actual Performance (SetResult / SteadyStateResult, logged by the user)
     |
     v
PerformanceProfile (ExercisePerformanceProfile / ActivityPerformanceProfile)
     — permanent, keyed to the canonical Exercise/ActivityType actually performed,
       never to the slot, the template, or any ProgramInstance.
```

Each arrow is a **resolution**, not a **mutation**: resolving a slot's
exercise never writes back into the template graph, and logging a result
never rewrites the prescription it was logged against.

## 3. THIS SESSION ONLY vs. GOING FORWARD

These are not two modes of one entity — they are two different
mechanisms attached to two different aggregate roots, chosen because that
is the cleanest fit once the actual template graph was inspected (per
Stage 4C's own instruction to prefer the smallest clean addition over the
kickoff's suggested schema):

- **THIS SESSION ONLY** edits an *already-materialized* row directly:
  `ExercisePrescription.exercise`/`.substitutionUsed`/`.substitutionReason`
  (strength) or `SteadyStatePrescription.activityType`/`.substitutionUsed`/
  `.substitutionReason` (endurance). No new persisted type at all — this
  is exactly the shape Stage 3C's `FunctionalFitnessPerformedMovement.performedExercise`
  already uses for "performed something other than prescribed, without
  touching the prescription." Nothing else is affected: not the next
  Session, not the `ProgramInstance`, not the template.
- **GOING FORWARD** writes to a `ProgramInstance`-scoped override —
  `SlotSelectionOverride` (strength, points at an `ExerciseSlot`) or
  `ActivitySelectionOverride` (endurance, points at a
  `SteadyStatePrescriptionTemplate`) — consulted by the materializer the
  next time it builds a *not-yet-materialized* Session for that slot.
  `SubstituteExerciseUseCase.resolvedExercise(for:in:)`/
  `SubstituteActivityUseCase.resolvedActivityType(for:in:)` are the only
  functions a materializer should ever call instead of reading
  `slot.resolvedExercise`/`template.preferredActivityType` directly.

**Stage 4D addition:** `IntervalPrescriptionTemplate` needed the exact
same GOING FORWARD mechanism as `SteadyStatePrescriptionTemplate`. Rather
than add a second, duplicate `ActivitySelectionOverride`-like entity for
intervals, `ActivitySelectionOverride` was **re-keyed to the owning
`WorkoutBlockTemplate`** (`templateBlock: WorkoutBlockTemplate?`, was
`templateSteadyState: SteadyStatePrescriptionTemplate?`) — the one object
both endurance template types already hang off of. A small
`ActivitySubstitutionTemplate` protocol
(`preferredActivityType`/`allowedActivityTypes`) lets
`SubstituteActivityUseCase` stay generic over whichever endurance
template a given block carries
(`WorkoutBlockTemplate.activitySubstitutionTemplate`). THIS SESSION ONLY
for intervals follows the identical strategy as steady-state — a direct
edit of `IntervalPrescription.activityType`/`.substitutionUsed`/
`.substitutionReason` (fields added this stage, mirroring
`SteadyStatePrescription`'s Stage 4C ones), with `IntensityTranslation`
applied to `workIntensity`/`recoveryIntensity` instead of
`primaryIntensity`/`secondaryIntensity`.

**Why two entities instead of one with a `scope` field:** the kickoff's
own sketch (`templateSlotID, selectedExerciseID, scope, reason,
timestamp`) was deliberately not used as-is. A "this session only" scope
value would need to reference a specific `Session`/`ExercisePrescription`
that already exists, while a "going forward" scope value references no
Session at all (it's read at future-materialization time, before any
Session exists). Modeling both in one entity would mean a nullable
dual-purpose row — the "nullable mega-entity" smell Stage 4C's own review
checklist names. Two small, single-purpose types (and, for THIS SESSION
ONLY, no new type at all) is the smaller, cleaner surface.

**Extensibility to a future `THIS_PHASE` scope:** would be a third
mechanism attached to `TrainingPhase` rather than `ProgramInstance` —
additive, following the same pattern (a small override type or reused
field, consulted at materialization time), not a redesign of the two
above. Not built in Stage 4C; not needed until a real product requirement
asks for it.

## 4. Invariants this model enforces

1. **`ProgramDefinition`/the template graph is never mutated by a user
   substitution** (§20/§43). `ExerciseSlot.resolvedExercise`,
   `SteadyStatePrescriptionTemplate.preferredActivityType`, and every
   `PrescriptionTemplate`/`SteadyStatePrescriptionTemplate` rule stay
   exactly as the generator produced them, for every `ProgramInstance`
   built from that definition, forever. Proven directly:
   `SubstitutionTests.testGoingForwardSubstitutionAffectsOnlyFutureMaterializationNeverAlreadyMaterializedSessions`
   asserts `slot.resolvedExercise` is unchanged after a substitution.
2. **A completed/already-materialized Session is never retroactively
   rewritten** (§30/§42). `StrengthMaterializer`/`SteadyStateMaterializer`
   only resolve the current override at the moment they build a new
   Session; they never revisit rows they already created.
3. **An override never leaks to a different `ProgramInstance`** (§32),
   including a fresh instance of the *same* `ProgramDefinition`/slot —
   `SlotSelectionOverride`/`ActivitySelectionOverride` are keyed to one
   specific instance, full stop.
4. **Exactly one override row per `(instance, slot)` pair** (§41) —
   `SubstituteExerciseUseCase.substituteGoingForward`/
   `SubstituteActivityUseCase.substituteGoingForward` update the existing
   row in place rather than appending a new one, so there is never more
   than one place a materializer needs to check.
5. **A substitute exercise never inherits the original's performance
   history** (§23/§24). `ExercisePerformanceProfile` is keyed to the
   canonical `Exercise` actually performed — switching exercises means
   consulting (or creating) a different, independent profile, never
   copying a PR or renaming a profile. Switching back later recovers the
   original profile exactly as it was (§31), since it was never touched.
6. **Substitution validity is deterministic, never invented** (§27).
   `SubstitutionValidator.isValid`/`SubstituteActivityUseCase.isValid`
   check only `ExerciseSlot.allowedExercises`/`.allowedTargets` (via the
   new `Exercise.primaryTargets` field this stage adds) or
   `SteadyStatePrescriptionTemplate.allowedActivityTypes` — never a
   string/name heuristic, never "shares a muscle" without going through
   the slot's own declared constraint.
7. **A recommendation after substitution is honest about its source**
   (§25/§29/§44) — `SubstitutionAwareRecommendation` escalates: the
   selected exercise's own history, if usable; else a related exercise's
   history (via `ExerciseRelationshipResolver`) at an explicitly
   discounted confidence (`ProgressionReasonCode.substitutionEstimate`);
   else `CALIBRATION_REQUIRED`, never an invented number.
8. **Intensity does not silently transfer across an activity
   substitution** (§37). `IntensityTranslation` keeps a physiological
   target (HR zone/percent, RPE) but drops an equipment-specific one
   (pace, power, cadence, stroke rate) to `nil` when the activity
   actually changes — the intended stimulus (e.g. "Zone 2") survives; the
   specific number does not pretend to.
9. **A running-specific (or any activity-locked) prescription rejects an
   invalid substitute** (§35/§38) — `SteadyStatePrescriptionTemplate.allowedActivityTypes`
   is never empty; a template with no substitution permitted sets it to
   exactly `[preferredActivityType]`.
10. **Functional Fitness scaling remains its own, already-correct
    mechanism** (§38-39/§53) — `FunctionalFitnessPerformedMovement.prescribedMovement`/
    `.performedExercise` already separates prescribed-vs-performed for
    Toes-to-Bar/Knee Raises-style scaling; Stage 4C adds no new code
    here, only a confirming test
    (`SubstitutionTests.testFunctionalFitnessScalingPreservesThePrescribedMovementSeparatelyFromWhatWasPerformed`).
    Whether a given real-world case is "scaling" or "substitution" is a
    UI/product framing choice layered on top of the same underlying
    prescribed-vs-performed mechanism, not two different domain models.

## 5. Reason-code vocabularies (deliberately two, not one)

- **`SubstitutionReason`** (new, this stage) answers *why the user chose
  something else*: `userExerciseSubstitution`, `exerciseUnavailable`,
  `equipmentUnavailable`, `userPreference`. Always optional — the user is
  never required to supply one.
- **`ProgressionReasonCode`** (existing since Stage 1-2, reused rather
  than duplicated) answers *how the recommended number was derived*:
  `.calibrationRequired` and `.substitutionEstimate` were declared back
  in Stage 1-2 as "intentionally unreachable... until a later pass" — this
  is that pass. Conflating the two vocabularies into one enum would mean
  either re-deriving `.calibrationRequired`'s meaning under a new name (a
  duplicate-truth smell) or overloading one enum with two unrelated
  questions.

## 6. What Stage 4C does not claim

- A full substitution UI (§45) — explicitly out of scope; this document
  and the domain/application logic behind it exist so that UI can be
  built correctly later.
- `THIS_PHASE` scope (§19) — designed for, not implemented.
- A curated `ExerciseRelationship` seed set — the type and resolver exist
  and are tested; populating it with real curated rows (beyond what tests
  construct) is a content task, not an architecture task.
- A biomechanical cross-exercise/cross-modality translation model (§25/§37)
  — the "related exercise" confidence discount and the intensity-target
  drop-to-`nil` behavior are both deliberately simple, clearly-labeled
  placeholders, not a physiology model.

## 7. Functional Fitness movement-slot substitution (Stage 4E)

Functional Fitness movement slots (e.g. "moderate-loaded squat/push,"
"gymnastics pull") are **not** a new substitution system — they're
`ExerciseSlot` rows, exactly like a strength slot, owned by a new parent
type (`FunctionalFitnessMovementSlotTemplate`) instead of
`PrescriptionTemplate`. `ExerciseSlot` gained two new constraint
dimensions to make this possible:

- `allowedMovementFunctions: [MovementFunction]` — the movement-pattern
  equivalent of `allowedTargets: [MuscleGroup]`.
- `allowedModalities: [FunctionalModality]` — which broad category
  (metabolic conditioning / gymnastics / weightlifting) a candidate must
  belong to.

`SubstitutionValidator.isValid` checks all three dimensions together
(AND across dimensions, OR within one dimension's own array;
`allowedExercises`, when set, still short-circuits everything else,
unchanged since Stage 4C) — a strength slot that never sets the two new
fields is completely unaffected, since an empty array imposes no
constraint.

Because substitution is validated and overridden through the exact same
`ExerciseSlot`/`SlotSelectionOverride`/`SubstituteExerciseUseCase`
machinery, THIS SESSION ONLY and GOING FORWARD both work for a
Functional Fitness movement slot with no new code beyond the two new
`ExerciseSlot` fields and the `SubstitutionValidator` generalization —
proven end-to-end by
`FunctionalFitnessSubstitutionAndBenchmarkTests.testGoingForwardMovementSlotSubstitutionNeverMutatesProgramDefinitionAndHistoricalSessionStaysStable`.
`Exercise` gained matching typed metadata (`movementFunctions:
[MovementFunction]`, `functionalModality: FunctionalModality?`) so a
candidate can actually be checked against these new dimensions, closing
the same "canonical Exercise metadata, never parsed names" gap
`primaryTargets` closed for strength substitution in Stage 4C.

## Stage 6B: live execution's Change Exercise / Change Activity

Building the actual Change Exercise (Strength) and Change Activity
(Steady State/Interval) screens surfaced one real gap: every prior
substitution test/call site had the `ExerciseSlot`/`WorkoutBlockTemplate`
in hand already (a materializer, or a test that just built one). Live
execution starts from an already-materialized `ExercisePrescription`/
`SteadyStatePrescription`/`IntervalPrescription` with no stored path back
to it — `SubstituteExerciseUseCase`/`SubstituteActivityUseCase` both
require it as a parameter. Closed additively (`DELETE_RULE_MATRIX.md`'s
own Stage 6B section): `ExercisePrescription.sourceExerciseSlot`/
`SteadyStatePrescription.sourceWorkoutBlockTemplate`/
`IntervalPrescription.sourceWorkoutBlockTemplate`, populated by
`StrengthMaterializer`/`SteadyStateMaterializer`/`IntervalMaterializer` at
the exact line each prescription is created. `nil` for anything
materialized outside that path — Change Exercise/Change Activity
correctly stay unavailable rather than validating against nothing.

**Ranking candidates** (Change Exercise only — Change Activity's pool is
just `template.allowedActivityTypes`, small enough to list unranked):
`SubstitutionCandidateRanking` filters via the existing
`SubstitutionValidator.isValid`, then tiers each eligible candidate by
re-running the existing `SubstitutionAwareRecommendation.resolve` with
that candidate as the "selected exercise" — no new scoring engine, reusing
exactly the tiering Stage 4C already built for the load-estimate flow.
Ties break alphabetically by `canonicalName` for determinism. Both
scopes route through the already-built `ApplySubstitutionUseCase` — no
new persistence code, only the new slot/template trace-back and the
ranking view.

## Stage 6C: real slot-materialized substitution, proven end-to-end

The Stage 6B acceptance Session had never actually been materialized
through a slot (it was a hand-assembled `ExercisePrescription`), so
Change Exercise's "unavailable" message — while technically correct —
had never been proven against a *real* alternative either. The Stage 6C
acceptance fixture (`SeedScenarios.materializedLowerASession`) includes
one slot with two genuine `allowedExercises` (Leg Press/Bulgarian Split
Squat, resolved by default to Leg Press), materialized with
`sourceExerciseSlot` set exactly as `StrengthMaterializer` does it. This
proves, with real data instead of a synthetic fixture:

- `SubstitutionCandidateRanking.rank` surfaces the real alternative for a
  real slot-materialized movement.
- **THIS SESSION ONLY** edits only the intended `ExercisePrescription` —
  every other movement in the same block is untouched, and the slot's
  own `resolvedExercise` (the template default) is never mutated.
- **GOING FORWARD** writes a real `SlotSelectionOverride` for
  `(instance, slot)`; `SubstituteExerciseUseCase.resolvedExercise`
  correctly prefers it over the template default, while the template
  default itself and the already-materialized prescription stay exactly
  as they were — an override only ever governs *future* materialization.

No new substitution mechanism was needed — `MultiExerciseExecutionTests`'
`M`/`N`/`O`/`P` tests exercise the existing Stage 4C architecture
directly against this realistic fixture.
