# Substitution Model

Stage 4C's Part B deliverable: exercise/activity substitution is a
domain/programming requirement, not a future UI feature. This document is
the contract for how it works — read it before touching
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
